import 'dart:math' as math;

import 'matsuzaki_2006_jma_baseline.dart';

class Matsuzaki2006StationBiasEstimate {
  const Matsuzaki2006StationBiasEstimate({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.trainingEventCount,
    required this.meanCenteredResidual,
    required this.centeredResidualStandardDeviation,
    required this.centeredResidualStandardError,
  });

  final String stationId;
  final double latitude;
  final double longitude;
  final int trainingEventCount;
  final double meanCenteredResidual;
  final double centeredResidualStandardDeviation;
  final double centeredResidualStandardError;

  Map<String, Object> toJson() => {
    'stationId': stationId,
    'latitude': latitude,
    'longitude': longitude,
    'trainingEventCount': trainingEventCount,
    'meanCenteredResidual': meanCenteredResidual,
    'centeredResidualStandardDeviation': centeredResidualStandardDeviation,
    'centeredResidualStandardError': centeredResidualStandardError,
  };
}

class Matsuzaki2006StationBiasModel {
  Matsuzaki2006StationBiasModel({
    required this.minimumTrainingEventCount,
    required this.trainingEventCount,
    required this.trainingObservationCount,
    required this.distinctTrainingStationCount,
    required this.coordinateConflictStationCount,
    required Map<String, Matsuzaki2006StationBiasEstimate> estimates,
  }) : estimates = Map.unmodifiable(estimates);

  final int minimumTrainingEventCount;
  final int trainingEventCount;
  final int trainingObservationCount;
  final int distinctTrainingStationCount;
  final int coordinateConflictStationCount;
  final Map<String, Matsuzaki2006StationBiasEstimate> estimates;

  Matsuzaki2006StationBiasEstimate? matchingEstimate(
    Matsuzaki2006StationResidual station,
  ) {
    final estimate = estimates[station.stationId];
    if (estimate == null ||
        estimate.latitude != station.latitude ||
        estimate.longitude != station.longitude) {
      return null;
    }
    return estimate;
  }

  Map<String, Object> toJson() {
    final stationIds = estimates.keys.toList()..sort();
    final trainingCounts = estimates.values
        .map((estimate) => estimate.trainingEventCount.toDouble())
        .toList();
    final absoluteBiases = estimates.values
        .map((estimate) => estimate.meanCenteredResidual.abs())
        .toList();
    final standardErrors = estimates.values
        .map((estimate) => estimate.centeredResidualStandardError)
        .toList();
    return {
      'minimumTrainingEventCount': minimumTrainingEventCount,
      'trainingEventCount': trainingEventCount,
      'trainingObservationCount': trainingObservationCount,
      'distinctTrainingStationCount': distinctTrainingStationCount,
      'coordinateConflictStationCount': coordinateConflictStationCount,
      'eligibleStationCount': estimates.length,
      'estimateDistributions': {
        'trainingEventCount': _distribution(trainingCounts),
        'absoluteMeanCenteredResidual': _distribution(absoluteBiases),
        'centeredResidualStandardError': _distribution(standardErrors),
      },
      'stationEstimates': [
        for (final stationId in stationIds) estimates[stationId]!.toJson(),
      ],
    };
  }

  static Map<String, double> _distribution(List<double> values) => {
    'minimum': _percentile(values, 0),
    'median': _percentile(values, 0.5),
    'p90': _percentile(values, 0.9),
    'p99': _percentile(values, 0.99),
    'maximum': _percentile(values, 1),
  };

  static double _percentile(List<double> values, double fraction) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final position = (sorted.length - 1) * fraction;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}

/// Shrinks a fitted station term toward zero without changing its training data.
///
/// The pseudo-event count is selected on a validation year. A value of zero
/// reproduces the unshrunk station-bias model exactly.
class Matsuzaki2006StationBiasShrinkage {
  const Matsuzaki2006StationBiasShrinkage({required this.pseudoEventCount})
    : assert(pseudoEventCount >= 0);

  final int pseudoEventCount;

  double apply(Matsuzaki2006StationBiasEstimate estimate) {
    if (pseudoEventCount == 0) return estimate.meanCenteredResidual;
    final weight =
        estimate.trainingEventCount /
        (estimate.trainingEventCount + pseudoEventCount);
    return estimate.meanCenteredResidual * weight;
  }

