import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../event_detection/event_detection_models.dart';
import 'source_candidate_region_tracker.dart';
import 'source_estimation_models.dart';
import 'source_estimator.dart';
import 'station_observation_history.dart';

class SourceEstimateStabilityConfig {
  final Duration warmupDuration;
  final double maxJumpKm;
  final double maxAnchorDistanceKm;

  const SourceEstimateStabilityConfig({
    this.warmupDuration = const Duration(seconds: 15),
    this.maxJumpKm = 60,
    this.maxAnchorDistanceKm = 100,
  });
}

class _PhaseBestFitEstimate {
  final String eventId;
  final SourceEstimate estimate;
  final double phaseMeanResidualSeconds;

  const _PhaseBestFitEstimate({
    required this.eventId,
    required this.estimate,
    required this.phaseMeanResidualSeconds,
  });
}

class SeismicSourceTracker {
  final Map<String, ValueNotifier<SeismicActiveEvent?>> _currentBySource = {};
  final Map<String, ValueNotifier<List<SeismicActiveEvent>>> _historyBySource =
      {};
  final Map<String, SourceEstimator> _estimatorsBySource = {};
  final Map<String, int> _sequenceBySource = {};
  final Map<String, String> _lastEstimateSignatureBySource = {};
  final Map<String, SourceEstimate?> _lastEstimateBySource = {};
  final Map<String, _PhaseBestFitEstimate> _phaseBestFitBySource = {};
  final Map<String, SourceEstimateStabilityConfig> _stabilityBySource = {};
  final Map<String, DateTime> _firstEstimateAtBySource = {};
  final Map<String, SourceEstimate> _stabilityAnchorBySource = {};
  final Map<String, SourceCandidateRegionTracker> _candidateRegionBySource = {};
  final SourceCandidateResidualGate _candidateResidualGate =
      const SourceCandidateResidualGate();
  final SourceCandidateLocalSupportGate _candidateLocalSupportGate =
      const SourceCandidateLocalSupportGate();

  ValueNotifier<SeismicActiveEvent?> currentEventNotifier(String sourceId) {
    return _currentBySource.putIfAbsent(sourceId, () => ValueNotifier(null));
  }

  ValueNotifier<List<SeismicActiveEvent>> historyNotifier(String sourceId) {
    return _historyBySource.putIfAbsent(
      sourceId,
      () => ValueNotifier(const []),
    );
  }

  SeismicActiveEvent? currentEvent(String sourceId) =>
      currentEventNotifier(sourceId).value;

  List<SeismicActiveEvent> history(String sourceId) =>
      historyNotifier(sourceId).value;

  void setEstimator(String sourceId, SourceEstimator estimator) {
    _estimatorsBySource[sourceId] = estimator;
  }

  void setStabilityConfig(
    String sourceId,
    SourceEstimateStabilityConfig? config,
  ) {
    if (config == null) {
      _stabilityBySource.remove(sourceId);
    } else {
      _stabilityBySource[sourceId] = config;
    }
    _clearStabilityState(sourceId);
  }

  void resetSource(String sourceId) {
    currentEventNotifier(sourceId).value = null;
    historyNotifier(sourceId).value = const [];
    _sequenceBySource[sourceId] = 0;
    _lastEstimateSignatureBySource.remove(sourceId);
    _lastEstimateBySource.remove(sourceId);
    _phaseBestFitBySource.remove(sourceId);
    _candidateRegionBySource.remove(sourceId);
    _clearStabilityState(sourceId);
  }

  void resetAll() {
    for (final sourceId in {
      ..._currentBySource.keys,
      ..._historyBySource.keys,
      ..._sequenceBySource.keys,
    }) {
      resetSource(sourceId);
    }
  }

