import 'dart:typed_data';
import 'native_ka_detector_result.dart';

class NativeKaDetector {
  NativeKaDetector.niedCoordinates(List<double> coordinates) {
    throw UnsupportedError('Native NIED detection requires Windows');
  }
  NativeKaDetector({
    required List<List<int>> adjacency,
    required double Function(int, int) distance,
  }) {
    throw UnsupportedError('Native KA detection requires Windows');
  }
  static bool get supported => false;
  static Map<String, int> get diagnostics => const {};
  void writeInput(
    int index, {
    required int kaLevel,
    required double activity,
    required int ascend,
    required bool isActive,
    required int triggerStamp,
    double continuousShindo = 0,
  }) => throw UnsupportedError('Native KA detection requires Windows');
  void writePacked(Int64List rows) =>
      throw UnsupportedError('Native KA detection requires Windows');
  NativeKaDetectionResult process({
    required int sensitivity,
    required bool hadActiveGrid,
  }) => throw UnsupportedError('Native KA detection requires Windows');
  void dispose() {}
}
