import 'dart:math' as math;

class Matsuzaki2006AttenuationCoefficients {
  const Matsuzaki2006AttenuationCoefficients({
    required this.magnitudeCoefficient,
    required this.logDistanceCoefficient,
    required this.saturationCoefficient,
    required this.saturationMagnitudeExponent,
    required this.depthCoefficient,
    required this.intercept,
  }) : assert(saturationCoefficient > 0),
       assert(saturationMagnitudeExponent > 0);

  static const published = Matsuzaki2006AttenuationCoefficients(
    magnitudeCoefficient: 1.36,
    logDistanceCoefficient: 4.03,
    saturationCoefficient: 0.00675,
    saturationMagnitudeExponent: 0.5,
    depthCoefficient: 0.0155,
    intercept: 2.05,
  );

  /// Calibrated on 2010-2016 with source-backed finite-fault distances where
  /// available, selected on the predeclared 2017 near/far objectives.
  static const finiteFaultSemanticFrozen2017 =
      Matsuzaki2006AttenuationCoefficients(
        magnitudeCoefficient: 0.8758394366604219,
        logDistanceCoefficient: 2.8107865312901934,
        saturationCoefficient: 0.00675,
        saturationMagnitudeExponent: 0.5,
        depthCoefficient: 0.006556775133699079,
        intercept: 2.6530791908969866,
      );

  final double magnitudeCoefficient;
  final double logDistanceCoefficient;
  final double saturationCoefficient;
  final double saturationMagnitudeExponent;
  final double depthCoefficient;
  final double intercept;

  Map<String, double> toJson() => {
    'magnitudeCoefficient': magnitudeCoefficient,
    'logDistanceCoefficient': logDistanceCoefficient,
    'saturationCoefficient': saturationCoefficient,
    'saturationMagnitudeExponent': saturationMagnitudeExponent,
    'depthCoefficient': depthCoefficient,
    'intercept': intercept,
  };
}

enum MatsuzakiMagnitudeInferenceStatus {
  solvedUnique,
  solvedAmbiguous,
  observedBelowModelOutputRange,
  observedAboveModelOutputRange,
}

class MatsuzakiMagnitudeInferenceResult {
  MatsuzakiMagnitudeInferenceResult({
    required this.status,
    required List<double> roots,
    required this.minimumPredictedIntensity,
    required this.maximumPredictedIntensity,
    required this.turningMagnitude,
  }) : roots = List.unmodifiable(roots);

  final MatsuzakiMagnitudeInferenceStatus status;
  final List<double> roots;
  final double minimumPredictedIntensity;
  final double maximumPredictedIntensity;
  final double? turningMagnitude;

  bool get hasSolution => roots.isNotEmpty;
  bool get isAmbiguous => roots.length > 1;

  double get uniqueMagnitude {
    if (roots.length != 1) {
      throw StateError('The inference result does not have exactly one root.');
    }
    return roots.single;
  }
}

/// Matsuzaki, Hisada, and Fukushima (2006), equation (12).
///
/// The model is kept inside experiment 1 because its published coefficients
/// still need validation against modern JMA instrumental-intensity records.
class Matsuzaki2006AttenuationModel {
  const Matsuzaki2006AttenuationModel({
    this.coefficients = Matsuzaki2006AttenuationCoefficients.published,
  });

  static const double minimumMagnitude = 5.0;
  static const double maximumMagnitude = 8.2;
  static const double minimumSourceDistanceKm = 1.0;
  static const double maximumSourceDistanceKm = 500.0;
  static const double minimumDepthKm = 0.0;
  static const double maximumObservedDepthKm = 183.0;
  static const double formulaDepthCapKm = 100.0;

  static const double magnitudeCoefficient = 1.36;
  static const double logDistanceCoefficient = 4.03;
  static const double saturationCoefficient = 0.00675;
  static const double saturationMagnitudeExponent = 0.5;
  static const double depthCoefficient = 0.0155;
  static const double intercept = 2.05;

  final Matsuzaki2006AttenuationCoefficients coefficients;

