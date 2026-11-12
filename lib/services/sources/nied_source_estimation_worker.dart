import 'dart:async';
import 'dart:isolate';

import '../../core/event_detection/event_detection_models.dart';
import '../../core/nied_replay_logger.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import 'nied_monitor.dart';
import 'nied_source_estimation_driver.dart';
import 'nied_source_station_frame.dart';

typedef _Trigger = (String?, DateTime, String, Map<String, Object?>);

class NiedSourceEstimationResult {
  final EventDetection detection;
  final SeismicActiveEvent? event;
  final List<SeismicActiveEvent>? history;
  final List<_Trigger> _triggers;
  final int computationMicroseconds;

  const NiedSourceEstimationResult(
    this.detection,
    this.event,
    this.history,
    this._triggers,
    this.computationMicroseconds,
  );

  void publish() {
    final tracker = StationEventTracker.instance;
    if (history != null) tracker.niedEventHistory.value = history!;
    tracker.currentNiedEvent.value = event;
    final logger = NiedReplayLogger.instance;
    for (final trigger in _triggers) {
      logger.startForSourceTrigger(
        eventId: trigger.$1,
        observedAt: trigger.$2,
        stageName: trigger.$3,
        metadata: trigger.$4,
      );
    }
    final estimate = event?.estimate;
    if (estimate != null && logger.isEnabled) {
      logger.logEpicenter(
        lat: estimate.latitude,
        lng: estimate.longitude,
        confidence: estimate.confidence,
        activeStationCount: estimate.supportingStationCount,
      );
    }
  }
}

/// A persistent, ordered inference session. The stateful HYP algorithm and its
/// adjacency caches stay off the UI isolate; observations are never coalesced.
class NiedSourceEstimationWorker {
  NiedSourceEstimationWorker({
    this.displayOnly = false,
    this.includeObservationHistory = true,
  });

  /// A map/card projection needs station summaries, not private observation
  /// windows or the inference owner's archived events. Inputs are unchanged.
  final bool displayOnly;

  /// Display consumers retain record summaries; private windows stay here.
  final bool includeObservationHistory;
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Completer<SendPort?>? _ready;
  final Map<int, Completer<NiedSourceEstimationResult?>> _pending = {};
  final _submittedAt = <int, int>{};
  final _diagnosticClock = Stopwatch()..start();
  int _submitted = 0, _completed = 0, _maxPending = 0;
  int _lastComputeUs = 0, _maxComputeUs = 0, _lastTurnaroundUs = 0;
  Map<String, Object?> get diagnostics => {
    'pending': _pending.length,
    'maxPending': _maxPending,
    'submitted': _submitted,
    'completed': _completed,
    'lastComputeUs': _lastComputeUs,
    'maxComputeUs': _maxComputeUs,
    'lastTurnaroundUs': _lastTurnaroundUs,
  };
  int _generation = 0;
  int _nextId = 0;
  int _sensitivity = 2;
  bool _disposed = false;
  final _stationEncoder = NiedSourceStationEncoder();

  void setSensitivity(int value) => _sensitivity = value.clamp(1, 3);

  Future<NiedSourceEstimationResult?> processStations(
    List<NiedStation> stations, {
    DateTime? observedAt,
  }) async {
    if (_disposed) return null;
    // Capture original dynamic inputs before the first await. KA histories
    // remain in their calculation owner; this consumer never reads them.
    final snapshot = _stationEncoder.capture(stations);
    return _submit(snapshot, observedAt: observedAt);
  }

  Future<NiedSourceEstimationResult?> processRawStations(
    dynamic rawStations, {
    DateTime? observedAt,
  }) async {
    if (_disposed) return null;
    // Archived snapshots are immutable. Send the original graph directly;
    // layout comparison, date parsing and numeric packing run in the owner.
    // A later typed input must include its catalogue after a raw input.
    _stationEncoder.reset();
    return _submit(rawStations, observedAt: observedAt);
  }

