import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/native_map_coordinates_io.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';

int bits(double x) => (ByteData(8)..setFloat64(0, x)).getUint64(0);
void main() {
  test(
    'all original map vertices retain scalar IEEE operation order and cache ownership',
    () async {
      if (!Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
        markTestSkipped('Native DLL required');
        return;
      }
      final data = await VectorBasemapService(
        loadAsset: (p) => File(p).readAsString(),
      ).load();
      var compared = 0;
      for (final dataset in data) {
        for (final polygon in dataset.polygons) {
          final points = [
            for (final p in polygon.rings.first)
              const Epsg3857().projection.project(p),
          ];
          final holes = [
            for (final ring in polygon.rings.skip(1))
              [for (final p in ring) const Epsg3857().projection.project(p)],
          ];
          // project() returns Offset, with original Mercator rounding unchanged.
          final a = 0.5 / (3.141592653589793 * 6378137.0);
          final args = [
            a,
            0.5,
            -a,
            0.5,
            13275.3221703,
            40075016.68557849,
            -147.33,
            -812.7,
            32768.0,
          ];
          final actual = NativeMapCoordinates.transform(
            points,
            holes,
            args[0],
            args[1],
            args[2],
            args[3],
            args[4],
            args[5],
            args[6],
            args[7],
            args[8],
          );
          final misses = NativeMapCoordinates.cacheMisses;
          final again = NativeMapCoordinates.transform(
            points,
            holes,
            args[0],
            args[1],
            args[2],
            args[3],
            args[4],
            args[5],
            args[6],
            args[7],
            args[8],
          );
          expect(NativeMapCoordinates.cacheMisses, misses);
          final flat = [...points, for (final ring in holes) ...ring];
          expect(actual.length, flat.length);
          for (var i = 0; i < flat.length; i++) {
            final p = flat[i];
            expect(
              bits(actual[i].dx),
              bits(
                args[4] * (args[0] * (p.dx + args[5]) + args[1]) +
                    args[6] +
                    args[8],
              ),
            );
            expect(
              bits(actual[i].dy),
              bits(args[4] * (args[2] * p.dy + args[3]) + args[7]),
            );
            expect(again[i], actual[i]);
            compared++;
          }
        }
      }
      expect(compared, greaterThan(100000));
    },
  );
}
