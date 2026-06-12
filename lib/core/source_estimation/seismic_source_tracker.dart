import 'package:flutter/foundation.dart';

import 'source_estimation_models.dart';
import 'source_estimator.dart';

class SeismicSourceTracker {
  final Map<String, ValueNotifier<SeismicActiveEvent?>> _currentBySource = {};
  final Map<String, ValueNotifier<List<SeismicActiveEvent>>> _historyBySource =
      {};
  final Map<String, SourceEstimator> _estimatorsBySource = {};
  final Map<String, int> _sequenceBySource = {};
  final Map<String, String> _lastEstimateSignatureBySource = {};
  final Map<String, SourceEstimate?> _lastEstimateBySource = {};

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

  void resetSource(String sourceId) {
    currentEventNotifier(sourceId).value = null;
    historyNotifier(sourceId).value = const [];
    _sequenceBySource[sourceId] = 0;
    _lastEstimateSignatureBySource.remove(sourceId);
    _lastEstimateBySource.remove(sourceId);
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
    Map<String, Object?> metadata = const {},
  }) {
    var activeEvent = currentEvent(sourceId);
    final hasSignal = stageName != 'idle';

    if (activeEvent == null && !hasSignal) {
      return;
    }

    if (activeEvent == null && hasSignal) {
      final seq = _sequenceBySource[sourceId] ?? 0;
      _sequenceBySource[sourceId] = seq + 1;
      activeEvent = SeismicActiveEvent(
        eventId: '$sourceId-${observedAt.toIso8601String()}-$seq',
        sourceId: sourceId,
        startedAt: observedAt,
        updatedAt: observedAt,
        stageName: stageName,
        maxShindo: maxShindo,
        metadata: <String, Object?>{'source_family': sourceId, ...metadata},
      );
      currentEventNotifier(sourceId).value = activeEvent;
    }

    if (activeEvent == null) {
      return;
    }

    activeEvent
      ..updatedAt = observedAt
      ..stageName = stageName
      ..maxShindo = maxShindo;
    activeEvent.metadata.addAll(metadata);

    for (final sample in samples) {
      final hasMeaningfulSample =
          sample.rawLevel != null ||
          sample.detectLevel != null ||
          sample.activity > 0 ||
          sample.ascend > 0 ||
          sample.isTriggered;

      if (!hasMeaningfulSample) {
        final existing = activeEvent.stationRecords[sample.descriptor.code];
        if (existing != null &&
            existing.isActiveLike &&
            existing.endAt == null &&
            _stationStateFromSample(sample) == StationLifecycleState.idle) {
          existing
            ..state = StationLifecycleState.ended
            ..endAt = observedAt
            ..lastObservedAt = observedAt;
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
      if (sample.observedPga != null && sample.observedPga!.isFinite) {
        record.lastPga = sample.observedPga;
      }
      if (sample.observedPgv != null && sample.observedPgv!.isFinite) {
        record.lastPgv = sample.observedPgv;
      }
      if (sample.observedPgd != null && sample.observedPgd!.isFinite) {
        record.lastPgd = sample.observedPgd;
      }

      if (sample.ascend > 0 || sample.activity > 0) {
        record.firstRiseAt ??= observedAt;
      }
      if (sample.isTriggered) {
        record.firstTriggerAt ??= observedAt;
        record.endAt = null;
      } else if (record.hasTriggered && record.endAt == null) {
        record.endAt = observedAt;
      }

      record.qualityFlags.addAll(sample.qualityFlags);
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
    );
    if (estimator != null && estimator.supports(request)) {
      final signature = _buildEstimateSignature(request);
      if (_lastEstimateSignatureBySource[sourceId] == signature) {
        activeEvent.estimate = _lastEstimateBySource[sourceId];
      } else {
        final estimate = estimator.estimate(request);
        activeEvent.estimate = estimate;
        _lastEstimateSignatureBySource[sourceId] = signature;
        _lastEstimateBySource[sourceId] = estimate;
      }
    } else {
      activeEvent.estimate = null;
      _lastEstimateSignatureBySource.remove(sourceId);
      _lastEstimateBySource.remove(sourceId);
    }

    if (!hasSignal) {
      activeEvent.endedAt ??= observedAt;
      final historyItems = List<SeismicActiveEvent>.from(history(sourceId))
        ..insert(0, activeEvent);
      if (historyItems.length > 20) {
        historyItems.removeRange(20, historyItems.length);
      }
      historyNotifier(sourceId).value = List.unmodifiable(historyItems);
      currentEventNotifier(sourceId).value = null;
    } else {
      currentEventNotifier(sourceId).value = activeEvent;
    }
  }

  StationLifecycleState _stationStateFromSample(SeismicStationSample sample) {
    final detectLevel = sample.detectLevel ?? -1;
    if (sample.isTriggered && detectLevel >= 14) {
      return StationLifecycleState.strong;
    }
    if (sample.isTriggered) {
      return StationLifecycleState.triggered;
    }
    if (sample.activity > 0 || sample.ascend > 0 || detectLevel >= 0) {
      return StationLifecycleState.rising;
    }
    return StationLifecycleState.idle;
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
