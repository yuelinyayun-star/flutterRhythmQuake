import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'sources/cwa_station_service.dart';
import 'sources/kma_monitor.dart';
import 'sources/nied_monitor.dart';
import 'sources/nied_gif_observation.dart';
import 'sources/palert_service.dart';
import 'sources/palert_detection_grid.dart';
import 'sources/shake_detection_service.dart';
import 'sources/seisjs_service.dart';
import 'sources/lpgm_monitor_service.dart';
import 'sources/fdsn_station_service.dart';
import 'sources/fdsn_motion_service.dart';
import 'sources/fan_radar_service.dart';
import 'sources/fan_satellite_cloud_service.dart';
import 'sources/jma_radar_service.dart';
import '../models/jma_volcano_site.dart';
import '../models/snet_station.dart';
import 'sources/cma_local_weather_service.dart';
import 'sources/jma_local_weather_service.dart';

/// Compact, isolate-safe snapshots for station inputs owned by the Android
/// foreground service. P-Alert also carries its confirmed detection grids;
/// the UI owns rendering and camera focus, without reclassifying station data.
class ForegroundStationPayload {
  const ForegroundStationPayload._();

  static Map<String, dynamic> nied(
    List<NiedStation> stations, {
    String? source,
  }) => {
    'kind': 'nied',
    if (source != null) 'source': source,
    'stations': stations.map(_niedStation).toList(growable: false),
  };

  static Map<String, dynamic> kma(
    List<KmaStation> stations, {
    DateTime? dataTime,
  }) => {
    'kind': 'kma',
    'dataTime': dataTime?.toIso8601String(),
    'stations': stations.map(_kmaStation).toList(growable: false),
  };

  static Map<String, dynamic> cwa(
    List<CwaStation> stations, {
    DateTime? dataTime,
  }) => {
    'kind': 'cwa',
    'dataTime': dataTime?.toIso8601String(),
    'stations': stations.map(_cwaStation).toList(growable: false),
  };

  static Map<String, dynamic> snet(List<SnetStation> stations) => {
    'kind': 'snet',
    'stations': stations.map(_snetStation).toList(growable: false),
  };

  static Map<String, dynamic> seisjs(
    List<SeisJsStation> stations, {
    DateTime? dataTime,
  }) => {
    'kind': 'seisjs',
    'dataTime': dataTime?.toIso8601String(),
    'stations': stations.map(_seisJsStation).toList(growable: false),
  };

  static Map<String, dynamic> palert(
    List<PAlertStation> stations, {
    DateTime? dataTime,
    DateTime? receivedTime,
    ShakeDetectionSnapshot? detection,
  }) => {
    'kind': 'palert',
    'detectedStationIds': [
      for (final station in detection?.detectedStations ?? <DetectedStationEntry>[])
        station.code,
    ],
    'dataTime': dataTime?.toIso8601String(),
    'receivedTime': receivedTime?.toIso8601String(),
    'detectionGrid': [
      for (final cell in detection?.gridCells.values ?? <NiedDetectionGridCell>[])
        [cell.center.latitude, cell.center.longitude, cell.level],
    ],
    'stations': stations.map(_pAlertStation).toList(growable: false),
  };

  static Set<String> decodePAlertDetectedStationIds(
    Map<String, dynamic> payload, {required DateTime now}
  ) {
    final received = _date(payload['receivedTime']);
    final raw = payload['detectedStationIds'];
    if (received == null || raw is! List ||
        PAlertService.isFrameStale(received, now)) {
      return const {};
    }
    return raw.whereType<String>().where((id) => id.isNotEmpty).toSet();
  }

  static List<PAlertDetectionGridCell> decodePAlertDetection(
    Map<String, dynamic> payload, {
    required DateTime now,
  }) {
    final received = _date(payload['receivedTime']);
    final raw = payload['detectionGrid'];
    if (received == null ||
        raw is! List ||
        PAlertService.isFrameStale(received, now)) {
      return const [];
    }
    return [
      for (final cell in raw)
        if (cell is List &&
            cell.length == 3 &&
            cell[0] is num &&
            cell[1] is num &&
            cell[2] is int &&
            (cell[0] as num).isFinite &&
            (cell[1] as num).isFinite &&
            (cell[0] as num).abs() <= 90 &&
            (cell[1] as num).abs() <= 180 &&
            (cell[2] as int) >= 0 &&
            (cell[2] as int) <= 20)
          PAlertDetectionGridCell(
            center: LatLng(
              (cell[0] as num).toDouble(), (cell[1] as num).toDouble(),
            ),
            level: cell[2] as int,
          ),
    ];
  }

