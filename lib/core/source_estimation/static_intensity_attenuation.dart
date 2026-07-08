import 'dart:math' as math;

import '../calculator.dart';
import '../utils/jma_seis_int_loc.dart';

class StaticIntensityStation {
  final String stationId;
  final double latitude;
  final double longitude;
  final double intensity;

  const StaticIntensityStation({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.intensity,
  });
}

class StaticIntensityEvent {
  final String eventId;
  final String split;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double? magnitude;
  final List<StaticIntensityStation> stations;
  final List<StaticIntensityVariant> variants;

  const StaticIntensityEvent({
    required this.eventId,
    required this.split,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    this.magnitude,
    required this.stations,
    required this.variants,
  });

  factory StaticIntensityEvent.fromJson(Map<String, Object?> json) {
    final truth = json['truth']! as Map<String, Object?>;
    return StaticIntensityEvent(
      eventId: json['eventId']! as String,
      split: json['split']! as String,
      latitude: (truth['latitude']! as num).toDouble(),
      longitude: (truth['longitude']! as num).toDouble(),
      depthKm: (truth['depthKm']! as num).toDouble(),
      magnitude: (truth['magnitude'] as num?)?.toDouble(),
      stations: [
        for (final raw in json['stations']! as List<Object?>)
          _stationFromJson(raw! as Map<String, Object?>),
      ],
      variants: [
        for (final raw in json['variants']! as List<Object?>)
          StaticIntensityVariant.fromJson(raw! as Map<String, Object?>),
      ],
    );
  }

  static StaticIntensityStation _stationFromJson(Map<String, Object?> json) {
    return StaticIntensityStation(
      stationId: json['stationId']! as String,
      latitude: (json['latitude']! as num).toDouble(),
      longitude: (json['longitude']! as num).toDouble(),
      intensity: (json['instrumentalIntensity']! as num).toDouble(),
    );
  }
}

class StaticIntensityVariant {
  final String variantId;
  final double maskRate;
  final List<String> retainedStationIds;

  const StaticIntensityVariant({
    required this.variantId,
    required this.maskRate,
    required this.retainedStationIds,
  });

  factory StaticIntensityVariant.fromJson(Map<String, Object?> json) {
    return StaticIntensityVariant(
      variantId: json['variantId']! as String,
      maskRate: (json['requestedMaskRate']! as num).toDouble(),
      retainedStationIds: (json['retainedStationIds']! as List<Object?>)
          .cast<String>(),
    );
  }
}

class StaticAttenuationModel {
  final String modelId;
  final double logDistanceCoefficient;
  final double linearDistanceCoefficient;
  final double nearDistanceKm;
  final double huberDelta;
  final double residualScale;
  final double centroidPenaltyPerKm;
  final List<double> depthClassesKm;

  const StaticAttenuationModel({
    this.modelId = 'static_intensity_attenuation_v1',
    required this.logDistanceCoefficient,
    required this.linearDistanceCoefficient,
    required this.nearDistanceKm,
    required this.huberDelta,
    required this.residualScale,
    this.centroidPenaltyPerKm = 0,
    this.depthClassesKm = const [10, 50, 150],
  });

  StaticAttenuationModel copyWith({double? centroidPenaltyPerKm}) {
    return StaticAttenuationModel(
      modelId: modelId,
      logDistanceCoefficient: logDistanceCoefficient,
      linearDistanceCoefficient: linearDistanceCoefficient,
      nearDistanceKm: nearDistanceKm,
      huberDelta: huberDelta,
      residualScale: residualScale,
      centroidPenaltyPerKm: centroidPenaltyPerKm ?? this.centroidPenaltyPerKm,
      depthClassesKm: depthClassesKm,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'modelId': modelId,
    'formula': 'I_hat=sourceScale-c*log10(R+r0)-d*R; R=hypocentralDistanceKm',
    'logDistanceCoefficient': logDistanceCoefficient,
    'linearDistanceCoefficient': linearDistanceCoefficient,
    'nearDistanceKm': nearDistanceKm,
    'huberDelta': huberDelta,
    'residualScale': residualScale,
    'centroidPenaltyPerKm': centroidPenaltyPerKm,
    'depthClassesKm': depthClassesKm,
    'sourceScaleSemantics': 'event_specific_fitted_intercept_not_jma_magnitude',
  };
}

class StaticAttenuationTrainer {
  final List<double> logDistanceCandidates;
  final List<double> linearDistanceCandidates;
  final List<double> nearDistanceCandidatesKm;
  final double huberDelta;

