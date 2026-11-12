import 'dart:ffi';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';
import 'native_jma_eew_portable.dart' as portable;

/// Scalar codec only; supported native platforms never silently fall back.
abstract final class NativeJmaEew {
  static bool get supported => StationCoreLibrary.supported;
  static final _isPlum = StationCoreLibrary.library
      .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
        'rq_jma_eew_is_plum',
      );
  static final _longPeriodClass = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Uint32, Pointer<Uint8>, Size),
        int Function(int, Pointer<Uint8>, int)
      >('rq_jma_eew_lg_int_class');

  static int? longPeriodClass({
    required String source,
    required bool isEew,
    required Object? value,
  }) {
    if (!supported) {
      return portable.NativeJmaEew.longPeriodClass(
        source: source,
        isEew: isEew,
        value: value,
      );
    }
    final flags = (source == 'jmaEew' ? 1 : 0) | (isEew ? 2 : 0);
    final bytes = utf8.encode(
      value is String || value is num ? value.toString() : '',
    );
    return using((arena) {
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      final result = _longPeriodClass(flags, data, bytes.length);
      return result < 0 ? null : result;
    });
  }

  static bool isPlum({
    required String source,
    required bool isEew,
    required bool isAssumption,
    required bool wireIsPlum,
  }) {
    if (!supported) {
      return portable.NativeJmaEew.isPlum(
        source: source,
        isEew: isEew,
        isAssumption: isAssumption,
        wireIsPlum: wireIsPlum,
      );
    }
    final flags =
        (source == 'jmaEew' ? 1 : 0) |
        (isEew ? 2 : 0) |
        (isAssumption ? 4 : 0) |
        (wireIsPlum ? 8 : 0);
    return _isPlum(flags) != 0;
  }
}
