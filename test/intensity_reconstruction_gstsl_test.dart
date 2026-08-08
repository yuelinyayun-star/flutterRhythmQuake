import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/intensity_reconstruction.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('paper attenuation models', () {
    test('equation 8-b round-trips intensity and magnitude', () {
      const model = GstsPaperAttenuationModels.southwestChina2010Logarithmic;
      final intensity = model.predictIntensity(magnitude: 7, distanceKm: 100);

      expect(intensity, closeTo(5.7434, 1e-12));
      expect(
        model.inferMagnitude(intensity: intensity, distanceKm: 100),
        closeTo(7, 1e-12),
      );
    });

    test('all three Sichuan-Yunnan equations retain paper coefficients', () {
      const linear = GstsPaperAttenuationModels.southwestChina2010Linear;
      const logarithmic =
          GstsPaperAttenuationModels.southwestChina2010Logarithmic;
      const combined = GstsPaperAttenuationModels.southwestChina2010Combined;

      expect(linear.intercept, -5.38);
      expect(linear.magnitudeCoefficient, 1.91);
      expect(linear.linearDistanceCoefficient, -0.0173);
      expect(logarithmic.intercept, -4.29);
      expect(logarithmic.magnitudeCoefficient, 2.06);
      expect(logarithmic.logDistanceCoefficient, -2.1933);
      expect(combined.intercept, -4.73);
      expect(combined.magnitudeCoefficient, 2.10);
      expect(combined.linearDistanceCoefficient, -0.0033);
      expect(combined.logDistanceCoefficient, -1.9294);
    });

    test('North China calibration retains paper equation 8-a', () {
      const model = GstsPaperAttenuationModels.northChina2009CalibratedLinear;

      expect(model.intercept, -1.73);
      expect(model.magnitudeCoefficient, 1.31);
      expect(model.linearDistanceCoefficient, -0.0106);
      expect(
        model.inferMagnitude(intensity: 7, distanceKm: 100),
        closeTo((7 + 1.73 + 0.0106 * 100) / 1.31, 1e-12),
      );
    });
  });

  group('paper distance weighting', () {
    test('separates 2010 scoring from 2009 confidence calibration', () {
      const scoring = GstsDistanceWeightModel.southwestChina2010Scoring;
      const calibration =
          GstsDistanceWeightModel.northChina2009ConfidenceCalibration;

      expect(scoring.weight(0), closeTo(1.1, 1e-12));
      expect(scoring.weight(500), closeTo(0.1 + math.cos(math.pi / 4), 1e-12));
      expect(scoring.weight(1000), 0.1);
      expect(calibration.weight(0), closeTo(1.05, 1e-12));
      expect(
        calibration.weight(240),
        closeTo(0.05 + math.cos(math.pi / 4), 1e-12),
      );
      expect(calibration.weight(480), 0.05);
    });
  });

  group('GSTSL reconstruction', () {
    test('finds the trial location where inferred magnitudes agree', () {
      const source = GstsCandidateLocation(latitude: 30, longitude: 102);
      const model = GstsPaperAttenuationModels.southwestChina2010Logarithmic;
      final observations = _syntheticObservations(
        source: source,
        magnitude: 7,
        model: model,
      );
      final result = const GstsReconstructor().reconstruct(
        observations: observations,
        candidates: const [
          source,
          GstsCandidateLocation(latitude: 30.5, longitude: 102.5),
        ],
      );

      expect(result.observationCount, observations.length);
      expect(result.bestCandidate.candidateIndex, 0);
      expect(result.bestCandidate.intensityMagnitude, closeTo(7, 1e-12));
      expect(result.bestCandidate.rawRms, closeTo(0, 1e-12));
      expect(result.bestCandidate.normalizedRms, 0);
      expect(result.candidates[1].rawRms, greaterThan(0));
      expect(result.candidates[1].normalizedRms, greaterThan(0));
    });

    test('uses unweighted M_I mean and squared distance weights in RMS', () {
      const candidate = GstsCandidateLocation(latitude: 30, longitude: 102);
      const model = GstsPaperAttenuationModels.southwestChina2010Logarithmic;
      const coordinates = [
        LatLng(30.1, 102),
        LatLng(30.2, 102),
        LatLng(30.3, 102),
      ];
      const magnitudes = [6.0, 7.0, 8.0];
      final observations = <GstsIntensityObservation>[];
      final weights = <double>[];
      for (var index = 0; index < coordinates.length; index++) {
        final distance = QuakeCalculator.haversineDistance(
          candidate.latitude,
          candidate.longitude,
          coordinates[index].latitude,
          coordinates[index].longitude,
        );
        observations.add(
          GstsIntensityObservation(
            id: 'S$index',
            coordinate: coordinates[index],
            intensity: model.predictIntensity(
              magnitude: magnitudes[index],
              distanceKm: distance,
            ),
          ),
        );
        weights.add(
          GstsDistanceWeightModel.southwestChina2010Scoring.weight(distance),
        );
      }
      final expectedRms = math.sqrt(
        (weights[0] * weights[0] + weights[2] * weights[2]) /
            weights.map((weight) => weight * weight).reduce((a, b) => a + b),
      );

      final score = const GstsReconstructor()
          .reconstruct(
            observations: observations,
            candidates: const [candidate],
          )
          .bestCandidate;

      expect(score.intensityMagnitude, closeTo(7, 1e-12));
      expect(score.rawRms, closeTo(expectedRms, 1e-12));
    });

    test('does not invent a distance floor for logarithmic candidates', () {
      const exactStation = LatLng(30, 102);
      const model = GstsPaperAttenuationModels.southwestChina2010Logarithmic;
      final result = const GstsReconstructor().reconstruct(
        observations: [
          GstsIntensityObservation(
            id: 'EXACT',
            coordinate: exactStation,
            intensity: model.predictIntensity(magnitude: 7, distanceKm: 10),
          ),
        ],
        candidates: const [
          GstsCandidateLocation(latitude: 30, longitude: 102),
          GstsCandidateLocation(latitude: 30.1, longitude: 102),
        ],
      );

      expect(result.candidates.first.isValid, isFalse);
      expect(
        result.candidates.first.invalidReason,
        GstsCandidateInvalidReason.nonPositiveDistanceForLogarithm,
      );
      expect(result.candidates.last.isValid, isTrue);
    });

    test('linear paper model permits zero epicentral distance', () {
      const observation = GstsIntensityObservation(
        id: 'EXACT',
        coordinate: LatLng(30, 102),
        intensity: 8,
      );
      const reconstructor = GstsReconstructor(
        attenuationModel: GstsPaperAttenuationModels.southwestChina2010Linear,
      );
      final result = reconstructor.reconstruct(
        observations: const [observation],
        candidates: const [GstsCandidateLocation(latitude: 30, longitude: 102)],
      );

      expect(result.bestCandidate.isValid, isTrue);
      expect(result.bestCandidate.normalizedRms, 0);
    });
  });

  group('paper confidence table', () {
    test('uses exact table rows and does not interpolate missing counts', () {
      final row5 =
          GstsBorrowedNorthChina2009ConfidenceTable.rowForExactObservationCount(
            5,
          )!;

      expect(row5.epicenterThreshold(GstsOneSidedProbability.p95), 0.311);
      expect(row5.epicenterThreshold(GstsOneSidedProbability.p50), 0.075);
      expect(
        row5.magnitudeOneSidedLimits(GstsOneSidedProbability.p95).lowerOffset,
        -0.65,
      );
      expect(
        row5.magnitudeOneSidedLimits(GstsOneSidedProbability.p95).upperOffset,
        0.58,
      );
      expect(
        row5.magnitudeOneSidedLimits(GstsOneSidedProbability.p50).lowerOffset,
        0.14,
      );
      expect(
        row5.magnitudeOneSidedLimits(GstsOneSidedProbability.p50).upperOffset,
        0.14,
      );
      expect(
        GstsBorrowedNorthChina2009ConfidenceTable.rowForExactObservationCount(
          6,
        ),
        isNull,
      );
    });

    test('converts offsets into two one-sided magnitude limits', () {
      final limits =
          GstsBorrowedNorthChina2009ConfidenceTable.rowForExactObservationCount(
                10,
              )!
              .magnitudeOneSidedLimits(GstsOneSidedProbability.p95)
              .magnitudeOneSidedLimits(7);

      expect(limits.lowerLimit, closeTo(6.37, 1e-12));
      expect(limits.upperLimit, closeTo(7.54, 1e-12));
    });

    test('50% one-sided limits meet at the empirical median', () {
      final limits =
          GstsBorrowedNorthChina2009ConfidenceTable.rowForExactObservationCount(
                5,
              )!
              .magnitudeOneSidedLimits(GstsOneSidedProbability.p50)
              .magnitudeOneSidedLimits(7);

      expect(limits.lowerLimit, closeTo(7.14, 1e-12));
      expect(limits.upperLimit, closeTo(7.14, 1e-12));
    });
  });

  group('confidence calibration', () {
    test('is deterministic and retains raw paper quantities', () {
      final event = _calibrationEvent();
      final spec = GstsConfidenceCalibrationSpec(
        attenuationModel:
            GstsPaperAttenuationModels.northChina2009CalibratedLinear,
        distanceWeightModel:
            GstsDistanceWeightModel.northChina2009ConfidenceCalibration,
        observationCounts: const [2],
        repetitionsPerEvent: 20,
        randomSeed: 20260718,
        probabilities: const [
          GstsOneSidedProbability.p95,
          GstsOneSidedProbability.p50,
        ],
        quantileRule: GstsEmpiricalQuantileRule.nearestRank,
      );
      const calibrator = GstsConfidenceCalibrator();

      final first = calibrator.calibrate(events: [event], spec: spec);
      final second = calibrator.calibrate(events: [event], spec: spec);
      final firstRow = first.rowForObservationCount(2)!;
      final secondRow = second.rowForObservationCount(2)!;

      expect(firstRow.samples, hasLength(20));
      expect(
        first.spec.attenuationModel.id,
        'zhang_ma_shi_2009_north_china_8a',
      );
      expect(first.spec.distanceWeightModel.baseline, 0.05);
      expect(first.spec.distanceWeightModel.distanceFactorKm, 480);
      expect(
        firstRow.samples
            .map((sample) => sample.normalizedRmsAtReference)
            .toList(),
        secondRow.samples
            .map((sample) => sample.normalizedRmsAtReference)
            .toList(),
      );
      expect(
        firstRow.samples
            .map((sample) => sample.magnitudeOffsetAtReference)
            .toList(),
        secondRow.samples
            .map((sample) => sample.magnitudeOffsetAtReference)
            .toList(),
      );
      expect(
        firstRow.epicenterThresholds[GstsOneSidedProbability.p95],
        isNonNegative,
      );
      final medianLimits =
          firstRow.magnitudeOneSidedLimits[GstsOneSidedProbability.p50]!;
      expect(medianLimits.lowerOffset, medianLimits.upperOffset);
    });

    test('rejects requested subsets larger than an event data set', () {
      final event = _calibrationEvent();
      final spec = GstsConfidenceCalibrationSpec(
        attenuationModel:
            GstsPaperAttenuationModels.northChina2009CalibratedLinear,
        distanceWeightModel:
            GstsDistanceWeightModel.northChina2009ConfidenceCalibration,
        observationCounts: const [5],
        repetitionsPerEvent: 1,
        randomSeed: 1,
        probabilities: const [GstsOneSidedProbability.p95],
        quantileRule: GstsEmpiricalQuantileRule.nearestRank,
      );
      const calibrator = GstsConfidenceCalibrator();

      expect(
        () => calibrator.calibrate(events: [event], spec: spec),
        throwsArgumentError,
      );
    });
  });

  test('regular grid requires explicit bounds and steps', () {
    const grid = GstsRegularGrid(
      minimumLatitude: 30,
      maximumLatitude: 30.2,
      latitudeStep: 0.1,
      minimumLongitude: 102,
      maximumLongitude: 102.2,
      longitudeStep: 0.1,
    );

    final candidates = grid.generate();

    expect(candidates, hasLength(9));
    expect(candidates.first.latitude, 30);
    expect(candidates.first.longitude, 102);
    expect(candidates.last.latitude, closeTo(30.2, 1e-12));
    expect(candidates.last.longitude, closeTo(102.2, 1e-12));
  });
}

