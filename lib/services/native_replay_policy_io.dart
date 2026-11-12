import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_replay_policy_portable.dart' as portable;
import 'sources/native_station_core_library_io.dart';

/// A bounded borrowed-input command; native errors are never replaced by Dart
/// policy on supported platforms. No native report/session survives this call.
abstract final class NativeReplayPolicy {
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static int get calls => _api.calls();
  static int get outputs => _api.outputs();
  static dynamic prepare(Map<String, dynamic> request) {
    if (!supported) return portable.NativeReplayPolicy.prepare(request);
    final bytes = JsonUtf8Encoder().convert(request);
    return using((arena) {
      final input = arena<Uint8>(bytes.length), length = arena<Size>();
      input.asTypedList(bytes.length).setAll(0, bytes);
      final pointer = _api.prepare(input, bytes.length, length);
      if (pointer == nullptr) throw StateError('Rust replay policy failed');
      try {
        final result = jsonDecode(
          utf8.decode(pointer.asTypedList(length.value)),
        );
        if (result is Map && result['error'] != null) {
          throw StateError('Rust replay policy: ${result['error']}');
        }
        return result;
      } finally {
        _api.free(pointer, length.value);
      }
    });
  }
}

class _Bindings {
  final library = StationCoreLibrary.library;
  late final prepare = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
      >('rq_replay_policy_prepare');
  late final free = library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_replay_policy_free');
  late final calls = library.lookupFunction<Uint64 Function(), int Function()>(
    'rq_replay_policy_calls',
  );
  late final outputs = library
      .lookupFunction<Uint64 Function(), int Function()>(
        'rq_replay_policy_outputs',
      );
}
