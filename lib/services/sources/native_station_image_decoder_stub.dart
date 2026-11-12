import 'dart:typed_data';

class NativeStationImageFrame {
  const NativeStationImageFrame(this.width, this.height, this.pixels);
  final int width;
  final int height;
  final Uint64List pixels;
}

class NativeStationImageDecoder {
  NativeStationImageDecoder(List<int> coordinates) {
    throw UnsupportedError(
      'Rust station decoder is not available on this platform',
    );
  }
  static bool get supported => false;
  static Map<String, int> get memoryStats => const {};
  int get bufferCapacityBytes => 0;
  NativeStationImageFrame decode(Uint8List bytes) => throw UnsupportedError(
    'Rust station decoder is not available on this platform',
  );
  void dispose() {}
  NativeNiedImageFrame sampleNied(Uint8List bytes, {bool physical = false}) =>
      throw UnsupportedError('Native NIED GIF sampling is unavailable');
}

class NativeNiedImageFrame {
  const NativeNiedImageFrame(this.width, this.height, this.values);
  final int width, height;
  final Float64List values;
}
