import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../models/source_payload.dart';
import 'sources/native_station_core_library_io.dart';

/// FFI codec only. Native parsing/grouping runs outside the Flutter UI isolate.
abstract final class NativeJmaTsunami {
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static Future<Map<String, dynamic>> prepareAsync(
    Map<String, dynamic> command,
  ) => Isolate.run(() => prepare(command));

  // Synchronous entry is for the existing synchronous replay/parser API.
  static Map<String, dynamic> prepare(Map<String, dynamic> command) {
    final input = JsonUtf8Encoder().convert(command);
    return using((arena) {
      final data = arena<Uint8>(input.length), length = arena<Size>();
      data.asTypedList(input.length).setAll(0, input);
      final output = _api.prepare(data, input.length, length);
      if (output == nullptr) {
        throw StateError('JMA tsunami native preparation failed');
      }
      try {
        final result = Map<String, dynamic>.from(
          PackedSourceJson(
                Uint8List.fromList(output.asTypedList(length.value)),
              ).root
              as Map,
        );
        if (result['error'] != null) {
          throw FormatException(result['error'] as String);
        }
        return result;
      } finally {
        _api.free(output, length.value);
      }
    });
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final prepare = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
      >('rq_jma_tsunami_prepare');
  late final free = lib
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_jma_tsunami_free');
}
