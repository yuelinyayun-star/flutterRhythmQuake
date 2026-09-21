import 'dart:math' as math;

import 'jp_shindo_scale.dart';

/// PGA-based estimate, not waveform-derived JMA instrumental intensity.
class PAlertIntensity {
  PAlertIntensity._();

  // Taiwan PGA relation: I = 2 log10(PGA [Gal]) + 0.70.
  // https://www.gep.ncu.edu.tw/storage/thesis/2017/2017%20Chung-Han%20Chan_TAOS.pdf
  static double? estimateFromPga(double? pgaGal) {
    if (pgaGal == null || !pgaGal.isFinite || pgaGal <= 0) return null;
    return 2 * math.log(pgaGal) / math.ln10 + 0.70;
  }

  static int detectionLevelFromPga(double? pgaGal) {
    final estimate = estimateFromPga(pgaGal);
    if (estimate == null) return -1;
    // Only the detector's bounded level domain is saturated. Raw PGA and the
    // unbounded estimate remain intact; missing samples are never the floor.
    return JpShindoScale.kanameishiLevelFromShindo(
      estimate.clamp(-3.0, 7.0).toDouble(),
    );
  }
}
