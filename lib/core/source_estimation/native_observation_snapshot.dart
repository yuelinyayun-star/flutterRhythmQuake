import 'dart:typed_data';

/// Owned, pointer-free packed ABI 1. Compression is lossless; wide rows retain
/// every original word when a delta, level or metadata ID cannot fit.
class NativeObservationSnapshot {
  NativeObservationSnapshot(this.bytes, this.count, this.baseUs, int wideCount)
    : data = ByteData.sublistView(bytes) {
    if (count < 0 ||
        wideCount < 0 ||
        bytes.length != count * 24 + wideCount * 64) {
      throw const FormatException('Invalid packed observation snapshot');
    }
    for (var index = 0; index < wideCount; index++) {
      final offset = count * 24 + index * 64;
      wideOffsets[data.getUint64(offset, Endian.little)] = offset + 8;
    }
  }
  final Uint8List bytes;
  final ByteData data;
  final int count, baseUs;
  final Map<int, int> wideOffsets = {};
}
