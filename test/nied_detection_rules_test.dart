import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/nied_detection_rules.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  test('KA detection grid extends each active cell to surrounding 9 cells', () {
    final latitudeDecimal = niedDetectionGridDecimalPart(37.34);
    final longitudeDecimal = niedDetectionGridDecimalPart(141.27);
    expect(latitudeDecimal, 0.3);
    expect(longitudeDecimal, 0.3);

    final latitudeIndex = niedDetectionGridAxisIndex(37.34, latitudeDecimal);
    final longitudeIndex = niedDetectionGridAxisIndex(141.27, longitudeDecimal);
    final centerKey = niedDetectionGridKey(latitudeIndex, longitudeIndex);
    final surrounding = niedDetectionSurroundingGridKeys([centerKey]);

    expect(surrounding, hasLength(9));
    expect(surrounding, contains(niedDetectionGridKey(36, 140)));
    expect(surrounding, contains(niedDetectionGridKey(37, 141)));
    expect(surrounding, contains(niedDetectionGridKey(38, 142)));
    expect(surrounding, isNot(contains(niedDetectionGridKey(39, 143))));
    expect(niedDetectionGridAxisCenter(latitudeIndex, latitudeDecimal), 37.3);
    expect(
      niedDetectionGridAxisCenter(longitudeIndex, longitudeDecimal),
      141.3,
    );
  });

  test('KA levels 0 through 20 use exact instantaneous shindo ranges', () {
    expect(JpShindoScale.kanameishiLevelFromShindo(-3.000001), -1);
    expect(JpShindoScale.kanameishiLevelFromShindo(-3.0), 0);
    expect(JpShindoScale.rawShindoFromKanameishiLevel(0), -3.0);
    expect(JpShindoScale.kanameishiLevelFromShindo(-2.999999), 1);
    expect(JpShindoScale.kanameishiLevelFromShindo(-2.500001), 1);

    for (var level = 2; level <= 19; level++) {
      final lowerInclusive = (level - 7) / 2.0;
      final upperExclusive = (level - 6) / 2.0;
      expect(JpShindoScale.kanameishiLevelFromShindo(lowerInclusive), level);
      expect(
        JpShindoScale.kanameishiLevelFromShindo(upperExclusive - 0.000001),
        level,
      );
      expect(
        JpShindoScale.kanameishiLevelFromShindo(upperExclusive),
        level + 1,
      );
    }

    expect(JpShindoScale.kanameishiLevelFromShindo(6.5), 20);
    expect(JpShindoScale.kanameishiLevelFromShindo(10), 20);
  });

  test('KA levels map to all ten JMA intensity classes', () {
    const expectedJmaIndexes = [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      2,
      2,
      3,
      3,
      4,
      4,
      5, // 5弱
      6, // 5強
      7, // 6弱
      8, // 6強
      9, // 7
    ];

    for (var level = 0; level <= 20; level++) {
      expect(
        JpShindoScale.jmaIndexFromKanameishiLevel(level),
        expectedJmaIndexes[level],
        reason: 'KA level $level',
      );
    }
  });

  test('KA sensitivity thresholds use the exact three reference tables', () {
    expect(niedActivityThresholds[1], [
      double.infinity,
      10,
      14,
      16,
      18,
      19,
      20,
    ]);
    expect(niedActivityThresholds[2], [double.infinity, 8, 11, 13, 14, 15, 16]);
    expect(niedActivityThresholds[3], [double.infinity, 6, 9, 11, 12, 13, 14]);
    expect(niedStationCountThreshold(1, 6), 4);
    expect(niedStationCountThreshold(2, 6), 3);
    expect(niedStationCountThreshold(3, 6), 3);
  });

  test('KA abnormal station pair uses distance propagation allowance', () {
    expect(
      isNiedAbnormalStationPair(
        firstTriggerStamp: 100000,
        secondTriggerStamp: 112000,
        distanceKm: 35,
      ),
      isFalse,
    );
    expect(
      isNiedAbnormalStationPair(
        firstTriggerStamp: 100000,
        secondTriggerStamp: 112001,
        distanceKm: 35,
      ),
      isTrue,
    );
  });

  test('station ascend and activity use KA level instead of display level', () {
    final frameTime = DateTime(2026, 7, 17, 12);
    final station =
        NiedStation(
            id: 2,
            code: 'TEST002',
            name: 'TEST002',
            coordinate: const LatLng(35, 140),
            network: 'K-NET',
            prefecture: 'Test',
            expireSeconds: 10,
          )
          ..lastDataTime = frameTime
          ..recentLevel = [8];

    station.update(10);

    expect(station.level, 10);
    expect(station.kaLevel, 10);
    expect(station.ascend, 2);
    expect(station.activity, 7);
    expect(
      station.triggerStamp,
      frameTime.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );
    expect(station.expireSeconds, NiedStation.kaExpireSeconds);
  });

  test('KA ascend keeps a short deep valley as a valid trigger baseline', () {
    final station =
        NiedStation(
            id: 3,
            code: 'TEST003',
            name: 'TEST003',
            coordinate: const LatLng(35, 140),
            network: 'K-NET',
            prefecture: 'Test',
            expireSeconds: 10,
          )
          ..lastDataTime = DateTime(2026, 7, 17, 12)
          ..recentLevel = [0, 0, 5];

    station.update(5);

    expect(station.recentLevel, [5, 0, 0, 5]);
    expect(station.ascend, 5);
    expect(
      station.triggerStamp,
      station.lastDataTime!
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
    );
    expect(station.activity, greaterThan(0));
  });

  test('KA ascend stops at the first one-level rebound', () {
    final frameTime = DateTime(2026, 7, 17, 12);
    final station =
        NiedStation(
            id: 4,
            code: 'TEST004',
            name: 'TEST004',
            coordinate: const LatLng(35, 140),
            network: 'K-NET',
            prefecture: 'Test',
            expireSeconds: 10,
          )
          ..lastDataTime = frameTime
          ..recentLevel = [4, 5, 0];

    station.update(5);

    expect(station.recentLevel, [5, 4, 5, 0]);
    expect(station.ascend, 1);
    expect(
      station.triggerStamp,
      frameTime.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );
  });

  test('KA abnormal station quarantine lasts 600 normal updates', () {
    final start = DateTime(2026, 7, 17, 12);
    final station = NiedStation(
      id: 1,
      code: 'TEST001',
      name: 'TEST001',
      coordinate: const LatLng(35, 140),
      network: 'K-NET',
      prefecture: 'Test',
      expireSeconds: 10,
    )..lastDataTime = start;

    station.recentLevel = [3, 0, 3, 0, 3, 0];
    station.update(0);
    expect(station.abnormalUpdateCount, 0);
    expect(station.ascend, 0);

    station.recentLevel.clear();
    for (var update = 1; update <= 599; update++) {
      station.lastDataTime = start.add(Duration(seconds: update));
      station.update(0);
    }
    expect(station.abnormalUpdateCount, 599);
    expect(station.ascend, 0);

    station.lastDataTime = start.add(const Duration(seconds: 600));
    station.update(0);
    expect(station.abnormalUpdateCount, isNull);
    expect(station.ascend, 0);

    station.recentLevel = [5, 0];
    station.lastDataTime = start.add(const Duration(seconds: 601));
    station.update(5);
    expect(station.ascend, 5);
    expect(station.triggerStamp, greaterThan(0));
  });
}
