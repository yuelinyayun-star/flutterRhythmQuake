import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class JmaLpgmPeriodValue {
  const JmaLpgmPeriodValue({required this.band, required this.value});

  /// 1-7 second band used by VXSE62.
  final int band;
  final double value;

  Map<String, dynamic> toMap() => {'band': band, 'value': value};

  factory JmaLpgmPeriodValue.fromMap(Map<dynamic, dynamic> map) =>
      JmaLpgmPeriodValue(
        band: int.tryParse(map['band']?.toString() ?? '') ?? 0,
        value: double.tryParse(map['value']?.toString() ?? '') ?? 0,
      );
}

@immutable
class JmaLpgmStation {
  const JmaLpgmStation({
    required this.name,
    required this.code,
    required this.intensity,
    required this.lgInt,
    required this.sva,
    this.lgIntPerPeriod = const [],
    this.svaPerPeriod = const [],
    this.prefecture = '',
    this.area = '',
  });

  final String name;
  final String code;
  final String intensity;
  final int lgInt;
  final double? sva;
  final List<JmaLpgmPeriodValue> lgIntPerPeriod;
  final List<JmaLpgmPeriodValue> svaPerPeriod;
  final String prefecture;
  final String area;

  Map<String, dynamic> toMap() => {
    'name': name,
    'code': code,
    'intensity': intensity,
    'lgInt': lgInt,
    'sva': sva,
    'lgIntPerPeriod': lgIntPerPeriod.map((e) => e.toMap()).toList(),
    'svaPerPeriod': svaPerPeriod.map((e) => e.toMap()).toList(),
    'prefecture': prefecture,
    'area': area,
  };

  factory JmaLpgmStation.fromMap(Map<dynamic, dynamic> map) => JmaLpgmStation(
    name: map['name']?.toString() ?? '',
    code: map['code']?.toString() ?? '',
    intensity: map['intensity']?.toString() ?? '',
    lgInt: int.tryParse(map['lgInt']?.toString() ?? '') ?? 0,
    sva: double.tryParse(map['sva']?.toString() ?? ''),
    lgIntPerPeriod: _periodList(map['lgIntPerPeriod']),
    svaPerPeriod: _periodList(map['svaPerPeriod']),
    prefecture: map['prefecture']?.toString() ?? '',
    area: map['area']?.toString() ?? '',
  );
}

@immutable
class JmaLpgmRegion {
  const JmaLpgmRegion({
    required this.name,
    required this.code,
    required this.maxLgInt,
    this.maxInt = '',
  });

  final String name;
  final String code;
  final int maxLgInt;
  final String maxInt;

  Map<String, dynamic> toMap() => {
    'name': name,
    'code': code,
    'maxLgInt': maxLgInt,
    'maxInt': maxInt,
  };

  factory JmaLpgmRegion.fromMap(Map<dynamic, dynamic> map) => JmaLpgmRegion(
    name: map['name']?.toString() ?? '',
    code: map['code']?.toString() ?? '',
    maxLgInt: int.tryParse(map['maxLgInt']?.toString() ?? '') ?? 0,
    maxInt: map['maxInt']?.toString() ?? '',
  );
}

@immutable
class JmaLpgmBulletin {
  const JmaLpgmBulletin({
    required this.eventId,
    required this.serial,
    required this.infoType,
    required this.headline,
    required this.maxInt,
    required this.maxLgInt,
    required this.lgCategory,
    this.originTime,
    this.reportTime,
    this.hypocenter = '',
    this.latitude,
    this.longitude,
    this.depthKm,
    this.magnitude,
    this.detailUrl = '',
    this.regions = const [],
    this.stations = const [],
  });

  final String eventId;
  final int serial;
  final String infoType;
  final String headline;
  final String maxInt;
  final int maxLgInt;
  final String lgCategory;
  final DateTime? originTime;
  final DateTime? reportTime;
  final String hypocenter;
  final double? latitude;
  final double? longitude;
  final double? depthKm;
  final double? magnitude;
  final String detailUrl;
  final List<JmaLpgmRegion> regions;
  final List<JmaLpgmStation> stations;

  bool get isCanceled => infoType.contains('取消');

  bool isActive({DateTime? now, Duration maxAge = const Duration(minutes: 1)}) {
    if (isCanceled || maxLgInt < 1) return false;
    final stamp = reportTime ?? originTime;
    if (stamp == null) return true;
    return nowUtc(now).difference(stamp.toUtc()) <= maxAge;
  }

  List<JmaLpgmRegion> regionsAtMaxClass() {
    return regions.where((region) => region.maxLgInt == maxLgInt).toList();
  }

  List<JmaLpgmStation> topStations({int limit = 8}) {
    final sorted = [...stations]
      ..sort((left, right) {
        final classCmp = right.lgInt.compareTo(left.lgInt);
        if (classCmp != 0) return classCmp;
        return (right.sva ?? -1).compareTo(left.sva ?? -1);
      });
    if (sorted.length <= limit) return sorted;
    return sorted.take(limit).toList();
  }

