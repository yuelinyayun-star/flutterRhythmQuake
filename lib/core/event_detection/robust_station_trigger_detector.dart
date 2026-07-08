import 'event_detection_models.dart';

class RobustStationTriggerConfig {
  final int historySeconds;
  final int minimumBaselineSamples;
  final double risingDelta;
  final double triggeredDelta;
  final int risingFrames;
  final int triggeredFrames;
  final int decayFrames;
  final int missingFramesToEnd;
  final int strongDetectLevel;

  const RobustStationTriggerConfig({
    this.historySeconds = 60,
    this.minimumBaselineSamples = 5,
    this.risingDelta = 2.0,
    this.triggeredDelta = 3.0,
    this.risingFrames = 2,
    this.triggeredFrames = 3,
    this.decayFrames = 3,
    this.missingFramesToEnd = 3,
    this.strongDetectLevel = 14,
  });
}

class RobustStationTriggerDetector implements StationTriggerDetector {
  @override
  final String detectorId;
  final RobustStationTriggerConfig config;
  final Map<String, _StationTriggerHistory> _histories = {};

  RobustStationTriggerDetector({
    this.detectorId = 'robust_station_trigger_v0',
    this.config = const RobustStationTriggerConfig(),
  });

  @override
  StationTriggerSnapshot update(StationObservationFrame observation) {
    final history = _histories.putIfAbsent(
      observation.stationId,
      _StationTriggerHistory.new,
    );
    final previousObservedAt = history.lastObservedAt;
    final signal = _signalValue(observation);
    final baseline = _median(history.samples.map((sample) => sample.value));
    final ascend = signal == null || history.samples.isEmpty
        ? 0
        : (signal - history.samples.last.value).round();
    final delta = signal == null || baseline == null ? 0.0 : signal - baseline;

    StationTriggerState nextState;
    final reasons = <String>{};
    if (!observation.hasUsableObservation || signal == null) {
      history.missingFrames++;
      history.risingStreak = 0;
      history.triggeredStreak = 0;
      if (history.wasActive &&
          history.missingFrames >= config.missingFramesToEnd) {
        nextState = StationTriggerState.ended;
        reasons.add('missing_observation_end');
      } else if (history.wasActive) {
        nextState = StationTriggerState.decaying;
        reasons.add('missing_observation_decay');
      } else {
        nextState = StationTriggerState.idle;
        reasons.add('missing_observation');
      }
    } else {
      history.missingFrames = 0;
      final hasBaseline =
          history.samples.length >= config.minimumBaselineSamples;
      if (!hasBaseline) {
        nextState = StationTriggerState.idle;
        reasons.add('warming_up');
      } else {
        if (delta >= config.risingDelta && ascend >= 0) {
          history.risingStreak++;
        } else {
          history.risingStreak = 0;
        }
        if (delta >= config.triggeredDelta && ascend >= 0) {
          history.triggeredStreak++;
        } else {
          history.triggeredStreak = 0;
        }

        if (observation.detectLevel != null &&
            observation.detectLevel! >= config.strongDetectLevel &&
            history.triggeredStreak >= config.triggeredFrames) {
          nextState = StationTriggerState.strong;
          reasons.add('strong_level_sustained');
        } else if (history.triggeredStreak >= config.triggeredFrames) {
          nextState = StationTriggerState.triggered;
          reasons.add('sustained_level_change');
        } else if (history.risingStreak >= config.risingFrames) {
          nextState = StationTriggerState.rising;
          reasons.add('level_rising');
        } else if (history.wasActive) {
          history.decayStreak++;
          if (history.decayStreak >= config.decayFrames) {
            nextState = StationTriggerState.ended;
            reasons.add('returned_to_baseline');
          } else {
            nextState = StationTriggerState.decaying;
            reasons.add('level_decaying');
          }
        } else {
          nextState = StationTriggerState.idle;
          reasons.add('within_baseline');
        }
      }
      if (nextState == StationTriggerState.rising ||
          nextState == StationTriggerState.triggered ||
          nextState == StationTriggerState.strong) {
        history.decayStreak = 0;
      }
    }

    final riseInterval = _updateRiseInterval(
      history,
      nextState,
      observation.observedAt,
      previousObservedAt,
    );
    final triggerInterval = _updateTriggerInterval(
      history,
      nextState,
      observation.observedAt,
      previousObservedAt,
    );

    history
      ..state = nextState
      ..lastObservedAt = observation.observedAt;
    if (signal != null) {
      history.samples.add(
        _TimedSignal(observedAt: observation.observedAt, value: signal),
      );
      _trimHistory(history, observation.observedAt);
    }
    if (nextState == StationTriggerState.ended) {
      history.clearEventState();
    }

    return StationTriggerSnapshot(
      stationId: observation.stationId,
      code: observation.code,
      sourceId: observation.sourceId,
      observedAt: observation.observedAt,
      state: nextState,
      latitude: observation.latitude,
      longitude: observation.longitude,
      intensity: observation.intensity,
      rawLevel: observation.rawLevel,
      detectLevel: observation.detectLevel,
      activity: delta > 0 ? delta : 0,
      ascend: ascend,
      firstRiseInterval: riseInterval,
      firstTriggerInterval: triggerInterval,
      qualityFlags: observation.qualityFlags,
      reasonCodes: reasons,
    );
  }

