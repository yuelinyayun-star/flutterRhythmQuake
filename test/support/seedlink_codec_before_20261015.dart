import 'dart:math';
import 'dart:typed_data';

class DartMiniSeedDecoderReference {
  static List<int> decode(
    Uint8List payload, {
    required int encoding,
    required Endian endian,
    required int sampleCount,
  }) {
    if (payload.isEmpty || sampleCount <= 0) return const [];
    switch (encoding) {
      case 1:
        return _decodeInt16(payload, endian, sampleCount);
      case 3:
        return _decodeInt32(payload, endian, sampleCount);
      case 10:
        return _decodeSteim1(payload, sampleCount, endian);
      case 11:
        return _decodeSteim2(payload, sampleCount, endian);
      default:
        return const [];
    }
  }

  static List<int> _decodeInt16(Uint8List payload, Endian endian, int count) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(count, payload.length ~/ 2));
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, endian);
    }
    return out;
  }

  static List<int> _decodeInt32(Uint8List payload, Endian endian, int count) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(count, payload.length ~/ 4));
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt32(i * 4, endian);
    }
    return out;
  }

  static List<int> _decodeSteim1(
    Uint8List payload,
    int sampleCount,
    Endian endian,
  ) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(sampleCount, payload.length * 2));
    var written = 0;
    int? previous;
    var skipFirstDifference = true;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, endian);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, endian);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, endian);
          out[written++] = previous;
          if (written == out.length) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return Int32List.sublistView(out, 0, written);
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final count = switch (code) {
          1 => 4,
          2 => 2,
          3 => 1,
          _ => 0,
        };
        for (var j = 0; j < count; j++) {
          final diff = switch (code) {
            1 => data.getInt8(wordOffset + j),
            2 => data.getInt16(wordOffset + j * 2, endian),
            _ => _signExtend(word, 32),
          };
          // D0 links the previous record to X0; X0 is already in the output.
          if (skipFirstDifference) {
            skipFirstDifference = false;
            continue;
          }
          current = (current + diff).toSigned(32);
          previous = current;
          out[written++] = current;
          if (written == out.length) return out;
        }
      }
    }
    return Int32List.sublistView(out, 0, written);
  }

  static List<int> _decodeSteim2(
    Uint8List payload,
    int sampleCount,
    Endian endian,
  ) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(sampleCount, payload.length * 2));
    var written = 0;
    int? previous;
    var skipFirstDifference = true;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, endian);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, endian);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, endian);
          out[written++] = previous;
          if (written == out.length) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return Int32List.sublistView(out, 0, written);
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final dnib = (word >> 30) & 3;
        final (count, bits) = switch ((code, dnib)) {
          (1, _) => (4, 8),
          (2, 1) => (1, 30),
          (2, 2) => (2, 15),
          (2, 3) => (3, 10),
          (3, 0) => (5, 6),
          (3, 1) => (6, 5),
          (3, 2) => (7, 4),
          _ => (0, 0),
        };
        for (var j = 0; j < count; j++) {
          final diff = code == 1
              ? data.getInt8(wordOffset + j)
              : _signExtend(word >> ((count - 1 - j) * bits), bits);
          if (skipFirstDifference) {
            skipFirstDifference = false;
            continue;
          }
          current = (current + diff).toSigned(32);
          previous = current;
          out[written++] = current;
          if (written == out.length) return out;
        }
      }
    }
    return Int32List.sublistView(out, 0, written);
  }

  static int _signExtend(int value, int bits) {
    if (bits >= 32) return value.toSigned(32);
    final signBit = 1 << (bits - 1);
    final mask = (1 << bits) - 1;
    value &= mask;
    return (value & signBit) != 0 ? value - (1 << bits) : value;
  }
}
