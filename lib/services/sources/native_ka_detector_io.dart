import 'dart:ffi';
import 'dart:typed_data';

import 'native_ka_detector_result.dart';
import 'native_station_core_library_io.dart';

typedef _CreateNative =
    Pointer<Void> Function(
      Pointer<Uint32>,
      Pointer<Uint32>,
      Size,
      Size,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Double>,
      Size,
    );
typedef _ProcessNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Int64>,
      Int64,
      Uint8,
      Pointer<Uint32>,
      Pointer<Int64>,
    );
typedef _ProcessDart =
    int Function(
      Pointer<Void>,
      Pointer<Int64>,
      int,
      int,
      Pointer<Uint32>,
      Pointer<Int64>,
    );

final class NativeKaDetector implements Finalizable {
  NativeKaDetector({
    required List<List<int>> adjacency,
    required double Function(int, int) distance,
  }) : _count = adjacency.length {
    if (!supported) {
      throw UnsupportedError('Native KA detection requires Windows');
    }
    if (_count > 1048576 ||
        adjacency.any(
          (row) =>
              row.length > 6 ||
              row.any((index) => index < 0 || index >= _count),
        )) {
      throw ArgumentError('Invalid KA adjacency');
    }
    final orderedDistances = <(int, int), double>{};
    for (final neighbors in adjacency) {
      for (var first = 0; first < neighbors.length - 1; first++) {
        for (var second = first + 1; second < neighbors.length; second++) {
          final a = neighbors[first], b = neighbors[second];
          orderedDistances.putIfAbsent((a, b), () => distance(a, b));
        }
      }
    }
    final edges = adjacency.fold<int>(0, (count, row) => count + row.length);
    final offsets = StationCoreBuffer((_count + 1) * 4);
    StationCoreBuffer? neighbors;
    StationCoreBuffer? pairFirst, pairSecond, pairDistances;
    try {
      neighbors = StationCoreBuffer(edges * 4);
      pairFirst = StationCoreBuffer(orderedDistances.length * 4);
      pairSecond = StationCoreBuffer(orderedDistances.length * 4);
      pairDistances = StationCoreBuffer(orderedDistances.length * 8);
      final values = neighbors.pointer.cast<Uint32>().asTypedList(edges);
      final starts = offsets.pointer.cast<Uint32>().asTypedList(_count + 1);
      final firstValues = pairFirst.pointer.cast<Uint32>().asTypedList(
        orderedDistances.length,
      );
      final secondValues = pairSecond.pointer.cast<Uint32>().asTypedList(
        orderedDistances.length,
      );
      final distanceValues = pairDistances.pointer.cast<Double>().asTypedList(
        orderedDistances.length,
      );
      var offset = 0;
      for (var index = 0; index < _count; index++) {
        starts[index] = offset;
        values.setAll(offset, adjacency[index]);
        offset += adjacency[index].length;
      }
      starts[_count] = offset;
      var pairIndex = 0;
      for (final entry in orderedDistances.entries) {
        firstValues[pairIndex] = entry.key.$1;
        secondValues[pairIndex] = entry.key.$2;
        distanceValues[pairIndex] = entry.value;
        pairIndex++;
      }
      _pointer = _bindings.create(
        offsets.pointer.cast(),
        neighbors.pointer.cast(),
        _count,
        edges,
        pairFirst.pointer.cast(),
        pairSecond.pointer.cast(),
        pairDistances.pointer.cast(),
        orderedDistances.length,
      );
      if (_pointer == nullptr) throw StateError('Cannot create KA detector');
      _finalizer.attach(this, _pointer, detach: this);
    } finally {
      offsets.dispose();
      neighbors?.dispose();
      pairFirst?.dispose();
      pairSecond?.dispose();
      pairDistances?.dispose();
    }
    try {
      _info = StationCoreBuffer(_count * 48);
      _output = StationCoreBuffer(_count * 4);
      _summary = StationCoreBuffer(16);
      _infoValues = _info!.pointer.cast<Int64>().asTypedList(_count * 6);
      _activityValues = _info!.pointer.cast<Double>().asTypedList(_count * 6);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  /// Owns display-detector geometry and adjacency entirely in native storage.
  NativeKaDetector.niedCoordinates(List<double> coordinates)
    : _count = coordinates.length ~/ 2 {
    if (!supported) {
      throw UnsupportedError('Native NIED detection requires Windows');
    }
    if (coordinates.length.isOdd || _count > 1048576) {
      throw ArgumentError('Invalid original NIED geometry');
    }
    final input = StationCoreBuffer(coordinates.length * 8);
    try {
      input.pointer
          .cast<Double>()
          .asTypedList(coordinates.length)
          .setAll(0, coordinates);
      _pointer = _bindings.createNied(input.pointer.cast(), _count);
      if (_pointer == nullptr) {
        throw StateError('Cannot create native NIED geometry owner');
      }
      _finalizer.attach(this, _pointer, detach: this);
    } finally {
      input.dispose();
    }
    try {
      _info = StationCoreBuffer(_count * 48);
      _output = StationCoreBuffer(_count * 4);
      _summary = StationCoreBuffer(16);
      _infoValues = _info!.pointer.cast<Int64>().asTypedList(_count * 6);
      _activityValues = _info!.pointer.cast<Double>().asTypedList(_count * 6);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static Map<String, int> get diagnostics => {
    'kaDetectorSessions': _bindings.sessions(),
    'kaDetectorCalls': _bindings.calls(),
  };
  final int _count;
  late Pointer<Void> _pointer;
  StationCoreBuffer? _info, _output, _summary;
  late Int64List _infoValues;
  late Float64List _activityValues;
  bool _disposed = false, _processing = false;

  void writeInput(
    int index, {
    required int kaLevel,
    required double activity,
    required int ascend,
    required bool isActive,
    required int triggerStamp,
    double continuousShindo = 0,
  }) {
    _check();
    if (index < 0 || index >= _count) {
      throw RangeError.index(index, _infoValues);
    }
    final offset = index * 6;
    _infoValues[offset] = kaLevel;
    _activityValues[offset + 1] = activity;
    _infoValues[offset + 2] = ascend;
    _infoValues[offset + 3] = isActive ? 1 : 0;
    _activityValues[offset + 4] = continuousShindo;
    _infoValues[offset + 5] = triggerStamp;
  }

  void writePacked(Int64List rows) {
    _check();
    if (rows.length != _count * 6) {
      throw ArgumentError('KA input count changed');
    }
    _infoValues.setAll(0, rows);
  }

  NativeKaDetectionResult process({
    required int sensitivity,
    required bool hadActiveGrid,
  }) {
    _check();
    _processing = true;
    try {
      final status = _bindings.process(
        _pointer,
        _info!.pointer.cast(),
        sensitivity,
        hadActiveGrid ? 1 : 0,
        _output!.pointer.cast(),
        _summary!.pointer.cast(),
      );
      if (status != 0) throw StateError('KA detection failed (status $status)');
      final summary = _summary!.pointer.cast<Int64>().asTypedList(2);
      return NativeKaDetectionResult(
        activeIndices: List.unmodifiable(
          _output!.pointer.cast<Uint32>().asTypedList(summary[0]),
        ),
        strongestIndex: summary[1] < 0 ? null : summary[1],
      );
    } finally {
      _processing = false;
    }
  }

  void _check() {
    if (_disposed) throw StateError('KA detector disposed');
    if (_processing) throw StateError('KA detector cannot be reentered');
  }

  void dispose() {
    if (_disposed) return;
    _check();
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
    _info?.dispose();
    _output?.dispose();
    _summary?.dispose();
  }
}

class _Bindings {
  late final Pointer<Void> Function(Pointer<Double>, int) createNied;
  _Bindings() {
    final library = StationCoreLibrary.library;
    createNied = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<Double>, Size),
          Pointer<Void> Function(Pointer<Double>, int)
        >('rq_ka_detector_create_nied');
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_ka_detector_abi_version',
    )();
    if (version != 2) throw StateError('Unsupported KA detector ABI: $version');
    create = library
        .lookupFunction<
          _CreateNative,
          Pointer<Void> Function(
            Pointer<Uint32>,
            Pointer<Uint32>,
            int,
            int,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Double>,
            int,
          )
        >('rq_ka_detector_create');
    process = library.lookupFunction<_ProcessNative, _ProcessDart>(
      'rq_ka_detector_process',
    );
    destroyPointer = library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'rq_ka_detector_destroy',
        );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    sessions = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_ka_detector_sessions',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_ka_detector_calls',
    );
  }
  late final Pointer<Void> Function(
    Pointer<Uint32>,
    Pointer<Uint32>,
    int,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Double>,
    int,
  )
  create;
  late final _ProcessDart process;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function() sessions, calls;
}
