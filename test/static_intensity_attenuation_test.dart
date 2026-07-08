import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

void main() {
  test('trains positive attenuation and locates a synthetic event', () {
    final events = [
      for (var eventIndex = 0; eventIndex < 6; eventIndex++)
        _event(
          'event-$eventIndex',
          latitude: 35 + eventIndex * 0.1,
          longitude: 140 - eventIndex * 0.1,
        ),
    ];
    final model = const StaticAttenuationTrainer(
      logDistanceCandidates: [1, 2, 3],
      linearDistanceCandidates: [0, 0.005],
      nearDistanceCandidatesKm: [5],
    ).train(events);
    final estimate = StaticIntensityLocator(
      model: model,
      coarseExtentDegrees: 2,
      coarseStepDegrees: 0.5,
      fineExtentDegrees: 0.5,
      fineStepDegrees: 0.1,
    ).locate(events.first.stations);

    expect(model.logDistanceCoefficient, greaterThan(0));
    expect(estimate, isNotNull);
    expect(estimate!.latitude, closeTo(events.first.latitude, 0.35));
    expect(estimate.longitude, closeTo(events.first.longitude, 0.35));
    expect(estimate.p90RadiusKm, greaterThanOrEqualTo(estimate.p50RadiusKm));
  });

  test('evaluation compares all variants against weighted centroid', () {
    final event = _event('event', latitude: 35, longitude: 140);
    final model = const StaticAttenuationModel(
      logDistanceCoefficient: 2,
      linearDistanceCoefficient: 0,
      nearDistanceKm: 5,
      huberDelta: 1,
      residualScale: 0.5,
    );
    final evaluation = StaticIntensityEvaluator(
      StaticIntensityLocator(
        model: model,
        coarseExtentDegrees: 2,
        coarseStepDegrees: 0.5,
        fineExtentDegrees: 0.5,
        fineStepDegrees: 0.1,
      ),
    ).evaluate([event]);

    expect(evaluation.caseCount, 1);
    expect(evaluation.medianErrorKm.isFinite, isTrue);
    expect(evaluation.weightedCentroidMedianErrorKm.isFinite, isTrue);
    expect(evaluation.byMaskRate, contains('50pct'));
  });
}

StaticIntensityEvent _event(
  String id, {
  required double latitude,
  required double longitude,
}) {
  final stations = <StaticIntensityStation>[];
  const offsets = [
    (-0.7, 0.0),
    (0.7, 0.0),
    (0.0, -0.7),
    (0.0, 0.7),
    (-0.5, -0.5),
    (0.5, 0.5),
  ];
  for (var index = 0; index < offsets.length; index++) {
    final offset = offsets[index];
    final distance = 111 * (offset.$1.abs() + offset.$2.abs());
    final intensity = 5 - 2 * _log10(distance + 5);
    stations.add(
      StaticIntensityStation(
        stationId: 'S$index',
        latitude: latitude + offset.$1,
        longitude: longitude + offset.$2,
        intensity: intensity,
      ),
    );
  }
  return StaticIntensityEvent(
    eventId: id,
    split: 'train',
    latitude: latitude,
    longitude: longitude,
    depthKm: 10,
    stations: stations,
    variants: [
      StaticIntensityVariant(
        variantId: '$id-mask',
        maskRate: 0.5,
        retainedStationIds: stations
            .map((station) => station.stationId)
            .toList(),
      ),
    ],
  );
}

double _log10(double value) => math.log(value) / math.ln10;
