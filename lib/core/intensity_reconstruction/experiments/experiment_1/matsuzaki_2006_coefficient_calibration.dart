import 'dart:math' as math;

import 'matsuzaki_2006_attenuation_model.dart';
import 'matsuzaki_2006_jma_baseline.dart';

enum Matsuzaki2006CalibrationMethod {
  globalStationWeighted,
  eventSourceStripped,
  eventSourceStrippedDistanceBalanced,
  eventSourceStrippedFixedSaturation,
  globalFixedSaturation,
  globalFixedExponent,
  globalFixedCoefficient,
}

class Matsuzaki2006DistanceBalanceSpec {
  const Matsuzaki2006DistanceBalanceSpec({
    required this.nearDistanceThresholdKm,
    required this.nearGroupWeight,
  });

  final double nearDistanceThresholdKm;
  final double nearGroupWeight;

  void validate() {
    if (!nearDistanceThresholdKm.isFinite || nearDistanceThresholdKm <= 0) {
      throw ArgumentError.value(
        nearDistanceThresholdKm,
        'nearDistanceThresholdKm',
        'Must be finite and positive.',
      );
    }
    if (!nearGroupWeight.isFinite ||
        nearGroupWeight <= 0 ||
        nearGroupWeight >= 1) {
      throw ArgumentError.value(
        nearGroupWeight,
        'nearGroupWeight',
        'Must be finite and strictly between zero and one.',
      );
    }
  }

  Map<String, Object> toJson() => {
    'nearDistanceThresholdKm': nearDistanceThresholdKm,
    'nearGroupWeightWhenBothGroupsExist': nearGroupWeight,
    'farGroupWeightWhenBothGroupsExist': 1 - nearGroupWeight,
    'eventWeighting': 'equal_total_weight_per_event',
    'singleGroupEventPolicy': 'present_group_receives_full_event_weight',
  };
}

class Matsuzaki2006NonlinearStart {
  const Matsuzaki2006NonlinearStart({
    required this.saturationCoefficient,
    required this.saturationMagnitudeExponent,
  }) : assert(saturationCoefficient > 0),
       assert(saturationMagnitudeExponent > 0);

  final double saturationCoefficient;
  final double saturationMagnitudeExponent;

  Map<String, double> toJson() => {
    'saturationCoefficient': saturationCoefficient,
    'saturationMagnitudeExponent': saturationMagnitudeExponent,
  };
}

class Matsuzaki2006CalibrationSearchSpec {
  Matsuzaki2006CalibrationSearchSpec({
    required List<Matsuzaki2006NonlinearStart> starts,
    required this.initialSimplexStep,
    required this.objectiveTolerance,
    required this.parameterTolerance,
    required this.maximumIterationsPerStart,
  }) : starts = List.unmodifiable(starts);

  final List<Matsuzaki2006NonlinearStart> starts;
  final double initialSimplexStep;
  final double objectiveTolerance;
  final double parameterTolerance;
  final int maximumIterationsPerStart;

  void validate() {
    if (starts.isEmpty) {
      throw ArgumentError.value(starts, 'starts', 'Must not be empty.');
    }
    if (!initialSimplexStep.isFinite || initialSimplexStep <= 0) {
      throw ArgumentError.value(
        initialSimplexStep,
        'initialSimplexStep',
        'Must be finite and positive.',
      );
    }
    if (!objectiveTolerance.isFinite || objectiveTolerance <= 0) {
      throw ArgumentError.value(
        objectiveTolerance,
        'objectiveTolerance',
        'Must be finite and positive.',
      );
    }
    if (!parameterTolerance.isFinite || parameterTolerance <= 0) {
      throw ArgumentError.value(
        parameterTolerance,
        'parameterTolerance',
        'Must be finite and positive.',
      );
    }
    if (maximumIterationsPerStart <= 0) {
      throw ArgumentError.value(
        maximumIterationsPerStart,
        'maximumIterationsPerStart',
        'Must be positive.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'nonlinearParameterization': {
      'x0': 'ln(saturationCoefficient)',
      'x1': 'ln(saturationMagnitudeExponent)',
    },
    'starts': starts.map((start) => start.toJson()).toList(),
    'initialSimplexStep': initialSimplexStep,
    'objectiveTolerance': objectiveTolerance,
    'parameterTolerance': parameterTolerance,
    'maximumIterationsPerStart': maximumIterationsPerStart,
    'numericBounds': null,
  };
}

class Matsuzaki2006PositiveParameterSearchSpec {
  Matsuzaki2006PositiveParameterSearchSpec({
    required List<double> starts,
    required this.initialSimplexStep,
    required this.objectiveTolerance,
    required this.parameterTolerance,
    required this.maximumIterationsPerStart,
  }) : starts = List.unmodifiable(starts);

  final List<double> starts;
  final double initialSimplexStep;
  final double objectiveTolerance;
  final double parameterTolerance;
  final int maximumIterationsPerStart;

  void validate() {
    if (starts.isEmpty ||
        starts.any((value) => !value.isFinite || value <= 0)) {
      throw ArgumentError.value(
        starts,
        'starts',
        'Must contain finite positive values.',
      );
    }
    if (!initialSimplexStep.isFinite || initialSimplexStep <= 0) {
      throw ArgumentError.value(
        initialSimplexStep,
        'initialSimplexStep',
        'Must be finite and positive.',
      );
    }
    if (!objectiveTolerance.isFinite || objectiveTolerance <= 0) {
      throw ArgumentError.value(
        objectiveTolerance,
        'objectiveTolerance',
        'Must be finite and positive.',
      );
    }
    if (!parameterTolerance.isFinite || parameterTolerance <= 0) {
      throw ArgumentError.value(
        parameterTolerance,
        'parameterTolerance',
        'Must be finite and positive.',
      );
    }
    if (maximumIterationsPerStart <= 0) {
      throw ArgumentError.value(
        maximumIterationsPerStart,
        'maximumIterationsPerStart',
        'Must be positive.',
      );
    }
  }

  Map<String, Object?> toJson({required String parameterName}) => {
    'parameter': parameterName,
    'parameterization': 'ln($parameterName)',
    'starts': starts,
    'initialSimplexStep': initialSimplexStep,
    'objectiveTolerance': objectiveTolerance,
    'parameterTolerance': parameterTolerance,
    'maximumIterationsPerStart': maximumIterationsPerStart,
    'numericBounds': null,
  };
}

class Matsuzaki2006CoefficientFit {
  Matsuzaki2006CoefficientFit({
    required this.method,
    required this.coefficients,
    required this.trainingObjective,
    required this.converged,
    required this.bestStartIndex,
    required this.iterations,
    required this.objectiveEvaluations,
    required Map<String, Object> parameterPolicy,
    required List<Matsuzaki2006CalibrationRun> nonlinearRuns,
  }) : parameterPolicy = Map.unmodifiable(parameterPolicy),
       nonlinearRuns = List.unmodifiable(nonlinearRuns);

  final Matsuzaki2006CalibrationMethod method;
  final Matsuzaki2006AttenuationCoefficients coefficients;
  final double trainingObjective;
  final bool converged;
  final int bestStartIndex;
  final int iterations;
  final int objectiveEvaluations;
  final Map<String, Object> parameterPolicy;
  final List<Matsuzaki2006CalibrationRun> nonlinearRuns;

