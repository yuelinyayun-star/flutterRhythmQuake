import 'dart:convert';
import 'dart:ffi';
import 'sources/native_station_core_library_io.dart';

/// Rust owns and queries official SGIS polygons; Dart consumes UTF-8 names.
abstract final class NativeKoreaLandRegions {
  static bool get supported => StationCoreLibrary.supported;
  static final _lookup = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Double, Double, Pointer<Size>),
        Pointer<Uint8> Function(double, double, Pointer<Size>)
      >('rq_korea_land_lookup');
  static final _length = StationCoreBuffer(sizeOf<Size>());

  static String? lookup(double lat, double lon) {
    if (!supported) return null;
    final length = _length.pointer.cast<Size>();
    final result = _lookup(lat, lon, length);
    return result == nullptr
        ? null
        : utf8.decode(result.asTypedList(length.value));
  }
}
