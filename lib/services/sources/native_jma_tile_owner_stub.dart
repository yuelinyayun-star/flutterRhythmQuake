import 'dart:typed_data';

class NativeJmaTileOwner {
  NativeJmaTileOwner({
    required bool satellite,
    required void Function(Map<String, dynamic>?) onFrame,
  });
  static bool get supported => false;
  static int get workers => 0;
  void start({
    required Duration interval,
    int attempts = 1,
    Uri? testEndpoint,
    Duration? testTimeout,
  }) => throw UnsupportedError('Native JMA tile owner');
  void stop({bool clear = false}) {}
  Future<void> fetch({int attempts = 1}) async {}
  Future<Map<String, dynamic>> diagnostics() async => {};
  Future<Uint8List?> tile(String path, Future<void> cancel) async =>
      throw UnsupportedError('Native JMA image');
  void dispose() {}
}