  double get saturationChangeFactorAcrossMagnitudeRange => math
      .pow(
        10,
        coefficients.saturationMagnitudeExponent *
            (Matsuzaki2006AttenuationModel.maximumMagnitude -
                Matsuzaki2006AttenuationModel.minimumMagnitude),
      )
      .toDouble();

  double get saturationDistanceAtMinimumMagnitudeKm =>
      _saturationDistanceAtMagnitude(
        Matsuzaki2006AttenuationModel.minimumMagnitude,
      );

  double get saturationDistanceAtMaximumMagnitudeKm =>
      _saturationDistanceAtMagnitude(
        Matsuzaki2006AttenuationModel.maximumMagnitude,
      );

  double _saturationDistanceAtMagnitude(double magnitude) =>
      coefficients.saturationCoefficient *
      math
          .pow(10, coefficients.saturationMagnitudeExponent * magnitude)
          .toDouble();

  Map<String, Object> toJson() => {
    'method': method.name,
    'coefficients': coefficients.toJson(),
    'trainingObjective': trainingObjective,
    'trainingObjectiveDefinition': switch (method) {
      Matsuzaki2006CalibrationMethod.globalStationWeighted =>
        'station_weighted_mean_squared_intensity_residual',
      Matsuzaki2006CalibrationMethod.eventSourceStripped =>
        'event_equal_within_event_centered_mean_squared_intensity_residual',
      Matsuzaki2006CalibrationMethod.eventSourceStrippedDistanceBalanced =>
        'event_equal_distance_group_balanced_centered_mean_squared_intensity_residual',
      Matsuzaki2006CalibrationMethod.eventSourceStrippedFixedSaturation =>
        'event_equal_fixed_saturation_centered_mean_squared_intensity_residual',
      Matsuzaki2006CalibrationMethod.globalFixedSaturation ||
      Matsuzaki2006CalibrationMethod.globalFixedExponent ||
      Matsuzaki2006CalibrationMethod.globalFixedCoefficient =>
        'station_weighted_mean_squared_intensity_residual',
    },
    'parameterPolicy': parameterPolicy,
    'converged': converged,
    'bestStartIndex': bestStartIndex,
    'iterations': iterations,
    'objectiveEvaluations': objectiveEvaluations,
    'saturationChangeFactorAcrossMagnitudeRange':
        saturationChangeFactorAcrossMagnitudeRange,
    'saturationDistanceAtMinimumMagnitudeKm':
        saturationDistanceAtMinimumMagnitudeKm,
    'saturationDistanceAtMaximumMagnitudeKm':
        saturationDistanceAtMaximumMagnitudeKm,
    'nonlinearRuns': nonlinearRuns.map((run) => run.toJson()).toList(),
  };
}

class Matsuzaki2006CalibrationRun {
  const Matsuzaki2006CalibrationRun({
    required this.startIndex,
    required this.start,
    required this.finalSaturationCoefficient,
    required this.finalSaturationMagnitudeExponent,
    required this.objective,
    required this.converged,
    required this.iterations,
    required this.objectiveEvaluations,
  });

  final int startIndex;
  final Matsuzaki2006NonlinearStart start;
  final double finalSaturationCoefficient;
  final double finalSaturationMagnitudeExponent;
  final double objective;
  final bool converged;
  final int iterations;
  final int objectiveEvaluations;

  Map<String, Object> toJson() => {
    'startIndex': startIndex,
    'start': start.toJson(),
    'finalSaturationCoefficient': finalSaturationCoefficient,
    'finalSaturationMagnitudeExponent': finalSaturationMagnitudeExponent,
    'objective': objective,
    'converged': converged,
    'iterations': iterations,
    'objectiveEvaluations': objectiveEvaluations,
  };
}

class Matsuzaki2006ModelEvaluation {
  Matsuzaki2006ModelEvaluation({
    required this.coefficients,
    required List<Matsuzaki2006EventBaseline> events,
  }) : events = List.unmodifiable(_evaluateEvents(coefficients, events));

  final Matsuzaki2006AttenuationCoefficients coefficients;
  final List<Matsuzaki2006EventBaseline> events;

  int get stationCount =>
      events.fold(0, (sum, event) => sum + event.stationResiduals.length);

  Matsuzaki2006ResidualSummary get stationWeightedSummary =>
      Matsuzaki2006ResidualSummary.fromResiduals(
        events.expand(
          (event) => event.stationResiduals.map((station) => station.residual),
        ),
      );

  Map<String, Object> get eventEqualMetrics {
    if (events.isEmpty) {
      return const {
        'eventCount': 0,
        'meanOfEventMeanResiduals': 0.0,
        'meanOfEventMeanAbsoluteResiduals': 0.0,
        'meanOfEventRootMeanSquareResiduals': 0.0,
      };
    }
    return {
      'eventCount': events.length,
      'meanOfEventMeanResiduals': _mean(
        events.map((event) => event.residualSummary.meanResidual),
      ),
      'meanOfEventMeanAbsoluteResiduals': _mean(
        events.map((event) => event.residualSummary.meanAbsoluteResidual),
      ),
      'meanOfEventRootMeanSquareResiduals': _mean(
        events.map((event) => event.residualSummary.rootMeanSquareResidual),
      ),
    };
  }

  Map<String, Matsuzaki2006ResidualSummary> get byDistanceBand =>
      _groupedSummary(
        (event, station) => _distanceBand(station.sourceDistanceKm),
      );

  Map<String, Matsuzaki2006ResidualSummary> get byDepthBand =>
      _groupedSummary((event, station) => _depthBand(event.depthKm));

  Map<String, Matsuzaki2006ResidualSummary> get byMagnitudeBand =>
      _groupedSummary((event, station) => _magnitudeBand(event.magnitude));

  Map<String, Object> toJson() => {
    'eventCount': events.length,
    'stationCount': stationCount,
    'stationWeighted': stationWeightedSummary.toJson(),
    'eventEqual': eventEqualMetrics,
    'byDistanceBand': _summariesToJson(byDistanceBand),
    'byDepthBand': _summariesToJson(byDepthBand),
    'byMagnitudeBand': _summariesToJson(byMagnitudeBand),
  };

  Map<String, Matsuzaki2006ResidualSummary> _groupedSummary(
    String Function(
      Matsuzaki2006EventBaseline event,
      Matsuzaki2006StationResidual station,
    )
    keyFor,
  ) {
    final residuals = <String, List<double>>{};
    for (final event in events) {
      for (final station in event.stationResiduals) {
        residuals
            .putIfAbsent(keyFor(event, station), () => <double>[])
            .add(station.residual);
      }
    }
    final keys = residuals.keys.toList()..sort();
    return {
      for (final key in keys)
        key: Matsuzaki2006ResidualSummary.fromResiduals(residuals[key]!),
    };
  }

  static List<Matsuzaki2006EventBaseline> _evaluateEvents(
    Matsuzaki2006AttenuationCoefficients coefficients,
    List<Matsuzaki2006EventBaseline> events,
  ) {
    final model = Matsuzaki2006AttenuationModel(coefficients: coefficients);
    return [
      for (final event in events)
        Matsuzaki2006EventBaseline(
          eventId: event.eventId,
          year: event.year,
          originTime: event.originTime,
          latitude: event.latitude,
          longitude: event.longitude,
          depthKm: event.depthKm,
          magnitude: event.magnitude,
          magnitudeType: event.magnitudeType,
          maximumIntensityClass: event.maximumIntensityClass,
          determinationFlag: event.determinationFlag,
          stationResiduals: [
            for (final station in event.stationResiduals)
              Matsuzaki2006StationResidual(
                stationId: station.stationId,
                latitude: station.latitude,
                longitude: station.longitude,
                sourceDistanceKm: station.sourceDistanceKm,
                observedIntensity: station.observedIntensity,
                predictedIntensity: model.predictIntensity(
                  magnitude: event.magnitude,
                  sourceDistanceKm: station.sourceDistanceKm,
                  depthKm: event.depthKm,
                ),
              ),
          ],
        ),
    ];
  }

