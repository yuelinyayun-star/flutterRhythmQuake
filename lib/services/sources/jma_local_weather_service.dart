import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/calculator.dart';
import '../../models/weather_alarm.dart';

enum JmaLocalWeatherStatus {
  idle,
  noLocation,
  resolvingStation,
  loading,
  ready,
  failed,
}

class JmaAmedasStation {
  const JmaAmedasStation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.altitude,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double? altitude;
}

class JmaWeatherAlarm {
  const JmaWeatherAlarm({
    required this.code,
    required this.label,
    required this.status,
    required this.severityRank,
  });

  final String code;
  final String label;
  final String status;
  final int severityRank;

  String get displayText => label;
}

class JmaLocalWeatherObservation {
  const JmaLocalWeatherObservation({
    required this.station,
    required this.locationPath,
    required this.precipitation,
    required this.precipitation10m,
    required this.temperature,
    required this.pressure,
    required this.humidity,
    required this.windDirection,
    required this.windDirectionDegree,
    required this.windSpeed,
    required this.visibility,
    required this.observedAt,
    this.forecastSummary = '',
    this.alarms = const [],
  });

  final JmaAmedasStation station;
  final String locationPath;
  final double? precipitation;
  final double? precipitation10m;
  final double? temperature;
  final double? pressure;
  final double? humidity;
  final String windDirection;
  final double? windDirectionDegree;
  final double? windSpeed;
  final double? visibility;
  final DateTime? observedAt;
  final String forecastSummary;
  final List<JmaWeatherAlarm> alarms;
}

class JmaLocalWeatherState {
  const JmaLocalWeatherState({
    this.status = JmaLocalWeatherStatus.idle,
    this.station,
    this.observation,
  });

  final JmaLocalWeatherStatus status;
  final JmaAmedasStation? station;
  final JmaLocalWeatherObservation? observation;
}

@visibleForTesting
double? jmaAmedasCoordinate(Object? raw) {
  if (raw is! List || raw.length < 2) return null;
  final degrees = _jmaDouble(raw[0]);
  final minutes = _jmaDouble(raw[1]);
  if (degrees == null || minutes == null) return null;
  final value = degrees + (minutes / 60.0);
  if (!value.isFinite) return null;
  return value;
}

@visibleForTesting
JmaAmedasStation? jmaAmedasStationFromEntry(
  String id,
  Map<String, dynamic> raw,
) {
  final lat = jmaAmedasCoordinate(raw['lat']);
  final lon = jmaAmedasCoordinate(raw['lon']);
  final name = raw['kjName']?.toString().trim() ?? '';
  if (lat == null ||
      lon == null ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180 ||
      name.isEmpty) {
    return null;
  }
  return JmaAmedasStation(
    id: id,
    name: name,
    latitude: lat,
    longitude: lon,
    altitude: _jmaDouble(raw['alt']),
  );
}

@visibleForTesting
JmaAmedasStation? jmaNearestAmedasStation(
  Map<String, dynamic> table, {
  required double latitude,
  required double longitude,
}) {
  JmaAmedasStation? nearest;
  var nearestDistance = double.infinity;

  for (final entry in table.entries) {
    if (entry.value is! Map) continue;
    final station = jmaAmedasStationFromEntry(
      entry.key,
      Map<String, dynamic>.from(entry.value as Map),
    );
    if (station == null) continue;
    final distance = QuakeCalculator.haversineDistance(
      latitude,
      longitude,
      station.latitude,
      station.longitude,
    );
    if (distance >= nearestDistance) continue;
    nearestDistance = distance;
    nearest = station;
  }

  return nearest;
}

@visibleForTesting
String jmaOfficeCodeFromLatLng(double latitude, double longitude) {
  String? bestCode;
  var bestDistance = double.infinity;
  for (final entry in _jmaOfficeCenters.entries) {
    final distance = QuakeCalculator.haversineDistance(
      latitude,
      longitude,
      entry.value.$1,
      entry.value.$2,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestCode = entry.key;
    }
  }
  return bestCode ?? '130000';
}