GstsConfidenceCalibrationEvent _calibrationEvent() {
  const source = GstsCandidateLocation(latitude: 30, longitude: 102);
  const model = GstsPaperAttenuationModels.southwestChina2010Logarithmic;
  const coordinates = [
    LatLng(29.8, 101.8),
    LatLng(29.8, 102.2),
    LatLng(30.2, 101.8),
    LatLng(30.2, 102.2),
  ];
  const inferredMagnitudes = [6.8, 7.0, 7.2, 7.4];
  final observations = <GstsIntensityObservation>[];
  for (var index = 0; index < coordinates.length; index++) {
    final coordinate = coordinates[index];
    observations.add(
      GstsIntensityObservation(
        id: 'C$index',
        coordinate: coordinate,
        intensity: model.predictIntensity(
          magnitude: inferredMagnitudes[index],
          distanceKm: QuakeCalculator.haversineDistance(
            source.latitude,
            source.longitude,
            coordinate.latitude,
            coordinate.longitude,
          ),
        ),
      ),
    );
  }
  return GstsConfidenceCalibrationEvent(
    id: 'synthetic',
    observations: observations,
    grid: GstsCalibrationGrid(
      widthKm: 400,
      heightKm: 400,
      spacingKm: 5,
      candidates: const [
        source,
        GstsCandidateLocation(latitude: 30.3, longitude: 102.3),
      ],
      referenceCandidateIndex: 0,
    ),
    referenceMagnitude: 7,
  );
}

List<GstsIntensityObservation> _syntheticObservations({
  required GstsCandidateLocation source,
  required double magnitude,
  required GstsAttenuationModel model,
}) {
  const coordinates = [
    LatLng(29.8, 101.8),
    LatLng(29.8, 102.2),
    LatLng(30.2, 101.8),
    LatLng(30.2, 102.2),
    LatLng(30.0, 102.35),
  ];
  return [
    for (var index = 0; index < coordinates.length; index++)
      GstsIntensityObservation(
        id: 'S$index',
        coordinate: coordinates[index],
        intensity: model.predictIntensity(
          magnitude: magnitude,
          distanceKm: QuakeCalculator.haversineDistance(
            source.latitude,
            source.longitude,
            coordinates[index].latitude,
            coordinates[index].longitude,
          ),
        ),
      ),
  ];
}
