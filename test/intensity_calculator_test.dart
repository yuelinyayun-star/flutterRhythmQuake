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
}
