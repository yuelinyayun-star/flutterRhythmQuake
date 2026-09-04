import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/calculator.dart';
import '../../models/weather_alarm.dart';

enum CmaLocalWeatherStatus {
  idle,
  noLocation,
  resolvingStation,
  loading,
  ready,
  failed,
}

class CmaWeatherStation {
  const CmaWeatherStation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
}

class CmaStationSummary {
  const CmaStationSummary({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.temperature,
    this.weather = '',
    this.weatherCode,
    this.windDirection = '',
    this.windScale = '',
    this.minTemperature,
    this.provinceCode = '',
    this.adminCode = '',
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double? temperature;
  final String weather;
  final int? weatherCode;
  final String windDirection;
  final String windScale;
  final double? minTemperature;
  final String provinceCode;
  final String adminCode;

  bool get isRaining {
    final w = weather.trim();
    return w.contains('雨') || w.contains('雪') || w.contains('雹');
  }

  /// 雨量/降水强度等级 (0: 无雨, 1: 阵雨/小雨, 2: 中雨/雷阵雨, 3: 大雨, 4: 暴雨, 5: 大暴雨/特大暴雨)
  int get rainSeverity {
    final w = weather.trim();
    if (w.contains('特大暴雨') || w.contains('大暴雨')) return 5;
    if (w.contains('暴雨')) return 4;
    if (w.contains('大雨') || w.contains('大到暴雨')) return 3;
    if (w.contains('中雨') || w.contains('中到大雨') || w.contains('雷阵雨')) return 2;
    if (w.contains('小雨') ||
        w.contains('阵雨') ||
        w.contains('毛毛雨') ||
        w.contains('小到中雨')) {
      return 1;
    }
    if (isRaining) return 1;
    return 0;
  }

  /// 真实降水天气现象名称（如 "大雨"、"中雨"、"暴雨"）
  String get rainWithAmountText => weather;
}

class CmaWeatherAlarm {
  const CmaWeatherAlarm({
    required this.id,
    required this.title,
    required this.signalType,
    required this.signalLevel,
    required this.severity,
    required this.effective,
  });

  final String id;
  final String title;
  final String signalType;
  final String signalLevel;
  final String severity;
  final DateTime? effective;

  String get displayText {
    final type = signalType.trim();
    final level = signalLevel.trim();
    if (type.isNotEmpty && level.isNotEmpty) return '$type$level预警';
    if (type.isNotEmpty) return type;
    return title.trim();
  }

  int get severityRank {
    switch (severity.trim().toUpperCase()) {
      case 'RED':
        return 4;
      case 'ORANGE':
        return 3;
      case 'YELLOW':
        return 2;
      case 'BLUE':
        return 1;
    }
    switch (signalLevel.trim()) {
      case '红色':
        return 4;
      case '橙色':
        return 3;
      case '黄色':
        return 2;
      case '蓝色':
        return 1;
      default:
        return 0;
    }
  }
}

class CmaLocalWeatherObservation {
  const CmaLocalWeatherObservation({
    required this.station,
    required this.locationPath,
    required this.precipitation,
    required this.temperature,
    required this.pressure,
    required this.humidity,
    required this.windDirection,
    required this.windDirectionDegree,
    required this.windSpeed,
    required this.windScale,
    required this.feelsLike,
    required this.observedAt,
    this.alarms = const [],
  });

  final CmaWeatherStation station;
  final String locationPath;
  final double? precipitation;
  final double? temperature;
  final double? pressure;
  final double? humidity;
  final String windDirection;
  final double? windDirectionDegree;
  final double? windSpeed;
  final String windScale;
  final double? feelsLike;
  final DateTime? observedAt;
  final List<CmaWeatherAlarm> alarms;
}

class CmaLocalWeatherState {
  const CmaLocalWeatherState({
    this.status = CmaLocalWeatherStatus.idle,
    this.station,
    this.observation,
  });

  final CmaLocalWeatherStatus status;
  final CmaWeatherStation? station;
  final CmaLocalWeatherObservation? observation;
}

@visibleForTesting
CmaWeatherStation? cmaNearestStationFromRows(
  List<dynamic> rows, {
  required double latitude,
  required double longitude,
}) {
  CmaWeatherStation? nearest;
  var nearestDistance = double.infinity;

  for (final raw in rows) {
    if (raw is! List || raw.length < 6) continue;
    final id = raw[0]?.toString().trim() ?? '';
    final name = raw[1]?.toString().trim() ?? '';
    final stationLat = _cmaDouble(raw[4]);
    final stationLng = _cmaDouble(raw[5]);
    if (!RegExp(r'^[A-Za-z0-9_-]{3,16}$').hasMatch(id) ||
        name.isEmpty ||
        stationLat == null ||
        stationLng == null ||
        stationLat < -90 ||
        stationLat > 90 ||
        stationLng < -180 ||
        stationLng > 180) {
      continue;
    }

    final distance = QuakeCalculator.haversineDistance(
      latitude,
      longitude,
      stationLat,
      stationLng,
    );
    if (distance >= nearestDistance) continue;
    nearestDistance = distance;
    nearest = CmaWeatherStation(
      id: id,
      name: name,
      latitude: stationLat,
      longitude: stationLng,
    );
  }

  return nearest;
}

@visibleForTesting
List<CmaStationSummary> cmaStationSummariesFromRows(List<dynamic> rows) {
  final list = <CmaStationSummary>[];
  for (final raw in rows) {
    if (raw is! List || raw.length < 6) continue;
    final id = raw[0]?.toString().trim() ?? '';
    final name = raw[1]?.toString().trim() ?? '';
    final stationLat = _cmaDouble(raw[4]);
    final stationLng = _cmaDouble(raw[5]);
    if (!RegExp(r'^[A-Za-z0-9_-]{3,16}$').hasMatch(id) ||
        name.isEmpty ||
        stationLat == null ||
        stationLng == null ||
        stationLat < -90 ||
        stationLat > 90 ||
        stationLng < -180 ||
        stationLng > 180) {
      continue;
    }
    final temp = raw.length > 6 ? _cmaDouble(raw[6]) : null;
    final weather = raw.length > 7 ? raw[7]?.toString().trim() ?? '' : '';
    final weatherCode = raw.length > 8 ? _cmaInt(raw[8]) : null;
    final windDirection = raw.length > 9
        ? raw[9]?.toString().trim() ?? ''
        : '';
    final windScale = raw.length > 10 ? raw[10]?.toString().trim() ?? '' : '';
    final minTemp = raw.length > 11 ? _cmaDouble(raw[11]) : null;
    final provinceCode = raw.length > 16
        ? raw[16]?.toString().trim() ?? ''
        : '';
    final adminCode = raw.length > 17 ? raw[17]?.toString().trim() ?? '' : '';

    list.add(
      CmaStationSummary(
        id: id,
        name: name,
        latitude: stationLat,
        longitude: stationLng,
        temperature: temp != null && temp > 9000 ? null : temp,
        weather: weather,
        weatherCode: weatherCode,
        windDirection: windDirection == '9999' ? '' : windDirection,
        windScale: windScale == '9999' ? '' : windScale,
        minTemperature: minTemp != null && minTemp > 9000 ? null : minTemp,
        provinceCode: provinceCode,
        adminCode: adminCode,
      ),
    );
  }
  return List<CmaStationSummary>.unmodifiable(list);
}

@visibleForTesting
CmaLocalWeatherObservation? cmaObservationFromJson(
  Map<String, dynamic> raw,
  CmaWeatherStation fallbackStation,
) {
  if (_cmaInt(raw['code']) != 0) return null;
  final dataRaw = raw['data'];
  if (dataRaw is! Map) return null;
  final data = Map<String, dynamic>.from(dataRaw);
  final locationRaw = data['location'];
  final nowRaw = data['now'];
  if (nowRaw is! Map) return null;
  final location = locationRaw is Map
      ? Map<String, dynamic>.from(locationRaw)
      : const <String, dynamic>{};
  final now = Map<String, dynamic>.from(nowRaw);

  final stationId = location['id']?.toString().trim() ?? '';
  final stationName = location['name']?.toString().trim() ?? '';
  final station = CmaWeatherStation(
    id: stationId.isEmpty ? fallbackStation.id : stationId,
    name: stationName.isEmpty ? fallbackStation.name : stationName,
    latitude: fallbackStation.latitude,
    longitude: fallbackStation.longitude,
  );

  return CmaLocalWeatherObservation(
    station: station,
    locationPath: location['path']?.toString().trim() ?? '',
    precipitation: _cmaDouble(now['precipitation']),
    temperature: _cmaDouble(now['temperature']),
    pressure: _cmaDouble(now['pressure']),
    humidity: _cmaDouble(now['humidity']),
    windDirection: now['windDirection']?.toString().trim() ?? '',
    windDirectionDegree: _cmaDouble(now['windDirectionDegree']),
    windSpeed: _cmaDouble(now['windSpeed']),
    windScale: now['windScale']?.toString().trim() ?? '',
    feelsLike: _cmaDouble(now['feelst']),
    observedAt: _cmaDateTime(data['lastUpdate']),
    alarms: cmaAlarmsFromRaw(data['alarm']),
  );
}

@visibleForTesting
List<CmaWeatherAlarm> cmaAlarmsFromRaw(Object? raw) {
  final rows = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) rows.add(Map<String, dynamic>.from(item));
    }
  } else if (raw is Map) {
    rows.add(Map<String, dynamic>.from(raw));
  }

  final alarms = <CmaWeatherAlarm>[];
  for (final row in rows) {
    final alarm = CmaWeatherAlarm(
      id: row['id']?.toString().trim() ?? '',
      title: row['title']?.toString().trim() ?? '',
      signalType: row['signaltype']?.toString().trim() ?? '',
      signalLevel: row['signallevel']?.toString().trim() ?? '',
      severity: row['severity']?.toString().trim() ?? '',
      effective: _cmaDateTime(row['effective']),
    );
    if (alarm.displayText.isEmpty) continue;
    alarms.add(alarm);
  }
  alarms.sort((a, b) => b.severityRank.compareTo(a.severityRank));
  return List<CmaWeatherAlarm>.unmodifiable(alarms);
}

