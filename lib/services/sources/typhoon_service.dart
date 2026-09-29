import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/typhoon_data.dart';
import 'jian_get_rate_limit.dart';
import 'web_source_proxy.dart';

class TyphoonService {
  static const String _baseUrl = 'https://typhoon.slt.zj.gov.cn/Api/';
  static const Duration _timeout = Duration(seconds: 14);
  static const Duration _cacheMaxAge = Duration(hours: 1);
  static const Duration fallbackRefreshInterval = Duration(minutes: 5);
  static const Duration retryInterval = Duration(seconds: 30);
  static const String _cacheKey = 'typhoon_zj_active_cache_v1';

  final http.Client? _client;
  final DateTime Function() _now;
  Timer? _timer;
  bool _running = false;
  int _generation = 0;
  int? _fetchingGeneration;
  int _revision = 0;
  Duration _interval = fallbackRefreshInterval;
  String _lastSignature = '';
  List<TyphoonData> _lastTyphoons = const [];

  TyphoonService({http.Client? client, DateTime Function()? now})
    : _client = client,
      _now = now ?? DateTime.now;

  void Function(List<TyphoonData> typhoons)? onActiveTyphoonsChanged;

  bool get isRunning => _running;

  void start({Duration interval = fallbackRefreshInterval}) {
    stop();
    _running = true;
    _interval = interval;
    unawaited(_start(_generation));
  }

  Future<void> _start(int generation) async {
    await _emitCachedActive(generation, _revision);
    if (generation == _generation) await fetchNow();
  }

  void stop({bool clearState = false}) {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (clearState) {
      _lastSignature = '';
      _lastTyphoons = const [];
    }
  }

  Future<void> fetchNow() async {
    final generation = _generation;
    if (_fetchingGeneration == generation) return;
    _fetchingGeneration = generation;
    _timer?.cancel();
    var complete = false;
    try {
      final result = await _fetchWithFallback(_lastTyphoons);
      if (generation != _generation) return;
      complete = result.complete;
      _revision++;
      ingestExternal(result.typhoons);
      await _saveActiveCache(result, generation);
    } catch (_) {
      // A failed activity request is not an empty activity list.
    } finally {
      if (_fetchingGeneration == generation) _fetchingGeneration = null;
      if (generation == _generation && _running) {
        _timer = Timer(complete ? _interval : retryInterval, fetchNow);
      }
    }
  }

  Future<List<TyphoonData>> fetchActiveNow() async {
    final result = await _fetchWithFallback(const []);
    if (!result.complete) {
      throw const FormatException('Incomplete typhoon data');
    }
    return result.typhoons;
  }

  Future<List<TyphoonData>> fetchById(String tfid) async {
    final id = tfid.trim();
    if (id.isEmpty) return const [];
    final raw = await _getJson('TyphoonInfo/${Uri.encodeComponent(id)}');
    return [_parseDetail(raw, id)];
  }

  /// Accept a snapshot already fetched by the Android foreground service.
  void ingestExternal(List<TyphoonData> typhoons) {
    final next = List<TyphoonData>.unmodifiable(typhoons);
    final signature = next.map((item) => item.signature).join('||');
    if (signature == _lastSignature && next.length == _lastTyphoons.length) {
      return;
    }
    _lastSignature = signature;
    _lastTyphoons = next;
    onActiveTyphoonsChanged?.call(next);
  }

  Future<_TyphoonSnapshot> _fetchSnapshot(List<TyphoonData> previous) async {
    final activity = await _getJson('TyhoonActivity');
    if (activity is! List) {
      throw const FormatException('Invalid typhoon activity list');
    }
    final ids = <String>{};
    for (final entry in activity) {
      final id = entry is Map ? entry['tfid']?.toString().trim() : null;
      if (id == null || !RegExp(r'^\d{6}$').hasMatch(id)) {
        throw const FormatException('Invalid active typhoon ID');
      }
      ids.add(id);
    }
    final sortedIds = ids.toList()..sort();
    final old = {for (final item in previous) item.tfid: item};
    final rawDetails = <dynamic>[];
    var complete = true;
    final items = <TyphoonData>[];
    for (final id in sortedIds) {
      try {
        final raw = await _getJson('TyphoonInfo/$id');
        final detail = _parseDetail(raw, id);
        if (detail.isActive) {
          items.add(detail);
          rawDetails.add(raw);
        }
      } catch (_) {
        complete = false;
        final retained = old[id];
        if (retained != null && retained.isActive) items.add(retained);
      }
    }
    return _TyphoonSnapshot(items, rawDetails, complete, activeIds: sortedIds);
  }

