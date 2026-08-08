import 'dart:math' as math;

import '../calculator.dart';
import 'gstsl_attenuation_model.dart';
import 'gstsl_models.dart';

/// Pure implementation of the paper's grid-search trial-source scoring.
class GstsReconstructor {
  const GstsReconstructor({
    this.attenuationModel =
        GstsPaperAttenuationModels.southwestChina2010Logarithmic,
    this.distanceWeightModel =
        GstsDistanceWeightModel.southwestChina2010Scoring,
  });

  final GstsAttenuationModel attenuationModel;
  final GstsDistanceWeightModel distanceWeightModel;

  GstsReconstructionResult reconstruct({
    required List<GstsIntensityObservation> observations,
    required List<GstsCandidateLocation> candidates,
  }) {
    _validateInput(observations, candidates);
    final rawScores = <GstsCandidateScore>[
      for (var index = 0; index < candidates.length; index++)
        _scoreCandidate(
          candidateIndex: index,
          location: candidates[index],
          observations: observations,
        ),
    ];
    final validScores = rawScores.where((score) => score.isValid).toList();
    if (validScores.isEmpty) {
      throw StateError('No candidate can be scored with the supplied model.');
    }
    final minimumRawRms = validScores
        .map((score) => score.rawRms!)
        .reduce(math.min);
    final normalized = [
      for (final score in rawScores)
        score.isValid
            ? score.withNormalizedRms(
                math.max(0, score.rawRms! - minimumRawRms),
              )
            : score,
    ];
    return GstsReconstructionResult(
      observationCount: observations.length,
      candidates: List.unmodifiable(normalized),
      minimumRawRms: minimumRawRms,
    );
  }

  GstsReconstructionResult reconstructGrid({
    required List<GstsIntensityObservation> observations,
    required GstsRegularGrid grid,
  }) {
    return reconstruct(observations: observations, candidates: grid.generate());
  }

  GstsCandidateScore _scoreCandidate({
    required int candidateIndex,
    required GstsCandidateLocation location,
    required List<GstsIntensityObservation> observations,
  }) {
    if (!_isFiniteLocation(location)) {
      return GstsCandidateScore.invalid(
        candidateIndex: candidateIndex,
        location: location,
        reason: GstsCandidateInvalidReason.nonFiniteInput,
      );
    }
    final stationMagnitudes = <GstsObservationMagnitude>[];
    var magnitudeSum = 0.0;
    for (final observation in observations) {
      final distanceKm = QuakeCalculator.haversineDistance(
        location.latitude,
        location.longitude,
        observation.coordinate.latitude,
        observation.coordinate.longitude,
      );
      if (!distanceKm.isFinite) {
        return GstsCandidateScore.invalid(
          candidateIndex: candidateIndex,
          location: location,
          reason: GstsCandidateInvalidReason.nonFiniteInput,
        );
      }
      if (attenuationModel.requiresPositiveDistance && distanceKm <= 0) {
        return GstsCandidateScore.invalid(
          candidateIndex: candidateIndex,
          location: location,
          reason: GstsCandidateInvalidReason.nonPositiveDistanceForLogarithm,
        );
      }
      final inferredMagnitude = attenuationModel.inferMagnitude(
        intensity: observation.intensity,
        distanceKm: distanceKm,
      );
      if (!inferredMagnitude.isFinite) {
        return GstsCandidateScore.invalid(
          candidateIndex: candidateIndex,
          location: location,
          reason: GstsCandidateInvalidReason.nonFiniteInferredMagnitude,
        );
      }
      final weight = distanceWeightModel.weight(distanceKm);
      stationMagnitudes.add(
        GstsObservationMagnitude(
          observationId: observation.id,
          distanceKm: distanceKm,
          distanceWeight: weight,
          inferredMagnitude: inferredMagnitude,
        ),
      );
      magnitudeSum += inferredMagnitude;
    }

    // Paper equation (3): M_I is the unweighted arithmetic mean of M_i.
    final intensityMagnitude = magnitudeSum / stationMagnitudes.length;
    var weightedSquaredResidualSum = 0.0;
    var squaredWeightSum = 0.0;
    for (final station in stationMagnitudes) {
      final squaredWeight = station.distanceWeight * station.distanceWeight;
      final residual = intensityMagnitude - station.inferredMagnitude;
      weightedSquaredResidualSum += squaredWeight * residual * residual;
      squaredWeightSum += squaredWeight;
    }
    if (squaredWeightSum <= 0 || !squaredWeightSum.isFinite) {
      return GstsCandidateScore.invalid(
        candidateIndex: candidateIndex,
        location: location,
        reason: GstsCandidateInvalidReason.zeroWeightSum,
      );
    }
    final rawRms = math.sqrt(weightedSquaredResidualSum / squaredWeightSum);
    return GstsCandidateScore.valid(
      candidateIndex: candidateIndex,
      location: location,
      observations: stationMagnitudes,
      intensityMagnitude: intensityMagnitude,
      rawRms: rawRms,
    );
  }

  void _validateInput(
    List<GstsIntensityObservation> observations,
    List<GstsCandidateLocation> candidates,
  ) {
    if (observations.isEmpty) {
      throw ArgumentError('At least one intensity observation is required.');
    }
    if (candidates.isEmpty) {
      throw ArgumentError('At least one candidate location is required.');
    }
    for (final observation in observations) {
      if (observation.id.isEmpty ||
          !observation.intensity.isFinite ||
          !observation.coordinate.latitude.isFinite ||
          !observation.coordinate.longitude.isFinite ||
          observation.coordinate.latitude < -90 ||
          observation.coordinate.latitude > 90) {
        throw ArgumentError('Intensity observations must be finite and valid.');
      }
    }
  }

  bool _isFiniteLocation(GstsCandidateLocation location) {
    return location.latitude.isFinite &&
        location.longitude.isFinite &&
        location.latitude >= -90 &&
        location.latitude <= 90;
  }
}