@visibleForTesting
double? jmaAmedasMetricValue(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final value = _jmaDouble(raw.first);
  if (value == null) return null;
  if (raw.length >= 2) {
    final flag = _jmaInt(raw[1]);
    if (flag == 1) return null;
  }
  return value;
}

@visibleForTesting
int? jmaAmedasDirectionCode(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final value = _jmaInt(raw.first);
  if (value == null || value <= 0) return null;
  if (raw.length >= 2 && _jmaInt(raw[1]) == 1) return null;
  return value;
}

@visibleForTesting
String jmaWindDirectionLabel(int? code) {
  if (code == null || code <= 0 || code > 16) return '';
  const labels = [
    '北',
    '北北东',
    '北东',
    '东北东',
    '东',
    '东南东',
    '南东',
    '南南东',
    '南',
    '南南西',
    '南西',
    '西南西',
    '西',
    '西北西',
    '北西',
    '北北西',
  ];
  return labels[code - 1];
}

@visibleForTesting
double? jmaWindDirectionDegree(int? code) {
  if (code == null || code <= 0 || code > 16) return null;
  return ((code - 1) * 22.5) % 360;
}

@visibleForTesting
DateTime jmaJstWallClock(DateTime time) {
  final jst = time.toUtc().add(const Duration(hours: 9));
  return DateTime(
    jst.year,
    jst.month,
    jst.day,
    jst.hour,
    jst.minute,
    jst.second,
  );
}

@visibleForTesting
DateTime? jmaParseLatestTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final hasExplicitZone = RegExp(
    r'(?:Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(text);
  if (hasExplicitZone || parsed.isUtc) {
    return jmaJstWallClock(parsed);
  }
  return DateTime(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  );
}

@visibleForTesting
String jmaPointBlockKey(DateTime time) {
  final hourBlock = (time.hour ~/ 3) * 3;
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  final h = hourBlock.toString().padLeft(2, '0');
  return '$y$m${d}_$h';
}

@visibleForTesting
String jmaMapTimestamp(DateTime time) {
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  final h = time.hour.toString().padLeft(2, '0');
  final min = (time.minute ~/ 10 * 10).toString().padLeft(2, '0');
  return '$y$m$d$h$min'
      '00';
}

@visibleForTesting
DateTime? jmaObservationTimestamp(String key) {
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$',
  ).firstMatch(key);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

@visibleForTesting
Map<String, dynamic>? jmaSelectLatestPointEntry(Map<String, dynamic> raw) {
  Map<String, dynamic>? latest;
  DateTime? latestTime;
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final time = jmaObservationTimestamp(entry.key);
    if (time == null) continue;
    if (latestTime == null || time.isAfter(latestTime)) {
      latestTime = time;
      latest = Map<String, dynamic>.from(value);
      latest['_timestamp'] = entry.key;
    }
  }
  return latest;
}

@visibleForTesting
JmaLocalWeatherObservation? jmaObservationFromPointJson(
  Map<String, dynamic> raw,
  JmaAmedasStation station, {
  String locationPath = '',
  String forecastSummary = '',
  List<JmaWeatherAlarm> alarms = const [],
}) {
  final latest = jmaSelectLatestPointEntry(raw);
  if (latest == null) return null;

  final timestampKey = latest.remove('_timestamp')?.toString() ?? '';
  final observedAt = jmaObservationTimestamp(timestampKey);
  final directionCode = jmaAmedasDirectionCode(latest['windDirection']);

  return JmaLocalWeatherObservation(
    station: station,
    locationPath: locationPath.isEmpty ? station.name : locationPath,
    precipitation: jmaAmedasMetricValue(latest['precipitation1h']),
    precipitation10m: jmaAmedasMetricValue(latest['precipitation10m']),
    temperature: jmaAmedasMetricValue(latest['temp']),
    pressure: jmaAmedasMetricValue(latest['pressure']),
    humidity: jmaAmedasMetricValue(latest['humidity']),
    windDirection: jmaWindDirectionLabel(directionCode),
    windDirectionDegree: jmaWindDirectionDegree(directionCode),
    windSpeed: jmaAmedasMetricValue(latest['wind']),
    visibility: jmaAmedasMetricValue(latest['visibility']),
    observedAt: observedAt,
    forecastSummary: forecastSummary,
    alarms: alarms,
  );
}