  void ingestFrame({
    required String sourceId,
    required DateTime observedAt,
    required String stageName,
    required int maxShindo,
    required List<SeismicStationSample> samples,
    String? eventId,
    Map<String, Object?> metadata = const {},
    bool splitOnEventIdChange = false,
  }) {
    var activeEvent = currentEvent(sourceId);
    final hasSignal = stageName != 'idle';

    if (activeEvent == null && !hasSignal) {
      return;
    }

    if (activeEvent != null &&
        hasSignal &&
        splitOnEventIdChange &&
        eventId != null &&
        activeEvent.eventId != eventId) {
      activeEvent.endedAt ??= observedAt;
      final historyItems = List<SeismicActiveEvent>.from(history(sourceId))
        ..insert(0, _archivedEventView(activeEvent));
      if (historyItems.length > 20) {
        historyItems.removeRange(20, historyItems.length);
      }
      historyNotifier(sourceId).value = List.unmodifiable(historyItems);
      currentEventNotifier(sourceId).value = null;
      _lastEstimateSignatureBySource.remove(sourceId);
      _lastEstimateBySource.remove(sourceId);
      _phaseBestFitBySource.remove(sourceId);
      _candidateRegionBySource.remove(sourceId);
      _clearStabilityState(sourceId);
      activeEvent = null;
    }

    if (activeEvent == null && hasSignal) {
      _clearStabilityState(sourceId);
      _phaseBestFitBySource.remove(sourceId);
      final seq = _sequenceBySource[sourceId] ?? 0;
      _sequenceBySource[sourceId] = seq + 1;
      final resolvedEventId =
          eventId ?? '$sourceId-${observedAt.toIso8601String()}-$seq';
      activeEvent = SeismicActiveEvent(
        eventId: resolvedEventId,
        sourceId: sourceId,
        startedAt: observedAt,
        updatedAt: observedAt,
        stageName: stageName,
        maxShindo: maxShindo,
        metadata: <String, Object?>{
          'source_family': sourceId,
          'estimate_revision': 0,
          ...metadata,
        },
      );
    }

    if (activeEvent == null) {
      return;
    }

    activeEvent
      ..updatedAt = observedAt
      ..stageName = stageName
      ..maxShindo = maxShindo;
    activeEvent.metadata.addAll(metadata);
    final strictStationTiming =
        sourceId == 'nied' ||
        activeEvent.metadata['nied_hypocenter_input_format'] ==
            'nied_station_hypocenter_snapshot_v1';
    final sourceTriggerMemberIds = _sourceTriggerMemberIds(
      activeEvent.metadata,
    ).toSet();

    for (final sample in samples) {
      final isSourceTriggerMember = sourceTriggerMemberIds.contains(
        sample.descriptor.code,
      );
      final hasMeaningfulSample =
          sample.rawLevel != null ||
          sample.detectLevel != null ||
          sample.activity > 0 ||
          sample.ascend > 0 ||
          sample.isTriggered ||
          isSourceTriggerMember;

      if (!hasMeaningfulSample) {
        final existing = activeEvent.stationRecords[sample.descriptor.code];
        if (existing != null) {
          _appendObservation(
            existing,
            sample,
            observedAt,
            extraQualityFlags: const {'missing_observation'},
          );
          if (existing.isActiveLike &&
              existing.endAt == null &&
              _stationStateFromSample(sample) == StationLifecycleState.idle) {
            existing
              ..state = StationLifecycleState.ended
              ..endAt = observedAt
              ..lastObservedAt = observedAt;
          }
        }
        continue;
      }

      final record = activeEvent.stationRecords.putIfAbsent(
        sample.descriptor.code,
        () => SeismicStationEventRecord(
          descriptor: sample.descriptor,
          firstObservedAt: observedAt,
        ),
      );

      _appendObservation(record, sample, observedAt);

      record
        ..lastObservedAt = observedAt
        ..lastRawLevel = sample.rawLevel
        ..lastDetectLevel = sample.detectLevel
        ..lastActivity = sample.activity
        ..lastAscend = sample.ascend
        ..sampleCount += 1
        ..state = _stationStateFromSample(sample);

      if (sample.value != null && sample.value!.isFinite) {
        record.lastValue = sample.value;
        if (record.peakValue == null || sample.value! > record.peakValue!) {
          record
            ..peakValue = sample.value
            ..peakAt = observedAt;
        }
      }
      if (sample.observedPga != null &&
          sample.observedPga!.isFinite &&
          _hasIndependentProvenance(sample, StationValueType.pga)) {
        record.lastPga = sample.observedPga;
      }
      if (sample.observedPgv != null &&
          sample.observedPgv!.isFinite &&
          _hasIndependentProvenance(sample, StationValueType.pgv)) {
        record.lastPgv = sample.observedPgv;
      }
      if (sample.observedPgd != null &&
          sample.observedPgd!.isFinite &&
          _hasIndependentProvenance(sample, StationValueType.pgd)) {
        record.lastPgd = sample.observedPgd;
      }

      if (sample.ascend > 0 || sample.activity > 0) {
        if (sample.firstRiseInterval != null) {
          record.firstRiseInterval ??= sample.firstRiseInterval;
        } else if (!strictStationTiming) {
          record.firstRiseInterval ??= _latestObservationInterval(record);
        }
      }
      if (isSourceTriggerMember) {
        if (sample.firstRiseInterval != null) {
          record.firstRiseInterval ??= sample.firstRiseInterval;
        } else if (!strictStationTiming) {
          record.firstRiseInterval ??= ObservationTimeInterval(
            start: observedAt,
            end: observedAt,
          );
        }
      }
      if (sample.isTriggered) {
        if (sample.firstTriggerInterval != null) {
          record.firstTriggerInterval ??= sample.firstTriggerInterval;
        } else if (!strictStationTiming) {
          record.firstTriggerInterval ??= _latestObservationInterval(record);
        }
        record.endAt = null;
      } else if (record.hasTriggered && record.endAt == null) {
        record.endAt = observedAt;
      }

      _updateEventPhysicalPeaks(
        record: record,
        eventStartedAt: activeEvent.startedAt,
        sample: sample,
      );

      record.qualityFlags.addAll(sample.qualityFlags);
      record.provenance.addAll(sample.provenance);
    }
    if (sourceTriggerMemberIds.isNotEmpty) {
      var memberRecordCount = 0;
      var memberTimingCount = 0;
      for (final id in sourceTriggerMemberIds) {
        final record = activeEvent.stationRecords[id];
        if (record == null) continue;
        memberRecordCount += 1;
        if ((record.firstTriggerAt ?? record.firstRiseAt) != null) {
          memberTimingCount += 1;
        }
      }
      activeEvent.metadata['source_trigger_member_record_count'] =
          memberRecordCount;
      activeEvent.metadata['source_trigger_member_timing_count'] =
          memberTimingCount;
    } else {
      activeEvent.metadata.remove('source_trigger_member_record_count');
      activeEvent.metadata.remove('source_trigger_member_timing_count');
    }

    final estimator = _estimatorsBySource[sourceId];
    final request = SourceEstimationRequest(
      sourceId: sourceId,
      eventId: activeEvent.eventId,
      observedAt: observedAt,
      stageName: stageName,
      maxShindo: maxShindo,
      stations: activeEvent.records,
      metadata: activeEvent.metadata,
      sensorSelection: const SensorSelection(),
    );
    if (estimator != null && estimator.supports(request)) {
      final SourceEstimatorLifecycleOwner? lifecycleOwner =
          estimator is SourceEstimatorLifecycleOwner
          ? estimator as SourceEstimatorLifecycleOwner
          : null;
      final baseSignature = _buildEstimateSignature(request);
      final signature = lifecycleOwner?.requiresEveryFrame == true
          ? '$baseSignature|estimator_frame_time:'
                '${observedAt.microsecondsSinceEpoch}'
          : baseSignature;
      if (_lastEstimateSignatureBySource[sourceId] == signature) {
        activeEvent.estimate = _lastEstimateBySource[sourceId];
      } else {
        final estimate = estimator.estimate(request);
        final clearPublishedEstimate =
            lifecycleOwner?.ownsOutputLifecycle == true &&
            activeEvent.metadata['nied_dart_hyp_clear_published_source'] ==
                true;
        if (clearPublishedEstimate) {
          activeEvent.estimate = null;
          _lastEstimateBySource.remove(sourceId);
          _phaseBestFitBySource.remove(sourceId);
          _candidateRegionBySource.remove(sourceId);
          _clearCandidateRegionMetadata(activeEvent.metadata);
          _clearEstimateQualityMetadata(activeEvent.metadata);
          _clearStabilityMetadata(activeEvent.metadata);
          _clearStabilityState(sourceId);
          activeEvent.metadata.remove('estimate_held_due_to_low_support');
        } else if (estimate != null) {
          final acceptedEstimate = lifecycleOwner?.ownsOutputLifecycle == true
              ? estimate
              : _applyTrackerEstimatePolicies(
                  sourceId: sourceId,
                  eventId: activeEvent.eventId,
                  observedAt: observedAt,
                  candidate: estimate,
                  previous: _lastEstimateBySource[sourceId],
                  metadata: activeEvent.metadata,
                );
          activeEvent.estimate = acceptedEstimate;
          if (lifecycleOwner?.ownsOutputLifecycle == true) {
            _clearCandidateRegionMetadata(activeEvent.metadata);
            _clearEstimateQualityMetadata(activeEvent.metadata);
            _clearStabilityMetadata(activeEvent.metadata);
            _clearStabilityState(sourceId);
          } else {
            _updateCandidateRegionDiagnostics(
              sourceId: sourceId,
              event: activeEvent,
              observedAt: observedAt,
              estimate: acceptedEstimate,
            );
          }
          if (identical(acceptedEstimate, estimate)) {
            final revision = activeEvent.metadata['estimate_revision'];
            activeEvent.metadata['estimate_revision'] =
                (revision is int ? revision : 0) + 1;
            activeEvent.metadata.remove('estimate_held_due_to_low_support');
            _lastEstimateBySource[sourceId] = estimate;
          }
        } else {
          activeEvent.estimate =
              _lastEstimateBySource[sourceId] ?? activeEvent.estimate;
          if (activeEvent.estimate != null) {
            activeEvent.metadata['estimate_held_due_to_low_support'] = true;
          }
        }
        _lastEstimateSignatureBySource[sourceId] = signature;
      }
    } else {
      activeEvent.estimate =
          _lastEstimateBySource[sourceId] ?? activeEvent.estimate;
      if (activeEvent.estimate != null && hasSignal) {
        activeEvent.metadata['estimate_held_due_to_low_support'] = true;
      }
      _lastEstimateSignatureBySource.remove(sourceId);
      if (!hasSignal) {
        _lastEstimateBySource.remove(sourceId);
        _phaseBestFitBySource.remove(sourceId);
        _candidateRegionBySource.remove(sourceId);
        _clearStabilityState(sourceId);
      }
    }

    if (!hasSignal) {
      activeEvent.endedAt ??= observedAt;
      final historyItems = List<SeismicActiveEvent>.from(history(sourceId))
        ..insert(0, _archivedEventView(activeEvent));
      if (historyItems.length > 20) {
        historyItems.removeRange(20, historyItems.length);
      }
      historyNotifier(sourceId).value = List.unmodifiable(historyItems);
      currentEventNotifier(sourceId).value = null;
    } else {
      currentEventNotifier(sourceId).value = _eventView(activeEvent);
    }
  }

