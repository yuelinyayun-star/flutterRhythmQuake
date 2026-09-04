import 'dart:math' as math;

import 'matsuzaki_2006_attenuation_model.dart';
import 'matsuzaki_2006_candidate_scoring.dart';
import 'matsuzaki_2006_geometry.dart';
import 'matsuzaki_2006_station_bias.dart';

/// Unknown events have no independently observed rupture surface at inference
/// time. Experiment 1 therefore searches candidate point sources only.
enum Matsuzaki2006InversionDistanceSemantics { candidatePointSource }

enum Matsuzaki2006JointInversionStatus {
  solved,
  multipleEquivalentSolutions,
  hardBoundaryReached,
  expansionLimitReached,
  candidateBudgetExceeded,
  insufficientObservations,
  noValidCandidate,
}

enum Matsuzaki2006SearchBoundary {
  latitudeMinimum,
  latitudeMaximum,
  longitudeMinimum,
  longitudeMaximum,
  depthMinimum,
  depthMaximum,
  radialMaximum,
}

class Matsuzaki2006RadialSearchConstraint {
  const Matsuzaki2006RadialSearchConstraint({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.maximumEpicentralDistanceKm,
  });

  final double centerLatitude;
  final double centerLongitude;
  final double maximumEpicentralDistanceKm;

  void validate() {
    if (!centerLatitude.isFinite ||
        centerLatitude < -90 ||
        centerLatitude > 90 ||
        !centerLongitude.isFinite ||
        centerLongitude < -180 ||
        centerLongitude > 180) {
      throw ArgumentError('Radial search center coordinates are invalid.');
    }
    if (!maximumEpicentralDistanceKm.isFinite ||
        maximumEpicentralDistanceKm <= 0) {
      throw ArgumentError.value(
        maximumEpicentralDistanceKm,
        'maximumEpicentralDistanceKm',
        'Must be finite and positive.',
      );
    }
  }
}

class Matsuzaki2006HorizontalBounds {
  const Matsuzaki2006HorizontalBounds({
    required this.minimumLatitude,
    required this.maximumLatitude,
    required this.minimumLongitude,
    required this.maximumLongitude,
  });

  final double minimumLatitude;
  final double maximumLatitude;
  final double minimumLongitude;
  final double maximumLongitude;

  bool contains(Matsuzaki2006HorizontalBounds other) =>
      other.minimumLatitude >= minimumLatitude &&
      other.maximumLatitude <= maximumLatitude &&
      other.minimumLongitude >= minimumLongitude &&
      other.maximumLongitude <= maximumLongitude;

  void validate(String name) {
    if (!minimumLatitude.isFinite ||
        !maximumLatitude.isFinite ||
        minimumLatitude < -90 ||
        maximumLatitude > 90 ||
        minimumLatitude >= maximumLatitude) {
      throw ArgumentError.value(
        this,
        name,
        'Latitude bounds must be finite, ordered, and inside -90..90.',
      );
    }
    if (!minimumLongitude.isFinite ||
        !maximumLongitude.isFinite ||
        minimumLongitude < -180 ||
        maximumLongitude > 180 ||
        minimumLongitude >= maximumLongitude) {
      throw ArgumentError.value(
        this,
        name,
        'Longitude bounds must be finite, ordered, and inside -180..180.',
      );
    }
  }
}

class Matsuzaki2006JointSearchStage {
  const Matsuzaki2006JointSearchStage({
    required this.latitudeStepDegrees,
    required this.longitudeStepDegrees,
    required this.depthStepKm,
  }) : maximumRefinementSeedCount = null,
       refinementSeedRmsIncrease = null;

  const Matsuzaki2006JointSearchStage.refinePreviousCandidates({
    required this.latitudeStepDegrees,
    required this.longitudeStepDegrees,
    required this.depthStepKm,
    required int maximumSeedCount,
    required double seedRmsIncrease,
  }) : maximumRefinementSeedCount = maximumSeedCount,
       refinementSeedRmsIncrease = seedRmsIncrease;

  final double latitudeStepDegrees;
  final double longitudeStepDegrees;
  final double depthStepKm;
  final int? maximumRefinementSeedCount;
  final double? refinementSeedRmsIncrease;

  bool get refinesPreviousCandidates => maximumRefinementSeedCount != null;

