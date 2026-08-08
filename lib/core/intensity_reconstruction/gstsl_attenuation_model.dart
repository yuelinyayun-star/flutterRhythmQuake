import 'dart:math' as math;

/// Intensity = c0 + c1*M + c2*distance + c3*log10(distance).
class GstsAttenuationModel {
  const GstsAttenuationModel({
    required this.id,
    required this.intercept,
    required this.magnitudeCoefficient,
    this.linearDistanceCoefficient = 0,
    this.logDistanceCoefficient = 0,
  });

  final String id;
  final double intercept;
  final double magnitudeCoefficient;
  final double linearDistanceCoefficient;
  final double logDistanceCoefficient;

  bool get requiresPositiveDistance => logDistanceCoefficient != 0;

  double predictIntensity({
    required double magnitude,
    required double distanceKm,
  }) {
    _validateDistance(distanceKm);
    final logTerm = requiresPositiveDistance
        ? logDistanceCoefficient * _log10(distanceKm)
        : 0.0;
    return intercept +
        magnitudeCoefficient * magnitude +
        linearDistanceCoefficient * distanceKm +
        logTerm;
  }

  double inferMagnitude({
    required double intensity,
    required double distanceKm,
  }) {
    _validateDistance(distanceKm);
    if (!intensity.isFinite) {
      throw ArgumentError.value(intensity, 'intensity', 'Must be finite.');
    }
    if (!magnitudeCoefficient.isFinite || magnitudeCoefficient == 0) {
      throw StateError('Magnitude coefficient must be finite and non-zero.');
    }
    final logTerm = requiresPositiveDistance
        ? logDistanceCoefficient * _log10(distanceKm)
        : 0.0;
    return (intensity -
            intercept -
            linearDistanceCoefficient * distanceKm -
            logTerm) /
        magnitudeCoefficient;
  }

  void _validateDistance(double distanceKm) {
    if (!distanceKm.isFinite || distanceKm < 0) {
      throw ArgumentError.value(
        distanceKm,
        'distanceKm',
        'Must be finite and non-negative.',
      );
    }
    if (requiresPositiveDistance && distanceKm <= 0) {
      throw ArgumentError.value(
        distanceKm,
        'distanceKm',
        'Must be positive for a logarithmic attenuation model.',
      );
    }
  }

  double _log10(double value) => math.log(value) / math.ln10;
}

abstract final class GstsPaperAttenuationModels {
  /// North China 2009 equation (8-a), used for the paper's GSTSL results.
  ///
  /// This is the calibrated station-magnitude relation
  /// `M_i = (I_i + 1.73 + 0.0106 * distanceKm) / 1.31`, represented in
  /// intensity-prediction form so [GstsAttenuationModel.inferMagnitude]
  /// reproduces that equation exactly. It is distinct from the preceding
  /// regression reported as equation (6-a).
  static const northChina2009CalibratedLinear = GstsAttenuationModel(
    id: 'zhang_ma_shi_2009_north_china_8a',
    intercept: -1.73,
    magnitudeCoefficient: 1.31,
    linearDistanceCoefficient: -0.0106,
  );

  /// Equation (8-a), calibrated from 14 instrumented Sichuan-Yunnan events.
  static const southwestChina2010Linear = GstsAttenuationModel(
    id: 'ma_zhang_shi_2010_southwest_china_8a',
    intercept: -5.38,
    magnitudeCoefficient: 1.91,
    linearDistanceCoefficient: -0.0173,
  );

  /// Equation (8-b), selected by the paper for later GSTSL calculations.
  static const southwestChina2010Logarithmic = GstsAttenuationModel(
    id: 'ma_zhang_shi_2010_southwest_china_8b',
    intercept: -4.29,
    magnitudeCoefficient: 2.06,
    logDistanceCoefficient: -2.1933,
  );

  /// Equation (8-c), the combined distance model evaluated by the paper.
  static const southwestChina2010Combined = GstsAttenuationModel(
    id: 'ma_zhang_shi_2010_southwest_china_8c',
    intercept: -4.73,
    magnitudeCoefficient: 2.10,
    linearDistanceCoefficient: -0.0033,
    logDistanceCoefficient: -1.9294,
  );
}

class GstsDistanceWeightModel {
  const GstsDistanceWeightModel({
    required this.baseline,
    required this.distanceFactorKm,
  });

  /// Paper symbol `a`.
  final double baseline;

  /// Paper symbol `b`.
  final double distanceFactorKm;

  /// Weight used for the 2010 Sichuan-Yunnan scoring and event plots.
  static const southwestChina2010Scoring = GstsDistanceWeightModel(
    baseline: 0.1,
    distanceFactorKm: 1000,
  );

  /// Weight used to generate table 3 in the 2009 North China paper.
  static const northChina2009ConfidenceCalibration = GstsDistanceWeightModel(
    baseline: 0.05,
    distanceFactorKm: 480,
  );

  double weight(double distanceKm) {
    if (!distanceKm.isFinite || distanceKm < 0) {
      throw ArgumentError.value(
        distanceKm,
        'distanceKm',
        'Must be finite and non-negative.',
      );
    }
    if (!baseline.isFinite || baseline < 0) {
      throw StateError('Weight baseline must be finite and non-negative.');
    }
    if (!distanceFactorKm.isFinite || distanceFactorKm <= 0) {
      throw StateError('Distance factor must be finite and positive.');
    }
    if (distanceKm >= distanceFactorKm) return baseline;
    return baseline + math.cos(distanceKm / distanceFactorKm * math.pi / 2);
  }
}
