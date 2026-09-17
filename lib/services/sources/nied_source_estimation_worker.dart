import 'dart:async';
import 'dart:isolate';

import '../../core/event_detection/event_detection_models.dart';
import '../../core/nied_replay_logger.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import 'nied_monitor.dart';
import 'nied_source_estimation_driver.dart';

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
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Completer<SendPort?>? _ready;
  final Map<int, Completer<NiedSourceEstimationResult?>> _pending = {};
  int _generation = 0;
  int _nextId = 0;
  int _sensitivity = 2;
  bool _disposed = false;

  void setSensitivity(int value) => _sensitivity = value.clamp(1, 3);

  Future<NiedSourceEstimationResult?> processStations(
    List<NiedStation> stations, {
    DateTime? observedAt,
  }) async {
    if (_disposed) return null;
    // Capture before the first await: live station objects contain timers and
    // are mutated in place by subsequent network frames.
    final snapshot = stations.map(_snapshotStation).toList(growable: false);
    final generation = _generation;
    final sensitivity = _sensitivity;
    final port = await _ensureStarted();
    if (generation != _generation || _disposed || port == null) return null;
    final id = _nextId++;
    final completer = Completer<NiedSourceEstimationResult?>();
    _pending[id] = completer;
    try {
      port.send((id, snapshot, observedAt, sensitivity));
    } catch (error, stack) {
      _pending.remove(id);
      completer.completeError(error, stack);
    }
    return completer.future;
  }

  Future<SendPort?> _ensureStarted() {
    if (_ready != null) return _ready!.future;
    final ready = Completer<SendPort?>();
    _ready = ready;
    final generation = _generation;
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    _responses = responses;
    _errors = errors;
    _exits = exits;
    responses.listen((dynamic message) {
      if (generation != _generation) return;
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is (int, NiedSourceEstimationResult)) {
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
        responses.sendPort,
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'nied-source-estimation',
      ).then(
        (isolate) {
          if (generation != _generation) {
            isolate.kill(priority: Isolate.immediate);
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
    reset();
  }

  void reset() {
    _generation++;
    // Wake startup waiters, which then discard this generation without sending.
    if (_ready case final ready? when !ready.isCompleted) {
      ready.complete(null);
    }
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

NiedStation _snapshotStation(NiedStation station) =>
    NiedStation(
        id: station.id,
        code: station.code,
        name: station.name,
        coordinate: station.coordinate,
        network: station.network,
        prefecture: station.prefecture,
        expireSeconds: station.expireSeconds,
        pixelX: station.pixelX,
        pixelY: station.pixelY,
        scanReliable: station.scanReliable,
        pixelClusterId: station.pixelClusterId,
        level: station.level,
      )
      ..defaultExpireSeconds = station.defaultExpireSeconds
      ..calibrationFactor = station.calibrationFactor
      ..thresholdCode = station.thresholdCode
      ..ascend = station.ascend
      ..triggerStamp = station.triggerStamp
      ..activity = station.activity
      ..isActive = station.isActive
      ..abnormalUpdateCount = station.abnormalUpdateCount
      ..detectState = station.detectState
      ..detectReason = station.detectReason
      ..recentLevel = List.of(station.recentLevel)
      ..lastUpdate = station.lastUpdate
      ..lastDataTime = station.lastDataTime
      ..lastReceivedAt = station.lastReceivedAt
      ..gifObservations.addAll(station.gifObservations)
      ..gifLayerQualityFlags.addAll({
        for (final entry in station.gifLayerQualityFlags.entries)
          entry.key: Set.of(entry.value),
      });

void _sourceWorkerMain(SendPort output) {
  final input = ReceivePort();
  final triggers = <_Trigger>[];
  final tracker = StationEventTracker.instance;
  final driver = NiedSourceEstimationDriver(
    onSourceTrigger: (id, time, stage, metadata) =>
        triggers.add((id, time, stage, metadata)),
  );
  var previousHistory = tracker.niedEventHistory.value;
  input.listen((dynamic message) {
    final (id, stations, observedAt, sensitivity) =
        message as (int, List<NiedStation>, DateTime?, int);
    try {
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
          tracker.currentNiedEvent.value,
          identical(history, previousHistory) ? null : history,
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