  void validate(int index) {
    if (!latitudeStepDegrees.isFinite || latitudeStepDegrees <= 0) {
      throw ArgumentError.value(
        latitudeStepDegrees,
        'stages[$index].latitudeStepDegrees',
        'Must be finite and positive.',
      );
    }
    if (!longitudeStepDegrees.isFinite || longitudeStepDegrees <= 0) {
      throw ArgumentError.value(
        longitudeStepDegrees,
        'stages[$index].longitudeStepDegrees',
        'Must be finite and positive.',
      );
    }
    if (!depthStepKm.isFinite || depthStepKm <= 0) {
      throw ArgumentError.value(
        depthStepKm,
        'stages[$index].depthStepKm',
        'Must be finite and positive.',
      );
    }
    if (refinesPreviousCandidates) {
      if (maximumRefinementSeedCount! <= 0) {
        throw ArgumentError.value(
          maximumRefinementSeedCount,
          'stages[$index].maximumSeedCount',
          'Must be positive.',
        );
      }
      if (refinementSeedRmsIncrease == null ||
          !refinementSeedRmsIncrease!.isFinite ||
          refinementSeedRmsIncrease! < 0) {
        throw ArgumentError.value(
          refinementSeedRmsIncrease,
          'stages[$index].seedRmsIncrease',
          'Must be finite and non-negative.',
        );
      }
    } else if (refinementSeedRmsIncrease != null) {
      throw StateError('A full-grid stage cannot define refinement settings.');
    }
  }
}

class Matsuzaki2006JointSearchSpec {
  Matsuzaki2006JointSearchSpec({
    required this.initialHorizontalBounds,
    required this.hardHorizontalBounds,
    required this.minimumDepthKm,
    required this.maximumDepthKm,
    required this.radialSearchConstraint,
    required List<Matsuzaki2006JointSearchStage> stages,
    required this.horizontalExpansionDegrees,
    required this.maximumHorizontalExpansionRounds,
    required this.maximumCandidateEvaluations,
    required this.minimumObservations,
    required this.equivalentObjectiveTolerance,
    required this.resolutionRmsIncrease,
    required this.magnitudeSearchSpec,
  }) : stages = List.unmodifiable(stages);

  final Matsuzaki2006HorizontalBounds initialHorizontalBounds;
  final Matsuzaki2006HorizontalBounds hardHorizontalBounds;
  final double minimumDepthKm;
  final double maximumDepthKm;
  final Matsuzaki2006RadialSearchConstraint? radialSearchConstraint;
  final List<Matsuzaki2006JointSearchStage> stages;
  final double horizontalExpansionDegrees;
  final int maximumHorizontalExpansionRounds;
  final int maximumCandidateEvaluations;
  final int minimumObservations;
  final double equivalentObjectiveTolerance;

  /// A diagnostic RMS envelope, not a probability or confidence interval.
  final double resolutionRmsIncrease;
  final Matsuzaki2006ForwardSearchSpec magnitudeSearchSpec;

  void validate() {
    initialHorizontalBounds.validate('initialHorizontalBounds');
    hardHorizontalBounds.validate('hardHorizontalBounds');
    if (!hardHorizontalBounds.contains(initialHorizontalBounds)) {
      throw ArgumentError(
        'hardHorizontalBounds must contain initialHorizontalBounds.',
      );
    }
    radialSearchConstraint?.validate();
    if (!minimumDepthKm.isFinite ||
        !maximumDepthKm.isFinite ||
        minimumDepthKm < Matsuzaki2006AttenuationModel.minimumDepthKm ||
        maximumDepthKm > Matsuzaki2006AttenuationModel.maximumObservedDepthKm ||
        minimumDepthKm >= maximumDepthKm) {
      throw ArgumentError(
        'Depth bounds must be finite, ordered, and inside the published data '
        'range.',
      );
    }
    if (stages.isEmpty) {
      throw ArgumentError.value(stages, 'stages', 'Must not be empty.');
    }
    if (stages.first.refinesPreviousCandidates) {
      throw ArgumentError('The first search stage must cover the full bounds.');
    }
    for (var index = 0; index < stages.length; index++) {
      stages[index].validate(index);
      if (index == 0) continue;
      final previous = stages[index - 1];
      final current = stages[index];
      if (current.latitudeStepDegrees >= previous.latitudeStepDegrees ||
          current.longitudeStepDegrees >= previous.longitudeStepDegrees ||
          current.depthStepKm >= previous.depthStepKm) {
        throw ArgumentError(
          'Every search stage must strictly refine latitude, longitude, and '
          'depth steps.',
        );
      }
    }
    if (!horizontalExpansionDegrees.isFinite ||
        horizontalExpansionDegrees <= 0) {
      throw ArgumentError.value(
        horizontalExpansionDegrees,
        'horizontalExpansionDegrees',
        'Must be finite and positive.',
      );
    }
    if (maximumHorizontalExpansionRounds < 0) {
      throw ArgumentError.value(
        maximumHorizontalExpansionRounds,
        'maximumHorizontalExpansionRounds',
        'Must be non-negative.',
      );
    }
    if (maximumCandidateEvaluations <= 0) {
      throw ArgumentError.value(
        maximumCandidateEvaluations,
        'maximumCandidateEvaluations',
        'Must be positive.',
      );
    }
    if (minimumObservations <= 0) {
      throw ArgumentError.value(
        minimumObservations,
        'minimumObservations',
        'Must be positive.',
      );
    }
    if (!equivalentObjectiveTolerance.isFinite ||
        equivalentObjectiveTolerance < 0) {
      throw ArgumentError.value(
        equivalentObjectiveTolerance,
        'equivalentObjectiveTolerance',
        'Must be finite and non-negative.',
      );
    }
    if (!resolutionRmsIncrease.isFinite || resolutionRmsIncrease < 0) {
      throw ArgumentError.value(
        resolutionRmsIncrease,
        'resolutionRmsIncrease',
        'Must be finite and non-negative.',
      );
    }
    magnitudeSearchSpec.validate();
  }
}

