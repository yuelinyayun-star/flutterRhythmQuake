import 'dart:typed_data';

class NativeStationRuntime {
  static bool get supported => false;
  static int get workers => 0;
  void Function(Map<String, dynamic>)? onFrame;
  void Function(List<dynamic>)? onPreparedPAlert;
  void start(Map<String, Object?> settings) =>
      throw UnsupportedError('Native station runtime');
  void settings(Map<String, Object?> settings) {}
  void injectOriginal(List<int> bytes, DateTime clock) {}
  void injectPacked(Uint8List bytes, int root, DateTime clock) {}
  Map<String, dynamic>? get original => null;
  Map<String, dynamic>? get archive => null;
  void stop() {}
}
