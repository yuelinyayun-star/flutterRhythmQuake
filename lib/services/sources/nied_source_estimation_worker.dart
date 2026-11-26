import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import '../../core/event_detection/event_detection_models.dart';
import '../../core/nied_replay_logger.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/srev_kaizou_magnitude.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import 'nied_monitor.dart';
import 'jp_shindo_scale.dart';
import 'native_nied_detection_owner.dart';
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

/// Projection of the original SREV slots, not a second trigger or estimator.
class SrevSourceProjection {
  static const method = 'nied_srev_hyp_rust_v1';
  static const _epoch2000Ms = 946684800000;
  final _active = <String, SeismicActiveEvent>{};
  final _history = <SeismicActiveEvent>[];
  String? _primaryId;
  // Production magnitude: reuse the pre-migration calibrated formula and 10s hold.
  // The former HYP report-number lock does not have a SREV equivalent.
  final _rqMagnitudeHold = SrevKaizouMagnitudeIntensityState();
  final _rqPeakByEvent = <String, double>{};

  void reset() {
    _active.clear();
    _history.clear();
    _primaryId = null;
    _rqMagnitudeHold.clear();
    _rqPeakByEvent.clear();
  }

  static DateTime _time(num seconds) => DateTime.fromMillisecondsSinceEpoch(
    _epoch2000Ms + (seconds * 1000).round(),
    isUtc: true,
  );

