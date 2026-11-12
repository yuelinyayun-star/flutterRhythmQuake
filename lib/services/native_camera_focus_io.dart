import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'sources/native_station_core_library_io.dart';
import 'native_camera_focus_portable.dart' as portable;

/// Synchronous bounded camera commands. All Rust output ownership ends in
/// this call; failures on a supported platform are surfaced, never hidden.
abstract final class NativeCameraFocus {
  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static int get calls => _bindings.calls();
  static int get outputs => _bindings.outputs();
  static Map<String, dynamic> prepareGeometry(Float64List coordinates) {
    if (coordinates.length.isOdd || coordinates.length ~/ 2 > 2000000) {
      throw ArgumentError('Invalid camera geometry pair count');
    }
    if (!supported) {
      return portable.NativeCameraFocus.prepareGeometry(coordinates);
    }
    return using((arena) {
      final input = arena<Double>(coordinates.isEmpty ? 1 : coordinates.length);
      final length = arena<Size>();
      input.asTypedList(coordinates.length).setAll(0, coordinates);
      final p = _bindings.geometry(input, coordinates.length ~/ 2, length);
      if (p == nullptr) throw StateError('Rust camera geometry failed');
      try {
        return jsonDecode(utf8.decode(p.asTypedList(length.value)))
            as Map<String, dynamic>;
      } finally {
        _bindings.free(p, length.value);
      }
    });
  }

  static dynamic prepare(Map<String, dynamic> request) {
    if (!supported) return portable.NativeCameraFocus.prepare(request);
    final bytes = JsonUtf8Encoder().convert(request);
    return using((arena) {
      final input = arena<Uint8>(bytes.length), length = arena<Size>();
      input.asTypedList(bytes.length).setAll(0, bytes);
      final p = _bindings.prepare(input, bytes.length, length);
      if (p == nullptr) throw StateError('Rust camera focus failed');
      try {
        final result = jsonDecode(utf8.decode(p.asTypedList(length.value)));
        if (result is Map && result['error'] != null) {
          throw StateError('Rust camera focus: ${result['error']}');
        }
        return result;
      } finally {
        _bindings.free(p, length.value);
      }
    });
  }
}

class _Bindings {
  final library = StationCoreLibrary.library;
  late final geometry = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Double>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Double>, int, Pointer<Size>)
      >('rq_camera_geometry_prepare');
  late final prepare = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
      >('rq_camera_focus_prepare');
  late final free = library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_camera_focus_free');
  late final calls = library.lookupFunction<Uint64 Function(), int Function()>(
    'rq_camera_focus_calls',
  );
  late final outputs = library
      .lookupFunction<Uint64 Function(), int Function()>(
        'rq_camera_focus_outputs',
      );
}
