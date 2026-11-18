import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';

void main() {
  test('pointDistToArea treats intensity points as longitude latitude', () {
    final distance = IntensityCalculator.pointDistToArea(
      39.9,
      116.0,
      const [],
      const [(116.4, 39.9)],
    );

    expect(distance, greaterThan(30));
    expect(distance, lessThan(40));
  });

  test('CSIS maximum estimate attenuates the zero-distance term by depth', () {
    final shallow = IntensityCalculator.calcCsis(4.5, 10, 0);
    final deep = IntensityCalculator.calcCsis(4.5, 300, 0);

    expect(shallow, closeTo(5.577815711282662, 1e-12));
    expect(deep, closeTo(0.3247140292473505, 1e-12));
    expect(deep, lessThan(shallow));
  });

  test('CSIS station distance path remains distance-driven', () {
    expect(
      IntensityCalculator.calcCsis(4.5, 10, 100),
      closeTo(2.2176829061192755, 1e-12),
    );
    expect(
      IntensityCalculator.calcCsis(4.5, 300, 100),
      closeTo(1.2331449663477692, 1e-12),
    );
  });

  test('JMA source prediction is unavailable beyond 150 km depth', () {
    final atLimit = IntensityCalculator.calcJmaShindo(
      5.0,
      IntensityCalculator.maxJmaShindoPredictionDepthKm,
      35.0,
      140.0,
      35.0,
      140.0,
    );
    final deep = IntensityCalculator.calcJmaShindo(
      5.0,
      IntensityCalculator.maxJmaShindoPredictionDepthKm + 0.1,
      35.0,
      140.0,
      35.0,
      140.0,
    );

    expect(atLimit, greaterThan(-3.0));
    expect(deep, -3.0);
  });
}
