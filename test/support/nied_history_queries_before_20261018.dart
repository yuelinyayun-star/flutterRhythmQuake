// Frozen verbatim query bodies from the pre-migration estimator (2026-10-18).
import 'dart:math' as math;
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

class BeforeNiedHistoryQueries {
  double change(SeismicStationEventRecord record, DateTime? now, int seconds) =>
      _kotoho7HistoryChangeValue(
        record,
        observedAt: now,
        targetSeconds: seconds.toDouble(),
      );
  double immediate(SeismicStationEventRecord record, DateTime now) =>
      _kotoho7ImmediateChangeSpeedValue(record, observedAt: now);
  bool fast(SeismicStationEventRecord record, DateTime now, int digit) =>
      _kotoho7ScratchFastRiseEnergyExceedsLimit(
        record,
        observedAt: now,
        upwardLimitDigit: digit,
      );
  double? pretrigger(
    SeismicStationEventRecord record,
    DateTime earliest,
    DateTime fallback,
  ) => _hypPretriggerCacheSeconds(
    record,
    earliestObserved: earliest,
    fallbackObservedAt: fallback,
  );
  double _kotoho7HistoryChangeValue(
    SeismicStationEventRecord record, {
    DateTime? observedAt,
    required double targetSeconds,
  }) {
    final frames = record.observationHistory.frames;
    if (frames.isNotEmpty) {
      final latest = frames.last;
      if (observedAt != null) {
        final ageSeconds =
            observedAt.difference(latest.dataTime).inMilliseconds.abs() /
            1000.0;
        if (ageSeconds > 1.5) return 0.0;
      }
      if (latest.isMissing || latest.isStale || !latest.isDecodable) {
        return 0.0;
      }
      final currentValue = _kotoho7FrameConvertedShindo(latest);
      if (currentValue == null) return 0.0;
      final targetTime = latest.dataTime.subtract(
        Duration(milliseconds: (targetSeconds * 1000).round()),
      );
      SeismicStationObservationFrame? reference;
      SeismicStationObservationFrame? oldestDecodable;
      for (var index = frames.length - 2; index >= 0; index--) {
        final candidate = frames[index];
        if (!candidate.isMissing &&
            !candidate.isStale &&
            candidate.isDecodable) {
          oldestDecodable = candidate;
          if (!candidate.dataTime.isAfter(targetTime)) {
            reference = candidate;
            break;
          }
        }
      }
      reference ??= oldestDecodable;
      if (reference == null) return record.lastAscend.toDouble();
      final referenceValue = _kotoho7FrameConvertedShindo(reference);
      if (referenceValue == null) return 0.0;
      return currentValue - referenceValue;
    }
    return record.lastAscend.toDouble();
  }

  double _kotoho7ImmediateChangeSpeedValue(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    final frames = record.observationHistory.frames;
    if (frames.length >= 2) {
      final latest = frames.last;
      final ageSeconds =
          observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
      if (ageSeconds > 1.5 ||
          latest.isMissing ||
          latest.isStale ||
          !latest.isDecodable) {
        return 0.0;
      }
      final currentValue = _kotoho7FrameConvertedShindo(latest);
      if (currentValue == null) return 0.0;
      for (var index = frames.length - 2; index >= 0; index--) {
        final previous = frames[index];
        if (previous.isMissing || previous.isStale || !previous.isDecodable) {
          continue;
        }
        final previousValue = _kotoho7FrameConvertedShindo(previous);
        if (previousValue == null) return 0.0;
        return currentValue - previousValue;
      }
    }
    return record.lastAscend.toDouble();
  }

  bool _kotoho7ScratchFastRiseEnergyExceedsLimit(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required int upwardLimitDigit,
  }) {
    final slots = _kotoho7ScratchRecentHistoryConvertedSlots(
      record,
      observedAt: observedAt,
      count: 3,
    );
    if (slots.length < 3) return false;
    final limit = upwardLimitDigit == 0
        ? 75.0
        : upwardLimitDigit * upwardLimitDigit.toDouble();
    final currentEnergy = math.pow(3.0 + slots[0], 2).toDouble();
    final previousEnergy = math.pow(3.0 + slots[2], 2).toDouble();
    return limit < currentEnergy - previousEnergy;
  }

  List<double> _kotoho7ScratchRecentHistoryConvertedSlots(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required int count,
  }) {
    final frames = record.observationHistory.frames;
    if (frames.isEmpty) return const <double>[];
    final slots = <double>[];
    for (var index = frames.length - 1; index >= 0; index--) {
      final frame = frames[index];
      if (frame.dataTime.isAfter(
        observedAt.add(const Duration(milliseconds: 1500)),
      )) {
        continue;
      }
      final value = _kotoho7FrameConvertedShindo(frame);
      if (value == null) continue;
      slots.add(value);
      if (slots.length >= count) break;
    }
    return slots;
  }

  double? _kotoho7FrameConvertedShindo(SeismicStationObservationFrame frame) {
    final value = frame.value;
    if (value != null && value.isFinite) return value;
    final kaLevel = frame.rawLevel ?? frame.detectLevel;
    return kaLevel == null
        ? null
        : JpShindoScale.rawShindoFromKanameishiLevel(kaLevel);
  }
}

double? _hypPretriggerCacheSeconds(
  SeismicStationEventRecord record, {
  required DateTime earliestObserved,
  required DateTime fallbackObservedAt,
}) {
  double? cacheSeconds;
  double? previousSignal;
  int? previousDetectLevel;
  for (final frame in record.observationHistory.frames) {
    if (frame.dataTime.isAfter(fallbackObservedAt)) break;
    if (frame.isMissing || frame.isStale || !frame.isDecodable) continue;
    final signal = _hypFrameSignal(frame);
    final activeLike = _hypFrameActiveLike(frame);
    if (!activeLike) {
      cacheSeconds = null;
      previousSignal = signal ?? previousSignal;
      previousDetectLevel = frame.detectLevel ?? previousDetectLevel;
      continue;
    }
    final risingBySignal =
        signal != null &&
        (previousSignal == null || signal > previousSignal + 0.01);
    final detectLevel = frame.detectLevel;
    final risingByDetectLevel =
        detectLevel != null &&
        (previousDetectLevel == null || detectLevel > previousDetectLevel);
    final rising = risingBySignal || risingByDetectLevel || frame.isTriggered;
    if (rising) {
      cacheSeconds ??= _secondsSince(frame.dataTime, earliestObserved);
    } else {
      cacheSeconds = null;
    }
    previousSignal = signal ?? previousSignal;
    previousDetectLevel = detectLevel ?? previousDetectLevel;
  }
  if (cacheSeconds != null) {
    final fallbackSeconds = _secondsSince(fallbackObservedAt, earliestObserved);
    if (fallbackSeconds - cacheSeconds <= 20.0) return cacheSeconds;
  }
  return null;
}

double? _hypFrameSignal(SeismicStationObservationFrame frame) {
  final value = frame.value;
  if (value != null && value.isFinite) return value;
  final kaLevel = frame.rawLevel ?? frame.detectLevel;
  if (kaLevel != null) {
    return JpShindoScale.rawShindoFromKanameishiLevel(kaLevel);
  }
  return null;
}

bool _hypFrameActiveLike(SeismicStationObservationFrame frame) {
  final signal = _hypFrameSignal(frame);
  return frame.isTriggered ||
      (frame.detectLevel != null && frame.detectLevel! > 0) ||
      (signal != null && signal > 0.0);
}

double _secondsSince(DateTime value, DateTime origin) =>
    value.difference(origin).inMilliseconds / 1000.0;
