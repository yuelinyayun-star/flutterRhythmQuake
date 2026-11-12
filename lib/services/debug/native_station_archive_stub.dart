import 'dart:typed_data';

class NativeStationArchive {
  static bool get supported => false;
  static int get sessions => 0;
  static int get calls => 0;
  static Uint8List encodeCompressed(List<Map<String, dynamic>> frames) =>
      throw UnsupportedError('Native station archives require Windows');
  static Uint8List encode(List<Map<String, dynamic>> frames) =>
      throw UnsupportedError('Native station archives require Windows');
}
