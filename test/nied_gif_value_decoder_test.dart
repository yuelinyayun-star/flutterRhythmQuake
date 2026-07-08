import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';

void main() {
  test('realtime shindo layer does not fabricate PGA PGV or PGD', () {
    final obs = NiedGifValueDecoder.decodeObservationFromPosition(0.35);
    expect(obs.colorPosition, closeTo(0.35, 1e-9));
    expect(obs.shindo, closeTo(0.5, 1e-9));
    expect(obs.layer, NiedGifLayer.realtimeShindo);
    expect(obs.pga, isNull);
    expect(obs.pgv, isNull);
    expect(obs.pgd, isNull);
  });

  test('physical layers decode only their matching quantity', () {
    final pga = NiedGifValueDecoder.decodeObservationFromPosition(
      0.35,
      layer: NiedGifLayer.peakAcceleration,
    );
    final pgv = NiedGifValueDecoder.decodeObservationFromPosition(
      0.35,
      layer: NiedGifLayer.peakVelocity,
    );
    final pgd = NiedGifValueDecoder.decodeObservationFromPosition(
      0.35,
      layer: NiedGifLayer.peakDisplacement,
    );

    expect(pga.pga, closeTo(0.56234132519, 1e-9));
    expect(pga.shindo, isNull);
    expect(pga.pgv, isNull);
    expect(pgv.pgv, closeTo(0.056234132519, 1e-12));
    expect(pgv.pga, isNull);
    expect(pgd.pgd, closeTo(0.0056234132519, 1e-12));
    expect(pgd.pga, isNull);
  });

  test('builds official per-layer surface and borehole URLs', () {
    final time = DateTime(2026, 6, 21, 16, 33, 18);
    expect(
      NiedGifLayer.peakAcceleration.imageUri(time, borehole: false).toString(),
      contains('/acmap_s/20260621/20260621163318.acmap_s.gif'),
    );
    expect(
      NiedGifLayer.peakVelocity.imageUri(time, borehole: true).toString(),
      contains('/vcmap_b/20260621/20260621163318.vcmap_b.gif'),
    );
  });
}