class Matsuzaki2006JointCandidate {
  const Matsuzaki2006JointCandidate({
    required this.source,
    required this.magnitude,
    required this.intensityRms,
    required this.meanIntensityResidual,
  });

  final Matsuzaki2006CandidateSource source;
  final double magnitude;
  final double intensityRms;
  final double meanIntensityResidual;
}

/// One candidate-source evaluation emitted only when an inversion caller
/// explicitly requests a diagnostic trace.
class Matsuzaki2006JointCandidateTraceEntry {
  const Matsuzaki2006JointCandidateTraceEntry({
    required this.stageIndex,
    required this.expansionRound,
    required this.source,
    required this.isValid,
    required this.invalidReason,
    required this.intensityRms,
    required this.magnitude,
    required this.meanIntensityResidual,
  });

  final int stageIndex;
  final int expansionRound;
  final Matsuzaki2006CandidateSource source;
  final bool isValid;
  final Matsuzaki2006CandidateInvalidReason? invalidReason;
  final double? intensityRms;
  final double? magnitude;
  final double? meanIntensityResidual;
}

class Matsuzaki2006JointSearchStageResult {
  const Matsuzaki2006JointSearchStageResult({
    required this.stageIndex,
    required this.expansionRound,
    required this.horizontalBounds,
    required this.candidateEvaluationCount,
    required this.validSolutionCount,
    required this.minimumIntensityRms,
  });

  final int stageIndex;
  final int expansionRound;
  final Matsuzaki2006HorizontalBounds horizontalBounds;
  final int candidateEvaluationCount;
  final int validSolutionCount;
  final double? minimumIntensityRms;
}

class Matsuzaki2006JointResolutionEnvelope {
  const Matsuzaki2006JointResolutionEnvelope({
    required this.maximumRmsIncrease,
    required this.minimumLatitude,
    required this.maximumLatitude,
    required this.minimumLongitude,
    required this.maximumLongitude,
    required this.minimumDepthKm,
    required this.maximumDepthKm,
    required this.minimumMagnitude,
    required this.maximumMagnitude,
  });

  final double maximumRmsIncrease;
  final double minimumLatitude;
  final double maximumLatitude;
  final double minimumLongitude;
  final double maximumLongitude;
  final double minimumDepthKm;
  final double maximumDepthKm;
  final double minimumMagnitude;
  final double maximumMagnitude;
}

class Matsuzaki2006JointInversionResult {
  Matsuzaki2006JointInversionResult({
    required this.status,
    required this.distanceSemantics,
    required this.candidateEvaluationCount,
    required List<Matsuzaki2006JointCandidate> bestCandidates,
    required List<Matsuzaki2006JointCandidate> resolutionCandidates,
    required List<Matsuzaki2006JointSearchStageResult> stageResults,
    required Set<Matsuzaki2006SearchBoundary> hardBoundaryContacts,
    required this.resolutionEnvelope,
  }) : bestCandidates = List.unmodifiable(bestCandidates),
       resolutionCandidates = List.unmodifiable(resolutionCandidates),
       stageResults = List.unmodifiable(stageResults),
       hardBoundaryContacts = Set.unmodifiable(hardBoundaryContacts);

  final Matsuzaki2006JointInversionStatus status;
  final Matsuzaki2006InversionDistanceSemantics distanceSemantics;
  final int candidateEvaluationCount;
  final List<Matsuzaki2006JointCandidate> bestCandidates;

  /// Candidates inside an explicitly configured RMS increase.
  ///
  /// This set is a grid-resolution diagnostic and has no probability meaning.
  final List<Matsuzaki2006JointCandidate> resolutionCandidates;
  final List<Matsuzaki2006JointSearchStageResult> stageResults;
  final Set<Matsuzaki2006SearchBoundary> hardBoundaryContacts;
  final Matsuzaki2006JointResolutionEnvelope? resolutionEnvelope;

  bool get hasSolution => bestCandidates.isNotEmpty;
  bool get isConverged =>
      status == Matsuzaki2006JointInversionStatus.solved ||
      status == Matsuzaki2006JointInversionStatus.multipleEquivalentSolutions;
}

class Matsuzaki2006JointInverter {
  const Matsuzaki2006JointInverter({
    required this.model,
    this.stationBiasModel,
    this.stationBiasShrinkage = const Matsuzaki2006StationBiasShrinkage(
      pseudoEventCount: 0,
    ),
  });

  final Matsuzaki2006AttenuationModel model;
  final Matsuzaki2006StationBiasModel? stationBiasModel;
  final Matsuzaki2006StationBiasShrinkage stationBiasShrinkage;

