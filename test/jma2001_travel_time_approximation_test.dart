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

  test('JMA2001 forward polynomial uses hypocentral distance', () {
    // Fixed values from KA TravelTimes.js through Utils.calcReachTime. KA's
    // table is indexed by epicentral distance, while the Scratch polynomial
    // approximating the same table takes sqrt(epicentral^2 + depth^2).
    const references =
        <
          ({
            double depthKm,
            double epicentralDistanceKm,
            double pSeconds,
            double sSeconds,
          })
        >[
          (
            depthKm: 40,
            epicentralDistanceKm: 0,
            pSeconds: 6.256,
            sSeconds: 10.735,
          ),
          (
            depthKm: 40,
            epicentralDistanceKm: 20,
            pSeconds: 6.981,
            sSeconds: 11.982,
          ),
          (
            depthKm: 150,
            epicentralDistanceKm: 20,
            pSeconds: 20.327,
            sSeconds: 35.797,
          ),
          (
            depthKm: 150,
            epicentralDistanceKm: 100,
            pSeconds: 24.075,
            sSeconds: 42.426,
          ),
        ];

    for (final reference in references) {
      final hypocentralDistanceKm = math.sqrt(
        reference.epicentralDistanceKm * reference.epicentralDistanceKm +
            reference.depthKm * reference.depthKm,
      );
      final p = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: reference.depthKm,
        pWave: true,
      );
      final s = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: reference.depthKm,
        pWave: false,
      );

      // The six-term polynomial approximates the source table, so use a tight
      // approximation tolerance instead of exact table equality.
      expect(p, closeTo(reference.pSeconds, 0.06));
      expect(s, closeTo(reference.sSeconds, 0.07));
    }

    final wrongSurfaceOnlyP = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: 20,
      depthKm: 150,
      pWave: true,
    );
    expect(wrongSurfaceOnlyP, lessThan(3));
  });

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
