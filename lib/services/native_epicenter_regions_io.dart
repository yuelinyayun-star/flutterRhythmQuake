import 'dart:convert';
import 'dart:ffi';

import 'sources/native_station_core_library_io.dart';

abstract final class NativeEpicenterRegions {
  static bool get supported => StationCoreLibrary.supported;

  static final _prepare = StationCoreLibrary.library
      .lookupFunction<Uint32 Function(), int Function()>(
        'rq_epicenter_regions_prepare',
      );
  static final _lookup = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Double, Double, Uint32, Pointer<Size>),
        Pointer<Uint8> Function(double, double, int, Pointer<Size>)
      >('rq_epicenter_regions_lookup');
  static final _length = StationCoreBuffer(sizeOf<Size>());

  static void prepare() {
    if (_prepare() != 1) {
      throw StateError('Native epicenter region index failed to initialize');
    }
  }

  static String? lookup(
    double latitude,
    double longitude, {
    bool chinaOnly = false,
  }) {
    final length = _length.pointer.cast<Size>();
    final name = _lookup(latitude, longitude, chinaOnly ? 1 : 0, length);
    return name == nullptr ? null : utf8.decode(name.asTypedList(length.value));
  }
}
