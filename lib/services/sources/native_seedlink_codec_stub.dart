import 'dart:typed_data';

class NativeSeedLinkCodec {
  static bool get supported => false;
  static Int32List decode(
    Uint8List payload, {
    required int encoding,
    required Endian endian,
    required int sampleCount,
  }) => throw UnsupportedError('Native SeedLink codec requires Windows');
  static void releaseScratch() {}
}
