import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PAlertStation {
  final String id;
  final String network;
  final String name;
  final String area;
  final LatLng coordinate;
  final double? pgaGal;
  final double? pgvCms;
  final int? cwaIntensityIndex;
  final int? heldCwaIntensityIndex;
  final DateTime? dataTime;
  final DateTime? receivedAt;

  const PAlertStation({
    required this.id,
    required this.network,
    required this.name,
    required this.area,
    required this.coordinate,
    this.pgaGal,
    this.pgvCms,
    this.cwaIntensityIndex,
    this.heldCwaIntensityIndex,
    this.dataTime,
    this.receivedAt,
  });

  int? get displayCwaIntensityIndex =>
      heldCwaIntensityIndex ?? cwaIntensityIndex;

  bool get hasRealtime => displayCwaIntensityIndex != null && dataTime != null;

  static const List<int> _gridLevels = [7, 9, 11, 13, 15, 16, 17, 18, 19, 20];

  int get gridLevel {
    final index = displayCwaIntensityIndex;
    if (index == null || index < 0 || index >= _gridLevels.length) return -1;
    return _gridLevels[index];
  }

  // Kept as an index-shaped compatibility getter for existing callers.
  int get jmaIndex => displayCwaIntensityIndex ?? -1;

  int get shindoClass {
    final index = displayCwaIntensityIndex;
    if (index == null) return -1;
    if (index <= 4) return index;
    if (index <= 6) return 5;
    if (index <= 8) return 6;
    return 7;
  }

  String get shindoLabel {
    return switch (displayCwaIntensityIndex) {
      0 => '0',
      1 => '1',
      2 => '2',
      3 => '3',
      4 => '4',
      5 => '5-',
      6 => '5+',
      7 => '6-',
      8 => '6+',
      9 => '7',
      _ => '--',
    };
  }

  PAlertStation copyWith({
    double? pgaGal,
    double? pgvCms,
    int? cwaIntensityIndex,
    int? heldCwaIntensityIndex,
    DateTime? dataTime,
    DateTime? receivedAt,
  }) {
    return PAlertStation(
      id: id,
      network: network,
      name: name,
      area: area,
      coordinate: coordinate,
      pgaGal: pgaGal ?? this.pgaGal,
      pgvCms: pgvCms ?? this.pgvCms,
      cwaIntensityIndex: cwaIntensityIndex ?? this.cwaIntensityIndex,
      heldCwaIntensityIndex:
          heldCwaIntensityIndex ?? this.heldCwaIntensityIndex,
      dataTime: dataTime ?? this.dataTime,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }
}

class PAlertService {
  static final PAlertService _instance = PAlertService._();
  factory PAlertService() => _instance;
  PAlertService._();

  static final Uri _graphqlUri = Uri.parse(
    'https://palert.earth.sinica.edu.tw/graphql/',
  );
  static const String _stationFilter = 'onlineDot15';
  static const Duration intensityHoldDuration = Duration(seconds: 3);
  static const Duration realtimePollInterval = Duration(seconds: 1);
  static const Duration frameStaleAfter = Duration(seconds: 6);
  static const Duration _frameWatchdogInterval = Duration(seconds: 1);
  static const int maxConsecutiveFailures = 3;

  // Keep the fixed low-value display floor separate from the user setting
  // that controls whether valid intensity 0 markers are shown.
  static const double numericMarkerPgaFloorGal = 0.7;

  static bool isPgaEligibleForNumericMarker(double? pgaGal) {
    return pgaGal != null &&
        pgaGal.isFinite &&
        pgaGal >= numericMarkerPgaFloorGal;
  }

  static const String _stationListQuery = '''
query (\$staFilter: staList_filter_choices) {
  stationList(staFilter: \$staFilter) {
    staInfos
    timestamp
  }
}
''';

  static const String _realtimeQuery = '''
query (\$recordTime: Float!, \$token: String!) {
  pga: realtimePGA(recordTime: \$recordTime, token: \$token, type: 0) {
    timestamp
    dataVals
  }
  pgv: realtimePGA(recordTime: \$recordTime, token: \$token, type: 1) {
    timestamp
    dataVals
  }
}
''';

  final _stationController = StreamController<List<PAlertStation>>.broadcast();
  Stream<List<PAlertStation>> get stationStream => _stationController.stream;
  final ValueNotifier<DateTime?> dataTimeNotifier = ValueNotifier(null);
  final ValueNotifier<DateTime?> receivedTimeNotifier = ValueNotifier(null);
  void Function(bool connected)? onStatusChanged;

  final Map<String, PAlertStation> _stationMap = {};
  final Map<String, List<({DateTime time, int intensityIndex})>>
  _intensityHistory = {};
  List<PAlertStation> _stations = const [];
  List<PAlertStation> get stations => _stations;

  Timer? _stationTimer;
  Timer? _realtimeTimer;
  Timer? _frameWatchdogTimer;
  bool _running = false;
  bool _fetchingStations = false;
  bool _fetchingRealtime = false;
  bool _isConnected = false;
  bool _failureReported = false;
  int _consecutiveFailures = 0;
  int _runGeneration = 0;
  DateTime? _lastRealtimeTimestamp;
  DateTime? _lastFrameReceivedAt;
  http.Client? _client;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_runGeneration;
    _consecutiveFailures = 0;
    _isConnected = false;
    _failureReported = false;
    _lastFrameReceivedAt = null;
    _client = http.Client();
    unawaited(_bootstrap(generation));
    _stationTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _fetchStationList(generation),
    );
    _realtimeTimer = Timer.periodic(
      realtimePollInterval,
      (_) => _fetchRealtime(generation),
    );
    _frameWatchdogTimer = Timer.periodic(
      _frameWatchdogInterval,
      (_) => _checkFrameFreshness(generation),
    );
  }

  void stop({bool clear = true}) {
    _running = false;
    _runGeneration++;
    _stationTimer?.cancel();
    _stationTimer = null;
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    _frameWatchdogTimer?.cancel();
    _frameWatchdogTimer = null;
    _fetchingStations = false;
    _fetchingRealtime = false;
    _isConnected = false;
    _failureReported = false;
    _consecutiveFailures = 0;
    _lastRealtimeTimestamp = null;
    _lastFrameReceivedAt = null;
    _intensityHistory.clear();
    dataTimeNotifier.value = null;
    receivedTimeNotifier.value = null;
    _client?.close();
    _client = null;
    onStatusChanged?.call(false);
    if (clear) {
      _stationMap.clear();
      _stations = const [];
      _stationController.add(_stations);
    }
  }

  bool _isCurrentRun(int generation) =>
      _running && generation == _runGeneration;

  Future<void> _bootstrap(int generation) async {
    await _fetchStationList(generation);
    if (_isCurrentRun(generation)) await _fetchRealtime(generation);
  }

  Future<void> _fetchStationList(int generation) async {
    if (!_isCurrentRun(generation) || _fetchingStations) return;
    _fetchingStations = true;
    try {
      final json = await _postGraphql(
        _stationListQuery,
        variables: const {'staFilter': _stationFilter},
      );
      final data = json['data'] as Map<String, dynamic>?;
      final stationList = data?['stationList'] as Map<String, dynamic>?;
      final infos = stationList?['staInfos'];
      if (infos is! List || infos.isEmpty) {
        if (_stationMap.isEmpty) _handleFailure();
        return;
      }

      final nextStations = <String, PAlertStation>{};
      for (final item in infos) {
        if (item is! Map<String, dynamic>) continue;
        final id = _asString(item['station']);
        final lat = _asDouble(item['lat']);
        final lon = _asDouble(item['lon']);
        if (id.isEmpty || lat == null || lon == null) continue;

        final existing = _stationMap[id];
        nextStations[id] = PAlertStation(
          id: id,
          network: _asString(item['network']),
          name: _asString(item['locname']).isNotEmpty
              ? _asString(item['locname'])
              : id,
          area: _asString(item['area']),
          coordinate: LatLng(lat, lon),
          pgaGal: existing?.pgaGal,
          pgvCms: existing?.pgvCms,
          cwaIntensityIndex: existing?.cwaIntensityIndex,
          heldCwaIntensityIndex: existing?.heldCwaIntensityIndex,
          dataTime: existing?.dataTime,
          receivedAt: existing?.receivedAt,
        );
      }
      if (!_isCurrentRun(generation)) return;
      if (nextStations.isEmpty) {
        if (_stationMap.isEmpty) _handleFailure();
        return;
      }
      _stationMap
        ..clear()
        ..addAll(nextStations);
      _intensityHistory.removeWhere((id, _) => !nextStations.containsKey(id));
      _emitStations();
    } catch (e) {
      if (_isCurrentRun(generation)) {
        debugPrint('[P-Alert] station list fetch failed: $e');
        if (_stationMap.isEmpty) _handleFailure();
      }
    } finally {
      if (generation == _runGeneration) {
        _fetchingStations = false;
      }
    }
  }

  Future<void> _fetchRealtime(int generation) async {
    if (!_isCurrentRun(generation) || _fetchingRealtime) return;
    if (_stationMap.isEmpty) {
      unawaited(_fetchStationList(generation));
      return;
    }
    _fetchingRealtime = true;
    try {
      final json = await _postGraphql(
        _realtimeQuery,
        variables: const {'recordTime': 0, 'token': ''},
      );
      final data = json['data'] as Map<String, dynamic>?;
      final pga = data?['pga'] as Map<String, dynamic>?;
      final pgv = data?['pgv'] as Map<String, dynamic>?;
      final pgaTimestamp = parseTimestamp(pga?['timestamp'] as String?);
      final pgvTimestamp = parseTimestamp(pgv?['timestamp'] as String?);
      if (!_isCurrentRun(generation)) return;
      if (pgaTimestamp == null) {
        _handleFailure();
        return;
      }
      if (!isNewerFrameTime(_lastRealtimeTimestamp, pgaTimestamp)) return;

      final pgaVals = _asValueMap(pga?['dataVals']);
      if (pgaVals.isEmpty) {
        _handleFailure();
        return;
      }
      final pgvVals = pgvTimestamp == pgaTimestamp
          ? _asValueMap(pgv?['dataVals'])
          : const <String, double>{};
      final receivedAt = DateTime.now().toUtc();
      var changed = false;
      for (final id in _stationMap.keys.toList(growable: false)) {
        final pgaGal = pgaVals[id];
        final pgvCms = pgvVals[id];
        if (pgaGal == null && pgvCms == null) continue;
        final station = _stationMap[id]!;
        final hasCurrentPga = pgaGal != null;
        final intensityIndex = hasCurrentPga
            ? cwaIntensityIndexFromPgaPgv(pgaGal: pgaGal, pgvCms: pgvCms)
            : null;
        final heldIntensityIndex = _heldIntensityFor(
          id,
          pgaTimestamp,
          intensityIndex,
        );
        _stationMap[id] = PAlertStation(
          id: station.id,
          network: station.network,
          name: station.name,
          area: station.area,
          coordinate: station.coordinate,
          pgaGal: pgaGal ?? station.pgaGal,
          pgvCms: pgvCms ?? station.pgvCms,
          cwaIntensityIndex: intensityIndex,
          heldCwaIntensityIndex: heldIntensityIndex,
          dataTime: hasCurrentPga ? pgaTimestamp : station.dataTime,
          receivedAt: hasCurrentPga ? receivedAt : station.receivedAt,
        );
        changed = true;
      }
      if (!changed) {
        unawaited(_fetchStationList(generation));
        _handleFailure();
        return;
      }

      _lastRealtimeTimestamp = pgaTimestamp;
      _lastFrameReceivedAt = receivedAt;
      dataTimeNotifier.value = pgaTimestamp;
      receivedTimeNotifier.value = receivedAt;
      _emitStations();
      _handleSuccess();
    } catch (e) {
      if (_isCurrentRun(generation)) {
        debugPrint('[P-Alert] realtime fetch failed: $e');
        _handleFailure();
      }
    } finally {
      if (generation == _runGeneration) {
        _fetchingRealtime = false;
      }
    }
  }

  void _checkFrameFreshness(int generation) {
    if (!_isCurrentRun(generation) ||
        !isFrameStale(_lastFrameReceivedAt, DateTime.now().toUtc())) {
      return;
    }
    _markDisconnected();
  }

  void _handleSuccess() {
    _consecutiveFailures = 0;
    _failureReported = false;
    if (_isConnected) return;
    _isConnected = true;
    onStatusChanged?.call(true);
  }

  void _handleFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures < maxConsecutiveFailures || _failureReported) {
      return;
    }
    _isConnected = false;
    _failureReported = true;
    onStatusChanged?.call(false);
  }

  void _markDisconnected() {
    _consecutiveFailures = maxConsecutiveFailures;
    if (_failureReported) return;
    _isConnected = false;
    _failureReported = true;
    onStatusChanged?.call(false);
  }

  Future<Map<String, dynamic>> _postGraphql(
    String query, {
    required Map<String, dynamic> variables,
  }) async {
    final client = _client;
    if (client == null) throw StateError('P-Alert client is not running');
    final response = await client
        .post(
          _graphqlUri,
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json;charset=UTF-8',
            'Origin': 'https://palert.earth.sinica.edu.tw',
            'Referer': 'https://palert.earth.sinica.edu.tw/realtime',
            'User-Agent': 'FlutterRhythmQuake/1.0',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw StateError('invalid JSON');
    }
    if (json['errors'] != null) {
      throw StateError('GraphQL errors: ${json['errors']}');
    }
    return json;
  }

  void _emitStations() {
    final next = _stationMap.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    _stations = next;
    _stationController.add(next);
  }

  static int? cwaIntensityIndexFromPgaPgv({double? pgaGal, double? pgvCms}) {
    if (pgaGal == null || pgaGal <= 0 || !pgaGal.isFinite) return null;
    if (pgaGal < 0.8) return 0;
    if (pgaGal < 2.5) return 1;
    if (pgaGal < 8.0) return 2;
    if (pgaGal < 25.0) return 3;
    if (pgaGal < 80.0) return 4;

    if (pgvCms == null || pgvCms < 0 || !pgvCms.isFinite) return null;
    if (pgvCms < 15.0) return 4;
    if (pgvCms < 30.0) return 5;
    if (pgvCms < 50.0) return 6;
    if (pgvCms < 80.0) return 7;
    if (pgvCms < 140.0) return 8;
    return 9;
  }

  int? _heldIntensityFor(
    String stationId,
    DateTime timestamp,
    int? currentIntensityIndex,
  ) {
    final samples = _intensityHistory.putIfAbsent(stationId, () => []);
    final cutoff = timestamp.subtract(intensityHoldDuration);
    samples.removeWhere(
      (sample) =>
          sample.time.isBefore(cutoff) || sample.time.isAfter(timestamp),
    );
    if (currentIntensityIndex != null) {
      samples.add((time: timestamp, intensityIndex: currentIntensityIndex));
    }
    if (samples.isEmpty) {
      _intensityHistory.remove(stationId);
      return currentIntensityIndex;
    }
    return samples
        .map((sample) => sample.intensityIndex)
        .reduce((a, b) => a > b ? a : b);
  }

  static DateTime? parseTimestamp(String? value) {
    if (value == null || value.isEmpty) return null;
    final trimmed = value.trim();
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;
    final match = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2}):(\d{2})$',
    ).firstMatch(trimmed);
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  @visibleForTesting
  static bool isNewerFrameTime(DateTime? previous, DateTime candidate) {
    return previous == null || candidate.isAfter(previous);
  }

  @visibleForTesting
  static bool isFrameStale(
    DateTime? receivedAt,
    DateTime now, {
    Duration staleAfter = frameStaleAfter,
  }) {
    return receivedAt != null && now.difference(receivedAt) > staleAfter;
  }

  static Map<String, double> _asValueMap(dynamic raw) {
    if (raw is! Map) return const {};
    final values = <String, double>{};
    for (final entry in raw.entries) {
      final value = _asDouble(entry.value);
      if (value != null) values[entry.key.toString()] = value;
    }
    return values;
  }

  static String _asString(dynamic value) => value?.toString().trim() ?? '';

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}
