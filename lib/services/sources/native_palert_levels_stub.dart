import 'dart:typed_data';

class NativePAlertLevels {
  static bool get supported => false;
  void configure(Int32List remap) =>
      throw UnsupportedError('Windows native core');
  Int32List process(int time, Float64List input) =>
      throw UnsupportedError('Windows native core');
  void dispose() {}
}