@visibleForTesting
JmaLocalWeatherObservation? jmaObservationFromMapEntry(
  Map<String, dynamic> raw,
  JmaAmedasStation station, {
  required DateTime observedAt,
  String locationPath = '',
  String forecastSummary = '',
  List<JmaWeatherAlarm> alarms = const [],
}) {
  final directionCode = jmaAmedasDirectionCode(raw['windDirection']);
  return JmaLocalWeatherObservation(
    station: station,
    locationPath: locationPath.isEmpty ? station.name : locationPath,
    precipitation: jmaAmedasMetricValue(raw['precipitation1h']),
    precipitation10m: jmaAmedasMetricValue(raw['precipitation10m']),
    temperature: jmaAmedasMetricValue(raw['temp']),
    pressure: jmaAmedasMetricValue(raw['pressure']),
    humidity: jmaAmedasMetricValue(raw['humidity']),
    windDirection: jmaWindDirectionLabel(directionCode),
    windDirectionDegree: jmaWindDirectionDegree(directionCode),
    windSpeed: jmaAmedasMetricValue(raw['wind']),
    visibility: jmaAmedasMetricValue(raw['visibility']),
    observedAt: observedAt,
    forecastSummary: forecastSummary,
    alarms: alarms,
  );
}

@visibleForTesting
int jmaWarningSeverityRank(String code) {
  switch (code) {
    case '32':
    case '33':
    case '35':
    case '36':
    case '37':
    case '38':
    case '39':
    case '43':
    case '48':
    case '49':
      return 4;
    case '02':
    case '03':
    case '04':
    case '05':
    case '06':
    case '07':
    case '08':
      return 3;
    default:
      return 2;
  }
}

@visibleForTesting
String jmaWarningLabel(String code) {
  return _jmaWarningLabels[code] ?? '気象警報・注意報($code)';
}

@visibleForTesting
String jmaWarningLevelCode(String code) {
  switch (jmaWarningSeverityRank(code)) {
    case 4:
      return '04';
    case 3:
      return '03';
    default:
      return '02';
  }
}

@visibleForTesting
List<JmaWeatherAlarm> jmaWarningsFromOfficeJson(Map<String, dynamic> raw) {
  final alarms = <JmaWeatherAlarm>[];
  final seen = <String>{};
  final areaTypes = raw['areaTypes'];
  if (areaTypes is! List) return const [];

  for (final areaType in areaTypes) {
    if (areaType is! Map) continue;
    final areas = areaType['areas'];
    if (areas is! List) continue;
    for (final area in areas) {
      if (area is! Map) continue;
      final warnings = area['warnings'];
      if (warnings is! List) continue;
      for (final warning in warnings) {
        if (warning is! Map) continue;
        final status = warning['status']?.toString().trim() ?? '';
        if (status.contains('なし') || status.contains('解除')) continue;
        final code = warning['code']?.toString().trim() ?? '';
        if (code.isEmpty || !seen.add(code)) continue;
        alarms.add(
          JmaWeatherAlarm(
            code: code,
            label: jmaWarningLabel(code),
            status: status.isEmpty ? '発表中' : status,
            severityRank: jmaWarningSeverityRank(code),
          ),
        );
      }
    }
  }

  alarms.sort((a, b) => b.severityRank.compareTo(a.severityRank));
  return List<JmaWeatherAlarm>.unmodifiable(alarms);
}

@visibleForTesting
String? jmaForecastSummaryFromOverview(Map<String, dynamic> raw) {
  final text = raw['text']?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return null;
  return lines.length <= 2 ? lines.join(' ') : lines[1];
}

