import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';
import 'native_weather_playback_catalog_portable.dart' as portable;

abstract final class NativeWeatherPlaybackCatalog {
  static bool get supported => StationCoreLibrary.supported;
  static final _parse = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Uint8> Function(Uint32, Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(int, Pointer<Uint8>, int, Pointer<Size>)
      >('rq_weather_playback_catalog');
  static final _free = StationCoreLibrary.library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_weather_playback_free');
  static List<Map<String, dynamic>> parse(int kind, Uint8List bytes) {
    if (!supported)
      return portable.NativeWeatherPlaybackCatalog.parse(kind, bytes);
    return using((arena) {
      final input = arena<Uint8>(bytes.length)
        ..asTypedList(bytes.length).setAll(0, bytes);
      final size = arena<Size>();
      final output = _parse(kind, input, bytes.length, size);
      if (output == nullptr)
        throw StateError('Weather playback catalog failed');
      try {
        final value = jsonDecode(utf8.decode(output.asTypedList(size.value)));
        if (value is Map) throw FormatException('${value['error']}');
        return (value as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } finally {
        _free(output, size.value);
      }
    });
  }
}
