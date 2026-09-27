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

/// Keep the API's coordinate and array order. Jian supplies names directly;
/// WHEWS resolves only unambiguous local catalogue matches.
List<NiedStation> buildWhewsNiedStations(
  List<LatLng> coordinates, {
  String source = 'whews',
  List<String> codes = const [],
  List<String> names = const [],
  List<String> regions = const [],
  List<String> stationTypes = const [],
}) {
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
    final fromJian = source == 'jian';
    final sourceCode = fromJian && codes.length == coordinates.length
        ? codes[index].trim()
        : '';
    final sourceName = fromJian && names.length == coordinates.length
        ? names[index].trim()
        : '';
    final sourceRegion = fromJian && regions.length == coordinates.length
        ? regions[index].trim()
        : '';
    final sourceNetwork = fromJian && stationTypes.length == coordinates.length
        ? stationTypes[index].trim()
        : '';
    return NiedStation(
      id: index,
      // The API's array index remains its identity, even for co-located sites.
      code: fromJian ? sourceCode : 'WHEWS-NIED-${index + 1}',
      name: sourceName.isNotEmpty
          ? sourceName
          : metadata?['name'] as String? ?? '',
      coordinate: coordinate,
      network: sourceNetwork.isNotEmpty
          ? sourceNetwork
          : metadata?['network'] as String? ?? source.toUpperCase(),
      prefecture: sourceRegion.isNotEmpty
          ? sourceRegion
          : _prefectureAt(coordinate) ?? metadata?['pref'] as String? ?? '',
      expireSeconds: NiedStation.kaExpireSeconds,
    );
  });
}
