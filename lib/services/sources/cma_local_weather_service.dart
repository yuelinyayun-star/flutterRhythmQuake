import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/calculator.dart';

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
    if (!RegExp(r'^\d{5}$').hasMatch(id) ||
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
  );
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
  static const Duration refreshInterval = Duration(minutes: 10);
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

  final http.Client _client;
  final ValueNotifier<CmaLocalWeatherState> stateNotifier =
      ValueNotifier<CmaLocalWeatherState>(const CmaLocalWeatherState());

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
      stateNotifier.value = CmaLocalWeatherState(
        status: previous == null
            ? CmaLocalWeatherStatus.failed
            : CmaLocalWeatherStatus.ready,
        station: station,
        observation: previous,
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
      final station = cmaNearestStationFromRows(
        data['city'] as List,
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
        !RegExp(r'^\d{5}$').hasMatch(stationId) ||
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