  void _updateCandidateRegionDiagnostics({
    required String sourceId,
    required SeismicActiveEvent event,
    required DateTime observedAt,
    required SourceEstimate estimate,
  }) {
    final localSupportSnapshot = _candidateLocalSupportGate.snapshotForEstimate(
      estimate: estimate,
      memberIds: _sourceTriggerMemberIds(event.metadata),
      stationRecords: event.records,
    );
    final result = _candidateResidualGate.evaluate(estimate);
    final existingTracker = _candidateRegionBySource[sourceId];
    final initialLocalSupportSnapshot = existingTracker
        ?.pendingLocalSupportSnapshot(event.eventId);
    final localSupportResult = _candidateLocalSupportGate.evaluate(
      initialSnapshot: initialLocalSupportSnapshot,
      currentSnapshot: localSupportSnapshot,
    );
    final observation = _candidateResidualGate.observationForEstimate(
      eventId: event.eventId,
      observedAt: observedAt,
      estimate: estimate,
      localSupportSnapshot: localSupportSnapshot,
    );
    if (result == null || observation == null) {
      event.metadata.remove('candidate_region_residual_gate');
      final tracker = _candidateRegionBySource[sourceId];
      if (tracker == null || !tracker.hasPending(event.eventId)) {
        _clearCandidateRegionMetadata(event.metadata);
        return;
      }

      final decision = tracker.confirmPendingWithLocalSupport(
        eventId: event.eventId,
        observedAt: observedAt,
        result: localSupportResult,
        currentSnapshot: localSupportSnapshot,
      );
      event.metadata['candidate_region'] = decision.toDiagnostics();
      event.metadata['candidate_region_local_support_gate'] = localSupportResult
          .toDiagnostics();
      return;
    }

    final tracker =
        existingTracker ??
        _candidateRegionBySource.putIfAbsent(
          sourceId,
          SourceCandidateRegionTracker.new,
        );
    final decision = tracker.observe(observation);
    event.metadata['candidate_region'] = decision.toDiagnostics();
    event.metadata['candidate_region_residual_gate'] = result.toDiagnostics();
    event.metadata['candidate_region_local_support_gate'] = localSupportResult
        .toDiagnostics();
  }