  double predictIntensity({
    required double magnitude,
    required double sourceDistanceKm,
    required double depthKm,
  }) {
    _validateMagnitude(magnitude);
    _validateGeometry(sourceDistanceKm: sourceDistanceKm, depthKm: depthKm);
    return _predictWithinCalibrationDomain(
      magnitude: magnitude,
      sourceDistanceKm: sourceDistanceKm,
      depthKm: depthKm,
    );
  }

  /// Returns every magnitude root inside the paper's calibrated Mj range.
  ///
  /// The equation is not globally monotonic in magnitude at short distances,
  /// so a station can have zero, one, or two valid roots. This method never
  /// chooses one branch implicitly.
  MatsuzakiMagnitudeInferenceResult inferMagnitudes({
    required double observedIntensity,
    required double sourceDistanceKm,
    required double depthKm,
    double intensityTolerance = 1e-10,
    double magnitudeTolerance = 1e-10,
    int maximumIterations = 100,
  }) {
    if (!observedIntensity.isFinite) {
      throw ArgumentError.value(
        observedIntensity,
        'observedIntensity',
        'Must be finite.',
      );
    }
    _validateGeometry(sourceDistanceKm: sourceDistanceKm, depthKm: depthKm);
    _validateSolverSettings(
      intensityTolerance: intensityTolerance,
      magnitudeTolerance: magnitudeTolerance,
      maximumIterations: maximumIterations,
    );

    final turningMagnitude = turningMagnitudeForSourceDistance(
      sourceDistanceKm,
    );
    final boundaries = <double>[
      minimumMagnitude,
      if (turningMagnitude != null &&
          turningMagnitude > minimumMagnitude &&
          turningMagnitude < maximumMagnitude)
        turningMagnitude,
      maximumMagnitude,
    ];
    final boundaryIntensities = [
      for (final magnitude in boundaries)
        _predictWithinCalibrationDomain(
          magnitude: magnitude,
          sourceDistanceKm: sourceDistanceKm,
          depthKm: depthKm,
        ),
    ];
    final minimumPredictedIntensity = boundaryIntensities.reduce(math.min);
    final maximumPredictedIntensity = boundaryIntensities.reduce(math.max);
    final roots = <double>[];

    for (var index = 0; index < boundaries.length; index++) {
      if ((boundaryIntensities[index] - observedIntensity).abs() <=
          intensityTolerance) {
        _addDistinctRoot(roots, boundaries[index], magnitudeTolerance);
      }
    }

    for (var index = 0; index < boundaries.length - 1; index++) {
      final lowerMagnitude = boundaries[index];
      final upperMagnitude = boundaries[index + 1];
      final lowerResidual = boundaryIntensities[index] - observedIntensity;
      final upperResidual = boundaryIntensities[index + 1] - observedIntensity;
      if (lowerResidual.abs() <= intensityTolerance ||
          upperResidual.abs() <= intensityTolerance) {
        continue;
      }
      if (lowerResidual.sign == upperResidual.sign) continue;

      final root = _bisectMagnitudeRoot(
        observedIntensity: observedIntensity,
        sourceDistanceKm: sourceDistanceKm,
        depthKm: depthKm,
        lowerMagnitude: lowerMagnitude,
        upperMagnitude: upperMagnitude,
        lowerResidual: lowerResidual,
        intensityTolerance: intensityTolerance,
        magnitudeTolerance: magnitudeTolerance,
        maximumIterations: maximumIterations,
      );
      _addDistinctRoot(roots, root, magnitudeTolerance);
    }

    if (roots.length == 1) {
      return MatsuzakiMagnitudeInferenceResult(
        status: MatsuzakiMagnitudeInferenceStatus.solvedUnique,
        roots: roots,
        minimumPredictedIntensity: minimumPredictedIntensity,
        maximumPredictedIntensity: maximumPredictedIntensity,
        turningMagnitude: _turningMagnitudeInsideDomain(turningMagnitude),
      );
    }
    if (roots.length == 2) {
      return MatsuzakiMagnitudeInferenceResult(
        status: MatsuzakiMagnitudeInferenceStatus.solvedAmbiguous,
        roots: roots,
        minimumPredictedIntensity: minimumPredictedIntensity,
        maximumPredictedIntensity: maximumPredictedIntensity,
        turningMagnitude: _turningMagnitudeInsideDomain(turningMagnitude),
      );
    }
    if (roots.length > 2) {
      throw StateError(
        'The attenuation equation produced more than two roots.',
      );
    }

    if (observedIntensity < minimumPredictedIntensity) {
      return MatsuzakiMagnitudeInferenceResult(
        status: MatsuzakiMagnitudeInferenceStatus.observedBelowModelOutputRange,
        roots: const [],
        minimumPredictedIntensity: minimumPredictedIntensity,
        maximumPredictedIntensity: maximumPredictedIntensity,
        turningMagnitude: _turningMagnitudeInsideDomain(turningMagnitude),
      );
    }
    if (observedIntensity > maximumPredictedIntensity) {
      return MatsuzakiMagnitudeInferenceResult(
        status: MatsuzakiMagnitudeInferenceStatus.observedAboveModelOutputRange,
        roots: const [],
        minimumPredictedIntensity: minimumPredictedIntensity,
        maximumPredictedIntensity: maximumPredictedIntensity,
        turningMagnitude: _turningMagnitudeInsideDomain(turningMagnitude),
      );
    }
    throw StateError(
      'Root search failed inside the predicted intensity range.',
    );
  }

