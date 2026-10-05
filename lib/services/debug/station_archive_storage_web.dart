import 'package:archive/archive.dart';

List<int> compress(List<int> bytes) => GZipEncoder().encode(bytes, level: 1);
List<int> expand(List<int> bytes, int limit) {
  final output = GZipDecoder().decodeBytes(bytes);
  if (output.length > limit) {
    throw const FormatException('Station archive too large');
  }
  return output;
}
