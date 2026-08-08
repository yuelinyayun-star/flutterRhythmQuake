import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  const published = Matsuzaki2006AttenuationCoefficients.published;
  const model = Matsuzaki2006AttenuationModel(coefficients: published);
  const calibrator = Matsuzaki2006CoefficientCalibrator();
  final events = _syntheticEvents(model);
  final searchSpec = Matsuzaki2006CalibrationSearchSpec(
    starts: const [
      Matsuzaki2006NonlinearStart(
        saturationCoefficient: 0.00675,
        saturationMagnitudeExponent: 0.5,
      ),
    ],
    initialSimplexStep: 0.25,
    objectiveTolerance: 1e-15,
    parameterTolerance: 1e-7,
    maximumIterationsPerStart: 400,
  );
  final coefficientSearchSpec = Matsuzaki2006PositiveParameterSearchSpec(
    starts: const [0.0016875, 0.00675, 0.027],
    initialSimplexStep: 0.5,
    objectiveTolerance: 1e-15,
    parameterTolerance: 1e-7,
    maximumIterationsPerStart: 400,
  );
  final exponentSearchSpec = Matsuzaki2006PositiveParameterSearchSpec(
    starts: const [0.25, 0.5, 1.0],
    initialSimplexStep: 0.5,
    objectiveTolerance: 1e-15,
    parameterTolerance: 1e-7,
    maximumIterationsPerStart: 400,
  );

  test('custom coefficients are used by the forward model', () {
    const custom = Matsuzaki2006AttenuationCoefficients(
      magnitudeCoefficient: 1.1,
      logDistanceCoefficient: 3.2,
      saturationCoefficient: 0.01,
      saturationMagnitudeExponent: 0.4,
      depthCoefficient: -0.002,
      intercept: 1.7,
    );
    const customModel = Matsuzaki2006AttenuationModel(coefficients: custom);

    expect(
      customModel.predictIntensity(
        magnitude: 6,
        sourceDistanceKm: 100,
        depthKm: 20,
      ),
      isNot(
        closeTo(
          model.predictIntensity(
            magnitude: 6,
            sourceDistanceKm: 100,
            depthKm: 20,
          ),
          1e-6,
        ),
      ),
    );
  });

  test('global fit recovers a zero-residual synthetic forward field', () {
    final fit = calibrator.fitGlobalStationWeighted(
      trainingEvents: events,
      searchSpec: searchSpec,
    );
    final evaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: events,
    );

    expect(fit.converged, isTrue);
    expect(fit.trainingObjective, lessThan(1e-12));
    expect(
      evaluation.stationWeightedSummary.rootMeanSquareResidual,
      lessThan(1e-6),
    );
  });

  test('event-source stripping preserves the synthetic distance field', () {
    final fit = calibrator.fitEventSourceStripped(
      trainingEvents: events,
      searchSpec: searchSpec,
    );
    final evaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: events,
    );

    expect(fit.converged, isTrue);
    expect(fit.trainingObjective, lessThan(1e-12));
    expect(
      evaluation.stationWeightedSummary.rootMeanSquareResidual,
      lessThan(1e-6),
    );
    expect(evaluation.byDistanceBand, isNotEmpty);
    expect(evaluation.byDepthBand, isNotEmpty);
    expect(evaluation.byMagnitudeBand, isNotEmpty);
  });

  test('distance-balanced source stripping preserves a synthetic field', () {
    final fit = calibrator.fitEventSourceStrippedDistanceBalanced(
      trainingEvents: events,
      searchSpec: searchSpec,
      balanceSpec: const Matsuzaki2006DistanceBalanceSpec(
        nearDistanceThresholdKm: 30,
        nearGroupWeight: 0.5,
      ),
    );
    final evaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: events,
    );

    expect(
      fit.method,
      Matsuzaki2006CalibrationMethod.eventSourceStrippedDistanceBalanced,
    );
    expect(fit.converged, isTrue);
    expect(fit.trainingObjective, lessThan(1e-12));
    expect(
      evaluation.stationWeightedSummary.rootMeanSquareResidual,
      lessThan(1e-6),
    );
  });

  test(
    'fixed saturation and distance balancing preserve a synthetic field',
    () {
      final fit = calibrator.fitEventSourceStrippedWithFixedSaturation(
        trainingEvents: events,
        sourceTermEvents: events,
        saturationCoefficient: published.saturationCoefficient,
        saturationMagnitudeExponent: published.saturationMagnitudeExponent,
        balanceSpec: const Matsuzaki2006DistanceBalanceSpec(
          nearDistanceThresholdKm: 30,
          nearGroupWeight: 0.5,
        ),
      );
      final evaluation = Matsuzaki2006ModelEvaluation(
        coefficients: fit.coefficients,
        events: events,
      );

      expect(
        fit.method,
        Matsuzaki2006CalibrationMethod.eventSourceStrippedFixedSaturation,
      );
      expect(fit.converged, isTrue);
      expect(fit.bestStartIndex, -1);
      expect(fit.iterations, 0);
      expect(fit.objectiveEvaluations, 1);
      expect(fit.nonlinearRuns, isEmpty);
      expect(
        fit.coefficients.saturationCoefficient,
        published.saturationCoefficient,
      );
      expect(
        fit.coefficients.saturationMagnitudeExponent,
        published.saturationMagnitudeExponent,
      );
      expect(fit.trainingObjective, lessThan(1e-12));
      expect(
        evaluation.stationWeightedSummary.rootMeanSquareResidual,
        lessThan(1e-6),
      );
    },
  );

  test('fixed published saturation recovers the synthetic linear terms', () {
    final fit = calibrator.fitGlobalWithFixedSaturation(
      trainingEvents: events,
      saturationCoefficient: published.saturationCoefficient,
      saturationMagnitudeExponent: published.saturationMagnitudeExponent,
    );
    final evaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: events,
    );

    expect(fit.method, Matsuzaki2006CalibrationMethod.globalFixedSaturation);
    expect(fit.nonlinearRuns, isEmpty);
    expect(fit.coefficients.magnitudeCoefficient, closeTo(1.36, 1e-8));
    expect(fit.coefficients.logDistanceCoefficient, closeTo(4.03, 1e-8));
    expect(fit.coefficients.depthCoefficient, closeTo(0.0155, 1e-10));
    expect(fit.coefficients.intercept, closeTo(2.05, 1e-8));
    expect(
      evaluation.stationWeightedSummary.rootMeanSquareResidual,
      lessThan(1e-6),
    );
  });

  test('fixed exponent recovers the synthetic saturation coefficient', () {
    final fit = calibrator.fitGlobalWithFixedExponent(
      trainingEvents: events,
      saturationMagnitudeExponent: published.saturationMagnitudeExponent,
      coefficientSearchSpec: coefficientSearchSpec,
    );
    final evaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: events,
    );

    expect(fit.method, Matsuzaki2006CalibrationMethod.globalFixedExponent);
    expect(fit.converged, isTrue);
    expect(fit.nonlinearRuns, hasLength(3));
    expect(fit.coefficients.saturationCoefficient, closeTo(0.00675, 1e-6));
    expect(
      evaluation.stationWeightedSummary.rootMeanSquareResidual,
      lessThan(1e-6),
    );
  });

  test('fixed coefficient recovers the synthetic saturation exponent', () {
    final fit = calibrator.fitGlobalWithFixedCoefficient(
      trainingEvents: events,
      saturationCoefficient: published.saturationCoefficient,
      exponentSearchSpec: exponentSearchSpec,
    );
    final evaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: events,
    );

    expect(fit.method, Matsuzaki2006CalibrationMethod.globalFixedCoefficient);
    expect(fit.converged, isTrue);
    expect(fit.nonlinearRuns, hasLength(3));
    expect(fit.coefficients.saturationMagnitudeExponent, closeTo(0.5, 1e-6));
    expect(
      evaluation.stationWeightedSummary.rootMeanSquareResidual,
      lessThan(1e-6),
    );
  });
}

