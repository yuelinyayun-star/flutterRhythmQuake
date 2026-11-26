import 'dart:typed_data';
import '../../models/fssn_station_frame.dart';

class NativeFssnStations {
  NativeFssnStations(Uint8List layout) {
    throw UnsupportedError('FSSN stations require the native station core');
  }
  static bool get supported => false;
  FssnStationFrame process(Uint8List bytes) =>
      throw UnsupportedError('FSSN stations require the native station core');
  void dispose() {}
}
