import 'dart:typed_data';

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
    final baseline = _median(history);
    final ascend = signal == null || history.isEmpty
        ? 0
        : (signal - history.lastValue).round();
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
      final hasBaseline = history.length >= config.minimumBaselineSamples;
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
      history.addSample(observation.observedAt.microsecondsSinceEpoch, signal);
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
    final cutoffMicros =
        observedAt.microsecondsSinceEpoch -
        config.historySeconds * Duration.microsecondsPerSecond;
    history.removeBefore(cutoffMicros);
  }

  double? _median(_StationTriggerHistory history) {
    if (history.isEmpty) return null;

    final histogramMedian = history.boundedIntegerMedian;
    if (histogramMedian != null) return histogramMedian;

    final sorted = history.sortedValues();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }
}

class _StationTriggerHistory {
  static const int _minimumHistogramValue = -32;
  static const int _maximumHistogramValue = 63;

  // Keep exact microsecond timestamps and IEEE-754 values without a separate
  // object for every station sample. Capacity grows only
  // when needed; chronological expiry advances the head without shifting.
  Int64List _times = Int64List(8);
  Float64List _values = Float64List(8);
  int _head = 0;
  int _length = 0;
  bool _chronological = true;
  final List<int> _boundedIntegerCounts = List<int>.filled(
    _maximumHistogramValue - _minimumHistogramValue + 1,
    0,
  );
  bool _containsOnlyBoundedIntegers = true;
  StationTriggerState state = StationTriggerState.idle;
  DateTime? lastObservedAt;
  ObservationTimeInterval? firstRiseInterval;
  ObservationTimeInterval? firstTriggerInterval;
  int risingStreak = 0;
  int triggeredStreak = 0;
  int decayStreak = 0;
  int missingFrames = 0;

  bool get isEmpty => _length == 0;
  int get length => _length;
  int _index(int offset) => (_head + offset) & (_values.length - 1);
  double get lastValue => _values[_index(_length - 1)];

  Float64List sortedValues() {
    final sorted = Float64List(_length);
    for (var offset = 0; offset < _length; offset++) {
      sorted[offset] = _values[_index(offset)];
    }
    return sorted..sort();
  }

  bool get wasActive =>
      state == StationTriggerState.rising ||
      state == StationTriggerState.triggered ||
      state == StationTriggerState.strong ||
      state == StationTriggerState.decaying;

  double? get boundedIntegerMedian {
    if (!_containsOnlyBoundedIntegers || isEmpty) return null;
    final lowerRank = (_length - 1) ~/ 2;
    final upperRank = _length ~/ 2;
    int? lowerValue;
    int? upperValue;
    var seen = 0;
    for (var index = 0; index < _boundedIntegerCounts.length; index++) {
      final count = _boundedIntegerCounts[index];
      if (count == 0) continue;
      final nextSeen = seen + count;
      final value = index + _minimumHistogramValue;
      if (lowerValue == null && lowerRank < nextSeen) {
        lowerValue = value;
      }
      if (upperRank < nextSeen) {
        upperValue = value;
        break;
      }
      seen = nextSeen;
    }
    if (lowerValue == null || upperValue == null) return null;
    return (lowerValue + upperValue) / 2.0;
  }

  void addSample(int observedAtMicros, double value) {
    if (_length > 0 && observedAtMicros < _times[_index(_length - 1)]) {
      _chronological = false;
    }
    if (_length == _values.length) {
      final times = Int64List(_values.length * 2);
      final values = Float64List(_values.length * 2);
      for (var offset = 0; offset < _length; offset++) {
        final index = _index(offset);
        times[offset] = _times[index];
        values[offset] = _values[index];
      }
      _times = times;
      _values = values;
      _head = 0;
    }
    final tail = _index(_length++);
    _times[tail] = observedAtMicros;
    _values[tail] = value;
    final index = _histogramIndex(value);
    if (index == null) {
      _containsOnlyBoundedIntegers = false;
      return;
    }
    _boundedIntegerCounts[index]++;
  }

  void removeBefore(int cutoffMicros) {
    if (_chronological) {
      while (_length > 0 && _times[_head] < cutoffMicros) {
        _removeHistogramValue(_values[_head]);
        _head = (_head + 1) & (_values.length - 1);
        _length--;
      }
      return;
    }
    // The public detector accepts out-of-order observations. Preserve the
    // original stable filtering semantics until the retained window is sorted.
    var writeIndex = 0;
    int? previousMicros;
    _chronological = true;
    for (var readIndex = 0; readIndex < _length; readIndex++) {
      final index = _index(readIndex);
      final micros = _times[index];
      final value = _values[index];
      if (micros < cutoffMicros) {
        _removeHistogramValue(value);
        continue;
      }
      if (previousMicros != null && micros < previousMicros) {
        _chronological = false;
      }
      previousMicros = micros;
      final target = _index(writeIndex++);
      _times[target] = micros;
      _values[target] = value;
    }
    _length = writeIndex;
  }

  void _removeHistogramValue(double value) {
    final index = _histogramIndex(value);
    if (index != null) _boundedIntegerCounts[index]--;
  }

  int? _histogramIndex(double value) {
    if (!value.isFinite || value != value.truncateToDouble()) return null;
    final integer = value.toInt();
    if (integer < _minimumHistogramValue || integer > _maximumHistogramValue) {
      return null;
    }
    return integer - _minimumHistogramValue;
  }

  void clearEventState() {
    firstRiseInterval = null;
    firstTriggerInterval = null;
    risingStreak = 0;
    triggeredStreak = 0;
    decayStreak = 0;
    missingFrames = 0;
  }
}
