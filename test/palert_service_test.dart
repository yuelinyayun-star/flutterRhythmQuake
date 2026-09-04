import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/services/sources/palert_service.dart';

void main() {
  group('P-Alert timestamp parsing', () {
    test('parses the current GraphQL UTC wall-time format', () {
      expect(
        PAlertService.parseTimestamp('07/17/2026 07:29:49'),
        DateTime.utc(2026, 7, 17, 7, 29, 49),
      );
    });

    test('parses the ISO format returned by other backend nodes', () {
      expect(
        PAlertService.parseTimestamp('2026-07-17T07:29:49Z'),
        DateTime.utc(2026, 7, 17, 7, 29, 49),
      );
    });

    test('accepts only a strictly newer realtime frame', () {
      final previous = DateTime.utc(2026, 8, 19, 4, 20, 16);

      expect(
        PAlertService.isNewerFrameTime(
          previous,
          previous.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(PAlertService.isNewerFrameTime(previous, previous), isFalse);
      expect(
        PAlertService.isNewerFrameTime(
          previous,
          previous.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(PAlertService.isNewerFrameTime(null, previous), isTrue);
    });

    test('marks a feed stale only after the six-second frame deadline', () {
      final receivedAt = DateTime.utc(2026, 8, 19, 4, 20, 16);

      expect(
        PAlertService.isFrameStale(
          receivedAt,
          receivedAt.add(PAlertService.frameStaleAfter),
        ),
        isFalse,
      );
      expect(
        PAlertService.isFrameStale(
          receivedAt,
          receivedAt.add(
            PAlertService.frameStaleAfter + const Duration(milliseconds: 1),
          ),
        ),
        isTrue,
      );
      expect(PAlertService.isFrameStale(null, receivedAt), isFalse);
    });

    test('requires three consecutive transport failures', () {
      expect(PAlertService.maxConsecutiveFailures, 3);
    });
  });

  group('P-Alert CWA intensity', () {
    test(
      'keeps the fixed low-value marker floor independent of the setting',
      () {
        expect(PAlertService.numericMarkerPgaFloorGal, 0.7);
        expect(PAlertService.isPgaEligibleForNumericMarker(0.699999), isFalse);
        expect(PAlertService.isPgaEligibleForNumericMarker(0.7), isTrue);
        expect(PAlertService.isPgaEligibleForNumericMarker(0.700001), isTrue);
        expect(PAlertService.isPgaEligibleForNumericMarker(null), isFalse);
        expect(
          PAlertService.isPgaEligibleForNumericMarker(double.nan),
          isFalse,
        );
      },
    );

    test('uses PGA for intensity 0 through 4', () {
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 0.1), 0);
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 0.8), 1);
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 2.5), 2);
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 8.0), 3);
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 25.0), 4);
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 79.999, pgvCms: 200),
        4,
      );
    });

    test('uses PGV after PGA reaches the intensity 5 threshold', () {
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 80, pgvCms: 5),
        4,
      );
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 80, pgvCms: 15),
        5,
      );
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 140, pgvCms: 30),
        6,
      );
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 250, pgvCms: 50),
        7,
      );
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 440, pgvCms: 80),
        8,
      );
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 800, pgvCms: 140),
        9,
      );
    });

    test('does not guess high intensity without a valid PGV', () {
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 80), isNull);
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 80, pgvCms: -1),
        isNull,
      );
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(
          pgaGal: 80,
          pgvCms: double.nan,
        ),
        isNull,
      );
    });

    test('uses null only for missing or invalid PGA', () {
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(), isNull);
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: 0), isNull);
      expect(
        PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: double.nan),
        isNull,
      );
      expect(PAlertService.cwaIntensityIndexFromPgaPgv(pgvCms: 1.2), isNull);
    });

    test('maps CWA levels into the existing station marker scale', () {
      final station = PAlertStation(
        id: 'TEST',
        network: 'P-Alert',
        name: 'Test',
        area: 'Test',
        coordinate: const LatLng(23.5, 121),
        cwaIntensityIndex: 6,
        dataTime: DateTime.utc(2026, 7, 25),
      );

      expect(station.hasRealtime, isTrue);
      expect(station.gridLevel, 17);
      expect(station.shindoClass, 5);
      expect(station.shindoLabel, '5+');
    });

    test('keeps an unmeasured station separate from CWA intensity 0', () {
      const station = PAlertStation(
        id: 'TEST',
        network: 'P-Alert',
        name: 'Test',
        area: 'Test',
        coordinate: LatLng(23.5, 121),
      );

      expect(station.hasRealtime, isFalse);
      expect(station.gridLevel, -1);
      expect(station.shindoLabel, '--');
    });

    test('uses held CWA intensity for map and dashboard levels', () {
      const station = PAlertStation(
        id: 'TEST',
        network: 'P-Alert',
        name: 'Test',
        area: 'Test',
        coordinate: LatLng(23.5, 121),
        cwaIntensityIndex: 1,
        heldCwaIntensityIndex: 4,
      );

      expect(station.cwaIntensityIndex, 1);
      expect(station.displayCwaIntensityIndex, 4);
      expect(station.gridLevel, 15);
      expect(station.shindoLabel, '4');
    });
  });
}