  Matsuzaki2006JointInversionResult invert({
    required List<Matsuzaki2006IntensityObservation> observations,
    required Matsuzaki2006JointSearchSpec searchSpec,
    void Function(Matsuzaki2006JointCandidateTraceEntry entry)?
    onCandidateEvaluated,
  }) {
    searchSpec.validate();
    _validateObservations(observations);
    if (observations.length < searchSpec.minimumObservations) {
      return _emptyResult(
        Matsuzaki2006JointInversionStatus.insufficientObservations,
      );
    }

    final scorer = Matsuzaki2006ForwardResidualScorer(
      model: model,
      stationBiasModel: stationBiasModel,
      stationBiasShrinkage: stationBiasShrinkage,
    );
    var horizontalBounds = searchSpec.initialHorizontalBounds;
    var expansionRounds = 0;
    var totalEvaluations = 0;
    var expansionLimitReached = false;
    var finalCandidates = <Matsuzaki2006JointCandidate>[];
    final stageResults = <Matsuzaki2006JointSearchStageResult>[];

    for (var stageIndex = 0; stageIndex < searchSpec.stages.length;) {
      final stage = searchSpec.stages[stageIndex];
      final sources = stage.refinesPreviousCandidates
          ? _refinementSources(
              previousCandidates: finalCandidates,
              previousStage: searchSpec.stages[stageIndex - 1],
              stage: stage,
              horizontalBounds: horizontalBounds,
              minimumDepthKm: searchSpec.minimumDepthKm,
              maximumDepthKm: searchSpec.maximumDepthKm,
              radialSearchConstraint: searchSpec.radialSearchConstraint,
            )
          : _fullGridSources(
              horizontalBounds: horizontalBounds,
              minimumDepthKm: searchSpec.minimumDepthKm,
              maximumDepthKm: searchSpec.maximumDepthKm,
              stage: stage,
              radialSearchConstraint: searchSpec.radialSearchConstraint,
            );
      final requiredEvaluations = sources.length;
      if (requiredEvaluations == 0) {
        return _resultFromCandidates(
          status: Matsuzaki2006JointInversionStatus.noValidCandidate,
          candidates: finalCandidates,
          searchSpec: searchSpec,
          horizontalBounds: horizontalBounds,
          totalEvaluations: totalEvaluations,
          stageResults: stageResults,
        );
      }
      if (requiredEvaluations >
          searchSpec.maximumCandidateEvaluations - totalEvaluations) {
        return _resultFromCandidates(
          status: Matsuzaki2006JointInversionStatus.candidateBudgetExceeded,
          candidates: finalCandidates,
          searchSpec: searchSpec,
          horizontalBounds: horizontalBounds,
          totalEvaluations: totalEvaluations,
          stageResults: stageResults,
        );
      }

      final evaluated = _evaluateSources(
        sources: sources,
        scorer: scorer,
        observations: observations,
        searchSpec: searchSpec,
        stageIndex: stageIndex,
        expansionRound: expansionRounds,
        onCandidateEvaluated: onCandidateEvaluated,
      );
      totalEvaluations += requiredEvaluations;
      finalCandidates = evaluated;
      stageResults.add(
        Matsuzaki2006JointSearchStageResult(
          stageIndex: stageIndex,
          expansionRound: expansionRounds,
          horizontalBounds: horizontalBounds,
          candidateEvaluationCount: requiredEvaluations,
          validSolutionCount: evaluated.length,
          minimumIntensityRms: evaluated.isEmpty
              ? null
              : evaluated.first.intensityRms,
        ),
      );

      if (evaluated.isEmpty) {
        return _resultFromCandidates(
          status: Matsuzaki2006JointInversionStatus.noValidCandidate,
          candidates: const [],
          searchSpec: searchSpec,
          horizontalBounds: horizontalBounds,
          totalEvaluations: totalEvaluations,
          stageResults: stageResults,
        );
      }

      final best = _bestCandidates(
        evaluated,
        searchSpec.equivalentObjectiveTolerance,
      );
      final currentContacts = _horizontalBoundaryContacts(
        candidates: best,
        bounds: horizontalBounds,
        stage: stage,
      );
      final expandableContacts = currentContacts.where(
        (boundary) => _canExpand(
          boundary: boundary,
          current: horizontalBounds,
          hard: searchSpec.hardHorizontalBounds,
        ),
      );
      if (expandableContacts.isNotEmpty) {
        if (expansionRounds >= searchSpec.maximumHorizontalExpansionRounds) {
          expansionLimitReached = true;
          stageIndex++;
          continue;
        }
        horizontalBounds = _expandedBounds(
          current: horizontalBounds,
          hard: searchSpec.hardHorizontalBounds,
          contacts: expandableContacts.toSet(),
          expansionDegrees: searchSpec.horizontalExpansionDegrees,
        );
        expansionRounds++;
        stageIndex = 0;
        finalCandidates = const [];
        continue;
      }
      stageIndex++;
    }

    final hardContacts = _hardBoundaryContacts(
      candidates: _bestCandidates(
        finalCandidates,
        searchSpec.equivalentObjectiveTolerance,
      ),
      hardHorizontalBounds: searchSpec.hardHorizontalBounds,
      minimumDepthKm: searchSpec.minimumDepthKm,
      maximumDepthKm: searchSpec.maximumDepthKm,
      finalStage: searchSpec.stages.last,
      radialSearchConstraint: searchSpec.radialSearchConstraint,
    );
    final best = _bestCandidates(
      finalCandidates,
      searchSpec.equivalentObjectiveTolerance,
    );
    final status = hardContacts.isNotEmpty
        ? Matsuzaki2006JointInversionStatus.hardBoundaryReached
        : expansionLimitReached
        ? Matsuzaki2006JointInversionStatus.expansionLimitReached
        : best.length > 1
        ? Matsuzaki2006JointInversionStatus.multipleEquivalentSolutions
        : Matsuzaki2006JointInversionStatus.solved;
    return _resultFromCandidates(
      status: status,
      candidates: finalCandidates,
      searchSpec: searchSpec,
      horizontalBounds: horizontalBounds,
      totalEvaluations: totalEvaluations,
      stageResults: stageResults,
    );
  }

