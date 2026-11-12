import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/source_payload.dart';
import '../../core/source_estimation/palert_source_profile.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../foreground_station_payload.dart';
import 'palert_detection.dart';
import 'palert_service.dart';
import 'palert_source_estimation.dart';
import 'native_station_runtime.dart';

typedef _Frame = (int, List<PAlertStation>, Set<String>, DateTime);
typedef _RecordedFrame = (int, Map<String, dynamic>, DateTime, int);
typedef _Result = (int, List<SeismicActiveEvent>?);

/// Persistent ordered session, isolated from both UI and NIED inference state.
class PAlertSourceWorker {
  PAlertSourceWorker() : _useNative = NativeStationRuntime.supported;

  /// Frozen Dart reference for migration parity tests, never a Windows fallback.
  PAlertSourceWorker.dartReferenceForTesting() : _useNative = false;
  final bool _useNative;
  NativeStationRuntime? _native;
  Future<void> _nativeOrder = Future.value();
  Completer<List<SeismicActiveEvent>?>? _nativePending;
  int _nativeSent = 0;
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Completer<SendPort?>? _ready;
  final _pending = <int, Completer<List<SeismicActiveEvent>?>>{};
  int _generation = 0;
  int _nextId = 0;
  bool _disposed = false;
  int _sensitivity = 2;

  void setSensitivity(int value) {
    _sensitivity = value;
    _native?.settings({'sensitivity': value});
  }

  /// Replay sends the immutable recorded snapshot directly. Decode and missing
  /// confirmation-ID detection belong to this owner, not the UI isolate.
  Future<List<SeismicActiveEvent>?> processRecordedSnapshot(
    Map<String, dynamic> snapshot, {
    required DateTime receivedAt,
  }) => _useNative
      ? _submitNative(
          packedSourceJsonTransport(snapshot) ??
              JsonUtf8Encoder().convert(snapshot),
          receivedAt,
        )
      : _submitRecorded(
          snapshotSourcePayload(snapshot),
          receivedAt: receivedAt,
        );

  /// Already owned, read-only native UI snapshot; no raw JSON conversion or
  /// station preparation is needed on the UI isolate.
  Future<List<SeismicActiveEvent>?> processPreparedSnapshot(
    Map<String, dynamic> snapshot, {
    required DateTime receivedAt,
  }) => _useNative
      ? _submitNative(
          packedSourceJsonTransport(snapshot) ??
              JsonUtf8Encoder().convert(snapshot),
          receivedAt,
        )
      : _submitRecorded(snapshot, receivedAt: receivedAt);

