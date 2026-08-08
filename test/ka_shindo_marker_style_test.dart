import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/widgets/map/ka_shindo_marker_style.dart';

void main() {
  group('KA station marker threshold', () {
    test('requires level 8 and zoom 4', () {
      expect(KaShindoMarkerStyle.shouldShowMarker(level: 7, zoom: 4), isFalse);
      expect(
        KaShindoMarkerStyle.shouldShowMarker(level: 8, zoom: 3.99),
        isFalse,
      );
      expect(KaShindoMarkerStyle.shouldShowMarker(level: 8, zoom: 4), isTrue);
      expect(KaShindoMarkerStyle.shouldShowMarker(level: 20, zoom: 10), isTrue);
      expect(
        KaShindoMarkerStyle.shouldShowMarker(
          level: 5,
          zoom: 4,
          displayShindo0: true,
        ),
        isFalse,
      );
      expect(
        KaShindoMarkerStyle.shouldShowMarker(
          level: 6,
          zoom: 4,
          displayShindo0: true,
        ),
        isTrue,
      );
    });

    test('TREM and P-Alert feed the threshold with KA levels', () {
      expect(CwaStationService.gridLevelFromInstShindo(0.49), 7);
      expect(CwaStationService.gridLevelFromInstShindo(0.50), 8);

      const stationBase = PAlertStation(
        id: 'TEST',
        network: 'P-Alert',
        name: 'Test',
        area: 'Test',
        coordinate: LatLng(23.5, 121),
      );
      expect(stationBase.copyWith(cwaIntensityIndex: 0).gridLevel, 7);
      expect(stationBase.copyWith(cwaIntensityIndex: 1).gridLevel, 9);
    });
  });

  group('KA station marker presentation', () {
    test('keeps all strong-shaking labels', () {
      expect(KaShindoMarkerStyle.labelForLevel(15), '4');
      expect(KaShindoMarkerStyle.labelForLevel(16), '5弱');
      expect(KaShindoMarkerStyle.labelForLevel(17), '5強');
      expect(KaShindoMarkerStyle.labelForLevel(18), '6弱');
      expect(KaShindoMarkerStyle.labelForLevel(19), '6強');
      expect(KaShindoMarkerStyle.labelForLevel(20), '7');
    });

    test('uses the KA 21-level color bands', () {
      expect(KaShindoMarkerStyle.colorForLevel(7), const Color(0xFF9F9F9F));
      expect(KaShindoMarkerStyle.colorForLevel(8), const Color(0xFFCFCFCF));
      expect(KaShindoMarkerStyle.colorForLevel(10), const Color(0xFF3FAFFF));
      expect(KaShindoMarkerStyle.colorForLevel(12), const Color(0xFF5FDF8F));
      expect(KaShindoMarkerStyle.colorForLevel(14), const Color(0xFFF7E757));
      expect(KaShindoMarkerStyle.colorForLevel(16), const Color(0xFFFF8F00));
      expect(KaShindoMarkerStyle.colorForLevel(17), const Color(0xFFFF4F00));
      expect(KaShindoMarkerStyle.colorForLevel(18), const Color(0xFFDF0F0F));
      expect(KaShindoMarkerStyle.colorForLevel(19), const Color(0xFFAF0000));
      expect(KaShindoMarkerStyle.colorForLevel(20), const Color(0xFF7F007F));
    });
  });
}
