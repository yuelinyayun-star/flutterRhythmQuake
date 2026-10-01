import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

import 'support/nied_replay_fixture.dart';
import 'support/nied_station_snapshot_reference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all original GIF frames preserve every captured station field',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!directory.existsSync()) {
        markTestSkipped('Local original Nara GIF capture is required.');
        return;
      }
      final service = LmoniImageService()..start();
      addTearDown(service.stop);
      var frames = 0;
      for (var second = 20; second <= 70; second++) {
        final stamp = DateTime(2026, 6, 10, 18, 1, second);
        final decoded = await decodeNiedGifFile(
          File('${directory.path}/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif'),
        );
        expect(decoded, isNotNull);
        final next = service.stationStream.firstWhere(
          (stations) => stations != null,
        );
        service.processPixels(
          decoded!.packedRgb,
          surfaceGifBytes: decoded.gifBytes,
          dataTime: stamp,
          receivedAt: stamp,
        );
        final stations = (await next)!;
        expect(stations.length, 1630);
        for (final station in stations) {
          final before = stationSnapshotValues(station);
          final snapshot = NiedStation.detachedSnapshot(station);
          expect(
            stationSnapshotValues(snapshot),
            stationSnapshotValues(referenceStationSnapshot(station)),
          );
          expect(stationSnapshotValues(station), before);
          expect(identical(snapshot.recentLevel, station.recentLevel), isFalse);
          expect(
            identical(snapshot.gifObservations, station.gifObservations),
            isFalse,
          );
          expect(
            identical(
              snapshot.gifLayerQualityFlags,
              station.gifLayerQualityFlags,
            ),
            isFalse,
          );
        }
        frames++;
      }
      expect(frames, 51);
    },
  );

  test(
    'snapshot detaches mutable state, preserves timestamps and omits timers',
    () async {
      if (!Directory('tmp/captures/20260610_180130_jst_nara_m36').existsSync()) {
        markTestSkipped('Local original Nara GIF capture is required.');
        return;
      }
      final service = LmoniImageService()..start();
      addTearDown(service.stop);
      final stamp = DateTime(2026, 6, 10, 18, 1, 20);
      final decoded = await decodeNiedGifFile(
        File(
          'tmp/captures/20260610_180130_jst_nara_m36/'
          '${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif',
        ),
      );
      expect(decoded, isNotNull);
      final next = service.stationStream.firstWhere(
        (stations) => stations != null,
      );
      service.processPixels(
        decoded!.packedRgb,
        dataTime: stamp,
        receivedAt: stamp,
      );
      // Controlled copy-isolation boundaries, not a modified earthquake replay.
      final source = referenceStationSnapshot((await next)!.first)
        ..lastUpdate = stamp.toUtc()
        ..lastDataTime = stamp
        ..lastReceivedAt = null
        ..abnormalUpdateCount = 0
        ..detectState = 6
        ..detectReason = 'copy-isolation-boundary';
      source.gifLayerQualityFlags[NiedGifLayer.peakVelocity] = {'missing'};
      source.setActive();
      addTearDown(source.terminate);
      final expected = stationSnapshotValues(referenceStationSnapshot(source));
      final first = NiedStation.detachedSnapshot(source);
      final second = NiedStation.detachedSnapshot(source);
      expect(stationSnapshotValues(first), expected);
      expect(first.activeTimer, isNull);
      expect(source.activeTimer?.isActive, isTrue);

      source.recentLevel.add(-1);
      source.gifObservations.clear();
      source.gifLayerQualityFlags[NiedGifLayer.peakVelocity]!.add('later');
      source.level = -1;
      expect(stationSnapshotValues(first), expected);
      first.recentLevel.clear();
      first.gifObservations.clear();
      first.gifLayerQualityFlags[NiedGifLayer.peakVelocity]!.clear();
      expect(stationSnapshotValues(second), expected);
      expect(source.gifLayerQualityFlags[NiedGifLayer.peakVelocity], {
        'missing',
        'later',
      });
    },
  );
}
