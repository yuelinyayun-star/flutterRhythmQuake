import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../models/source_payload.dart';
import 'native_station_core_library_io.dart';

class NativeNiedTopology {
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static List<dynamic> build(
    List<int> ids,
    List<double> coordinates,
    List<String> codes,
  ) {
    if (ids.length != codes.length || coordinates.length != ids.length * 2) {
      throw ArgumentError('Mismatched NIED directory columns');
    }
    return using((arena) {
      final names = JsonUtf8Encoder().convert(codes);
      final id = arena<Int64>(ids.isEmpty ? 1 : ids.length);
      final xy = arena<Double>(coordinates.isEmpty ? 1 : coordinates.length);
      final text = arena<Uint8>(names.length), size = arena<Size>();
      id.asTypedList(ids.length).setAll(0, ids);
      xy.asTypedList(coordinates.length).setAll(0, coordinates);
      text.asTypedList(names.length).setAll(0, names);
      final owner = _api.build(id, xy, ids.length, text, names.length);
      if (owner == nullptr) {
        throw StateError('Native NIED topology preparation failed');
      }
      try {
        final bytes = _api.bytes(owner, size);
        return PackedSourceJson(
              Uint8List.fromList(bytes.asTypedList(size.value)),
            ).root
            as List<dynamic>;
      } finally {
        _api.free(owner);
      }
    });
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final build = lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Int64>,
          Pointer<Double>,
          Size,
          Pointer<Uint8>,
          Size,
        ),
        Pointer<Void> Function(
          Pointer<Int64>,
          Pointer<Double>,
          int,
          Pointer<Uint8>,
          int,
        )
      >('rq_nied_topology_build');
  late final bytes = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)
      >('rq_nied_topology_bytes');
  late final free = lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('rq_nied_topology_free');
}
