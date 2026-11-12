import 'dart:ffi';
import 'dart:typed_data';
import '../../services/sources/native_station_core_library_io.dart';
import '../../services/sources/native_station_image_decoder.dart';
import 'event_detection_models.dart';
import 'robust_station_trigger_detector.dart';

final class _Config extends Struct {
  @Int64()
  external int historyMicros;
  @Int64()
  external int minimumSamples;
  @Double()
  external double risingDelta;
  @Double()
  external double triggeredDelta;
  @Int64()
  external int risingFrames;
  @Int64()
  external int triggeredFrames;
  @Int64()
  external int decayFrames;
  @Int64()
  external int missingFrames;
  @Int64()
  external int strongLevel;
}

final class _Input extends Struct {
  @Uint64()
  external int station;
  @Int64()
  external int time;
  @Double()
  external double signal;
  @Int64()
  external int detectLevel;
  @Uint64()
  external int flags;
}

final class _Output extends Struct {
  @Uint32()
  external int state;
  @Uint32()
  external int reason;
  @Int64()
  external int ascend;
  @Double()
  external double activity;
  @Int64()
  external int riseStart;
  @Int64()
  external int riseEnd;
  @Int64()
  external int triggerStart;
  @Int64()
  external int triggerEnd;
  @Uint64()
  external int flags;
}

class NativeStationTriggerDetector implements BatchStationTriggerDetector {
  NativeStationTriggerDetector({
    this.detectorId = 'robust_station_trigger_v0',
    this.config = const RobustStationTriggerConfig(),
    this.collectTimings = false,
  }) {
    if (!supported) {
      throw UnsupportedError('Native trigger session requires Windows');
    }
  }

  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static Map<String, int> get globalDiagnostics => {
    ...NativeStationImageDecoder.memoryStats,
    'triggerSessions': _bindings.sessions(),
    'triggerCalls': _bindings.calls(),
  };
  static const _reasons = [
    'missing_observation_end',
    'missing_observation_decay',
    'missing_observation',
    'warming_up',
    'strong_level_sustained',
    'sustained_level_change',
    'level_rising',
    'returned_to_baseline',
    'level_decaying',
    'within_baseline',
  ];
  @override
  final String detectorId;
  final RobustStationTriggerConfig config;
  final bool collectTimings;
  int _marshalMicros = 0, _nativeMicros = 0, _outputMicros = 0;
  final Map<String, _StationIdentity> _indices = {};
  List<_StationIdentity?> _rows = const [];
  int _nextIndex = 0;
  final List<int> _freeIndices = [];
  _Session? _session;
  StationCoreBuffer? _inputs, _outputs;
  Int64List? _inputInts, _outputInts;
  Float64List? _inputDoubles, _outputDoubles;
  int _capacity = 0;
  bool _disposed = false;

  Map<String, int> get diagnostics => {
    ...globalDiagnostics,
    'stationCount': _indices.length,
    'bufferCapacityBytes': (_inputs?.length ?? 0) + (_outputs?.length ?? 0),
    if (collectTimings) ...{
      'marshalMicros': _marshalMicros,
      'nativeMicros': _nativeMicros,
      'outputMicros': _outputMicros,
    },
  };

  @override
  StationTriggerSnapshot update(StationObservationFrame observation) =>
      updateBatch([observation]).single;

