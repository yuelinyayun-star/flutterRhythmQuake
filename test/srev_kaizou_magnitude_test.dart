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

    test('applies the D-conditioned intensity slope plus the distance term', () {
      const intensity = 3.5;
      const distanceKm = 42.0;
      final distanceTerm = 1.73 * (math.log(distanceKm) / math.ln10);
      final legacy = (intensity - 0.94) + distanceTerm;
      final raised =
          srevKaizouMagnitudeIntensitySlope * intensity +
          srevKaizouMagnitudeIntensityOffset +
          distanceTerm;
      final weight = srevKaizouMagnitudeDistanceWeight(distanceKm);
      final expected = legacy + weight * (raised - legacy);

      expect(weight, closeTo(20.0 / 42.0, 1e-12));
      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: distanceKm,
          inputIntensity: intensity,
          multipleSources: false,
        ),
        closeTo(expected, 1e-12),
      );
      // 锚定值：legacy + (20/42)·(raised − legacy) ≈ 5.3615
      // （无条件重拟合版本为 5.3541，生产旧式为 5.3682）
      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: distanceKm,
          inputIntensity: intensity,
          multipleSources: false,
        ),
        closeTo(5.3615, 1e-3),
      );
    });

    test('applies the full intensity raise at the 20 km clamp floor', () {
      // D 触底时 w=1，退化为无条件重拟合式 slope·I + offset + 1.73·log10(20)。
      const intensity = 1.83;
      final expected = srevKaizouMagnitudeIntensitySlope * intensity +
          srevKaizouMagnitudeIntensityOffset +
          1.73 * (math.log(20.0) / math.ln10);
      expect(srevKaizouMagnitudeDistanceWeight(20.0), 1.0);
      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: 20.0,
          inputIntensity: intensity,
          multipleSources: false,
        ),
        closeTo(expected, 1e-12),
      );
      // 锚定值：0.7016*1.83 + 0.0903 + 1.73*log10(20) ≈ 3.6250
      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: 20.0,
          inputIntensity: intensity,
          multipleSources: false,
        ),
        closeTo(3.6250, 1e-3),
      );
    });

    test('distance weight decays as 20/D beyond the clamp floor', () {
      expect(srevKaizouMagnitudeDistanceWeight(20.0), 1.0);
      expect(srevKaizouMagnitudeDistanceWeight(40.0), closeTo(0.5, 1e-12));
      expect(srevKaizouMagnitudeDistanceWeight(100.0), closeTo(0.2, 1e-12));
      // 未钳位（<20km）也保底 1，不放大抬升量。
      expect(srevKaizouMagnitudeDistanceWeight(10.0), 1.0);
      expect(srevKaizouMagnitudeDistanceWeight(double.nan), 0.0);
      expect(srevKaizouMagnitudeDistanceWeight(0.0), 0.0);
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
      // 旧系数在 I=−3 时即触发钳零；新斜率下该输入约为 +0.24，
      // 故改用更极端的输入来覆盖钳零分支。
      expect(
        srevKaizouMagnitudeFromDistanceAndIntensity(
          stationDistanceKm: 20.0,
          inputIntensity: -10.0,
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

  group('srev-kaizou report publication state (JMA policy)', () {
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

    SrevKaizouMagnitudeResult resultAt(
      double intensity,
      double latitude,
      double longitude,
    ) => calculateSrevKaizouMagnitude(
      sourceLatitude: latitude,
      sourceLongitude: longitude,
      inputIntensity: intensity,
      multipleSources: false,
    )!;

    final startedAt = DateTime.utc(2026, 10, 13, 20, 44, 24);

    test('re-publishes whenever the observed intensity improves', () {
      // JMA は「推定精度が良くなるたびに更新して発表する」。同一 HYP 報の
      // 中でも入力震度が上がれば M を再公開し、下がっても後退させない。
      final state = SrevKaizouMagnitudePublicationState();
      var calculations = 0;
      SrevKaizouMagnitudeResult tracked(double intensity) {
        calculations += 1;
        return result(intensity);
      }

      final first = state.update(
        reportNumber: 1,
        stable: false,
        observedAt: startedAt,
        observedIntensity: 3.5,
        calculate: tracked,
      );
      final improved = state.update(
        reportNumber: 1,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 1)),
        observedIntensity: 4.5,
        calculate: tracked,
      );
      final lower = state.update(
        reportNumber: 1,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 2)),
        observedIntensity: 4.0,
        calculate: tracked,
      );

      expect(calculations, 3);
      expect(first!.inputIntensity, 3.5);
      expect(improved!.inputIntensity, 4.5);
      // 後退は公開しない。
      expect(lower, same(improved));
      expect(state.publishedInputIntensity, 4.5);
      expect(state.improvementCount, 2);
      expect(state.locked, isFalse);
    });

    test('finalises at the JMA final report: stable and observation matured',
        () {
      final state = SrevKaizouMagnitudePublicationState();
      SrevKaizouMagnitudeResult? calculate(double intensity) =>
          result(intensity);

      final first = state.update(
        reportNumber: 1,
        stable: false,
        observedAt: startedAt,
        observedIntensity: 3.5,
        calculate: calculate,
      );
      // 震源は安定したが、直前に震度が改善したばかりで未成熟 → まだ凍結しない。
      final notYet = state.update(
        reportNumber: 1,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 1)),
        observedIntensity: 4.5,
        calculate: calculate,
      );
      expect(state.locked, isFalse);

      // 震度がホールド期間改善しなくなって初めて確定する（最終報相当）。
      final locked = state.update(
        reportNumber: 1,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 11)),
        observedIntensity: 4.5,
        calculate: calculate,
      );
      final afterLock = state.update(
        reportNumber: 2,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 12)),
        observedIntensity: 4.5,
        calculate: calculate,
      );

      expect(first!.inputIntensity, 3.5);
      expect(notYet!.inputIntensity, 4.5);
      expect(locked, same(notYet));
      expect(afterLock, same(notYet));
      expect(state.locked, isTrue);
      expect(state.lockedReportNumber, 1);
      expect(state.lockReason, 'stable_and_observation_matured');
    });

    test('re-opens the frozen magnitude when a new report moves the source cell',
        () {
      // 宮城県沖 2026-10-13 22:05 の実測：震央が 0.1° 格子で 141.9→141.7 へ
      // 収束した後も M が 141.9 基準のまま凍結し +0.22 過大になっていた。
      final state = SrevKaizouMagnitudePublicationState();
      state.update(
        reportNumber: 10,
        stable: false,
        observedAt: startedAt,
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.9),
      );
      final locked = state.update(
        reportNumber: 10,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 11)),
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.9),
      );
      expect(state.locked, isTrue);
      expect(state.lockedReportNumber, 10);
      expect(locked!.roundedSourceLongitude, 141.9);

      // 新しい報で震源格子が 141.7 へ移動 → ロック解除して再計算。
      final moved = state.update(
        reportNumber: 11,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 12)),
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.7),
      );
      expect(moved, isNotNull);
      expect(moved, isNot(same(locked)));
      expect(moved!.roundedSourceLongitude, 141.7);
      expect(state.locked, isFalse);
      expect(state.lockReason, 'reopened_source_cell_changed');

      // 同一格子の再報では再公開しない。
      final repeat = state.update(
        reportNumber: 11,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 13)),
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.7),
      );
      expect(repeat, same(moved));

      // 震源が安定しかつ観測成熟で再ロックする。
      final relocked = state.update(
        reportNumber: 11,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 23)),
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.7),
      );
      expect(state.locked, isTrue);
      expect(relocked!.roundedSourceLongitude, 141.7);
    });

    test('keeps a monotone intensity peak across a source-cell move', () {
      // 震源格子が動いても、その時点の震度が既にピークを下回っていれば
      // M はピーク震度で再計算される（震源変化で震度が後退してはならない）。
      final state = SrevKaizouMagnitudePublicationState();
      state.update(
        reportNumber: 10,
        stable: false,
        observedAt: startedAt,
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.9),
      );
      state.update(
        reportNumber: 10,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 11)),
        observedIntensity: 1.83,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.9),
      );
      expect(state.locked, isTrue);

      // 震源格子が移動。観測震度は既に減衰（-0.17）しているがピーク 1.83 を保つ。
      final moved = state.update(
        reportNumber: 11,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 12)),
        observedIntensity: -0.17,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.7),
      );
      expect(moved, isNotNull);
      expect(moved!.inputIntensity, closeTo(1.83, 1e-9));
      expect(moved.roundedSourceLongitude, 141.7);
      expect(state.publishedInputIntensity, closeTo(1.83, 1e-9));
    });

    test('keeps the frozen magnitude when a new report stays in the same cell',
        () {
      final state = SrevKaizouMagnitudePublicationState();
      state.update(
        reportNumber: 10,
        stable: false,
        observedAt: startedAt,
        observedIntensity: 3.5,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.9),
      );
      final locked = state.update(
        reportNumber: 10,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 11)),
        observedIntensity: 3.5,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.9),
      );
      expect(state.locked, isTrue);

      // 141.94 は 0.1° 丸めで 141.9 のまま → 距離項も同じ → ロック維持。
      final subCell = state.update(
        reportNumber: 11,
        stable: false,
        observedAt: startedAt.add(const Duration(seconds: 12)),
        observedIntensity: 3.5,
        calculate: (intensity) => resultAt(intensity, 38.5, 141.94),
      );
      expect(subCell, same(locked));
      expect(state.locked, isTrue);
      expect(state.lockedReportNumber, 10);
    });

    test('tracks the intensity peak before finalising the weak event', () {
      // 紀伊水道 2026-10-13 の実測：報#4 が震度 0.5 で安定した後も
      // ピークは 1.5（震度2）まで上昇した。旧方針は 0.5 で凍結していた。
      final state = SrevKaizouMagnitudePublicationState();
      final early = state.update(
        reportNumber: 4,
        stable: true,
        observedAt: startedAt,
        observedIntensity: 0.5,
        calculate: (intensity) => result(intensity),
      );
      final mid = state.update(
        reportNumber: 4,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 3)),
        observedIntensity: 0.83,
        calculate: (intensity) => result(intensity),
      );
      final peak = state.update(
        reportNumber: 4,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 9)),
        observedIntensity: 1.5,
        calculate: (intensity) => result(intensity),
      );
      final finalised = state.update(
        reportNumber: 4,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 19)),
        observedIntensity: 0.83,
        calculate: (intensity) => result(intensity),
      );

      expect(early!.inputIntensity, 0.5);
      expect(mid!.inputIntensity, 0.83);
      expect(peak!.inputIntensity, 1.5);
      expect(finalised, same(peak));
      expect(state.locked, isTrue);
      expect(state.publishedInputIntensity, 1.5);
    });

    test('retries a report until its input becomes valid', () {
      final state = SrevKaizouMagnitudePublicationState();
      var valid = false;
      var calculations = 0;
      SrevKaizouMagnitudeResult? calculate(double intensity) {
        calculations += 1;
        return valid ? result(intensity) : null;
      }

      final first = state.update(
        reportNumber: 1,
        stable: false,
        observedAt: startedAt,
        observedIntensity: 3.5,
        calculate: calculate,
      );
      valid = true;
      final second = state.update(
        reportNumber: 1,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 1)),
        observedIntensity: 3.5,
        calculate: calculate,
      );
      final maturity = state.update(
        reportNumber: 1,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 11)),
        observedIntensity: 3.5,
        calculate: calculate,
      );

      expect(first, isNull);
      expect(second, isNotNull);
      expect(maturity, isNotNull);
      expect(calculations, 3);
      expect(state.locked, isTrue);
    });

    test('copies the publication and lock state when clusters merge', () {
      final source = SrevKaizouMagnitudePublicationState();
      final target = SrevKaizouMagnitudePublicationState();
      source.update(
        reportNumber: 3,
        stable: true,
        observedAt: startedAt,
        observedIntensity: 3.5,
        calculate: (intensity) => result(intensity),
      );
      final published = source.update(
        reportNumber: 3,
        stable: true,
        observedAt: startedAt.add(const Duration(seconds: 11)),
        observedIntensity: 3.5,
        calculate: (intensity) => result(intensity),
      );

      target.copyFrom(source);

      expect(target.publishedReportNumber, 3);
      expect(target.locked, isTrue);
      expect(target.lockedReportNumber, 3);
      expect(target.publishedResult, same(published));
      expect(target.publishedInputIntensity, 3.5);
    });
  });
}