List<Matsuzaki2006EventBaseline> _syntheticEvents(
  Matsuzaki2006AttenuationModel model,
) {
  final events = <Matsuzaki2006EventBaseline>[];
  for (var eventIndex = 0; eventIndex < 12; eventIndex++) {
    final magnitude = 5.0 + eventIndex * 0.25;
    final depthKm = 5.0 + eventIndex * 12.0;
    final stations = <Matsuzaki2006StationResidual>[];
    for (var stationIndex = 0; stationIndex < 24; stationIndex++) {
      final distanceKm = 5.0 + stationIndex * 18.0;
      final observed = model.predictIntensity(
        magnitude: magnitude,
        sourceDistanceKm: distanceKm,
        depthKm: depthKm,
      );
      stations.add(
        Matsuzaki2006StationResidual(
          stationId: 'E${eventIndex}_S$stationIndex',
          latitude: 30 + eventIndex * 0.1,
          longitude: 130 + stationIndex * 0.01,
          sourceDistanceKm: distanceKm,
          observedIntensity: observed,
          predictedIntensity: observed,
        ),
      );
    }
    events.add(
      Matsuzaki2006EventBaseline(
        eventId: 'synthetic-$eventIndex',
        year: 2020,
        originTime: '2020-01-${(eventIndex + 1).toString().padLeft(2, '0')}',
        latitude: 35,
        longitude: 140,
        depthKm: depthKm,
        magnitude: magnitude,
        magnitudeType: 'D',
        maximumIntensityClass: '',
        determinationFlag: 'K',
        stationResiduals: stations,
      ),
    );
  }
  return events;
}
