import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
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

  final _stationController = StreamController<List<NiedStation>?>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  Stream<List<NiedStation>?> get stationStream => _stationController.stream;
  Stream<bool> get statusStream => _statusController.stream;

  void Function(bool connected)? onStatusChanged;

  List<NiedStation>? _stations;
  String? _siteConfigId;
  bool _isRunning = false;
  Timer? _timer;
  String? _lastFetchedTime;
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
    _fetchStationList();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _isRunning = false;
    onStatusChanged?.call(false);
  }

  void dispose() {
    stop();
    _stationController.close();
    _statusController.close();
  }

  void configureReplay(NiedReplayConfig config) {
    _replayConfig = config;
    _replayCursorJst = config.enabled ? config.startJst : null;
    _lastFetchedTime = null;
  }

  Future<void> _fetchStationList() async {
    try {
      final url =
          '$_stationListUrl?time=${DateTime.now().millisecondsSinceEpoch}';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _siteConfigId = data['siteConfigId'] as String?;
        final items = data['items'] as List<dynamic>?;
        if (items != null && _stations == null) {
          _buildStations(items);
        } else if (items == null) {
          debugPrint('$_tag: ⚠ 测站列表 items 为 null');
        }
      } else {
        debugPrint('$_tag: ⚠ 测站列表获取失败 HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('$_tag: ✖ 测站列表获取异常: $e');
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
            expireSeconds: 30,
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
            expireSeconds: 30,
          ),
        );
      }
    }

    _stations = list;
  }

  Future<void> _tick() async {
    if (_stations == null || _stations!.isEmpty) return;

    if (_replayConfig.enabled && _replayConfig.startJst != null) {
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
      await _fetchReplayRealtimeData(timeKey);
      return;
    }

    _tickCount++;
    final jstNow = NtpService().now
        .toUtc()
        .add(const Duration(hours: 9))
        .subtract(const Duration(seconds: 2));
    final ymd =
        '${jstNow.year}${jstNow.month.toString().padLeft(2, '0')}${jstNow.day.toString().padLeft(2, '0')}';
    final hms =
        '${jstNow.hour.toString().padLeft(2, '0')}${jstNow.minute.toString().padLeft(2, '0')}${jstNow.second.toString().padLeft(2, '0')}';
    final timeKey = '$ymd$hms';

    if (timeKey == _lastFetchedTime) {
      return;
    }
    _lastFetchedTime = timeKey;

    final url = '$_realtimeDataBaseUrl/$ymd/$timeKey.json';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        _errorCount++;
        if (_tickCount % 20 == 0) {
          debugPrint(
            '$_tag: HTTP ${response.statusCode} (tick=$_tickCount, 成功=$_successCount, 错误=$_errorCount)',
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
        return;
      }

      final intensityStr = rtData['intensity'] as String?;
      if (intensityStr == null) {
        debugPrint('$_tag: ⚠ intensity 字符串为 null');
        return;
      }

      final dataTime = rtData['dataTime'] as String?;
      final stamp =
          _parseYahooDataTime(dataTime) ??
          _parseTimeKey(timeKey) ??
          DateTime.now();
      _successCount++;
      for (int i = 0; i < _stations!.length && i < intensityStr.length; i++) {
        final charCode = intensityStr.codeUnitAt(i);
        final detectLevel = charCode - 100;
        final level = JpShindoScale.levelFromKanameishiLevel(detectLevel);
        final station = _stations![i];
        station.update(level, newDetectLevel: detectLevel);
        station
          ..lastUpdate = stamp
          ..lastDataTime = stamp
          ..lastReceivedAt = DateTime.now();
      }

      _logZeroOrAboveStations(dataTime ?? timeKey);

      _stationController.add(List.unmodifiable(_stations!));
      _statusController.add(true);
      onStatusChanged?.call(true);
    } catch (e) {
      _errorCount++;
      if (_errorCount <= 5 || _errorCount % 20 == 0) {
        debugPrint('$_tag: ✖ tick 异常: $e (tick=$_tickCount, 错误=$_errorCount)');
      }
    }
  }

  Future<void> _fetchReplayRealtimeData(String timeKey) async {
    final ymd = timeKey.substring(0, 8);
    final url = '$_realtimeDataBaseUrl/$ymd/$timeKey.json';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

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

      _successCount++;
      final stamp =
          _parseYahooDataTime(rtData['dataTime'] as String?) ??
          _parseTimeKey(timeKey) ??
          DateTime.now();
      for (int i = 0; i < _stations!.length && i < intensityStr.length; i++) {
        final detectLevel = intensityStr.codeUnitAt(i) - 100;
        final level = JpShindoScale.levelFromKanameishiLevel(detectLevel);
        final station = _stations![i];
        station.update(level, newDetectLevel: detectLevel);
        station
          ..lastUpdate = stamp
          ..lastDataTime = stamp
          ..lastReceivedAt = DateTime.now();
      }

      _logZeroOrAboveStations(timeKey);
      _stationController.add(List.unmodifiable(_stations!));
      _statusController.add(true);
      onStatusChanged?.call(true);
    } catch (e) {
      _errorCount++;
      debugPrint('$_tag: Replay error: $e');
    }
  }

  String _formatJst(DateTime jstTime) {
    final ymd =
        '${jstTime.year}${jstTime.month.toString().padLeft(2, '0')}${jstTime.day.toString().padLeft(2, '0')}';
    final hms =
        '${jstTime.hour.toString().padLeft(2, '0')}${jstTime.minute.toString().padLeft(2, '0')}${jstTime.second.toString().padLeft(2, '0')}';
    return '$ymd$hms';
  }

  void _logZeroOrAboveStations(String dataTime) {
    final stations = _stations;
    if (stations == null) return;

    final detected =
        stations
            .where(
              (s) =>
                  s.level >= 0 &&
                  JpShindoScale.rawShindoFromLevel(s.level) >= 0,
            )
            .toList()
          ..sort((a, b) => b.level.compareTo(a.level));
    if (detected.isEmpty) return;

    final list = detected
        .map((s) {
          final rawShindo = JpShindoScale.rawShindoFromLevel(s.level);
          final name = s.name.isNotEmpty ? s.name : s.code;
          return '${s.code}/$name:${rawShindo.toStringAsFixed(2)}';
        })
        .join(', ');
    debugPrint(
      '$_tag: shindo>=0 stations time=$dataTime count=${detected.length}: $list',
    );
  }

  static double levelToShindo(int lvl) {
    return JpShindoScale.displayShindoFromLevel(lvl);
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