  List<Matsuzaki2006JointCandidate> _evaluateSources({
    required List<Matsuzaki2006CandidateSource> sources,
    required Matsuzaki2006ForwardResidualScorer scorer,
    required List<Matsuzaki2006IntensityObservation> observations,
    required Matsuzaki2006JointSearchSpec searchSpec,
    required int stageIndex,
    required int expansionRound,
    required void Function(Matsuzaki2006JointCandidateTraceEntry entry)?
    onCandidateEvaluated,
  }) {
    final candidates = <Matsuzaki2006JointCandidate>[];
    for (final source in sources) {
      final score = scorer.scorePrevalidated(
        observations: observations,
        source: source,
        minimumObservations: searchSpec.minimumObservations,
        searchSpec: searchSpec.magnitudeSearchSpec,
      );
      if (!score.isValid || score.solutions.isEmpty) {
        onCandidateEvaluated?.call(
          Matsuzaki2006JointCandidateTraceEntry(
            stageIndex: stageIndex,
            expansionRound: expansionRound,
            source: source,
            isValid: false,
            invalidReason: score.invalidReason,
            intensityRms: null,
            magnitude: null,
            meanIntensityResidual: null,
          ),
        );
        continue;
      }
      final firstSolution = score.solutions.first;
      onCandidateEvaluated?.call(
        Matsuzaki2006JointCandidateTraceEntry(
          stageIndex: stageIndex,
          expansionRound: expansionRound,
          source: source,
          isValid: true,
          invalidReason: null,
          intensityRms: firstSolution.intensityRms,
          magnitude: firstSolution.magnitude,
          meanIntensityResidual: firstSolution.meanIntensityResidual,
        ),
      );
      for (final solution in score.solutions) {
        candidates.add(
          Matsuzaki2006JointCandidate(
            source: source,
            magnitude: solution.magnitude,
            intensityRms: solution.intensityRms,
            meanIntensityResidual: solution.meanIntensityResidual,
          ),
        );
      }
    }
    candidates.sort(_compareCandidates);
    return candidates;
  }

  Matsuzaki2006JointInversionResult _resultFromCandidates({
    required Matsuzaki2006JointInversionStatus status,
    required List<Matsuzaki2006JointCandidate> candidates,
    required Matsuzaki2006JointSearchSpec searchSpec,
    required Matsuzaki2006HorizontalBounds horizontalBounds,
    required int totalEvaluations,
    required List<Matsuzaki2006JointSearchStageResult> stageResults,
  }) {
    if (candidates.isEmpty) {
      return Matsuzaki2006JointInversionResult(
        status: status,
        distanceSemantics:
            Matsuzaki2006InversionDistanceSemantics.candidatePointSource,
        candidateEvaluationCount: totalEvaluations,
        bestCandidates: const [],
        resolutionCandidates: const [],
        stageResults: stageResults,
        hardBoundaryContacts: const {},
        resolutionEnvelope: null,
      );
    }
    final best = _bestCandidates(
      candidates,
      searchSpec.equivalentObjectiveTolerance,
    );
    final resolution = candidates
        .where(
          (candidate) =>
              candidate.intensityRms - candidates.first.intensityRms <=
              searchSpec.resolutionRmsIncrease,
        )
        .toList();
    final finalStage = searchSpec.stages.last;
    final hardContacts = _hardBoundaryContacts(
      candidates: best,
      hardHorizontalBounds: searchSpec.hardHorizontalBounds,
      minimumDepthKm: searchSpec.minimumDepthKm,
      maximumDepthKm: searchSpec.maximumDepthKm,
      finalStage: finalStage,
      radialSearchConstraint: searchSpec.radialSearchConstraint,
    );
    return Matsuzaki2006JointInversionResult(
      status: status,
      distanceSemantics:
          Matsuzaki2006InversionDistanceSemantics.candidatePointSource,
      candidateEvaluationCount: totalEvaluations,
      bestCandidates: best,
      resolutionCandidates: resolution,
      stageResults: stageResults,
      hardBoundaryContacts: hardContacts,
      resolutionEnvelope: _resolutionEnvelope(
        resolution,
        searchSpec.resolutionRmsIncrease,
      ),
    );
  }

