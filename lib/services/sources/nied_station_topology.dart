import 'dart:math' as math;

import '../../core/source_estimation/nied_hyp_input_snapshot.dart';
import 'nied_detection_rules.dart';
import 'nied_monitor.dart';
import 'native_topology_sort.dart';
import 'native_nied_topology.dart';

typedef _StationGeometry = ({int id, String code, double lat, double lng});

/// Immutable geometry shared by successive observation frames. Detection and
/// source estimation use different neighbour rules, but the same distances.
class NiedStationTopology {
  final List<_StationGeometry> _geometry;
  final Map<String, List<int>> hypocenterAdjacentIds;
  final Map<String, List<String>> detectionAdjacentCodes;

  NiedStationTopology._(
    this._geometry,
    this.hypocenterAdjacentIds,
    this.detectionAdjacentCodes,
  );

  factory NiedStationTopology.fromStations(List<NiedStation> stations) {
    final geometry = [
      for (final station in stations)
        (
          id: station.id,
          code: station.code,
          lat: station.coordinate.latitude,
          lng: station.coordinate.longitude,
        ),
    ];
    // Equal distance/ID ties have unspecified order in the original Dart sort.
    // Preserve that implementation for duplicate IDs and non-native targets.
    if (NativeTopologySort.supported &&
        geometry.length <= 1048576 &&
        geometry.map((station) => station.id).toSet().length ==
            geometry.length) {
      return _fromNativeGeometry(geometry);
    }
    final hypocenter = <String, List<int>>{};
    final detection = <String, List<String>>{};
    for (final station in geometry) {
      final distances = <({int index, double km})>[];
      for (var index = 0; index < geometry.length; index++) {
        final other = geometry[index];
        final km = _distanceKm(station, other);
        // Neither consumer can select a station beyond 300 km. All original
        // coordinates still participate; discard only unused sort entries.
        if (km <= 300.0) distances.add((index: index, km: km));
      }
      distances.sort((a, b) {
        final byDistance = a.km.compareTo(b.km);
        return byDistance != 0
            ? byDistance
            : geometry[a.index].id.compareTo(geometry[b.index].id);
      });

      final nearby = distances.where((item) => item.km <= 30.0).toList();
      if (nearby.length <= 1) {
        for (final candidate in distances) {
          if (candidate.km > 30.0 && candidate.km <= 40.0) {
            nearby.add(candidate);
            break;
          }
        }
      }
      detection[station.code] = List.unmodifiable(
        nearby
            .take(niedNearbyStationLimit)
            .map((item) => geometry[item.index].code),
      );

      final selected = <int>{};
      final coveredDirections = <int>{};
      for (final item in distances) {
        if (item.km <= 30.0) {
          final other = geometry[item.index];
          selected.add(other.id);
          if (other.id != station.id) {
            coveredDirections.add(_direction(station, other));
          }
        }
      }
      for (final item in distances) {
        if (coveredDirections.length >= 4) break;
        final other = geometry[item.index];
        if (other.id == station.id || item.km <= 30.0) continue;
        if (coveredDirections.add(_direction(station, other))) {
          selected.add(other.id);
        }
      }
      hypocenter['${station.id}'] = List.unmodifiable(selected);
    }
    return NiedStationTopology._(
      List.unmodifiable(geometry),
      NiedHypAdjacencySnapshot<int>(hypocenter),
      NiedHypAdjacencySnapshot<String>(detection),
    );
  }

  static NiedStationTopology _fromNativeGeometry(
    List<_StationGeometry> geometry,
  ) {
    final rows = NativeNiedTopology.build(
      [for (final station in geometry) station.id],
      [
        for (final station in geometry) ...[station.lat, station.lng],
      ],
      [for (final station in geometry) station.code],
    );
    return NiedStationTopology._(
      List.unmodifiable(geometry),
      NiedHypAdjacencySnapshot<int>({
        for (final row in rows) row[0] as String: (row[2] as List).cast<int>(),
      }),
      NiedHypAdjacencySnapshot<String>({
        for (final row in rows)
          row[1] as String: (row[3] as List).cast<String>(),
      }),
    );
  }

  /// Include coordinates and IDs, rather than just codes, when invalidating.
  bool matchesStations(List<NiedStation> stations) {
    if (_geometry.length != stations.length) return false;
    for (var index = 0; index < stations.length; index++) {
      final saved = _geometry[index];
      final station = stations[index];
      if (saved.id != station.id ||
          saved.code != station.code ||
          saved.lat != station.coordinate.latitude ||
          saved.lng != station.coordinate.longitude) {
        return false;
      }
    }
    return true;
  }

  static int _direction(_StationGeometry first, _StationGeometry second) {
    final phi1 = first.lat * math.pi / 180.0;
    final phi2 = second.lat * math.pi / 180.0;
    final deltaLambda = (second.lng - first.lng) * math.pi / 180.0;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final bearing = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
    return (((bearing + 45.0) % 360.0) ~/ 90) % 4;
  }

  static double _distanceKm(_StationGeometry first, _StationGeometry second) {
    const earthRadiusKm = 6371.0;
    final dLat = (second.lat - first.lat) * math.pi / 180.0;
    final dLon = (second.lng - first.lng) * math.pi / 180.0;
    final rLat1 = first.lat * math.pi / 180.0;
    final rLat2 = second.lat * math.pi / 180.0;
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