  Iterable<String> _sourceTriggerMemberIds(Map<String, Object?> metadata) {
    final raw = metadata['source_trigger_member_ids'];
    if (raw is Iterable) return raw.whereType<String>();
    return const <String>[];
  }

  SourceEstimate _applyTrackerEstimatePolicies({
    required String sourceId,
    required String eventId,
    required DateTime observedAt,
    required SourceEstimate candidate,
    required SourceEstimate? previous,
    required Map<String, Object?> metadata,
  }) {
    final qualityHeldEstimate = _applyEstimateQualityPolicy(
      sourceId: sourceId,
      eventId: eventId,
      candidate: candidate,
      previous: previous,
      metadata: metadata,
    );
    return identical(qualityHeldEstimate, candidate)
        ? _applyStabilityPolicy(
            sourceId: sourceId,
            observedAt: observedAt,
            candidate: qualityHeldEstimate,
            previous: previous,
            metadata: metadata,
          )
        : qualityHeldEstimate;
  }

  SourceEstimate _applyEstimateQualityPolicy({
    required String sourceId,
    required String eventId,
    required SourceEstimate candidate,
    required SourceEstimate? previous,
    required Map<String, Object?> metadata,
  }) {
    if (candidate.method != 'nied_gif_hybrid_v1') {
      _clearEstimateQualityMetadata(metadata);
      return candidate;
    }
    if (previous == null) {
      _phaseBestFitHoldEstimate(
        sourceId: sourceId,
        eventId: eventId,
        candidate: candidate,
        candidatePhaseMeanResidual: _diagnosticDouble(
          candidate,
          'phase_line_mean_residual_s',
        ),
      );
      _clearEstimateQualityMetadata(metadata);
      return candidate;
    }

    final supportCount = candidate.supportingStationCount;
    final stationGeometry = candidate.diagnostics['station_geometry'];
    final searchBoundaryHit =
        candidate.diagnostics['search_boundary_hit'] == true;
    final uncertaintyP90 =
        candidate.diagnostics['horizontal_uncertainty_p90_km'];
    final uncertaintyP90Km = uncertaintyP90 is num
        ? uncertaintyP90.toDouble()
        : null;
    final candidatePhaseMeanResidual = _diagnosticDouble(
      candidate,
      'phase_line_mean_residual_s',
    );
    final previousPhaseMeanResidual = _diagnosticDouble(
      previous,
      'phase_line_mean_residual_s',
    );
    final jumpKm = _estimateDistanceKm(previous, candidate);
    final phaseBestFitHold = _phaseBestFitHoldEstimate(
      sourceId: sourceId,
      eventId: eventId,
      candidate: candidate,
      candidatePhaseMeanResidual: candidatePhaseMeanResidual,
    );

    String? holdReason;
    SourceEstimate heldEstimate = previous;
    if (phaseBestFitHold != null) {
      holdReason = 'phase_best_fit_hold';
      heldEstimate = phaseBestFitHold;
    } else if (previousPhaseMeanResidual != null &&
        candidatePhaseMeanResidual != null &&
        previousPhaseMeanResidual <= 1.4 &&
        candidatePhaseMeanResidual >= previousPhaseMeanResidual + 0.8 &&
        jumpKm >= 20) {
      holdReason = 'phase_line_regression';
    } else if (supportCount < 6) {
      holdReason = 'low_support';
    } else if (stationGeometry == 'one_sided' &&
        searchBoundaryHit &&
        uncertaintyP90Km != null &&
        uncertaintyP90Km >= 120) {
      holdReason = 'one_sided_boundary_uncertain';
    }

    if (holdReason == null) {
      _clearEstimateQualityMetadata(metadata);
      return candidate;
    }

    metadata['estimate_held_due_to_quality'] = true;
    metadata['estimate_quality_hold_reason'] = holdReason;
    metadata['quality_candidate_latitude'] = candidate.latitude;
    metadata['quality_candidate_longitude'] = candidate.longitude;
    metadata['quality_candidate_jump_km'] = jumpKm;
    metadata['quality_candidate_supporting_station_count'] = supportCount;
    if (candidatePhaseMeanResidual != null) {
      metadata['quality_candidate_phase_line_mean_residual_s'] =
          candidatePhaseMeanResidual;
    } else {
      metadata.remove('quality_candidate_phase_line_mean_residual_s');
    }
    if (previousPhaseMeanResidual != null) {
      metadata['quality_previous_phase_line_mean_residual_s'] =
          previousPhaseMeanResidual;
    } else {
      metadata.remove('quality_previous_phase_line_mean_residual_s');
    }
    if (uncertaintyP90Km != null) {
      metadata['quality_candidate_horizontal_uncertainty_p90_km'] =
          uncertaintyP90Km;
    } else {
      metadata.remove('quality_candidate_horizontal_uncertainty_p90_km');
    }
    metadata['quality_candidate_station_geometry'] = stationGeometry;
    metadata['quality_candidate_search_boundary_hit'] = searchBoundaryHit;
    return heldEstimate;
  }