  const StaticAttenuationTrainer({
    this.logDistanceCandidates = const [0.5, 1.0, 1.5, 2.0, 2.5, 3.0],
    this.linearDistanceCandidates = const [0, 0.001, 0.0025, 0.005, 0.01],
    this.nearDistanceCandidatesKm = const [1, 5, 10, 20],
    this.huberDelta = 1.0,
  });

  StaticAttenuationModel train(List<StaticIntensityEvent> events) {
    if (events.isEmpty) throw ArgumentError('Training events are empty.');
    var bestLoss = double.infinity;
    var bestC = 0.0;
    var bestD = 0.0;
    var bestR0 = 1.0;
    for (final c in logDistanceCandidates) {
      for (final d in linearDistanceCandidates) {
        for (final r0 in nearDistanceCandidatesKm) {
          final loss = _datasetLoss(events, c: c, d: d, r0: r0);
          if (loss < bestLoss) {
            bestLoss = loss;
            bestC = c;
            bestD = d;
            bestR0 = r0;
          }
        }
      }
    }
    final residuals = <double>[];
    for (final event in events) {
      final terms = [
        for (final station in event.stations)
          _correctedIntensity(event, station, c: bestC, d: bestD, r0: bestR0),
      ];
      final sourceScale = _median(terms);
      for (final value in terms) {
        residuals.add(value - sourceScale);
      }
    }
    final absolute = residuals.map((value) => value.abs()).toList()..sort();
    final mad = _median(absolute);
    return StaticAttenuationModel(
      logDistanceCoefficient: bestC,
      linearDistanceCoefficient: bestD,
      nearDistanceKm: bestR0,
      huberDelta: huberDelta,
      residualScale: math.max(0.1, mad * 1.4826),
    );
  }

  double _datasetLoss(
    List<StaticIntensityEvent> events, {
    required double c,
    required double d,
    required double r0,
  }) {
    var loss = 0.0;
    var count = 0;
    for (final event in events) {
      if (event.stations.length < 4) continue;
      final corrected = [
        for (final station in event.stations)
          _correctedIntensity(event, station, c: c, d: d, r0: r0),
      ];
      final sourceScale = _median(corrected);
      for (final value in corrected) {
        loss += _huber(value - sourceScale, huberDelta);
        count++;
      }
    }
    return count == 0 ? double.infinity : loss / count;
  }

  double _correctedIntensity(
    StaticIntensityEvent event,
    StaticIntensityStation station, {
    required double c,
    required double d,
    required double r0,
  }) {
    final surfaceDistance = QuakeCalculator.haversineDistance(
      event.latitude,
      event.longitude,
      station.latitude,
      station.longitude,
    );
    final distance = math.sqrt(
      surfaceDistance * surfaceDistance + event.depthKm * event.depthKm,
    );
    return station.intensity + c * _log10(distance + r0) + d * distance;
  }
}

class JmaStyleIntensityPrediction {
  final double intensity;
  final double pgv600;
  final double surfacePgv;
  final double amplification;
  final double amplificationDistanceKm;
  final String amplificationSource;

  const JmaStyleIntensityPrediction({
    required this.intensity,
    required this.pgv600,
    required this.surfacePgv,
    required this.amplification,
    required this.amplificationDistanceKm,
    required this.amplificationSource,
  });
}

class JmaStyleIntensityPredictor {
  final double defaultAmplification;
  final double maximumAmplificationMatchKm;

  const JmaStyleIntensityPredictor({
    this.defaultAmplification = 1.0,
    this.maximumAmplificationMatchKm = 5.0,
  });

