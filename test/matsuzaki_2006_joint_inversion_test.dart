import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  const model = Matsuzaki2006AttenuationModel();
  const inverter = Matsuzaki2006JointInverter(model: model);

  test('recovers synthetic latitude longitude depth and magnitude', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.6, 139.7),
        (34.7, 140.4),
        (35.2, 139.5),
        (35.4, 140.3),
        (35.0, 140.6),
        (35.6, 139.9),
      ],
    );

    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.8,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.8,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        minimumDepthKm: 20,
        maximumDepthKm: 60,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.2,
            longitudeStepDegrees: 0.2,
            depthStepKm: 20,
          ),
          Matsuzaki2006JointSearchStage.refinePreviousCandidates(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
            maximumSeedCount: 2,
            seedRmsIncrease: 0.05,
          ),
          Matsuzaki2006JointSearchStage.refinePreviousCandidates(
            latitudeStepDegrees: 0.05,
            longitudeStepDegrees: 0.05,
            depthStepKm: 5,
            maximumSeedCount: 2,
            seedRmsIncrease: 0.05,
          ),
        ],
      ),
    );

    expect(result.status, Matsuzaki2006JointInversionStatus.solved);
    expect(
      result.distanceSemantics,
      Matsuzaki2006InversionDistanceSemantics.candidatePointSource,
    );
    expect(result.bestCandidates, hasLength(1));
    final best = result.bestCandidates.single;
    expect(best.source.latitude, closeTo(source.latitude, 1e-10));
    expect(best.source.longitude, closeTo(source.longitude, 1e-10));
    expect(best.source.depthKm, closeTo(source.depthKm, 1e-10));
    expect(best.magnitude, closeTo(6.5, 1e-7));
    expect(best.intensityRms, lessThan(1e-7));
    expect(result.hardBoundaryContacts, isEmpty);
    expect(result.resolutionEnvelope, isNotNull);
    expect(result.isConverged, isTrue);
    expect(result.candidateEvaluationCount, lessThan(600));
  });

  test('expands a touched initial horizontal boundary', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.5, 139.6),
        (34.6, 140.3),
        (35.3, 139.5),
        (35.5, 140.4),
        (35.1, 140.7),
      ],
    );
    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.6,
          maximumLatitude: 34.8,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.6,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        minimumDepthKm: 30,
        maximumDepthKm: 50,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
        maximumExpansionRounds: 3,
      ),
    );

    expect(result.status, Matsuzaki2006JointInversionStatus.solved);
    expect(result.stageResults.length, greaterThan(1));
    expect(result.stageResults.last.expansionRound, 2);
    expect(result.bestCandidates.single.source.latitude, closeTo(35, 1e-10));
  });

  test('reports a best candidate on the hard search boundary', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.5, 139.6),
        (34.6, 140.3),
        (35.3, 139.5),
        (35.5, 140.4),
        (35.1, 140.7),
      ],
    );
    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.6,
          maximumLatitude: 34.9,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.6,
          maximumLatitude: 34.9,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        minimumDepthKm: 30,
        maximumDepthKm: 50,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.hardBoundaryReached,
    );
    expect(
      result.hardBoundaryContacts,
      contains(Matsuzaki2006SearchBoundary.latitudeMaximum),
    );
  });

  test('reports a best depth on the configured depth boundary', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140,
      depthKm: 20,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.6, 139.7),
        (34.7, 140.4),
        (35.2, 139.5),
        (35.4, 140.3),
        (35.0, 140.6),
        (35.6, 139.9),
      ],
    );
    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.8,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.8,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        minimumDepthKm: 20,
        maximumDepthKm: 60,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.hardBoundaryReached,
    );
    expect(
      result.hardBoundaryContacts,
      contains(Matsuzaki2006SearchBoundary.depthMinimum),
    );
  });

  test('reports a best candidate on the radial hard boundary', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35.2,
      longitude: 140,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.7, 139.7),
        (34.8, 140.4),
        (35.3, 139.5),
        (35.5, 140.3),
        (35.1, 140.6),
      ],
    );
    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.7,
          maximumLatitude: 35.3,
          minimumLongitude: 139.7,
          maximumLongitude: 140.3,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.7,
          maximumLatitude: 35.3,
          minimumLongitude: 139.7,
          maximumLongitude: 140.3,
        ),
        minimumDepthKm: 30,
        maximumDepthKm: 50,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.05,
            longitudeStepDegrees: 0.05,
            depthStepKm: 10,
          ),
        ],
        radialSearchConstraint: const Matsuzaki2006RadialSearchConstraint(
          centerLatitude: 35,
          centerLongitude: 140,
          maximumEpicentralDistanceKm: 15,
        ),
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.hardBoundaryReached,
    );
    expect(
      result.hardBoundaryContacts,
      contains(Matsuzaki2006SearchBoundary.radialMaximum),
    );
    expect(result.isConverged, isFalse);
  });

  test('reports an exhausted expansion limit without claiming a solution', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 34.8,
      longitude: 140,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.5, 139.6),
        (34.6, 140.3),
        (35.3, 139.5),
        (35.5, 140.4),
        (35.1, 140.7),
      ],
    );
    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.6,
          maximumLatitude: 34.8,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.6,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        minimumDepthKm: 30,
        maximumDepthKm: 50,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.expansionLimitReached,
    );
    expect(result.hasSolution, isTrue);
    expect(result.isConverged, isFalse);
    expect(result.hardBoundaryContacts, isEmpty);
  });

  test('preserves mirrored equivalent solutions', () {
    const source = Matsuzaki2006CandidateSource(
      latitude: 35,
      longitude: 140.1,
      depthKm: 40,
    );
    final observations = _syntheticObservations(
      model: model,
      source: source,
      magnitude: 6.5,
      coordinates: const [
        (34.5, 140.0),
        (34.7, 140.0),
        (34.9, 140.0),
        (35.2, 140.0),
        (35.4, 140.0),
        (35.6, 140.0),
      ],
    );
    final result = inverter.invert(
      observations: observations,
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.8,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.8,
          maximumLatitude: 35.2,
          minimumLongitude: 139.8,
          maximumLongitude: 140.2,
        ),
        minimumDepthKm: 30,
        maximumDepthKm: 50,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
        equivalentObjectiveTolerance: 1e-7,
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.multipleEquivalentSolutions,
    );
    final longitudes = result.bestCandidates
        .map((candidate) => candidate.source.longitude)
        .toList();
    expect(longitudes.any((value) => (value - 139.9).abs() < 1e-10), isTrue);
    expect(longitudes.any((value) => (value - 140.1).abs() < 1e-10), isTrue);
  });

  test('reports no valid candidate outside the model distance domain', () {
    final result = inverter.invert(
      observations: const [
        Matsuzaki2006IntensityObservation(
          id: 'a',
          latitude: 35,
          longitude: 140,
          intensity: 3,
        ),
        Matsuzaki2006IntensityObservation(
          id: 'b',
          latitude: 35.2,
          longitude: 140.2,
          intensity: 3,
        ),
      ],
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 20,
          maximumLatitude: 20.1,
          minimumLongitude: 120,
          maximumLongitude: 120.1,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 20,
          maximumLatitude: 20.1,
          minimumLongitude: 120,
          maximumLongitude: 120.1,
        ),
        minimumDepthKm: 10,
        maximumDepthKm: 20,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
        minimumObservations: 2,
      ),
    );

    expect(result.status, Matsuzaki2006JointInversionStatus.noValidCandidate);
    expect(result.hasSolution, isFalse);
  });

  test('stops before a stage that exceeds the explicit candidate budget', () {
    final result = inverter.invert(
      observations: const [
        Matsuzaki2006IntensityObservation(
          id: 'a',
          latitude: 35,
          longitude: 140,
          intensity: 3,
        ),
      ],
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.9,
          maximumLatitude: 35.1,
          minimumLongitude: 139.9,
          maximumLongitude: 140.1,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.9,
          maximumLatitude: 35.1,
          minimumLongitude: 139.9,
          maximumLongitude: 140.1,
        ),
        minimumDepthKm: 10,
        maximumDepthKm: 20,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
        minimumObservations: 1,
        maximumCandidateEvaluations: 1,
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.candidateBudgetExceeded,
    );
    expect(result.candidateEvaluationCount, 0);
    expect(result.hasSolution, isFalse);
  });

  test('reports insufficient observations before searching', () {
    final result = inverter.invert(
      observations: const [
        Matsuzaki2006IntensityObservation(
          id: 'a',
          latitude: 35,
          longitude: 140,
          intensity: 3,
        ),
      ],
      searchSpec: _searchSpec(
        initial: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.9,
          maximumLatitude: 35.1,
          minimumLongitude: 139.9,
          maximumLongitude: 140.1,
        ),
        hard: const Matsuzaki2006HorizontalBounds(
          minimumLatitude: 34.9,
          maximumLatitude: 35.1,
          minimumLongitude: 139.9,
          maximumLongitude: 140.1,
        ),
        minimumDepthKm: 10,
        maximumDepthKm: 20,
        stages: const [
          Matsuzaki2006JointSearchStage(
            latitudeStepDegrees: 0.1,
            longitudeStepDegrees: 0.1,
            depthStepKm: 10,
          ),
        ],
        minimumObservations: 2,
      ),
    );

    expect(
      result.status,
      Matsuzaki2006JointInversionStatus.insufficientObservations,
    );
    expect(result.candidateEvaluationCount, 0);
  });
}