  static DateTime? frameTime(Map<String, dynamic> payload) =>
      _date(payload['dataTime']);

  static Map<String, dynamic> lpgm(LpgmSnapshot snapshot) => {
    'kind': 'lpgm',
    'dataTime': snapshot.dataTime.toIso8601String(),
    'maxSva': snapshot.maxSva,
    'maxClass': snapshot.maxClass,
    'maxRawRgb': snapshot.maxRawRgb,
    'topStations': snapshot.topStations
        .map(
          (station) => {
            'code': station.code,
            'name': station.name,
            'lat': station.coordinate.latitude,
            'lng': station.coordinate.longitude,
            'sva': station.sva,
            'lpgmClass': station.lpgmClass,
          },
        )
        .toList(growable: false),
  };

  static Map<String, dynamic> fdsnStations(
    String source,
    List<FdsnStation> stations,
  ) => {
    'kind': 'fdsnStations',
    'source': source,
    'stations': stations
        .map(
          (station) => {
            'network': station.network,
            'station': station.station,
            'location': station.location,
            'coordinate': _latLng(station.coordinate),
            'elevation': station.elevation,
            'siteName': station.siteName,
            'startTime': station.startTime?.toIso8601String(),
            'endTime': station.endTime?.toIso8601String(),
            'sourceName': station.source,
            'pga': station.pga,
            'pgv': station.pgv,
            'intensity': station.intensity,
            'lastMotionUpdate': station.lastMotionUpdate?.toIso8601String(),
          },
        )
        .toList(growable: false),
  };

  static Map<String, dynamic> fdsnMotion(FdsnMotionSample sample) => {
    'kind': 'fdsnMotion',
    'source': sample.source,
    'network': sample.network,
    'station': sample.station,
    'channel': sample.channel,
    'pga': sample.pga,
    'pgv': sample.pgv,
    'intensity': sample.intensity,
    'active': sample.active,
    'timestamp': sample.timestamp.toIso8601String(),
  };

  static Map<String, dynamic> volcanoSites(List<JmaVolcanoSite> sites) => {
    'kind': 'volcanoSites',
    'sites': sites
        .map(
          (site) => {
            'code': site.code,
            'nameJp': site.nameJp,
            'nameEn': site.nameEn,
            'latitude': site.latitude,
            'longitude': site.longitude,
            'levelOperation': site.levelOperation,
            'alertLevel': site.alertLevel,
            'hasWarning': site.hasWarning,
            'hasRecentInfo': site.hasRecentInfo,
            'hasRecentEruption': site.hasRecentEruption,
            'warningKindCode': site.warningKindCode,
            'warningKindName': site.warningKindName,
            'warningAlarm': site.warningAlarm,
            'warningReportTime': site.warningReportTime?.toIso8601String(),
            'infoHeadTitle': site.infoHeadTitle,
            'infoReportTime': site.infoReportTime?.toIso8601String(),
            'eruptionReportTime': site.eruptionReportTime?.toIso8601String(),
            'hasProvisionalInfo': site.hasProvisionalInfo,
          },
        )
        .toList(growable: false),
  };

