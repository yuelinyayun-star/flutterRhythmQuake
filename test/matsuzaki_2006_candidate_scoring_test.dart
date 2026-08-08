import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  const rootScorer = Matsuzaki2006RootClusterScorer();
  const forwardScorer = Matsuzaki2006ForwardResidualScorer();
  const searchSpec = Matsuzaki2006ForwardSearchSpec(
    magnitudeScanStep: 0.05,
    refinementTolerance: 1e-10,
    objectiveTieTolerance: 1e-12,
    maximumRefinementIterations: 100,
  );

  test('both scores prefer the exact synthetic candidate', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 40,
    );
    const wrongSource = Matsuzaki2006CandidateSource(
      latitude: 35.2,
      longitude: 140.2,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.7, 139.7),
        (34.7, 140.3),
        (35.3, 139.7),
        (35.3, 140.3),
        (35.0, 140.5),
        (35.5, 140.0),
      ],
    );

    final exactRoot = rootScorer.score(
      observations: observations,
      source: source,
      minimumSolvedStations: observations.length,
      rejectCandidateWhenAnyStationHasNoRoot: true,
      clusterTieTolerance: 1e-12,
    );
    final wrongRoot = rootScorer.score(
      observations: observations,
      source: wrongSource,
      minimumSolvedStations: observations.length,
      rejectCandidateWhenAnyStationHasNoRoot: true,
      clusterTieTolerance: 1e-12,
    );
    final exactForward = forwardScorer.score(
      observations: observations,
      source: source,
      minimumObservations: observations.length,
      searchSpec: searchSpec,
    );
    final wrongForward = forwardScorer.score(
      observations: observations,
      source: wrongSource,
      minimumObservations: observations.length,
      searchSpec: searchSpec,
    );

    expect(exactRoot.isValid, isTrue);
    expect(exactRoot.solutions, hasLength(1));
    expect(exactRoot.solutions.single.commonMagnitude, closeTo(6.5, 1e-8));
    expect(exactRoot.minimumMagnitudeRms, closeTo(0, 1e-8));
    expect(wrongRoot.isValid, isTrue);
    expect(wrongRoot.minimumMagnitudeRms!, greaterThan(1e-3));

    expect(exactForward.isValid, isTrue);
    expect(exactForward.solutions, hasLength(1));
    expect(exactForward.solutions.single.magnitude, closeTo(6.5, 1e-7));
    expect(exactForward.minimumIntensityRms, closeTo(0, 1e-7));
    expect(wrongForward.isValid, isTrue);
    expect(wrongForward.minimumIntensityRms!, greaterThan(1e-3));
  });

  test(
    'root clustering preserves a shared lower branch across double roots',
    () {
      const source = Matsuzaki2006CandidateSource(
        latitude: 35,
        longitude: 140,
        depthKm: 10,
      );
      final observations = _syntheticObservations(
        source: source,
        magnitude: 7,
        coordinates: const [
          (35.10, 140.00),
          (34.90, 140.00),
          (35.00, 140.12),
          (35.00, 139.88),
          (35.08, 140.08),
          (34.92, 139.92),
        ],
      );

      final rootScore = rootScorer.score(
        observations: observations,
        source: source,
        minimumSolvedStations: observations.length,
        rejectCandidateWhenAnyStationHasNoRoot: true,
        clusterTieTolerance: 1e-10,
      );
      final forwardScore = forwardScorer.score(
        observations: observations,
        source: source,
        minimumObservations: observations.length,
        searchSpec: searchSpec,
      );

      expect(rootScore.isValid, isTrue);
      expect(rootScore.solutions, hasLength(1));
      final rootSolution = rootScore.solutions.single;
      expect(rootSolution.ambiguousStationCount, greaterThan(0));
      expect(rootSolution.commonMagnitude, closeTo(7, 1e-8));
      expect(rootSolution.magnitudeRms, closeTo(0, 1e-8));
      expect(forwardScore.solutions.single.magnitude, closeTo(7, 1e-7));
      expect(forwardScore.minimumIntensityRms, closeTo(0, 1e-7));
    },
  );

  test(
    'no-root observations are explicit instead of being magnitude-clamped',
    () {
      const source = Matsuzaki2006CandidateSource(
        latitude: 35,
        longitude: 140,
        depthKm: 40,
      );
      const observations = [
        Matsuzaki2006IntensityObservation(
          id: 'OUTSIDE',
          latitude: 35.3,
          longitude: 140.3,
          intensity: 20,
        ),
      ];

      final rootScore = rootScorer.score(
        observations: observations,
        source: source,
        minimumSolvedStations: 1,
        rejectCandidateWhenAnyStationHasNoRoot: true,
        clusterTieTolerance: 1e-12,
      );
      final forwardScore = forwardScorer.score(
        observations: observations,
        source: source,
        minimumObservations: 1,
        searchSpec: searchSpec,
      );

      expect(rootScore.isValid, isFalse);
      expect(
        rootScore.invalidReason,
        Matsuzaki2006CandidateInvalidReason.stationWithoutMagnitudeRoot,
      );
      expect(rootScore.unsolvedObservationIds, ['OUTSIDE']);
      expect(forwardScore.isValid, isTrue);
      expect(forwardScore.minimumIntensityRms!, greaterThan(10));
    },
  );

  test('prevalidated forward score preserves the checked score exactly', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 30,
    );
    final observations = _syntheticObservations(
      source: source,
      magnitude: 6.2,
      coordinates: const [
        (34.8, 139.8),
        (34.8, 140.2),
        (35.2, 139.8),
        (35.2, 140.2),
      ],
    );

    final checked = forwardScorer.score(
      observations: observations,
      source: source,
      minimumObservations: observations.length,
      searchSpec: searchSpec,
    );
    final prevalidated = forwardScorer.scorePrevalidated(
      observations: observations,
      source: source,
      minimumObservations: observations.length,
      searchSpec: searchSpec,
    );

    expect(prevalidated.isValid, checked.isValid);
    expect(prevalidated.invalidReason, checked.invalidReason);
    expect(prevalidated.solutions, hasLength(checked.solutions.length));
    for (var index = 0; index < checked.solutions.length; index++) {
      expect(
        prevalidated.solutions[index].magnitude,
        closeTo(checked.solutions[index].magnitude, 1e-12),
      );
      expect(
        prevalidated.solutions[index].intensityRms,
        closeTo(checked.solutions[index].intensityRms, 1e-12),
      );
      expect(
        prevalidated.solutions[index].meanIntensityResidual,
        closeTo(checked.solutions[index].meanIntensityResidual, 1e-12),
      );
    }
  });

  test('forward score applies only a matching frozen station correction', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 30,
    );
    const model = Matsuzaki2006AttenuationModel();
    final stationBiasTrainer = Matsuzaki2006StationBiasTrainer()
      ..addEvent(_stationBiasTrainingEvent('train-a'))
      ..addEvent(_stationBiasTrainingEvent('train-b'));
    final stationBiasModel = stationBiasTrainer.build(
      minimumTrainingEventCount: 2,
    );
    final observations = _stationBiasedObservations(
      source: source,
      magnitude: 6.2,
    );
    final corrected =
        Matsuzaki2006ForwardResidualScorer(
          model: model,
          stationBiasModel: stationBiasModel,
        ).score(
          observations: observations,
          source: source,
          minimumObservations: observations.length,
          searchSpec: searchSpec,
        );
    final uncorrected = Matsuzaki2006ForwardResidualScorer(model: model).score(
      observations: observations,
      source: source,
      minimumObservations: observations.length,
      searchSpec: searchSpec,
    );

    expect(corrected.solutions.single.magnitude, closeTo(6.2, 1e-7));
    expect(corrected.minimumIntensityRms, lessThan(1e-7));
    expect(uncorrected.minimumIntensityRms!, greaterThan(1e-3));
  });
}

