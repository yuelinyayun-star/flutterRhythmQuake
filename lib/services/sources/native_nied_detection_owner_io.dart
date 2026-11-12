import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../models/source_payload.dart';
import 'native_station_core_library_io.dart';
import 'nied_monitor.dart';

/// Raw station columns in; native station deltas and prepared UI projections out.
/// Holds, expiry scheduling, grids, event lifecycle and effects belong to Rust.
final class NativeNiedDetectionOwner implements Finalizable {
  NativeNiedDetectionOwner(
    List<NiedStation> stations, {
    required this.onUpdate,
    bool manualClock = false,
  }) : _count = stations.length {
    if (!supported) {
      throw UnsupportedError(
        'Native NIED detection requires Windows or Android',
      );
    }
    final weak = WeakReference(this);
    _port = RawReceivePort((_) => weak.target?._drain());
    try {
      using((arena) {
        final xy = arena<Double>(_count == 0 ? 1 : _count * 2);
        final coordinates = xy.asTypedList(_count * 2);
        for (var i = 0; i < _count; i++) {
          coordinates[i * 2] = stations[i].coordinate.latitude;
          coordinates[i * 2 + 1] = stations[i].coordinate.longitude;
        }
        final encoded = JsonUtf8Encoder().convert([
          for (final s in stations)
            [s.code, s.isActive, s.detectState, s.detectReason, s.id],
        ]);
        final bytes = arena<Uint8>(encoded.length);
        bytes.asTypedList(encoded.length).setAll(0, encoded);
        _owner = _api.create(
          xy,
          _count,
          bytes,
          encoded.length,
          _port.sendPort.nativePort,
          NativeApi.postCObject.cast(),
          manualClock ? 1 : 0,
        );
      });
      if (_owner == nullptr) {
        throw StateError('Cannot create native NIED detection owner');
      }
      _finalizer.attach(this, _owner, detach: this);
      _portFinalizer.attach(this, _port, detach: this);
      _input = StationCoreBuffer(_count * 64);
      _length = StationCoreBuffer(sizeOf<Size>());
      _integers = _input!.pointer.cast<Int64>().asTypedList(_count * 8);
      _doubles = _input!.pointer.cast<Double>().asTypedList(_count * 8);
      _active = [for (final s in stations) s.isActive];
      _states = [for (final s in stations) s.detectState];
      _reasons = [for (final s in stations) s.detectReason];
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static final _finalizer = NativeFinalizer(_api.destroyPointer);
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  static Map<String, int> get diagnostics => {
    'sessions': _api.sessions(),
    'workers': _api.workers(),
    'frames': _api.frames(),
  };
  final void Function(List<dynamic>) onUpdate;
  final int _count;
  late final RawReceivePort _port;
  Pointer<Void> _owner = nullptr;
  StationCoreBuffer? _input, _length;
  late final Int64List _integers;
  late final Float64List _doubles;
  late final List<bool> _active;
  late final List<int> _states;
  late final List<String> _reasons;
  bool _disposed = false, _draining = false;
  String? layerSignature;

  void process(List<NiedStation> stations, int sensitivity, {int clock = 0}) {
    if (_disposed) throw StateError('NIED detection owner is disposed');
    if (stations.length != _count) {
      throw ArgumentError('NIED directory changed');
    }
    // Deliver an already queued expiry before the next original input frame.
    _drain();
    if (_disposed) return;
    for (var i = 0; i < _count; i++) {
      final s = stations[i], offset = i * 8;
      final observed = s.lastDataTime ?? s.lastUpdate;
      _integers[offset] = s.kaLevel;
      _doubles[offset + 1] = s.activity;
      _integers[offset + 2] = s.ascend;
      _doubles[offset + 3] = s.continuousShindo;
      _integers[offset + 4] = s.triggerStamp;
      _integers[offset + 5] =
          observed?.microsecondsSinceEpoch ?? -9223372036854775808;
      _integers[offset + 6] = observed?.isUtc == true ? 1 : 0;
      // Raw sampler reset/missing-frame invalidation, not a detection decision.
      _integers[offset + 7] =
          (s.isActive ? 1 : 0) | (s.isRealtimeObservationMissing ? 2 : 0);
    }
    final error = _api.apply(
      _owner,
      _input!.pointer.cast(),
      _count,
      sensitivity,
      clock,
    );
    if (error != 0) {
      throw StateError('Native NIED detection input rejected ($error)');
    }
    _drain();
  }

  /// An explicit monotonic clock for lifecycle tests; never rewrites source time.
  void tick(int clock) {
    if (_disposed) throw StateError('NIED detection owner is disposed');
    final error = _api.tick(_owner, clock);
    if (error != 0) {
      throw StateError('Native NIED detection clock rejected ($error)');
    }
    _drain();
  }

  void _drain() {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      while (!_disposed) {
        final pointer = _api.take(_owner, _length!.pointer.cast());
        if (pointer == nullptr) break;
        final size = _length!.pointer.cast<Size>().value;
        final result =
            PackedSourceJson(Uint8List.fromList(pointer.asTypedList(size))).root
                as List<dynamic>;
        for (final row in result[0] as List) {
          final index = row[0] as int;
          _active[index] = row[1] as bool;
          _states[index] = row[2] as int;
          _reasons[index] = row[3] as String;
        }
        if (result[3] case final String signature) layerSignature = signature;
        onUpdate(result);
      }
    } finally {
      _draining = false;
    }
  }

  /// Bind the existing native view to replacement objects of the same directory.
  void rebind(List<NiedStation> stations) {
    for (var i = 0; i < _count; i++) {
      stations[i]
        ..isActive = _active[i]
        ..detectState = _states[i]
        ..detectReason = _reasons[i];
    }
  }

  void reset({required bool clearHolds}) {
    if (_disposed) return;
    _api.reset(_owner, clearHolds ? 1 : 0);
    layerSignature = null;
    if (clearHolds) {
      _active.fillRange(0, _count, false);
      _states.fillRange(0, _count, 0);
      _reasons.fillRange(0, _count, '');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _port.close();
    if (_owner != nullptr) {
      _finalizer.detach(this);
      _portFinalizer.detach(this);
      _api.destroy(_owner);
      _owner = nullptr;
    }
    _input?.dispose();
    _length?.dispose();
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final create = lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Double>,
          Size,
          Pointer<Uint8>,
          Size,
          Int64,
          Pointer<Void>,
          Uint8,
        ),
        Pointer<Void> Function(
          Pointer<Double>,
          int,
          Pointer<Uint8>,
          int,
          int,
          Pointer<Void>,
          int,
        )
      >('rq_nied_detection_create');
  late final apply = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Int64>, Size, Int64, Int64),
        int Function(Pointer<Void>, Pointer<Int64>, int, int, int)
      >('rq_nied_detection_apply');
  late final tick = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int64),
        int Function(Pointer<Void>, int)
      >('rq_nied_detection_tick');
  late final take = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)
      >('rq_nied_detection_take');
  late final reset = lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint8),
        void Function(Pointer<Void>, int)
      >('rq_nied_detection_reset');
  late final destroyPointer = lib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_nied_detection_destroy',
      );
  late final destroy = destroyPointer
      .asFunction<void Function(Pointer<Void>)>();
  late final sessions = lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_nied_detection_sessions',
  );
  late final workers = lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_nied_detection_workers',
  );
  late final frames = lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_nied_detection_frames',
  );
}
