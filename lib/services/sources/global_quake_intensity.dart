import 'dart:math' as math;

/// GlobalQuake's estimated MMI conversion.
///
/// GlobalQuake computes the event maximum PGA on its server and carries that
/// value in HypocenterData.maxPGA. The client then applies the MMI thresholds
/// below. This stays separate from the application's CSIS/JMA estimators.
abstract final class GlobalQuakeIntensity {
  static const List<double> mmiPgaThresholds = <double>[
    0.5,
    1.0,
    2.1,
    5.0,
    11.0,
    26.0,
    60.0,
    140.0,
    321.8,
    740.0,
    1702.0,
    3000.0,
  ];

  /// Returns 0 when the PGA is below MMI I or is not usable.
  static int mmiLevelFromPga(double pga) {
    if (!pga.isFinite || pga < mmiPgaThresholds.first) return 0;
    var level = 0;
    for (var i = 0; i < mmiPgaThresholds.length; i++) {
      if (pga < mmiPgaThresholds[i]) break;
      level = i + 1;
    }
    return level;
  }

  /// GlobalQuake's depth correction from EarthquakeAnalysis.
  static double depthCorrection(double depth) {
    if (!depth.isFinite || depth < 0) return double.nan;
    return math.log(depth + 160.0) / math.ln10 - math.log(160.0) / math.ln10;
  }

  /// GlobalQuake's current PGA attenuation function from GeoUtils.
  ///
  /// [distanceKm] must use the same geological-distance semantics as the
  /// GlobalQuake client. Event maximum PGA should normally come from the
  /// packet's maxPGA field instead of recomputing it without its region data.
  static double pgaFunction({
    required double magnitude,
    required double distanceKm,
    required double depth,
  }) {
    final correction = depthCorrection(depth);
    if (!magnitude.isFinite || !distanceKm.isFinite || !correction.isFinite) {
      return double.nan;
    }
    final correctedMagnitude = magnitude + 0.4 * correction;
    final correctedDistance = distanceKm / (1.0 + 0.75 * correction);
    return math.pow(10, correctedMagnitude * 0.575).toDouble() /
        (0.36 *
                math
                    .pow(correctedDistance, 1.25 + magnitude / 22.0)
                    .toDouble() +
            10);
  }
}