  SourceEstimate? _phaseBestFitHoldEstimate({
    required String sourceId,
    required String eventId,
    required SourceEstimate candidate,
    required double? candidatePhaseMeanResidual,
  }) {
    final existing = _phaseBestFitBySource[sourceId];
    if (existing != null && existing.eventId != eventId) {
      _phaseBestFitBySource.remove(sourceId);
    }

    final best = _phaseBestFitBySource[sourceId];
    if (best != null && candidatePhaseMeanResidual != null) {
      final distanceFromBestKm = _estimateDistanceKm(best.estimate, candidate);
      if (best.phaseMeanResidualSeconds <= 1.55 &&
          candidatePhaseMeanResidual >= best.phaseMeanResidualSeconds + 0.8 &&
          distanceFromBestKm >= 20) {
        return best.estimate;
      }
    }

    if (candidatePhaseMeanResidual != null &&
        candidate.supportingStationCount >= 9 &&
        candidatePhaseMeanResidual <= 1.55 &&
        (best == null ||
            candidatePhaseMeanResidual < best.phaseMeanResidualSeconds - 0.15 ||
            (candidate.supportingStationCount >=
                    best.estimate.supportingStationCount + 6 &&
                candidatePhaseMeanResidual <=
                    best.phaseMeanResidualSeconds + 0.2))) {
      _phaseBestFitBySource[sourceId] = _PhaseBestFitEstimate(
        eventId: eventId,
        estimate: candidate,
        phaseMeanResidualSeconds: candidatePhaseMeanResidual,
      );
    }

    return null;
  }

