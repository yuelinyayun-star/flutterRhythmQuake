import 'dart:convert';
import 'dart:ffi';
import 'sources/native_station_core_library_io.dart';

/// Rust retains the static polygons and performs the complete new sea lookup.
/// Dart only decodes the returned UTF-8 display string.
abstract final class NativeJapanSeaRegions {
  static bool get supported => StationCoreLibrary.supported;
  static final _lookup = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Double, Double, Uint32, Pointer<Size>),
        Pointer<Uint8> Function(double, double, int, Pointer<Size>)
      >('rq_japan_sea_lookup');
  // Synchronous FFI has no callbacks; one caller-owned slot per isolate avoids
  // allocating a native length buffer for every place-name lookup.
  static final _length = StationCoreBuffer(sizeOf<Size>());

  static String? lookup(double lat, double lon, {bool domestic = false}) {
    if (!supported) return null;
    final length = _length.pointer.cast<Size>();
    final result = _lookup(lat, lon, domestic ? 1 : 0, length);
    if (result == nullptr) return null;
    return utf8.decode(result.asTypedList(length.value));
  }
}