  Future<List<SeismicActiveEvent>?> _submitNative(
    Object bytes,
    DateTime clock,
  ) {
    if (_disposed) return Future.value(null);
    final generation = _generation;
    final result = Completer<List<SeismicActiveEvent>?>();
    _nativeOrder = _nativeOrder.then((_) async {
      if (_disposed || generation != _generation) {
        result.complete(null);
        return;
      }
      try {
        if (_native == null) {
          final runtime = _native = NativeStationRuntime();
          runtime.onPreparedPAlert = (message) {
            if (!identical(_native, runtime) || generation != _generation)
              return;
            if (message[1] == _nativeSent && _nativePending != null) {
              final pending = _nativePending!;
              _nativePending = null;
              pending.complete(bindPAlertNativeSourceViews(message[2] as List));
            }
          };
          runtime.start({
            'kind': 'palert',
            'testing': true,
            'nativeDisplay': true,
            'sourceDisplayOnly': true,
            'inference': true,
            'sensitivity': _sensitivity,
          });
        }
        _nativeSent++;
        final pending = _nativePending = Completer<List<SeismicActiveEvent>?>();
        if (bytes case (Uint8List data, int root)) {
          _native!.injectPacked(data, root, clock);
        } else {
          _native!.injectOriginal(bytes as List<int>, clock);
        }
        result.complete(await pending.future);
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<List<SeismicActiveEvent>?> _submitRecorded(
    Map<String, dynamic> original, {
    required DateTime receivedAt,
  }) async {
    if (_disposed) return null;
    final sensitivity = _sensitivity;
    final generation = _generation;
    final port = await _start();
    if (_disposed || generation != _generation || port == null) return null;
    final id = _nextId++;
    final result = Completer<List<SeismicActiveEvent>?>();
    _pending[id] = result;
    port.send((id, original, receivedAt, sensitivity));
    return result.future;
  }

  Future<List<SeismicActiveEvent>?> process(
    List<PAlertStation> stations,
    Set<String> confirmedIds, {
    DateTime? now,
  }) async {
    if (_disposed) return null;
    if (_useNative) {
      final clock = now ?? DateTime.now();
      final payload = ForegroundStationPayload.palert(
        stations,
        receivedTime: clock,
      );
      payload['detectedStationIds'] = confirmedIds.toList(growable: false);
      return _submitNative(JsonUtf8Encoder().convert(payload), clock);
    }
    final frame = List<PAlertStation>.of(stations);
    final ids = Set<String>.of(confirmedIds);
    final receivedAt = now ?? DateTime.now();
    final generation = _generation;
    final port = await _start();
    if (_disposed || generation != _generation || port == null) return null;
    final id = _nextId++;
    final result = Completer<List<SeismicActiveEvent>?>();
    _pending[id] = result;
    port.send((id, frame, ids, receivedAt));
    return result.future;
  }

  Future<SendPort?> _start() {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<SendPort?>();
    final generation = _generation;
    final responses = _responses = ReceivePort();
    final errors = _errors = ReceivePort();
    final exits = _exits = ReceivePort();
    responses.listen((dynamic message) {
      if (generation != _generation) return;
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is _Result) {
        _pending.remove(message.$1)?.complete(message.$2);
      } else if (message is (int, String)) {
        _fail(StateError(message.$2));
      }
    });
    errors.listen((dynamic error) {
      if (generation == _generation) {
        _fail(StateError('P-Alert worker: $error'));
      }
    });
    exits.listen((_) {
      if (generation == _generation) _fail(StateError('P-Alert worker exited'));
    });
    unawaited(
      Isolate.spawn(
        _run,
        responses.sendPort,
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'palert-source-estimation',
      ).then(
        (isolate) {
          if (generation != _generation) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _isolate = isolate;
          }
        },
        onError: (Object error) {
          if (generation == _generation) _fail(error);
        },
      ),
    );
    return ready.future;
  }

  void _fail(Object error) {
    if (_ready case final ready? when !ready.isCompleted) {
      ready.completeError(error);
    }
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    reset();
  }

  void reset() {
    _generation++;
    _native?.stop();
    _native = null;
    _nativeSent = 0;
    if (_nativePending case final pending? when !pending.isCompleted)
      pending.complete(null);
    _nativePending = null;
    if (_ready case final ready? when !ready.isCompleted) ready.complete(null);
    _ready = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _responses = _errors = _exits = null;
    for (final pending in _pending.values) {
      pending.complete(null);
    }
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}

void _run(SendPort output) {
  final input = ReceivePort();
  final session = PAlertSourceEstimation();
  late final detector = PAlertDetector();
  input.listen((dynamic message) {
    final int id;
    final List<PAlertStation> stations;
    final Set<String> active;
    final DateTime now;
    if (message is _Frame) {
      (id, stations, active, now) = message;
    } else {
      final (request, snapshot, receivedAt, sensitivity) =
          message as _RecordedFrame;
      id = request;
      now = receivedAt;
      try {
        stations = ForegroundStationPayload.decodePAlert(snapshot['stations']);
        if (stations.isEmpty) {
          output.send((id, null));
          return;
        }
        if (snapshot.containsKey('detectedStationIds')) {
          active = ForegroundStationPayload.decodePAlertDetectedStationIds(
            snapshot,
            now: now,
          );
        } else {
          detector.setSensitivity(sensitivity);
          detector.update(stations, now: now);
          active = {
            for (final entry in detector.snapshot.detectedStations) entry.code,
          };
        }
      } catch (error) {
        output.send((id, error.toString()));
        return;
      }
    }
    try {
      final estimates = session.update(stations, active, now);
      final activeStations = stations.where((s) => active.contains(s.id));
      final maxIndex = activeStations.fold<int>(-1, (value, station) {
        final index = PAlertSourceProfile.intensityIndexFromLevel(
          station.currentGridLevel,
        );
        return index > value ? index : value;
      });
      final events = <SeismicActiveEvent>[
        for (final estimate in estimates)
          SeismicActiveEvent(
            eventId:
                '${session.eventId}:${estimate.diagnostics['selected_detection_id']}',
            sourceId: 'palert',
            startedAt: estimate.originTime!,
            updatedAt: now,
            stageName: 'confirmed',
            maxShindo: -1,
            estimate: estimate,
            metadata: {'palert_max_cwa_intensity_index': maxIndex},
          ),
      ];
      output.send((id, events));
    } catch (error) {
      output.send((id, error.toString()));
    }
  });
  output.send(input.sendPort);
}