@visibleForTesting
WeatherAlarm? cmaBestWeatherAlarmForDisplay(
  CmaLocalWeatherObservation? observation,
) {
  if (observation == null || observation.alarms.isEmpty) return null;

  final alarm = observation.alarms.first;
  final headline = alarm.title.trim().isNotEmpty
      ? alarm.title.trim()
      : '${observation.station.name}发布${alarm.displayText}';
  final description = observation.locationPath.trim().isNotEmpty
      ? observation.locationPath.trim()
      : observation.station.name;

  return WeatherAlarm(
    id: alarm.id.isNotEmpty
        ? 'cma:${alarm.id}'
        : 'cma:${observation.station.id}:${alarm.displayText}',
    headline: headline,
    effective: _cmaEffectiveText(alarm.effective),
    description: description,
    latitude: observation.station.latitude,
    longitude: observation.station.longitude,
    type: '11${_cmaLevelCode(alarm)}',
    source: WeatherAlarmSource.chinaWeatherLocal,
  );
}

String _cmaEffectiveText(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _cmaLevelCode(CmaWeatherAlarm alarm) {
  switch (alarm.severity.trim().toUpperCase()) {
    case 'RED':
      return '04';
    case 'ORANGE':
      return '03';
    case 'YELLOW':
      return '02';
    case 'BLUE':
      return '01';
  }
  switch (alarm.signalLevel.trim()) {
    case '红色':
      return '04';
    case '橙色':
      return '03';
    case '黄色':
      return '02';
    case '蓝色':
      return '01';
    default:
      return '02';
  }
}

double? _cmaDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _cmaInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _cmaDateTime(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceAll('/', '-'));
}

