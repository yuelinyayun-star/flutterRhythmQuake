import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/palert_intensity.dart';

void main() {
  test('PGA estimate preserves fractional and negative values', () {
    for (final entry in <double, double>{
      0.01: -3.3,
      0.1: -1.3,
      1: 0.7,
      10: 2.7,
      100: 4.7,
      1000: 6.7,
      10000: 8.7,
    }.entries) {
      expect(
        PAlertIntensity.estimateFromPga(entry.key),
        closeTo(entry.value, 1e-12),
      );
    }
  });

  test('invalid samples are unknown, never a quiet observation', () {
    for (final pga in <double?>[
      null,
      0,
      -0.1,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(PAlertIntensity.estimateFromPga(pga), isNull);
      expect(PAlertIntensity.detectionLevelFromPga(pga), -1);
    }
  });

  test('only detector levels saturate at the supported range', () {
    expect(PAlertIntensity.detectionLevelFromPga(0.001), 0);
    expect(PAlertIntensity.estimateFromPga(0.001), closeTo(-5.3, 1e-12));
    expect(PAlertIntensity.detectionLevelFromPga(0.02), 1);
    expect(PAlertIntensity.detectionLevelFromPga(0.1), 4);
    expect(PAlertIntensity.detectionLevelFromPga(0.5), 7);
    expect(PAlertIntensity.detectionLevelFromPga(1), 8);
    expect(PAlertIntensity.detectionLevelFromPga(1000), 20);
    expect(PAlertIntensity.detectionLevelFromPga(10000), 20);
    expect(PAlertIntensity.estimateFromPga(10000), closeTo(8.7, 1e-12));
  });
}
