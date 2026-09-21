/// P-Alert inference levels and weights from kanameishi 8748cf7 (AGPL-3.0).
/// These internal levels are separate from the PGA continuous estimate and
/// from CWA display categories. Neither raw observations nor display change.
class PAlertSourceProfile {
  static const pgaThresholds = <double>[
    0.1,
    0.14,
    0.18,
    0.25,
    0.33,
    0.44,
    0.59,
    0.8,
    1.4,
    2.5,
    4.4,
    8,
    14,
    25,
    44,
  ];
  static const pgvThresholds = <double>[15, 30, 50, 80, 140];

  static int level(double? pga, double? pgv) {
    if (pga == null || !pga.isFinite || pga < 0) return -1;
    if (pga < 80) return pgaThresholds.where((v) => pga >= v).length;
    // Do not substitute zero for missing velocity at high acceleration.
    if (pgv == null || !pgv.isFinite || pgv < 0) return -1;
    return 15 + pgvThresholds.where((v) => pgv >= v).length;
  }

  static double pickWeight(int maxLevel) {
    if (maxLevel == 6) return 0.1;
    if (maxLevel == 7) return 0.4;
    if (maxLevel == 8) return 1.6;
    if (maxLevel < 6) return 0;
    return (2 + (maxLevel - 8) * 0.4).clamp(0, 4).toDouble();
  }
}