  @override
  List<StationTriggerSnapshot> updateBatch(
    List<StationObservationFrame> observations,
  ) {
    if (_disposed) throw StateError('Native trigger session disposed');
    if (observations.length > 1048576) {
      throw ArgumentError('Station trigger batch exceeds limit');
    }
    if (observations.isEmpty) return const [];
    final watch = collectTimings ? (Stopwatch()..start()) : null;
    final session = _session ??= _Session(_bindings, config);
    if (_capacity < observations.length) {
      _inputInts = _outputInts = null;
      _inputDoubles = _outputDoubles = null;
      _inputs?.dispose();
      _outputs?.dispose();
      _capacity = observations.length;
      _rows = List<_StationIdentity?>.filled(_capacity, null);
      _inputs = StationCoreBuffer(_capacity * sizeOf<_Input>());
      _outputs = StationCoreBuffer(_capacity * sizeOf<_Output>());
      _inputInts = _inputs!.pointer.cast<Int64>().asTypedList(_capacity * 5);
      _inputDoubles = _inputs!.pointer.cast<Double>().asTypedList(
        _capacity * 5,
      );
      _outputInts = _outputs!.pointer.cast<Int64>().asTypedList(_capacity * 8);
      _outputDoubles = _outputs!.pointer.cast<Double>().asTypedList(
        _capacity * 8,
      );
    }
    final inputs = _inputs!.pointer.cast<_Input>();
    final integers = _inputInts!, doubles = _inputDoubles!;
    for (var i = 0; i < observations.length; i++) {
      final observation = observations[i];
      final signal =
          observation.detectLevel?.toDouble() ??
          observation.rawLevel?.toDouble() ??
          (observation.intensity?.isFinite == true
              ? observation.intensity
              : null);
      var identity = _rows[i];
      if (identity == null ||
          identity.retired ||
          identity.stationId != observation.stationId) {
        identity = _indices[observation.stationId];
      }
      if (identity == null) {
        final index = _freeIndices.isEmpty
            ? _nextIndex++
            : _freeIndices.removeLast();
        if (index >= 1048576) {
          throw StateError('Native station catalogue exceeds limit');
        }
        identity = _StationIdentity(index, observation.stationId);
        _indices[observation.stationId] = identity;
      }
      _rows[i] = identity;
      final offset = i * 5;
      integers[offset] = identity.index;
      integers[offset + 1] = observation.observedAt.microsecondsSinceEpoch;
      doubles[offset + 2] = signal ?? 0;
      integers[offset + 3] = observation.detectLevel ?? 0;
      integers[offset + 4] =
          (signal == null ? 0 : 1) |
          (observation.hasUsableObservation ? 2 : 0) |
          (observation.detectLevel == null ? 0 : 4) |
          (observation.observedAt.isUtc ? 8 : 0);
    }
    final outputs = _outputs!.pointer.cast<_Output>();
    final marshalEnd = watch?.elapsedMicroseconds ?? 0;
    final status = _bindings.process(
      session.pointer,
      inputs,
      observations.length,
      outputs,
    );
    if (status != 0) {
      throw StateError('Rust station trigger failed (status $status)');
    }
    final results = _outputInts!, values = _outputDoubles!;
    final nativeEnd = watch?.elapsedMicroseconds ?? 0;
    final snapshots = List<StationTriggerSnapshot>.generate(
      observations.length,
      (i) {
        final observation = observations[i];
        final offset = i * 8;
        final packed = results[offset], flags = results[offset + 7];
        final identity = _rows[i]!;
        // Reuse immutable display intervals while native state is unchanged.
        identity.rise = _interval(
          identity.rise,
          flags,
          1,
          4,
          8,
          results[offset + 3],
          results[offset + 4],
        );
        identity.trigger = _interval(
          identity.trigger,
          flags,
          2,
          16,
          32,
          results[offset + 5],
          results[offset + 6],
        );
        final reasons = <String>{}..add(_reasons[(packed >> 32) & 0xffffffff]);
        final snapshot = StationTriggerSnapshot(
          stationId: observation.stationId,
          code: observation.code,
          sourceId: observation.sourceId,
          observedAt: observation.observedAt,
          state: StationTriggerState.values[packed & 0xffffffff],
          latitude: observation.latitude,
          longitude: observation.longitude,
          intensity: observation.intensity,
          rawLevel: observation.rawLevel,
          detectLevel: observation.detectLevel,
          activity: values[offset + 2],
          ascend: results[offset + 1],
          firstRiseInterval: identity.rise,
          firstTriggerInterval: identity.trigger,
          qualityFlags: observation.qualityFlags,
          reasonCodes: reasons,
        );
        if (snapshot.state == StationTriggerState.ended) {
          identity.rise = identity.trigger = null;
        }
        return snapshot;
      },
      growable: false,
    );
    if (watch != null) {
      _marshalMicros += marshalEnd;
      _nativeMicros += nativeEnd - marshalEnd;
      _outputMicros += watch.elapsedMicroseconds - nativeEnd;
    }
    return snapshots;
  }

