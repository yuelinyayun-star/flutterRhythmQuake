// Frozen pre-refactor neighbour selection, used only against original metadata.
import 'dart:math' as math;
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_detection_rules.dart';

class NiedTopologyReference {
  String? _dartHypAdjStationIdsKey;
  Map<String, List<int>> _dartHypAdjStationIds = {};
  String? _dartDetectionAdjStationCodesKey;
  Map<String, List<String>> _dartDetectionAdjStationCodes = {};
  Map<String, List<int>> hypocenter(List<NiedStation> stations) =>
      _dartHypocenterAdjStationIds(stations);
  Map<String, List<String>> detection(List<NiedStation> stations) =>
      _dartDetectionAdjacencyByCode(stations);
  Map<String, List<int>> _dartHypocenterAdjStationIds(
    List<NiedStation> stations,
  ) {
    final key = stations.map((station) => station.code).join('|');
    if (_dartHypAdjStationIdsKey == key) return _dartHypAdjStationIds;
    final result = <String, List<int>>{};
    for (final station in stations) {
      final distances = <({int id, double distanceKm, double bearingDeg})>[];
      for (final other in stations) {
        final distanceKm = _haversineKm(
          station.coordinate.latitude,
          station.coordinate.longitude,
          other.coordinate.latitude,
          other.coordinate.longitude,
        );
        distances.add((
          id: other.id,
          distanceKm: distanceKm,
          bearingDeg: _bearingDeg(
            station.coordinate.latitude,
            station.coordinate.longitude,
            other.coordinate.latitude,
            other.coordinate.longitude,
          ),
        ));
      }
      distances.sort((a, b) {
        final distanceCompare = a.distanceKm.compareTo(b.distanceKm);
        return distanceCompare != 0 ? distanceCompare : a.id.compareTo(b.id);
      });
      final selected = <int>{};
      final coveredDirections = <int>{};
      for (final item in distances) {
        if (item.distanceKm <= 30.0) {
          selected.add(item.id);
          if (item.id != station.id) {
            coveredDirections.add(_bearingDirection(item.bearingDeg));
          }
        }
      }
      for (final item in distances) {
        if (coveredDirections.length >= 4) break;
        if (item.id == station.id ||
            item.distanceKm <= 30.0 ||
            item.distanceKm > 300.0) {
          continue;
        }
        final direction = _bearingDirection(item.bearingDeg);
        if (coveredDirections.add(direction)) {
          selected.add(item.id);
        }
      }
      result['${station.id}'] = List<int>.unmodifiable(selected);
    }
    _dartHypAdjStationIdsKey = key;
    _dartHypAdjStationIds = Map<String, List<int>>.unmodifiable(result);
    return _dartHypAdjStationIds;
  }

  Map<String, List<String>> _dartDetectionAdjacencyByCode(
    List<NiedStation> stations,
  ) {
    final key = stations.map((station) => station.code).join('|');
    if (_dartDetectionAdjStationCodesKey == key) {
      return _dartDetectionAdjStationCodes;
    }
    final result = <String, List<String>>{};
    for (final station in stations) {
      final distances =
          <({NiedStation station, double distanceKm})>[
            for (final other in stations)
              (
                station: other,
                distanceKm: _haversineKm(
                  station.coordinate.latitude,
                  station.coordinate.longitude,
                  other.coordinate.latitude,
                  other.coordinate.longitude,
                ),
              ),
          ]..sort((left, right) {
            final byDistance = left.distanceKm.compareTo(right.distanceKm);
            return byDistance != 0
                ? byDistance
                : left.station.id.compareTo(right.station.id);
          });
      final nearby = distances
          .where((item) => item.distanceKm <= 30.0)
          .toList();
      if (nearby.length <= 1) {
        for (final candidate in distances) {
          if (candidate.distanceKm > 30.0 && candidate.distanceKm <= 40.0) {
            nearby.add(candidate);
            break;
          }
        }
      }
      result[station.code] = List<String>.unmodifiable(
        nearby.take(niedNearbyStationLimit).map((item) => item.station.code),
      );
    }
    _dartDetectionAdjStationCodesKey = key;
    _dartDetectionAdjStationCodes = Map<String, List<String>>.unmodifiable(
      result,
    );
    return _dartDetectionAdjStationCodes;
  }

  int _bearingDirection(double bearingDeg) {
    return (((bearingDeg + 45.0) % 360.0) ~/ 90) % 4;
  }

  double _bearingDeg(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaLambda = (lon2 - lon1) * math.pi / 180.0;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final rLat1 = lat1 * math.pi / 180.0;
    final rLat2 = lat2 * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final clamped = a.clamp(0.0, 1.0);
    return earthRadiusKm *
        2.0 *
        math.atan2(math.sqrt(clamped), math.sqrt(1.0 - clamped));
  }
}