  Future<NiedSourceEstimationResult?> _submit(
    Object? snapshot, {
    DateTime? observedAt,
  }) async {
    final generation = _generation;
    final sensitivity = _sensitivity;
    final port = await _ensureStarted();
    if (generation != _generation || _disposed || port == null) return null;
    final id = _nextId++;
    final completer = Completer<NiedSourceEstimationResult?>();
    _pending[id] = completer;
    _submittedAt[id] = _diagnosticClock.elapsedMicroseconds;
    _submitted++;
    if (_pending.length > _maxPending) _maxPending = _pending.length;
    try {
      port.send((id, snapshot, observedAt, sensitivity));
    } catch (error, stack) {
      _pending.remove(id);
      _submittedAt.remove(id);
      completer.completeError(error, stack);
    }
    return completer.future;
  }

  Future<SendPort?> _ensureStarted() {
    if (_ready != null) return _ready!.future;
    final ready = Completer<SendPort?>();
    _ready = ready;
    final generation = _generation;
    SendPort? generationPort;
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    _responses = responses;
    _errors = errors;
    _exits = exits;
    responses.listen((dynamic message) {
      if (generation != _generation) return;
      if (message is SendPort) {
        generationPort = message;
        _commandPort = message;
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is (int, NiedSourceEstimationResult)) {
        _completed++;
        _lastComputeUs = message.$2.computationMicroseconds;
        if (_lastComputeUs > _maxComputeUs) _maxComputeUs = _lastComputeUs;
        final submitted = _submittedAt.remove(message.$1);
        if (submitted != null)
          _lastTurnaroundUs = _diagnosticClock.elapsedMicroseconds - submitted;
        _pending.remove(message.$1)?.complete(message.$2);
      } else if (message is (int, String, String)) {
        _fail(StateError(message.$2), StackTrace.fromString(message.$3));
      }
    });
    errors.listen((dynamic error) {
      if (generation == _generation) {
        _fail(StateError('NIED source worker: $error'), StackTrace.current);
      }
    });
    exits.listen((_) {
      if (generation == _generation) {
        _fail(StateError('NIED source worker exited'), StackTrace.current);
      }
    });
    unawaited(
      Isolate.spawn(
        _sourceWorkerMain,
        (responses.sendPort, displayOnly, includeObservationHistory),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'nied-source-estimation',
      ).then(
        (isolate) {
          if (generation != _generation) {
            // A ready message can race the spawn Future. A configured native
            // session must close cooperatively even in that startup race.
            if (generationPort case final port?) {
              port.send('close');
            } else {
              isolate.kill(priority: Isolate.immediate);
            }
          } else {
            _isolate = isolate;
          }
        },
        onError: (Object error, StackTrace stack) {
          if (generation == _generation) _fail(error, stack);
        },
      ),
    );
    return ready.future;
  }

  void _fail(Object error, StackTrace stack) {
    if (_ready case final ready? when !ready.isCompleted) {
      ready.completeError(error, stack);
    }
    for (final pending in _pending.values) {
      pending.completeError(error, stack);
    }
    _pending.clear();
    _submittedAt.clear();
    reset();
  }

