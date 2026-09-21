import 'dart:async';
import 'dart:isolate';

import '../../core/source_estimation/source_estimation_models.dart';
import 'palert_service.dart';
import 'palert_source_estimation.dart';

typedef _Frame = (int, List<PAlertStation>, Set<String>, DateTime);
typedef _Result = (int, List<SeismicActiveEvent>);

/// Persistent ordered session, isolated from both UI and NIED inference state.
class PAlertSourceWorker {
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Completer<SendPort?>? _ready;
  final _pending = <int, Completer<List<SeismicActiveEvent>?>>{};
  int _generation = 0;
  int _nextId = 0;
  bool _disposed = false;

  Future<List<SeismicActiveEvent>?> process(
    List<PAlertStation> stations,
    Set<String> confirmedIds, {
    DateTime? now,
  }) async {
    if (_disposed) return null;
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
  input.listen((dynamic message) {
    final (id, stations, active, now) = message as _Frame;
    try {
      final estimates = session.update(stations, active, now);
      final activeStations = stations.where((s) => active.contains(s.id));
      final maxIndex = activeStations.fold<int>(
        -1,
        (value, station) => (station.cwaIntensityIndex ?? -1) > value
            ? station.cwaIntensityIndex!
            : value,
      );
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