Matsuzaki2006JointSearchSpec _searchSpec({
  required Matsuzaki2006HorizontalBounds initial,
  required Matsuzaki2006HorizontalBounds hard,
  required double minimumDepthKm,
  required double maximumDepthKm,
  required List<Matsuzaki2006JointSearchStage> stages,
  int maximumExpansionRounds = 0,
  int maximumCandidateEvaluations = 100000,
  int minimumObservations = 5,
  double equivalentObjectiveTolerance = 1e-10,
  Matsuzaki2006RadialSearchConstraint? radialSearchConstraint,
}) => Matsuzaki2006JointSearchSpec(
  initialHorizontalBounds: initial,
  hardHorizontalBounds: hard,
  minimumDepthKm: minimumDepthKm,
  maximumDepthKm: maximumDepthKm,
  radialSearchConstraint: radialSearchConstraint,
  stages: stages,
  horizontalExpansionDegrees: 0.2,
  maximumHorizontalExpansionRounds: maximumExpansionRounds,
  maximumCandidateEvaluations: maximumCandidateEvaluations,
  minimumObservations: minimumObservations,
  equivalentObjectiveTolerance: equivalentObjectiveTolerance,
  resolutionRmsIncrease: 0.01,
  magnitudeSearchSpec: const Matsuzaki2006ForwardSearchSpec(
    magnitudeScanStep: 0.05,
    refinementTolerance: 1e-10,
    objectiveTieTolerance: 1e-12,
    maximumRefinementIterations: 100,
  ),
);

List<Matsuzaki2006IntensityObservation> _syntheticObservations({
  required Matsuzaki2006AttenuationModel model,
  required Matsuzaki2006CandidateSource source,
  required double magnitude,
  required List<(double, double)> coordinates,
}) => [
  for (var index = 0; index < coordinates.length; index++)
    Matsuzaki2006IntensityObservation(
      id: 'station-$index',
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
