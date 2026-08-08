import 'dart:math' as math;

import '../../../calculator.dart';
import 'matsuzaki_2006_attenuation_model.dart';
import 'matsuzaki_2006_geometry.dart';
import 'matsuzaki_2006_station_bias.dart';

class Matsuzaki2006IntensityObservation {
  const Matsuzaki2006IntensityObservation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.intensity,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double intensity;
}

class Matsuzaki2006CandidateSource {
  const Matsuzaki2006CandidateSource({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
  });

  final double latitude;
  final double longitude;
  final double depthKm;
}

enum Matsuzaki2006CandidateInvalidReason {
  insufficientObservations,
  sourceDistanceOutsideCalibrationRange,
  stationWithoutMagnitudeRoot,
  insufficientSolvedStations,
  noSelfConsistentRootCluster,
  magnitudeOptimizationFailed,
}

class Matsuzaki2006RootSelection {
  Matsuzaki2006RootSelection({
    required this.observationId,
    required this.sourceDistanceKm,
    required List<double> availableRoots,
    required this.selectedMagnitude,
  }) : availableRoots = List.unmodifiable(availableRoots);

  final String observationId;
  final double sourceDistanceKm;
  final List<double> availableRoots;
  final double selectedMagnitude;
}

class Matsuzaki2006RootClusterSolution {
  Matsuzaki2006RootClusterSolution({
    required this.commonMagnitude,
    required this.magnitudeRms,
    required List<Matsuzaki2006RootSelection> selections,
  }) : selections = List.unmodifiable(selections);

  final double commonMagnitude;
  final double magnitudeRms;
  final List<Matsuzaki2006RootSelection> selections;

  int get ambiguousStationCount => selections
      .where((selection) => selection.availableRoots.length > 1)
      .length;
}

class Matsuzaki2006RootClusterScore {
  Matsuzaki2006RootClusterScore._({
    required this.source,
    required List<Matsuzaki2006RootClusterSolution> solutions,
    required List<String> unsolvedObservationIds,
    required this.invalidReason,
  }) : solutions = List.unmodifiable(solutions),
       unsolvedObservationIds = List.unmodifiable(unsolvedObservationIds);

  factory Matsuzaki2006RootClusterScore.valid({
    required Matsuzaki2006CandidateSource source,
    required List<Matsuzaki2006RootClusterSolution> solutions,
    required List<String> unsolvedObservationIds,
  }) => Matsuzaki2006RootClusterScore._(
    source: source,
    solutions: solutions,
    unsolvedObservationIds: unsolvedObservationIds,
    invalidReason: null,
  );

  factory Matsuzaki2006RootClusterScore.invalid({
    required Matsuzaki2006CandidateSource source,
    required Matsuzaki2006CandidateInvalidReason reason,
    List<String> unsolvedObservationIds = const [],
  }) => Matsuzaki2006RootClusterScore._(
    source: source,
    solutions: const [],
    unsolvedObservationIds: unsolvedObservationIds,
    invalidReason: reason,
  );

  final Matsuzaki2006CandidateSource source;
  final List<Matsuzaki2006RootClusterSolution> solutions;
  final List<String> unsolvedObservationIds;
  final Matsuzaki2006CandidateInvalidReason? invalidReason;

  bool get isValid => invalidReason == null;
  double? get minimumMagnitudeRms =>
      isValid ? solutions.first.magnitudeRms : null;
}

class Matsuzaki2006RootClusterScorer {
  const Matsuzaki2006RootClusterScorer({
    this.model = const Matsuzaki2006AttenuationModel(),
  });

  final Matsuzaki2006AttenuationModel model;

