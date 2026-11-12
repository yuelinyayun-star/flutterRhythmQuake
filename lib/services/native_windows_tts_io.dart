import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';

abstract final class NativeWindowsTts {
  static bool get supported =>
      Platform.isWindows && StationCoreLibrary.supported;
  static final _lib = StationCoreLibrary.library;
  static final _probe = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Size>)
      >('rq_windows_tts_probe');
  static final _synthesize = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
      >('rq_windows_tts_synthesize');
  static final _abort = _lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_windows_tts_abort',
  );
  static final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_windows_tts_free');
  static final _outputs = _lib.lookupFunction<Size Function(), int Function()>(
    'rq_windows_tts_outputs',
  );

  static int get outputs => supported ? _outputs() : 0;

  static Future<Map<String, dynamic>> probe() {
    if (!supported) {
      throw UnsupportedError('Native Windows speech probe unavailable');
    }
    return Isolate.run(_runProbe);
  }

  static Future<void> synthesize({
    required String text,
    required String file,
    required int rate,
    required int volume,
    required String voice,
  }) async {
    if (!supported) {
      throw UnsupportedError('Native Windows SAPI synthesis unavailable');
    }
    final payload = utf8.encode(
      jsonEncode({
        'text': text,
        'file': file,
        'rate': rate,
        'volume': volume,
        'voice': voice,
      }),
    );
    final result = await Isolate.run(() => _runSynthesize(payload));
    if (result['ok'] != true) {
      throw StateError(
        result['error']?.toString() ?? 'Windows SAPI synthesis failed',
      );
    }
  }

  static int abort() => supported ? _abort() : 0;

  static Map<String, dynamic> _runProbe() => using((arena) {
    final size = arena<Size>();
    final output = _probe(size);
    if (output == nullptr) throw StateError('Rust Windows speech probe failed');
    try {
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(output.asTypedList(size.value))) as Map,
      );
    } finally {
      _free(output, size.value);
    }
  });

  static Map<String, dynamic> _runSynthesize(List<int> payload) =>
      using((arena) {
        final inputPtr = arena<Uint8>(payload.isEmpty ? 1 : payload.length);
        if (payload.isNotEmpty) {
          inputPtr.asTypedList(payload.length).setAll(0, payload);
        }
        final outSize = arena<Size>();
        final output = _synthesize(inputPtr, payload.length, outSize);
        if (output == nullptr) {
          throw StateError('Rust Windows SAPI synthesis failed');
        }
        try {
          return Map<String, dynamic>.from(
            jsonDecode(utf8.decode(output.asTypedList(outSize.value))) as Map,
          );
        } finally {
          _free(output, outSize.value);
        }
      });
}