List<Matsuzaki2006IntensityObservation> _syntheticObservations({
  required Matsuzaki2006CandidateSource source,
  required double magnitude,
  required List<(double, double)> coordinates,
}) {
  const model = Matsuzaki2006AttenuationModel();
  return [
    for (var index = 0; index < coordinates.length; index++)
      Matsuzaki2006IntensityObservation(
        id: 'S$index',
        latitude: coordinates[index].$1,
        longitude: coordinates[index].$2,
        intensity: model.predictIntensity(
          magnitude: magnitude,
          sourceDistanceKm:
              Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
                sourceLatitude: source.latitude,
                sourceLongitude: source.longitude,
                stationLatitude: coordinates[index].$1,
                stationLongitude: coordinates[index].$2,
                depthKm: source.depthKm,
              ),
          depthKm: source.depthKm,
        ),
      ),
  ];
}

Matsuzaki2006EventBaseline _stationBiasTrainingEvent(String eventId) {
  return Matsuzaki2006EventBaseline(
    eventId: eventId,
    year: 2010,
    originTime: '2010-01-01T00:00:00Z',
    latitude: 35,
    longitude: 140,
    depthKm: 30,
    magnitude: 6,
    magnitudeType: 'D',
    maximumIntensityClass: '3',
    determinationFlag: 'K',
    stationResiduals: const [
      Matsuzaki2006StationResidual(
        stationId: 'S0',
        latitude: 34.8,
        longitude: 139.8,
        sourceDistanceKm: 30,
        observedIntensity: 2,
        predictedIntensity: 0,
      ),
      Matsuzaki2006StationResidual(
        stationId: 'S1',
        latitude: 35.2,
        longitude: 140.2,
        sourceDistanceKm: 30,
        observedIntensity: 0,
        predictedIntensity: 0,
      ),
    ],
  );
}

List<Matsuzaki2006IntensityObservation> _stationBiasedObservations({
  required Matsuzaki2006CandidateSource source,
  required double magnitude,
}) {
  const model = Matsuzaki2006AttenuationModel();
  const stations = [('S0', 34.8, 139.8, 1.0), ('S1', 35.2, 140.2, -1.0)];
  return [
    for (final station in stations)
      Matsuzaki2006IntensityObservation(
        id: station.$1,
        latitude: station.$2,
        longitude: station.$3,
        intensity:
            model.predictIntensity(
              magnitude: magnitude,
              sourceDistanceKm:
                  Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
                    sourceLatitude: source.latitude,
                    sourceLongitude: source.longitude,
                    stationLatitude: station.$2,
                    stationLongitude: station.$3,
                    depthKm: source.depthKm,
                  ),
              depthKm: source.depthKm,
            ) +
            station.$4,
      ),
  ];
}
