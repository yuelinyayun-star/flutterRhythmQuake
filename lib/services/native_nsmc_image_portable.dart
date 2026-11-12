import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Explicit backend for platforms without station-core support.
abstract final class NativeNsmcImage {
  static bool get supported => false;
  static const limit = 85.0511287798066;
  static List<double> bounds(int z, int x, int y) {
    if (z < 0 || z > 8 || y < 0 || y >= (1 << z))
      throw const FormatException('Invalid cloud tile');
    final n = 1 << z;
    final wrapped = x % n;
    double lat(int v) =>
        (2 * math.atan(math.exp(math.pi * (1 - 2 * v / n))) - math.pi / 2) *
        180 /
        math.pi;
    return [
      wrapped / n * 360 - 180,
      lat(y + 1),
      (wrapped + 1) / n * 360 - 180,
      lat(y),
    ];
  }

  static Uint8List project(Uint8List bytes, {int z = -1, int y = 0}) {
    final source = img.decodePng(bytes), global = z == -1;
    if (z < -1 ||
        source == null ||
        source.width != (global ? 2048 : 256) ||
        source.height != (global ? 1024 : 256))
      throw const FormatException('Invalid NSMC cloud image');
    final b = global ? [-180.0, -limit, 180.0, limit] : bounds(z, 0, y);
    final rgba = source
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    if (global &&
        !Iterable.generate(
          rgba.length ~/ 4,
          (i) => rgba[i * 4 + 3],
        ).any((a) => a > 0))
      throw const FormatException('Empty NSMC cloud image');
    final height = global ? 2048 : 256,
        width = source.width,
        stride = source.width * 4;
    final output = Uint8List(height * stride);
    for (var row = 0; row < height; row++) {
      final fraction = global
          ? (row + .5) / height
          : (y + (row + .5) / height) / (1 << z);
      final lat =
          (2 * math.atan(math.exp(math.pi * (1 - 2 * fraction))) -
              math.pi / 2) *
          180 /
          math.pi;
      final from =
          (((b[3] - lat) / (b[3] - b[1]) * source.height).floor().clamp(
            0,
            source.height - 1,
          )) *
          stride;
      output.setRange(row * stride, (row + 1) * stride, rgba, from);
    }
    return img.encodePng(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: output.buffer,
        numChannels: 4,
      ),
    );
  }
}
