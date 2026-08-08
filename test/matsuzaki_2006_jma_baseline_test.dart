import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  const model = Matsuzaki2006AttenuationModel();
  const evaluator = Matsuzaki2006JmaBaselineEvaluator();

  test('evaluates reported JMA station intensities at the catalog source', () {
    final dataset = _dataset(
      magnitudeType: 'D',
      observedIntensity: (distanceKm) => model.predictIntensity(
        magnitude: 6,
        sourceDistanceKm: distanceKm,
        depthKm: 20,
      ),
    );

    final result = evaluator.evaluate([dataset]);

    expect(result.inputEventCount, 1);
    expect(result.events, hasLength(1));
    expect(result.stationResidualCount, 10);
    expect(result.overallResidualSummary.meanResidual, closeTo(0, 1e-12));
    expect(
      result.overallResidualSummary.rootMeanSquareResidual,
      closeTo(0, 1e-12),
    );
    expect(result.byMagnitudeType.keys, ['D']);
    expect(result.eventEqualMetrics['meanOfEventRootMeanSquareResiduals'], 0);
    expect(result.toMarkdown(), contains('Accepted events | 1'));
  });

  test('does not feed moment magnitude type W into the Mj equation', () {
    final dataset = _dataset(
      magnitudeType: 'W',
      observedIntensity: (distanceKm) => 3,
    );

    final result = evaluator.evaluate([dataset]);

    expect(result.events, isEmpty);
    expect(result.eventRejectionCounts['unsupported_magnitude_type'], 1);
  });

  test('requires the paper minimum of ten usable station records', () {
    final dataset = _dataset(
      magnitudeType: 'D',
      stationCount: 9,
      observedIntensity: (distanceKm) => 3,
    );

    final result = evaluator.evaluate([dataset]);

    expect(result.events, isEmpty);
    expect(
      result.eventRejectionCounts['fewer_than_minimum_usable_stations'],
      1,
    );
  });

  test('excludes compound records with unassigned alternate hypocenters', () {
    final dataset = _dataset(
      magnitudeType: 'D',
      observedIntensity: (distanceKm) => 3,
    );
    final event =
        (dataset['events']! as List<Object?>).single as Map<String, Object?>;
    event['alternateHypocenters'] = [
      {
        'originTime': '2020-01-01T00:01:00.000Z',
        'latitude': 35.1,
        'longitude': 140.1,
        'depthKm': 20.0,
        'magnitude': 5.5,
        'magnitudeType': 'D',
      },
    ];

    final result = evaluator.evaluate([dataset]);

    expect(result.events, isEmpty);
    expect(
      result.eventRejectionCounts['has_unassigned_alternate_hypocenters'],
      1,
    );
  });
}

Map<String, Object?> _dataset({
  required String magnitudeType,
  required double Function(double distanceKm) observedIntensity,
  int stationCount = 10,
}) {
  const sourceLatitude = 35.0;
  const sourceLongitude = 140.0;
  const depthKm = 20.0;
  final observations = <Map<String, Object?>>[];
  for (var index = 0; index < stationCount; index++) {
    final stationLatitude = sourceLatitude + 0.1 + index * 0.01;
    final stationLongitude = sourceLongitude + 0.05;
    final distanceKm =
        Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
          sourceLatitude: sourceLatitude,
          sourceLongitude: sourceLongitude,
          stationLatitude: stationLatitude,
          stationLongitude: stationLongitude,
          depthKm: depthKm,
        );
    observations.add({
      'stationId': 'S$index',
      'latitude': stationLatitude,
      'longitude': stationLongitude,
      'instrumentalIntensity': observedIntensity(distanceKm),
    });
  }
  return {
    'schemaVersion': 1,
    'datasetId': 'synthetic-2020',
    'year': 2020,
    'events': [
      {
        'eventId': 'synthetic-event',
        'preferredHypocenter': {
          'originTime': '2020-01-01T00:00:00.000Z',
          'latitude': sourceLatitude,
          'longitude': sourceLongitude,
          'depthKm': depthKm,
          'magnitude': 6.0,
          'magnitudeType': magnitudeType,
          'maximumIntensityClass': '4',
          'determinationFlag': 'K',
        },
        'observations': observations,
      },
    ],
  };
}
