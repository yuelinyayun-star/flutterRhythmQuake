import 'dart:math' as math;

import 'source_estimation_models.dart';

abstract class SourceEstimator {
  String get methodId;

  bool supports(SourceEstimationRequest request);

  SourceEstimate? estimate(SourceEstimationRequest request);
}

class WeightedCentroidSourceEstimator implements SourceEstimator {
  const WeightedCentroidSourceEstimator();

  @override
  String get methodId => 'weighted_centroid_baseline';

  @override
  bool supports(SourceEstimationRequest request) =>
      request.stations.where((s) => s.isActiveLike).length >= 2;

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final usable = request.stations
        .where((record) {
          return record.isActiveLike &&
              record.lastValue != null &&
              record.lastValue!.isFinite;
        })
        .toList(growable: false);
    if (usable.length < 2) {
      return null;
    }

    double weightedLat = 0;
    double weightedLng = 0;
    double weightSum = 0;
    DateTime? earliestTrigger;

    for (final record in usable) {
      final valueWeight = math.max(record.lastValue ?? 0, -2.5) + 3.5;
      final activityWeight = math.max(record.lastActivity, 0) / 8.0;
      final triggerBonus = record.hasTriggered ? 1.0 : 0.35;
      final weight = math.max(0.2, valueWeight + activityWeight) * triggerBonus;
      weightedLat += record.descriptor.coordinate.latitude * weight;
      weightedLng += record.descriptor.coordinate.longitude * weight;
      weightSum += weight;
      final trigger = record.firstTriggerAt ?? record.firstRiseAt;
      if (trigger != null &&
          (earliestTrigger == null || trigger.isBefore(earliestTrigger))) {
        earliestTrigger = trigger;
      }
    }

    if (weightSum <= 0) {
      return null;
    }

    final latitude = weightedLat / weightSum;
    final longitude = weightedLng / weightSum;
    final confidence = math.min(0.85, 0.25 + usable.length * 0.06);

    return SourceEstimate(
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: usable.length,
      originTime: earliestTrigger,
      diagnostics: {
        'weight_sum': weightSum,
        'usable_station_count': usable.length,
        'event_stage': request.stageName,
      },
    );
  }
}

class TriggerTimeGridSearchEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;

  const TriggerTimeGridSearchEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 3.8,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
  });

  @override
  String get methodId => 'trigger_time_grid_v2';

  @override
  bool supports(SourceEstimationRequest request) {
    final triggeredCount = _usableTimingRecords(request).length;
    if (triggeredCount >= 3) {
      return true;
    }
    return fallback?.supports(request) ?? false;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final usable = _usableTimingRecords(request);
    if (usable.length < 3) {
      return fallback?.estimate(request);
    }

    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);

    _Candidate best = _Candidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      score: double.infinity,
    );

    best = _searchGrid(
      usable,
      earliestObserved,
      minLat: bounds.$1,
      maxLat: bounds.$2,
      minLng: bounds.$3,
      maxLng: bounds.$4,
      stepDeg: coarseStepDeg,
      currentBest: best,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - coarseStepDeg * 1.5,
      maxLat: best.latitude + coarseStepDeg * 1.5,
      minLng: best.longitude - coarseStepDeg * 1.5,
      maxLng: best.longitude + coarseStepDeg * 1.5,
      stepDeg: fineStepDeg,
      currentBest: best,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - fineStepDeg * 1.5,
      maxLat: best.latitude + fineStepDeg * 1.5,
      minLng: best.longitude - fineStepDeg * 1.5,
      maxLng: best.longitude + fineStepDeg * 1.5,
      stepDeg: refineStepDeg,
      currentBest: best,
    );

    if (!best.score.isFinite) {
      return fallback?.estimate(request);
    }

    final supportCount = usable.length;
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore);
    final confidence =
        (0.15 +
                timeFit * 0.45 +
                rankFit * 0.20 +
                math.min(0.20, supportCount * 0.025))
            .clamp(0.0, 0.95);

    final originTime = earliestObserved.subtract(
      Duration(
        milliseconds:
            (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                .round(),
      ),
    );

    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: supportCount,
      originTime: originTime,
      diagnostics: {
        'wave_speed_kmps': assumedWaveSpeedKmPerSec,
        'time_score': best.timeScore,
        'rank_score': best.rankScore,
        'final_score': best.score,
        'reference_distance_km': best.referenceDistanceKm,
        'usable_station_count': supportCount,
        'search_bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _Candidate _searchGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved, {
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double stepDeg,
    required _Candidate currentBest,
  }) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        final scored = _scoreCandidate(
          usable,
          earliestObserved,
          lat,
          lng,
          assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
        );
        if (scored.score < best.score) {
          best = scored;
        }
      }
    }
    return best;
  }
}

class NiedGifHybridSourceEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;

  const NiedGifHybridSourceEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 3.8,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
  });

  @override
  String get methodId => 'nied_gif_hybrid_v1';

  bool _isGifRequest(SourceEstimationRequest request) {
    return request.metadata['nied_input_kind'] == 'gif';
  }

  @override
  bool supports(SourceEstimationRequest request) {
    if (!_isGifRequest(request)) return false;
    final triggeredCount = _usableTimingRecords(request).length;
    if (triggeredCount >= 3) return true;
    return fallback?.supports(request) ?? false;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    if (!_isGifRequest(request)) return null;
    final usable = _usableTimingRecords(request);
    if (usable.length < 3) {
      return fallback?.estimate(request);
    }

    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);

    _Candidate best = _Candidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      score: double.infinity,
    );

    best = _searchGifGrid(
      usable,
      earliestObserved,
      weightedCenter: weightedCenter,
      minLat: bounds.$1,
      maxLat: bounds.$2,
      minLng: bounds.$3,
      maxLng: bounds.$4,
      stepDeg: coarseStepDeg,
      currentBest: best,
    );
    best = _searchGifGrid(
      usable,
      earliestObserved,
      weightedCenter: weightedCenter,
      minLat: best.latitude - coarseStepDeg * 1.5,
      maxLat: best.latitude + coarseStepDeg * 1.5,
      minLng: best.longitude - coarseStepDeg * 1.5,
      maxLng: best.longitude + coarseStepDeg * 1.5,
      stepDeg: fineStepDeg,
      currentBest: best,
    );
    best = _searchGifGrid(
      usable,
      earliestObserved,
      weightedCenter: weightedCenter,
      minLat: best.latitude - fineStepDeg * 1.5,
      maxLat: best.latitude + fineStepDeg * 1.5,
      minLng: best.longitude - fineStepDeg * 1.5,
      maxLng: best.longitude + fineStepDeg * 1.5,
      stepDeg: refineStepDeg,
      currentBest: best,
    );

    if (!best.score.isFinite) {
      return fallback?.estimate(request);
    }

    final supportCount = usable.length;
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore / math.max(1, supportCount));
    final confidence =
        (0.18 +
                timeFit * 0.42 +
                rankFit * 0.28 +
                math.min(0.18, supportCount * 0.02))
            .clamp(0.0, 0.95);

    final originTime = earliestObserved.subtract(
      Duration(
        milliseconds:
            (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                .round(),
      ),
    );

    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: supportCount,
      originTime: originTime,
      diagnostics: {
        'wave_speed_kmps': assumedWaveSpeedKmPerSec,
        'time_score': best.timeScore,
        'rank_score': best.rankScore,
        'final_score': best.score,
        'reference_distance_km': best.referenceDistanceKm,
        'usable_station_count': supportCount,
        'search_bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _Candidate _searchGifGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved, {
    required (double, double) weightedCenter,
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double stepDeg,
    required _Candidate currentBest,
  }) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        final scored = _scoreNiedGifCandidate(
          usable,
          earliestObserved,
          lat,
          lng,
          weightedCenter: weightedCenter,
          assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
        );
        if (scored.score < best.score) {
          best = scored;
        }
      }
    }
    return best;
  }
}

class TriggerTimeDepthGridSearchEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;
  final List<double> depthCandidatesKm;

  const TriggerTimeDepthGridSearchEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 4.0,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
    this.depthCandidatesKm = const [0, 10, 20, 30, 40, 60, 80, 100, 150, 200],
  });

  @override
  String get methodId => 'trigger_time_depth_grid_v3';

  @override
  bool supports(SourceEstimationRequest request) {
    final triggeredCount = _usableTimingRecords(request).length;
    if (triggeredCount >= 4) {
      return true;
    }
    return fallback?.supports(request) ?? false;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final usable = _usableTimingRecords(request);
    if (usable.length < 4) {
      return fallback?.estimate(request);
    }

    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);

    _DepthCandidate best = _DepthCandidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      depthKm: depthCandidatesKm.first,
      score: double.infinity,
    );

    best = _searchDepthGrid(
      usable,
      earliestObserved,
      minLat: bounds.$1,
      maxLat: bounds.$2,
      minLng: bounds.$3,
      maxLng: bounds.$4,
      stepDeg: coarseStepDeg,
      currentBest: best,
    );
    best = _searchDepthGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - coarseStepDeg * 1.5,
      maxLat: best.latitude + coarseStepDeg * 1.5,
      minLng: best.longitude - coarseStepDeg * 1.5,
      maxLng: best.longitude + coarseStepDeg * 1.5,
      stepDeg: fineStepDeg,
      currentBest: best,
    );
    best = _searchDepthGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - fineStepDeg * 1.5,
      maxLat: best.latitude + fineStepDeg * 1.5,
      minLng: best.longitude - fineStepDeg * 1.5,
      maxLng: best.longitude + fineStepDeg * 1.5,
      stepDeg: refineStepDeg,
      currentBest: best,
    );

    if (!best.score.isFinite) {
      return fallback?.estimate(request);
    }

    final supportCount = usable.length;
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore);
    final depthPenalty = math.min(0.18, best.depthKm / 1000.0);
    final confidence =
        (0.18 +
                timeFit * 0.42 +
                rankFit * 0.18 +
                math.min(0.22, supportCount * 0.025) -
                depthPenalty)
            .clamp(0.0, 0.95);

    final originTime = earliestObserved.subtract(
      Duration(
        milliseconds:
            (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                .round(),
      ),
    );

    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      depthKm: best.depthKm,
      confidence: confidence,
      method: methodId,
      supportingStationCount: supportCount,
      originTime: originTime,
      diagnostics: {
        'wave_speed_kmps': assumedWaveSpeedKmPerSec,
        'time_score': best.timeScore,
        'rank_score': best.rankScore,
        'final_score': best.score,
        'reference_distance_km': best.referenceDistanceKm,
        'best_depth_km': best.depthKm,
        'depth_candidates_km': depthCandidatesKm,
        'usable_station_count': supportCount,
        'search_bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _DepthCandidate _searchDepthGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved, {
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double stepDeg,
    required _DepthCandidate currentBest,
  }) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        for (final depthKm in depthCandidatesKm) {
          final scored = _scoreDepthCandidate(
            usable,
            earliestObserved,
            lat,
            lng,
            depthKm,
            assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
          );
          if (scored.score < best.score) {
            best = scored;
          }
        }
      }
    }
    return best;
  }
}

List<SeismicStationEventRecord> _usableTimingRecords(
  SourceEstimationRequest request,
) {
  final usable = request.stations
      .where((record) {
        return record.isActiveLike &&
            (record.firstTriggerAt ?? record.firstRiseAt) != null;
      })
      .toList(growable: false);
  if (usable.length <= 24) {
    return usable;
  }

  final earliest = List<SeismicStationEventRecord>.from(usable)
    ..sort((a, b) {
      final aTime = a.firstTriggerAt ?? a.firstRiseAt!;
      final bTime = b.firstTriggerAt ?? b.firstRiseAt!;
      final timeCmp = aTime.compareTo(bTime);
      if (timeCmp != 0) return timeCmp;
      return a.descriptor.code.compareTo(b.descriptor.code);
    });
  final strongest = List<SeismicStationEventRecord>.from(usable)
    ..sort((a, b) {
      final bValue = b.lastValue ?? b.peakValue ?? -99;
      final aValue = a.lastValue ?? a.peakValue ?? -99;
      final valueCmp = bValue.compareTo(aValue);
      if (valueCmp != 0) return valueCmp;
      return a.descriptor.code.compareTo(b.descriptor.code);
    });

  final selected = <String, SeismicStationEventRecord>{};
  for (final record in earliest.take(16)) {
    selected[record.descriptor.code] = record;
  }
  for (final record in strongest.take(16)) {
    selected[record.descriptor.code] = record;
  }

  final result = selected.values.toList(growable: false)
    ..sort((a, b) {
      final aTime = a.firstTriggerAt ?? a.firstRiseAt!;
      final bTime = b.firstTriggerAt ?? b.firstRiseAt!;
      final timeCmp = aTime.compareTo(bTime);
      if (timeCmp != 0) return timeCmp;
      return a.descriptor.code.compareTo(b.descriptor.code);
    });
  return result.take(24).toList(growable: false);
}

