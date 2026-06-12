import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';

void main() {
  test('NIED GIF position decoder preserves original shindo formula', () {
    final obs = NiedGifValueDecoder.decodeObservationFromPosition(0.35);
    expect(obs.colorPosition, closeTo(0.35, 1e-9));
    expect(obs.shindo, closeTo(0.5, 1e-9));
    expect(obs.pga, closeTo(0.56234132519, 1e-9));
    expect(obs.pgv, closeTo(0.056234132519, 1e-12));
    expect(obs.pgd, closeTo(0.0056234132519, 1e-12));
  });
}
