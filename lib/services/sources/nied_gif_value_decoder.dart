import 'dart:math';

import '../../core/replay/replay_versions.dart';
import 'nied_gif_observation.dart';
import 'shindo_color_util.dart';

class NiedGifValueDecoder {
  NiedGifValueDecoder._();

  static const String decoderVersion = ReplayDataVersions.niedGifLayeredDecoder;

  static NiedGifObservation? decodeObservationFromRgba(
    int r,
    int g,
    int b, {
    NiedGifLayer layer = NiedGifLayer.realtimeShindo,
  }) {
    final position = ShindoColorUtil.rgbaToPosition(r, g, b);
    if (position == null || !position.isFinite || position <= 0) {
      return null;
    }
    return decodeObservationFromPosition(position, layer: layer);
  }

  static NiedGifObservation decodeObservationFromPosition(
    double position, {
    NiedGifLayer layer = NiedGifLayer.realtimeShindo,
  }) {
    final p = position.clamp(0.0, 1.0);
    return switch (layer) {
      NiedGifLayer.realtimeShindo => NiedGifObservation(
        layer: layer,
        colorPosition: p,
        shindo: 10.0 * p - 3.0,
      ),
      NiedGifLayer.peakAcceleration => NiedGifObservation(
        layer: layer,
        colorPosition: p,
        pga: pow(10.0, 5.0 * p - 2.0).toDouble(),
      ),
      NiedGifLayer.peakVelocity => NiedGifObservation(
        layer: layer,
        colorPosition: p,
        pgv: pow(10.0, 5.0 * p - 3.0).toDouble(),
      ),
      NiedGifLayer.peakDisplacement => NiedGifObservation(
        layer: layer,
        colorPosition: p,
        pgd: pow(10.0, 5.0 * p - 4.0).toDouble(),
      ),
      _ => NiedGifObservation(
        layer: layer,
        colorPosition: p,
        velocityResponse: pow(10.0, 5.0 * p - 3.0).toDouble(),
      ),
    };
  }
}
