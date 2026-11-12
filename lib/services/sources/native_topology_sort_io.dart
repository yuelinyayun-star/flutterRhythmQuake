import 'dart:ffi';
import 'dart:typed_data';

import 'native_station_core_library_io.dart';

/// Scratch owned by one synchronous topology build; never sent to an isolate.
class NativeTopologySort {
  NativeTopologySort(List<int> ids) : _count = ids.length {
    if (!supported) {
      throw UnsupportedError('Native topology sorting requires Windows');
    }
    if (_count > 1048576 || ids.toSet().length != _count) {
      throw ArgumentError(
        'Topology sorting requires bounded unique station IDs',
      );
    }
    _bindings;
    final input = StationCoreBuffer(_count * 8);
    StationCoreBuffer? idBuffer, output;
    try {
      idBuffer = StationCoreBuffer(_count * 8);
      output = StationCoreBuffer(_count * 4);
      _input = input;
      _ids = idBuffer;
      _output = output;
      _distances = input.pointer.cast<Double>().asTypedList(_count);
      _indices = output.pointer.cast<Uint32>().asTypedList(_count);
      idBuffer.pointer.cast<Int64>().asTypedList(_count).setAll(0, ids);
    } catch (_) {
      input.dispose();
      idBuffer?.dispose();
      output?.dispose();
      rethrow;
    }
  }

  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static int get calls => _bindings.calls();
  final int _count;
  late final StationCoreBuffer _input, _ids, _output;
  late final Float64List _distances;
  late final Uint32List _indices;
  bool _disposed = false;

  Float64List get distances {
    _check();
    return _distances;
  }

  /// Borrowed indices are valid until the next sort or dispose. Consumers use
  /// them synchronously and copy selected IDs/codes into immutable Dart lists.
  Uint32List sort() {
    _check();
    final count = _bindings.sort(
      _input.pointer.cast(),
      _ids.pointer.cast(),
      _count,
      _output.pointer.cast(),
    );
    if (count < 0) throw StateError('Topology sort failed (status $count)');
    return Uint32List.sublistView(_indices, 0, count);
  }

  void _check() {
    if (_disposed) throw StateError('Topology sort buffers are disposed');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _input.dispose();
    _ids.dispose();
    _output.dispose();
  }
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final abi = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_topology_sort_abi_version',
    )();
    if (abi != 1) throw StateError('Unsupported topology sort ABI: $abi');
    sort = library
        .lookupFunction<
          Int64 Function(
            Pointer<Double>,
            Pointer<Int64>,
            Size,
            Pointer<Uint32>,
          ),
          int Function(Pointer<Double>, Pointer<Int64>, int, Pointer<Uint32>)
        >('rq_topology_sort');
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_topology_sort_calls',
    );
  }
  late final int Function(Pointer<Double>, Pointer<Int64>, int, Pointer<Uint32>)
  sort;
  late final int Function() calls;
}