  static Map<String, Object> _summariesToJson(
    Map<String, Matsuzaki2006ResidualSummary> values,
  ) => {for (final entry in values.entries) entry.key: entry.value.toJson()};

  static String _distanceBand(double distanceKm) {
    if (distanceKm < 15) return '1-<15 km';
    if (distanceKm < 30) return '15-<30 km';
    if (distanceKm < 100) return '30-<100 km';
    return '100-500 km';
  }

  static String _depthBand(double depthKm) {
    if (depthKm < 30) return '0-<30 km';
    if (depthKm < 100) return '30-<100 km';
    return '100-183 km';
  }

  static String _magnitudeBand(double magnitude) {
    if (magnitude < 5.5) return '5.0-<5.5';
    if (magnitude < 6.0) return '5.5-<6.0';
    if (magnitude < 6.5) return '6.0-<6.5';
    if (magnitude < 7.0) return '6.5-<7.0';
    return '7.0-8.2';
  }

  static double _mean(Iterable<double> values) {
    var count = 0;
    var sum = 0.0;
    for (final value in values) {
      count++;
      sum += value;
    }
    return count == 0 ? 0 : sum / count;
  }
}

class Matsuzaki2006CoefficientCalibrator {
  const Matsuzaki2006CoefficientCalibrator();

  Matsuzaki2006CoefficientFit fitGlobalStationWeighted({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required Matsuzaki2006CalibrationSearchSpec searchSpec,
  }) {
    _validateTrainingEvents(trainingEvents);
    searchSpec.validate();
    final optimization = _optimizeNonlinear(searchSpec, (
      logSaturationCoefficient,
      logSaturationMagnitudeExponent,
    ) {
      final nonlinear = _nonlinearValues(
        logSaturationCoefficient,
        logSaturationMagnitudeExponent,
      );
      if (nonlinear == null) return double.infinity;
      return _globalLinearFit(
            trainingEvents,
            nonlinear.$1,
            nonlinear.$2,
          )?.meanSquaredResidual ??
          double.infinity;
    });
    final nonlinear = _nonlinearValues(
      optimization.point.$1,
      optimization.point.$2,
    )!;
    final linear = _globalLinearFit(trainingEvents, nonlinear.$1, nonlinear.$2);
    if (linear == null) {
      throw StateError('Global coefficient fit became singular.');
    }
    return Matsuzaki2006CoefficientFit(
      method: Matsuzaki2006CalibrationMethod.globalStationWeighted,
      coefficients: Matsuzaki2006AttenuationCoefficients(
        magnitudeCoefficient: linear.coefficients[0],
        logDistanceCoefficient: linear.coefficients[1],
        saturationCoefficient: nonlinear.$1,
        saturationMagnitudeExponent: nonlinear.$2,
        depthCoefficient: linear.coefficients[2],
        intercept: linear.coefficients[3],
      ),
      trainingObjective: linear.meanSquaredResidual,
      converged: optimization.converged,
      bestStartIndex: optimization.bestStartIndex,
      iterations: optimization.iterations,
      objectiveEvaluations: optimization.objectiveEvaluations,
      parameterPolicy: {
        'linearCoefficients': 'fitted_station_weighted_least_squares',
        'saturationCoefficient': 'optimized_positive_unbounded',
        'saturationMagnitudeExponent': 'optimized_positive_unbounded',
      },
      nonlinearRuns: optimization.runs,
    );
  }

  Matsuzaki2006CoefficientFit fitEventSourceStripped({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required Matsuzaki2006CalibrationSearchSpec searchSpec,
    List<Matsuzaki2006EventBaseline>? sourceTermEvents,
  }) {
    _validateTrainingEvents(trainingEvents);
    if (sourceTermEvents != null) {
      _validateTrainingEvents(sourceTermEvents);
    }
    searchSpec.validate();
    final optimization = _optimizeNonlinear(searchSpec, (
      logSaturationCoefficient,
      logSaturationMagnitudeExponent,
    ) {
      final nonlinear = _nonlinearValues(
        logSaturationCoefficient,
        logSaturationMagnitudeExponent,
      );
      if (nonlinear == null) return double.infinity;
      return _withinEventDistanceFit(
            trainingEvents,
            nonlinear.$1,
            nonlinear.$2,
          )?.meanSquaredResidual ??
          double.infinity;
    });
    final nonlinear = _nonlinearValues(
      optimization.point.$1,
      optimization.point.$2,
    )!;
    final distanceFit = _withinEventDistanceFit(
      trainingEvents,
      nonlinear.$1,
      nonlinear.$2,
    );
    if (distanceFit == null) {
      throw StateError('Within-event distance fit became singular.');
    }
    final sourceFit = _eventMeanSourceFit(
      sourceTermEvents ?? trainingEvents,
      nonlinear.$1,
      nonlinear.$2,
      distanceFit.logDistanceCoefficient,
    );
    if (sourceFit == null) {
      throw StateError('Event-mean source fit became singular.');
    }
    return Matsuzaki2006CoefficientFit(
      method: Matsuzaki2006CalibrationMethod.eventSourceStripped,
      coefficients: Matsuzaki2006AttenuationCoefficients(
        magnitudeCoefficient: sourceFit[0],
        logDistanceCoefficient: distanceFit.logDistanceCoefficient,
        saturationCoefficient: nonlinear.$1,
        saturationMagnitudeExponent: nonlinear.$2,
        depthCoefficient: sourceFit[1],
        intercept: sourceFit[2],
      ),
      trainingObjective: distanceFit.meanSquaredResidual,
      converged: optimization.converged,
      bestStartIndex: optimization.bestStartIndex,
      iterations: optimization.iterations,
      objectiveEvaluations: optimization.objectiveEvaluations,
      parameterPolicy: {
        'distanceShape': 'fitted_after_within_event_centering',
        'eventTerms': 'fitted_from_event_means',
        'eventTermSource': sourceTermEvents == null
            ? 'distance_shape_events'
            : 'separate_source_term_events',
        'saturationCoefficient': 'optimized_positive_unbounded',
        'saturationMagnitudeExponent': 'optimized_positive_unbounded',
      },
      nonlinearRuns: optimization.runs,
    );
  }

