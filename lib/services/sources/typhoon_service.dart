import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/typhoon_data.dart';

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
      final result = await _fetchSnapshot(_lastTyphoons);
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
    final result = await _fetchSnapshot(const []);
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
    return _TyphoonSnapshot(items, rawDetails, complete);
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
                ? http.get(uri, headers: headers)
                : _client.get(uri, headers: headers))
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

  const _TyphoonSnapshot(this.typhoons, this.rawDetails, this.complete);
}