  void _clearEstimateQualityMetadata(Map<String, Object?> metadata) {
    metadata
      ..remove('estimate_held_due_to_quality')
      ..remove('estimate_quality_hold_reason')
      ..remove('quality_candidate_latitude')
      ..remove('quality_candidate_longitude')
      ..remove('quality_candidate_jump_km')
      ..remove('quality_candidate_supporting_station_count')
      ..remove('quality_candidate_phase_line_mean_residual_s')
      ..remove('quality_previous_phase_line_mean_residual_s')
      ..remove('quality_candidate_horizontal_uncertainty_p90_km')
      ..remove('quality_candidate_station_geometry')
      ..remove('quality_candidate_search_boundary_hit');
  }

  double? _diagnosticDouble(SourceEstimate estimate, String key) {
    final value = estimate.diagnostics[key];
    return value is num ? value.toDouble() : null;
  }

  void _clearCandidateRegionMetadata(Map<String, Object?> metadata) {
    metadata
      ..remove('candidate_region')
      ..remove('candidate_region_residual_gate')
      ..remove('candidate_region_local_support_gate');
  }

  SeismicActiveEvent _eventView(SeismicActiveEvent event) {
    return SeismicActiveEvent(
      eventId: event.eventId,
      sourceId: event.sourceId,
      startedAt: event.startedAt,
      updatedAt: event.updatedAt,
      stageName: event.stageName,
      maxShindo: event.maxShindo,
      stationRecords: event.stationRecords,
      metadata: event.metadata,
      estimate: event.estimate,
      endedAt: event.endedAt,
    );
  }

