import 'dart:math';

import 'nied_gif_observation.dart';
import 'shindo_color_util.dart';

class NiedGifValueDecoder {
  NiedGifValueDecoder._();

  static NiedGifObservation? decodeObservationFromRgba(int r, int g, int b) {
    final position = ShindoColorUtil.rgbaToPosition(r, g, b);
    if (position == null || !position.isFinite || position <= 0) {
      return null;
    }
    return decodeObservationFromPosition(position);
  }

  static NiedGifObservation decodeObservationFromPosition(double position) {
    final p = position.clamp(0.0, 1.0);
    return NiedGifObservation(
      colorPosition: p,
      shindo: 10.0 * p - 3.0,
      pga: pow(10.0, 5.0 * p - 2.0).toDouble(),
      pgv: pow(10.0, 5.0 * p - 3.0).toDouble(),
      pgd: pow(10.0, 5.0 * p - 4.0).toDouble(),
    );
  }
}
