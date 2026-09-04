import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/calculator.dart';

void main() {
  group('QuakeCalculator.isUsableMapCoordinate', () {
    test('accepts normal Japan coordinates', () {
      expect(QuakeCalculator.isUsableMapCoordinate(35.6, 139.7), isTrue);
    });

    test('accepts real epicenter at equator/prime meridian', () {
      expect(QuakeCalculator.isUsableMapCoordinate(0, 0), isTrue);
    });

    test('rejects non-finite values', () {
      expect(QuakeCalculator.isUsableMapCoordinate(double.nan, 139.0), isFalse);
      expect(
        QuakeCalculator.isUsableMapCoordinate(35.0, double.infinity),
        isFalse,
      );
    });

    test('rejects out-of-range values', () {
      expect(QuakeCalculator.isUsableMapCoordinate(91, 0), isFalse);
      expect(QuakeCalculator.isUsableMapCoordinate(0, 181), isFalse);
    });
  });

  group('QuakeCalculator.isLikelyUninitializedCoordinate', () {
    test('flags Kotoho7 scratch placeholder defaults', () {
      expect(QuakeCalculator.isLikelyUninitializedCoordinate(0, 0), isTrue);
    });

    test('does not flag nearby real coordinates', () {
      expect(
        QuakeCalculator.isLikelyUninitializedCoordinate(0.1, 140.1),
        isFalse,
      );
    });
  });
}