  Future<_TyphoonSnapshot> _fetchWithFallback(
    List<TyphoonData> previous,
  ) async {
    _TyphoonSnapshot? primary;
    try {
      primary = await _fetchSnapshot(previous);
      if (primary.complete) return primary;
    } catch (_) {
      // The activity endpoint itself may be unavailable.
    }
    try {
      final fallback = await _fetchJianSnapshot();
      if (primary == null) {
        if (fallback.typhoons.isEmpty && previous.isNotEmpty) {
          return _TyphoonSnapshot(previous, const [], false, fromJian: true);
        }
        return fallback;
      }
      if (fallback.typhoons.isEmpty) return primary;
      final activeIds = primary.activeIds.toSet();
      final backupById = {
        for (final item in fallback.typhoons)
          if (activeIds.contains(item.tfid)) item.tfid: item,
      };
      if (backupById.isEmpty) return primary;
      final merged = <TyphoonData>[
        ...backupById.values,
        for (final item in primary.typhoons)
          if (!backupById.containsKey(item.tfid)) item,
      ]..sort((a, b) => a.tfid.compareTo(b.tfid));
      final primaryDetailIds = {
        for (final raw in primary.rawDetails)
          if (raw is Map && raw['tfid'] is String) raw['tfid'] as String,
      };
      final complete = activeIds.every(
        (id) => backupById.containsKey(id) || primaryDetailIds.contains(id),
      );
      return _TyphoonSnapshot(merged, const [], complete, fromJian: true);
    } catch (_) {
      if (primary != null) return primary;
      rethrow;
    }
  }