  Matsuzaki2006CoefficientFit fitEventSourceStrippedDistanceBalanced({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required Matsuzaki2006CalibrationSearchSpec searchSpec,
    required Matsuzaki2006DistanceBalanceSpec balanceSpec,
    List<Matsuzaki2006EventBaseline>? sourceTermEvents,
  }) {
    _validateTrainingEvents(trainingEvents);
    if (sourceTermEvents != null) {
      _validateTrainingEvents(sourceTermEvents);
    }
    searchSpec.validate();
    balanceSpec.validate();
    final optimization = _optimizeNonlinear(searchSpec, (
      logSaturationCoefficient,
      logSaturationMagnitudeExponent,
    ) {
      final nonlinear = _nonlinearValues(
        logSaturationCoefficient,
        logSaturationMagnitudeExponent,
      );
      if (nonlinear == null) return double.infinity;
      return _distanceBalancedWithinEventFit(
            trainingEvents,
            nonlinear.$1,
            nonlinear.$2,
            balanceSpec,
          )?.meanSquaredResidual ??
          double.infinity;
    });
    final nonlinear = _nonlinearValues(
      optimization.point.$1,
      optimization.point.$2,
    )!;
    final distanceFit = _distanceBalancedWithinEventFit(
      trainingEvents,
      nonlinear.$1,
      nonlinear.$2,
      balanceSpec,
    );
    if (distanceFit == null) {
      throw StateError('Distance-balanced within-event fit became singular.');
    }
    final sourceFit = _distanceBalancedEventMeanSourceFit(
      sourceTermEvents ?? trainingEvents,
      nonlinear.$1,
      nonlinear.$2,
      distanceFit.logDistanceCoefficient,
      balanceSpec,
    );
    if (sourceFit == null) {
      throw StateError('Distance-balanced event-mean fit became singular.');
    }
    return Matsuzaki2006CoefficientFit(
      method:
          Matsuzaki2006CalibrationMethod.eventSourceStrippedDistanceBalanced,
      coefficients: Matsuzaki2006AttenuationCoefficients(
        magnitudeCoefficient: sourceFit[0],
        logDistanceCoefficient: distanceFit.logDistanceCoefficient,
        saturationCoefficient: nonlinear.$1,
        saturationMagnitudeExponent: nonlinear.$2,
        depthCoefficient: sourceFit[1],
        intercept: sourceFit[2],
      ),
      trainingObjective: distanceFit.meanSquaredResidual,
      converged: optimization.converged,
      bestStartIndex: optimization.bestStartIndex,
      iterations: optimization.iterations,
      objectiveEvaluations: optimization.objectiveEvaluations,
      parameterPolicy: {
        'distanceShape': 'fitted_after_weighted_within_event_centering',
        'eventTerms': 'fitted_from_weighted_event_means',
        'eventTermSource': sourceTermEvents == null
            ? 'distance_shape_events'
            : 'separate_source_term_events',
        'saturationCoefficient': 'optimized_positive_unbounded',
        'saturationMagnitudeExponent': 'optimized_positive_unbounded',
        'distanceBalance': balanceSpec.toJson(),
      },
      nonlinearRuns: optimization.runs,
    );
  }

  Matsuzaki2006CoefficientFit fitEventSourceStrippedWithFixedSaturation({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required double saturationCoefficient,
    required double saturationMagnitudeExponent,
    List<Matsuzaki2006EventBaseline>? sourceTermEvents,
    Matsuzaki2006DistanceBalanceSpec? balanceSpec,
  }) {
    _validateTrainingEvents(trainingEvents);
    if (sourceTermEvents != null) {
      _validateTrainingEvents(sourceTermEvents);
    }
    _validatePositiveParameter(saturationCoefficient, 'saturationCoefficient');
    _validatePositiveParameter(
      saturationMagnitudeExponent,
      'saturationMagnitudeExponent',
    );
    balanceSpec?.validate();

    final distanceFit = balanceSpec == null
        ? _withinEventDistanceFit(
            trainingEvents,
            saturationCoefficient,
            saturationMagnitudeExponent,
          )
        : _distanceBalancedWithinEventFit(
            trainingEvents,
            saturationCoefficient,
            saturationMagnitudeExponent,
            balanceSpec,
          );
    if (distanceFit == null) {
      throw StateError('Fixed-saturation distance fit became singular.');
    }

    final sourceEvents = sourceTermEvents ?? trainingEvents;
    final sourceFit = balanceSpec == null
        ? _eventMeanSourceFit(
            sourceEvents,
            saturationCoefficient,
            saturationMagnitudeExponent,
            distanceFit.logDistanceCoefficient,
          )
        : _distanceBalancedEventMeanSourceFit(
            sourceEvents,
            saturationCoefficient,
            saturationMagnitudeExponent,
            distanceFit.logDistanceCoefficient,
            balanceSpec,
          );
    if (sourceFit == null) {
      throw StateError('Fixed-saturation event-mean fit became singular.');
    }

    return Matsuzaki2006CoefficientFit(
      method: Matsuzaki2006CalibrationMethod.eventSourceStrippedFixedSaturation,
      coefficients: Matsuzaki2006AttenuationCoefficients(
        magnitudeCoefficient: sourceFit[0],
        logDistanceCoefficient: distanceFit.logDistanceCoefficient,
        saturationCoefficient: saturationCoefficient,
        saturationMagnitudeExponent: saturationMagnitudeExponent,
        depthCoefficient: sourceFit[1],
        intercept: sourceFit[2],
      ),
      trainingObjective: distanceFit.meanSquaredResidual,
      converged: true,
      bestStartIndex: -1,
      iterations: 0,
      objectiveEvaluations: 1,
      parameterPolicy: {
        'distanceShape': balanceSpec == null
            ? 'fitted_after_within_event_centering'
            : 'fitted_after_weighted_within_event_centering',
        'eventTerms': balanceSpec == null
            ? 'fitted_from_event_means'
            : 'fitted_from_weighted_event_means',
        'eventTermSource': sourceTermEvents == null
            ? 'distance_shape_events'
            : 'separate_source_term_events',
        'saturationCoefficient': 'fixed:$saturationCoefficient',
        'saturationMagnitudeExponent': 'fixed:$saturationMagnitudeExponent',
        if (balanceSpec != null) 'distanceBalance': balanceSpec.toJson(),
      },
      nonlinearRuns: const [],
    );
  }

  Matsuzaki2006CoefficientFit fitGlobalWithFixedSaturation({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required double saturationCoefficient,
    required double saturationMagnitudeExponent,
  }) {
    _validateTrainingEvents(trainingEvents);
    _validatePositiveParameter(saturationCoefficient, 'saturationCoefficient');
    _validatePositiveParameter(
      saturationMagnitudeExponent,
      'saturationMagnitudeExponent',
    );
    final linear = _globalLinearFit(
      trainingEvents,
      saturationCoefficient,
      saturationMagnitudeExponent,
    );
    if (linear == null) {
      throw StateError('Fixed-saturation linear fit became singular.');
    }
    return _globalFitResult(
      method: Matsuzaki2006CalibrationMethod.globalFixedSaturation,
      linear: linear,
      saturationCoefficient: saturationCoefficient,
      saturationMagnitudeExponent: saturationMagnitudeExponent,
      converged: true,
      bestStartIndex: -1,
      iterations: 0,
      objectiveEvaluations: 1,
      parameterPolicy: {
        'linearCoefficients': 'fitted_station_weighted_least_squares',
        'saturationCoefficient': 'fixed:$saturationCoefficient',
        'saturationMagnitudeExponent': 'fixed:$saturationMagnitudeExponent',
      },
      nonlinearRuns: const [],
    );
  }

