import 'dart:math' as math;

import 'gstsl_attenuation_model.dart';
import 'gstsl_confidence_table.dart';
import 'gstsl_models.dart';
import 'gstsl_reconstructor.dart';

enum GstsEmpiricalQuantileRule { nearestRank }

/// An explicitly supplied candidate grid used by one calibration event.
///
/// The paper states its dimensions and spacing but not the geographic
/// projection used to build it. Callers therefore supply the actual candidate
/// coordinates instead of relying on a hidden km-to-degree conversion.
class GstsCalibrationGrid {
  GstsCalibrationGrid({
    required this.widthKm,
    required this.heightKm,
    required this.spacingKm,
    required List<GstsCandidateLocation> candidates,
    required this.referenceCandidateIndex,
  }) : candidates = List.unmodifiable(candidates);

  final double widthKm;
  final double heightKm;
  final double spacingKm;
  final List<GstsCandidateLocation> candidates;
  final int referenceCandidateIndex;
}

class GstsConfidenceCalibrationEvent {
  GstsConfidenceCalibrationEvent({
    required this.id,
    required List<GstsIntensityObservation> observations,
    required this.grid,
    required this.referenceMagnitude,
  }) : observations = List.unmodifiable(observations);

  final String id;
  final List<GstsIntensityObservation> observations;
  final GstsCalibrationGrid grid;
  final double referenceMagnitude;
}

class GstsConfidenceCalibrationSpec {
  GstsConfidenceCalibrationSpec({
    required this.attenuationModel,
    required this.distanceWeightModel,
    required List<int> observationCounts,
    required this.repetitionsPerEvent,
    required this.randomSeed,
    required List<GstsOneSidedProbability> probabilities,
    required this.quantileRule,
  }) : observationCounts = List.unmodifiable(observationCounts),
       probabilities = List.unmodifiable(probabilities);

  /// Regional relation used to derive each station magnitude `M_i`.
  final GstsAttenuationModel attenuationModel;

  /// Distance weighting used in the RMS surface for this calibration run.
  final GstsDistanceWeightModel distanceWeightModel;
  final List<int> observationCounts;
  final int repetitionsPerEvent;
  final int randomSeed;
  final List<GstsOneSidedProbability> probabilities;
  final GstsEmpiricalQuantileRule quantileRule;
}

class GstsConfidenceCalibrationSample {
  const GstsConfidenceCalibrationSample({
    required this.eventId,
    required this.observationCount,
    required this.repetitionIndex,
    required this.normalizedRmsAtReference,
    required this.magnitudeOffsetAtReference,
  });

  final String eventId;
  final int observationCount;
  final int repetitionIndex;
  final double normalizedRmsAtReference;

  /// `referenceMagnitude - M_I` at the reference epicenter candidate.
  final double magnitudeOffsetAtReference;
}

class GstsCalibratedConfidenceRow {
  GstsCalibratedConfidenceRow({
    required this.observationCount,
    required List<GstsConfidenceCalibrationSample> samples,
    required Map<GstsOneSidedProbability, double> epicenterThresholds,
    required Map<GstsOneSidedProbability, GstsMagnitudeOffsetBounds>
    magnitudeOneSidedLimits,
  }) : samples = List.unmodifiable(samples),
       epicenterThresholds = Map.unmodifiable(epicenterThresholds),
       magnitudeOneSidedLimits = Map.unmodifiable(magnitudeOneSidedLimits);

  final int observationCount;
  final List<GstsConfidenceCalibrationSample> samples;
  final Map<GstsOneSidedProbability, double> epicenterThresholds;
  final Map<GstsOneSidedProbability, GstsMagnitudeOffsetBounds>
  magnitudeOneSidedLimits;
}

class GstsConfidenceCalibrationResult {
  GstsConfidenceCalibrationResult({
    required this.spec,
    required List<GstsCalibratedConfidenceRow> rows,
  }) : rows = List.unmodifiable(rows);

  final GstsConfidenceCalibrationSpec spec;
  final List<GstsCalibratedConfidenceRow> rows;

  GstsCalibratedConfidenceRow? rowForObservationCount(int count) {
    for (final row in rows) {
      if (row.observationCount == count) return row;
    }
    return null;
  }
}

/// Reproduces the paper's random-subset confidence calibration structure.
///
/// The source papers do not state their random seed, quantile convention, or
/// geographic projection. Those choices are therefore required explicitly.
class GstsConfidenceCalibrator {
  const GstsConfidenceCalibrator();

  GstsConfidenceCalibrationResult calibrate({
    required List<GstsConfidenceCalibrationEvent> events,
    required GstsConfidenceCalibrationSpec spec,
  }) {
    _validate(events, spec);
    final reconstructor = GstsReconstructor(
      attenuationModel: spec.attenuationModel,
      distanceWeightModel: spec.distanceWeightModel,
    );
    final random = math.Random(spec.randomSeed);
    final rows = <GstsCalibratedConfidenceRow>[];

    for (final observationCount in spec.observationCounts) {
      final samples = <GstsConfidenceCalibrationSample>[];
      for (final event in events) {
        for (
          var repetitionIndex = 0;
          repetitionIndex < spec.repetitionsPerEvent;
          repetitionIndex++
        ) {
          final observations = _sampleWithoutReplacement(
            event.observations,
            observationCount,
            random,
          );
          final reconstruction = reconstructor.reconstruct(
            observations: observations,
            candidates: event.grid.candidates,
          );
          final referenceScore =
              reconstruction.candidates[event.grid.referenceCandidateIndex];
          if (!referenceScore.isValid) {
            throw StateError(
              'Reference candidate for event ${event.id} is not scoreable: '
              '${referenceScore.invalidReason}.',
            );
          }
          samples.add(
            GstsConfidenceCalibrationSample(
              eventId: event.id,
              observationCount: observationCount,
              repetitionIndex: repetitionIndex,
              normalizedRmsAtReference: referenceScore.normalizedRms!,
              magnitudeOffsetAtReference:
                  event.referenceMagnitude - referenceScore.intensityMagnitude!,
            ),
          );
        }
      }
      rows.add(_summarize(observationCount, samples, spec));
    }

    return GstsConfidenceCalibrationResult(spec: spec, rows: rows);
  }