  SeismicActiveEvent _archivedEventView(SeismicActiveEvent event) {
    return SeismicActiveEvent(
      eventId: event.eventId,
      sourceId: event.sourceId,
      startedAt: event.startedAt,
      updatedAt: event.updatedAt,
      stageName: event.stageName,
      maxShindo: event.maxShindo,
      stationRecords: const <String, SeismicStationEventRecord>{},
      metadata: Map<String, Object?>.unmodifiable(event.metadata),
      estimate: event.estimate,
      endedAt: event.endedAt,
    );
  }

  StationLifecycleState _stationStateFromSample(SeismicStationSample sample) {
    final detectLevel = sample.detectLevel ?? -1;
    if (sample.isTriggered && detectLevel >= 14) {
      return StationLifecycleState.strong;
    }
    if (sample.isTriggered) {
      return StationLifecycleState.triggered;
    }
    if (sample.activity > 0 || sample.ascend > 0) {
      return StationLifecycleState.rising;
    }
    return StationLifecycleState.idle;
  }

  void _appendObservation(
    SeismicStationEventRecord record,
    SeismicStationSample sample,
    DateTime receivedAt, {
    Set<String> extraQualityFlags = const {},
  }) {
    final latest = record.observationHistory.latest;
    final sampleReceivedAt = sample.receivedAt ?? receivedAt;
    var dataTime = sample.observedAt;
    var clampedNonChronological = false;
    if (latest != null && dataTime.isBefore(latest.dataTime)) {
      dataTime = sampleReceivedAt.isBefore(latest.dataTime)
          ? latest.dataTime
          : sampleReceivedAt;
      clampedNonChronological = true;
    }
    record.observationHistory.add(
      SeismicStationObservationFrame(
        dataTime: dataTime,
        receivedAt: sampleReceivedAt,
        value: sample.value,
        rawLevel: sample.rawLevel,
        detectLevel: sample.detectLevel,
        isTriggered: sample.isTriggered,
        qualityFlags: Set.unmodifiable({
          ...sample.qualityFlags,
          ...extraQualityFlags,
          if (clampedNonChronological)
            'observation_time_clamped_nonchronological',
        }),
        physicalObservations: Map.unmodifiable(sample.physicalObservations),
      ),
    );
  }

  void _updateEventPhysicalPeaks({
    required SeismicStationEventRecord record,
    required DateTime eventStartedAt,
    required SeismicStationSample sample,
  }) {
    final windowStartAt =
        record.firstTriggerAt ?? record.firstRiseAt ?? eventStartedAt;
    record.eventPhysicalPeaks.removeWhere(
      (_, observation) => observation.dataTime.isBefore(windowStartAt),
    );
    for (final observation in sample.physicalObservations.values) {
      if (!observation.isUsable ||
          observation.dataTime.isBefore(windowStartAt)) {
        continue;
      }
      if (!_hasIndependentProvenance(sample, observation.quantity)) continue;
      final previous = record.eventPhysicalPeaks[observation.quantity];
      if (previous == null || observation.value > previous.value) {
        record.eventPhysicalPeaks[observation.quantity] = observation;
      }
    }
  }

  ObservationTimeInterval _latestObservationInterval(
    SeismicStationEventRecord record,
  ) {
    final frames = record.observationHistory.frames;
    final end = frames.last.dataTime;
    final start = frames.length >= 2 ? frames[frames.length - 2].dataTime : end;
    return ObservationTimeInterval(start: start, end: end);
  }

  bool _hasIndependentProvenance(
    SeismicStationSample sample,
    StationValueType quantity,
  ) {
    return sample.provenance[quantity]?.mayBeUsedAsIndependentEvidence == true;
  }

