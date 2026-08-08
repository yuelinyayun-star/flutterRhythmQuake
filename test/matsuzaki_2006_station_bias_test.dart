import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  test('removes each event source term before estimating station bias', () {
    final trainer = Matsuzaki2006StationBiasTrainer()
      ..addEvent(_event('train-a', 2010, [3, 1]))
      ..addEvent(_event('train-b', 2011, [-2, -4]));

    final model = trainer.build(minimumTrainingEventCount: 2);

    expect(model.estimates['S0']!.meanCenteredResidual, closeTo(1, 1e-12));
    expect(model.estimates['S1']!.meanCenteredResidual, closeTo(-1, 1e-12));
    expect(model.trainingEventCount, 2);
    expect(model.trainingObservationCount, 4);
  });

  test('reduces matched station structure without removing event source', () {
    final trainer = Matsuzaki2006StationBiasTrainer()
      ..addEvent(_event('train-a', 2010, [3, 1]))
      ..addEvent(_event('train-b', 2011, [-2, -4]));
    final model = trainer.build(minimumTrainingEventCount: 2);
    final evaluation = const Matsuzaki2006StationBiasEvaluator().evaluate(
      events: [
        _event('validation', 2017, [1.5, -0.5]),
      ],
      stationBiasModel: model,
    );

    expect(evaluation.correctionAppliedCount, 2);
    expect(evaluation.correctedEventEqualCenteredRms, closeTo(0, 1e-12));
    expect(evaluation.centeredRmsImprovedEventCount, 1);
    expect(evaluation.centeredRmsWorsenedEventCount, 0);
    final event = evaluation.events.single;
    expect(event.correctedRawResiduals.meanResidual, closeTo(0.5, 1e-12));
    expect(
      event.correctedRawResiduals.rootMeanSquareResidual,
      closeTo(0.5, 1e-12),
    );
  });

  test('leaves unavailable and coordinate-mismatched stations unmodified', () {
    final trainer = Matsuzaki2006StationBiasTrainer()
      ..addEvent(_event('train-a', 2010, [3, 1]))
      ..addEvent(_event('train-b', 2011, [-2, -4]));
    final model = trainer.build(minimumTrainingEventCount: 2);
    final validation = _event('validation', 2017, [1.5, -0.5, 2]);
    final moved = validation.stationResiduals[1];
    final event = Matsuzaki2006EventBaseline(
      eventId: validation.eventId,
      year: validation.year,
      originTime: validation.originTime,
      latitude: validation.latitude,
      longitude: validation.longitude,
      depthKm: validation.depthKm,
      magnitude: validation.magnitude,
      magnitudeType: validation.magnitudeType,
      maximumIntensityClass: validation.maximumIntensityClass,
      determinationFlag: validation.determinationFlag,
      stationResiduals: [
        validation.stationResiduals[0],
        Matsuzaki2006StationResidual(
          stationId: moved.stationId,
          latitude: moved.latitude + 0.01,
          longitude: moved.longitude,
          sourceDistanceKm: moved.sourceDistanceKm,
          observedIntensity: moved.observedIntensity,
          predictedIntensity: moved.predictedIntensity,
        ),
        validation.stationResiduals[2],
      ],
    );

    final evaluation = const Matsuzaki2006StationBiasEvaluator().evaluate(
      events: [event],
      stationBiasModel: model,
    );

    expect(evaluation.correctionAppliedCount, 1);
    expect(evaluation.coordinateMismatchCount, 1);
    expect(evaluation.correctionUnavailableCount, 1);
    expect(evaluation.events.single.correctedRawResiduals.maximumResidual, 2);
  });

  test(
    'shrinks low-count station estimates without changing training input',
    () {
      final trainer = Matsuzaki2006StationBiasTrainer()
        ..addEvent(_event('train-a', 2010, [3, 1]))
        ..addEvent(_event('train-b', 2011, [-2, -4]));
      final model = trainer.build(minimumTrainingEventCount: 2);
      final evaluation =
          const Matsuzaki2006StationBiasEvaluator(
            shrinkage: Matsuzaki2006StationBiasShrinkage(pseudoEventCount: 2),
          ).evaluate(
            events: [
              _event('validation', 2017, [1.5, -0.5]),
            ],
            stationBiasModel: model,
          );

      // The two-event terms +1 and -1 receive the 2 / (2 + 2) weight.
      expect(
        evaluation.events.single.correctedRawResiduals.meanResidual,
        closeTo(0.5, 1e-12),
      );
      expect(
        evaluation.events.single.correctedRawResiduals.rootMeanSquareResidual,
        closeTo(math.sqrt(0.5), 1e-12),
      );
      expect(model.estimates['S0']!.meanCenteredResidual, closeTo(1, 1e-12));
    },
  );

  test('requires at least two events for a long-term estimate', () {
    final trainer = Matsuzaki2006StationBiasTrainer()
      ..addEvent(_event('train', 2010, [1, -1]));

    expect(
      () => trainer.build(minimumTrainingEventCount: 1),
      throwsArgumentError,
    );
    expect(trainer.build(minimumTrainingEventCount: 2).estimates, isEmpty);
  });
}

Matsuzaki2006EventBaseline _event(
  String eventId,
  int year,
  List<double> residuals,
) {
  return Matsuzaki2006EventBaseline(
    eventId: eventId,
    year: year,
    originTime: '$year-01-01T00:00:00Z',
    latitude: 35,
    longitude: 140,
    depthKm: 20,
    magnitude: 6,
    magnitudeType: 'D',
    maximumIntensityClass: '4',
    determinationFlag: 'K',
    stationResiduals: [
      for (var index = 0; index < residuals.length; index++)
        Matsuzaki2006StationResidual(
          stationId: 'S$index',
          latitude: 35 + index * 0.1,
          longitude: 140,
          sourceDistanceKm: 20 + index.toDouble(),
          observedIntensity: residuals[index],
          predictedIntensity: 0,
        ),
    ],
  );
}
