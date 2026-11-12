import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';
import 'native_dyfi_grid_portable.dart' as portable;

abstract final class NativeDyfiGrid {
  static bool get supported => StationCoreLibrary.supported;
  static final _lib = StationCoreLibrary.library;
  static final _call = _lib
      .lookupFunction<
        Pointer<Uint8> Function(
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
          Pointer<Size>,
        ),
        Pointer<Uint8> Function(
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Size>,
        )
      >('rq_dyfi_grid_prepare');
  static final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_dyfi_grid_free');
  static final _outputs = _lib.lookupFunction<Size Function(), int Function()>(
    'rq_dyfi_grid_outputs',
  );
  static int get outputs => supported ? _outputs() : 0;
  static Map<String, dynamic> select(List<String> files) => supported
      ? _prepare({'op': 'select', 'files': files}, null)
      : portable.NativeDyfiGrid.select(files);
  static Future<Map<String, dynamic>> decodeKmz(Uint8List document) => supported
      ? Isolate.run(() => _prepare({'op': 'kmz'}, document))
      : portable.NativeDyfiGrid.decodeKmz(document);
  static Map<String, dynamic> _prepare(
    Map<String, dynamic> command,
    Uint8List? document,
  ) {
    final bytes = JsonUtf8Encoder().convert(command);
    return using((arena) {
      final input = arena<Uint8>(bytes.length), size = arena<Size>();
      input.asTypedList(bytes.length).setAll(0, bytes);
      final body = document == null || document.isEmpty
          ? nullptr.cast<Uint8>()
          : arena<Uint8>(document.length);
      if (document != null && document.isNotEmpty) {
        body.asTypedList(document.length).setAll(0, document);
      }
      final result = _call(
        input,
        bytes.length,
        body,
        document?.length ?? 0,
        size,
      );
      if (result == nullptr) {
        throw StateError('Rust DYFI grid preparation failed');
      }
      try {
        final output = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(result.asTypedList(size.value))) as Map,
        );
        if (output['error'] != null) {
          throw FormatException(output['error'] as String);
        }
        return output;
      } finally {
        _free(result, size.value);
      }
    });
  }
}
