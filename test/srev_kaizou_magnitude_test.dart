import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';

void main() {
  group('srev-kaizou Scratch magnitude', () {
    test('rounds source coordinates to 0.1 degree before station scan', () {
      expect(srevKaizouRoundCoordinate(35.24), 35.2);
      expect(srevKaizouRoundCoordinate(140.26), 140.3);
    });

    test(
      'uses the original station-distance constants and operation order',
      () {
        const sourceLatitude = 35.2;
        const sourceLongitude = 140.3;
        const stationLatitude = 34.8;
        const stationLongitude = 139.7;
        final latitudePart = (sourceLatitude - stationLatitude) * 111.2;
        final longitudePart =
            6371.0 *
            (sourceLongitude - stationLongitude) *
            (3.1416 / 180.0) *
            math.cos(
              ((sourceLatitude + stationLatitude) / 2.0) * math.pi / 180.0,
            );
        final expected = math.sqrt(
          latitudePart * latitudePart + longitudePart * longitudePart,
        );

        expect(
          srevKaizouStationDistanceKm(
            roundedSourceLatitude: sourceLatitude,
            roundedSourceLongitude: sourceLongitude,
            stationLatitude: stationLatitude,
            stationLongitude: stationLongitude,
          ),
          closeTo(expected, 1e-12),
        );
      },
    );

    test('uses the complete Scratch d ten station table', () {
      expect(
        srevKaizouMagnitudeSourceProjectSha256,
        '13C441EDC1F865CEFA9A5399AD2AD9721E6B0868B6B2E7B20325E745B3335B3A',
      );
      expect(srevKaizouScratchStations, hasLength(1748));
      expect(srevKaizouScratchStations.first.code, 'scratch:0001');
      expect(srevKaizouScratchStations.first.name, '尾西');
      expect(srevKaizouScratchStations.first.longitude, 136.7505);
      expect(srevKaizouScratchStations.first.latitude, 35.2974);
      expect(srevKaizouScratchStations[12].name, '長篠');
      expect(srevKaizouScratchStations[12].longitude, 137.5749);
      expect(srevKaizouScratchStations[12].latitude, 34.9335);
      expect(srevKaizouScratchStations.last.code, 'scratch:1748');
      expect(srevKaizouScratchStations.last.name, '黒俣');
      expect(srevKaizouScratchStations.last.longitude, 138.1979);
      expect(srevKaizouScratchStations.last.latitude, 35.0332);

      final result = calculateSrevKaizouMagnitude(
        sourceLatitude: 35.25,
        sourceLongitude: 140.25,
        inputIntensity: 3.5,
        multipleSources: false,
      );
      expect(result, isNotNull);
      expect(result!.scannedStationCount, 1748);
    });

    test('selects the nearest station and clamps its distance to 20 km', () {
      final result = calculateSrevKaizouMagnitude(
        sourceLatitude: 35.04,
        sourceLongitude: 140.04,
        inputIntensity: 2.5,
        multipleSources: false,
        stations: const <SrevKaizouMagnitudeStation>[
          SrevKaizouMagnitudeStation(
            code: 'NEAR',
            latitude: 35.0,
            longitude: 140.0,
          ),
          SrevKaizouMagnitudeStation(
            code: 'FAR',
            latitude: 40.0,
            longitude: 145.0,
          ),
        ],
      );

      expect(result, isNotNull);
      expect(result!.roundedSourceLatitude, 35.0);
      expect(result.roundedSourceLongitude, 140.0);
      expect(result.nearestStationCode, 'NEAR');
      expect(result.nearestStationDistanceKm, 0.0);
      expect(result.clampedStationDistanceKm, 20.0);
    });

    test('keeps the two pow10 operations and outer log10 chain', () {
      const intensity = 3.5;
      const distanceKm = 42.0;
      final exponent = (intensity - 0.94) / 2.0;
      final firstPower = math.pow(10.0, exponent).toDouble();
      final secondPower = math.pow(10.0, exponent).toDouble();
      final expected =
          1.0 * (math.log(firstPower * secondPower) / math.ln10) +
          1.73 * (math.log(distanceKm) / math.ln10);

      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: distanceKm,
          inputIntensity: intensity,
          multipleSources: false,
        ),
        closeTo(expected, 1e-12),
      );
    });

    test(
      'applies the greater-than-four conversion only for multiple sources',
      () {
        expect(srevKaizouProcessedIntensity(5.5, multipleSources: false), 5.5);
        expect(srevKaizouProcessedIntensity(5.5, multipleSources: true), 5.75);
        expect(srevKaizouProcessedIntensity(4.0, multipleSources: true), 4.0);
      },
    );

    test('clamps negative magnitude to zero', () {
      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: 20.0,
          inputIntensity: -3.0,
          multipleSources: false,
        ),
        0.0,
      );
    });

    test('does not fabricate a result from missing or nonfinite input', () {
      expect(
        calculateSrevKaizouMagnitude(
          sourceLatitude: double.nan,
          sourceLongitude: 140.0,
          inputIntensity: 2.0,
          multipleSources: false,
        ),
        isNull,
      );
      expect(
        calculateSrevKaizouMagnitude(
          sourceLatitude: 35.0,
          sourceLongitude: 140.0,
          inputIntensity: double.infinity,
          multipleSources: false,
        ),
        isNull,
      );
      expect(
        calculateSrevKaizouMagnitude(
          sourceLatitude: 35.0,
          sourceLongitude: 140.0,
          inputIntensity: 2.0,
          multipleSources: false,
          stations: const <SrevKaizouMagnitudeStation>[],
        ),
        isNull,
      );
    });
  });

  group('srev-kaizou maximum-shindo state', () {
    test(
      'holds a station maximum for ten seconds then accepts the lower value',
      () {
        final state = SrevKaizouMagnitudeIntensityState();
        final startedAt = DateTime.utc(2026, 8, 10, 12);
        state.updateFrame(<String, double?>{'A': 4.3}, observedAt: startedAt);
        expect(state.maximumFor(const <String>['A']), 4.16);

        state.updateFrame(<String, double?>{
          'A': 2.2,
        }, observedAt: startedAt.add(const Duration(seconds: 10)));
        expect(state.maximumFor(const <String>['A']), 4.16);

        state.updateFrame(<String, double?>{
          'A': 2.2,
        }, observedAt: startedAt.add(const Duration(milliseconds: 10001)));
        expect(state.maximumFor(const <String>['A']), 2.16);
      },
    );

    test('time reversal clears held intensity and prevents stale reuse', () {
      final state = SrevKaizouMagnitudeIntensityState();
      final startedAt = DateTime.utc(2026, 8, 10, 12);
      state.updateFrame(<String, double?>{'A': 3.7}, observedAt: startedAt);
      expect(state.maximumFor(const <String>['A']), 3.5);

      state.updateFrame(const <String, double?>{
        'A': null,
      }, observedAt: startedAt.subtract(const Duration(seconds: 1)));
      expect(state.maximumFor(const <String>['A']), isNull);
    });

    test('missing initial intensity stays unavailable', () {
      final state = SrevKaizouMagnitudeIntensityState();
      state.updateFrame(const <String, double?>{
        'A': null,
      }, observedAt: DateTime.utc(2026, 8, 10, 12));
      expect(state.maximumFor(const <String>['A']), isNull);
    });
  });

  group('srev-kaizou report publication state', () {
    SrevKaizouMagnitudeResult result(double intensity) =>
        calculateSrevKaizouMagnitude(
          sourceLatitude: 35.0,
          sourceLongitude: 140.0,
          inputIntensity: intensity,
          multipleSources: false,
          stations: const <SrevKaizouMagnitudeStation>[
            SrevKaizouMagnitudeStation(
              code: 'TEST',
              latitude: 35.0,
              longitude: 140.0,
            ),
          ],
        )!;

    test('updates only when the HYP report changes', () {
      final state = SrevKaizouMagnitudePublicationState();
      var calculations = 0;
      final first = state.update(
        reportNumber: 1,
        stable: false,
        calculate: () {
          calculations += 1;
          return result(3.5);
        },
      );
      final sameReport = state.update(
        reportNumber: 1,
        stable: false,
        calculate: () {
          calculations += 1;
          return result(4.5);
        },
      );

      expect(calculations, 1);
      expect(sameReport, same(first));
      expect(sameReport!.inputIntensity, 3.5);
      expect(state.publishedReportNumber, 1);
      expect(state.locked, isFalse);
    });

    test('locks the current report at the stable point', () {
      final state = SrevKaizouMagnitudePublicationState();
      var calculations = 0;
      SrevKaizouMagnitudeResult? calculate() {
        calculations += 1;
        return result(calculations == 1 ? 3.5 : 4.5);
      }

      final first = state.update(
        reportNumber: 1,
        stable: false,
        calculate: calculate,
      );
      final locked = state.update(
        reportNumber: 1,
        stable: true,
        calculate: calculate,
      );
      final afterLock = state.update(
        reportNumber: 2,
        stable: false,
        calculate: calculate,
      );

      expect(calculations, 1);
      expect(locked, same(first));
      expect(afterLock, same(first));
      expect(state.locked, isTrue);
      expect(state.lockedReportNumber, 1);
    });

    test('retries a report until its input becomes valid', () {
      final state = SrevKaizouMagnitudePublicationState();
      var valid = false;
      var calculations = 0;
      final first = state.update(
        reportNumber: 1,
        stable: false,
        calculate: () {
          calculations += 1;
          return valid ? result(3.5) : null;
        },
      );
      valid = true;
      final second = state.update(
        reportNumber: 1,
        stable: true,
        calculate: () {
          calculations += 1;
          return valid ? result(3.5) : null;
        },
      );

      expect(first, isNull);
      expect(second, isNotNull);
      expect(calculations, 2);
      expect(state.locked, isTrue);
    });

    test('copies the publication and lock state when clusters merge', () {
      final source = SrevKaizouMagnitudePublicationState();
      final target = SrevKaizouMagnitudePublicationState();
      final published = source.update(
        reportNumber: 3,
        stable: true,
        calculate: () => result(3.5),
      );

      target.copyFrom(source);

      expect(target.publishedReportNumber, 3);
      expect(target.locked, isTrue);
      expect(target.lockedReportNumber, 3);
      expect(target.publishedResult, same(published));
    });
  });
}