  /// The one stationary point of intensity as a function of magnitude.
  ///
  /// Returns null when the equation coefficients do not permit a stationary
  /// point. The returned value is not clipped to the calibrated Mj range.
  double? turningMagnitudeForSourceDistance(double sourceDistanceKm) {
    if (!sourceDistanceKm.isFinite || sourceDistanceKm <= 0) {
      throw ArgumentError.value(
        sourceDistanceKm,
        'sourceDistanceKm',
        'Must be finite and positive.',
      );
    }
    final maximumLogSlope =
        coefficients.logDistanceCoefficient *
        coefficients.saturationMagnitudeExponent;
    if (maximumLogSlope <= coefficients.magnitudeCoefficient) return null;

    final saturationFraction =
        coefficients.magnitudeCoefficient / maximumLogSlope;
    final saturationTerm =
        saturationFraction * sourceDistanceKm / (1 - saturationFraction);
    return _log10(saturationTerm / coefficients.saturationCoefficient) /
        coefficients.saturationMagnitudeExponent;
  }

  double intensityDerivativeByMagnitude({
    required double magnitude,
    required double sourceDistanceKm,
  }) {
    _validateMagnitude(magnitude);
    if (!sourceDistanceKm.isFinite || sourceDistanceKm <= 0) {
      throw ArgumentError.value(
        sourceDistanceKm,
        'sourceDistanceKm',
        'Must be finite and positive.',
      );
    }
    final saturationTerm =
        coefficients.saturationCoefficient *
        math.pow(10, coefficients.saturationMagnitudeExponent * magnitude);
    return coefficients.magnitudeCoefficient -
        coefficients.logDistanceCoefficient *
            coefficients.saturationMagnitudeExponent *
            saturationTerm /
            (sourceDistanceKm + saturationTerm);
  }

  double _predictWithinCalibrationDomain({
    required double magnitude,
    required double sourceDistanceKm,
    required double depthKm,
  }) {
    final saturationTerm =
        coefficients.saturationCoefficient *
        math.pow(10, coefficients.saturationMagnitudeExponent * magnitude);
    final effectiveDepthKm = math.min(depthKm, formulaDepthCapKm);
    return coefficients.magnitudeCoefficient * magnitude -
        coefficients.logDistanceCoefficient *
            _log10(sourceDistanceKm + saturationTerm) +
        coefficients.depthCoefficient * effectiveDepthKm +
        coefficients.intercept;
  }