  Matsuzaki2006CoefficientFit fitGlobalWithFixedExponent({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required double saturationMagnitudeExponent,
    required Matsuzaki2006PositiveParameterSearchSpec coefficientSearchSpec,
  }) {
    _validateTrainingEvents(trainingEvents);
    _validatePositiveParameter(
      saturationMagnitudeExponent,
      'saturationMagnitudeExponent',
    );
    coefficientSearchSpec.validate();
    final optimization = _optimizePositiveParameter(
      coefficientSearchSpec,
      (saturationCoefficient) =>
          _globalLinearFit(
            trainingEvents,
            saturationCoefficient,
            saturationMagnitudeExponent,
          )?.meanSquaredResidual ??
          double.infinity,
    );
    final linear = _globalLinearFit(
      trainingEvents,
      optimization.value,
      saturationMagnitudeExponent,
    );
    if (linear == null) {
      throw StateError('Fixed-exponent global fit became singular.');
    }
    return _globalFitResult(
      method: Matsuzaki2006CalibrationMethod.globalFixedExponent,
      linear: linear,
      saturationCoefficient: optimization.value,
      saturationMagnitudeExponent: saturationMagnitudeExponent,
      converged: optimization.converged,
      bestStartIndex: optimization.bestStartIndex,
      iterations: optimization.iterations,
      objectiveEvaluations: optimization.objectiveEvaluations,
      parameterPolicy: {
        'linearCoefficients': 'fitted_station_weighted_least_squares',
        'saturationCoefficient': 'optimized_positive_unbounded',
        'saturationMagnitudeExponent': 'fixed:$saturationMagnitudeExponent',
      },
      nonlinearRuns: [
        for (final run in optimization.runs)
          Matsuzaki2006CalibrationRun(
            startIndex: run.startIndex,
            start: Matsuzaki2006NonlinearStart(
              saturationCoefficient: run.start,
              saturationMagnitudeExponent: saturationMagnitudeExponent,
            ),
            finalSaturationCoefficient: run.value,
            finalSaturationMagnitudeExponent: saturationMagnitudeExponent,
            objective: run.objective,
            converged: run.converged,
            iterations: run.iterations,
            objectiveEvaluations: run.objectiveEvaluations,
          ),
      ],
    );
  }

  Matsuzaki2006CoefficientFit fitGlobalWithFixedCoefficient({
    required List<Matsuzaki2006EventBaseline> trainingEvents,
    required double saturationCoefficient,
    required Matsuzaki2006PositiveParameterSearchSpec exponentSearchSpec,
  }) {
    _validateTrainingEvents(trainingEvents);
    _validatePositiveParameter(saturationCoefficient, 'saturationCoefficient');
    exponentSearchSpec.validate();
    final optimization = _optimizePositiveParameter(
      exponentSearchSpec,
      (saturationMagnitudeExponent) =>
          _globalLinearFit(
            trainingEvents,
            saturationCoefficient,
            saturationMagnitudeExponent,
          )?.meanSquaredResidual ??
          double.infinity,
    );
    final linear = _globalLinearFit(
      trainingEvents,
      saturationCoefficient,
      optimization.value,
    );
    if (linear == null) {
      throw StateError('Fixed-coefficient global fit became singular.');
    }
    return _globalFitResult(
      method: Matsuzaki2006CalibrationMethod.globalFixedCoefficient,
      linear: linear,
      saturationCoefficient: saturationCoefficient,
      saturationMagnitudeExponent: optimization.value,
      converged: optimization.converged,
      bestStartIndex: optimization.bestStartIndex,
      iterations: optimization.iterations,
      objectiveEvaluations: optimization.objectiveEvaluations,
      parameterPolicy: {
        'linearCoefficients': 'fitted_station_weighted_least_squares',
        'saturationCoefficient': 'fixed:$saturationCoefficient',
        'saturationMagnitudeExponent': 'optimized_positive_unbounded',
      },
      nonlinearRuns: [
        for (final run in optimization.runs)
          Matsuzaki2006CalibrationRun(
            startIndex: run.startIndex,
            start: Matsuzaki2006NonlinearStart(
              saturationCoefficient: saturationCoefficient,
              saturationMagnitudeExponent: run.start,
            ),
            finalSaturationCoefficient: saturationCoefficient,
            finalSaturationMagnitudeExponent: run.value,
            objective: run.objective,
            converged: run.converged,
            iterations: run.iterations,
            objectiveEvaluations: run.objectiveEvaluations,
          ),
      ],
    );
  }

  Matsuzaki2006CoefficientFit _globalFitResult({
    required Matsuzaki2006CalibrationMethod method,
    required _LinearFit linear,
    required double saturationCoefficient,
    required double saturationMagnitudeExponent,
    required bool converged,
    required int bestStartIndex,
    required int iterations,
    required int objectiveEvaluations,
    required Map<String, Object> parameterPolicy,
    required List<Matsuzaki2006CalibrationRun> nonlinearRuns,
  }) => Matsuzaki2006CoefficientFit(
    method: method,
    coefficients: Matsuzaki2006AttenuationCoefficients(
      magnitudeCoefficient: linear.coefficients[0],
      logDistanceCoefficient: linear.coefficients[1],
      saturationCoefficient: saturationCoefficient,
      saturationMagnitudeExponent: saturationMagnitudeExponent,
      depthCoefficient: linear.coefficients[2],
      intercept: linear.coefficients[3],
    ),
    trainingObjective: linear.meanSquaredResidual,
    converged: converged,
    bestStartIndex: bestStartIndex,
    iterations: iterations,
    objectiveEvaluations: objectiveEvaluations,
    parameterPolicy: parameterPolicy,
    nonlinearRuns: nonlinearRuns,
  );

  _PositiveOptimizationResult _optimizePositiveParameter(
    Matsuzaki2006PositiveParameterSearchSpec spec,
    double Function(double) objective,
  ) {
    _PositiveOptimizationResult? best;
    final runs = <_PositiveOptimizationRun>[];
    var totalEvaluations = 0;
    for (var index = 0; index < spec.starts.length; index++) {
      final start = spec.starts[index];
      final result = _nelderMead1d(
        start: math.log(start),
        initialStep: spec.initialSimplexStep,
        objectiveTolerance: spec.objectiveTolerance,
        parameterTolerance: spec.parameterTolerance,
        maximumIterations: spec.maximumIterationsPerStart,
        objective: (logValue) {
          final value = math.exp(logValue);
          return value.isFinite ? objective(value) : double.infinity;
        },
      );
      final finalValue = math.exp(result.point);
      totalEvaluations += result.objectiveEvaluations;
      runs.add(
        _PositiveOptimizationRun(
          startIndex: index,
          start: start,
          value: finalValue,
          objective: result.objective,
          converged: result.converged,
          iterations: result.iterations,
          objectiveEvaluations: result.objectiveEvaluations,
        ),
      );
      if (best == null || result.objective < best.objective) {
        best = _PositiveOptimizationResult(
          value: finalValue,
          objective: result.objective,
          converged: result.converged,
          bestStartIndex: index,
          iterations: result.iterations,
          objectiveEvaluations: 0,
          runs: const [],
        );
      }
    }
    if (best == null || !best.objective.isFinite) {
      throw StateError('Every one-dimensional calibration start failed.');
    }
    return _PositiveOptimizationResult(
      value: best.value,
      objective: best.objective,
      converged: best.converged,
      bestStartIndex: best.bestStartIndex,
      iterations: best.iterations,
      objectiveEvaluations: totalEvaluations,
      runs: runs,
    );
  }