  Map<String, Object> toJson() => {
    'formula':
        'station_bias * training_event_count / '
        '(training_event_count + pseudo_event_count)',
    'pseudoEventCount': pseudoEventCount,
  };
}

class Matsuzaki2006StationBiasTrainer {
  final Map<String, _StationAccumulator> _stations = {};
  var _eventCount = 0;
  var _observationCount = 0;

  int get eventCount => _eventCount;
  int get observationCount => _observationCount;
  int get distinctStationCount => _stations.length;

  void addEvents(Iterable<Matsuzaki2006EventBaseline> events) {
    for (final event in events) {
      addEvent(event);
    }
  }

  void addEvent(Matsuzaki2006EventBaseline event) {
    if (event.stationResiduals.isEmpty) {
      throw ArgumentError.value(
        event.eventId,
        'event',
        'Station-bias training requires at least one station residual.',
      );
    }
    final eventMeanResidual = event.residualSummary.meanResidual;
    _eventCount++;
    for (final station in event.stationResiduals) {
      _observationCount++;
      _stations
          .putIfAbsent(
            station.stationId,
            () => _StationAccumulator(
              latitude: station.latitude,
              longitude: station.longitude,
            ),
          )
          .add(
            latitude: station.latitude,
            longitude: station.longitude,
            centeredResidual: station.residual - eventMeanResidual,
          );
    }
  }

  Matsuzaki2006StationBiasModel build({
    required int minimumTrainingEventCount,
  }) {
    if (minimumTrainingEventCount < 2) {
      throw ArgumentError.value(
        minimumTrainingEventCount,
        'minimumTrainingEventCount',
        'A long-term station estimate requires at least two events.',
      );
    }
    final estimates = <String, Matsuzaki2006StationBiasEstimate>{};
    var coordinateConflictStationCount = 0;
    for (final entry in _stations.entries) {
      final accumulator = entry.value;
      if (accumulator.hasCoordinateConflict) {
        coordinateConflictStationCount++;
        continue;
      }
      if (accumulator.count < minimumTrainingEventCount) continue;
      estimates[entry.key] = accumulator.estimate(entry.key);
    }
    return Matsuzaki2006StationBiasModel(
      minimumTrainingEventCount: minimumTrainingEventCount,
      trainingEventCount: _eventCount,
      trainingObservationCount: _observationCount,
      distinctTrainingStationCount: _stations.length,
      coordinateConflictStationCount: coordinateConflictStationCount,
      estimates: estimates,
    );
  }
}

class Matsuzaki2006StationBiasEventEvaluation {
  const Matsuzaki2006StationBiasEventEvaluation({
    required this.eventId,
    required this.year,
    required this.observationCount,
    required this.correctionAppliedCount,
    required this.correctionUnavailableCount,
    required this.coordinateMismatchCount,
    required this.baselineRawResiduals,
    required this.correctedRawResiduals,
    required this.baselineCenteredResiduals,
    required this.correctedCenteredResiduals,
  });

  final String eventId;
  final int year;
  final int observationCount;
  final int correctionAppliedCount;
  final int correctionUnavailableCount;
  final int coordinateMismatchCount;
  final Matsuzaki2006ResidualSummary baselineRawResiduals;
  final Matsuzaki2006ResidualSummary correctedRawResiduals;
  final Matsuzaki2006ResidualSummary baselineCenteredResiduals;
  final Matsuzaki2006ResidualSummary correctedCenteredResiduals;

  Map<String, Object> toJson() => {
    'eventId': eventId,
    'year': year,
    'observationCount': observationCount,
    'correctionAppliedCount': correctionAppliedCount,
    'correctionUnavailableCount': correctionUnavailableCount,
    'coordinateMismatchCount': coordinateMismatchCount,
    'baselineRawResiduals': baselineRawResiduals.toJson(),
    'correctedRawResiduals': correctedRawResiduals.toJson(),
    'baselineCenteredResiduals': baselineCenteredResiduals.toJson(),
    'correctedCenteredResiduals': correctedCenteredResiduals.toJson(),
  };
}

class Matsuzaki2006StationBiasEvaluation {
  Matsuzaki2006StationBiasEvaluation({
    required List<Matsuzaki2006StationBiasEventEvaluation> events,
  }) : events = List.unmodifiable(events);

  final List<Matsuzaki2006StationBiasEventEvaluation> events;

  static const double _eventComparisonTolerance = 1e-12;