class CmaLocalWeatherService {
  CmaLocalWeatherService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _stationDirectoryUrl =
      'https://weather.cma.cn/api/map/weather/1';
  static const String _observationBaseUrl = 'https://weather.cma.cn/api/now/';
  static const Duration refreshInterval = Duration(minutes: 5);
  static const double _stationCacheAnchorRadiusKm = 5;

  static const String _cacheAnchorLatKey = 'cma_weather_anchor_lat';
  static const String _cacheAnchorLngKey = 'cma_weather_anchor_lng';
  static const String _cacheStationIdKey = 'cma_weather_station_id';
  static const String _cacheStationNameKey = 'cma_weather_station_name';
  static const String _cacheStationLatKey = 'cma_weather_station_lat';
  static const String _cacheStationLngKey = 'cma_weather_station_lng';

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Referer': 'https://weather.cma.cn/',
    'User-Agent': 'flutterrhythmquake/1.0',
  };
  static Map<String, String> get _requestHeaders =>
      kIsWeb ? const {'Accept': 'application/json'} : _headers;

  /// 全局共享的 CMA 全国测站实况摘要列表（供地图图层与各组件直接复用）
  static final ValueNotifier<List<CmaStationSummary>> stationDirectoryNotifier =
      ValueNotifier<List<CmaStationSummary>>(const []);
  static DateTime? _lastDirectoryFetchTime;

  /// 全局共享的测站实时详情缓存（包含实测降水 mm、实测风速 m/s、体感气温等）
  static final ValueNotifier<Map<String, CmaLocalWeatherObservation>>
  stationObservationMapNotifier =
      ValueNotifier<Map<String, CmaLocalWeatherObservation>>(const {});
  static final Set<String> _pendingObservationFetches = <String>{};
  static final List<String> _prefetchQueue = <String>[];
  static final Map<String, CmaLocalWeatherObservation> _batchBuffer =
      <String, CmaLocalWeatherObservation>{};
  static Timer? _batchFlushTimer;
  static bool _isWorkerActive = false;
  static http.Client? _sharedWorkerClient;

  /// 批量预加载指定测站列表（按视口优先级插入队列头部并触发后台 Worker，防重防卡顿）
  static void preloadStations(Iterable<String> stationIds) {
    final toAdd = <String>[];
    final now = DateTime.now();
    for (final id in stationIds) {
      final trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      final cached = stationObservationMapNotifier.value[trimmed];
      if (cached != null &&
          cached.observedAt != null &&
          now.difference(cached.observedAt!) < const Duration(minutes: 5)) {
        continue;
      }
      if (!_pendingObservationFetches.contains(trimmed) &&
          !_prefetchQueue.contains(trimmed)) {
        toAdd.add(trimmed);
      }
    }
    if (toAdd.isNotEmpty) {
      _prefetchQueue.insertAll(0, toAdd);
      _startBackgroundPrefetchWorker();
    }
  }

  static void _startBackgroundPrefetchWorker() {
    if (_isWorkerActive) return;
    _isWorkerActive = true;
    _sharedWorkerClient ??= http.Client();
    _processPrefetchQueue();
  }

  static Future<void> _processPrefetchQueue() async {
    const int maxConcurrent = 4;
    while (_prefetchQueue.isNotEmpty) {
      final batch = <String>[];
      while (batch.length < maxConcurrent && _prefetchQueue.isNotEmpty) {
        final id = _prefetchQueue.removeAt(0);
        if (_pendingObservationFetches.add(id)) {
          batch.add(id);
        }
      }
      if (batch.isEmpty) break;

      await Future.wait(
        batch.map((id) async {
          try {
            final response = await (_sharedWorkerClient ?? http.Client())
                .get(
                  Uri.parse('$_observationBaseUrl$id'),
                  headers: _requestHeaders,
                )
                .timeout(const Duration(seconds: 8));
            if (response.statusCode == 200) {
              final decoded = jsonDecode(utf8.decode(response.bodyBytes));
              if (decoded is Map) {
                final fallbackStation = CmaWeatherStation(
                  id: id,
                  name: '',
                  latitude: 0,
                  longitude: 0,
                );
                final observation = cmaObservationFromJson(
                  Map<String, dynamic>.from(decoded),
                  fallbackStation,
                );
                if (observation != null) {
                  _batchBuffer[id] = observation;
                  _scheduleBatchFlush();
                }
              }
            }
          } catch (_) {
            // 后台预加载忽略网络偶发抖动
          } finally {
            _pendingObservationFetches.remove(id);
          }
        }),
      );
      // 微小延时让出事件循环，保障主线程 UI 60fps 丝滑渲染
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    _isWorkerActive = false;
  }

  static void _scheduleBatchFlush() {
    _batchFlushTimer?.cancel();
    _batchFlushTimer = Timer(const Duration(milliseconds: 250), () {
      if (_batchBuffer.isEmpty) return;
      final nextMap = Map<String, CmaLocalWeatherObservation>.from(
        stationObservationMapNotifier.value,
      );
      nextMap.addAll(_batchBuffer);
      _batchBuffer.clear();
      stationObservationMapNotifier.value = Map.unmodifiable(nextMap);
    });
  }

  /// 异步按需拉取指定测站的完整实测数据（带节流与去重）
  static Future<CmaLocalWeatherObservation?> fetchStationObservation(
    String stationId, {
    http.Client? client,
  }) async {
    final id = stationId.trim();
    if (id.isEmpty) return null;
    final cached = stationObservationMapNotifier.value[id];
    if (cached != null) {
      final updateTime = cached.observedAt;
      if (updateTime != null &&
          DateTime.now().difference(updateTime) < const Duration(minutes: 5)) {
        return cached;
      }
    }
    preloadStations([id]);
    return cached;
  }

  /// 确保全国气象站数据已加载，避免重复请求
  static Future<void> ensureStationDirectoryLoaded({
    http.Client? client,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force &&
        stationDirectoryNotifier.value.isNotEmpty &&
        _lastDirectoryFetchTime != null &&
        now.difference(_lastDirectoryFetchTime!) < const Duration(minutes: 10)) {
      return;
    }
    final c = client ?? http.Client();
    try {
      final response = await c
          .get(Uri.parse(_stationDirectoryUrl), headers: _requestHeaders)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && _cmaInt(decoded['code']) == 0) {
          final data = decoded['data'];
          if (data is Map && data['city'] is List) {
            final list = cmaStationSummariesFromRows(data['city'] as List);
            if (list.isNotEmpty) {
              stationDirectoryNotifier.value = list;
              _lastDirectoryFetchTime = DateTime.now();
              debugPrint(
                '[CMAWeather] loaded ${list.length} station summaries for map/sidebar',
              );
              // 自动在后台启动全国降雨站的高精度预加载，用户操作前已就绪
              final rainStationIds = list
                  .where((s) => s.isRaining)
                  .take(40)
                  .map((s) => s.id);
              preloadStations(rainStationIds);
            }
          }
        }
      }
    } catch (error) {
      debugPrint('[CMAWeather] ensureStationDirectoryLoaded failed: $error');
    } finally {
      if (client == null) {
        c.close();
      }
    }
  }

  final http.Client _client;
  final ValueNotifier<CmaLocalWeatherState> stateNotifier =
      ValueNotifier<CmaLocalWeatherState>(const CmaLocalWeatherState());

  /// 接收 Android 前台服务已经完成请求和解析的状态快照。
  void ingestExternalState(CmaLocalWeatherState state) {
    stateNotifier.value = state;
  }

  Timer? _timer;
  CmaWeatherStation? _station;
  double? _anchorLatitude;
  double? _anchorLongitude;
  final Set<String> _activeObservationRequests = <String>{};
  bool _disposed = false;
  int _locationRevision = 0;

  Future<void> startForLocation(double latitude, double longitude) async {
    if (_disposed ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      clearLocation();
      return;
    }

    final previousLat = _anchorLatitude;
    final previousLng = _anchorLongitude;
    if (_station != null && previousLat != null && previousLng != null) {
      final moved = QuakeCalculator.haversineDistance(
        previousLat,
        previousLng,
        latitude,
        longitude,
      );
      if (moved <= _stationCacheAnchorRadiusKm) {
        if (stateNotifier.value.observation == null) {
          await refreshNow();
        }
        return;
      }
    }

    final revision = ++_locationRevision;
    _timer?.cancel();
    _timer = null;
    _station = null;
    _anchorLatitude = latitude;
    _anchorLongitude = longitude;
    stateNotifier.value = CmaLocalWeatherState(
      status: CmaLocalWeatherStatus.resolvingStation,
    );

    final station =
        await _cachedStation(latitude, longitude) ??
        await _fetchNearestStation(latitude, longitude);
    if (_disposed || revision != _locationRevision) return;
    if (station == null) {
      _station = null;
      stateNotifier.value = CmaLocalWeatherState(
        status: CmaLocalWeatherStatus.failed,
      );
      _timer = Timer(
        refreshInterval,
        () => unawaited(startForLocation(latitude, longitude)),
      );
      return;
    }

    _station = station;
    await _saveStationCache(latitude, longitude, station);
    if (_disposed || revision != _locationRevision) return;
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refreshNow()));
    await refreshNow();
  }

  void clearLocation() {
    if (_disposed) return;
    _locationRevision++;
    _timer?.cancel();
    _timer = null;
    _station = null;
    _anchorLatitude = null;
    _anchorLongitude = null;
    stateNotifier.value = const CmaLocalWeatherState(
      status: CmaLocalWeatherStatus.noLocation,
    );
  }

  void pause() {
    if (_disposed) return;
    _locationRevision++;
    _timer?.cancel();
    _timer = null;
    _station = null;
    _anchorLatitude = null;
    _anchorLongitude = null;
    stateNotifier.value = const CmaLocalWeatherState();
  }

  Future<void> refreshNow() async {
    final station = _station;
    if (_disposed || station == null) return;
    final revision = _locationRevision;
    final requestKey = '$revision:${station.id}';
    if (!_activeObservationRequests.add(requestKey)) return;
    final previous = stateNotifier.value.observation;
    stateNotifier.value = CmaLocalWeatherState(
      status: previous == null
          ? CmaLocalWeatherStatus.loading
          : CmaLocalWeatherStatus.ready,
      station: station,
      observation: previous,
    );

    try {
      final response = await _client
          .get(
            Uri.parse('$_observationBaseUrl${station.id}'),
            headers: _requestHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException('response is not map');
      final observation = cmaObservationFromJson(
        Map<String, dynamic>.from(decoded),
        station,
      );
      if (observation == null) {
        throw const FormatException('invalid observation payload');
      }
      if (_disposed ||
          revision != _locationRevision ||
          _station?.id != station.id) {
        return;
      }
      final nextObsMap = Map<String, CmaLocalWeatherObservation>.from(
        stationObservationMapNotifier.value,
      );
      nextObsMap[station.id] = observation;
      stationObservationMapNotifier.value = Map.unmodifiable(nextObsMap);

      stateNotifier.value = CmaLocalWeatherState(
        status: CmaLocalWeatherStatus.ready,
        station: observation.station,
        observation: observation,
      );
    } catch (error) {
      debugPrint('[CMAWeather] observation failed: $error');
      if (_disposed ||
          revision != _locationRevision ||
          _station?.id != station.id) {
        return;
      }
      // 优雅降级：若单站详细接口失败，优先从已加载的全国测站概况构造基础实况，避免卡片展示为暂不可用
      CmaLocalWeatherObservation? fallbackObs = previous;
      if (fallbackObs == null) {
        final matches = stationDirectoryNotifier.value.where((s) => s.id == station.id);
        if (matches.isNotEmpty) {
          final summary = matches.first;
          fallbackObs = CmaLocalWeatherObservation(
            station: station,
            locationPath: summary.name,
            precipitation: null,
            temperature: summary.temperature,
            pressure: null,
            humidity: null,
            windDirection: summary.windDirection,
            windDirectionDegree: null,
            windSpeed: null,
            windScale: summary.windScale,
            feelsLike: null,
            observedAt: DateTime.now(),
          );
        }
      }

      stateNotifier.value = CmaLocalWeatherState(
        status: fallbackObs == null
            ? CmaLocalWeatherStatus.failed
            : CmaLocalWeatherStatus.ready,
        station: station,
        observation: fallbackObs,
      );
    } finally {
      _activeObservationRequests.remove(requestKey);
    }
  }

  Future<CmaWeatherStation?> _fetchNearestStation(
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await _client
          .get(Uri.parse(_stationDirectoryUrl), headers: _requestHeaders)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || _cmaInt(decoded['code']) != 0) return null;
      final data = decoded['data'];
      if (data is! Map || data['city'] is! List) return null;
      final cityList = data['city'] as List;
      final summaries = cmaStationSummariesFromRows(cityList);
      if (summaries.isNotEmpty) {
        stationDirectoryNotifier.value = summaries;
        _lastDirectoryFetchTime = DateTime.now();
      }
      final station = cmaNearestStationFromRows(
        cityList,
        latitude: latitude,
        longitude: longitude,
      );
      if (station != null) {
        debugPrint(
          '[CMAWeather] nearest station: ${station.name}(${station.id})',
        );
      }
      return station;
    } catch (error) {
      debugPrint('[CMAWeather] station lookup failed: $error');
      return null;
    }
  }

  Future<CmaWeatherStation?> _cachedStation(
    double latitude,
    double longitude,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final anchorLat = prefs.getDouble(_cacheAnchorLatKey);
    final anchorLng = prefs.getDouble(_cacheAnchorLngKey);
    final stationId = prefs.getString(_cacheStationIdKey)?.trim() ?? '';
    final stationName = prefs.getString(_cacheStationNameKey)?.trim() ?? '';
    final stationLat = prefs.getDouble(_cacheStationLatKey);
    final stationLng = prefs.getDouble(_cacheStationLngKey);
    if (anchorLat == null ||
        anchorLng == null ||
        stationLat == null ||
        stationLng == null ||
        !RegExp(r'^[A-Za-z0-9_-]{3,16}$').hasMatch(stationId) ||
        stationName.isEmpty) {
      return null;
    }

    final moved = QuakeCalculator.haversineDistance(
      anchorLat,
      anchorLng,
      latitude,
      longitude,
    );
    if (moved > _stationCacheAnchorRadiusKm) return null;
    return CmaWeatherStation(
      id: stationId,
      name: stationName,
      latitude: stationLat,
      longitude: stationLng,
    );
  }

  Future<void> _saveStationCache(
    double latitude,
    double longitude,
    CmaWeatherStation station,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble(_cacheAnchorLatKey, latitude),
      prefs.setDouble(_cacheAnchorLngKey, longitude),
      prefs.setString(_cacheStationIdKey, station.id),
      prefs.setString(_cacheStationNameKey, station.name),
      prefs.setDouble(_cacheStationLatKey, station.latitude),
      prefs.setDouble(_cacheStationLngKey, station.longitude),
    ]);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _locationRevision++;
    _timer?.cancel();
    _timer = null;
    _client.close();
    stateNotifier.dispose();
  }
}
