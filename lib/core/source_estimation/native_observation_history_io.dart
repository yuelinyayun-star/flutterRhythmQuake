import 'dart:ffi';
import 'dart:typed_data';
import 'native_observation_snapshot.dart';
import 'native_observation_commit.dart';
import 'native_nied_observation_summary.dart';
import '../../services/sources/native_station_core_library_io.dart';

/// Owned only by the inference isolate. Snapshots contain no pointers/handles.
final class NativeObservationHistory implements Finalizable {
  NativeObservationHistory() {
    if (!supported) {
      throw UnsupportedError('Native observation history requires Windows');
    }
    _pointer = _bindings.create();
    if (_pointer == nullptr) {
      throw StateError('Cannot create observation history');
    }
    _finalizer.attach(this, _pointer, detach: this);
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  // Synchronous calls share scratch buffers inside each isolate, not per station.
  static final _row = StationCoreBuffer(7 * 8);
  static final _result = StationCoreBuffer(3 * 8);
  static final _summary = StationCoreBuffer(9 * 8);
  static StationCoreBuffer? _copyBuffer;
  static _ObservationBatch? _batch;
  static void batchUpdates(void Function() action) {
    if (!supported || _batch != null) {
      action();
      return;
    }
    final batch = _batch = _ObservationBatch();
    try {
      action();
    } finally {
      try {
        batch.flush();
      } finally {
        _batch = null;
        batch.dispose();
      }
    }
  }

  static Map<String, int> get diagnostics => {
    'sessions': _bindings.sessions(),
    'calls': _bindings.calls(),
    'batchCalls': _bindings.batchCalls(),
    'summaryCalls': _bindings.summaryCalls(),
    'snapshotCalls': _bindings.snapshotCalls(),
    'scratchBytes':
        _row.length +
        _result.length +
        _summary.length +
        (_copyBuffer?.length ?? 0),
  };
  late Pointer<Void> _pointer;
  bool _disposed = false;
  int _length = 0, _capacityBytes = 0;
  int get length {
    _batch?.flush();
    return _length;
  }

  int get capacityBytes {
    _batch?.flush();
    return _capacityBytes;
  }

  void _check() {
    if (_disposed) throw StateError('Observation history disposed');
  }

  void _status(int status) {
    if (status != 0) {
      throw StateError('Observation history failed (status $status)');
    }
  }

  int append(Int64List row, int cutoffUs) {
    _check();
    _batch?.flush();
    if (row.length != 7) {
      throw ArgumentError('Observation row must contain 7 words');
    }
    _row.pointer.cast<Int64>().asTypedList(7).setAll(0, row);
    _status(
      _bindings.push(
        _pointer,
        _row.pointer.cast(),
        cutoffUs,
        _result.pointer.cast(),
      ),
    );
    final result = _result.pointer.cast<Int64>().asTypedList(3);
    _length = result[0];
    _capacityBytes = result[2];
    return result[1];
  }

  void appendDeferred(
    Int64List row,
    int cutoffUs,
    NativeObservationCommit owner,
  ) {
    _check();
    if (row.length != 7) {
      throw ArgumentError('Observation row must contain 7 words');
    }
    final batch = _batch;
    if (batch == null) {
      owner.observationCommitted(append(row, cutoffUs), row[6]);
    } else {
      batch.add(this, row, cutoffUs, owner);
    }
  }

  NativeObservationSnapshot snapshot() {
    _check();
    _batch?.flush();
    if (_length == 0) {
      return NativeObservationSnapshot(Uint8List(0), 0, 0, 0);
    }
    final bytes = _bindings.packedSize(_pointer);
    if (_copyBuffer == null || _copyBuffer!.length < bytes) {
      _copyBuffer?.dispose();
      _copyBuffer = StationCoreBuffer(bytes);
    }
    _status(
      _bindings.copyPacked(
        _pointer,
        _copyBuffer!.pointer,
        bytes,
        _result.pointer.cast(),
      ),
    );
    final header = _result.pointer.cast<Int64>().asTypedList(3);
    return NativeObservationSnapshot(
      Uint8List.fromList(_copyBuffer!.pointer.asTypedList(bytes)),
      header[0],
      header[1],
      header[2],
    );
  }

  NativeNiedObservationSummary niedSummary(DateTime? observedAt) {
    _check();
    _batch?.flush();
    _status(
      _bindings.niedSummary(
        _pointer,
        observedAt?.microsecondsSinceEpoch ?? 0,
        observedAt == null ? 0 : 1,
        _summary.pointer.cast(),
      ),
    );
    return NativeNiedObservationSummary(
      Float64List.fromList(_summary.pointer.cast<Double>().asTypedList(9)),
    );
  }

  double? pretriggerSeconds(DateTime earliest, DateTime fallback) {
    _check();
    _batch?.flush();
    final status = _bindings.pretrigger(
      _pointer,
      earliest.microsecondsSinceEpoch,
      fallback.microsecondsSinceEpoch,
      _summary.pointer.cast(),
    );
    if (status < 0) _status(status);
    return status == 0 ? null : _summary.pointer.cast<Double>().value;
  }

  bool fastRiseExceeds(DateTime observedAt, int digit) {
    _check();
    _batch?.flush();
    final status = _bindings.fastRise(
      _pointer,
      observedAt.microsecondsSinceEpoch,
      digit,
    );
    if (status < 0) _status(status);
    return status != 0;
  }

  void clear() {
    _check();
    _batch?.flush();
    _status(_bindings.clear(_pointer));
    _length = 0;
    _capacityBytes = 0;
  }

  void dispose() {
    if (_disposed) return;
    _batch?.flush();
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
    _length = 0;
    _capacityBytes = 0;
  }
}

/// Bounded caller-owned buffers. No handles or buffers survive the scope.
class _ObservationBatch {
  static const capacity = 2048;
  StationCoreBuffer? _handles, _rows, _results;
  Pointer<Pointer<Void>>? _handleValues;
  Int64List? _rowValues, _resultValues;
  final List<NativeObservationHistory> _owners = [];
  final List<NativeObservationCommit> _receivers = [];
  bool _flushing = false;
  void add(
    NativeObservationHistory history,
    Int64List row,
    int cutoff,
    NativeObservationCommit receiver,
  ) {
    if (_flushing) throw StateError('Observation batch reentry');
    if (_owners.length == capacity) flush();
    _handles ??= StationCoreBuffer(capacity * sizeOf<Pointer<Void>>());
    _rows ??= StationCoreBuffer(capacity * 8 * 8);
    _results ??= StationCoreBuffer(capacity * 4 * 8);
    _handleValues ??= _handles!.pointer.cast<Pointer<Void>>();
    _rowValues ??= _rows!.pointer.cast<Int64>().asTypedList(capacity * 8);
    _resultValues ??= _results!.pointer.cast<Int64>().asTypedList(capacity * 4);
    final index = _owners.length;
    _handleValues![index] = history._pointer;
    final values = _rowValues!;
    values.setRange(index * 8, index * 8 + 7, row);
    values[index * 8 + 7] = cutoff;
    _owners.add(history);
    _receivers.add(receiver);
  }

