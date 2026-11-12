import 'dart:typed_data';

class NativeReplayLogSession {
  NativeReplayLogSession({void Function(Map<String, dynamic>)? onStatus});
  static bool get supported => false;
  static int get activeWorkers => 0;
  Map<String, dynamic> get lastStatus => const {};
  Never _unavailable() =>
      throw UnsupportedError('Native replay archive unavailable');
  void start({
    required String sessionStart,
    required String stamp,
    required String outputDirectory,
    required bool writeToDisk,
  }) => _unavailable();
  void append(int type, Map<String, dynamic> record) => _unavailable();
  void appendRaw(int type, Uint8List originalJson) => _unavailable();
  void capture(Map<String, dynamic> metadata, Uint8List originalGif) =>
      _unavailable();
  Future<void> save() => _unavailable();
  void saveSync() => _unavailable();
  void stopSync() => _unavailable();
  void barrier() => _unavailable();
  Map<String, dynamic> refreshStatus() => _unavailable();
  List<Map<String, dynamic>> readRecords() => _unavailable();
  void dispose() {}
}