  Matsuzaki2006RootClusterScore score({
    required List<Matsuzaki2006IntensityObservation> observations,
    required Matsuzaki2006CandidateSource source,
    required int minimumSolvedStations,
    required bool rejectCandidateWhenAnyStationHasNoRoot,
    required double clusterTieTolerance,
  }) {
    _validateScoringInput(
      observations: observations,
      source: source,
      minimumObservations: minimumSolvedStations,
    );
    if (!clusterTieTolerance.isFinite || clusterTieTolerance < 0) {
      throw ArgumentError.value(
        clusterTieTolerance,
        'clusterTieTolerance',
        'Must be finite and non-negative.',
      );
    }
    if (observations.length < minimumSolvedStations) {
      return Matsuzaki2006RootClusterScore.invalid(
        source: source,
        reason: Matsuzaki2006CandidateInvalidReason.insufficientObservations,
      );
    }

    final rootSets = <_StationRootSet>[];
    final unsolvedIds = <String>[];
    for (final observation in observations) {
      final distanceKm = _sourceDistance(observation, source);
      if (!_distanceIsInsideModel(distanceKm)) {
        return Matsuzaki2006RootClusterScore.invalid(
          source: source,
          reason: Matsuzaki2006CandidateInvalidReason
              .sourceDistanceOutsideCalibrationRange,
        );
      }
      final inference = model.inferMagnitudes(
        observedIntensity: observation.intensity,
        sourceDistanceKm: distanceKm,
        depthKm: source.depthKm,
      );
      if (!inference.hasSolution) {
        unsolvedIds.add(observation.id);
        continue;
      }
      rootSets.add(
        _StationRootSet(
          observationId: observation.id,
          sourceDistanceKm: distanceKm,
          roots: inference.roots,
        ),
      );
    }
    if (rejectCandidateWhenAnyStationHasNoRoot && unsolvedIds.isNotEmpty) {
      return Matsuzaki2006RootClusterScore.invalid(
        source: source,
        reason: Matsuzaki2006CandidateInvalidReason.stationWithoutMagnitudeRoot,
        unsolvedObservationIds: unsolvedIds,
      );
    }
    if (rootSets.length < minimumSolvedStations) {
      return Matsuzaki2006RootClusterScore.invalid(
        source: source,
        reason: Matsuzaki2006CandidateInvalidReason.insufficientSolvedStations,
        unsolvedObservationIds: unsolvedIds,
      );
    }

    final allSolutions = _selfConsistentClusters(rootSets);
    if (allSolutions.isEmpty) {
      return Matsuzaki2006RootClusterScore.invalid(
        source: source,
        reason: Matsuzaki2006CandidateInvalidReason.noSelfConsistentRootCluster,
        unsolvedObservationIds: unsolvedIds,
      );
    }
    final minimumRms = allSolutions
        .map((solution) => solution.magnitudeRms)
        .reduce(math.min);
    final bestSolutions =
        allSolutions
            .where(
              (solution) =>
                  solution.magnitudeRms - minimumRms <= clusterTieTolerance,
            )
            .toList()
          ..sort(
            (left, right) =>
                left.commonMagnitude.compareTo(right.commonMagnitude),
          );
    return Matsuzaki2006RootClusterScore.valid(
      source: source,
      solutions: bestSolutions,
      unsolvedObservationIds: unsolvedIds,
    );
  }

  List<Matsuzaki2006RootClusterSolution> _selfConsistentClusters(
    List<_StationRootSet> rootSets,
  ) {
    final thresholds =
        rootSets
            .where((station) => station.roots.length == 2)
            .map((station) => (station.roots.first + station.roots.last) / 2)
            .toSet()
            .toList()
          ..sort();
    final intervalBounds = <double>[
      Matsuzaki2006AttenuationModel.minimumMagnitude,
      ...thresholds,
      Matsuzaki2006AttenuationModel.maximumMagnitude,
    ];
    final solutions = <Matsuzaki2006RootClusterSolution>[];
    final seenAssignments = <String>{};
    for (var index = 0; index < intervalBounds.length - 1; index++) {
      final lowerBound = intervalBounds[index];
      final upperBound = intervalBounds[index + 1];
      final probe = (lowerBound + upperBound) / 2;
      final selected = [
        for (final station in rootSets) _nearestRoot(station.roots, probe),
      ];
      final assignmentKey = selected.map((value) => value.toString()).join('|');
      if (!seenAssignments.add(assignmentKey)) continue;
      final commonMagnitude =
          selected.reduce((a, b) => a + b) / selected.length;
      const consistencyTolerance = 1e-12;
      if (commonMagnitude < lowerBound - consistencyTolerance ||
          commonMagnitude > upperBound + consistencyTolerance) {
        continue;
      }
      final magnitudeRms = math.sqrt(
        selected
                .map((value) {
                  final residual = value - commonMagnitude;
                  return residual * residual;
                })
                .reduce((a, b) => a + b) /
            selected.length,
      );
      solutions.add(
        Matsuzaki2006RootClusterSolution(
          commonMagnitude: commonMagnitude,
          magnitudeRms: magnitudeRms,
          selections: [
            for (
              var stationIndex = 0;
              stationIndex < rootSets.length;
              stationIndex++
            )
              Matsuzaki2006RootSelection(
                observationId: rootSets[stationIndex].observationId,
                sourceDistanceKm: rootSets[stationIndex].sourceDistanceKm,
                availableRoots: rootSets[stationIndex].roots,
                selectedMagnitude: selected[stationIndex],
              ),
          ],
        ),
      );
    }
    return solutions;
  }

