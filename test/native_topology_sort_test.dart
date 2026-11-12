import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/native_topology_sort.dart';

double _distance(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lng2 - lng1) * math.pi / 180.0;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final clamped = a.clamp(0.0, 1.0);
  return 6371.0 *
      2.0 *
      math.atan2(math.sqrt(clamped), math.sqrt(1.0 - clamped));
}

void main() {
  test(
    'sorts original catalogue distances exactly without changing input',
    () {
      final stations = NiedStationDb.stations;
      // The station decoder uses the original catalogue position as station ID.
      final ids = List.generate(stations.length, (index) => index);
      final sorter = NativeTopologySort(ids);
      try {
        for (final seed in stations.take(3)) {
          final distances = sorter.distances;
          for (var i = 0; i < stations.length; i++) {
            final station = stations[i];
            distances[i] = _distance(
              (seed['lat'] as num).toDouble(),
              (seed['lng'] as num).toDouble(),
              (station['lat'] as num).toDouble(),
              (station['lng'] as num).toDouble(),
            );
          }
          final original = Uint8List.fromList(
            Uint8List.view(
              distances.buffer,
              distances.offsetInBytes,
              distances.lengthInBytes,
            ),
          );
          final expected =
              [
                for (var i = 0; i < stations.length; i++)
                  if (distances[i] <= 300.0) i,
              ]..sort((a, b) {
                final comparison = distances[a].compareTo(distances[b]);
                return comparison == 0 ? ids[a].compareTo(ids[b]) : comparison;
              });
          expect(sorter.sort(), orderedEquals(expected));
          expect(
            Uint8List.view(
              distances.buffer,
              distances.offsetInBytes,
              distances.lengthInBytes,
            ),
            orderedEquals(original),
          );
        }
      } finally {
        sorter.dispose();
      }
      sorter.dispose();
      expect(() => sorter.sort(), throwsStateError);
      expect(() => sorter.distances, throwsStateError);
    },
    skip: !NativeTopologySort.supported,
  );

  test('empty and structural invalid input', () {
    final sorter = NativeTopologySort([]);
    try {
      expect(sorter.distances, isEmpty);
      expect(sorter.sort(), isEmpty);
    } finally {
      sorter.dispose();
    }
    expect(() => NativeTopologySort([1, 1]), throwsArgumentError);
  }, skip: !NativeTopologySort.supported);
}