  Matsuzaki2006JointInversionResult _emptyResult(
    Matsuzaki2006JointInversionStatus status,
  ) => Matsuzaki2006JointInversionResult(
    status: status,
    distanceSemantics:
        Matsuzaki2006InversionDistanceSemantics.candidatePointSource,
    candidateEvaluationCount: 0,
    bestCandidates: const [],
    resolutionCandidates: const [],
    stageResults: const [],
    hardBoundaryContacts: const {},
    resolutionEnvelope: null,
  );
}

List<Matsuzaki2006JointCandidate> _bestCandidates(
  List<Matsuzaki2006JointCandidate> sortedCandidates,
  double tolerance,
) {
  if (sortedCandidates.isEmpty) return const [];
  final minimum = sortedCandidates.first.intensityRms;
  return sortedCandidates
      .where((candidate) => candidate.intensityRms - minimum <= tolerance)
      .toList();
}

int _compareCandidates(
  Matsuzaki2006JointCandidate left,
  Matsuzaki2006JointCandidate right,
) {
  var comparison = left.intensityRms.compareTo(right.intensityRms);
  if (comparison != 0) return comparison;
  comparison = left.source.latitude.compareTo(right.source.latitude);
  if (comparison != 0) return comparison;
  comparison = left.source.longitude.compareTo(right.source.longitude);
  if (comparison != 0) return comparison;
  comparison = left.source.depthKm.compareTo(right.source.depthKm);
  if (comparison != 0) return comparison;
  return left.magnitude.compareTo(right.magnitude);
}

List<Matsuzaki2006CandidateSource> _fullGridSources({
  required Matsuzaki2006HorizontalBounds horizontalBounds,
  required double minimumDepthKm,
  required double maximumDepthKm,
  required Matsuzaki2006JointSearchStage stage,
  required Matsuzaki2006RadialSearchConstraint? radialSearchConstraint,
}) {
  final sources = <Matsuzaki2006CandidateSource>[];
  for (final latitude in _axisValues(
    horizontalBounds.minimumLatitude,
    horizontalBounds.maximumLatitude,
    stage.latitudeStepDegrees,
  )) {
    for (final longitude in _axisValues(
      horizontalBounds.minimumLongitude,
      horizontalBounds.maximumLongitude,
      stage.longitudeStepDegrees,
    )) {
      if (_insideRadialConstraint(
        latitude: latitude,
        longitude: longitude,
        constraint: radialSearchConstraint,
      )) {
        for (final depthKm in _axisValues(
          minimumDepthKm,
          maximumDepthKm,
          stage.depthStepKm,
        )) {
          sources.add(
            Matsuzaki2006CandidateSource(
              latitude: latitude,
              longitude: longitude,
              depthKm: depthKm,
            ),
          );
        }
      }
    }
  }
  return sources;
}

List<Matsuzaki2006CandidateSource> _refinementSources({
  required List<Matsuzaki2006JointCandidate> previousCandidates,
  required Matsuzaki2006JointSearchStage previousStage,
  required Matsuzaki2006JointSearchStage stage,
  required Matsuzaki2006HorizontalBounds horizontalBounds,
  required double minimumDepthKm,
  required double maximumDepthKm,
  required Matsuzaki2006RadialSearchConstraint? radialSearchConstraint,
}) {
  if (previousCandidates.isEmpty || !stage.refinesPreviousCandidates) {
    return const [];
  }
  final minimumRms = previousCandidates.first.intensityRms;
  final seeds = <Matsuzaki2006CandidateSource>[];
  final seedKeys = <String>{};
  for (final candidate in previousCandidates) {
    if (candidate.intensityRms - minimumRms >
        stage.refinementSeedRmsIncrease!) {
      break;
    }
    final key = _sourceKey(candidate.source);
    if (!seedKeys.add(key)) continue;
    seeds.add(candidate.source);
    if (seeds.length >= stage.maximumRefinementSeedCount!) break;
  }
  if (seeds.isEmpty) seeds.add(previousCandidates.first.source);

  final sourcesByKey = <String, Matsuzaki2006CandidateSource>{};
  for (final seed in seeds) {
    final latitudeMinimum = math.max(
      horizontalBounds.minimumLatitude,
      seed.latitude - previousStage.latitudeStepDegrees,
    );
    final latitudeMaximum = math.min(
      horizontalBounds.maximumLatitude,
      seed.latitude + previousStage.latitudeStepDegrees,
    );
    final longitudeMinimum = math.max(
      horizontalBounds.minimumLongitude,
      seed.longitude - previousStage.longitudeStepDegrees,
    );
    final longitudeMaximum = math.min(
      horizontalBounds.maximumLongitude,
      seed.longitude + previousStage.longitudeStepDegrees,
    );
    final depthMinimum = math.max(
      minimumDepthKm,
      seed.depthKm - previousStage.depthStepKm,
    );
    final depthMaximum = math.min(
      maximumDepthKm,
      seed.depthKm + previousStage.depthStepKm,
    );
    for (final latitude in _axisValues(
      latitudeMinimum,
      latitudeMaximum,
      stage.latitudeStepDegrees,
    )) {
      for (final longitude in _axisValues(
        longitudeMinimum,
        longitudeMaximum,
        stage.longitudeStepDegrees,
      )) {
        if (!_insideRadialConstraint(
          latitude: latitude,
          longitude: longitude,
          constraint: radialSearchConstraint,
        )) {
          continue;
        }
        for (final depthKm in _axisValues(
          depthMinimum,
          depthMaximum,
          stage.depthStepKm,
        )) {
          final source = Matsuzaki2006CandidateSource(
            latitude: latitude,
            longitude: longitude,
            depthKm: depthKm,
          );
          sourcesByKey[_sourceKey(source)] = source;
        }
      }
    }
  }
  final sources = sourcesByKey.values.toList()
    ..sort((left, right) {
      var comparison = left.latitude.compareTo(right.latitude);
      if (comparison != 0) return comparison;
      comparison = left.longitude.compareTo(right.longitude);
      return comparison != 0
          ? comparison
          : left.depthKm.compareTo(right.depthKm);
    });
  return sources;
}

