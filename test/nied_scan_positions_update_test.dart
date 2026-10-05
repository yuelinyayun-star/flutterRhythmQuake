import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as images;
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

// Actual upstream geometry, not generated observation values.
const expected = {
  'HKD063': [338, 52, 0, 0],
  'HKD126': [271, 90, 0, 0],
  'ISK006': [164, 223, -1, 0],
  'TKY023': [228, 259, -1, -1],
  'TKY014': [227, 260, 0, -1],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('added points preserve upstream centers and offsets', () {
    final db = NiedStationDb.stations.map((s) => s['code']).toSet();
    expect(NiedScanPositions.points.length, 1634);
    for (final entry in expected.entries) {
      expect(db, contains(entry.key));
      final point = NiedScanPositions.points[entry.key]!;
      expect([
        point.centerX,
        point.centerY,
        point.offsetX,
        point.offsetY,
      ], entry.value);
      expect(NiedScanPositions.positions[entry.key], [
        entry.value[0] + entry.value[2],
        entry.value[1] + entry.value[3],
      ]);
      final samePixel = NiedScanPositions.points.entries.where(
        (s) =>
            s.value.sampleX == point.sampleX &&
            s.value.sampleY == point.sampleY,
      );
      expect(samePixel.map((s) => s.key), [entry.key]);
    }
    for (final code in ['MIE014', 'MIE017', 'OSK010']) {
      expect(NiedScanPositions.positions.containsKey(code), false);
    }
  });

  test(
    'real archived GIF uses offset pixels in worker and station construction',
    () async {
      final file = File(
        'test/fixtures/nied_recovery/20260610180121.lmoni.jma_s.gif',
      );
      final originalBytes = file.readAsBytesSync();
      final image = images.decodeGif(originalBytes)!;
      expect([image.width, image.height], [352, 400]);
      final codes = expected.keys.toList();
      final scanned = await NiedBackgroundWorker.instance.scanFrame(
        surfaceBytes: originalBytes,
        configs: [
          for (final code in codes)
            NiedScanConfig(
              pixelX: NiedScanPositions.points[code]!.sampleX,
              pixelY: NiedScanPositions.points[code]!.sampleY,
            ),
        ],
        configSignature:
            '${NiedScanPositions.version}-upstream-offset-regression',
      );
      expect(scanned, isNotNull);
      for (var i = 0; i < codes.length; i++) {
        final p = NiedScanPositions.points[codes[i]]!;
        final pixel = image.getPixel(p.sampleX, p.sampleY);
        final expectedPosition = ShindoColorUtil.rgbaToPosition(
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
        );
        expect(
          scanned!.samples[i].surfacePosition,
          expectedPosition == null ? isNull : closeTo(expectedPosition, 1e-9),
        );
      }
      final service = LmoniImageService()
        ..stop()
        ..start();
      addTearDown(service.stop);
      final stationsFuture = service.stationStream.first;
      service.processPixels(
        [
          for (var y = 0; y < image.height; y++)
            for (var x = 0; x < image.width; x++)
              (image.getPixel(x, y).r.toInt() << 16) |
                  (image.getPixel(x, y).g.toInt() << 8) |
                  image.getPixel(x, y).b.toInt(),
        ],
        surfaceGifBytes: originalBytes,
        dataTime: DateTime.utc(2026, 6, 10, 9, 1, 21),
      );
      final stations = await stationsFuture.timeout(const Duration(seconds: 5));
      for (final code in codes) {
        final station = stations!.singleWhere((s) => s.code == code);
        final point = NiedScanPositions.points[code]!;
        expect(
          [station.pixelX, station.pixelY],
          [point.sampleX, point.sampleY],
        );
      }
      expect(file.readAsBytesSync(), originalBytes);
    },
  );
}