  _OptimizationResult _optimizeNonlinear(
    Matsuzaki2006CalibrationSearchSpec spec,
    double Function(double, double) objective,
  ) {
    _OptimizationResult? best;
    var totalEvaluations = 0;
    final runs = <Matsuzaki2006CalibrationRun>[];
    for (var index = 0; index < spec.starts.length; index++) {
      final start = spec.starts[index];
      final result = _nelderMead2d(
        start: (
          math.log(start.saturationCoefficient),
          math.log(start.saturationMagnitudeExponent),
        ),
        initialStep: spec.initialSimplexStep,
        objectiveTolerance: spec.objectiveTolerance,
        parameterTolerance: spec.parameterTolerance,
        maximumIterations: spec.maximumIterationsPerStart,
        objective: objective,
      );
      totalEvaluations += result.objectiveEvaluations;
      final finalValues = _nonlinearValues(result.point.$1, result.point.$2);
      if (finalValues != null) {
        runs.add(
          Matsuzaki2006CalibrationRun(
            startIndex: index,
            start: start,
            finalSaturationCoefficient: finalValues.$1,
            finalSaturationMagnitudeExponent: finalValues.$2,
            objective: result.objective,
            converged: result.converged,
            iterations: result.iterations,
            objectiveEvaluations: result.objectiveEvaluations,
          ),
        );
      }
      if (best == null || result.objective < best.objective) {
        best = _OptimizationResult(
          point: result.point,
          objective: result.objective,
          converged: result.converged,
          bestStartIndex: index,
          iterations: result.iterations,
          objectiveEvaluations: totalEvaluations,
          runs: const [],
        );
      }
    }
    if (best == null || !best.objective.isFinite) {
      throw StateError('Every nonlinear calibration start failed.');
    }
    return _OptimizationResult(
      point: best.point,
      objective: best.objective,
      converged: best.converged,
      bestStartIndex: best.bestStartIndex,
      iterations: best.iterations,
      objectiveEvaluations: totalEvaluations,
      runs: runs,
    );
  }

  _LinearFit? _globalLinearFit(
    List<Matsuzaki2006EventBaseline> events,
    double saturationCoefficient,
    double saturationMagnitudeExponent,
  ) {
    final normal = _WeightedNormalEquations(4);
    for (final event in events) {
      final saturationTerm = _saturationTerm(
        saturationCoefficient,
        saturationMagnitudeExponent,
        event.magnitude,
      );
      if (saturationTerm == null) return null;
      final effectiveDepth = math.min(
        event.depthKm,
        Matsuzaki2006AttenuationModel.formulaDepthCapKm,
      );
      for (final station in event.stationResiduals) {
        final logDistance = _log10(station.sourceDistanceKm + saturationTerm);
        normal.add(
          [event.magnitude, -logDistance, effectiveDepth, 1],
          station.observedIntensity,
          1,
        );
      }
    }
    return normal.solve();
  }

  _WithinEventDistanceFit? _withinEventDistanceFit(
    List<Matsuzaki2006EventBaseline> events,
    double saturationCoefficient,
    double saturationMagnitudeExponent,
  ) {
    var centeredCross = 0.0;
    var centeredLogSquare = 0.0;
    var centeredIntensitySquare = 0.0;
    for (final event in events) {
      final saturationTerm = _saturationTerm(
        saturationCoefficient,
        saturationMagnitudeExponent,
        event.magnitude,
      );
      if (saturationTerm == null) return null;
      var sumIntensity = 0.0;
      var sumLog = 0.0;
      var sumIntensitySquare = 0.0;
      var sumLogSquare = 0.0;
      var sumCross = 0.0;
      for (final station in event.stationResiduals) {
        final intensity = station.observedIntensity;
        final logDistance = _log10(station.sourceDistanceKm + saturationTerm);
        sumIntensity += intensity;
        sumLog += logDistance;
        sumIntensitySquare += intensity * intensity;
        sumLogSquare += logDistance * logDistance;
        sumCross += intensity * logDistance;
      }
      final count = event.stationResiduals.length.toDouble();
      centeredIntensitySquare +=
          (sumIntensitySquare - sumIntensity * sumIntensity / count) / count;
      centeredLogSquare += (sumLogSquare - sumLog * sumLog / count) / count;
      centeredCross += (sumCross - sumIntensity * sumLog / count) / count;
    }
    if (centeredLogSquare <= 0 || !centeredLogSquare.isFinite) return null;
    final coefficient = -centeredCross / centeredLogSquare;
    final squaredResidual =
        centeredIntensitySquare +
        2 * coefficient * centeredCross +
        coefficient * coefficient * centeredLogSquare;
    return _WithinEventDistanceFit(
      logDistanceCoefficient: coefficient,
      meanSquaredResidual: math.max(0, squaredResidual / events.length),
    );
  }

  _WithinEventDistanceFit? _distanceBalancedWithinEventFit(
    List<Matsuzaki2006EventBaseline> events,
    double saturationCoefficient,
    double saturationMagnitudeExponent,
    Matsuzaki2006DistanceBalanceSpec balanceSpec,
  ) {
    var centeredCross = 0.0;
    var centeredLogSquare = 0.0;
    var centeredIntensitySquare = 0.0;
    for (final event in events) {
      final saturationTerm = _saturationTerm(
        saturationCoefficient,
        saturationMagnitudeExponent,
        event.magnitude,
      );
      if (saturationTerm == null) return null;
      final weights = _distanceBalancedStationWeights(event, balanceSpec);
      var meanIntensity = 0.0;
      var meanLog = 0.0;
      var intensitySquare = 0.0;
      var logSquare = 0.0;
      var cross = 0.0;
      for (var index = 0; index < event.stationResiduals.length; index++) {
        final station = event.stationResiduals[index];
        final weight = weights[index];
        final intensity = station.observedIntensity;
        final logDistance = _log10(station.sourceDistanceKm + saturationTerm);
        meanIntensity += weight * intensity;
        meanLog += weight * logDistance;
        intensitySquare += weight * intensity * intensity;
        logSquare += weight * logDistance * logDistance;
        cross += weight * intensity * logDistance;
      }
      centeredIntensitySquare +=
          intensitySquare - meanIntensity * meanIntensity;
      centeredLogSquare += logSquare - meanLog * meanLog;
      centeredCross += cross - meanIntensity * meanLog;
    }
    if (centeredLogSquare <= 0 || !centeredLogSquare.isFinite) return null;
    final coefficient = -centeredCross / centeredLogSquare;
    final squaredResidual =
        centeredIntensitySquare +
        2 * coefficient * centeredCross +
        coefficient * coefficient * centeredLogSquare;
    return _WithinEventDistanceFit(
      logDistanceCoefficient: coefficient,
      meanSquaredResidual: math.max(0, squaredResidual / events.length),
    );
  }

  List<double>? _distanceBalancedEventMeanSourceFit(
    List<Matsuzaki2006EventBaseline> events,
    double saturationCoefficient,
    double saturationMagnitudeExponent,
    double logDistanceCoefficient,
    Matsuzaki2006DistanceBalanceSpec balanceSpec,
  ) {
    final normal = _WeightedNormalEquations(3);
    for (final event in events) {
      final saturationTerm = _saturationTerm(
        saturationCoefficient,
        saturationMagnitudeExponent,
        event.magnitude,
      );
      if (saturationTerm == null) return null;
      final weights = _distanceBalancedStationWeights(event, balanceSpec);
      var adjustedMean = 0.0;
      for (var index = 0; index < event.stationResiduals.length; index++) {
        final station = event.stationResiduals[index];
        adjustedMean +=
            weights[index] *
            (station.observedIntensity +
                logDistanceCoefficient *
                    _log10(station.sourceDistanceKm + saturationTerm));
      }
      normal.add(
        [
          event.magnitude,
          math.min(
            event.depthKm,
            Matsuzaki2006AttenuationModel.formulaDepthCapKm,
          ),
          1,
        ],
        adjustedMean,
        1,
      );
    }
    return normal.solve()?.coefficients;
  }