  int get observationCount =>
      events.fold(0, (sum, event) => sum + event.observationCount);
  int get correctionAppliedCount =>
      events.fold(0, (sum, event) => sum + event.correctionAppliedCount);
  int get correctionUnavailableCount =>
      events.fold(0, (sum, event) => sum + event.correctionUnavailableCount);
  int get coordinateMismatchCount =>
      events.fold(0, (sum, event) => sum + event.coordinateMismatchCount);

  double get correctionCoverage =>
      observationCount == 0 ? 0 : correctionAppliedCount / observationCount;

  double get baselineEventEqualCenteredRms => _eventEqualAverage(
    (event) => event.baselineCenteredResiduals.rootMeanSquareResidual,
  );

  double get correctedEventEqualCenteredRms => _eventEqualAverage(
    (event) => event.correctedCenteredResiduals.rootMeanSquareResidual,
  );

  int get centeredRmsImprovedEventCount => events
      .where(
        (event) =>
            event.correctedCenteredResiduals.rootMeanSquareResidual +
                _eventComparisonTolerance <
            event.baselineCenteredResiduals.rootMeanSquareResidual,
      )
      .length;

  int get centeredRmsWorsenedEventCount => events
      .where(
        (event) =>
            event.baselineCenteredResiduals.rootMeanSquareResidual +
                _eventComparisonTolerance <
            event.correctedCenteredResiduals.rootMeanSquareResidual,
      )
      .length;

  int get centeredRmsUnchangedEventCount =>
      events.length -
      centeredRmsImprovedEventCount -
      centeredRmsWorsenedEventCount;

  Map<String, Object> toJson({bool includeEvents = true}) => {
    'eventCount': events.length,
    'observationCount': observationCount,
    'correctionAppliedCount': correctionAppliedCount,
    'correctionUnavailableCount': correctionUnavailableCount,
    'coordinateMismatchCount': coordinateMismatchCount,
    'correctionCoverage': correctionCoverage,
    'eventCenteredRmsComparison': {
      'tolerance': _eventComparisonTolerance,
      'improvedEventCount': centeredRmsImprovedEventCount,
      'worsenedEventCount': centeredRmsWorsenedEventCount,
      'unchangedEventCount': centeredRmsUnchangedEventCount,
    },
    'stationWeighted': {
      'baselineRaw': _pooledSummary(
        (event) => event.baselineRawResiduals,
      ).toJson(),
      'correctedRaw': _pooledSummary(
        (event) => event.correctedRawResiduals,
      ).toJson(),
      'baselineCentered': _pooledSummary(
        (event) => event.baselineCenteredResiduals,
      ).toJson(),
      'correctedCentered': _pooledSummary(
        (event) => event.correctedCenteredResiduals,
      ).toJson(),
    },
    'eventEqual': {
      'baselineRawMeanRms': _eventEqualAverage(
        (event) => event.baselineRawResiduals.rootMeanSquareResidual,
      ),
      'correctedRawMeanRms': _eventEqualAverage(
        (event) => event.correctedRawResiduals.rootMeanSquareResidual,
      ),
      'baselineCenteredMeanRms': baselineEventEqualCenteredRms,
      'correctedCenteredMeanRms': correctedEventEqualCenteredRms,
      'centeredMeanRmsFractionalImprovement': baselineEventEqualCenteredRms == 0
          ? 0.0
          : (baselineEventEqualCenteredRms - correctedEventEqualCenteredRms) /
                baselineEventEqualCenteredRms,
    },
    if (includeEvents) 'events': [for (final event in events) event.toJson()],
  };

  double _eventEqualAverage(
    double Function(Matsuzaki2006StationBiasEventEvaluation event) value,
  ) {
    if (events.isEmpty) return 0;
    return events.fold(0.0, (sum, event) => sum + value(event)) / events.length;
  }

