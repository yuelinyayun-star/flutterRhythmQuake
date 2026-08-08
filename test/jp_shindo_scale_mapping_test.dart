import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  group('kanameishi 21-level mapping', () {
    test('Yahoo level is consumed directly without conversion', () {
      final station = NiedStation(
        id: 0,
        code: 'TEST',
        name: 'TEST',
        coordinate: const LatLng(35.0, 140.0),
        network: 'K-NET',
        prefecture: 'TEST',
        expireSeconds: 30,
      );

      station.update(8);

      expect(station.level, 8);
      expect(station.kaLevel, 8);
    });

    test('GIF continuous shindo is converted directly to KA level', () {
      final station = NiedStation(
        id: 0,
        code: 'TEST',
        name: 'TEST',
        coordinate: const LatLng(35.0, 140.0),
        network: 'K-NET',
        prefecture: 'TEST',
        expireSeconds: 30,
      );

      station.updateFromContinuousShindo(0.49);

      expect(station.level, 7);
      expect(station.kaLevel, 7);
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
  });
}