  List<double> _distanceBalancedStationWeights(
    Matsuzaki2006EventBaseline event,
    Matsuzaki2006DistanceBalanceSpec balanceSpec,
  ) {
    final nearCount = event.stationResiduals
        .where(
          (station) =>
              station.sourceDistanceKm < balanceSpec.nearDistanceThresholdKm,
        )
        .length;
    final farCount = event.stationResiduals.length - nearCount;
    if (nearCount == 0 || farCount == 0) {
      final weight = 1 / event.stationResiduals.length;
      return List<double>.filled(event.stationResiduals.length, weight);
    }
    final nearWeight = balanceSpec.nearGroupWeight / nearCount;
    final farWeight = (1 - balanceSpec.nearGroupWeight) / farCount;
    return [
      for (final station in event.stationResiduals)
        station.sourceDistanceKm < balanceSpec.nearDistanceThresholdKm
            ? nearWeight
            : farWeight,
    ];
  }

  List<double>? _eventMeanSourceFit(
    List<Matsuzaki2006EventBaseline> events,
    double saturationCoefficient,
    double saturationMagnitudeExponent,
    double logDistanceCoefficient,
  ) {
    final normal = _WeightedNormalEquations(3);
    for (final event in events) {
      final saturationTerm = _saturationTerm(
        saturationCoefficient,
        saturationMagnitudeExponent,
        event.magnitude,
      );
      if (saturationTerm == null) return null;
      var adjustedIntensitySum = 0.0;
      for (final station in event.stationResiduals) {
        adjustedIntensitySum +=
            station.observedIntensity +
            logDistanceCoefficient *
                _log10(station.sourceDistanceKm + saturationTerm);
      }
      final adjustedMean = adjustedIntensitySum / event.stationResiduals.length;
      normal.add(
        [
          event.magnitude,
          math.min(
            event.depthKm,
            Matsuzaki2006AttenuationModel.formulaDepthCapKm,
          ),
          1,
        ],
        adjustedMean,
        1,
      );
    }
    return normal.solve()?.coefficients;
  }

  static (double, double)? _nonlinearValues(
    double logSaturationCoefficient,
    double logSaturationMagnitudeExponent,
  ) {
    final coefficient = math.exp(logSaturationCoefficient);
    final exponent = math.exp(logSaturationMagnitudeExponent);
    if (!coefficient.isFinite || !exponent.isFinite) return null;
    return (coefficient, exponent);
  }

  static double? _saturationTerm(
    double coefficient,
    double exponent,
    double magnitude,
  ) {
    final value = coefficient * math.exp(math.ln10 * exponent * magnitude);
    return value.isFinite ? value : null;
  }

  static void _validateTrainingEvents(List<Matsuzaki2006EventBaseline> events) {
    if (events.isEmpty) {
      throw ArgumentError.value(events, 'trainingEvents', 'Must not be empty.');
    }
    if (events.any((event) => event.stationResiduals.isEmpty)) {
      throw ArgumentError.value(
        events,
        'trainingEvents',
        'Every event must contain at least one station.',
      );
    }
  }

  static void _validatePositiveParameter(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Must be finite and positive.');
    }
  }

  static double _log10(double value) => math.log(value) / math.ln10;
}

class _WeightedNormalEquations {
  _WeightedNormalEquations(this.dimension)
    : matrix = List.generate(
        dimension,
        (_) => List<double>.filled(dimension, 0),
      ),
      vector = List<double>.filled(dimension, 0);

  final int dimension;
  final List<List<double>> matrix;
  final List<double> vector;
  var weightedTargetSquare = 0.0;
  var totalWeight = 0.0;

  void add(List<double> features, double target, double weight) {
    if (features.length != dimension) {
      throw ArgumentError.value(features.length, 'features.length');
    }
    totalWeight += weight;
    weightedTargetSquare += weight * target * target;
    for (var row = 0; row < dimension; row++) {
      vector[row] += weight * features[row] * target;
      for (var column = 0; column < dimension; column++) {
        matrix[row][column] += weight * features[row] * features[column];
      }
    }
  }

  _LinearFit? solve() {
    if (totalWeight <= 0) return null;
    final scales = [
      for (var index = 0; index < dimension; index++)
        math.sqrt(matrix[index][index]),
    ];
    if (scales.any((scale) => !scale.isFinite || scale <= 0)) return null;
    final scaledMatrix = List.generate(
      dimension,
      (row) => List.generate(
        dimension,
        (column) => matrix[row][column] / (scales[row] * scales[column]),
      ),
    );
    final scaledVector = [
      for (var index = 0; index < dimension; index++)
        vector[index] / scales[index],
    ];
    final scaledCoefficients = _solveLinearSystem(scaledMatrix, scaledVector);
    if (scaledCoefficients == null) return null;
    final coefficients = [
      for (var index = 0; index < dimension; index++)
        scaledCoefficients[index] / scales[index],
    ];
    final explained = List.generate(
      dimension,
      (index) => coefficients[index] * vector[index],
    ).reduce((a, b) => a + b);
    final squaredResidual = math.max(0, weightedTargetSquare - explained);
    return _LinearFit(
      coefficients: coefficients,
      meanSquaredResidual: squaredResidual / totalWeight,
    );
  }

  static List<double>? _solveLinearSystem(
    List<List<double>> inputMatrix,
    List<double> inputVector,
  ) {
    final dimension = inputVector.length;
    final matrix = [
      for (final row in inputMatrix) [...row],
    ];
    final vector = [...inputVector];
    for (var pivot = 0; pivot < dimension; pivot++) {
      var bestRow = pivot;
      var bestValue = matrix[pivot][pivot].abs();
      for (var row = pivot + 1; row < dimension; row++) {
        final value = matrix[row][pivot].abs();
        if (value > bestValue) {
          bestValue = value;
          bestRow = row;
        }
      }
      if (!bestValue.isFinite || bestValue < 1e-12) return null;
      if (bestRow != pivot) {
        final row = matrix[pivot];
        matrix[pivot] = matrix[bestRow];
        matrix[bestRow] = row;
        final value = vector[pivot];
        vector[pivot] = vector[bestRow];
        vector[bestRow] = value;
      }
      for (var row = pivot + 1; row < dimension; row++) {
        final factor = matrix[row][pivot] / matrix[pivot][pivot];
        for (var column = pivot; column < dimension; column++) {
          matrix[row][column] -= factor * matrix[pivot][column];
        }
        vector[row] -= factor * vector[pivot];
      }
    }
    final result = List<double>.filled(dimension, 0);
    for (var row = dimension - 1; row >= 0; row--) {
      var value = vector[row];
      for (var column = row + 1; column < dimension; column++) {
        value -= matrix[row][column] * result[column];
      }
      result[row] = value / matrix[row][row];
      if (!result[row].isFinite) return null;
    }
    return result;
  }
}

class _LinearFit {
  const _LinearFit({
    required this.coefficients,
    required this.meanSquaredResidual,
  });

  final List<double> coefficients;
  final double meanSquaredResidual;
}

class _WithinEventDistanceFit {
  const _WithinEventDistanceFit({
    required this.logDistanceCoefficient,
    required this.meanSquaredResidual,
  });

