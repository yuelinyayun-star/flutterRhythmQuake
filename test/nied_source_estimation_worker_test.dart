import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/nied_replay_logger.dart';
import 'package:flutterrhythmquake/core/event_detection/robust_station_trigger_detector.dart';
import 'package:flutterrhythmquake/core/event_detection/native_station_trigger_detector.dart';
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
      // Freeze the pre-migration Dart detector as the serial reference.
      final driver = NiedSourceEstimationDriver(
        stationTriggerDetector: RobustStationTriggerDetector(),
      );
      final imageService = LmoniImageService()..start();
      final detector = ShakeDetectionService()..setSensitivity(2);
      addTearDown(() {
        worker.dispose();
        driver.dispose();
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
      final frameMeasurements = <Map<String, Object?>>[];
      // Hold timers use wall time. Pace original observations when comparing
      // whole histories across implementations with different processing speed.
      final paced = Platform.environment['RQ_NIED_REALTIME_REPLAY'] == 'true';
      final replayClock = Stopwatch()..start();
      for (var second = 20; second <= 70; second++) {
        if (paced) {
          final remaining = Duration(seconds: frameCount) - replayClock.elapsed;
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        }
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
        frameMeasurements.add({
          'stamp': stamp.toIso8601String(),
          'syncUs': syncClock.elapsedMicroseconds,
          'workerUs': result.computationMicroseconds,
          'submitUs': submitClock.elapsedMicroseconds,
          'rssBytes': ProcessInfo.currentRss,
          'result': jsonDecode(
            jsonEncode(
              expected,
              toEncodable: (value) => value is DateTime
                  ? value.toIso8601String()
                  : value.toString(),
            ),
          ),
        });
        frameCount++;
      }
      expect(frameCount, 51);
      expect(estimates, greaterThan(0));
      expect(heartbeatCount, greaterThan(0));
      final measurementsPath = Platform.environment['RQ_NIED_MEASUREMENTS'];
      if (measurementsPath != null) {
        final event = tracker.currentNiedEvent.value;
        final flags = HashSet<Set<String>>.identity();
        final physicalMaps = HashSet<Object>.identity();
        final observations = <Object?>[];
        for (final record
            in event?.stationRecords.values ??
                const <SeismicStationEventRecord>[]) {
          for (final frame in record.observationHistory.frames) {
            flags.add(frame.qualityFlags);
            physicalMaps.add(frame.physicalObservations);
            observations.add([
              record.descriptor.code,
              frame.dataTime.toIso8601String(),
              frame.receivedAt.toIso8601String(),
              frame.value,
              frame.rawLevel,
              frame.detectLevel,
              frame.isTriggered,
              frame.qualityFlags.toList()..sort(),
              frame.physicalObservations.length,
            ]);
          }
        }
        await File(measurementsPath).writeAsString(
          jsonEncode({
            'frames': frameMeasurements,
            'stationCount': stationCount,
            'realTimePaced': paced,
            'maxRssBytes': ProcessInfo.maxRss,
            'retainedObservationCount': observations.length,
            'retainedQualityFlagSets': flags.length,
            'retainedPhysicalMaps': physicalMaps.length,
            'observationsSha256': sha256
                .convert(utf8.encode(jsonEncode(observations)))
                .toString(),
          }),
        );
        await File(
          '$measurementsPath.observations.json.gz',
        ).writeAsBytes(gzip.encode(utf8.encode(jsonEncode(observations))));
      }
      // Timings are measured evidence, not machine-dependent pass thresholds.
      debugPrint(
        'NIED_RAW_REPLAY frames=$frameCount stations=$stationCount estimates=$estimates '
        'maxSyncUs=$maxSyncUs maxWorkerUs=$maxWorkerUs maxSubmitUs=$maxSubmitUs '
        'heartbeatTicks=$heartbeatCount maxHeartbeatGapUs=$maxWorkerHeartbeatGapUs',
      );
      // The serial reference owns a native KA session too. Close both sides
      // before asserting process-wide allocation counters, not just the worker.
      driver.dispose();
      tracker.resetNied();
      detector.reset(detachStations: true);
      imageService.stop();
      worker.dispose();
      if (NativeStationTriggerDetector.supported) {
        for (var attempt = 0; attempt < 100; attempt++) {
          if (NativeStationTriggerDetector
                  .globalDiagnostics['triggerSessions'] ==
              0) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(
          NativeStationTriggerDetector.globalDiagnostics['triggerSessions'],
          0,
        );
        expect(
          NativeStationTriggerDetector.globalDiagnostics['rustCurrentBytes'],
          0,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