  SourceEstimate _applyStabilityPolicy({
    required String sourceId,
    required DateTime observedAt,
    required SourceEstimate candidate,
    required SourceEstimate? previous,
    required Map<String, Object?> metadata,
  }) {
    final config = _stabilityBySource[sourceId];
    if (config == null || previous == null) {
      _firstEstimateAtBySource[sourceId] = observedAt;
      _stabilityAnchorBySource[sourceId] = candidate;
      _clearStabilityMetadata(metadata);
      return candidate;
    }

    final firstEstimateAt = _firstEstimateAtBySource.putIfAbsent(
      sourceId,
      () => observedAt,
    );
    if (observedAt.difference(firstEstimateAt) <= config.warmupDuration) {
      _stabilityAnchorBySource[sourceId] = candidate;
      _clearStabilityMetadata(metadata);
      return candidate;
    }

    final anchor = _stabilityAnchorBySource[sourceId] ?? previous;
    final jumpKm = _estimateDistanceKm(previous, candidate);
    final anchorDistanceKm = _estimateDistanceKm(anchor, candidate);
    if (jumpKm <= config.maxJumpKm &&
        anchorDistanceKm <= config.maxAnchorDistanceKm) {
      _clearStabilityMetadata(metadata);
      return candidate;
    }

    metadata['estimate_held_due_to_stability'] = true;
    metadata['stability_rejected_jump_km'] = jumpKm;
    metadata['stability_rejected_anchor_distance_km'] = anchorDistanceKm;
    metadata['stability_candidate_latitude'] = candidate.latitude;
    metadata['stability_candidate_longitude'] = candidate.longitude;
    return previous;
  }

  void _clearStabilityMetadata(Map<String, Object?> metadata) {
    metadata
      ..remove('estimate_held_due_to_stability')
      ..remove('stability_rejected_jump_km')
      ..remove('stability_rejected_anchor_distance_km')
      ..remove('stability_candidate_latitude')
      ..remove('stability_candidate_longitude');
  }

  void _clearStabilityState(String sourceId) {
    _firstEstimateAtBySource.remove(sourceId);
    _stabilityAnchorBySource.remove(sourceId);
  }

  double _estimateDistanceKm(SourceEstimate a, SourceEstimate b) {
    const earthRadiusKm = 6371.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final deltaLat = lat2 - lat1;
    final deltaLng = (b.longitude - a.longitude) * math.pi / 180;
    final sinLat = math.sin(deltaLat / 2);
    final sinLng = math.sin(deltaLng / 2);
    final h =
        sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
    return 2 * earthRadiusKm * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  String _buildEstimateSignature(SourceEstimationRequest request) {
    final records =
        request.stations
            .where((record) => record.isActiveLike)
            .toList(growable: false)
          ..sort((a, b) => a.descriptor.code.compareTo(b.descriptor.code));
    final parts = <String>[
      request.stageName,
      '${request.maxShindo}',
      '${records.length}',
    ];
    final sourceMembers = _sourceTriggerMemberIds(request.metadata).toList()
      ..sort();
    if (sourceMembers.isNotEmpty) {
      parts.add('source_members:${sourceMembers.join(',')}');
    }
    final kotoho7ReceiverFrameKey =
        request.metadata['kotoho7_receiver_frame_key'];
    if (kotoho7ReceiverFrameKey != null) {
      parts.add('kotoho7_receiver_frame:$kotoho7ReceiverFrameKey');
    }
    final niedHypocenterFrameKey =
        request.metadata['nied_hypocenter_frame_key'];
    if (niedHypocenterFrameKey != null) {
      parts.add('nied_hypocenter_frame:$niedHypocenterFrameKey');
    }
    for (final record in records) {
      parts.add(
        '${record.descriptor.code}:'
        '${record.state.name}:'
        '${record.lastRawLevel ?? -1}:'
        '${record.lastDetectLevel ?? -1}:'
        '${record.lastAscend}:'
        '${record.lastActivity.toStringAsFixed(2)}:'
        '${(record.lastValue ?? record.peakValue ?? -99).toStringAsFixed(2)}:'
        '${(record.lastPga ?? -99).toStringAsFixed(3)}:'
        '${(record.lastPgv ?? -99).toStringAsFixed(3)}:'
        '${(record.lastPgd ?? -99).toStringAsFixed(4)}',
      );
    }
    return parts.join('|');
  }
}
