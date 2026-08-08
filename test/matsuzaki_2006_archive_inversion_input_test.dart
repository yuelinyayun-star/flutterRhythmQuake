import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  const builder = Matsuzaki2006ArchiveInversionInputBuilder();
  const spec = Matsuzaki2006ArchiveInputSpec(
    initialSearchRadiusKm: 100,
    maximumHorizontalSearchDistanceKm: 200,
    minimumSearchDepthKm: 5,
    maximumSearchDepthKm: 100,
    minimumObservations: 3,
    maximumObservations: 4,
    minimumInstrumentalIntensity: 0.5,
  );

  test('builds anchor bounds and strongest domain-safe observations', () {
    final input = builder.build(rawEvent: _event(), spec: spec);

    expect(input.status, Matsuzaki2006ArchiveInputStatus.ready);
    expect(input.anchorLatitude, closeTo(35.1, 1e-12));
    expect(input.anchorLongitude, closeTo(140.1, 1e-12));
    expect(input.initialHorizontalBounds!.minimumLatitude, lessThan(35.1));
    expect(input.initialHorizontalBounds!.maximumLongitude, greaterThan(140.1));
    expect(input.hardHorizontalBounds!.minimumLatitude, lessThan(34));
    expect(input.hardHorizontalBounds!.maximumLongitude, greaterThan(142));
    expect(input.radialSearchConstraint!.maximumEpicentralDistanceKm, 200);
    expect(input.observations, hasLength(4));
    expect(
      input.observations.map((observation) => observation.id),
      orderedEquals(const ['max-a', 'max-b', 'near-a', 'near-b']),
    );
    expect(input.rawObservationCount, 6);
    expect(input.validObservationCount, 6);
    expect(input.domainSafeObservationCount, 5);
  });

  test('catalog hypocenter magnitude and depth cannot change the input', () {
    final first = builder.build(rawEvent: _event(), spec: spec);
    final changedTruth = _event();
    changedTruth['preferredHypocenter'] = <String, Object?>{
      'latitude': 10.0,
      'longitude': 170.0,
      'depthKm': 180.0,
      'magnitude': 8.2,
    };
    final second = builder.build(rawEvent: changedTruth, spec: spec);

    expect(second.status, first.status);
    expect(second.anchorLatitude, first.anchorLatitude);
    expect(second.anchorLongitude, first.anchorLongitude);
    expect(
      second.observations.map(_observationTuple),
      orderedEquals(first.observations.map(_observationTuple)),
    );
    expect(
      _boundsTuple(second.initialHorizontalBounds!),
      _boundsTuple(first.initialHorizontalBounds!),
    );
    expect(
      _boundsTuple(second.hardHorizontalBounds!),
      _boundsTuple(first.hardHorizontalBounds!),
    );
    expect(
      second.radialSearchConstraint!.maximumEpicentralDistanceKm,
      first.radialSearchConstraint!.maximumEpicentralDistanceKm,
    );
  });

  test('keeps selected stations safe across the radial search boundary', () {
    final input = builder.build(rawEvent: _event(), spec: spec);
    final hard = input.hardHorizontalBounds!;
    final boundaryPoints = <(double, double)>[
      (hard.minimumLatitude, input.anchorLongitude!),
      (hard.maximumLatitude, input.anchorLongitude!),
      (input.anchorLatitude!, hard.minimumLongitude),
      (input.anchorLatitude!, hard.maximumLongitude),
    ];

    for (final observation in input.observations) {
      for (final point in boundaryPoints) {
        final distance =
            Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
              sourceLatitude: point.$1,
              sourceLongitude: point.$2,
              stationLatitude: observation.latitude,
              stationLongitude: observation.longitude,
              depthKm: spec.maximumSearchDepthKm,
            );
        expect(
          distance,
          lessThanOrEqualTo(
            Matsuzaki2006AttenuationModel.maximumSourceDistanceKm,
          ),
        );
      }
    }
  });

  test('does not silently keep too few domain-safe observations', () {
    final event = _event();
    event['observations'] = <Object?>[
      _observation('max-a', 35, 140, 4.2),
      _observation('far-a', 43, 150, 3.0),
      _observation('far-b', 44, 151, 2.9),
    ];
    final input = builder.build(rawEvent: event, spec: spec);

    expect(
      input.status,
      Matsuzaki2006ArchiveInputStatus.insufficientDomainSafeObservations,
    );
    expect(input.observations, isEmpty);
    expect(input.domainSafeObservationCount, 1);
  });

  test('keeps the JMA 0.5 boundary and rejects lower values unchanged', () {
    final event = _event();
    event['observations'] = <Object?>[
      _observation('maximum', 35.0, 140.0, 2.0),
      _observation('second', 35.1, 140.1, 1.0),
      _observation('boundary', 35.2, 140.2, 0.5),
      _observation('below', 35.3, 140.3, 0.4),
    ];

    final input = builder.build(rawEvent: event, spec: spec);

    expect(input.status, Matsuzaki2006ArchiveInputStatus.ready);
    expect(input.rawObservationCount, 4);
    expect(input.validObservationCount, 3);
    expect(input.observations.map((item) => item.id), isNot(contains('below')));
    expect(
      input.observations.singleWhere((item) => item.id == 'boundary').intensity,
      0.5,
    );
    expect(input.rejectionCounts, {'below_minimum_instrumental_intensity': 1});
  });
}

Map<String, Object?> _event() => <String, Object?>{
  'eventId': 'test-event',
  'preferredHypocenter': <String, Object?>{
    'latitude': 35.05,
    'longitude': 140.05,
    'depthKm': 40.0,
    'magnitude': 6.5,
  },
  'observations': <Object?>[
    _observation('max-a', 35.0, 140.0, 4.2),
    _observation('max-b', 35.2, 140.2, 4.2),
    _observation('near-a', 34.8, 139.9, 3.8),
    _observation('near-b', 35.3, 140.1, 3.7),
    _observation('near-c', 34.9, 140.3, 3.6),
    _observation('far', 43.0, 150.0, 3.5),
  ],
};

Map<String, Object?> _observation(
  String id,
  double latitude,
  double longitude,
  double intensity,
) => <String, Object?>{
  'stationId': id,
  'latitude': latitude,
  'longitude': longitude,
  'instrumentalIntensity': intensity,
};

(String, double, double, double) _observationTuple(
  Matsuzaki2006IntensityObservation observation,
) => (
  observation.id,
  observation.latitude,
  observation.longitude,
  observation.intensity,
);

(double, double, double, double) _boundsTuple(
  Matsuzaki2006HorizontalBounds bounds,
) => (
  bounds.minimumLatitude,
  bounds.maximumLatitude,
  bounds.minimumLongitude,
  bounds.maximumLongitude,
);
