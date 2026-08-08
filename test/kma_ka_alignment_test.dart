import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/widgets/map/ka_kma_marker_style.dart';

void main() {
  group('KA KMA marker rules', () {
    test('uses hold level and zoom thresholds', () {
      expect(KaKmaMarkerStyle.shouldShowMarker(holdLevel: 3, zoom: 4), isFalse);
      expect(
        KaKmaMarkerStyle.shouldShowMarker(holdLevel: 4, zoom: 3.99),
        isFalse,
      );
      expect(KaKmaMarkerStyle.shouldShowMarker(holdLevel: 4, zoom: 4), isTrue);
      expect(
        KaKmaMarkerStyle.shouldShowMarker(
          holdLevel: 3,
          zoom: 4,
          displayShindo0: true,
        ),
        isTrue,
      );
    });

    test('preserves MMI 10 and 11 as levels 12 and 13', () {
      expect(KaKmaMarkerStyle.mmiForLevel(12), 10);
      expect(KaKmaMarkerStyle.mmiForLevel(13), 11);
      expect(
        KaKmaMarkerStyle.stationColorForLevel(12),
        const Color(0xFFAE0000),
      );
      expect(
        KaKmaMarkerStyle.stationColorForLevel(13),
        const Color(0xFFAD0000),
      );
      expect(KaKmaMarkerStyle.markerColorForLevel(13), const Color(0xFF7F007F));
    });

    test('uses the same station sizes as the NIED layer', () {
      expect(KaKmaMarkerStyle.dotSizeForZoom(3), 0.9);
      expect(KaKmaMarkerStyle.dotSizeForZoom(4), closeTo(1.85, 0.0001));
      expect(KaKmaMarkerStyle.dotSizeForZoom(7), closeTo(4.7, 0.0001));
      expect(KaKmaMarkerStyle.dotSizeForZoom(10), 7.5);
      expect(KaKmaMarkerStyle.labeledMarkerSize, 14.0);
      expect(KaKmaMarkerStyle.borderWidthForZoom(3.2), 0.35);
      expect(KaKmaMarkerStyle.borderWidthForZoom(7), 0.9);
      expect(KaKmaMarkerStyle.labelFontSizeForLevel(6), 7.0);
      expect(KaKmaMarkerStyle.labelFontSizeForLevel(7), 8.0);
    });
  });

  group('KA KMA station windows', () {
    test('defaults hold level to the current frame', () {
      final station = KmaStation(id: 1, coordinate: const LatLng(37.5, 127));

      station.update(6);
      expect(station.holdLevel, 8);
      expect(station.heldIntensity, 6);
      station.update(1);
      expect(station.holdLevel, 3);
      expect(station.heldIntensity, 1);
      station.update(11);
      expect(station.holdLevel, 13);
      expect(station.heldIntensity, 11);
    });

    test('honors configured hold frames', () {
      final station = KmaStation(id: 2, coordinate: const LatLng(37.5, 127));

      station.update(6, holdFrames: 5);
      station.update(1, holdFrames: 5);
      expect(station.holdLevel, 8);
    });

    test('starts ascend after 36 valid past samples', () {
      final station = KmaStation(id: 3, coordinate: const LatLng(37.5, 127));

      for (var i = 0; i < 47; i++) {
        station.update(0);
      }
      expect(station.ascend, 0);

      station.update(1);
      expect(station.ascend, 1);
    });
  });
}
