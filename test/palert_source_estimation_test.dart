import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/palert_source_profile.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_estimation.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_worker.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';

// Controlled algorithm tests, not recordings or real earthquake observations.
final base = DateTime.utc(2026, 9, 21);
PAlertStation sample(int second, double? pga, {int index = 0}) => PAlertStation(
  id: 'TEST-$index',
  network: 'P-Alert',
  name: 'TEST-$index',
  area: 'TEST',
  coordinate: LatLng(23.5 + index * 0.01, 121 + index * 0.01),
  pgaGal: pga,
  cwaIntensityIndex: PAlertService.cwaIntensityIndexFromPgaPgv(pgaGal: pga),
  heldCwaIntensityIndex: 9,
  dataTime: base.add(Duration(seconds: second)),
  receivedAt: base.add(Duration(seconds: second)),
);

void main() {
  test('KA internal level boundaries are not CWA display categories', () {
    for (var i = 0; i < PAlertSourceProfile.pgaThresholds.length; i++) {
      final threshold = PAlertSourceProfile.pgaThresholds[i];
      expect(PAlertSourceProfile.level(threshold - 1e-9, null), i);
      expect(PAlertSourceProfile.level(threshold, null), i + 1);
    }
    for (var i = 0; i < PAlertSourceProfile.pgvThresholds.length; i++) {
      final threshold = PAlertSourceProfile.pgvThresholds[i];
      expect(PAlertSourceProfile.level(80, threshold - 1e-9), 15 + i);
      expect(PAlertSourceProfile.level(80, threshold), 16 + i);
    }
    expect(PAlertSourceProfile.level(80, null), -1);
    expect(PAlertSourceProfile.level(null, 30), -1);
    expect(PAlertSourceProfile.level(double.nan, 30), -1);
    expect(PAlertSourceProfile.level(-1, 30), -1);
    expect(PAlertSourceProfile.pickWeight(5), 0);
    expect(PAlertSourceProfile.pickWeight(6), 0.1);
    expect(PAlertSourceProfile.pickWeight(7), 0.4);
    expect(PAlertSourceProfile.pickWeight(8), 1.6);
    expect(PAlertSourceProfile.pickWeight(9), 2.4);
    expect(PAlertSourceProfile.pickWeight(20), 4);
  });

  test('pick needs eight consecutive raw seconds, ignoring display hold', () {
    final pick = PAlertSourcePick();
    for (var t = 0; t < 8; t++) {
      pick.update(sample(t, 0.3));
      expect(pick.triggerAt, isNull);
    }
    pick.update(sample(8, 0.45));
    expect(pick.triggerAt, isNull);
    pick.update(sample(9, 0.45));
    expect(pick.triggerAt, base.add(const Duration(seconds: 8)));
    expect(pick.maxLevel, 6);
    expect(pick.secondMaxLevel, 6);
  });

  test('single double rise, duplicate frames, decay and gaps', () {
    final pick = PAlertSourcePick();
    for (var t = 0; t < 8; t++) {
      pick.update(sample(t, 0.2));
    }
    pick.update(sample(8, 0.8));
    expect(pick.triggerAt, base.add(const Duration(seconds: 8)));
    for (var i = 0; i < 20; i++) {
      pick.update(sample(8, 0.8));
    }
    expect(pick.secondMaxLevel, -1);
    pick.update(sample(9, 0.8));
    expect(pick.secondMaxLevel, 8);
    for (var t = 10; t < 18; t++) {
      pick.update(sample(t, 0.2));
    }
    expect(pick.triggerAt, isNull);
    pick.update(sample(20, 1.5));
    expect(pick.triggerAt, isNull);
    pick.update(sample(21, null));
    expect(pick.updatedAt, isNull);
  });

  test('raw zero is quiet; high PGA must not reuse retained PGV', () {
    final pick = PAlertSourcePick();
    for (var t = 0; t < 8; t++) {
      pick.update(sample(t, 0));
    }
    expect(pick.hasQuietHistory, isTrue);
    pick.update(sample(8, 0.8));
    expect(pick.triggerAt, isNotNull);
    pick.update(
      PAlertStation(
        id: 'TEST-0',
        network: 'P-Alert',
        name: 'TEST-0',
        area: 'TEST',
        coordinate: const LatLng(23.5, 121),
        pgaGal: 90,
        pgvCms: 40,
        cwaIntensityIndex: null,
        dataTime: base.add(const Duration(seconds: 9)),
        receivedAt: base.add(const Duration(seconds: 9)),
      ),
    );
    expect(pick.triggerAt, isNull);
  });

  test('unconfirmed or held-only observations cannot publish', () {
    final session = PAlertSourceEstimation();
    for (var t = 0; t < 12; t++) {
      final stations = [
        for (var i = 0; i < 6; i++) sample(t, t < 8 ? 0.02 : 1.5, index: i),
      ];
      expect(
        session.update(stations, {}, base.add(Duration(seconds: t))),
        isEmpty,
      );
      expect(stations.first.pgaGal, t < 8 ? 0.02 : 1.5);
    }
  });

  test('confirmed picks publish an independent HYP result and expire', () {
    final session = PAlertSourceEstimation();
    final ids = {for (var i = 0; i < 6; i++) 'TEST-$i'};
    for (var t = 0; t < 8; t++) {
      expect(
        session.update(
          [for (var i = 0; i < 6; i++) sample(t, 0.02, index: i)],
          {},
          base.add(Duration(seconds: t)),
        ),
        isEmpty,
      );
    }
    final frame = [for (var i = 0; i < 6; i++) sample(8, 2.5, index: i)];
    final results = session.update(
      frame,
      ids,
      base.add(const Duration(seconds: 8)),
    );
    expect(results, isNotEmpty);
    expect(results.every(PAlertSourceEstimation.isPublishable), isTrue);
    expect(results.first.method, 'palert_hyp_v1');
    expect(results.first.magnitude, isNull);
    expect(results.first.diagnostics['quality_score'], isA<num>());
    expect(
      session.update(frame, ids, base.add(const Duration(seconds: 15))),
      isEmpty,
    );
  });

  test(
    'foreground confirmed IDs are exact and stale payloads cannot renew',
    () {
      final payload = <String, dynamic>{
        'receivedTime': base.toIso8601String(),
        'detectedStationIds': ['001', 'ABC', '', 123],
      };
      expect(
        ForegroundStationPayload.decodePAlertDetectedStationIds(
          payload,
          now: base,
        ),
        {'001', 'ABC'},
      );
      expect(
        ForegroundStationPayload.decodePAlertDetectedStationIds(
          payload,
          now: base.add(const Duration(seconds: 7)),
        ),
        isEmpty,
      );
      expect(
        ForegroundStationPayload.decodePAlertDetectedStationIds({}, now: base),
        isEmpty,
      );
    },
  );

  test('worker reset and disposal complete pending startup requests', () async {
    final worker = PAlertSourceWorker();
    final result = worker.process([sample(0, 0.02)], {}, now: base);
    worker.reset();
    expect(await result, isNull);
    expect(await worker.process([sample(1, 0.02)], {}, now: base), isEmpty);
    worker.dispose();
    expect(await worker.process([], {}), isNull);
  });

  test(
    'worker carries ordered raw frames and reset cannot reuse old picks',
    () async {
      final worker = PAlertSourceWorker();
      addTearDown(worker.dispose);
      final ids = {for (var i = 0; i < 6; i++) 'TEST-$i'};
      for (var t = 0; t < 8; t++) {
        expect(
          await worker.process(
            [for (var i = 0; i < 6; i++) sample(t, 0.02, index: i)],
            {},
            now: base.add(Duration(seconds: t)),
          ),
          isEmpty,
        );
      }
      final frame = [for (var i = 0; i < 6; i++) sample(8, 2.5, index: i)];
      final events = await worker.process(
        frame,
        ids,
        now: base.add(const Duration(seconds: 8)),
      );
      expect(events, isNotEmpty);
      expect(events!.first.sourceId, 'palert');
      expect(events.first.metadata['palert_max_cwa_intensity_index'], 2);
      worker.reset();
      expect(
        await worker.process(
          frame,
          ids,
          now: base.add(const Duration(seconds: 8)),
        ),
        isEmpty,
      );
    },
  );
}