  void reset() {
    _generation++;
    _stationEncoder.reset();
    // Wake startup waiters, which then discard this generation without sending.
    if (_ready case final ready? when !ready.isCompleted) {
      ready.complete(null);
    }
    _ready = null;
    if (_commandPort case final port?) {
      // Native state belongs to this worker. Finish its current synchronous
      // computation, dispose the driver, then exit instead of abandoning it.
      port.send('close');
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _commandPort = null;
    _isolate = null;
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _responses = _errors = _exits = null;
    for (final pending in _pending.values) {
      pending.complete(null);
    }
    _pending.clear();
    _submittedAt.clear();
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}

void _sourceWorkerMain((SendPort, bool, bool) configuration) {
  final (output, displayOnly, includeObservationHistory) = configuration;
  final input = ReceivePort();
  final triggers = <_Trigger>[];
  final tracker = StationEventTracker.instance..useNativeObservationHistories();
  final stationDecoder = NiedSourceStationDecoder();
  final rawEncoder = NiedSourceStationEncoder();
  final driver = NiedSourceEstimationDriver(
    onSourceTrigger: (id, time, stage, metadata) =>
        triggers.add((id, time, stage, metadata)),
  );
  var previousHistory = tracker.niedEventHistory.value;
  input.listen((dynamic message) {
    if (message == 'close') {
      stationDecoder.dispose();
      tracker.resetNied();
      driver.dispose();
      input.close();
      Isolate.exit();
    }
    final (id, payload, observedAt, sensitivity) =
        message as (int, Object?, DateTime?, int);
    try {
      final NiedSourceStationFrame frame;
      if (payload is NiedSourceStationFrame) {
        rawEncoder.reset();
        frame = payload;
      } else {
        frame = rawEncoder.captureRaw(payload);
      }
      final stations = stationDecoder.apply(frame);
      triggers.clear();
      driver.setSensitivity(sensitivity);
      final stopwatch = Stopwatch()..start();
      final detection = driver.processStations(
        stations,
        observedAt: observedAt,
      );
      stopwatch.stop();
      final history = tracker.niedEventHistory.value;
      output.send((
        id,
        NiedSourceEstimationResult(
          detection,
          _eventForTransfer(
            tracker.currentNiedEvent.value,
            includeRecords: !displayOnly,
            includeObservationHistory: includeObservationHistory,
          ),
          displayOnly || identical(history, previousHistory)
              ? null
              : [
                  for (final event in history)
                    _eventForTransfer(
                      event,
                      includeObservationHistory: includeObservationHistory,
                    )!,
                ],
          List.of(triggers),
          stopwatch.elapsedMicroseconds,
        ),
      ));
      previousHistory = history;
    } catch (error, stack) {
      output.send((id, error.toString(), stack.toString()));
    }
  });
  output.send(input.sendPort);
}

/// Do not send native owners or their complete materialized frame graphs.
/// All event/record fields are preserved; histories carry owned compact rows.
SeismicActiveEvent? _eventForTransfer(
  SeismicActiveEvent? event, {
  bool includeRecords = true,
  bool includeObservationHistory = true,
}) {
  if (event == null) return null;
  return SeismicActiveEvent(
    eventId: event.eventId,
    sourceId: event.sourceId,
    startedAt: event.startedAt,
    updatedAt: event.updatedAt,
    endedAt: event.endedAt,
    stageName: event.stageName,
    maxShindo: event.maxShindo,
    estimate: event.estimate,
    metadata: event.metadata,
    stationRecords: includeRecords
        ? {
            for (final entry in event.stationRecords.entries)
              entry.key: _recordForTransfer(
                entry.value,
                includeObservationHistory: includeObservationHistory,
              ),
          }
        : const {},
  );
}

SeismicStationEventRecord _recordForTransfer(
  SeismicStationEventRecord r, {
  bool includeObservationHistory = true,
}) => SeismicStationEventRecord(
  descriptor: r.descriptor,
  firstObservedAt: r.firstObservedAt,
  firstRiseInterval: r.firstRiseInterval,
  firstTriggerInterval: r.firstTriggerInterval,
  peakAt: r.peakAt,
  lastObservedAt: r.lastObservedAt,
  endAt: r.endAt,
  peakValue: r.peakValue,
  lastValue: r.lastValue,
  lastPga: r.lastPga,
  lastPgv: r.lastPgv,
  lastPgd: r.lastPgd,
  eventPhysicalPeaks: r.eventPhysicalPeaks,
  lastRawLevel: r.lastRawLevel,
  lastDetectLevel: r.lastDetectLevel,
  lastActivity: r.lastActivity,
  lastAscend: r.lastAscend,
  sampleCount: r.sampleCount,
  state: r.state,
  qualityFlags: r.qualityFlags,
  provenance: r.provenance,
  observationHistory: includeObservationHistory
      ? r.observationHistory.detachedSnapshot()
      : null,
);
