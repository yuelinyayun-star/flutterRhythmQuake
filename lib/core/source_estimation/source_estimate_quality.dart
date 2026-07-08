import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'source_estimation_models.dart';
import 'source_station_phase_classifier.dart';

class SourceEstimateQuality {
  final String grade;
  final double confidence;
  final double? rmsResidualSeconds;
  final double? azimuthalGapDegrees;
  final double? horizontalUncertaintyP50Km;
  final double? horizontalUncertaintyP90Km;
  final String? stationGeometry;
  final bool searchBoundaryHit;
  final int associatedStationCount;
  final int residualStationCount;

  const SourceEstimateQuality({
    required this.grade,
    required this.confidence,
    required this.rmsResidualSeconds,
    required this.azimuthalGapDegrees,
    required this.horizontalUncertaintyP50Km,
    required this.horizontalUncertaintyP90Km,
    required this.stationGeometry,
    required this.searchBoundaryHit,
    required this.associatedStationCount,
    required this.residualStationCount,
  });
}

class SourceEstimateQualityCalculator {
  final SourceStationPhaseClassifier phaseClassifier;

  const SourceEstimateQualityCalculator({
    this.phaseClassifier = const SourceStationPhaseClassifier(),
  });

  SourceEstimateQuality? calculate(SeismicActiveEvent event) {
    final estimate = event.estimate;
    if (estimate == null) return null;

    final phases = phaseClassifier.classify(event);
    final residuals = phases.stations
        .where((item) => item.phase != EstimatedStationPhase.other)
        .map((item) => item.residualSeconds)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    final rmsResidual = residuals.isEmpty
        ? null
        : math.sqrt(
            residuals.fold<double>(0, (sum, value) => sum + value * value) /
                residuals.length,
          );
    final gap = _azimuthalGapDegrees(
      estimate.latitude,
      estimate.longitude,
      phases.stations.map((item) => item.coordinate),
    );
    final associatedCount = phases.stations.length;
    final confidence = estimate.confidence.clamp(0.0, 1.0);
    final horizontalUncertaintyP50Km = _diagnosticDouble(
      estimate,
      'horizontal_uncertainty_p50_km',
    );
    final horizontalUncertaintyP90Km = _diagnosticDouble(
      estimate,
      'horizontal_uncertainty_p90_km',
    );
    final stationGeometry = estimate.diagnostics['station_geometry']
        ?.toString();
    final searchBoundaryHit =
        estimate.diagnostics['search_boundary_hit'] == true;

    return SourceEstimateQuality(
      grade: _grade(
        confidence: confidence,
        stationCount: associatedCount,
        rmsResidualSeconds: rmsResidual,
        azimuthalGapDegrees: gap,
        horizontalUncertaintyP90Km: horizontalUncertaintyP90Km,
        stationGeometry: stationGeometry,
        searchBoundaryHit: searchBoundaryHit,
      ),
      confidence: confidence,
      rmsResidualSeconds: rmsResidual,
      azimuthalGapDegrees: gap,
      horizontalUncertaintyP50Km: horizontalUncertaintyP50Km,
      horizontalUncertaintyP90Km: horizontalUncertaintyP90Km,
      stationGeometry: stationGeometry,
      searchBoundaryHit: searchBoundaryHit,
      associatedStationCount: associatedCount,
      residualStationCount: residuals.length,
    );
  }

  String _grade({
    required double confidence,
    required int stationCount,
    required double? rmsResidualSeconds,
    required double? azimuthalGapDegrees,
    required double? horizontalUncertaintyP90Km,
    required String? stationGeometry,
    required bool searchBoundaryHit,
  }) {
    final worstOrdinal = [
      _higherIsBetterOrdinal(confidence, const [0.85, 0.75, 0.60, 0.40]),
      _higherIsBetterOrdinal(stationCount.toDouble(), const [16, 12, 8, 4]),
      _lowerIsBetterOrdinal(rmsResidualSeconds, const [1.0, 1.5, 2.5, 4.0]),
      _lowerIsBetterOrdinal(azimuthalGapDegrees, const [90, 135, 180, 270]),
      _optionalLowerIsBetterOrdinal(horizontalUncertaintyP90Km, const [
        25,
        50,
        100,
        180,
      ]),
      _geometryOrdinal(
        stationGeometry: stationGeometry,
        searchBoundaryHit: searchBoundaryHit,
      ),
    ].reduce(math.max);
    return const ['S', 'A', 'B', 'C', 'D'][worstOrdinal];
  }

  int _higherIsBetterOrdinal(double value, List<double> thresholds) {
    for (var index = 0; index < thresholds.length; index++) {
      if (value >= thresholds[index]) return index;
    }
    return 4;
  }

  int _lowerIsBetterOrdinal(double? value, List<double> thresholds) {
    if (value == null || !value.isFinite) return 4;
    for (var index = 0; index < thresholds.length; index++) {
      if (value <= thresholds[index]) return index;
    }
    return 4;
  }

  int _optionalLowerIsBetterOrdinal(double? value, List<double> thresholds) {
    if (value == null || !value.isFinite) return 0;
    return _lowerIsBetterOrdinal(value, thresholds);
  }

  int _geometryOrdinal({
    required String? stationGeometry,
    required bool searchBoundaryHit,
  }) {
    if (stationGeometry == 'one_sided' && searchBoundaryHit) return 4;
    if (searchBoundaryHit) return 3;
    if (stationGeometry == 'one_sided') return 2;
    return 0;
  }

  double? _diagnosticDouble(SourceEstimate estimate, String key) {
    final value = estimate.diagnostics[key];
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  double? _azimuthalGapDegrees(
    double latitude,
    double longitude,
    Iterable<LatLng> coordinates,
  ) {
    final bearings = <double>[];
    for (final coordinate in coordinates) {
      final bearing = _bearingDegrees(
        latitude,
        longitude,
        coordinate.latitude,
        coordinate.longitude,
      );
      if (bearing != null) bearings.add(bearing);
    }
    if (bearings.isEmpty) return null;
    if (bearings.length == 1) return 360;
    bearings.sort();
    var largestGap = 0.0;
    for (var index = 1; index < bearings.length; index++) {
      largestGap = math.max(largestGap, bearings[index] - bearings[index - 1]);
    }
    return math.max(largestGap, 360 - bearings.last + bearings.first);
  }

  double? _bearingDegrees(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    if (fromLatitude == toLatitude && fromLongitude == toLongitude) {
      return null;
    }
    final fromLat = fromLatitude * math.pi / 180;
    final toLat = toLatitude * math.pi / 180;
    final deltaLongitude = (toLongitude - fromLongitude) * math.pi / 180;
    final y = math.sin(deltaLongitude) * math.cos(toLat);
    final x =
        math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLongitude);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