String _sourceKey(Matsuzaki2006CandidateSource source) =>
    '${(source.latitude * 1e10).round()}|'
    '${(source.longitude * 1e10).round()}|'
    '${(source.depthKm * 1e8).round()}';

int _axisCount(double minimum, double maximum, double step) =>
    ((maximum - minimum) / step).floor() +
    (_almostEqual(
          minimum + ((maximum - minimum) / step).floor() * step,
          maximum,
          step,
        )
        ? 1
        : 2);

List<double> _axisValues(double minimum, double maximum, double step) {
  final count = _axisCount(minimum, maximum, step);
  return [
    for (var index = 0; index < count; index++)
      index == count - 1 ? maximum : minimum + index * step,
  ];
}

Set<Matsuzaki2006SearchBoundary> _horizontalBoundaryContacts({
  required List<Matsuzaki2006JointCandidate> candidates,
  required Matsuzaki2006HorizontalBounds bounds,
  required Matsuzaki2006JointSearchStage stage,
}) {
  final contacts = <Matsuzaki2006SearchBoundary>{};
  for (final candidate in candidates) {
    if (_almostEqual(
      candidate.source.latitude,
      bounds.minimumLatitude,
      stage.latitudeStepDegrees,
    )) {
      contacts.add(Matsuzaki2006SearchBoundary.latitudeMinimum);
    }
    if (_almostEqual(
      candidate.source.latitude,
      bounds.maximumLatitude,
      stage.latitudeStepDegrees,
    )) {
      contacts.add(Matsuzaki2006SearchBoundary.latitudeMaximum);
    }
    if (_almostEqual(
      candidate.source.longitude,
      bounds.minimumLongitude,
      stage.longitudeStepDegrees,
    )) {
      contacts.add(Matsuzaki2006SearchBoundary.longitudeMinimum);
    }
    if (_almostEqual(
      candidate.source.longitude,
      bounds.maximumLongitude,
      stage.longitudeStepDegrees,
    )) {
      contacts.add(Matsuzaki2006SearchBoundary.longitudeMaximum);
    }
  }
  return contacts;
}

Set<Matsuzaki2006SearchBoundary> _hardBoundaryContacts({
  required List<Matsuzaki2006JointCandidate> candidates,
  required Matsuzaki2006HorizontalBounds hardHorizontalBounds,
  required double minimumDepthKm,
  required double maximumDepthKm,
  required Matsuzaki2006JointSearchStage finalStage,
  required Matsuzaki2006RadialSearchConstraint? radialSearchConstraint,
}) {
  final contacts = _horizontalBoundaryContacts(
    candidates: candidates,
    bounds: hardHorizontalBounds,
    stage: finalStage,
  );
  for (final candidate in candidates) {
    if (_almostEqual(
      candidate.source.depthKm,
      minimumDepthKm,
      finalStage.depthStepKm,
    )) {
      contacts.add(Matsuzaki2006SearchBoundary.depthMinimum);
    }
    if (_almostEqual(
      candidate.source.depthKm,
      maximumDepthKm,
      finalStage.depthStepKm,
    )) {
      contacts.add(Matsuzaki2006SearchBoundary.depthMaximum);
    }
    if (radialSearchConstraint != null) {
      final distanceKm = _epicentralDistanceToRadialCenter(
        latitude: candidate.source.latitude,
        longitude: candidate.source.longitude,
        constraint: radialSearchConstraint,
      );
      final gridToleranceKm =
          math.sqrt(
            finalStage.latitudeStepDegrees * finalStage.latitudeStepDegrees +
                finalStage.longitudeStepDegrees *
                    finalStage.longitudeStepDegrees,
          ) *
          _maximumKilometresPerDegree;
      if (radialSearchConstraint.maximumEpicentralDistanceKm - distanceKm <=
          gridToleranceKm) {
        contacts.add(Matsuzaki2006SearchBoundary.radialMaximum);
      }
    }
  }
  return contacts;
}

