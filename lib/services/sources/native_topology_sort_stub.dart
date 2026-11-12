import 'dart:typed_data';

class NativeTopologySort {
  NativeTopologySort(List<int> ids) {
    throw UnsupportedError('Native topology sorting requires Windows');
  }
  static bool get supported => false;
  static int get calls => 0;
  Float64List get distances =>
      throw UnsupportedError('Native topology unavailable');
  Uint32List sort() => throw UnsupportedError('Native topology unavailable');
  void dispose() {}
}
