import 'dart:typed_data';

class NativeHypGeometry {
  NativeHypGeometry(List<double> coordinates) {
    throw UnsupportedError('Native HYP geometry requires Windows');
  }
  static bool get supported => false;
  static int get calls => 0;
  Float64List evaluate(double latitude, double longitude, double depthKm) =>
      throw UnsupportedError('Native HYP geometry unavailable');
  void dispose() {}
}