  Future<_TyphoonSnapshot> _fetchJianSnapshot() async {
    final uri = Uri.https('api.sismotide.top', '/get/typhoon.php');
    final response = await (_client == null
        ? JianGetRateLimit.run(() => http.get(uri).timeout(_timeout))
        : _client.get(uri).timeout(_timeout));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Jian typhoon HTTP ${response.statusCode}',
        uri,
      );
    }
    final items = parseJianTyphoons(
      jsonDecode(utf8.decode(response.bodyBytes)),
    );
    return _TyphoonSnapshot(items, const [], true, fromJian: true);
  }

  static List<TyphoonData> parseJianTyphoons(dynamic raw) {
    if (raw is! List) {
      throw const FormatException('Invalid Jian typhoon list');
    }
    final ids = <String>{};
    final items = <TyphoonData>[];
    for (final entry in raw) {
      if (entry is! Map) {
        throw const FormatException('Invalid Jian typhoon entry');
      }
      final id = entry['id'];
      if (id is! String || !RegExp(r'^\d{6}$').hasMatch(id) || !ids.add(id)) {
        throw const FormatException('Invalid Jian typhoon ID');
      }
      final points = <TyphoonPoint>[];
      final rawPoints = entry['points'];
      if (rawPoints != null && rawPoints is! List) {
        throw const FormatException('Invalid Jian typhoon track');
      }
      for (final rawPoint in rawPoints ?? const []) {
        if (rawPoint is! Map) {
          throw const FormatException('Invalid Jian typhoon track point');
        }
        final point = TyphoonPoint.fromJson({
          ...rawPoint,
          'lat': rawPoint['lat'] ?? rawPoint['latitude'],
          'lng': rawPoint['lng'] ?? rawPoint['longitude'],
          'time': rawPoint['time'] ?? rawPoint['updateTime'],
        });
        if (point == null ||
            !point.hasLocation ||
            DateTime.tryParse(point.time) == null) {
          continue;
        }
        points.add(point);
      }
      final current = TyphoonPoint.fromJson({
        'time': entry['updateTime'],
        'lat': entry['latitude'],
        'lng': entry['longitude'],
        'strong': entry['type'],
        'power': entry['power'],
        'speed': entry['windSpeed'],
        'pressure': entry['pressure'],
        'movespeed': entry['moveSpeed'],
        'movedirection': entry['moveDirection'],
        'radius7': entry['radius7'],
        'radius10': entry['radius10'],
      });
      if (current != null &&
          current.hasLocation &&
          DateTime.tryParse(current.time) != null &&
          (points.isEmpty ||
              points.last.time != current.time ||
              points.last.lat != current.lat ||
              points.last.lng != current.lng)) {
        points.add(current);
      }
      if (points.isEmpty) {
        throw const FormatException('Jian typhoon has no located track point');
      }
      items.add(
        TyphoonData(
          tfid: id,
          name: entry['name'] is String ? entry['name'] as String : '',
          enname: entry['name_en'] is String ? entry['name_en'] as String : '',
          isActive: true,
          startTime: '',
          endTime: '',
          warnLevel: '',
          centerLng: points.last.lng,
          centerLat: points.last.lat,
          land: const [],
          points: List.unmodifiable(points),
          ckposition: '',
          jl: '',
        ),
      );
    }
    return items;
  }

  static TyphoonData _parseDetail(dynamic raw, String id) {
    if (raw is! Map || raw['tfid']?.toString() != id) {
      throw const FormatException('Mismatched typhoon detail');
    }
    final active = raw['isactive']?.toString();
    final points = raw['points'];
    if ((active != '0' && active != '1') || points is! List || points.isEmpty) {
      throw const FormatException('Invalid typhoon detail');
    }
    final result = TyphoonData.fromMap(raw)!;
    if (result.points.length != points.length ||
        result.points.any(
          (point) => !point.hasLocation || point.time.isEmpty,
        )) {
      throw const FormatException('Invalid typhoon track');
    }
    return result;
  }

  Future<dynamic> _getJson(String path) async {
    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: {'time': '${_now().millisecondsSinceEpoch}'});
    const headers = {
      'Accept': 'application/json',
      'User-Agent': 'RhythmQuake/typhoon-layer',
    };
    final response =
        await (_client == null
                ? http.get(sourceUri(uri), headers: sourceHeaders(headers))
                : _client.get(sourceUri(uri), headers: sourceHeaders(headers)))
            .timeout(_timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('Typhoon HTTP ${response.statusCode}', uri);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> _emitCachedActive(int generation, int revision) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(_cacheKey);
      if (body == null) return;
      final cached = jsonDecode(body) as Map;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        cached['savedAt'] as int,
      );
      final age = _now().difference(savedAt);
      if (age.isNegative || age > _cacheMaxAge) return;
      final details = cached['details'] as List;
      final items = details
          .map((raw) => _parseDetail(raw, raw['tfid'].toString()))
          .where((item) => item.isActive)
          .toList();
      if (generation != _generation || revision != _revision) return;
      ingestExternal(items);
    } catch (_) {}
  }

  Future<void> _saveActiveCache(_TyphoonSnapshot result, int generation) async {
    if (result.fromJian) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation) return;
      // Do not persist retained details as fresh data, or revive removed IDs.
      if (!result.complete || result.typhoons.isEmpty) {
        await prefs.remove(_cacheKey);
      } else {
        await prefs.setString(
          _cacheKey,
          jsonEncode({
            'savedAt': _now().millisecondsSinceEpoch,
            'details': result.rawDetails,
          }),
        );
      }
    } catch (_) {}
  }
}

class _TyphoonSnapshot {
  final List<TyphoonData> typhoons;
  final List<dynamic> rawDetails;
  final bool complete;
  final bool fromJian;
  final List<String> activeIds;

  const _TyphoonSnapshot(
    this.typhoons,
    this.rawDetails,
    this.complete, {
    this.fromJian = false,
    this.activeIds = const [],
  });
}