  double _nearestRoot(List<double> roots, double probe) {
    if (roots.length == 1) return roots.single;
    final firstDistance = (roots.first - probe).abs();
    final lastDistance = (roots.last - probe).abs();
    return firstDistance <= lastDistance ? roots.first : roots.last;
  }
}

class Matsuzaki2006ForwardSearchSpec {
  const Matsuzaki2006ForwardSearchSpec({
    required this.magnitudeScanStep,
    required this.refinementTolerance,
    required this.objectiveTieTolerance,
    required this.maximumRefinementIterations,
  });

  final double magnitudeScanStep;
  final double refinementTolerance;
  final double objectiveTieTolerance;
  final int maximumRefinementIterations;

  void validate() {
    final magnitudeWidth =
        Matsuzaki2006AttenuationModel.maximumMagnitude -
        Matsuzaki2006AttenuationModel.minimumMagnitude;
    if (!magnitudeScanStep.isFinite ||
        magnitudeScanStep <= 0 ||
        magnitudeScanStep > magnitudeWidth) {
      throw ArgumentError.value(
        magnitudeScanStep,
        'magnitudeScanStep',
        'Must be finite, positive, and no larger than the Mj search width.',
      );
    }
    if (!refinementTolerance.isFinite || refinementTolerance <= 0) {
      throw ArgumentError.value(
        refinementTolerance,
        'refinementTolerance',
        'Must be finite and positive.',
      );
    }
    if (!objectiveTieTolerance.isFinite || objectiveTieTolerance < 0) {
      throw ArgumentError.value(
        objectiveTieTolerance,
        'objectiveTieTolerance',
        'Must be finite and non-negative.',
      );
    }
    if (maximumRefinementIterations <= 0) {
      throw ArgumentError.value(
        maximumRefinementIterations,
        'maximumRefinementIterations',
        'Must be positive.',
      );
    }
  }
}

class Matsuzaki2006ForwardStationResidual {
  const Matsuzaki2006ForwardStationResidual({
    required this.observationId,
    required this.sourceDistanceKm,
    required this.observedIntensity,
    required this.predictedIntensity,
  });

  final String observationId;
  final double sourceDistanceKm;
  final double observedIntensity;
  final double predictedIntensity;

  double get residual => observedIntensity - predictedIntensity;
}

class Matsuzaki2006ForwardMagnitudeSolution {
  Matsuzaki2006ForwardMagnitudeSolution({
    required this.magnitude,
    required this.intensityRms,
    required this.meanIntensityResidual,
    required List<Matsuzaki2006ForwardStationResidual> stationResiduals,
  }) : stationResiduals = List.unmodifiable(stationResiduals);

  final double magnitude;
  final double intensityRms;
  final double meanIntensityResidual;
  final List<Matsuzaki2006ForwardStationResidual> stationResiduals;
}

class Matsuzaki2006ForwardCandidateScore {
  Matsuzaki2006ForwardCandidateScore._({
    required this.source,
    required List<Matsuzaki2006ForwardMagnitudeSolution> solutions,
    required this.invalidReason,
  }) : solutions = List.unmodifiable(solutions);

  factory Matsuzaki2006ForwardCandidateScore.valid({
    required Matsuzaki2006CandidateSource source,
    required List<Matsuzaki2006ForwardMagnitudeSolution> solutions,
  }) => Matsuzaki2006ForwardCandidateScore._(
    source: source,
    solutions: solutions,
    invalidReason: null,
  );

