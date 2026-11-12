abstract final class NativeJmaTsunami {
  static bool get supported => false;
  static Map<String, dynamic> prepare(Map<String, dynamic> command) =>
      throw UnsupportedError('Native JMA tsunami requires the native core');
  static Future<Map<String, dynamic>> prepareAsync(
    Map<String, dynamic> command,
  ) async => prepare(command);
}