  GstsCalibratedConfidenceRow _summarize(
    int observationCount,
    List<GstsConfidenceCalibrationSample> samples,
    GstsConfidenceCalibrationSpec spec,
  ) {
    final normalizedRmsValues =
        samples.map((sample) => sample.normalizedRmsAtReference).toList()
          ..sort();
    final magnitudeOffsets =
        samples.map((sample) => sample.magnitudeOffsetAtReference).toList()
          ..sort();
    final epicenterThresholds = <GstsOneSidedProbability, double>{};
    final magnitudeLimits =
        <GstsOneSidedProbability, GstsMagnitudeOffsetBounds>{};

    for (final probability in spec.probabilities) {
      final p = probability.probability;
      epicenterThresholds[probability] = _quantile(
        normalizedRmsValues,
        p,
        spec.quantileRule,
      );
      magnitudeLimits[probability] = GstsMagnitudeOffsetBounds(
        _quantile(magnitudeOffsets, 1 - p, spec.quantileRule),
        _quantile(magnitudeOffsets, p, spec.quantileRule),
      );
    }

    return GstsCalibratedConfidenceRow(
      observationCount: observationCount,
      samples: samples,
      epicenterThresholds: epicenterThresholds,
      magnitudeOneSidedLimits: magnitudeLimits,
    );
  }

  List<T> _sampleWithoutReplacement<T>(
    List<T> source,
    int count,
    math.Random random,
  ) {
    final indices = List<int>.generate(source.length, (index) => index);
    for (var index = 0; index < count; index++) {
      final selected = index + random.nextInt(indices.length - index);
      final swap = indices[index];
      indices[index] = indices[selected];
      indices[selected] = swap;
    }
    return [for (var index = 0; index < count; index++) source[indices[index]]];
  }

  double _quantile(
    List<double> sortedValues,
    double probability,
    GstsEmpiricalQuantileRule rule,
  ) {
    final rank = (probability * sortedValues.length).ceil().clamp(
      1,
      sortedValues.length,
    );
    return switch (rule) {
      GstsEmpiricalQuantileRule.nearestRank => sortedValues[rank - 1],
    };
  }

  void _validate(
    List<GstsConfidenceCalibrationEvent> events,
    GstsConfidenceCalibrationSpec spec,
  ) {
    if (events.isEmpty) {
      throw ArgumentError('At least one calibration event is required.');
    }
    if (spec.observationCounts.isEmpty ||
        spec.observationCounts.any((count) => count <= 0) ||
        spec.observationCounts.toSet().length !=
            spec.observationCounts.length) {
      throw ArgumentError(
        'Observation counts must be non-empty, positive, and unique.',
      );
    }
    if (spec.repetitionsPerEvent <= 0) {
      throw ArgumentError('Repetitions per event must be positive.');
    }
    if (spec.probabilities.isEmpty ||
        spec.probabilities.toSet().length != spec.probabilities.length) {
      throw ArgumentError(
        'One-sided probabilities must be non-empty and unique.',
      );
    }
    final attenuation = spec.attenuationModel;
    if (attenuation.id.isEmpty ||
        !attenuation.intercept.isFinite ||
        !attenuation.magnitudeCoefficient.isFinite ||
        attenuation.magnitudeCoefficient == 0 ||
        !attenuation.linearDistanceCoefficient.isFinite ||
        !attenuation.logDistanceCoefficient.isFinite) {
      throw ArgumentError(
        'The calibration attenuation model must have an id and finite, '
        'scoreable coefficients.',
      );
    }
    final weight = spec.distanceWeightModel;
    if (!weight.baseline.isFinite ||
        weight.baseline < 0 ||
        !weight.distanceFactorKm.isFinite ||
        weight.distanceFactorKm <= 0) {
      throw ArgumentError(
        'Calibration distance-weight parameters must be finite and valid.',
      );
    }
    final eventIds = <String>{};
    final maximumObservationCount = spec.observationCounts.reduce(math.max);
    for (final event in events) {
      if (event.id.isEmpty || !eventIds.add(event.id)) {
        throw ArgumentError(
          'Calibration event ids must be non-empty and unique.',
        );
      }
      if (!event.referenceMagnitude.isFinite) {
        throw ArgumentError('Reference magnitudes must be finite.');
      }
      if (event.observations.length < maximumObservationCount) {
        throw ArgumentError(
          'Event ${event.id} has ${event.observations.length} observations, '
          'fewer than the requested $maximumObservationCount.',
        );
      }
      final grid = event.grid;
      if (!grid.widthKm.isFinite ||
          !grid.heightKm.isFinite ||
          !grid.spacingKm.isFinite ||
          grid.widthKm <= 0 ||
          grid.heightKm <= 0 ||
          grid.spacingKm <= 0) {
        throw ArgumentError(
          'Calibration grid dimensions must be finite and positive.',
        );
      }
      if (grid.candidates.isEmpty ||
          grid.referenceCandidateIndex < 0 ||
          grid.referenceCandidateIndex >= grid.candidates.length) {
        throw ArgumentError(
          'Calibration grids need candidates and a valid reference index.',
        );
      }
    }
  }
}