  factory Matsuzaki2006ForwardCandidateScore.invalid({
    required Matsuzaki2006CandidateSource source,
    required Matsuzaki2006CandidateInvalidReason reason,
  }) => Matsuzaki2006ForwardCandidateScore._(
    source: source,
    solutions: const [],
    invalidReason: reason,
  );

  final Matsuzaki2006CandidateSource source;
  final List<Matsuzaki2006ForwardMagnitudeSolution> solutions;
  final Matsuzaki2006CandidateInvalidReason? invalidReason;

  bool get isValid => invalidReason == null;
  double? get minimumIntensityRms =>
      isValid ? solutions.first.intensityRms : null;
}

class Matsuzaki2006ForwardResidualScorer {
  const Matsuzaki2006ForwardResidualScorer({
    this.model = const Matsuzaki2006AttenuationModel(),
    this.stationBiasModel,
    this.stationBiasShrinkage = const Matsuzaki2006StationBiasShrinkage(
      pseudoEventCount: 0,
    ),
  });

  final Matsuzaki2006AttenuationModel model;
  final Matsuzaki2006StationBiasModel? stationBiasModel;
  final Matsuzaki2006StationBiasShrinkage stationBiasShrinkage;

  Matsuzaki2006ForwardCandidateScore score({
    required List<Matsuzaki2006IntensityObservation> observations,
    required Matsuzaki2006CandidateSource source,
    required int minimumObservations,
    required Matsuzaki2006ForwardSearchSpec searchSpec,
  }) {
    _validateScoringInput(
      observations: observations,
      source: source,
      minimumObservations: minimumObservations,
    );
    searchSpec.validate();
    return _score(
      observations: observations,
      source: source,
      minimumObservations: minimumObservations,
      searchSpec: searchSpec,
      sourceDistance: _sourceDistance,
      stationCorrection: _stationCorrection,
    );
  }

  /// Scores a source after the caller has validated the complete input once.
  ///
  /// This is for bounded candidate loops only. It preserves the same forward
  /// model and magnitude optimization as [score], while avoiding repeated
  /// station-ID, coordinate, and search-spec validation for every candidate.
  Matsuzaki2006ForwardCandidateScore scorePrevalidated({
    required List<Matsuzaki2006IntensityObservation> observations,
    required Matsuzaki2006CandidateSource source,
    required int minimumObservations,
    required Matsuzaki2006ForwardSearchSpec searchSpec,
  }) => _score(
    observations: observations,
    source: source,
    minimumObservations: minimumObservations,
    searchSpec: searchSpec,
    sourceDistance: _sourceDistancePrevalidated,
    stationCorrection: _stationCorrection,
  );