DateTime _earliestObserved(List<SeismicStationEventRecord> usable) {
  return usable
      .map((record) => record.firstTriggerAt ?? record.firstRiseAt!)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

(double, double, double, double) _searchBounds(
  List<SeismicStationEventRecord> usable, {
  required double bboxPaddingDeg,
}) {
  final latitudes = usable.map((s) => s.descriptor.coordinate.latitude);
  final longitudes = usable.map((s) => s.descriptor.coordinate.longitude);
  return (
    latitudes.reduce(math.min) - bboxPaddingDeg,
    latitudes.reduce(math.max) + bboxPaddingDeg,
    longitudes.reduce(math.min) - bboxPaddingDeg,
    longitudes.reduce(math.max) + bboxPaddingDeg,
  );
}

(double, double) _weightedCenter(List<SeismicStationEventRecord> usable) {
  double latSum = 0;
  double lngSum = 0;
  double weightSum = 0;
  for (final record in usable) {
    final weight = math.max(
      0.3,
      (record.lastValue ?? record.peakValue ?? -2.5) + 3.5,
    );
    latSum += record.descriptor.coordinate.latitude * weight;
    lngSum += record.descriptor.coordinate.longitude * weight;
    weightSum += weight;
  }
  return (latSum / weightSum, lngSum / weightSum);
}

List<Map<String, Object?>> _topTimingPicks(
  List<SeismicStationEventRecord> usable, {
  required DateTime earliestObserved,
  int limit = 6,
}) {
  final picks = usable
      .map((record) {
        final observedAt = record.firstTriggerAt ?? record.firstRiseAt!;
        return <String, Object?>{
          'code': record.descriptor.code,
          'delay_s':
              observedAt.difference(earliestObserved).inMilliseconds / 1000.0,
          'value': record.lastValue ?? record.peakValue,
          'pga': record.lastPga,
          'pgv': record.lastPgv,
          'pgd': record.lastPgd,
          'activity': record.lastActivity,
          'ascend': record.lastAscend,
        };
      })
      .toList(growable: false);
  picks.sort((a, b) {
    final aDelay = (a['delay_s'] as double?) ?? double.infinity;
    final bDelay = (b['delay_s'] as double?) ?? double.infinity;
    return aDelay.compareTo(bDelay);
  });
  return picks.take(limit).toList(growable: false);
}

_Candidate _scoreCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng, {
  required double assumedWaveSpeedKmPerSec,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances = <double>[];
  final values = <double>[];

  for (final record in usable) {
    final obs = record.firstTriggerAt ?? record.firstRiseAt!;
    final delaySec = obs.difference(earliestObserved).inMilliseconds / 1000.0;
    final distanceKm = _haversineKm(
      lat,
      lng,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    observedSeconds.add(delaySec);
    distances.add(distanceKm);
    values.add(record.lastValue ?? record.peakValue ?? -3.0);
  }

  final minDistance = distances.reduce(math.min);
  for (final distanceKm in distances) {
    predictedSeconds.add((distanceKm - minDistance) / assumedWaveSpeedKmPerSec);
  }

  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final rankScore = _rankScore(distances, values);
  final nearestStrongPenalty = _nearestStrongPenalty(distances, values);
  final finalScore = timeScore + rankScore + nearestStrongPenalty;

  return _Candidate(
    latitude: lat,
    longitude: lng,
    score: finalScore,
    timeScore: timeScore,
    rankScore: rankScore + nearestStrongPenalty,
    referenceDistanceKm: minDistance,
  );
}

_Candidate _scoreNiedGifCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng, {
  required (double, double) weightedCenter,
  required double assumedWaveSpeedKmPerSec,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances = <double>[];
  final shindoValues = <double>[];
  final pgaValues = <double?>[];
  final pgvValues = <double?>[];
  final pgdValues = <double?>[];

  for (final record in usable) {
    final obs = record.firstTriggerAt ?? record.firstRiseAt!;
    final delaySec = obs.difference(earliestObserved).inMilliseconds / 1000.0;
    final distanceKm = _haversineKm(
      lat,
      lng,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    observedSeconds.add(delaySec);
    distances.add(distanceKm);
    shindoValues.add(record.lastValue ?? record.peakValue ?? -3.0);
    pgaValues.add(record.lastPga);
    pgvValues.add(record.lastPgv);
    pgdValues.add(record.lastPgd);
  }

  final minDistance = distances.reduce(math.min);
  for (final distanceKm in distances) {
    predictedSeconds.add((distanceKm - minDistance) / assumedWaveSpeedKmPerSec);
  }

  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final shindoRank = _rankScore(distances, shindoValues);
  final pgaRank = _rankScoreOptional(distances, pgaValues);
  final pgvRank = _rankScoreOptional(distances, pgvValues);
  final pgdRank = _rankScoreOptional(distances, pgdValues);
  final nearestPenalty = _nearestStrongPenalty(distances, shindoValues);
  final centerPenalty =
      _haversineKm(lat, lng, weightedCenter.$1, weightedCenter.$2) * 0.015;

  final rankScore =
      shindoRank +
      pgaRank * 0.50 +
      pgvRank * 0.35 +
      pgdRank * 0.20 +
      nearestPenalty +
      centerPenalty;
  final finalScore = timeScore * 1.15 + rankScore;

  return _Candidate(
    latitude: lat,
    longitude: lng,
    score: finalScore,
    timeScore: timeScore,
    rankScore: rankScore,
    referenceDistanceKm: minDistance,
  );
}

_DepthCandidate _scoreDepthCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng,
  double depthKm, {
  required double assumedWaveSpeedKmPerSec,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances3d = <double>[];
  final surfaceDistances = <double>[];
  final values = <double>[];

  for (final record in usable) {
    final obs = record.firstTriggerAt ?? record.firstRiseAt!;
    final delaySec = obs.difference(earliestObserved).inMilliseconds / 1000.0;
    final surfaceDistanceKm = _haversineKm(
      lat,
      lng,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final distance3d = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    observedSeconds.add(delaySec);
    surfaceDistances.add(surfaceDistanceKm);
    distances3d.add(distance3d);
    values.add(record.lastValue ?? record.peakValue ?? -3.0);
  }

  final minDistance = distances3d.reduce(math.min);
  for (final distanceKm in distances3d) {
    predictedSeconds.add((distanceKm - minDistance) / assumedWaveSpeedKmPerSec);
  }

  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final rankScore = _rankScore(surfaceDistances, values);
  final nearestStrongPenalty = _nearestStrongPenalty(surfaceDistances, values);
  final depthRegularization = depthKm * 0.0025;
  final finalScore =
      timeScore + rankScore + nearestStrongPenalty + depthRegularization;

  return _DepthCandidate(
    latitude: lat,
    longitude: lng,
    depthKm: depthKm,
    score: finalScore,
    timeScore: timeScore,
    rankScore: rankScore + nearestStrongPenalty + depthRegularization,
    referenceDistanceKm: minDistance,
  );
}

double _timeResidualScore(List<double> observed, List<double> predicted) {
  double score = 0;
  for (var i = 0; i < observed.length; i++) {
    final residual = observed[i] - predicted[i];
    score += residual * residual;
  }
  return score;
}

double _rankScore(List<double> distances, List<double> values) {
  double rankScore = 0;
  for (var i = 0; i < values.length; i++) {
    for (var j = i + 1; j < values.length; j++) {
      final valueDiff = values[i] - values[j];
      if (valueDiff.abs() < 0.15) continue;
      final distDiff = distances[i] - distances[j];
      if (valueDiff > 0 && distDiff > 0) {
        rankScore += math.min(2.0, valueDiff.abs()) * 0.35;
      } else if (valueDiff < 0 && distDiff < 0) {
        rankScore += math.min(2.0, valueDiff.abs()) * 0.35;
      }
    }
  }
  return rankScore;
}

double _rankScoreOptional(List<double> distances, List<double?> values) {
  double rankScore = 0;
  for (var i = 0; i < values.length; i++) {
    final vi = values[i];
    if (vi == null || !vi.isFinite) continue;
    for (var j = i + 1; j < values.length; j++) {
      final vj = values[j];
      if (vj == null || !vj.isFinite) continue;
      final valueDiff = vi - vj;
      if (valueDiff.abs() < 0.02) continue;
      final distDiff = distances[i] - distances[j];
      if (valueDiff > 0 && distDiff > 0) {
        rankScore += math.min(2.0, valueDiff.abs()) * 0.30;
      } else if (valueDiff < 0 && distDiff < 0) {
        rankScore += math.min(2.0, valueDiff.abs()) * 0.30;
      }
    }
  }
  return rankScore;
}

double _nearestStrongPenalty(List<double> distances, List<double> values) {
  var strongestIndex = 0;
  var strongestValue = values.first;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > strongestValue) {
      strongestValue = values[i];
      strongestIndex = i;
    }
  }
  final nearestDistance = distances.reduce(math.min);
  final strongestDistance = distances[strongestIndex];
  return math.max(0, strongestDistance - nearestDistance) * 0.08;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * math.pi / 180.0;

class _Candidate {
  final double latitude;
  final double longitude;
  final double score;
  final double timeScore;
  final double rankScore;
  final double referenceDistanceKm;

  const _Candidate({
    required this.latitude,
    required this.longitude,
    required this.score,
    this.timeScore = double.infinity,
    this.rankScore = double.infinity,
    this.referenceDistanceKm = 0,
  });
}

class _DepthCandidate extends _Candidate {
  final double depthKm;

  const _DepthCandidate({
    required super.latitude,
    required super.longitude,
    required this.depthKm,
    required super.score,
    super.timeScore,
    super.rankScore,
    super.referenceDistanceKm,
  });
}
