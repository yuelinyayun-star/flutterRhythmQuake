import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

class StationImagePixels {
  const StationImagePixels(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  Uint32List get packedRgb {
    final result = Uint32List(width * height);
    for (var index = 0; index < result.length; index++) {
      final offset = index * 4;
      result[index] =
          (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
    }
    return result;
  }
}

/// The headless collector must not allocate Skia images: disposing them under
/// a static Xvfb Flutter root still retains native memory on this Linux engine.
class StationImageDecoder {
  static bool cpuOnly = false;

  static Future<StationImagePixels?> decodeCpu(Uint8List bytes) =>
      compute(decodeStationImageCpu, bytes);
}

StationImagePixels? decodeStationImageCpu(Uint8List bytes) {
  if (bytes.length > 8 * 1024 * 1024) return null;
  try {
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 1024 * 1024) {
      return null;
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return null;
    // Palette images expose index bytes through getBytes even with RGBA order.
    final rgba =
        (decoded.hasPalette
                ? decoded.convert(numChannels: 4, withPalette: false)
                : decoded)
            .getBytes(order: image.ChannelOrder.rgba);
    // Match dart:ui rawRgba's premultiplied-alpha representation.
    for (var offset = 0; offset < rgba.length; offset += 4) {
      final alpha = rgba[offset + 3];
      if (alpha == 255) continue;
      for (var channel = 0; channel < 3; channel++) {
        rgba[offset + channel] = (rgba[offset + channel] * alpha + 127) ~/ 255;
      }
    }
    return StationImagePixels(decoded.width, decoded.height, rgba);
  } catch (_) {
    return null;
  }
}