  static ObservationTimeInterval? _interval(
    ObservationTimeInterval? existing,
    int flags,
    int bit,
    int startBit,
    int endBit,
    int start,
    int end,
  ) {
    if (flags & bit == 0) return null;
    final startUtc = flags & startBit != 0, endUtc = flags & endBit != 0;
    if (existing != null &&
        existing.start.microsecondsSinceEpoch == start &&
        existing.end.microsecondsSinceEpoch == end &&
        existing.start.isUtc == startUtc &&
        existing.end.isUtc == endUtc) {
      return existing;
    }
    return ObservationTimeInterval(
      start: DateTime.fromMicrosecondsSinceEpoch(start, isUtc: startUtc),
      end: DateTime.fromMicrosecondsSinceEpoch(end, isUtc: endUtc),
    );
  }

  @override
  void resetStation(String stationId) {
    if (_disposed) throw StateError('Native trigger session disposed');
    final index = _indices.remove(stationId);
    if (index != null && _session != null) {
      index.retired = true;
      index.rise = index.trigger = null;
      _freeIndices.add(index.index);
      final status = _bindings.resetStation(_session!.pointer, index.index);
      if (status != 0) {
        throw StateError('Rust station reset failed (status $status)');
      }
    }
  }

  @override
  void reset() {
    _session?.dispose();
    _session = null;
    _inputInts = _outputInts = null;
    _inputDoubles = _outputDoubles = null;
    _inputs?.dispose();
    _outputs?.dispose();
    _inputs = _outputs = null;
    _capacity = 0;
    _rows = const [];
    _indices.clear();
    _freeIndices.clear();
    _nextIndex = 0;
  }

  void dispose() {
    if (_disposed) return;
    reset();
    _disposed = true;
  }
}

class _StationIdentity {
  _StationIdentity(this.index, this.stationId);
  final int index;
  final String stationId;
  bool retired = false;
  ObservationTimeInterval? rise, trigger;
}

final class _Session implements Finalizable {
  _Session(this.bindings, RobustStationTriggerConfig config) {
    final buffer = StationCoreBuffer(sizeOf<_Config>());
    try {
      final c = buffer.pointer.cast<_Config>().ref;
      c
        ..historyMicros = config.historySeconds * Duration.microsecondsPerSecond
        ..minimumSamples = config.minimumBaselineSamples
        ..risingDelta = config.risingDelta
        ..triggeredDelta = config.triggeredDelta
        ..risingFrames = config.risingFrames
        ..triggeredFrames = config.triggeredFrames
        ..decayFrames = config.decayFrames
        ..missingFrames = config.missingFramesToEnd
        ..strongLevel = config.strongDetectLevel;
      pointer = bindings.create(buffer.pointer.cast());
      if (pointer == nullptr) {
        throw StateError('Rust trigger session creation failed');
      }
      bindings.finalizer.attach(this, pointer, detach: this);
    } finally {
      buffer.dispose();
    }
  }
  final _Bindings bindings;
  late final Pointer<Void> pointer;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.finalizer.detach(this);
    bindings.destroy(pointer);
  }
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_trigger_abi_version',
    )();
    if (version != 1) throw StateError('Unsupported trigger ABI: $version');
    create = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<_Config>),
          Pointer<Void> Function(Pointer<_Config>)
        >('rq_trigger_create');
    destroy = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('rq_trigger_destroy');
    resetStation = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, Uint64),
          int Function(Pointer<Void>, int)
        >('rq_trigger_reset_station');
    process = library
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<_Input>,
            Size,
            Pointer<_Output>,
          ),
          int Function(Pointer<Void>, Pointer<_Input>, int, Pointer<_Output>)
        >('rq_trigger_process');
    finalizer = NativeFinalizer(
      library.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_trigger_destroy',
      ),
    );
    sessions = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_trigger_sessions',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_trigger_calls',
    );
  }
  late final Pointer<Void> Function(Pointer<_Config>) create;
  late final void Function(Pointer<Void>) destroy;
  late final int Function(Pointer<Void>, int) resetStation;
  late final int Function(Pointer<Void>, Pointer<_Input>, int, Pointer<_Output>)
  process;
  late final NativeFinalizer finalizer;
  late final int Function() sessions, calls;
}