  static List<JmaVolcanoSite> decodeVolcanoSites(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeVolcanoSite(Map<String, dynamic>.from(item)))
        .whereType<JmaVolcanoSite>()
        .toList(growable: false);
  }

  static Map<String, dynamic> fanRadar(FanRadarFrame frame) => {
    'kind': 'fanRadar',
    'time': frame.time.toIso8601String(),
    'southWest': _latLng(frame.southWest),
    'northEast': _latLng(frame.northEast),
    'width': frame.width,
    'height': frame.height,
    'imageBytes': frame.imageBytes,
  };

  static Map<String, dynamic> cmaPrecipitation(FanRadarFrame frame) => {
    ...fanRadar(frame),
    'kind': 'cmaPrecipitation',
  };

  static Map<String, dynamic> fanSatellite(FanSatelliteCloudFrame frame) => {
    'kind': 'fanSatellite',
    'time': frame.time.toIso8601String(),
    'southWest': _latLng(frame.southWest),
    'northEast': _latLng(frame.northEast),
    'imageBytes': frame.imageBytes,
  };

  static Map<String, dynamic> jmaRadar(JmaRadarFrame frame) => {
    'kind': 'jmaRadar',
    'basetime': frame.basetime,
    'validtime': frame.validtime,
    'time': frame.time.toIso8601String(),
  };

  static Map<String, dynamic> cmaWeather(CmaLocalWeatherState state) => {
    'kind': 'cmaWeather',
    'status': state.status.name,
    'station': state.station == null
        ? null
        : {
            'id': state.station!.id,
            'name': state.station!.name,
            'latitude': state.station!.latitude,
            'longitude': state.station!.longitude,
          },
    'observation': state.observation == null
        ? null
        : _cmaObservation(state.observation!),
  };

  static Map<String, dynamic> jmaWeather(JmaLocalWeatherState state) => {
    'kind': 'jmaWeather',
    'status': state.status.name,
    'station': state.station == null
        ? null
        : {
            'id': state.station!.id,
            'name': state.station!.name,
            'latitude': state.station!.latitude,
            'longitude': state.station!.longitude,
            'altitude': state.station!.altitude,
          },
    'observation': state.observation == null
        ? null
        : _jmaObservation(state.observation!),
  };

  static CmaLocalWeatherState decodeCmaWeather(Map<String, dynamic> raw) {
    final stationRaw = raw['station'];
    final station = stationRaw is Map
        ? CmaWeatherStation(
            id: stationRaw['id']?.toString() ?? '',
            name: stationRaw['name']?.toString() ?? '',
            latitude: _number(stationRaw['latitude']) ?? 0,
            longitude: _number(stationRaw['longitude']) ?? 0,
          )
        : null;
    final observationRaw = raw['observation'];
    return CmaLocalWeatherState(
      status: _cmaStatus(raw['status']),
      station: station,
      observation: observationRaw is Map
          ? _decodeCmaObservation(Map<String, dynamic>.from(observationRaw))
          : null,
    );
  }

  static JmaLocalWeatherState decodeJmaWeather(Map<String, dynamic> raw) {
    final stationRaw = raw['station'];
    final station = stationRaw is Map
        ? JmaAmedasStation(
            id: stationRaw['id']?.toString() ?? '',
            name: stationRaw['name']?.toString() ?? '',
            latitude: _number(stationRaw['latitude']) ?? 0,
            longitude: _number(stationRaw['longitude']) ?? 0,
            altitude: _number(stationRaw['altitude']),
          )
        : null;
    final observationRaw = raw['observation'];
    return JmaLocalWeatherState(
      status: _jmaStatus(raw['status']),
      station: station,
      observation: observationRaw is Map
          ? _decodeJmaObservation(Map<String, dynamic>.from(observationRaw))
          : null,
    );
  }

  static Map<String, dynamic> _cmaObservation(CmaLocalWeatherObservation o) => {
    'station': {
      'id': o.station.id,
      'name': o.station.name,
      'latitude': o.station.latitude,
      'longitude': o.station.longitude,
    },
    'locationPath': o.locationPath,
    'precipitation': o.precipitation,
    'temperature': o.temperature,
    'pressure': o.pressure,
    'humidity': o.humidity,
    'windDirection': o.windDirection,
    'windDirectionDegree': o.windDirectionDegree,
    'windSpeed': o.windSpeed,
    'windScale': o.windScale,
    'feelsLike': o.feelsLike,
    'observedAt': o.observedAt?.toIso8601String(),
    'alarms': o.alarms
        .map(
          (alarm) => {
            'id': alarm.id,
            'title': alarm.title,
            'signalType': alarm.signalType,
            'signalLevel': alarm.signalLevel,
            'severity': alarm.severity,
            'effective': alarm.effective?.toIso8601String(),
          },
        )
        .toList(growable: false),
  };

  static Map<String, dynamic> _jmaObservation(JmaLocalWeatherObservation o) => {
    'station': {
      'id': o.station.id,
      'name': o.station.name,
      'latitude': o.station.latitude,
      'longitude': o.station.longitude,
      'altitude': o.station.altitude,
    },
    'locationPath': o.locationPath,
    'precipitation': o.precipitation,
    'precipitation10m': o.precipitation10m,
    'temperature': o.temperature,
    'pressure': o.pressure,
    'humidity': o.humidity,
    'windDirection': o.windDirection,
    'windDirectionDegree': o.windDirectionDegree,
    'windSpeed': o.windSpeed,
    'visibility': o.visibility,
    'observedAt': o.observedAt?.toIso8601String(),
    'forecastSummary': o.forecastSummary,
    'alarms': o.alarms
        .map(
          (alarm) => {
            'code': alarm.code,
            'label': alarm.label,
            'status': alarm.status,
            'severityRank': alarm.severityRank,
          },
        )
        .toList(growable: false),
  };

  static CmaLocalWeatherObservation _decodeCmaObservation(
    Map<String, dynamic> raw,
  ) {
    final stationRaw = raw['station'] as Map? ?? const {};
    final station = CmaWeatherStation(
      id: stationRaw['id']?.toString() ?? '',
      name: stationRaw['name']?.toString() ?? '',
      latitude: _number(stationRaw['latitude']) ?? 0,
      longitude: _number(stationRaw['longitude']) ?? 0,
    );
    final alarms = (raw['alarms'] is List ? raw['alarms'] as List : const [])
        .whereType<Map>()
        .map(
          (item) => CmaWeatherAlarm(
            id: item['id']?.toString() ?? '',
            title: item['title']?.toString() ?? '',
            signalType: item['signalType']?.toString() ?? '',
            signalLevel: item['signalLevel']?.toString() ?? '',
            severity: item['severity']?.toString() ?? '',
            effective: _date(item['effective']),
          ),
        )
        .toList(growable: false);
    return CmaLocalWeatherObservation(
      station: station,
      locationPath: raw['locationPath']?.toString() ?? '',
      precipitation: _number(raw['precipitation']),
      temperature: _number(raw['temperature']),
      pressure: _number(raw['pressure']),
      humidity: _number(raw['humidity']),
      windDirection: raw['windDirection']?.toString() ?? '',
      windDirectionDegree: _number(raw['windDirectionDegree']),
      windSpeed: _number(raw['windSpeed']),
      windScale: raw['windScale']?.toString() ?? '',
      feelsLike: _number(raw['feelsLike']),
      observedAt: _date(raw['observedAt']),
      alarms: alarms,
    );
  }

  static JmaLocalWeatherObservation _decodeJmaObservation(
    Map<String, dynamic> raw,
  ) {
    final stationRaw = raw['station'] as Map? ?? const {};
    final station = JmaAmedasStation(
      id: stationRaw['id']?.toString() ?? '',
      name: stationRaw['name']?.toString() ?? '',
      latitude: _number(stationRaw['latitude']) ?? 0,
      longitude: _number(stationRaw['longitude']) ?? 0,
      altitude: _number(stationRaw['altitude']),
    );
    final alarms = (raw['alarms'] is List ? raw['alarms'] as List : const [])
        .whereType<Map>()
        .map(
          (item) => JmaWeatherAlarm(
            code: item['code']?.toString() ?? '',
            label: item['label']?.toString() ?? '',
            status: item['status']?.toString() ?? '',
            severityRank: _int(item['severityRank']) ?? 0,
          ),
        )
        .toList(growable: false);
    return JmaLocalWeatherObservation(
      station: station,
      locationPath: raw['locationPath']?.toString() ?? '',
      precipitation: _number(raw['precipitation']),
      precipitation10m: _number(raw['precipitation10m']),
      temperature: _number(raw['temperature']),
      pressure: _number(raw['pressure']),
      humidity: _number(raw['humidity']),
      windDirection: raw['windDirection']?.toString() ?? '',
      windDirectionDegree: _number(raw['windDirectionDegree']),
      windSpeed: _number(raw['windSpeed']),
      visibility: _number(raw['visibility']),
      observedAt: _date(raw['observedAt']),
      forecastSummary: raw['forecastSummary']?.toString() ?? '',
      alarms: alarms,
    );
  }

  static CmaLocalWeatherStatus _cmaStatus(Object? raw) =>
      CmaLocalWeatherStatus.values.firstWhere(
        (item) => item.name == raw?.toString(),
        orElse: () => CmaLocalWeatherStatus.idle,
      );

  static JmaLocalWeatherStatus _jmaStatus(Object? raw) =>
      JmaLocalWeatherStatus.values.firstWhere(
        (item) => item.name == raw?.toString(),
        orElse: () => JmaLocalWeatherStatus.idle,
      );

  static FanRadarFrame? decodeFanRadar(Map<String, dynamic> raw) {
    final time = _date(raw['time']);
    final sw = _readLatLng(_nestedMap(raw['southWest']));
    final ne = _readLatLng(_nestedMap(raw['northEast']));
    final bytes = raw['imageBytes'];
    final width = _int(raw['width']);
    final height = _int(raw['height']);
    if (time == null ||
        sw == null ||
        ne == null ||
        bytes is! List ||
        width == null ||
        height == null)
      return null;
    return FanRadarFrame(
      time: time,
      southWest: sw,
      northEast: ne,
      width: width,
      height: height,
      imageBytes: Uint8List.fromList(bytes.cast<int>()),
    );
  }

  static FanSatelliteCloudFrame? decodeFanSatellite(Map<String, dynamic> raw) {
    final time = _date(raw['time']);
    final sw = _readLatLng(_nestedMap(raw['southWest']));
    final ne = _readLatLng(_nestedMap(raw['northEast']));
    final bytes = raw['imageBytes'];
    if (time == null || sw == null || ne == null || bytes is! List) return null;
    return FanSatelliteCloudFrame(
      time: time,
      southWest: sw,
      northEast: ne,
      imageBytes: Uint8List.fromList(bytes.cast<int>()),
    );
  }

  static JmaRadarFrame? decodeJmaRadar(Map<String, dynamic> raw) {
    final basetime = raw['basetime']?.toString() ?? '';
    final validtime = raw['validtime']?.toString() ?? '';
    final time = _date(raw['time']);
    if (basetime.isEmpty || validtime.isEmpty || time == null) return null;
    return JmaRadarFrame(basetime: basetime, validtime: validtime, time: time);
  }

  static JmaVolcanoSite? _decodeVolcanoSite(Map<String, dynamic> raw) {
    final latitude = _number(raw['latitude']);
    final longitude = _number(raw['longitude']);
    if (latitude == null || longitude == null) return null;
    return JmaVolcanoSite(
      code: raw['code']?.toString() ?? '',
      nameJp: raw['nameJp']?.toString() ?? '',
      nameEn: raw['nameEn']?.toString() ?? '',
      latitude: latitude,
      longitude: longitude,
      levelOperation: raw['levelOperation'] == true,
      alertLevel: _int(raw['alertLevel']) ?? 0,
      hasWarning: raw['hasWarning'] == true,
      hasRecentInfo: raw['hasRecentInfo'] == true,
      hasRecentEruption: raw['hasRecentEruption'] == true,
      warningKindCode: raw['warningKindCode']?.toString(),
      warningKindName: raw['warningKindName']?.toString(),
      warningAlarm: raw['warningAlarm']?.toString(),
      warningReportTime: _date(raw['warningReportTime']),
      infoHeadTitle: raw['infoHeadTitle']?.toString(),
      infoReportTime: _date(raw['infoReportTime']),
      eruptionReportTime: _date(raw['eruptionReportTime']),
      hasProvisionalInfo: raw['hasProvisionalInfo'] == true,
    );
  }

  static List<FdsnStation> decodeFdsnStations(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeFdsnStation(Map<String, dynamic>.from(item)))
        .whereType<FdsnStation>()
        .toList(growable: false);
  }

  static FdsnMotionSample? decodeFdsnMotion(Map<String, dynamic> raw) {
    final timestamp = DateTime.tryParse(raw['timestamp']?.toString() ?? '');
    if (timestamp == null) return null;
    return FdsnMotionSample(
      source: raw['source']?.toString() ?? '',
      network: raw['network']?.toString() ?? '',
      station: raw['station']?.toString() ?? '',
      channel: raw['channel']?.toString() ?? '',
      pga: _number(raw['pga']),
      pgv: _number(raw['pgv']),
      intensity: _number(raw['intensity']),
      active: raw['active'] == true,
      timestamp: timestamp,
    );
  }

  static FdsnStation? _decodeFdsnStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    final network = raw['network']?.toString() ?? '';
    final station = raw['station']?.toString() ?? '';
    if (coordinate == null || network.isEmpty || station.isEmpty) return null;
    return FdsnStation(
      network: network,
      station: station,
      location: raw['location']?.toString() ?? '',
      coordinate: coordinate,
      elevation: _number(raw['elevation']),
      siteName: raw['siteName']?.toString() ?? '',
      startTime: _date(raw['startTime']),
      endTime: _date(raw['endTime']),
      source: raw['sourceName']?.toString() ?? '',
      pga: _number(raw['pga']),
      pgv: _number(raw['pgv']),
      intensity: _number(raw['intensity']),
      lastMotionUpdate: _date(raw['lastMotionUpdate']),
    );
  }

  static LpgmSnapshot? decodeLpgm(Map<String, dynamic> raw) {
    final dataTime = DateTime.tryParse(raw['dataTime']?.toString() ?? '');
    final topRaw = raw['topStations'];
    if (dataTime == null || topRaw is! List) return null;
    final top = <LpgmStationReading>[];
    for (final item in topRaw.whereType<Map>()) {
      final value = Map<String, dynamic>.from(item);
      final lat = _number(value['lat']);
      final lng = _number(value['lng']);
      final sva = _number(value['sva']);
      final lpgmClass = _int(value['lpgmClass']);
      if (lat == null || lng == null || sva == null || lpgmClass == null) {
        continue;
      }
      top.add(
        LpgmStationReading(
          code: value['code']?.toString() ?? '',
          name: value['name']?.toString() ?? '',
          coordinate: LatLng(lat, lng),
          sva: sva,
          lpgmClass: lpgmClass,
        ),
      );
    }
    return LpgmSnapshot(
      dataTime: dataTime,
      maxSva: _number(raw['maxSva']) ?? 0,
      maxClass: _int(raw['maxClass']) ?? 0,
      topStations: List.unmodifiable(top),
      maxRawRgb: _int(raw['maxRawRgb']),
    );
  }

  static List<NiedStation> decodeNied(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeNiedStation(Map<String, dynamic>.from(item)))
        .whereType<NiedStation>()
        .toList(growable: false);
  }

  static List<KmaStation> decodeKma(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeKmaStation(Map<String, dynamic>.from(item)))
        .whereType<KmaStation>()
        .toList(growable: false);
  }

  static List<CwaStation> decodeCwa(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeCwaStation(Map<String, dynamic>.from(item)))
        .whereType<CwaStation>()
        .toList(growable: false);
  }

  static List<SnetStation> decodeSnet(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeSnetStation(Map<String, dynamic>.from(item)))
        .whereType<SnetStation>()
        .toList(growable: false);
  }

  static List<SeisJsStation> decodeSeisJs(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodeSeisJsStation(Map<String, dynamic>.from(item)))
        .whereType<SeisJsStation>()
        .toList(growable: false);
  }

  static List<PAlertStation> decodePAlert(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _decodePAlertStation(Map<String, dynamic>.from(item)))
        .whereType<PAlertStation>()
        .toList(growable: false);
  }

  static Map<String, dynamic> _latLng(LatLng value) => {
    'lat': value.latitude,
    'lng': value.longitude,
  };

  static LatLng? _readLatLng(Map<String, dynamic> raw) {
    final lat = _number(raw['lat']);
    final lng = _number(raw['lng']);
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    return LatLng(lat, lng);
  }

  static Map<String, dynamic> _niedStation(NiedStation station) => {
    'id': station.id,
    'code': station.code,
    'name': station.name,
    'coordinate': _latLng(station.coordinate),
    'network': station.network,
    'prefecture': station.prefecture,
    'level': station.level,
    'calibrationFactor': station.calibrationFactor,
    'thresholdCode': station.thresholdCode,
    'ascend': station.ascend,
    'triggerStamp': station.triggerStamp,
    'activity': station.activity,
    'isActive': station.isActive,
    'abnormalUpdateCount': station.abnormalUpdateCount,
    'detectState': station.detectState,
    'detectReason': station.detectReason,
    'recentLevel': station.recentLevel,
    'expireSeconds': station.expireSeconds,
    'defaultExpireSeconds': station.defaultExpireSeconds,
    'lastUpdate': station.lastUpdate?.toIso8601String(),
    'lastDataTime': station.lastDataTime?.toIso8601String(),
    'lastReceivedAt': station.lastReceivedAt?.toIso8601String(),
    'pixelX': station.pixelX,
    'pixelY': station.pixelY,
    'scanReliable': station.scanReliable,
    'pixelClusterId': station.pixelClusterId,
    'gifObservations': station.gifObservations.values
        .map(_niedObservation)
        .toList(growable: false),
    'gifLayerQualityFlags': {
      for (final entry in station.gifLayerQualityFlags.entries)
        entry.key.id: entry.value.toList(growable: false),
    },
  };

  static Map<String, dynamic> _niedObservation(NiedGifObservation value) => {
    'layer': value.layer.id,
    'colorPosition': value.colorPosition,
    'shindo': value.shindo,
    'pga': value.pga,
    'pgv': value.pgv,
    'pgd': value.pgd,
    'velocityResponse': value.velocityResponse,
  };

  static NiedStation? _decodeNiedStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    final id = _int(raw['id']);
    final expire = _int(raw['expireSeconds']);
    if (coordinate == null || id == null || expire == null) return null;
    final station = NiedStation(
      id: id,
      code: raw['code']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      coordinate: coordinate,
      network: raw['network']?.toString() ?? '',
      prefecture: raw['prefecture']?.toString() ?? '',
      expireSeconds: expire,
      pixelX: _int(raw['pixelX']) ?? 0,
      pixelY: _int(raw['pixelY']) ?? 0,
      scanReliable: raw['scanReliable'] != false,
      pixelClusterId: raw['pixelClusterId']?.toString(),
      level: _int(raw['level']) ?? -1,
    );
    station
      ..calibrationFactor = _number(raw['calibrationFactor']) ?? 1.0
      ..thresholdCode = _int(raw['thresholdCode']) ?? 320
      ..ascend = _int(raw['ascend']) ?? 0
      ..triggerStamp = _int(raw['triggerStamp']) ?? 0
      ..activity = _number(raw['activity']) ?? 0.0
      ..isActive = raw['isActive'] == true
      ..abnormalUpdateCount = _int(raw['abnormalUpdateCount'])
      ..detectState = _int(raw['detectState']) ?? 0
      ..detectReason = raw['detectReason']?.toString() ?? ''
      ..recentLevel = _intList(raw['recentLevel'])
      ..lastUpdate = _date(raw['lastUpdate'])
      ..lastDataTime = _date(raw['lastDataTime'])
      ..lastReceivedAt = _date(raw['lastReceivedAt']);
    final defaultExpire = _int(raw['defaultExpireSeconds']);
    if (defaultExpire != null) station.defaultExpireSeconds = defaultExpire;
    final observations = raw['gifObservations'];
    if (observations is List) {
      for (final item in observations.whereType<Map>()) {
        final observation = _decodeNiedObservation(
          Map<String, dynamic>.from(item),
        );
        if (observation != null) station.updateGifObservation(observation);
      }
    }
    final quality = raw['gifLayerQualityFlags'];
    if (quality is Map) {
      for (final entry in quality.entries) {
        final layer = _gifLayer(entry.key.toString());
        final values = entry.value;
        if (layer != null && values is List) {
          station.gifLayerQualityFlags[layer] = values
              .map((item) => item.toString())
              .toSet();
        }
      }
    }
    return station;
  }

  static NiedGifObservation? _decodeNiedObservation(Map<String, dynamic> raw) {
    final layer = _gifLayer(raw['layer']?.toString() ?? '');
    if (layer == null) return null;
    return NiedGifObservation(
      layer: layer,
      colorPosition: _number(raw['colorPosition']),
      shindo: _number(raw['shindo']),
      pga: _number(raw['pga']),
      pgv: _number(raw['pgv']),
      pgd: _number(raw['pgd']),
      velocityResponse: _number(raw['velocityResponse']),
    );
  }

  static NiedGifLayer? _gifLayer(String id) {
    for (final layer in NiedGifLayer.values) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  static Map<String, dynamic> _kmaStation(KmaStation station) => {
    'id': station.id,
    'coordinate': _latLng(station.coordinate),
    'intensity': station.intensity,
    'lastUpdate': station.lastUpdate?.toIso8601String(),
    'recentLevel': station.recentLevel,
    'activityLevel': station.activityLevel,
    'holdLevel': station.holdLevel,
    'ascend': station.ascend,
    'isActive': station.isActive,
  };

  static KmaStation? _decodeKmaStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    final id = _int(raw['id']);
    if (coordinate == null || id == null) return null;
    final station = KmaStation(
      id: id,
      coordinate: coordinate,
      intensity: _int(raw['intensity']) ?? -3,
      lastUpdate: _date(raw['lastUpdate']),
    );
    station
      ..recentLevel = _intList(raw['recentLevel'])
      ..activityLevel = _int(raw['activityLevel']) ?? -1
      ..holdLevel = _int(raw['holdLevel']) ?? -1
      ..ascend = _int(raw['ascend']) ?? 0
      ..isActive = raw['isActive'] == true;
    return station;
  }

  static Map<String, dynamic> _cwaStation(CwaStation station) => {
    'id': station.id,
    'code': station.code,
    'net': station.net,
    'coordinate': _latLng(station.coordinate),
    'work': station.work,
    'pga': station.pga,
    'pgv': station.pgv,
    'intensity': station.intensity,
    'alertIntensity': station.alertIntensity,
    'hasAlert': station.hasAlert,
    'lastUpdate': station.lastUpdate?.toIso8601String(),
  };

  static CwaStation? _decodeCwaStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    final id = raw['id']?.toString();
    final code = _int(raw['code']);
    if (coordinate == null || id == null || code == null) return null;
    return CwaStation(
      id: id,
      code: code,
      net: raw['net']?.toString() ?? '',
      coordinate: coordinate,
      work: raw['work'] == true,
      pga: _number(raw['pga']) ?? 0,
      pgv: _number(raw['pgv']) ?? 0,
      intensity: _number(raw['intensity']) ?? -3,
      alertIntensity: _number(raw['alertIntensity']) ?? -3.1,
      hasAlert: raw['hasAlert'] == true,
      lastUpdate: _date(raw['lastUpdate']),
    );
  }

  static Map<String, dynamic> _snetStation(SnetStation station) => {
    'code': station.code,
    'name': station.name,
    'coordinate': _latLng(station.coordinate),
    'depth': station.depth,
    'network': station.network,
    'type': station.type,
    'intensity': station.intensity,
    'shindo': station.shindo,
    'level': station.level,
    'pixelX': station.pixelX,
    'pixelY': station.pixelY,
    'isActive': station.isActive,
    'pressure': station.pressure,
    'lastUpdate': station.lastUpdate?.toIso8601String(),
  };

  static SnetStation? _decodeSnetStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    if (coordinate == null) return null;
    return SnetStation(
      code: raw['code']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      coordinate: coordinate,
      depth: _number(raw['depth']) ?? 0,
      network: raw['network']?.toString() ?? '',
      type: raw['type']?.toString() ?? '',
      intensity: _number(raw['intensity']),
      shindo: _number(raw['shindo']) ?? 0,
      level: _int(raw['level']) ?? -1,
      pixelX: _int(raw['pixelX']) ?? 0,
      pixelY: _int(raw['pixelY']) ?? 0,
      isActive: raw['isActive'] == true,
      pressure: _number(raw['pressure']),
      lastUpdate: _date(raw['lastUpdate']),
    );
  }

  static Map<String, dynamic> _seisJsStation(SeisJsStation station) => {
    'id': station.id,
    'region': station.region,
    'coordinate': _latLng(station.coordinate),
    'shindo': station.shindo,
    'calcShindo': station.calcShindo,
    'intensity': station.intensity,
    'pga': station.pga,
    'pgv': station.pgv,
    'maxPga': station.maxPga,
    'maxPgv': station.maxPgv,
    'maxIntensity': station.maxIntensity,
    'isDesktop': station.isDesktop,
    'lastUpdate': station.lastUpdate?.toIso8601String(),
  };

  static SeisJsStation? _decodeSeisJsStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    final id = raw['id']?.toString();
    if (coordinate == null || id == null) return null;
    return SeisJsStation(
      id: id,
      region: raw['region']?.toString() ?? '',
      coordinate: coordinate,
      shindo: _int(raw['shindo']) ?? 0,
      calcShindo: _number(raw['calcShindo']) ?? -3,
      intensity: _number(raw['intensity']) ?? 0,
      pga: _number(raw['pga']) ?? 0,
      pgv: _number(raw['pgv']) ?? 0,
      maxPga: _number(raw['maxPga']) ?? 0,
      maxPgv: _number(raw['maxPgv']) ?? 0,
      maxIntensity: _number(raw['maxIntensity']) ?? 0,
      isDesktop: raw['isDesktop'] == true,
      lastUpdate: _date(raw['lastUpdate']),
    );
  }

  static Map<String, dynamic> _pAlertStation(PAlertStation station) => {
    'id': station.id,
    'network': station.network,
    'name': station.name,
    'area': station.area,
    'coordinate': _latLng(station.coordinate),
    'pgaGal': station.pgaGal,
    'pgvCms': station.pgvCms,
    'cwaIntensityIndex': station.cwaIntensityIndex,
    'heldCwaIntensityIndex': station.heldCwaIntensityIndex,
    'dataTime': station.dataTime?.toIso8601String(),
    'receivedAt': station.receivedAt?.toIso8601String(),
  };

  static PAlertStation? _decodePAlertStation(Map<String, dynamic> raw) {
    final coordinate = _readLatLng(_nestedMap(raw['coordinate']));
    final id = raw['id']?.toString();
    if (coordinate == null || id == null) return null;
    return PAlertStation(
      id: id,
      network: raw['network']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      area: raw['area']?.toString() ?? '',
      coordinate: coordinate,
      pgaGal: _number(raw['pgaGal']),
      pgvCms: _number(raw['pgvCms']),
      cwaIntensityIndex: _int(raw['cwaIntensityIndex']),
      heldCwaIntensityIndex: _int(raw['heldCwaIntensityIndex']),
      dataTime: _date(raw['dataTime']),
      receivedAt: _date(raw['receivedAt']),
    );
  }

  static double? _number(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static Map<String, dynamic> _nestedMap(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static int? _int(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static List<int> _intList(dynamic raw) {
    if (raw is! List) return <int>[];
    return raw.map(_int).whereType<int>().toList(growable: true);
  }

  static DateTime? _date(dynamic raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString());
}
