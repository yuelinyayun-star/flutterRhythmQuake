import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_worker.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

import 'support/nied_replay_fixture.dart';

Object? sourceValues(SeismicActiveEvent? event) => event == null
    ? null
    : [
        event.eventId,
        event.stageName,
        event.updatedAt,
        event.maxShindo,
        event.stationRecords.keys.toList(),
        event.metadata['estimate_revision'],
        if (event.estimate case final estimate?)
          [
            estimate.latitude,
            estimate.longitude,
            estimate.depthKm,
            estimate.magnitude,
            estimate.originTime,
            estimate.confidence,
            estimate.supportingStationCount,
            estimate.method,
          ],
      ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reset cancels startup and permits a fresh worker session', () async {
    final worker = NiedSourceEstimationWorker();
    addTearDown(worker.dispose);
    final pending = worker.processStations(const []);
    worker.reset();
    expect(await pending, isNull);
    final result = await worker.processStations(
      const [],
      observedAt: DateTime(2026),
    );
    expect(result, isNotNull);
    expect(result!.event, isNull);
    worker.dispose();
    expect(await worker.processStations(const []), isNull);
  });

  test(
    'raw Nara GIF replay preserves serial inference off UI isolate',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!directory.existsSync()) {
        markTestSkipped('Local original Nara GIF capture is required.');
        return;
      }
      final tracker = StationEventTracker.instance..resetNied();
      NiedReplayLogger.instance.resetForTest();
      final worker = NiedSourceEstimationWorker();
      final driver = NiedSourceEstimationDriver();
      final imageService = LmoniImageService()..start();
      final detector = ShakeDetectionService()..setSensitivity(2);
      addTearDown(() {
        worker.dispose();
        imageService.stop();
        tracker.resetNied();
        NiedReplayLogger.instance.resetForTest(writeToDisk: true);
      });
      var estimates = 0;
      var frameCount = 0;
      var stationCount = 0;
      var maxSyncUs = 0;
      var maxWorkerUs = 0;
      var maxSubmitUs = 0;
      var heartbeatCount = 0;
      var maxWorkerHeartbeatGapUs = 0;
      for (var second = 20; second <= 70; second++) {
        final stamp = DateTime(2026, 6, 10, 18, 1, second);
        final file = File(
          '${directory.path}/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif',
        );
        final decoded = await decodeNiedGifFile(file);
        expect(decoded, isNotNull, reason: file.path);
        final nextStations = imageService.stationStream.firstWhere(
          (value) => value != null,
        );
        imageService.processPixels(
          decoded!.packedRgb,
          surfaceGifBytes: decoded.gifBytes,
          dataTime: stamp,
          receivedAt: stamp,
        );
        final stations = (await nextStations)!;
        stationCount = stations.length;
        detector.setStations(stations);
        detector.processUpdate();
        final syncClock = Stopwatch()..start();
        final detection = driver.processStations(stations, observedAt: stamp);
        syncClock.stop();
        if (syncClock.elapsedMicroseconds > maxSyncUs) {
          maxSyncUs = syncClock.elapsedMicroseconds;
        }
        final expected = sourceValues(tracker.currentNiedEvent.value);
        final heartbeatClock = Stopwatch()..start();
        var lastTick = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
          heartbeatCount++;
          final now = heartbeatClock.elapsedMicroseconds;
          final gap = now - lastTick;
          if (gap > maxWorkerHeartbeatGapUs) maxWorkerHeartbeatGapUs = gap;
          lastTick = now;
        });
        final submitClock = Stopwatch()..start();
        final pending = worker.processStations(stations, observedAt: stamp);
        submitClock.stop();
        if (submitClock.elapsedMicroseconds > maxSubmitUs) {
          maxSubmitUs = submitClock.elapsedMicroseconds;
        }
        final result = await pending;
        timer.cancel();
        expect(result, isNotNull);
        expect(result!.detection.state, detection.state, reason: '$stamp');
        expect(result.detection.memberStationIds, detection.memberStationIds);
        expect(sourceValues(result.event), expected, reason: '$stamp');
        if (result.event?.estimate != null) estimates++;
        if (result.computationMicroseconds > maxWorkerUs) {
          maxWorkerUs = result.computationMicroseconds;
        }
        frameCount++;
      }
      expect(frameCount, 51);
      expect(estimates, greaterThan(0));
      expect(heartbeatCount, greaterThan(0));
      // Timings are measured evidence, not machine-dependent pass thresholds.
      debugPrint(
        'NIED_RAW_REPLAY frames=$frameCount stations=$stationCount estimates=$estimates '
        'maxSyncUs=$maxSyncUs maxWorkerUs=$maxWorkerUs maxSubmitUs=$maxSubmitUs '
        'heartbeatTicks=$heartbeatCount maxHeartbeatGapUs=$maxWorkerHeartbeatGapUs',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
