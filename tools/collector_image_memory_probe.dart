import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/services/sources/station_image_decoder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final path = Platform.environment['RQ_PROBE_IMAGE'];
  if (path == null) exit(64);
  final bytes = await File(path).readAsBytes();
  final software = Platform.environment['RQ_PROBE_DECODER'] == 'software';
  await Future<void>.delayed(const Duration(seconds: 2));
  for (var index = 0; index < 1000; index++) {
    final Uint8List pixels;
    if (software) {
      final decoded = await StationImageDecoder.decodeCpu(bytes);
      if (decoded == null) throw StateError('Cannot decode original image');
      pixels = decoded.rgba;
    } else {
      final codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      final ByteData? data;
      try {
        data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        frame.image.dispose();
      }
      if (data == null) throw StateError('Cannot read original image pixels');
      pixels = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    if (pixels.isEmpty) throw StateError('Empty decoded pixels');
    if (index % 100 == 0) {
      stdout.writeln(
        'decoder=${software ? "software" : "native"} '
        'frames=${index + 1} rss=${ProcessInfo.currentRss}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(seconds: 5));
  stdout.writeln('frames=1000 rss=${ProcessInfo.currentRss}');
  exit(0);
}