  JmaStyleIntensityPrediction predict({
    required double magnitude,
    required double sourceLatitude,
    required double sourceLongitude,
    required double depthKm,
    required double stationLatitude,
    required double stationLongitude,
    double? siteAmplification,
    double? siteAmplificationDistanceKm,
    String? siteAmplificationSource,
  }) {
    final surfaceDistanceKm = QuakeCalculator.haversineDistance(
      sourceLatitude,
      sourceLongitude,
      stationLatitude,
      stationLongitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final pgv600 = pgv600FromJmaMagnitude(
      magnitude: magnitude,
      depthKm: depthKm,
      distanceKm: hypocentralDistanceKm,
    );
    final site = siteAmplification == null
        ? nearestAmplification(
            stationLatitude: stationLatitude,
            stationLongitude: stationLongitude,
          )
        : (
            siteAmplification,
            siteAmplificationDistanceKm ?? 0.0,
            siteAmplificationSource ?? 'provided_arv',
          );
    final surfacePgv = surfacePgvFromPgv600(
      pgv600: pgv600,
      amplification: site.$1,
    );
    return JmaStyleIntensityPrediction(
      intensity: instrumentalIntensityFromSurfacePgv(surfacePgv),
      pgv600: pgv600,
      surfacePgv: surfacePgv,
      amplification: site.$1,
      amplificationDistanceKm: site.$2,
      amplificationSource: site.$3,
    );
  }

  double pgv600FromJmaMagnitude({
    required double magnitude,
    required double depthKm,
    required double distanceKm,
  }) {
    final mw = magnitude - 0.171;
    final x = math.max(distanceKm, 1.0);
    final logPgv600 =
        0.58 * mw +
        0.0038 * depthKm -
        1.29 -
        _log10(x + 0.0028 * math.pow(10, 0.50 * mw)) -
        0.002 * x;
    return math.pow(10, logPgv600).toDouble();
  }

  double surfacePgvFromPgv600({
    required double pgv600,
    required double amplification,
  }) {
    return amplification * 0.90 * pgv600;
  }

  double instrumentalIntensityFromSurfacePgv(double surfacePgv) {
    if (surfacePgv <= 0) return -3.0;
    return 2.68 + 1.72 * _log10(surfacePgv);
  }

  (double, double, String) nearestAmplification({
    required double stationLatitude,
    required double stationLongitude,
  }) {
    var bestDistance = double.infinity;
    var bestAmplification = defaultAmplification;
    var bestName = 'default_arv';
    for (final station in JmaSeisIntLoc.getStations()) {
      final distance = QuakeCalculator.haversineDistance(
        stationLatitude,
        stationLongitude,
        station.lat,
        station.lng,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestAmplification = station.arv;
        bestName = station.name;
      }
    }
    if (bestDistance > maximumAmplificationMatchKm) {
      return (defaultAmplification, bestDistance, 'default_arv');
    }
    return (bestAmplification, bestDistance, bestName);
  }
}

class PlumLikeIntensityPrediction {
  final double intensity;
  final int evidenceCount;
  final double nearestEvidenceDistanceKm;
  final String? strongestEvidenceStationId;

  const PlumLikeIntensityPrediction({
    required this.intensity,
    required this.evidenceCount,
    required this.nearestEvidenceDistanceKm,
    this.strongestEvidenceStationId,
  });
}

class PlumLikeIntensityPredictor {
  final double radiusKm;
  final double dampingPer10Km;
  final int minimumEvidenceCount;
  final double noPredictionIntensity;

  const PlumLikeIntensityPredictor({
    this.radiusKm = 30.0,
    this.dampingPer10Km = 0.0,
    this.minimumEvidenceCount = 1,
    this.noPredictionIntensity = -3.0,
  });