  NiedSourceEstimationResult project(
    List<dynamic> rows,
    List<NiedStation> stations,
    DateTime observedAt, {
    int computationMicroseconds = 0,
  }) {
    final next = <String, SeismicActiveEvent>{};
    final triggers = <_Trigger>[];
    final published = <Map<String, Object?>>[];
    // Same comparable physical shindo convention as the retired driver.
    final active = <String, double?>{};
    for (final s in stations) {
      if (!s.isActive || s.isRealtimeObservationMissing) continue;
      final fine = s.gifObservation?.shindo;
      active[s.code] = fine != null && fine.isFinite
          ? fine
          : s.kaLevel >= 0
          ? JpShindoScale.rawShindoFromKanameishiLevel(s.kaLevel)
          : null;
    }
    _rqMagnitudeHold.updateFrame(active, observedAt: observedAt);
    final multiple = rows.length > 1;
    for (final raw in rows) {
      final row = raw as Map;
      final slot = (row['id'] as num).toInt();
      final start = _time(row['start'] as num);
      final id = 'nied-srev-${start.millisecondsSinceEpoch}-$slot';
      final members = <NiedStation>[
        for (final index in row['members'] as List)
          if (index is int && index >= 0 && index < stations.length)
            stations[index],
      ];
      var max = -1;
      for (final station in members) {
        final rank = JpShindoScale.jmaNumberFromKanameishiLevel(station.level);
        if (rank > max) max = rank;
      }
      final previous = _active[id];
      if (previous != null && previous.maxShindo > max)
        max = previous.maxShindo;
      final stage = max >= 4
          ? 'strong'
          : max >= 1
          ? 'detected'
          : 'weak';
      final rawEstimate = row['estimate'];
      final accepted = row['hyp_accepted_at'] as num?;
      final oldAccepted =
          previous?.estimate?.diagnostics['srev_hyp_accepted_at'] as num?;
      final oldReport =
          (previous?.estimate?.diagnostics['srev_hyp_report_num'] as int?) ?? 0;
      // Count the first accepted solution and distinct commits at this
      // observation time. A merge can copy another slot's older timestamp.
      final commitNow =
          accepted != null &&
          accepted == row['observed_at'] &&
          (oldAccepted == null || accepted > oldAccepted);
      final report = accepted != null && (oldReport == 0 || commitNow)
          ? oldReport + 1
          : oldReport;
      final hypState = row['hyp_state'] as String? ?? 'unknown';

      final count = (row['count'] as num).toInt();
      final current = _rqMagnitudeHold.maximumFor(
        multiple ? members.map((s) => s.code) : active.keys,
      );
      if (current != null &&
          (_rqPeakByEvent[id] == null || current > _rqPeakByEvent[id]!)) {
        _rqPeakByEvent[id] = current;
      }
      final shadow = <String, Object?>{};
      if (rawEstimate is Map) {
        final peak = _rqPeakByEvent[id];
        SrevKaizouMagnitudeResult? calc(double? input) => input == null
            ? null
            : calculateSrevKaizouMagnitude(
                sourceLatitude: (rawEstimate['lat'] as num).toDouble(),
                sourceLongitude: (rawEstimate['lon'] as num).toDouble(),
                inputIntensity: input,
                multipleSources: multiple,
              );
        final now = calc(current);
        final held = peak == current ? now : calc(peak);
        shadow.addAll({
          'rq_magnitude_shadow': held?.magnitude,
          'rq_magnitude_shadow_current': now?.magnitude,
          'rq_magnitude_shadow_input': current,
          'rq_magnitude_shadow_peak': peak,
          'rq_magnitude_shadow_distance_km': held?.clampedStationDistanceKm,
          'rq_magnitude_shadow_multiple_sources': multiple,
          'rq_magnitude_shadow_model': srevKaizouMagnitudeModelId,
          'rq_magnitude_shadow_policy':
              'legacy_hold_peak_recompute_no_report_lock',
          if (now != null)
            'rq_magnitude_uncalibrated_current':
                (now.processedIntensity -
                        0.94 +
                        1.73 *
                            (math.log(now.clampedStationDistanceKm) /
                                math.ln10))
                    .clamp(0.0, double.infinity),
        });
      }
      final rqMagnitude = (shadow['rq_magnitude_shadow'] as num?)?.toDouble();
      final originalMagnitude = rawEstimate is Map
          ? (rawEstimate['magnitude'] as num?)?.toDouble()
          : null;
      final estimate = rawEstimate is Map
          ? SourceEstimate(
              latitude: (rawEstimate['lat'] as num).toDouble(),
              longitude: (rawEstimate['lon'] as num).toDouble(),
              depthKm: (rawEstimate['depth'] as num).toDouble(),
              magnitude: rqMagnitude ?? originalMagnitude,
              originTime: _time(rawEstimate['origin'] as num),
              // SREV's residual is not a calibrated probability.
              confidence: 0,
              method: method,
              supportingStationCount: count,
              diagnostics: {
                'selected_detection_id': slot,
                'srev_error': rawEstimate['error'],
                'srev_hyp_state': hypState,
                'srev_hyp_accepted_at': accepted,
                'srev_hyp_report_num': report,
                'srev_hyp_report_time': accepted == null
                    ? null
                    : _time(accepted).toIso8601String(),
                'srev_source_event_id': id,
                'wave_elapsed_s':
                    (row['observed_at'] as num? ??
                        (observedAt.millisecondsSinceEpoch - _epoch2000Ms) /
                            1000) -
                    (rawEstimate['origin'] as num),

                'srev_p_radius_km': rawEstimate['p_radius'],
                'srev_s_radius_km': rawEstimate['s_radius'],
                'confidence_available': false,
                ...shadow,
                'srev_original_magnitude': originalMagnitude,
                'magnitude_model': rqMagnitude != null
                    ? srevKaizouMagnitudeModelId
                    : originalMagnitude != null
                    ? 'srev_original_fallback'
                    : 'unavailable',
              },
            )
          : null;
      final records = <String, SeismicStationEventRecord>{};
      for (final s in members) {
        final old = previous?.stationRecords[s.code];
        final value =
            s.gifObservation?.shindo ??
            JpShindoScale.rawShindoFromKanameishiLevel(s.level);
        final priorPeak = old?.peakValue;
        final newPeak = priorPeak == null || value > priorPeak;
        records[s.code] = SeismicStationEventRecord(
          descriptor: SeismicStationDescriptor(
            stationId: s.code,
            code: s.code,
            sourceId: 'nied',
            network: s.network,
            coordinate: s.coordinate,
          ),
          firstObservedAt: old?.firstObservedAt ?? observedAt,
          firstTriggerAt: s.triggerStamp > 0
              ? DateTime.fromMillisecondsSinceEpoch(s.triggerStamp, isUtc: true)
              : old?.firstTriggerAt,
          peakAt: newPeak ? observedAt : old?.peakAt,
          lastObservedAt: observedAt,
          peakValue: newPeak ? value : priorPeak,
          lastValue: value,
          lastRawLevel: s.level,
          lastDetectLevel: s.detectState,
          sampleCount: (old?.sampleCount ?? 0) + 1,
          state: s.detectState >= 6
              ? StationLifecycleState.strong
              : StationLifecycleState.triggered,
        );
      }
      final event = SeismicActiveEvent(
        eventId: id,
        sourceId: 'nied',
        startedAt: start,
        updatedAt: observedAt,
        stageName: stage,
        maxShindo: max,
        estimate: estimate,
        stationRecords: records,
        metadata: {
          'source_estimation_entry': method,
          'srev_hyp_state': hypState,
          'selected_detection_id': slot,
          'member_station_ids': members.map((s) => s.code).toList(),
        },
      );
      next[id] = event;
      if (previous == null) {
        triggers.add((
          id,
          observedAt,
          stage,
          {'source_estimation_entry': method},
        ));
      }
    }
    _rqPeakByEvent.removeWhere((id, _) => !next.containsKey(id));
    var historyChanged = false;
    for (final entry in _active.entries) {
      if (!next.containsKey(entry.key)) {
        entry.value.endedAt = observedAt;
        _history.add(entry.value);
        historyChanged = true;
      }
    }
    if (_history.length > 100) _history.removeRange(0, _history.length - 100);
    _active
      ..clear()
      ..addAll(next);
    final candidates = next.values.toList()
      ..sort((a, b) {
        final estimated = (b.estimate != null ? 1 : 0).compareTo(
          a.estimate != null ? 1 : 0,
        );
        if (estimated != 0) return estimated;
        return (b.estimate?.supportingStationCount ?? 0).compareTo(
          a.estimate?.supportingStationCount ?? 0,
        );
      });
    var primary = next[_primaryId];
    if (primary == null ||
        (primary.estimate == null &&
            candidates.isNotEmpty &&
            candidates.first.estimate != null)) {
      primary = candidates.isEmpty ? null : candidates.first;
    }
    _primaryId = primary?.eventId;
    for (final event in candidates) {
      final a = event.estimate;
      if (a == null) continue;
      published.add({
        'selected': event.eventId == _primaryId,
        'latitude': a.latitude,
        'longitude': a.longitude,
        'depth_km': a.depthKm,
        'magnitude': a.magnitude,
        'origin_time': a.originTime?.toIso8601String(),
        'confidence': a.confidence,
        'method': a.method,
        'supporting_station_count': a.supportingStationCount,
        'diagnostics': a.diagnostics,
      });
    }
    // Retain the existing map's multi-source transport contract.
    primary?.metadata['nied_dart_hyp_sources'] = published;
    final detection = EventDetection(
      detectorId: 'srev_nied_hyp_rust',
      sourceId: 'nied',
      eventId: primary?.eventId,
      observedAt: observedAt,
      startedAt: primary?.startedAt,
      updatedAt: primary?.updatedAt,
      state: primary == null
          ? EventDetectionState.idle
          : primary.stageName == 'strong'
          ? EventDetectionState.strong
          : primary.estimate == null
          ? EventDetectionState.candidate
          : EventDetectionState.confirmed,
      memberStationIds: primary == null
          ? const []
          : (primary.metadata['member_station_ids'] as List).cast<String>(),
      maxIntensity: primary?.maxShindo ?? -1,
    );
    return NiedSourceEstimationResult(
      detection,
      primary,
      historyChanged ? List.of(_history) : null,
      triggers,
      computationMicroseconds,
    );
  }
}