bool _canExpand({
  required Matsuzaki2006SearchBoundary boundary,
  required Matsuzaki2006HorizontalBounds current,
  required Matsuzaki2006HorizontalBounds hard,
}) => switch (boundary) {
  Matsuzaki2006SearchBoundary.latitudeMinimum =>
    current.minimumLatitude > hard.minimumLatitude,
  Matsuzaki2006SearchBoundary.latitudeMaximum =>
    current.maximumLatitude < hard.maximumLatitude,
  Matsuzaki2006SearchBoundary.longitudeMinimum =>
    current.minimumLongitude > hard.minimumLongitude,
  Matsuzaki2006SearchBoundary.longitudeMaximum =>
    current.maximumLongitude < hard.maximumLongitude,
  Matsuzaki2006SearchBoundary.depthMinimum ||
  Matsuzaki2006SearchBoundary.depthMaximum ||
  Matsuzaki2006SearchBoundary.radialMaximum => false,
};

Matsuzaki2006HorizontalBounds _expandedBounds({
  required Matsuzaki2006HorizontalBounds current,
  required Matsuzaki2006HorizontalBounds hard,
  required Set<Matsuzaki2006SearchBoundary> contacts,
  required double expansionDegrees,
}) => Matsuzaki2006HorizontalBounds(
  minimumLatitude:
      contacts.contains(Matsuzaki2006SearchBoundary.latitudeMinimum)
      ? math.max(
          hard.minimumLatitude,
          current.minimumLatitude - expansionDegrees,
        )
      : current.minimumLatitude,
  maximumLatitude:
      contacts.contains(Matsuzaki2006SearchBoundary.latitudeMaximum)
      ? math.min(
          hard.maximumLatitude,
          current.maximumLatitude + expansionDegrees,
        )
      : current.maximumLatitude,
  minimumLongitude:
      contacts.contains(Matsuzaki2006SearchBoundary.longitudeMinimum)
      ? math.max(
          hard.minimumLongitude,
          current.minimumLongitude - expansionDegrees,
        )
      : current.minimumLongitude,
  maximumLongitude:
      contacts.contains(Matsuzaki2006SearchBoundary.longitudeMaximum)
      ? math.min(
          hard.maximumLongitude,
          current.maximumLongitude + expansionDegrees,
        )
      : current.maximumLongitude,
);

Matsuzaki2006JointResolutionEnvelope _resolutionEnvelope(
  List<Matsuzaki2006JointCandidate> candidates,
  double maximumRmsIncrease,
) {
  double minimum(double Function(Matsuzaki2006JointCandidate value) field) =>
      candidates.map(field).reduce(math.min);
  double maximum(double Function(Matsuzaki2006JointCandidate value) field) =>
      candidates.map(field).reduce(math.max);
  return Matsuzaki2006JointResolutionEnvelope(
    maximumRmsIncrease: maximumRmsIncrease,
    minimumLatitude: minimum((candidate) => candidate.source.latitude),
    maximumLatitude: maximum((candidate) => candidate.source.latitude),
    minimumLongitude: minimum((candidate) => candidate.source.longitude),
    maximumLongitude: maximum((candidate) => candidate.source.longitude),
    minimumDepthKm: minimum((candidate) => candidate.source.depthKm),
    maximumDepthKm: maximum((candidate) => candidate.source.depthKm),
    minimumMagnitude: minimum((candidate) => candidate.magnitude),
    maximumMagnitude: maximum((candidate) => candidate.magnitude),
  );
}

bool _almostEqual(double left, double right, double scale) =>
    (left - right).abs() <= math.max(1e-12, scale.abs() * 1e-9);

const double _maximumKilometresPerDegree = 111.2;

bool _insideRadialConstraint({
  required double latitude,
  required double longitude,
  required Matsuzaki2006RadialSearchConstraint? constraint,
}) =>
    constraint == null ||
    _epicentralDistanceToRadialCenter(
          latitude: latitude,
          longitude: longitude,
          constraint: constraint,
        ) <=
        constraint.maximumEpicentralDistanceKm;

double _epicentralDistanceToRadialCenter({
  required double latitude,
  required double longitude,
  required Matsuzaki2006RadialSearchConstraint constraint,
}) => Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
  sourceLatitude: constraint.centerLatitude,
  sourceLongitude: constraint.centerLongitude,
  stationLatitude: latitude,
  stationLongitude: longitude,
  depthKm: 0,
);

void _validateObservations(
  List<Matsuzaki2006IntensityObservation> observations,
) {
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