  PlumLikeIntensityPrediction predict({
    required StaticIntensityStation targetStation,
    required List<StaticIntensityStation> observedStations,
  }) {
    var evidenceCount = 0;
    var nearestDistance = double.infinity;
    var bestIntensity = -double.infinity;
    String? bestStationId;
    for (final observed in observedStations) {
      if (observed.stationId == targetStation.stationId) continue;
      final distance = QuakeCalculator.haversineDistance(
        targetStation.latitude,
        targetStation.longitude,
        observed.latitude,
        observed.longitude,
      );
      if (distance > radiusKm) continue;
      evidenceCount++;
      if (distance < nearestDistance) nearestDistance = distance;
      final propagated =
          observed.intensity - dampingPer10Km * (distance / 10.0);
      if (propagated > bestIntensity) {
        bestIntensity = propagated;
        bestStationId = observed.stationId;
      }
    }
    if (evidenceCount < minimumEvidenceCount) {
      return PlumLikeIntensityPrediction(
        intensity: noPredictionIntensity,
        evidenceCount: evidenceCount,
        nearestEvidenceDistanceKm: nearestDistance,
      );
    }
    return PlumLikeIntensityPrediction(
      intensity: bestIntensity,
      evidenceCount: evidenceCount,
      nearestEvidenceDistanceKm: nearestDistance,
      strongestEvidenceStationId: bestStationId,
    );
  }
}

class StaticIntensityLocationEstimate {
  final double latitude;
  final double longitude;
  final double depthKm;
  final double sourceScale;
  final double score;
  final double p50RadiusKm;
  final double p90RadiusKm;
  final int stationCount;

  const StaticIntensityLocationEstimate({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.sourceScale,
    required this.score,
    required this.p50RadiusKm,
    required this.p90RadiusKm,
    required this.stationCount,
  });
}

class StaticIntensityLocator {
  final StaticAttenuationModel model;
  final double coarseExtentDegrees;
  final double coarseStepDegrees;
  final double fineExtentDegrees;
  final double fineStepDegrees;
  final int maximumStations;

  const StaticIntensityLocator({
    required this.model,
    this.coarseExtentDegrees = 3,
    this.coarseStepDegrees = 0.5,
    this.fineExtentDegrees = 0.6,
    this.fineStepDegrees = 0.1,
    this.maximumStations = 32,
  });

  StaticIntensityLocationEstimate? locate(
    List<StaticIntensityStation> inputStations,
  ) {
    if (inputStations.length < 4) return null;
    final stations = _selectStations(inputStations);
    final center = _weightedCentroid(stations);
    var candidates = _scan(
      stations,
      weightedCenter: center,
      minLatitude: center.$1 - coarseExtentDegrees,
      maxLatitude: center.$1 + coarseExtentDegrees,
      minLongitude: center.$2 - coarseExtentDegrees,
      maxLongitude: center.$2 + coarseExtentDegrees,
      step: coarseStepDegrees,
    );
    final coarseBest = candidates.first;
    candidates = _scan(
      stations,
      weightedCenter: center,
      minLatitude: coarseBest.latitude - fineExtentDegrees,
      maxLatitude: coarseBest.latitude + fineExtentDegrees,
      minLongitude: coarseBest.longitude - fineExtentDegrees,
      maxLongitude: coarseBest.longitude + fineExtentDegrees,
      step: fineStepDegrees,
    );
    final best = candidates.first;
    final uncertainty = _uncertainty(candidates, best);
    return StaticIntensityLocationEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      depthKm: best.depthKm,
      sourceScale: best.sourceScale,
      score: best.score,
      p50RadiusKm: uncertainty.$1,
      p90RadiusKm: uncertainty.$2,
      stationCount: stations.length,
    );
  }

  List<_StaticCandidate> _scan(
    List<StaticIntensityStation> stations, {
    required (double, double) weightedCenter,
    required double minLatitude,
    required double maxLatitude,
    required double minLongitude,
    required double maxLongitude,
    required double step,
  }) {
    final candidates = <_StaticCandidate>[];
    for (
      var latitude = minLatitude;
      latitude <= maxLatitude + 1e-9;
      latitude += step
    ) {
      for (
        var longitude = minLongitude;
        longitude <= maxLongitude + 1e-9;
        longitude += step
      ) {
        for (final depthKm in model.depthClassesKm) {
          candidates.add(
            _score(
              stations,
              latitude,
              longitude,
              depthKm,
              weightedCenter: weightedCenter,
            ),
          );
        }
      }
    }
    candidates.sort((left, right) => left.score.compareTo(right.score));
    return candidates;
  }