  /// Covers all fields that can be revised in a same-Serial bulletin.
  ///
  /// The Atom entry ID and Serial are not sufficient: JMA may revise the
  /// report time, hypocenter, regions, or station values without changing
  /// the Serial number.
  String get signature {
    final regionSignature = regions
        .map(
          (region) =>
              '${region.name}|${region.code}|${region.maxLgInt}|${region.maxInt}',
        )
        .join(';');
    final stationSignature = stations
        .map(
          (station) => [
            station.name,
            station.code,
            station.intensity,
            station.lgInt,
            station.sva,
            station.lgIntPerPeriod
                .map((item) => '${item.band}:${item.value}')
                .join(','),
            station.svaPerPeriod
                .map((item) => '${item.band}:${item.value}')
                .join(','),
            station.prefecture,
            station.area,
          ].join('|'),
        )
        .join(';');
    return [
      eventId,
      serial,
      infoType,
      headline,
      maxInt,
      maxLgInt,
      lgCategory,
      originTime?.toUtc().toIso8601String() ?? '',
      reportTime?.toUtc().toIso8601String() ?? '',
      hypocenter,
      latitude,
      longitude,
      depthKm,
      magnitude,
      regionSignature,
      stationSignature,
    ].join('|');
  }

  Map<String, dynamic> toMap() => {
    'eventId': eventId,
    'serial': serial,
    'infoType': infoType,
    'headline': headline,
    'maxInt': maxInt,
    'maxLgInt': maxLgInt,
    'lgCategory': lgCategory,
    'originTime': originTime?.toIso8601String(),
    'reportTime': reportTime?.toIso8601String(),
    'hypocenter': hypocenter,
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'detailUrl': detailUrl,
    'regions': regions.map((e) => e.toMap()).toList(),
    'stations': stations.map((e) => e.toMap()).toList(),
  };

  factory JmaLpgmBulletin.fromMap(Map<dynamic, dynamic> map) => JmaLpgmBulletin(
    eventId: map['eventId']?.toString() ?? '',
    serial: int.tryParse(map['serial']?.toString() ?? '') ?? 1,
    infoType: map['infoType']?.toString() ?? '',
    headline: map['headline']?.toString() ?? '',
    maxInt: map['maxInt']?.toString() ?? '',
    maxLgInt: int.tryParse(map['maxLgInt']?.toString() ?? '') ?? 0,
    lgCategory: map['lgCategory']?.toString() ?? '',
    originTime: DateTime.tryParse(map['originTime']?.toString() ?? ''),
    reportTime: DateTime.tryParse(map['reportTime']?.toString() ?? ''),
    hypocenter: map['hypocenter']?.toString() ?? '',
    latitude: double.tryParse(map['latitude']?.toString() ?? ''),
    longitude: double.tryParse(map['longitude']?.toString() ?? ''),
    depthKm: double.tryParse(map['depthKm']?.toString() ?? ''),
    magnitude: double.tryParse(map['magnitude']?.toString() ?? ''),
    detailUrl: map['detailUrl']?.toString() ?? '',
    regions: _mapList(map['regions'], JmaLpgmRegion.fromMap),
    stations: _mapList(map['stations'], JmaLpgmStation.fromMap),
  );
}

List<JmaLpgmPeriodValue> _periodList(Object? raw) => raw is List
    ? raw
          .whereType<Map>()
          .map(JmaLpgmPeriodValue.fromMap)
          .toList(growable: false)
    : const [];

List<T> _mapList<T>(Object? raw, T Function(Map<dynamic, dynamic>) decode) =>
    raw is List
    ? raw.whereType<Map>().map(decode).toList(growable: false)
    : const [];

DateTime nowUtc(DateTime? now) => (now ?? DateTime.now()).toUtc();

String jmaLpgmXmlIntLabel(String raw) {
  return switch (raw.trim()) {
    '5-' || '5−' => '5弱',
    '5+' => '5强',
    '6-' || '6−' => '6弱',
    '6+' => '6强',
    _ => raw.trim(),
  };
}

String jmaLpgmCategoryLabel(String category) {
  return switch (category.trim()) {
    '1' => '震度与阶级大体一致',
    '2' => '部分地区震度偏低',
    '3' => '强长周期，震度也高',
    '4' => '强长周期，部分地区震度偏低',
    _ => '',
  };
}

Color jmaLpgmClassColor(int lgInt) {
  return switch (lgInt) {
    1 => const Color(0xFFF2E55C),
    2 => const Color(0xFFE6A732),
    3 => const Color(0xFFE53E3E),
    4 => const Color(0xFF9B1B7E),
    _ => const Color(0xFF9EA9B7),
  };
}
