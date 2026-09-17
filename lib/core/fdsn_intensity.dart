import 'dart:math';
import 'package:flutter/foundation.dart';

enum FdsnIntensityScale { mmi, csis }

class FdsnIntensity {
  static const preferenceKey = 'fdsn_intensity_scale';
  static final scale = ValueNotifier(FdsnIntensityScale.mmi);

  static FdsnIntensityScale parseScale(String? value) =>
      value == 'csis' ? FdsnIntensityScale.csis : FdsnIntensityScale.mmi;

  /// GB/T 17742-2020 amplitude relation, SI units. Existing FDSN record peaks
  /// are only scalar-sensitivity estimates, not filtered three-axis peaks.
  /// Therefore this is explicitly an estimate, not standard-compliant II.
  static double? estimateCsis({double? pgaGal, double? pgvCms}) {
    if (pgaGal == null ||
        pgvCms == null ||
        !pgaGal.isFinite ||
        !pgvCms.isFinite ||
        pgaGal <= 0 ||
        pgvCms <= 0) {
      return null;
    }
    final ia = 3.17 * log(pgaGal / 100) / ln10 + 6.59;
    final iv = 3.00 * log(pgvCms / 100) / ln10 + 9.77;
    return (ia >= 6 && iv >= 6 ? iv : (ia + iv) / 2).clamp(1.0, 12.0);
  }

  static int? displayLevel(
    FdsnIntensityScale scale, {
    double? mmi,
    double? pgaGal,
    double? pgvCms,
  }) {
    final value = scale == FdsnIntensityScale.mmi
        ? mmi
        : estimateCsis(pgaGal: pgaGal, pgvCms: pgvCms);
    if (value == null || !value.isFinite || value < 1) return null;
    return scale == FdsnIntensityScale.mmi
        ? value.round().clamp(1, 10)
        : value.round().clamp(1, 12);
  }
}