  _StaticCandidate _score(
    List<StaticIntensityStation> stations,
    double latitude,
    double longitude,
    double depthKm, {
    required (double, double) weightedCenter,
  }) {
    final corrected = <double>[];
    for (final station in stations) {
      final surfaceDistance = QuakeCalculator.haversineDistance(
        latitude,
        longitude,
        station.latitude,
        station.longitude,
      );
      final distance = math.sqrt(
        surfaceDistance * surfaceDistance + depthKm * depthKm,
      );
      corrected.add(
        station.intensity +
            model.logDistanceCoefficient *
                _log10(distance + model.nearDistanceKm) +
            model.linearDistanceCoefficient * distance,
      );
    }
    final sourceScale = _median(corrected);
    var score = 0.0;
    for (final value in corrected) {
      score += _huber(value - sourceScale, model.huberDelta);
    }
    score +=
        model.centroidPenaltyPerKm *
        QuakeCalculator.haversineDistance(
          latitude,
          longitude,
          weightedCenter.$1,
          weightedCenter.$2,
        ) *
        stations.length;
    return _StaticCandidate(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      sourceScale: sourceScale,
      score: score / stations.length,
    );
  }

  (double, double) _weightedCentroid(List<StaticIntensityStation> stations) {
    var latitude = 0.0;
    var longitude = 0.0;
    var total = 0.0;
    for (final station in stations) {
      final weight = math.pow(10, station.intensity / 2).toDouble();
      latitude += station.latitude * weight;
      longitude += station.longitude * weight;
      total += weight;
    }
    return (latitude / total, longitude / total);
  }

  List<StaticIntensityStation> _selectStations(
    List<StaticIntensityStation> stations,
  ) {
    if (stations.length <= maximumStations) return stations;
    final sorted = List<StaticIntensityStation>.from(stations)
      ..sort((left, right) {
        final intensityOrder = right.intensity.compareTo(left.intensity);
        return intensityOrder != 0
            ? intensityOrder
            : left.stationId.compareTo(right.stationId);
      });
    return sorted.take(maximumStations).toList(growable: false);
  }

  (double, double) _uncertainty(
    List<_StaticCandidate> candidates,
    _StaticCandidate best,
  ) {
    final scale = math.max(model.residualScale, 0.1);
    final weightedDistances = <(double, double)>[];
    var totalWeight = 0.0;
    for (final candidate in candidates) {
      final weight = math.exp(-(candidate.score - best.score) / scale);
      final distance = QuakeCalculator.haversineDistance(
        best.latitude,
        best.longitude,
        candidate.latitude,
        candidate.longitude,
      );
      weightedDistances.add((distance, weight));
      totalWeight += weight;
    }
    weightedDistances.sort((left, right) => left.$1.compareTo(right.$1));
    double percentile(double target) {
      var cumulative = 0.0;
      for (final item in weightedDistances) {
        cumulative += item.$2;
        if (cumulative / totalWeight >= target) return item.$1;
      }
      return weightedDistances.last.$1;
    }

    return (percentile(0.5), percentile(0.9));
  }
}

class StaticIntensityEvaluation {
  final int caseCount;
  final double medianErrorKm;
  final double p90ErrorKm;
  final double weightedCentroidMedianErrorKm;
  final double weightedCentroidP90ErrorKm;
  final double p50Coverage;
  final double p90Coverage;
  final double medianP50RadiusKm;
  final double medianP90RadiusKm;
  final Map<String, Map<String, Object?>> byMaskRate;

  const StaticIntensityEvaluation({
    required this.caseCount,
    required this.medianErrorKm,
    required this.p90ErrorKm,
    required this.weightedCentroidMedianErrorKm,
    required this.weightedCentroidP90ErrorKm,
    required this.p50Coverage,
    required this.p90Coverage,
    required this.medianP50RadiusKm,
    required this.medianP90RadiusKm,
    required this.byMaskRate,
  });

  Map<String, Object?> toJson() => {
    'caseCount': caseCount,
    'medianErrorKm': medianErrorKm,
    'p90ErrorKm': p90ErrorKm,
    'weightedCentroidMedianErrorKm': weightedCentroidMedianErrorKm,
    'weightedCentroidP90ErrorKm': weightedCentroidP90ErrorKm,
    'p50Coverage': p50Coverage,
    'p90Coverage': p90Coverage,
    'medianP50RadiusKm': medianP50RadiusKm,
    'medianP90RadiusKm': medianP90RadiusKm,
    'byMaskRate': byMaskRate,
  };
}

class StaticIntensityEvaluator {
  final StaticIntensityLocator locator;

