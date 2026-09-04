import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

Future<List<int>> _gifToPackedRgb(File file) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) throw StateError('toByteData returned null');

  final pixels = List<int>.filled(image.width * image.height, 0);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    final r = byteData.getUint8(offset);
    final g = byteData.getUint8(offset + 1);
    final b = byteData.getUint8(offset + 2);
    pixels[i] = (r << 16) | (g << 8) | b;
  }
  image.dispose();
  return pixels;
}

DateTime _timeFromName(String name) {
  final key = RegExp(r'(\d{14})\.jma_s\.gif').firstMatch(name)!.group(1)!;
  return DateTime(
    int.parse(key.substring(0, 4)),
    int.parse(key.substring(4, 6)),
    int.parse(key.substring(6, 8)),
    int.parse(key.substring(8, 10)),
    int.parse(key.substring(10, 12)),
    int.parse(key.substring(12, 14)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloaded GIF replay reaches NIED shake detection', () async {
    final dir = Directory('.dart_tool/nied_gif_20260531_1058_jst');
    if (!dir.existsSync()) {
      markTestSkipped('Downloaded GIF samples are not present.');
      return;
    }

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.gif'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final service = LmoniImageService()..start();
    final detector = ShakeDetectionService()..setSensitivity(2);
    final detected = <int>[];
    detector.onShakeDetected = detected.add;

    final sub = service.stationStream.listen((stations) {
      if (stations == null) return;
      detector.setStations(stations);
      detector.processUpdate();
    });

    for (final file in files) {
      final pixels = await _gifToPackedRgb(file);
      service.processPixels(
        pixels,
        dataTime: _timeFromName(file.uri.pathSegments.last),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await sub.cancel();
    service.stop();

    expect(detected, isNotEmpty);
    expect(detected.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(1));
  });
}
