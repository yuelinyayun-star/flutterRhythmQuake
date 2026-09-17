import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../core/intensity_calculator.dart';
import '../../models/nied_station_db.dart';
import 'nied_monitor.dart';

Future<void>? _loadingPrefectures;
final _prefectures =
    <
      ({
        String name,
        List<List<LatLng>> rings,
        double south,
        double north,
        double west,
        double east,
      })
    >[];

Future<void> loadWhewsNiedPrefectures() =>
    _loadingPrefectures ??= _loadPrefectures().catchError((Object error) {
      _loadingPrefectures = null;
      throw error;
    });

Future<void> _loadPrefectures() async {
  final data =
      jsonDecode(
            await rootBundle.loadString(
              'assets/maps/japan_prefectures.geojson',
            ),
          )
          as Map<String, dynamic>;
  for (final feature in data['features'] as List) {
    final name = feature['properties']['N03_001'] as String;
    final geometry = feature['geometry'] as Map;
    final polygons = geometry['type'] == 'Polygon'
        ? [geometry['coordinates']]
        : geometry['coordinates'] as List;
    for (final polygon in polygons) {
      final rings = (polygon as List)
          .map(
            (ring) => (ring as List)
                .map(
                  (p) => LatLng(
                    (p[1] as num).toDouble(),
                    (p[0] as num).toDouble(),
                  ),
                )
                .toList(growable: false),
          )
          .toList(growable: false);
      final outer = rings.first;
      _prefectures.add((
        name: name,
        rings: rings,
        south: outer.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
        north: outer.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
        west: outer.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
        east: outer.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
      ));
    }
  }
}

String? _prefectureAt(LatLng point) {
  for (final area in _prefectures) {
    if (point.latitude < area.south ||
        point.latitude > area.north ||
        point.longitude < area.west ||
        point.longitude > area.east) {
      continue;
    }
    if (IntensityCalculator.pointInPolygon(
          point.latitude,
          point.longitude,
          area.rings.first,
        ) &&
        !area.rings
            .skip(1)
            .any(
              (hole) => IntensityCalculator.pointInPolygon(
                point.latitude,
                point.longitude,
                hole,
              ),
            )) {
      return area.name;
    }
  }
  return null;
}

/// Resolve only an unambiguous local catalogue entry in a small coordinate
/// tolerance. Do not replace the API coordinate or reorder its station array.
List<NiedStation> buildWhewsNiedStations(List<LatLng> coordinates) {
  const tolerance = 0.001;
  // Exact historical coordinates published by NIED, not nearest-site guesses:
  // https://www.kyoshin.bosai.go.jp/en/stationlocationinfobefore20220201/
  final legacyCodes = {
    (37.9204, 138.4981): 'NIG005',
    (34.0121, 131.4042): 'YMG008',
  };
  return List.generate(coordinates.length, (index) {
    final coordinate = coordinates[index];
    final legacyCode = legacyCodes[(coordinate.latitude, coordinate.longitude)];
    final matches = NiedStationDb.stations
        .where((entry) {
          return ((entry['lat'] as num) - coordinate.latitude).abs() <=
                  tolerance &&
              ((entry['lng'] as num) - coordinate.longitude).abs() <= tolerance;
        })
        .toList(growable: false);
    final exact = matches
        .where(
          (entry) =>
              entry['lat'] == coordinate.latitude &&
              entry['lng'] == coordinate.longitude,
        )
        .toList(growable: false);
    final metadata = legacyCode != null
        ? NiedStationDb.stations.firstWhere(
            (entry) => entry['code'] == legacyCode,
          )
        : exact.length == 1
        ? exact.single
        : matches.length == 1
        ? matches.single
        : null;
    return NiedStation(
      id: index,
      // The API's array index remains its identity, even for co-located sites.
      code: 'WHEWS-NIED-${index + 1}',
      name: metadata?['name'] as String? ?? '',
      coordinate: coordinate,
      network: metadata?['network'] as String? ?? 'WHEWS',
      prefecture:
          _prefectureAt(coordinate) ?? metadata?['pref'] as String? ?? '',
      expireSeconds: NiedStation.kaExpireSeconds,
    );
  });
}