  Matsuzaki2006ForwardCandidateScore _score({
    required List<Matsuzaki2006IntensityObservation> observations,
    required Matsuzaki2006CandidateSource source,
    required int minimumObservations,
    required Matsuzaki2006ForwardSearchSpec searchSpec,
    required double Function(
      Matsuzaki2006IntensityObservation observation,
      Matsuzaki2006CandidateSource source,
    )
    sourceDistance,
    required double Function(Matsuzaki2006IntensityObservation observation)
    stationCorrection,
  }) {
    if (observations.length < minimumObservations) {
      return Matsuzaki2006ForwardCandidateScore.invalid(
        source: source,
        reason: Matsuzaki2006CandidateInvalidReason.insufficientObservations,
      );
    }
    final stations = <_ForwardStation>[];
    for (final observation in observations) {
      final distanceKm = sourceDistance(observation, source);
      if (!_distanceIsInsideModel(distanceKm)) {
        return Matsuzaki2006ForwardCandidateScore.invalid(
          source: source,
          reason: Matsuzaki2006CandidateInvalidReason
              .sourceDistanceOutsideCalibrationRange,
        );
      }
      stations.add(
        _ForwardStation(
          observation: observation,
          sourceDistanceKm: distanceKm,
          stationCorrection: stationCorrection(observation),
        ),
      );
    }

    final scanMagnitudes = _scanMagnitudes(searchSpec.magnitudeScanStep);
    final scanObjectives = [
      for (final magnitude in scanMagnitudes)
        _meanSquaredIntensityResidual(stations, source.depthKm, magnitude),
    ];
    final localMinimumIndices = <int>[];
    for (var index = 0; index < scanMagnitudes.length; index++) {
      final left = index == 0 ? double.infinity : scanObjectives[index - 1];
      final right = index == scanMagnitudes.length - 1
          ? double.infinity
          : scanObjectives[index + 1];
      if (scanObjectives[index] <= left && scanObjectives[index] <= right) {
        localMinimumIndices.add(index);
      }
    }
    if (localMinimumIndices.isEmpty) {
      return Matsuzaki2006ForwardCandidateScore.invalid(
        source: source,
        reason: Matsuzaki2006CandidateInvalidReason.magnitudeOptimizationFailed,
      );
    }

    final magnitudeCandidates = <double>[];
    for (final index in localMinimumIndices) {
      if (index == 0 || index == scanMagnitudes.length - 1) {
        magnitudeCandidates.add(scanMagnitudes[index]);
        continue;
      }
      magnitudeCandidates.add(
        _goldenSectionMinimum(
          lower: scanMagnitudes[index - 1],
          upper: scanMagnitudes[index + 1],
          objective: (magnitude) => _meanSquaredIntensityResidual(
            stations,
            source.depthKm,
            magnitude,
          ),
          tolerance: searchSpec.refinementTolerance,
          maximumIterations: searchSpec.maximumRefinementIterations,
        ),
      );
    }
    final objectiveByMagnitude = <double, double>{
      for (final magnitude in magnitudeCandidates)
        magnitude: _meanSquaredIntensityResidual(
          stations,
          source.depthKm,
          magnitude,
        ),
    };
    final minimumObjective = objectiveByMagnitude.values.reduce(math.min);
    final bestMagnitudes =
        objectiveByMagnitude.entries
            .where(
              (entry) =>
                  entry.value - minimumObjective <=
                  searchSpec.objectiveTieTolerance,
            )
            .map((entry) => entry.key)
            .toList()
          ..sort();
    final solutions = [
      for (final magnitude in bestMagnitudes)
        _forwardSolution(stations, source.depthKm, magnitude),
    ];
    return Matsuzaki2006ForwardCandidateScore.valid(
      source: source,
      solutions: solutions,
    );
  }

  double _stationCorrection(Matsuzaki2006IntensityObservation observation) {
    final model = stationBiasModel;
    if (model == null) return 0;
    final estimate = model.estimates[observation.id];
    if (estimate == null ||
        estimate.latitude != observation.latitude ||
        estimate.longitude != observation.longitude) {
      return 0;
    }
    return stationBiasShrinkage.apply(estimate);
  }

  List<double> _scanMagnitudes(double step) {
    final values = <double>[];
    var magnitude = Matsuzaki2006AttenuationModel.minimumMagnitude;
    while (magnitude < Matsuzaki2006AttenuationModel.maximumMagnitude) {
      values.add(magnitude);
      magnitude += step;
    }
    values.add(Matsuzaki2006AttenuationModel.maximumMagnitude);
    return values;
  }

  double _meanSquaredIntensityResidual(
    List<_ForwardStation> stations,
    double depthKm,
    double magnitude,
  ) {
    var squaredSum = 0.0;
    for (final station in stations) {
      final predicted =
          model.predictIntensity(
            magnitude: magnitude,
            sourceDistanceKm: station.sourceDistanceKm,
            depthKm: depthKm,
          ) +
          station.stationCorrection;
      final residual = station.observation.intensity - predicted;
      squaredSum += residual * residual;
    }
    return squaredSum / stations.length;
  }

  Matsuzaki2006ForwardMagnitudeSolution _forwardSolution(
    List<_ForwardStation> stations,
    double depthKm,
    double magnitude,
  ) {
    final residuals = <Matsuzaki2006ForwardStationResidual>[];
    var residualSum = 0.0;
    var squaredSum = 0.0;
    for (final station in stations) {
      final predicted =
          model.predictIntensity(
            magnitude: magnitude,
            sourceDistanceKm: station.sourceDistanceKm,
            depthKm: depthKm,
          ) +
          station.stationCorrection;
      final result = Matsuzaki2006ForwardStationResidual(
        observationId: station.observation.id,
        sourceDistanceKm: station.sourceDistanceKm,
        observedIntensity: station.observation.intensity,
        predictedIntensity: predicted,
      );
      residuals.add(result);
      residualSum += result.residual;
      squaredSum += result.residual * result.residual;
    }
    return Matsuzaki2006ForwardMagnitudeSolution(
      magnitude: magnitude,
      intensityRms: math.sqrt(squaredSum / residuals.length),
      meanIntensityResidual: residualSum / residuals.length,
      stationResiduals: residuals,
    );
  }

