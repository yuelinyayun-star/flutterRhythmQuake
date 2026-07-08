import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';

void main() {
  test('JMA2001 coefficient table shape is frozen', () {
    expect(Jma2001TravelTimeApproximation.coefficientCount, 1704);
    expect(Jma2001TravelTimeApproximation.depthBinCount, 71);
    expect(Jma2001TravelTimeApproximation.coefficientsPerDepth, 6);
    expect(Jma2001TravelTimeApproximation.branchLength, 426);
  });

  test(
    'JMA2001 travel time approximation matches extracted reference values',
    () {
      final hypocentralDistanceKm = math.sqrt(60 * 60 + 100 * 100);

      final p = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: 60,
        pWave: true,
      );
      final s = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: 60,
        pWave: false,
      );

      expect(p, closeTo(16.8374, 0.001));
      expect(s, closeTo(29.2223, 0.001));
      expect(s, greaterThan(p));
    },
  );

  test('JMA2001 radius approximation keeps P radius ahead of S radius', () {
    final p = Jma2001TravelTimeApproximation.epicentralRadiusKm(
      elapsedSeconds: 20,
      depthKm: 40,
      pWave: true,
    );
    final s = Jma2001TravelTimeApproximation.epicentralRadiusKm(
      elapsedSeconds: 20,
      depthKm: 40,
      pWave: false,
    );

    expect(p, closeTo(128.0508, 0.001));
    expect(s, closeTo(63.8989, 0.001));
    expect(p, greaterThan(s));
  });
}
