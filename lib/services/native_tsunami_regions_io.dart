import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../models/source_payload.dart';
import 'sources/native_station_core_library_io.dart';

/// Raw bytes go to Rust off the UI isolate, only prepared lines return.
abstract final class NativeTsunamiRegions {
  static bool get supported => StationCoreLibrary.supported;
  static Future<Map<String, dynamic>> prepare(
    Map<String, dynamic> command, {
    Uint8List? document,
  }) => Isolate.run(() => _prepare(command, document));
  static Map<String, dynamic> _prepare(
    Map<String, dynamic> command,
    Uint8List? document,
  ) {
    final lib = StationCoreLibrary.library;
    final prepare = lib
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
        >('rq_tsunami_regions_prepare');
    final free = lib
        .lookupFunction<
          Void Function(Pointer<Uint8>, Size),
          void Function(Pointer<Uint8>, int)
        >('rq_tsunami_regions_free');
    final bytes = JsonUtf8Encoder().convert(command);
    return using((arena) {
      final input = arena<Uint8>(bytes.length), length = arena<Size>();
      input.asTypedList(bytes.length).setAll(0, bytes);
      final body = document == null || document.isEmpty
          ? nullptr.cast<Uint8>()
          : arena<Uint8>(document.length);
      if (document != null && document.isNotEmpty) {
        body.asTypedList(document.length).setAll(0, document);
      }
      final result = prepare(
        input,
        bytes.length,
        body,
        document?.length ?? 0,
        length,
      );
      if (result == nullptr) {
        throw StateError('Tsunami geometry preparation failed');
      }
      try {
        final output = Map<String, dynamic>.from(
          PackedSourceJson(
                Uint8List.fromList(result.asTypedList(length.value)),
              ).root
              as Map,
        );
        if (output['error'] != null) {
          throw FormatException(output['error'] as String);
        }
        return output;
      } finally {
        free(result, length.value);
      }
    });
  }
}