  double _bisectMagnitudeRoot({
    required double observedIntensity,
    required double sourceDistanceKm,
    required double depthKm,
    required double lowerMagnitude,
    required double upperMagnitude,
    required double lowerResidual,
    required double intensityTolerance,
    required double magnitudeTolerance,
    required int maximumIterations,
  }) {
    var lower = lowerMagnitude;
    var upper = upperMagnitude;
    var lowerValue = lowerResidual;
    for (var iteration = 0; iteration < maximumIterations; iteration++) {
      final middle = (lower + upper) / 2;
      final middleValue =
          _predictWithinCalibrationDomain(
            magnitude: middle,
            sourceDistanceKm: sourceDistanceKm,
            depthKm: depthKm,
          ) -
          observedIntensity;
      if (middleValue.abs() <= intensityTolerance ||
          (upper - lower) / 2 <= magnitudeTolerance) {
        return middle;
      }
      if (middleValue.sign == lowerValue.sign) {
        lower = middle;
        lowerValue = middleValue;
      } else {
        upper = middle;
      }
    }
    throw StateError('Magnitude root search did not converge.');
  }

  void _addDistinctRoot(
    List<double> roots,
    double root,
    double magnitudeTolerance,
  ) {
    if (roots.any(
      (existing) => (existing - root).abs() <= magnitudeTolerance,
    )) {
      return;
    }
    roots.add(root);
    roots.sort();
  }

  double? _turningMagnitudeInsideDomain(double? turningMagnitude) {
    if (turningMagnitude == null ||
        turningMagnitude <= minimumMagnitude ||
        turningMagnitude >= maximumMagnitude) {
      return null;
    }
    return turningMagnitude;
  }

  void _validateMagnitude(double magnitude) {
    if (!magnitude.isFinite) {
      throw ArgumentError.value(magnitude, 'magnitude', 'Must be finite.');
    }
    if (magnitude < minimumMagnitude || magnitude > maximumMagnitude) {
      throw RangeError.value(
        magnitude,
        'magnitude',
        'Must be within the published calibration range '
            '$minimumMagnitude..$maximumMagnitude.',
      );
    }
  }

  void _validateGeometry({
    required double sourceDistanceKm,
    required double depthKm,
  }) {
    if (!sourceDistanceKm.isFinite) {
      throw ArgumentError.value(
        sourceDistanceKm,
        'sourceDistanceKm',
        'Must be finite.',
      );
    }
    if (sourceDistanceKm < minimumSourceDistanceKm ||
        sourceDistanceKm > maximumSourceDistanceKm) {
      throw RangeError.value(
        sourceDistanceKm,
        'sourceDistanceKm',
        'Must be within the published calibration range '
            '$minimumSourceDistanceKm..$maximumSourceDistanceKm km.',
      );
    }
    if (!depthKm.isFinite) {
      throw ArgumentError.value(depthKm, 'depthKm', 'Must be finite.');
    }
    if (depthKm < minimumDepthKm || depthKm > maximumObservedDepthKm) {
      throw RangeError.value(
        depthKm,
        'depthKm',
        'Must be within the published data range '
            '$minimumDepthKm..$maximumObservedDepthKm km.',
      );
    }
  }

  void _validateSolverSettings({
    required double intensityTolerance,
    required double magnitudeTolerance,
    required int maximumIterations,
  }) {
    if (!intensityTolerance.isFinite || intensityTolerance <= 0) {
      throw ArgumentError.value(
        intensityTolerance,
        'intensityTolerance',
        'Must be finite and positive.',
      );
    }
    if (!magnitudeTolerance.isFinite || magnitudeTolerance <= 0) {
      throw ArgumentError.value(
        magnitudeTolerance,
        'magnitudeTolerance',
        'Must be finite and positive.',
      );
    }
    if (maximumIterations <= 0) {
      throw ArgumentError.value(
        maximumIterations,
        'maximumIterations',
        'Must be positive.',
      );
    }
  }

  double _log10(num value) => math.log(value) / math.ln10;
}