  @override
  void resetStation(String stationId) {
    _histories.remove(stationId);
  }

  @override
  void reset() {
    _histories.clear();
  }

  double? _signalValue(StationObservationFrame observation) {
    final detectLevel = observation.detectLevel;
    if (detectLevel != null) return detectLevel.toDouble();
    final rawLevel = observation.rawLevel;
    if (rawLevel != null) return rawLevel.toDouble();
    final intensity = observation.intensity;
    return intensity != null && intensity.isFinite ? intensity : null;
  }

  ObservationTimeInterval? _updateRiseInterval(
    _StationTriggerHistory history,
    StationTriggerState state,
    DateTime observedAt,
    DateTime? previousObservedAt,
  ) {
    if (state == StationTriggerState.rising ||
        state == StationTriggerState.triggered ||
        state == StationTriggerState.strong) {
      history.firstRiseInterval ??= _frameInterval(
        observedAt,
        previousObservedAt,
      );
    }
    return history.firstRiseInterval;
  }

  ObservationTimeInterval? _updateTriggerInterval(
    _StationTriggerHistory history,
    StationTriggerState state,
    DateTime observedAt,
    DateTime? previousObservedAt,
  ) {
    if (state == StationTriggerState.triggered ||
        state == StationTriggerState.strong) {
      history.firstTriggerInterval ??= _frameInterval(
        observedAt,
        previousObservedAt,
      );
    }
    return history.firstTriggerInterval;
  }

  ObservationTimeInterval _frameInterval(
    DateTime observedAt,
    DateTime? previousObservedAt,
  ) {
    final fallback = observedAt.subtract(const Duration(seconds: 1));
    return ObservationTimeInterval(
      start:
          previousObservedAt != null && previousObservedAt.isBefore(observedAt)
          ? previousObservedAt
          : fallback,
      end: observedAt,
    );
  }

  void _trimHistory(_StationTriggerHistory history, DateTime observedAt) {
    final oldest = observedAt.subtract(
      Duration(seconds: config.historySeconds),
    );
    history.samples.removeWhere((sample) => sample.observedAt.isBefore(oldest));
  }

  double? _median(Iterable<double> values) {
    final sorted = values.toList(growable: false)..sort();
    if (sorted.isEmpty) return null;
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }
}

class _StationTriggerHistory {
  final List<_TimedSignal> samples = [];
  StationTriggerState state = StationTriggerState.idle;
  DateTime? lastObservedAt;
  ObservationTimeInterval? firstRiseInterval;
  ObservationTimeInterval? firstTriggerInterval;
  int risingStreak = 0;
  int triggeredStreak = 0;
  int decayStreak = 0;
  int missingFrames = 0;

  bool get wasActive =>
      state == StationTriggerState.rising ||
      state == StationTriggerState.triggered ||
      state == StationTriggerState.strong ||
      state == StationTriggerState.decaying;

  void clearEventState() {
    firstRiseInterval = null;
    firstTriggerInterval = null;
    risingStreak = 0;
    triggeredStreak = 0;
    decayStreak = 0;
    missingFrames = 0;
  }
}

class _TimedSignal {
  final DateTime observedAt;
  final double value;

  const _TimedSignal({required this.observedAt, required this.value});
}
