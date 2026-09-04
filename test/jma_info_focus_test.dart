import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/jma_info_focus.dart';

void main() {
  test('P2P ScalePrompt focus uses known JMA intensity areas', () {
    final points = jmaInfoFocusPoints(
      warnAreaJson: '[{"name":"埼玉県南部","intensity":"3","className":"green"}]',
    );

    expect(points, hasLength(2));
    expect(points.first.latitude, lessThan(points.last.latitude));
    expect(points.first.longitude, lessThan(points.last.longitude));
  });

  test(
    'P2P Destination focus includes epicenter and retained intensity areas',
    () {
      final points = jmaInfoFocusPoints(
        warnAreaJson: '[{"name":"埼玉県南部","intensity":"3","className":"green"}]',
        epicenterLatitude: 36.2,
        epicenterLongitude: 140.5,
      );

      expect(points, hasLength(3));
      expect(points.first.latitude, 36.2);
      expect(points.first.longitude, 140.5);
    },
  );

  test('invalid area payload never turns missing coordinates into a focus', () {
    expect(jmaInfoFocusPoints(warnAreaJson: 'invalid'), isEmpty);
  });
}