@visibleForTesting
WeatherAlarm? jmaBestWeatherAlarmForDisplay(
  JmaLocalWeatherObservation? observation,
) {
  if (observation == null || observation.alarms.isEmpty) return null;
  final alarm = observation.alarms.first;
  final headline = '${observation.locationPath} ${alarm.displayText}';
  return WeatherAlarm(
    id: 'jma:${observation.station.id}:${alarm.code}',
    headline: headline,
    effective: _jmaEffectiveText(observation.observedAt),
    description: observation.station.name,
    latitude: observation.station.latitude,
    longitude: observation.station.longitude,
    type: '11${jmaWarningLevelCode(alarm.code)}',
    source: WeatherAlarmSource.jmaLocal,
  );
}

String _jmaEffectiveText(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

double? _jmaDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _jmaInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

const Map<String, (double, double)> _jmaOfficeCenters = {
  '011000': (43.77, 142.36),
  '012000': (43.98, 142.48),
  '013000': (43.80, 143.90),
  '014100': (43.33, 144.60),
  '015000': (42.92, 141.61),
  '016000': (43.06, 141.35),
  '017000': (41.77, 140.73),
  '020000': (40.82, 140.74),
  '030000': (39.70, 141.15),
  '040000': (38.27, 140.87),
  '050000': (39.72, 140.10),
  '060000': (38.24, 140.36),
  '070000': (37.75, 140.47),
  '080000': (36.34, 140.45),
  '090000': (36.57, 139.88),
  '100000': (36.39, 139.06),
  '110000': (35.86, 139.65),
  '120000': (35.61, 140.12),
  '130000': (35.69, 139.69),
  '140000': (35.45, 139.64),
  '150000': (37.90, 139.02),
  '160000': (36.70, 137.21),
  '170000': (36.59, 136.63),
  '180000': (36.07, 136.22),
  '190000': (35.66, 138.57),
  '200000': (36.23, 138.18),
  '210000': (35.39, 136.72),
  '220000': (34.98, 138.38),
  '230000': (35.18, 136.91),
  '240000': (34.73, 136.51),
  '250000': (35.00, 135.87),
  '260000': (35.02, 135.76),
  '270000': (34.69, 135.50),
  '280000': (34.69, 135.18),
  '290000': (34.69, 135.83),
  '300000': (34.23, 135.17),
  '310000': (35.50, 134.24),
  '320000': (35.47, 133.05),
  '330000': (34.66, 133.93),
  '340000': (34.40, 132.46),
  '350000': (33.84, 131.03),
  '360000': (33.56, 133.53),
  '370000': (34.07, 134.56),
  '380000': (33.84, 132.77),
  '390000': (33.56, 133.53),
  '400000': (33.61, 130.42),
  '410000': (33.25, 130.30),
  '420000': (32.75, 129.87),
  '430000': (32.79, 130.74),
  '440000': (31.91, 131.42),
  '450000': (31.56, 130.56),
  '460000': (31.60, 130.56),
  '460040': (28.14, 129.58),
  '471000': (26.21, 127.68),
};

const Map<String, String> _jmaWarningLabels = {
  '02': '暴風雪警報',
  '03': '大雨警報',
  '04': '洪水警報',
  '05': '暴風警報',
  '06': '大雪警報',
  '07': '波浪警報',
  '08': '高潮警報',
  '10': '大雨注意報',
  '12': '大雪注意報',
  '13': '風雪注意報',
  '14': '雷注意報',
  '15': '強風注意報',
  '16': '波浪注意報',
  '17': '融雪注意報',
  '18': '洪水注意報',
  '19': '高潮注意報',
  '20': '濃霧注意報',
  '21': '乾燥注意報',
  '22': 'なだれ注意報',
  '23': '低温注意報',
  '24': '霜注意報',
  '25': '着氷注意報',
  '26': '着雪注意報',
  '29': '土砂災害注意報',
  '32': '暴風雪特別警報',
  '33': '大雨特別警報',
  '35': '暴風特別警報',
  '36': '大雪特別警報',
  '37': '波浪特別警報',
  '38': '高潮特別警報',
  '39': '土砂災害特別警報',
  '43': '大雨危険警報',
  '48': '高潮危険警報',
  '49': '土砂災害危険警報',
};

class JmaLocalWeatherService {
  JmaLocalWeatherService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://www.jma.go.jp/bosai';
  static const Duration refreshInterval = Duration(minutes: 10);
  static const double _stationCacheAnchorRadiusKm = 8;

  static const String _cacheAnchorLatKey = 'jma_weather_anchor_lat';
  static const String _cacheAnchorLngKey = 'jma_weather_anchor_lng';
  static const String _cacheStationIdKey = 'jma_weather_station_id';
  static const String _cacheStationNameKey = 'jma_weather_station_name';
  static const String _cacheStationLatKey = 'jma_weather_station_lat';
  static const String _cacheStationLngKey = 'jma_weather_station_lng';

  static const Map<String, String> _headers = {
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://www.jma.go.jp/',
    'User-Agent': 'flutterrhythmquake/1.0',
  };
  static Map<String, String> get _requestHeaders =>
      kIsWeb ? const {'Accept': 'application/json, text/plain, */*'} : _headers;

  final http.Client _client;
  final ValueNotifier<JmaLocalWeatherState> stateNotifier =
      ValueNotifier<JmaLocalWeatherState>(const JmaLocalWeatherState());

  /// 接收 Android 前台服务已经完成请求和解析的状态快照。
  void ingestExternalState(JmaLocalWeatherState state) {
    stateNotifier.value = state;
  }

  Timer? _timer;
  JmaAmedasStation? _station;
  double? _anchorLatitude;
  double? _anchorLongitude;
  Map<String, dynamic>? _amedasTable;
  Future<Map<String, dynamic>?>? _amedasTableLoading;
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
    stateNotifier.value = JmaLocalWeatherState(
      status: JmaLocalWeatherStatus.resolvingStation,
    );

    var station = await _cachedStation(latitude, longitude);
    if (station == null) {
      final table = await _loadAmedasTable();
      if (_disposed || revision != _locationRevision) return;
      if (table == null) {
        stateNotifier.value = const JmaLocalWeatherState(
          status: JmaLocalWeatherStatus.failed,
        );
        _timer = Timer(
          refreshInterval,
          () => unawaited(startForLocation(latitude, longitude)),
        );
        return;
      }
      station = jmaNearestAmedasStation(
        table,
        latitude: latitude,
        longitude: longitude,
      );
    }
    if (_disposed || revision != _locationRevision) return;
    if (station == null) {
      stateNotifier.value = const JmaLocalWeatherState(
        status: JmaLocalWeatherStatus.failed,
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
    stateNotifier.value = const JmaLocalWeatherState(
      status: JmaLocalWeatherStatus.noLocation,
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
    stateNotifier.value = const JmaLocalWeatherState();
  }

  Future<void> refreshNow() async {
    final station = _station;
    final anchorLat = _anchorLatitude;
    final anchorLng = _anchorLongitude;
    if (_disposed ||
        station == null ||
        anchorLat == null ||
        anchorLng == null) {
      return;
    }

    final revision = _locationRevision;
    final requestKey = '$revision:${station.id}';
    if (!_activeObservationRequests.add(requestKey)) return;
    final previous = stateNotifier.value.observation;
    stateNotifier.value = JmaLocalWeatherState(
      status: previous == null
          ? JmaLocalWeatherStatus.loading
          : JmaLocalWeatherStatus.ready,
      station: station,
      observation: previous,
    );

    try {
      final latestTimeText = await _fetchText(
        '$_baseUrl/amedas/data/latest_time.txt',
      );
      final latestTime = jmaParseLatestTime(latestTimeText);
      if (latestTime == null) {
        throw const FormatException('invalid latest_time');
      }

      final officeCode = jmaOfficeCodeFromLatLng(anchorLat, anchorLng);
      final pointKey = jmaPointBlockKey(latestTime);
      final results = await Future.wait<Object?>([
        _fetchJson('$_baseUrl/amedas/data/point/${station.id}/$pointKey.json'),
        _fetchJson('$_baseUrl/warning/data/warning/$officeCode.json'),
        _fetchJson(
          '$_baseUrl/forecast/data/overview_forecast/$officeCode.json',
        ),
      ]);

      if (_disposed ||
          revision != _locationRevision ||
          _station?.id != station.id) {
        return;
      }

      Map<String, dynamic>? pointRaw = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : null;
      if (pointRaw == null || pointRaw.isEmpty) {
        final mapRaw = await _fetchJson(
          '$_baseUrl/amedas/data/map/${jmaMapTimestamp(latestTime)}.json',
        );
        if (mapRaw is Map && mapRaw[station.id] is Map) {
          final mapEntry = Map<String, dynamic>.from(mapRaw[station.id] as Map);
          final alarms = results[1] is Map
              ? jmaWarningsFromOfficeJson(
                  Map<String, dynamic>.from(results[1] as Map),
                )
              : const <JmaWeatherAlarm>[];
          final forecastSummary = results[2] is Map
              ? jmaForecastSummaryFromOverview(
                      Map<String, dynamic>.from(results[2] as Map),
                    ) ??
                    ''
              : '';
          final observation = jmaObservationFromMapEntry(
            mapEntry,
            station,
            observedAt: latestTime,
            locationPath: station.name,
            forecastSummary: forecastSummary,
            alarms: alarms,
          );
          if (observation == null) {
            throw const FormatException('invalid map observation');
          }
          stateNotifier.value = JmaLocalWeatherState(
            status: JmaLocalWeatherStatus.ready,
            station: observation.station,
            observation: observation,
          );
          return;
        }
        throw const FormatException('invalid point/map observation');
      }

      final alarms = results[1] is Map
          ? jmaWarningsFromOfficeJson(
              Map<String, dynamic>.from(results[1] as Map),
            )
          : const <JmaWeatherAlarm>[];
      final forecastSummary = results[2] is Map
          ? jmaForecastSummaryFromOverview(
                  Map<String, dynamic>.from(results[2] as Map),
                ) ??
                ''
          : '';
      final observation = jmaObservationFromPointJson(
        pointRaw,
        station,
        locationPath: station.name,
        forecastSummary: forecastSummary,
        alarms: alarms,
      );
      if (observation == null) {
        throw const FormatException('invalid point observation');
      }

      stateNotifier.value = JmaLocalWeatherState(
        status: JmaLocalWeatherStatus.ready,
        station: observation.station,
        observation: observation,
      );
    } catch (error) {
      debugPrint('[JMAWeather] observation failed: $error');
      if (_disposed ||
          revision != _locationRevision ||
          _station?.id != station.id) {
        return;
      }
      stateNotifier.value = JmaLocalWeatherState(
        status: previous == null
            ? JmaLocalWeatherStatus.failed
            : JmaLocalWeatherStatus.ready,
        station: station,
        observation: previous,
      );
    } finally {
      _activeObservationRequests.remove(requestKey);
    }
  }

  Future<Map<String, dynamic>?> _loadAmedasTable() async {
    if (_amedasTable != null) return _amedasTable;
    final inFlight = _amedasTableLoading;
    if (inFlight != null) return inFlight;
    final request = _fetchJson('$_baseUrl/amedas/const/amedastable.json').then((
      raw,
    ) {
      if (raw is! Map) return null;
      return Map<String, dynamic>.from(raw);
    });
    _amedasTableLoading = request;
    try {
      final table = await request;
      if (table == null) return null;
      _amedasTable = table;
      return _amedasTable;
    } catch (error) {
      debugPrint('[JMAWeather] amedas table failed: $error');
      return null;
    } finally {
      _amedasTableLoading = null;
    }
  }

  Future<Object?> _fetchJson(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: _requestHeaders)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded;
  }

  Future<String> _fetchText(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: _requestHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<JmaAmedasStation?> _cachedStation(
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
        stationId.isEmpty ||
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
    return JmaAmedasStation(
      id: stationId,
      name: stationName,
      latitude: stationLat,
      longitude: stationLng,
    );
  }

  Future<void> _saveStationCache(
    double latitude,
    double longitude,
    JmaAmedasStation station,
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
