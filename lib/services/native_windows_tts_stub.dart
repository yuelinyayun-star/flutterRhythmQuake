abstract final class NativeWindowsTts {
  static bool get supported => false;
  static int get outputs => 0;

  static Future<Map<String, dynamic>> probe() =>
      throw UnsupportedError('Windows speech detection is unavailable');

  static Future<void> synthesize({
    required String text,
    required String file,
    required int rate,
    required int volume,
    required String voice,
  }) => throw UnsupportedError('Windows SAPI synthesis is unavailable');

  static int abort() => 0;
}