  void flush() {
    if (_owners.isEmpty) return;
    if (_flushing) throw StateError('Observation batch reentry');
    _flushing = true;
    final count = _owners.length;
    List<NativeObservationCommit>? failed;
    var status = 0;
    try {
      status = NativeObservationHistory._bindings.pushBatch(
        _handles!.pointer.cast(),
        _rows!.pointer.cast(),
        count,
        _results!.pointer.cast(),
      );
      final results = _resultValues!;
      final rows = _rowValues!;
      for (var index = 0; index < count; index++) {
        final offset = index * 4;
        if (results[offset] != 0) {
          failed = _receivers.sublist(index);
          break;
        }
        _owners[index]
          .._length = results[offset + 1]
          .._capacityBytes = results[offset + 3];
        _receivers[index].observationCommitted(
          results[offset + 2],
          rows[index * 8 + 6],
        );
      }
    } finally {
      _owners.clear();
      _receivers.clear();
      _flushing = false;
    }
    if (status != 0) {
      for (final receiver in failed?.toSet() ?? <NativeObservationCommit>{}) {
        receiver.observationBatchFailed();
      }
      throw StateError('Observation batch failed (status $status)');
    }
  }

  void dispose() {
    _handles?.dispose();
    _rows?.dispose();
    _results?.dispose();
  }
}

class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    final abi = lib.lookupFunction<Uint32 Function(), int Function()>(
      'rq_observation_abi_version',
    )();
    if (abi != 1) throw StateError('Unsupported observation ABI: $abi');
    final batchAbi = lib.lookupFunction<Uint32 Function(), int Function()>(
      'rq_observation_batch_abi_version',
    )();
    if (batchAbi != 1) {
      throw StateError('Unsupported observation batch ABI: $batchAbi');
    }
    pushBatch = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Pointer<Void>>,
            Pointer<Uint64>,
            Size,
            Pointer<Int64>,
          ),
          int Function(
            Pointer<Pointer<Void>>,
            Pointer<Uint64>,
            int,
            Pointer<Int64>,
          )
        >('rq_observation_push_batch');
    batchCalls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_observation_batch_calls',
    );
    create = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'rq_observation_create',
        );
    destroyPointer = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'rq_observation_destroy',
    );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    push = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint64>, Int64, Pointer<Int64>),
          int Function(Pointer<Void>, Pointer<Uint64>, int, Pointer<Int64>)
        >('rq_observation_push');
    packedSize = lib
        .lookupFunction<
          Size Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('rq_observation_packed_size');
    copyPacked = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Int64>),
          int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Int64>)
        >('rq_observation_copy_packed');
    clear = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('rq_observation_clear');
    sessions = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_observation_sessions',
    );
    calls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_observation_calls',
    );
    summaryCalls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_observation_summary_calls',
    );
    snapshotCalls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_observation_snapshot_calls',
    );
    niedSummary = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Int64, Uint32, Pointer<Double>),
          int Function(Pointer<Void>, int, int, Pointer<Double>)
        >('rq_observation_nied_summary');
    pretrigger = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Int64, Int64, Pointer<Double>),
          int Function(Pointer<Void>, int, int, Pointer<Double>)
        >('rq_observation_pretrigger');
    fastRise = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Int64, Int64),
          int Function(Pointer<Void>, int, int)
        >('rq_observation_fast_rise');
  }
  late final Pointer<Void> Function() create;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function(Pointer<Void>, Pointer<Uint64>, int, Pointer<Int64>)
  push;
  late final int Function(Pointer<Void>) packedSize;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Int64>)
  copyPacked;
  late final int Function(Pointer<Void>) clear;
  late final int Function() sessions, calls;
  late final int Function() batchCalls;
  late final int Function() summaryCalls, snapshotCalls;
  late final int Function(Pointer<Void>, int, int, Pointer<Double>) niedSummary,
      pretrigger;
  late final int Function(Pointer<Void>, int, int) fastRise;
  late final int Function(
    Pointer<Pointer<Void>>,
    Pointer<Uint64>,
    int,
    Pointer<Int64>,
  )
  pushBatch;
}