  const StaticIntensityEvaluator(this.locator);

  StaticIntensityEvaluation evaluate(List<StaticIntensityEvent> events) {
    final errors = <double>[];
    final baselineErrors = <double>[];
    final p50Radii = <double>[];
    final p90Radii = <double>[];
    var p50Covered = 0;
    var p90Covered = 0;
    final buckets = <String, _EvaluationBucket>{};
    for (final event in events) {
      final byId = {
        for (final station in event.stations) station.stationId: station,
      };
      for (final variant in event.variants) {
        final stations = [
          for (final id in variant.retainedStationIds)
            if (byId[id] != null) byId[id]!,
        ];
        final estimate = locator.locate(stations);
        if (estimate == null) continue;
        final error = QuakeCalculator.haversineDistance(
          event.latitude,
          event.longitude,
          estimate.latitude,
          estimate.longitude,
        );
        final centroid = _weightedCentroid(stations);
        final baselineError = QuakeCalculator.haversineDistance(
          event.latitude,
          event.longitude,
          centroid.$1,
          centroid.$2,
        );
        errors.add(error);
        baselineErrors.add(baselineError);
        p50Radii.add(estimate.p50RadiusKm);
        p90Radii.add(estimate.p90RadiusKm);
        if (error <= estimate.p50RadiusKm) p50Covered++;
        if (error <= estimate.p90RadiusKm) p90Covered++;
        final key = '${(variant.maskRate * 100).round()}pct';
        buckets
            .putIfAbsent(key, _EvaluationBucket.new)
            .add(error: error, baselineError: baselineError);
      }
    }
    if (errors.isEmpty) throw StateError('No evaluation cases produced.');
    return StaticIntensityEvaluation(
      caseCount: errors.length,
      medianErrorKm: _percentile(errors, 0.5),
      p90ErrorKm: _percentile(errors, 0.9),
      weightedCentroidMedianErrorKm: _percentile(baselineErrors, 0.5),
      weightedCentroidP90ErrorKm: _percentile(baselineErrors, 0.9),
      p50Coverage: p50Covered / errors.length,
      p90Coverage: p90Covered / errors.length,
      medianP50RadiusKm: _percentile(p50Radii, 0.5),
      medianP90RadiusKm: _percentile(p90Radii, 0.5),
      byMaskRate: {
        for (final entry in buckets.entries) entry.key: entry.value.toJson(),
      },
    );
  }
}

class _StaticCandidate {
  final double latitude;
  final double longitude;
  final double depthKm;
  final double sourceScale;
  final double score;

  const _StaticCandidate({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.sourceScale,
    required this.score,
  });
}

class _EvaluationBucket {
  final List<double> errors = [];
  final List<double> baselineErrors = [];

  void add({required double error, required double baselineError}) {
    errors.add(error);
    baselineErrors.add(baselineError);
  }

  Map<String, Object?> toJson() => {
    'caseCount': errors.length,
    'medianErrorKm': _percentile(errors, 0.5),
    'p90ErrorKm': _percentile(errors, 0.9),
    'weightedCentroidMedianErrorKm': _percentile(baselineErrors, 0.5),
    'weightedCentroidP90ErrorKm': _percentile(baselineErrors, 0.9),
  };
}

(double, double) _weightedCentroid(List<StaticIntensityStation> stations) {
  var latitude = 0.0;
  var longitude = 0.0;
  var total = 0.0;
  for (final station in stations) {
    final weight = math.pow(10, station.intensity / 2).toDouble();
    latitude += station.latitude * weight;
    longitude += station.longitude * weight;
    total += weight;
  }
  return (latitude / total, longitude / total);
}

double _huber(double residual, double delta) {
  final absolute = residual.abs();
  return absolute <= delta
      ? 0.5 * residual * residual
      : delta * (absolute - 0.5 * delta);
}

double _median(List<double> values) => _percentile(values, 0.5);

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return double.nan;
  final sorted = List<double>.from(values)..sort();
  final position = (sorted.length - 1) * percentile;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = position - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}

double _log10(double value) => math.log(value) / math.ln10;