/// A persistent, ordered inference session. The stateful HYP algorithm and its
/// adjacency caches stay off the UI isolate; observations are never coalesced.
class NiedSourceEstimationWorker {
  NiedSourceEstimationWorker({
    this.displayOnly = false,
    this.includeObservationHistory = true,
    this.srevDetectionInput = false,
    this.useSrevHyp = false,
  });

  /// A map/card projection needs station summaries, not private observation
  /// windows or the inference owner's archived events. Inputs are unchanged.
  final bool displayOnly;

  /// Display consumers retain record summaries; private windows stay here.
  final bool includeObservationHistory;
  final bool srevDetectionInput;
  final bool useSrevHyp;
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
        (
          responses.sendPort,
          displayOnly,
          includeObservationHistory,
          srevDetectionInput,
          useSrevHyp,
        ),
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

void _sourceWorkerMain((SendPort, bool, bool, bool, bool) configuration) {
  final (
    output,
    displayOnly,
    includeObservationHistory,
    srevDetectionInput,
    useSrevHyp,
  ) = configuration;
  final input = ReceivePort();
  final triggers = <_Trigger>[];
  final tracker = StationEventTracker.instance..useNativeObservationHistories();
  final stationDecoder = NiedSourceStationDecoder();
  final rawEncoder = NiedSourceStationEncoder();
  final driver = useSrevHyp
      ? null
      : NiedSourceEstimationDriver(
          srevDetectionInput: srevDetectionInput,
          onSourceTrigger: (id, time, stage, metadata) =>
              triggers.add((id, time, stage, metadata)),
        );
  final srevProjection = SrevSourceProjection();
  NativeNiedDetectionOwner? srevOwner;
  String? srevCatalogue;
  List<dynamic> srevRows = const [];
  int? firstSrevTime;
  var previousHistory = tracker.niedEventHistory.value;
  input.listen((dynamic message) {
    if (message == 'close') {
      stationDecoder.dispose();
      tracker.resetNied();
      driver?.dispose();
      srevOwner?.dispose();
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
      if (useSrevHyp) {
        final watch = Stopwatch()..start();
        final time =
            observedAt ??
            stations.fold<DateTime?>(null, (old, s) {
              final t = s.lastDataTime ?? s.lastUpdate;
              return t != null && (old == null || t.isAfter(old)) ? t : old;
            }) ??
            DateTime.now();
        final catalogue = stations
            .map((s) => '${s.code}:${s.name}:${s.coordinate}')
            .join('|');
        if (catalogue != srevCatalogue) {
          srevOwner?.dispose();
          srevProjection.reset();
          srevRows = const [];
          firstSrevTime = null;
          srevCatalogue = catalogue;
          srevOwner = stations.isEmpty
              ? null
              : NativeNiedDetectionOwner(
                  stations,
                  manualClock: true,
                  useSrev: true,
                  onUpdate: (result) {
                    if (result.length > 4) srevRows = result[4] as List;
                  },
                );
        }
        firstSrevTime ??= time.millisecondsSinceEpoch;
        srevRows = const [];
        srevOwner?.process(
          stations,
          sensitivity,
          clock: (time.millisecondsSinceEpoch - firstSrevTime!).clamp(
            0,
            1 << 53,
          ),
          solveSrev: true,
        );
        srevOwner?.rebind(stations);
        watch.stop();
        final result = srevProjection.project(
          srevRows,
          stations,
          time,
          computationMicroseconds: watch.elapsedMicroseconds,
        );
        output.send((id, result));
        return;
      }
      driver!.setSensitivity(sensitivity);
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
