import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

void main() {
  test('exact black pixel is treated as no data', () {
    expect(ShindoColorUtil.rgbaToShindo(0, 0, 0), isNull);
  });

  test('known green station color still decodes to positive shindo', () {
    final shindo = ShindoColorUtil.rgbaToShindo(75, 250, 49);
    expect(shindo, isNotNull);
    expect(shindo!, greaterThan(0));
  });
}