  double _goldenSectionMinimum({
    required double lower,
    required double upper,
    required double Function(double magnitude) objective,
    required double tolerance,
    required int maximumIterations,
  }) {
    const inversePhi = 0.6180339887498949;
    var left = lower;
    var right = upper;
    var c = right - (right - left) * inversePhi;
    var d = left + (right - left) * inversePhi;
    var fc = objective(c);
    var fd = objective(d);
    for (
      var iteration = 0;
      iteration < maximumIterations && right - left > tolerance;
      iteration++
    ) {
      if (fc <= fd) {
        right = d;
        d = c;
        fd = fc;
        c = right - (right - left) * inversePhi;
        fc = objective(c);
      } else {
        left = c;
        c = d;
        fc = fd;
        d = left + (right - left) * inversePhi;
        fd = objective(d);
      }
    }
    if (right - left > tolerance) {
      throw StateError('Forward magnitude refinement did not converge.');
    }
    return (left + right) / 2;
  }
}

class _StationRootSet {
  _StationRootSet({
    required this.observationId,
    required this.sourceDistanceKm,
    required List<double> roots,
  }) : roots = List.unmodifiable(roots);

  final String observationId;
  final double sourceDistanceKm;
  final List<double> roots;
}

class _ForwardStation {
  const _ForwardStation({
    required this.observation,
    required this.sourceDistanceKm,
    required this.stationCorrection,
  });

  final Matsuzaki2006IntensityObservation observation;
  final double sourceDistanceKm;
  final double stationCorrection;
}

double _sourceDistance(
  Matsuzaki2006IntensityObservation observation,
  Matsuzaki2006CandidateSource source,
) => Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
  sourceLatitude: source.latitude,
  sourceLongitude: source.longitude,
  stationLatitude: observation.latitude,
  stationLongitude: observation.longitude,
  depthKm: source.depthKm,
);

double _sourceDistancePrevalidated(
  Matsuzaki2006IntensityObservation observation,
  Matsuzaki2006CandidateSource source,
) {
  final epicentralDistanceKm = QuakeCalculator.haversineDistance(
    source.latitude,
    source.longitude,
    observation.latitude,
    observation.longitude,
  );
  return math.sqrt(
    epicentralDistanceKm * epicentralDistanceKm +
        source.depthKm * source.depthKm,
  );
}

bool _distanceIsInsideModel(double distanceKm) =>
    distanceKm >= Matsuzaki2006AttenuationModel.minimumSourceDistanceKm &&
    distanceKm <= Matsuzaki2006AttenuationModel.maximumSourceDistanceKm;

void _validateScoringInput({
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006CandidateSource source,
  required int minimumObservations,
}) {
  if (minimumObservations <= 0) {
    throw ArgumentError.value(
      minimumObservations,
      'minimumObservations',
      'Must be positive.',
    );
  }
  if (!source.latitude.isFinite ||
      source.latitude < -90 ||
      source.latitude > 90 ||
      !source.longitude.isFinite ||
      source.longitude < -180 ||
      source.longitude > 180 ||
      !source.depthKm.isFinite ||
      source.depthKm < Matsuzaki2006AttenuationModel.minimumDepthKm ||
      source.depthKm > Matsuzaki2006AttenuationModel.maximumObservedDepthKm) {
    throw ArgumentError('Candidate source coordinates and depth are invalid.');
  }
  final ids = <String>{};
  for (final observation in observations) {
    if (observation.id.isEmpty || !ids.add(observation.id)) {
      throw ArgumentError(
        'Observation identifiers must be non-empty and unique.',
      );
    }
    if (!observation.latitude.isFinite ||
        observation.latitude < -90 ||
        observation.latitude > 90 ||
        !observation.longitude.isFinite ||
        observation.longitude < -180 ||
        observation.longitude > 180 ||
        !observation.intensity.isFinite) {
      throw ArgumentError(
        'Observation coordinates and intensity must be finite.',
      );
    }
  }
}
