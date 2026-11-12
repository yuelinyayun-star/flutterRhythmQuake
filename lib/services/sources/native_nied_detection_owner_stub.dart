import 'nied_monitor.dart';

class NativeNiedDetectionOwner {
  NativeNiedDetectionOwner(
    List<NiedStation> stations, {
    required void Function(List<dynamic>) onUpdate,
    bool manualClock = false,
  }) {
    throw UnsupportedError('Native NIED detection requires Windows');
  }
  static bool get supported => false;
  static Map<String, int> get diagnostics => const {};
  String? get layerSignature => null;
  void process(List<NiedStation> stations, int sensitivity, {int clock = 0}) {}
  void tick(int clock) {}
  void rebind(List<NiedStation> stations) {}
  void reset({required bool clearHolds}) {}
  void dispose() {}
}
