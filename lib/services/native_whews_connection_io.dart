import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';
import 'native_whews_connection_portable.dart' as portable;

abstract final class NativeWhewsConnection {
  static bool get supported => StationCoreLibrary.supported;
  static final _library = StationCoreLibrary.library;
  static final _prepare = _library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
      >('rq_whews_connection_prepare');
  static final _free = _library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_whews_connection_free');
  static final _outputs = _library
      .lookupFunction<Size Function(), int Function()>(
        'rq_whews_connection_outputs',
      );
  static int get outputs => supported ? _outputs() : 0;
  static dynamic prepare(Map<String, dynamic> request) {
    if (!supported) return portable.NativeWhewsConnection.prepare(request);
    final bytes = JsonUtf8Encoder().convert(request);
    return using((arena) {
      final input = arena<Uint8>(bytes.length), length = arena<Size>();
      input.asTypedList(bytes.length).setAll(0, bytes);
      final result = _prepare(input, bytes.length, length);
      if (result == nullptr) {
        throw StateError('Native WHEWS connection policy failed');
      }
      try {
        final decoded = jsonDecode(
          utf8.decode(result.asTypedList(length.value)),
        );
        if (decoded is Map && decoded['error'] != null) {
          throw StateError(
            'Native WHEWS connection policy: ${decoded['error']}',
          );
        }
        return decoded;
      } finally {
        _free(result, length.value);
      }
    });
  }
}