  Matsuzaki2006ResidualSummary _pooledSummary(
    Matsuzaki2006ResidualSummary Function(
      Matsuzaki2006StationBiasEventEvaluation event,
    )
    summary,
  ) {
    var count = 0;
    var sum = 0.0;
    var absoluteSum = 0.0;
    var squaredSum = 0.0;
    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    for (final event in events) {
      final value = summary(event);
      count += value.count;
      sum += value.meanResidual * value.count;
      absoluteSum += value.meanAbsoluteResidual * value.count;
      squaredSum +=
          value.rootMeanSquareResidual *
          value.rootMeanSquareResidual *
          value.count;
      if (value.count > 0) {
        minimum = math.min(minimum, value.minimumResidual);
        maximum = math.max(maximum, value.maximumResidual);
      }
    }
    if (count == 0) {
      return Matsuzaki2006ResidualSummary.fromResiduals(const []);
    }
    return Matsuzaki2006ResidualSummary(
      count: count,
      meanResidual: sum / count,
      meanAbsoluteResidual: absoluteSum / count,
      rootMeanSquareResidual: math.sqrt(squaredSum / count),
      minimumResidual: minimum,
      maximumResidual: maximum,
    );
  }
}

class Matsuzaki2006StationBiasEvaluator {
  const Matsuzaki2006StationBiasEvaluator({
    this.shrinkage = const Matsuzaki2006StationBiasShrinkage(
      pseudoEventCount: 0,
    ),
  });

  final Matsuzaki2006StationBiasShrinkage shrinkage;

  Matsuzaki2006StationBiasEvaluation evaluate({
    required Iterable<Matsuzaki2006EventBaseline> events,
    required Matsuzaki2006StationBiasModel stationBiasModel,
  }) {
    final evaluations = <Matsuzaki2006StationBiasEventEvaluation>[];
    for (final event in events) {
      if (event.stationResiduals.isEmpty) continue;
      final baselineRaw = <double>[];
      final correctedRaw = <double>[];
      var applied = 0;
      var unavailable = 0;
      var coordinateMismatch = 0;
      for (final station in event.stationResiduals) {
        final residual = station.residual;
        baselineRaw.add(residual);
        final estimate = stationBiasModel.estimates[station.stationId];
        if (estimate == null) {
          unavailable++;
          correctedRaw.add(residual);
        } else if (estimate.latitude != station.latitude ||
            estimate.longitude != station.longitude) {
          coordinateMismatch++;
          correctedRaw.add(residual);
        } else {
          applied++;
          correctedRaw.add(residual - shrinkage.apply(estimate));
        }
      }
      final baselineMean = _mean(baselineRaw);
      final correctedMean = _mean(correctedRaw);
      evaluations.add(
        Matsuzaki2006StationBiasEventEvaluation(
          eventId: event.eventId,
          year: event.year,
          observationCount: baselineRaw.length,
          correctionAppliedCount: applied,
          correctionUnavailableCount: unavailable,
          coordinateMismatchCount: coordinateMismatch,
          baselineRawResiduals: Matsuzaki2006ResidualSummary.fromResiduals(
            baselineRaw,
          ),
          correctedRawResiduals: Matsuzaki2006ResidualSummary.fromResiduals(
            correctedRaw,
          ),
          baselineCenteredResiduals: Matsuzaki2006ResidualSummary.fromResiduals(
            baselineRaw.map((value) => value - baselineMean),
          ),
          correctedCenteredResiduals:
              Matsuzaki2006ResidualSummary.fromResiduals(
                correctedRaw.map((value) => value - correctedMean),
              ),
        ),
      );
    }
    return Matsuzaki2006StationBiasEvaluation(events: evaluations);
  }

  static double _mean(List<double> values) =>
      values.fold(0.0, (sum, value) => sum + value) / values.length;
}

class _StationAccumulator {
  _StationAccumulator({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
  var count = 0;
  var sum = 0.0;
  var squaredSum = 0.0;
  var hasCoordinateConflict = false;

  void add({
    required double latitude,
    required double longitude,
    required double centeredResidual,
  }) {
    if (latitude != this.latitude || longitude != this.longitude) {
      hasCoordinateConflict = true;
    }
    count++;
    sum += centeredResidual;
    squaredSum += centeredResidual * centeredResidual;
  }

  Matsuzaki2006StationBiasEstimate estimate(String stationId) {
    final mean = sum / count;
    final variance = count < 2
        ? 0.0
        : math.max(0.0, (squaredSum - sum * sum / count) / (count - 1));
    final standardDeviation = math.sqrt(variance);
    return Matsuzaki2006StationBiasEstimate(
      stationId: stationId,
      latitude: latitude,
      longitude: longitude,
      trainingEventCount: count,
      meanCenteredResidual: mean,
      centeredResidualStandardDeviation: standardDeviation,
      centeredResidualStandardError: standardDeviation / math.sqrt(count),
    );
  }
}
