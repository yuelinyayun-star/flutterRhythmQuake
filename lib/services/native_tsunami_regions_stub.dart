import 'dart:typed_data';

abstract final class NativeTsunamiRegions {
  static bool get supported => false;
  static Future<Map<String, dynamic>> prepare(
    Map<String, dynamic> command, {
    Uint8List? document,
  }) =>
      Future.error(UnsupportedError('Native tsunami geometry is unavailable'));
}
