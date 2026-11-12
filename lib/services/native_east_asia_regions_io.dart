import 'dart:convert';
import 'dart:ffi';
import 'sources/native_station_core_library_io.dart';

/// Static clipped regions are owned and queried in Rust; UI receives a name.
abstract final class NativeEastAsiaRegions {
  static bool get supported => StationCoreLibrary.supported;
  static final _lookup = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Double, Double, Pointer<Size>),
        Pointer<Uint8> Function(double, double, Pointer<Size>)
      >('rq_east_asia_place_lookup');
  static final _length = StationCoreBuffer(sizeOf<Size>());
  static final _datasetHash = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Size>)
      >('rq_east_asia_dataset_sha256');
  static String? get datasetSha256 {
    if (!supported) return null;
    final length = _length.pointer.cast<Size>();
    final p = _datasetHash(length);
    return p == nullptr ? null : utf8.decode(p.asTypedList(length.value));
  }

  static final _chinaLand = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Double, Double, Pointer<Size>),
        Pointer<Uint8> Function(double, double, Pointer<Size>)
      >('rq_east_asia_china_land_lookup');
  static String? chinaLandName(double lat, double lon) {
    if (!supported) return null;
    final length = _length.pointer.cast<Size>();
    final p = _chinaLand(lat, lon, length);
    return p == nullptr ? null : utf8.decode(p.asTypedList(length.value));
  }

  static String? lookup(double lat, double lon) {
    if (!supported) return null;
    final length = _length.pointer.cast<Size>();
    final p = _lookup(lat, lon, length);
    return p == nullptr ? null : utf8.decode(p.asTypedList(length.value));
  }
}
