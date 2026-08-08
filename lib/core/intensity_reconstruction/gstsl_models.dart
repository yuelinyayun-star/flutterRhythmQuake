import 'package:latlong2/latlong.dart';

/// One macroseismic intensity observation used by the GSTSL paper method.
class GstsIntensityObservation {
  const GstsIntensityObservation({
    required this.id,
    required this.coordinate,
    required this.intensity,
  });

  final String id;
  final LatLng coordinate;
  final double intensity;
}

/// A trial epicenter. The paper does not search depth or origin time.
class GstsCandidateLocation {
  const GstsCandidateLocation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  LatLng get coordinate => LatLng(latitude, longitude);
}

enum GstsCandidateInvalidReason {
  nonFiniteInput,
  nonPositiveDistanceForLogarithm,
  nonFiniteInferredMagnitude,
  zeroWeightSum,
}

class GstsObservationMagnitude {
  const GstsObservationMagnitude({
    required this.observationId,
    required this.distanceKm,
    required this.distanceWeight,
    required this.inferredMagnitude,
  });

  final String observationId;
  final double distanceKm;
  final double distanceWeight;
  final double inferredMagnitude;
}

class GstsCandidateScore {
  const GstsCandidateScore._({
    required this.candidateIndex,
    required this.location,
    required this.observations,
    required this.intensityMagnitude,
    required this.rawRms,
    required this.normalizedRms,
    required this.invalidReason,
  });

  factory GstsCandidateScore.valid({
    required int candidateIndex,
    required GstsCandidateLocation location,
    required List<GstsObservationMagnitude> observations,
    required double intensityMagnitude,
    required double rawRms,
    double? normalizedRms,
  }) {
    return GstsCandidateScore._(
      candidateIndex: candidateIndex,
      location: location,
      observations: List.unmodifiable(observations),
      intensityMagnitude: intensityMagnitude,
      rawRms: rawRms,
      normalizedRms: normalizedRms,
      invalidReason: null,
    );
  }

  factory GstsCandidateScore.invalid({
    required int candidateIndex,
    required GstsCandidateLocation location,
    required GstsCandidateInvalidReason reason,
  }) {
    return GstsCandidateScore._(
      candidateIndex: candidateIndex,
      location: location,
      observations: const [],
      intensityMagnitude: null,
      rawRms: null,
      normalizedRms: null,
      invalidReason: reason,
    );
  }

  final int candidateIndex;
  final GstsCandidateLocation location;
  final List<GstsObservationMagnitude> observations;
  final double? intensityMagnitude;
  final double? rawRms;
  final double? normalizedRms;
  final GstsCandidateInvalidReason? invalidReason;

  bool get isValid => invalidReason == null;

  GstsCandidateScore withNormalizedRms(double value) {
    if (!isValid) return this;
    return GstsCandidateScore.valid(
      candidateIndex: candidateIndex,
      location: location,
      observations: observations,
      intensityMagnitude: intensityMagnitude!,
      rawRms: rawRms!,
      normalizedRms: value,
    );
  }
}

class GstsReconstructionResult {
  const GstsReconstructionResult({
    required this.observationCount,
    required this.candidates,
    required this.minimumRawRms,
  });

  final int observationCount;
  final List<GstsCandidateScore> candidates;
  final double minimumRawRms;

  Iterable<GstsCandidateScore> get validCandidates =>
      candidates.where((candidate) => candidate.isValid);

  Iterable<GstsCandidateScore> get invalidCandidates =>
      candidates.where((candidate) => !candidate.isValid);

  GstsCandidateScore get bestCandidate => validCandidates.reduce(
    (best, candidate) => candidate.rawRms! < best.rawRms! ? candidate : best,
  );

  Iterable<GstsCandidateScore> get minimumCandidates =>
      validCandidates.where((candidate) => candidate.normalizedRms == 0);

  Iterable<GstsCandidateScore> candidatesWithinNormalizedRms(
    double maximumNormalizedRms,
  ) {
    if (!maximumNormalizedRms.isFinite || maximumNormalizedRms < 0) {
      throw ArgumentError.value(
        maximumNormalizedRms,
        'maximumNormalizedRms',
        'Must be finite and non-negative.',
      );
    }
    return validCandidates.where(
      (candidate) => candidate.normalizedRms! <= maximumNormalizedRms,
    );
  }
}

/// Explicit regular-grid helper. The paper does not prescribe these bounds or
/// steps, so every value is required from the caller.
class GstsRegularGrid {
  const GstsRegularGrid({
    required this.minimumLatitude,
    required this.maximumLatitude,
    required this.latitudeStep,
    required this.minimumLongitude,
    required this.maximumLongitude,
    required this.longitudeStep,
  });

  final double minimumLatitude;
  final double maximumLatitude;
  final double latitudeStep;
  final double minimumLongitude;
  final double maximumLongitude;
  final double longitudeStep;

  List<GstsCandidateLocation> generate() {
    _validate();
    final latitudes = _axisValues(
      minimum: minimumLatitude,
      maximum: maximumLatitude,
      step: latitudeStep,
    );
    final longitudes = _axisValues(
      minimum: minimumLongitude,
      maximum: maximumLongitude,
      step: longitudeStep,
    );
    return [
      for (final latitude in latitudes)
        for (final longitude in longitudes)
          GstsCandidateLocation(latitude: latitude, longitude: longitude),
    ];
  }

  void _validate() {
    final values = [
      minimumLatitude,
      maximumLatitude,
      latitudeStep,
      minimumLongitude,
      maximumLongitude,
      longitudeStep,
    ];
    if (values.any((value) => !value.isFinite)) {
      throw ArgumentError('Grid bounds and steps must be finite.');
    }
    if (minimumLatitude < -90 || maximumLatitude > 90) {
      throw ArgumentError('Latitude bounds must stay within -90..90.');
    }
    if (minimumLatitude > maximumLatitude ||
        minimumLongitude > maximumLongitude) {
      throw ArgumentError('Grid minimums must not exceed maximums.');
    }
    if (latitudeStep <= 0 || longitudeStep <= 0) {
      throw ArgumentError('Grid steps must be positive.');
    }
  }

  List<double> _axisValues({
    required double minimum,
    required double maximum,
    required double step,
  }) {
    final rawStepCount = (maximum - minimum) / step;
    final count = (rawStepCount + rawStepCount.abs() * 1e-12).floor();
    final values = <double>[
      for (var index = 0; index <= count; index++) minimum + index * step,
    ];
    final remaining = maximum - values.last;
    if (remaining > 0 && remaining <= step * 1e-10) {
      values[values.length - 1] = maximum;
    }
    return values;
  }
}
