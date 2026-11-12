import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/core/source_estimation/kanameishi_jma2001_travel_time_table.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_geometry.dart';

double _distance(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180.0;
  final a =
      math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 6371.0088 * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)));
}

int _bits(double v) => (ByteData(8)..setFloat64(0, v)).getUint64(0);
void main() {
  test(
    'original station catalogue distance and JMA2001 values are bit exact',
    () {
      final stations = NiedStationDb.stations;
      final geometry = NativeHypGeometry([
        for (final s in stations) ...[
          (s['lat'] as num).toDouble(),
          (s['lng'] as num).toDouble(),
        ],
      ]);
      try {
        // Original catalogue coordinates. Depth sweeps separately exercise table
        // boundaries and extrapolation; they are not synthetic earthquake input.
        for (final seed in stations.take(3)) {
          final lat = (seed['lat'] as num).toDouble(),
              lng = (seed['lng'] as num).toDouble();
          for (final depth in [
            -1.0,
            0.0,
            1.0,
            2.0,
            10.0,
            54.99,
            55.0,
            55.01,
            100.0,
            700.0,
            710.0,
          ]) {
            final values = geometry.evaluate(lat, lng, depth);
            for (var i = 0; i < stations.length; i++) {
              final s = stations[i];
              final distance = _distance(
                lat,
                lng,
                (s['lat'] as num).toDouble(),
                (s['lng'] as num).toDouble(),
              );
              expect(
                _bits(values[i * 3]),
                _bits(distance),
                reason: 'distance $i $depth',
              );
              for (var wave = 0; wave < 2; wave++) {
                final expected =
                    KanameishiJma2001TravelTimeTable.travelTimeSeconds(
                      surfaceDistanceKm: distance,
                      depthKm: depth,
                      pWave: wave == 0,
                    );
                expect(
                  _bits(values[i * 3 + wave + 1]),
                  _bits(expected),
                  reason: 'travel $i $depth $wave',
                );
              }
            }
          }
        }
        final first = geometry.evaluate(35, 139, 10),
            saved = Float64List.fromList(geometry.evaluate(35, 139, 10));
        geometry.evaluate(36, 140, 20);
        geometry.dispose();
        expect(first, orderedEquals(saved));
        expect(() => geometry.evaluate(35, 139, 10), throwsStateError);
      } finally {
        geometry.dispose();
      }
    },
    skip: !NativeHypGeometry.supported,
  );
  test(
    'empty inputs and malformed coordinate counts',
    () {
      final empty = NativeHypGeometry([]);
      expect(empty.evaluate(0, 0, 0), isEmpty);
      empty.dispose();
      expect(() => NativeHypGeometry([1]), throwsArgumentError);
    },
    skip: !NativeHypGeometry.supported,
  );
}
