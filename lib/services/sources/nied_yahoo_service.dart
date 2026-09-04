import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/source_estimation/kotoho7_js_receiver_bridge.dart';
import '../../models/nied_station_db.dart';
import '../../services/ntp_service.dart';
import 'jp_shindo_scale.dart';
import 'nied_monitor.dart';

class NiedYahooService {
  static final NiedYahooService _instance = NiedYahooService._internal();
  factory NiedYahooService() => _instance;
  NiedYahooService._internal();

  static const String _tag = 'NiedYahoo';
  static const String _stationListUrl =
      'https://weather-kyoshin.east.edge.storage-yahoo.jp/SiteList/sitelist.json';
  static const String _realtimeDataBaseUrl =
      'https://weather-kyoshin.east.edge.storage-yahoo.jp/RealTimeData';
  static const int _defaultRealtimeDelayMs = 1200;
  static const int _maxRealtimeDelayMs = 3000;
  static const Map<String, String> _noCacheHeaders = <String, String>{
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  final _stationController = StreamController<List<NiedStation>?>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  Stream<List<NiedStation>?> get stationStream => _stationController.stream;
  Stream<bool> get statusStream => _statusController.stream;
  final ValueNotifier<DateTime?> dataFrameTime = ValueNotifier(null);

  void Function(bool connected)? onStatusChanged;

  List<NiedStation>? _stations;
  String? _siteConfigId;
  bool _isRunning = false;
  bool _stationListReloading = false;
  bool _stationListFetching = false;
  Timer? _timer;
  int _runGeneration = 0;
  int? _tickingGeneration;
  String? _lastFetchedTime;
  DateTime? _lastFrameTime;
  DateTime? _lastReplayTickAt;
  DateTime? _lastStationListReloadAt;
  DateTime? _lastDelayDecayAt;
  int _realtimeDelayMs = _defaultRealtimeDelayMs;
  NiedReplayConfig _replayConfig = const NiedReplayConfig.disabled();
  DateTime? _replayCursorJst;
  int _tickCount = 0;
  int _successCount = 0;
  int _errorCount = 0;
  int _configMismatchCount = 0;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _tickCount = 0;
    _successCount = 0;
    _errorCount = 0;
    _configMismatchCount = 0;
    _lastFrameTime = null;
    dataFrameTime.value = null;
    _lastDelayDecayAt = null;
    _realtimeDelayMs = _defaultRealtimeDelayMs;
    _runGeneration++;
    final generation = _runGeneration;
    unawaited(_fetchStationList(generation: generation));
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_tick()),
    );
    unawaited(_tick());
  }

  void stop() {
    _isRunning = false;
    _runGeneration++;
    _timer?.cancel();
    _timer = null;
    _tickingGeneration = null;
    _stationListReloading = false;
    _lastFrameTime = null;
    dataFrameTime.value = null;
    _lastDelayDecayAt = null;
    _realtimeDelayMs = _defaultRealtimeDelayMs;
    onStatusChanged?.call(false);
  }

  void dispose() {
    stop();
    dataFrameTime.value = null;
    _stationController.close();
    _statusController.close();
  }

  void configureReplay(NiedReplayConfig config) {
    _replayConfig = config;
    _replayCursorJst = config.enabled ? config.startJst : null;
    _lastFetchedTime = null;
    _lastFrameTime = null;
    dataFrameTime.value = null;
    _lastReplayTickAt = null;
    _lastDelayDecayAt = null;
    if (!config.enabled) {
      _realtimeDelayMs = _defaultRealtimeDelayMs;
    }
    _restartRunningRequests();
  }

  Future<void> _fetchStationList({
    bool forceRebuild = false,
    bool publish = true,
    required int generation,
  }) async {
    if (_stationListFetching) return;
    _stationListFetching = true;
    try {
      final url =
          '$_stationListUrl?time=${DateTime.now().millisecondsSinceEpoch}';
      final response = await http
          .get(Uri.parse(url), headers: _noCacheHeaders)
          .timeout(const Duration(seconds: 10));
      if (!_isCurrentRun(generation)) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final siteConfigId = data['siteConfigId'] as String?;
        final items = data['items'] as List<dynamic>?;
        if (items != null && (forceRebuild || _stations == null)) {
          _siteConfigId = siteConfigId;
          _buildStations(items);
          if (publish && _stations != null) {
            _stationController.add(List.unmodifiable(_stations!));
          }
          unawaited(_tick());
        } else if (items == null) {
          debugPrint('$_tag: ⚠ 测站列表 items 为 null');
        } else {
          _siteConfigId = siteConfigId;
        }
      } else {
        debugPrint('$_tag: ⚠ 测站列表获取失败 HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!_isCurrentRun(generation)) return;
      debugPrint('$_tag: ✖ 测站列表获取异常: $e');
    } finally {
      _stationListFetching = false;
    }
  }

  void _buildStations(List<dynamic> items) {
    final db = NiedStationDb.stations;
    final list = <NiedStation>[];
    int k = -1;
    const maxTry = 10;

    for (int i = 0; i < items.length; i++) {
      final item = items[i] as List<dynamic>;
      final targetLat = _roundTo1((item[0] as num).toDouble());
      final targetLng = _roundTo1((item[1] as num).toDouble());

      int? matchedIdx;
      for (int j = 0; j < maxTry && (k + j + 1) < db.length; j++) {
        final s = db[k + j + 1];
        final lat = _roundTo1((s['lat'] as num).toDouble());
        final lng = _roundTo1((s['lng'] as num).toDouble());
        if (lat == targetLat && lng == targetLng) {
          matchedIdx = k + j + 1;
          break;
        }
      }

      if (matchedIdx != null) {
        k = matchedIdx;
        final s = db[matchedIdx];
        list.add(
          NiedStation(
            id: i,
            code: s['code'] as String,
            name: s['name'] as String,
            coordinate: LatLng(
              (s['lat'] as num).toDouble(),
              (s['lng'] as num).toDouble(),
            ),
            network: (s['network'] as String?) ?? 'K-NET',
            prefecture: (s['pref'] as String?) ?? '',
            expireSeconds: NiedStation.kaExpireSeconds,
          ),
        );
      } else {
        list.add(
          NiedStation(
            id: i,
            code: 'YAH$i',
            name: '',
            coordinate: LatLng(
              (item[0] as num).toDouble(),
              (item[1] as num).toDouble(),
            ),
            network: 'K-NET',
            prefecture: '',
            expireSeconds: NiedStation.kaExpireSeconds,
          ),
        );
      }
    }

    _stations = list;
  }

  Future<void> _reloadStationListAfterConfigMismatch({
    required String? expected,
    required String? actual,
    required int generation,
  }) async {
    if (!_isCurrentRun(generation)) return;
    if (_stationListReloading) return;
    final now = DateTime.now();
    final lastReloadAt = _lastStationListReloadAt;
    if (lastReloadAt != null &&
        now.difference(lastReloadAt) < const Duration(seconds: 5)) {
      return;
    }

    _stationListReloading = true;
    _lastStationListReloadAt = now;
    try {
      debugPrint(
        '$_tag: siteConfigId changed, reloading station list '
        '(expected=$expected, actual=$actual)',
      );
      for (final station in _stations ?? const <NiedStation>[]) {
        station.terminate();
      }
      _stations = null;
      _siteConfigId = null;
      _lastFrameTime = null;
      _lastFetchedTime = null;
      dataFrameTime.value = null;
      _lastDelayDecayAt = null;
      _realtimeDelayMs = _defaultRealtimeDelayMs;
      _stationController.add(const <NiedStation>[]);
      await _fetchStationList(forceRebuild: true, generation: generation);
      if (!_isCurrentRun(generation)) return;
      if (_stations != null && _stations!.isNotEmpty) {
        _configMismatchCount = 0;
      }
    } finally {
      if (_isCurrentRun(generation)) {
        _stationListReloading = false;
      }
    }
  }

  Future<void> _tick() async {
    if (!_isRunning) return;
    if (_stations == null || _stations!.isEmpty) {
      unawaited(_fetchStationList(generation: _runGeneration));
      return;
    }
    final generation = _runGeneration;
    if (_tickingGeneration == generation) return;
    _tickingGeneration = generation;
    try {
      if (_replayConfig.enabled && _replayConfig.startJst != null) {
        final now = DateTime.now();
        final lastReplayTickAt = _lastReplayTickAt;
        if (lastReplayTickAt != null &&
            now.difference(lastReplayTickAt) < const Duration(seconds: 1)) {
          return;
        }
        _lastReplayTickAt = now;
        _tickCount++;
        final replayTime = _replayCursorJst ?? _replayConfig.startJst!;
        _replayCursorJst = replayTime.add(
          Duration(seconds: _replayConfig.stepSeconds.clamp(1, 60)),
        );
        final timeKey = _formatJst(replayTime);
        if (timeKey == _lastFetchedTime) {
          return;
        }
        _lastFetchedTime = timeKey;
        await _fetchReplayRealtimeData(timeKey, generation: generation);
        return;
      }

      _tickCount++;
      _decayRealtimeDelayIfNeeded();
      final jstNow = NtpService().now
          .toUtc()
          .add(const Duration(hours: 9))
          .subtract(Duration(milliseconds: _realtimeDelayMs));
      final ymd =
          '${jstNow.year}${jstNow.month.toString().padLeft(2, '0')}${jstNow.day.toString().padLeft(2, '0')}';
      final hms =
          '${jstNow.hour.toString().padLeft(2, '0')}${jstNow.minute.toString().padLeft(2, '0')}${jstNow.second.toString().padLeft(2, '0')}';
      final timeKey = '$ymd$hms';

      if (timeKey == _lastFetchedTime) {
        return;
      }

      final url = '$_realtimeDataBaseUrl/$ymd/$timeKey.json';

      try {
        final response = await http
            .get(Uri.parse(url), headers: _noCacheHeaders)
            .timeout(const Duration(seconds: 5));
        if (!_isCurrentRun(generation)) return;

        if (response.statusCode != 200) {
          _errorCount++;
          _increaseRealtimeDelay();
          if (_tickCount % 20 == 0) {
            debugPrint(
              '$_tag: HTTP ${response.statusCode} '
              '(tick=$_tickCount, 成功=$_successCount, 错误=$_errorCount, '
              'delay=${_realtimeDelayMs}ms)',
            );
          }
          return;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rtData = data['realTimeData'] as Map<String, dynamic>?;
        if (rtData == null) {
          debugPrint('$_tag: ⚠ realTimeData 为 null');
          return;
        }

        final configId = rtData['siteConfigId'] as String?;
        if (configId != _siteConfigId) {
          _configMismatchCount++;
          if (_configMismatchCount <= 3) {
            debugPrint(
              '$_tag: ⚠ siteConfigId 不匹配: 期望=$_siteConfigId, 实际=$configId',
            );
          }
          await _reloadStationListAfterConfigMismatch(
            expected: _siteConfigId,
            actual: configId,
            generation: generation,
          );
          return;
        }

        final intensityStr = rtData['intensity'] as String?;
        if (intensityStr == null) {
          debugPrint('$_tag: ⚠ intensity 字符串为 null');
          return;
        }
        if (intensityStr.length != _stations!.length) {
          debugPrint(
            '$_tag: ⚠ intensity 长度不一致: '
            'stations=${_stations!.length}, intensity=${intensityStr.length}',
          );
          return;
        }

        final dataTime = rtData['dataTime'] as String?;
        final stamp =
            _parseYahooDataTime(dataTime) ??
            _parseTimeKey(timeKey) ??
            DateTime.now();
        if (!_shouldProcessFrame(stamp)) {
          return;
        }
        _applyFrameGap(stamp);
        _lastFetchedTime = timeKey;
        dataFrameTime.value = stamp;
        _successCount++;
        for (int i = 0; i < _stations!.length && i < intensityStr.length; i++) {
          final charCode = intensityStr.codeUnitAt(i);
          final detectLevel = charCode - 100;
          final station = _stations![i];
          station
            ..lastUpdate = stamp
            ..lastDataTime = stamp
            ..lastReceivedAt = DateTime.now();
          station.update(detectLevel);
        }

        _logZeroOrAboveStations(dataTime ?? timeKey);

        _stationController.add(List.unmodifiable(_stations!));
        _statusController.add(true);
        onStatusChanged?.call(true);
      } catch (e) {
        if (!_isCurrentRun(generation)) return;
        _errorCount++;
        if (_errorCount <= 5 || _errorCount % 20 == 0) {
          debugPrint(
            '$_tag: ✖ tick 异常: $e (tick=$_tickCount, 错误=$_errorCount)',
          );
        }
      }
    } finally {
      if (_tickingGeneration == generation) {
        _tickingGeneration = null;
      }
    }
  }

  Future<void> _fetchReplayRealtimeData(
    String timeKey, {
    required int generation,
  }) async {
    final ymd = timeKey.substring(0, 8);
    final url = '$_realtimeDataBaseUrl/$ymd/$timeKey.json';

    try {
      final response = await http
          .get(Uri.parse(url), headers: _noCacheHeaders)
          .timeout(const Duration(seconds: 5));
      if (!_isCurrentRun(generation)) return;

      if (response.statusCode != 200) {
        _errorCount++;
        debugPrint('$_tag: Replay HTTP ${response.statusCode} for $timeKey');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rtData = data['realTimeData'] as Map<String, dynamic>?;
      if (rtData == null) {
        debugPrint('$_tag: Replay realTimeData is null for $timeKey');
        return;
      }

      final configId = rtData['siteConfigId'] as String?;
      if (configId != _siteConfigId && _configMismatchCount < 3) {
        _configMismatchCount++;
        debugPrint(
          '$_tag: Replay siteConfigId mismatch: expected=$_siteConfigId actual=$configId, parsing with current site list',
        );
      }

      final intensityStr = rtData['intensity'] as String?;
      if (intensityStr == null) {
        debugPrint('$_tag: Replay intensity is null for $timeKey');
        return;
      }
      if (intensityStr.length != _stations!.length) {
        debugPrint(
          '$_tag: Replay intensity length mismatch: '
          'stations=${_stations!.length}, intensity=${intensityStr.length}',
        );
        return;
      }

      final stamp =
          _parseYahooDataTime(rtData['dataTime'] as String?) ??
          _parseTimeKey(timeKey) ??
          DateTime.now();
      if (!_shouldProcessFrame(stamp)) {
        return;
      }
      _applyFrameGap(stamp);
      dataFrameTime.value = stamp;
      _successCount++;
      for (int i = 0; i < _stations!.length && i < intensityStr.length; i++) {
        final detectLevel = intensityStr.codeUnitAt(i) - 100;
        final station = _stations![i];
        station
          ..lastUpdate = stamp
          ..lastDataTime = stamp
          ..lastReceivedAt = DateTime.now();
        station.update(detectLevel);
      }

      _logZeroOrAboveStations(timeKey);
      _stationController.add(List.unmodifiable(_stations!));
      _statusController.add(true);
      onStatusChanged?.call(true);
      await _waitForReplaySourceBridgeBackpressure();
    } catch (e) {
      if (!_isCurrentRun(generation)) return;
      _errorCount++;
      debugPrint('$_tag: Replay error: $e');
    }
  }

  Future<void> _waitForReplaySourceBridgeBackpressure() async {
    await Future<void>.delayed(Duration.zero);
    const maxWait = Duration(milliseconds: 1200);
    final stopwatch = Stopwatch()..start();
    var lastLogged = '';
    while (stopwatch.elapsed < maxWait) {
      final status = Kotoho7JsReceiverBridge.queueStatus();
      if (!status.hasWork) return;
      final signature =
          '${status.pendingFrameCount}/${status.inFlightSessionCount}';
      if (kDebugMode && signature != lastLogged) {
        lastLogged = signature;
        debugPrint(
          '$_tag: Replay wait JS bridge '
          'pending=${status.pendingFrameCount} '
          'inFlight=${status.inFlightSessionCount}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  bool _shouldProcessFrame(DateTime stamp) {
    return _isNewerFrame(stamp, _lastFrameTime);
  }

  static bool _isNewerFrame(DateTime stamp, DateTime? previous) =>
      previous == null || stamp.isAfter(previous);

  @visibleForTesting
  static bool isNewerFrameForTest(DateTime stamp, DateTime? previous) =>
      _isNewerFrame(stamp, previous);

  @visibleForTesting
  static Map<String, String> get realtimeRequestHeadersForTest =>
      _noCacheHeaders;

  void _applyFrameGap(DateTime stamp) {
    final stations = _stations;
    if (stations == null || stations.isEmpty) {
      _lastFrameTime = stamp;
      return;
    }

    final previous = _lastFrameTime;
    if (previous == null) {
      _lastFrameTime = stamp;
      return;
    }

    final diffMs = stamp.difference(previous).inMilliseconds;
    if (diffMs <= 0) return;

    _lastFrameTime = stamp;
    if (diffMs <= 1000) return;

    var missingFrames = (diffMs / 1000).round() - 1;
    if (missingFrames <= 0) return;
    if (missingFrames > NiedStation.maxExpireSeconds) {
      missingFrames = NiedStation.maxExpireSeconds;
    }

    final noData = List<int>.filled(missingFrames, -1);
    final stale = diffMs > 10000;
    for (final station in stations) {
      station.recentLevel.insertAll(0, noData);
      if (station.recentLevel.length > NiedStation.maxExpireSeconds) {
        station.recentLevel = station.recentLevel.sublist(
          0,
          NiedStation.maxExpireSeconds,
        );
      }
      if (stale) {
        station.isActive = false;
      }
    }
  }

  void _increaseRealtimeDelay() {
    if (_replayConfig.enabled) return;
    if (_realtimeDelayMs <= _maxRealtimeDelayMs - 100) {
      _realtimeDelayMs += 100;
    }
  }

  void _decayRealtimeDelayIfNeeded() {
    if (_replayConfig.enabled) return;
    final now = DateTime.now();
    final lastDecay = _lastDelayDecayAt;
    if (lastDecay != null &&
        now.difference(lastDecay) < const Duration(seconds: 10)) {
      return;
    }
    _lastDelayDecayAt = now;
    if (_realtimeDelayMs <= _defaultRealtimeDelayMs) {
      _realtimeDelayMs = _defaultRealtimeDelayMs;
      return;
    }
    final step = _realtimeDelayMs <= (_maxRealtimeDelayMs * 2 ~/ 3) ? 20 : 100;
    _realtimeDelayMs = (_realtimeDelayMs - step).clamp(
      _defaultRealtimeDelayMs,
      _maxRealtimeDelayMs,
    );
  }

  bool _isCurrentRun(int generation) =>
      _isRunning && _runGeneration == generation;

  void _restartRunningRequests() {
    if (!_isRunning) return;
    _runGeneration++;
    _tickingGeneration = null;
    unawaited(_tick());
  }

  String _formatJst(DateTime jstTime) {
    final ymd =
        '${jstTime.year}${jstTime.month.toString().padLeft(2, '0')}${jstTime.day.toString().padLeft(2, '0')}';
    final hms =
        '${jstTime.hour.toString().padLeft(2, '0')}${jstTime.minute.toString().padLeft(2, '0')}${jstTime.second.toString().padLeft(2, '0')}';
    return '$ymd$hms';
  }

  void _logZeroOrAboveStations(String dataTime) {
    if (!kDebugMode) return;
    final stations = _stations;
    if (stations == null) return;

    final detected = stations.where((s) => s.level >= 7).toList()
      ..sort((a, b) => b.level.compareTo(a.level));
    if (detected.isEmpty) return;

    final list = detected
        .map((s) {
          final rawShindo = JpShindoScale.rawShindoFromKanameishiLevel(s.level);
          final name = s.name.isNotEmpty ? s.name : s.code;
          return '${s.code}/$name:${rawShindo.toStringAsFixed(2)}';
        })
        .join(', ');
    debugPrint(
      '$_tag: shindo>=0 stations time=$dataTime count=${detected.length}: $list',
    );
  }

  static double levelToShindo(int lvl) {
    return JpShindoScale.rawShindoFromKanameishiLevel(lvl);
  }

  DateTime? _parseYahooDataTime(String? value) {
    if (value == null) return null;
    final m = RegExp(
      r'^(\d{4})[/-](\d{2})[/-](\d{2})\s+(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(value.trim());
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  DateTime? _parseTimeKey(String? timeKey) {
    if (timeKey == null || timeKey.length != 14) return null;
    try {
      return DateTime(
        int.parse(timeKey.substring(0, 4)),
        int.parse(timeKey.substring(4, 6)),
        int.parse(timeKey.substring(6, 8)),
        int.parse(timeKey.substring(8, 10)),
        int.parse(timeKey.substring(10, 12)),
        int.parse(timeKey.substring(12, 14)),
      );
    } catch (_) {
      return null;
    }
  }

  static double _roundTo1(double v) => (v * 10).roundToDouble() / 10;
}
