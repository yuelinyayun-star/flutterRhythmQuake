import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  group('kanameishi 21-level mapping', () {
    test('continuous shindo is mapped by range, not by snapped 30-level value', () {
      final station = NiedStation(
        id: 0,
        code: 'TEST',
        name: 'TEST',
        coordinate: const LatLng(35.0, 140.0),
        network: 'K-NET',
        prefecture: 'TEST',
        expireSeconds: 30,
      );

      // 30段 level 9 normally displays as 0.50, which would map to 21段 level 8
      // if someone wrongly converts via display level. The true continuous
      // shindo here is still below 0.50, so the correct 21段 bin is 7.
      station.updateFromContinuousShindo(9, 0.49);

      expect(station.level, 9);
      expect(station.detectLevel, 7);
      expect(
        JpShindoScale.kanameishiLevelFromDisplayLevel(9),
        8,
        reason: 'Display-level back-conversion would wrongly snap this upward.',
      );
    });

    test('continuous shindo bin edges match 21-step half-unit ranges', () {
      expect(JpShindoScale.kanameishiLevelFromShindo(-3.00), 0);
      expect(JpShindoScale.kanameishiLevelFromShindo(-2.99), 1);
      expect(JpShindoScale.kanameishiLevelFromShindo(-2.50), 2);
      expect(JpShindoScale.kanameishiLevelFromShindo(-0.01), 6);
      expect(JpShindoScale.kanameishiLevelFromShindo(0.00), 7);
      expect(JpShindoScale.kanameishiLevelFromShindo(0.49), 7);
      expect(JpShindoScale.kanameishiLevelFromShindo(0.50), 8);
      expect(JpShindoScale.kanameishiLevelFromShindo(4.74), 16);
      expect(JpShindoScale.kanameishiLevelFromShindo(4.75), 16);
      expect(JpShindoScale.kanameishiLevelFromShindo(4.99), 16);
      expect(JpShindoScale.kanameishiLevelFromShindo(5.00), 17);
      expect(JpShindoScale.kanameishiLevelFromShindo(6.49), 19);
      expect(JpShindoScale.kanameishiLevelFromShindo(6.50), 20);
    });

    test('21-step level to 30-step display is intentionally not a strict inverse', () {
      expect(JpShindoScale.levelFromKanameishiLevel(1), 0);
      expect(JpShindoScale.levelFromKanameishiLevel(2), 1);
      expect(JpShindoScale.levelFromKanameishiLevel(7), 8);
      expect(JpShindoScale.levelFromKanameishiLevel(8), 9);
    });
  });
}
