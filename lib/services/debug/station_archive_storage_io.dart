import 'dart:io';
import 'dart:typed_data';

List<int> compress(List<int> bytes) => GZipCodec(level: 1).encode(bytes);

List<int> expand(List<int> bytes, int limit) {
  final output = _BoundedBytes(limit);
  final converter = gzip.decoder.startChunkedConversion(output);
  converter.add(bytes);
  converter.close();
  return output.bytes.takeBytes();
}

class _BoundedBytes implements Sink<List<int>> {
  _BoundedBytes(this.limit);
  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int length = 0;
  @override
  void add(List<int> value) {
    length += value.length;
    if (length > limit) {
      throw const FormatException('Station archive too large');
    }
    bytes.add(value);
  }

  @override
  void close() {}
}
