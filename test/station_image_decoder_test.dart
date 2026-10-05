import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/station_image_decoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normal applications keep the existing native decoder', () {
    expect(StationImageDecoder.cpuOnly, isFalse);
  });

  test(
    'CPU pixels equal native pixels for unchanged NIED GIF and S-net PNG frames',
    () async {
      final files = [
        ...Directory('test/fixtures/nied_recovery')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.gif')),
        ...Directory('test/fixtures/station_image_decoder')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.png')),
      ];
      expect(files, isNotEmpty);
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final decoded = await StationImageDecoder.decodeCpu(bytes);
        expect(decoded, isNotNull, reason: file.path);
        final codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frame;
        try {
          frame = await codec.getNextFrame();
        } finally {
          codec.dispose();
        }
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(decoded!.width, frame.image.width);
          expect(decoded.height, frame.image.height);
          expect(
            decoded.rgba,
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            reason: file.path,
          );
        } finally {
          frame.image.dispose();
        }
      }
    },
  );

  test(
    'invalid image input is rejected without allocating native images',
    () async {
      expect(await StationImageDecoder.decodeCpu(Uint8List(0)), isNull);
      expect(
        await StationImageDecoder.decodeCpu(Uint8List(8 * 1024 * 1024 + 1)),
        isNull,
      );
    },
  );
}