  final double logDistanceCoefficient;
  final double meanSquaredResidual;
}

class _OptimizationResult {
  _OptimizationResult({
    required this.point,
    required this.objective,
    required this.converged,
    required this.bestStartIndex,
    required this.iterations,
    required this.objectiveEvaluations,
    required List<Matsuzaki2006CalibrationRun> runs,
  }) : runs = List.unmodifiable(runs);

  final (double, double) point;
  final double objective;
  final bool converged;
  final int bestStartIndex;
  final int iterations;
  final int objectiveEvaluations;
  final List<Matsuzaki2006CalibrationRun> runs;
}

class _PositiveOptimizationResult {
  _PositiveOptimizationResult({
    required this.value,
    required this.objective,
    required this.converged,
    required this.bestStartIndex,
    required this.iterations,
    required this.objectiveEvaluations,
    required List<_PositiveOptimizationRun> runs,
  }) : runs = List.unmodifiable(runs);

  final double value;
  final double objective;
  final bool converged;
  final int bestStartIndex;
  final int iterations;
  final int objectiveEvaluations;
  final List<_PositiveOptimizationRun> runs;
}

class _PositiveOptimizationRun {
  const _PositiveOptimizationRun({
    required this.startIndex,
    required this.start,
    required this.value,
    required this.objective,
    required this.converged,
    required this.iterations,
    required this.objectiveEvaluations,
  });

  final int startIndex;
  final double start;
  final double value;
  final double objective;
  final bool converged;
  final int iterations;
  final int objectiveEvaluations;
}

class _OneDimensionalOptimizationResult {
  const _OneDimensionalOptimizationResult({
    required this.point,
    required this.objective,
    required this.converged,
    required this.iterations,
    required this.objectiveEvaluations,
  });

  final double point;
  final double objective;
  final bool converged;
  final int iterations;
  final int objectiveEvaluations;
}

_OneDimensionalOptimizationResult _nelderMead1d({
  required double start,
  required double initialStep,
  required double objectiveTolerance,
  required double parameterTolerance,
  required int maximumIterations,
  required double Function(double) objective,
}) {
  var evaluations = 0;
  double evaluate(double point) {
    evaluations++;
    final value = objective(point);
    return value.isFinite ? value : double.infinity;
  }

  var simplex = <(double, double)>[
    (start, evaluate(start)),
    (start + initialStep, evaluate(start + initialStep)),
  ];
  var converged = false;
  var iterations = 0;
  for (; iterations < maximumIterations; iterations++) {
    simplex.sort((left, right) => left.$2.compareTo(right.$2));
    final best = simplex.first;
    final worst = simplex.last;
    if ((worst.$2 - best.$2) <= objectiveTolerance &&
        (worst.$1 - best.$1).abs() <= parameterTolerance) {
      converged = true;
      break;
    }
    final reflected = 2 * best.$1 - worst.$1;
    final reflectedValue = evaluate(reflected);
    if (reflectedValue < best.$2) {
      final expanded = best.$1 + 2 * (reflected - best.$1);
      final expandedValue = evaluate(expanded);
      simplex[1] = expandedValue < reflectedValue
          ? (expanded, expandedValue)
          : (reflected, reflectedValue);
      continue;
    }
    if (reflectedValue < worst.$2) {
      simplex[1] = (reflected, reflectedValue);
      continue;
    }
    final contracted = best.$1 + 0.5 * (worst.$1 - best.$1);
    final contractedValue = evaluate(contracted);
    if (contractedValue < worst.$2) {
      simplex[1] = (contracted, contractedValue);
      continue;
    }
    final shrunk = best.$1 + 0.5 * (worst.$1 - best.$1);
    simplex[1] = (shrunk, evaluate(shrunk));
  }
  simplex.sort((left, right) => left.$2.compareTo(right.$2));
  return _OneDimensionalOptimizationResult(
    point: simplex.first.$1,
    objective: simplex.first.$2,
    converged: converged,
    iterations: iterations,
    objectiveEvaluations: evaluations,
  );
}

_OptimizationResult _nelderMead2d({
  required (double, double) start,
  required double initialStep,
  required double objectiveTolerance,
  required double parameterTolerance,
  required int maximumIterations,
  required double Function(double, double) objective,
}) {
  var evaluations = 0;
  double evaluate((double, double) point) {
    evaluations++;
    final value = objective(point.$1, point.$2);
    return value.isFinite ? value : double.infinity;
  }

  var simplex = <((double, double), double)>[
    (start, evaluate(start)),
    (
      (start.$1 + initialStep, start.$2),
      evaluate((start.$1 + initialStep, start.$2)),
    ),
    (
      (start.$1, start.$2 + initialStep),
      evaluate((start.$1, start.$2 + initialStep)),
    ),
  ];
  var converged = false;
  var iterations = 0;
  for (; iterations < maximumIterations; iterations++) {
    simplex.sort((left, right) => left.$2.compareTo(right.$2));
    final objectiveSpread = simplex.last.$2 - simplex.first.$2;
    final parameterSpread = math.max(
      _pointDistance(simplex.first.$1, simplex[1].$1),
      _pointDistance(simplex.first.$1, simplex.last.$1),
    );
    if (objectiveSpread <= objectiveTolerance &&
        parameterSpread <= parameterTolerance) {
      converged = true;
      break;
    }
    final best = simplex[0];
    final middle = simplex[1];
    final worst = simplex[2];
    final centroid = (
      (best.$1.$1 + middle.$1.$1) / 2,
      (best.$1.$2 + middle.$1.$2) / 2,
    );
    final reflected = _affinePoint(centroid, worst.$1, -1);
    final reflectedValue = evaluate(reflected);
    if (reflectedValue < best.$2) {
      final expanded = _affinePoint(centroid, reflected, 2);
      final expandedValue = evaluate(expanded);
      simplex[2] = expandedValue < reflectedValue
          ? (expanded, expandedValue)
          : (reflected, reflectedValue);
      continue;
    }
    if (reflectedValue < middle.$2) {
      simplex[2] = (reflected, reflectedValue);
      continue;
    }
    final contractionTarget = reflectedValue < worst.$2 ? reflected : worst.$1;
    final contracted = _affinePoint(centroid, contractionTarget, 0.5);
    final contractedValue = evaluate(contracted);
    if (contractedValue < math.min(reflectedValue, worst.$2)) {
      simplex[2] = (contracted, contractedValue);
      continue;
    }
    final shrunkMiddle = _affinePoint(best.$1, middle.$1, 0.5);
    final shrunkWorst = _affinePoint(best.$1, worst.$1, 0.5);
    simplex = [
      best,
      (shrunkMiddle, evaluate(shrunkMiddle)),
      (shrunkWorst, evaluate(shrunkWorst)),
    ];
  }
  simplex.sort((left, right) => left.$2.compareTo(right.$2));
  return _OptimizationResult(
    point: simplex.first.$1,
    objective: simplex.first.$2,
    converged: converged,
    bestStartIndex: 0,
    iterations: iterations,
    objectiveEvaluations: evaluations,
    runs: const [],
  );
}

(double, double) _affinePoint(
  (double, double) origin,
  (double, double) target,
  double scale,
) => (
  origin.$1 + scale * (target.$1 - origin.$1),
  origin.$2 + scale * (target.$2 - origin.$2),
);

double _pointDistance((double, double) left, (double, double) right) =>
    math.max((left.$1 - right.$1).abs(), (left.$2 - right.$2).abs());
