import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_realtime_pipeline.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_array_observation_processor.dart';
import 'package:flutterrhythmquake/services/sources/whews_nied_station_metadata.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_worker.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_projection.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_worker.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_detector.dart';
import 'package:flutterrhythmquake/services/sources/native_station_summary.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:latlong2/latlong.dart';
import 'nied_source_estimation_worker_test.dart' show sourceValues;
import 'support/nied_replay_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original physical GIF sampling preserves values and missing flags',
    () async {
      final file = File(
        'test/fixtures/nied_worker_20261017/20261003214550.acmap_s.gif',
      );
      final bytes = file.readAsBytesSync();
      final digest = sha256.convert(bytes);
      final pixels = decodeStationImageCpu(bytes)!;
      final image = LmoniImageService()..start();
      List<NiedStation>? stations;
      final sub = image.stationStream.listen((value) => stations = value);
      final time = DateTime(2026, 10, 3, 21, 45, 50);
      List<Object?> values() => [
        for (final s in stations!)
          [
            s.code,
            s.pgaObservation?.colorPosition,
            s.pgaObservation?.pga,
            s.gifLayerQualityFlags[NiedGifLayer.peakAcceleration]?.toList(),
            s.lastDataTime,
            s.lastReceivedAt,
          ],
      ];
      try {
        image.processPhysicalLayerPixels(
          layer: NiedGifLayer.peakAcceleration,
          dataTime: time,
          receivedAt: time,
          surfacePackedRgb: pixels.packedRgb,
        );
        image.publishStations();
        await Future<void>.delayed(Duration.zero);
        final expected = values();
        expect(stations!.where((s) => s.pgaObservation != null), isNotEmpty);
        final sampled = await NiedBackgroundWorker.instance.scanFrame(
          surfaceBytes: bytes,
          configs: image.backgroundScanConfigs,
          configSignature: image.backgroundScanConfigSignature,
          physicalValues: true,
        );
        image.stop();
        image.start();
        image.processPhysicalLayerSamples(
          layer: NiedGifLayer.peakAcceleration,
          dataTime: time,
          receivedAt: time,
          sampled: sampled,
        );
        image.publishStations();
        await Future<void>.delayed(Duration.zero);
        expect(values(), expected);
        // Missing and out-of-order physical layers retain the old policy.
        image.processPhysicalLayerSamples(
          layer: NiedGifLayer.peakAcceleration,
          dataTime: time.subtract(const Duration(seconds: 1)),
          receivedAt: time,
        );
        expect(
          values().where((row) => (row as List)[4] != null),
          expected.where((row) => (row as List)[4] != null),
        );
        image.processPhysicalLayerSamples(
          layer: NiedGifLayer.peakAcceleration,
          dataTime: time,
          receivedAt: time,
        );
        expect(
          stations!.every(
            (s) =>
                s.pgaObservation == null &&
                s.gifLayerQualityFlags[NiedGifLayer.peakAcceleration]!.contains(
                  'layer_missing',
                ),
          ),
          isTrue,
        );
        expect(sha256.convert(file.readAsBytesSync()), digest);
      } finally {
        await sub.cancel();
        image.stop();
        NiedBackgroundWorker.instance.stop();
      }
    },
  );
  test(
    'original 1560-station ingress reaches prepared UI summary with original values',
    () async {
      final metadataBytes = File(
        'test/fixtures/whews_nied/stations.json',
      ).readAsBytesSync();
      final dataBytes = File(
        'test/fixtures/whews_nied/observations.json',
      ).readAsBytesSync();
      final metadata =
          jsonDecode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
      final raw = jsonDecode(utf8.decode(dataBytes)) as Map<String, dynamic>;
      final coordinates = [
        for (final station in metadata['stations'])
          LatLng(
            (station['latitude'] as num).toDouble(),
            (station['longitude'] as num).toDouble(),
          ),
      ];
      final data = raw['Data'];
      final frame = WhewsStationFrame(
        kind: WhewsStationKind.nied,
        dataTime: DateTime.parse(data['timestamp']),
        coordinates: coordinates,
        values: [for (final value in data['shindo']) (value as num).toDouble()],
        pga: [for (final value in data['pga']) (value as num).toDouble()],
        pgv: [for (final value in data['pgv']) (value as num).toDouble()],
        originalJson: {'metadata': metadata, 'data': raw},
      );
      final geo = File(
        'assets/maps/japan_prefectures.geojson',
      ).readAsStringSync(encoding: utf8);
      final pipeline = NiedRealtimePipeline(
        testMode: true,
        testPrefecturesJson: geo,
      );
      final summary = StationSummaryWorker();
      final reference = StationSummaryProjection();
      final processor = NiedArrayObservationProcessor();
      final detection = ShakeDetectionService.forSource('nied');
      NiedPipelineFrame? result;
      pipeline.onFrame = (value) => result = value;
      final errors = <Object>[];
      pipeline.onError = errors.add;
      await loadWhewsNiedPrefectures();
      processor.configure(buildWhewsNiedStations(coordinates));
      final seisjs = <SeisJsStation>[];
      for (var i = 1; i <= 7; i++) {
        final d = jsonDecode(
          File(
            'test/fixtures/source_ws_followup_20261016/seisjs_0$i.original.bytes',
          ).readAsStringSync(encoding: utf8),
        );
        seisjs.add(
          SeisJsStation(
            id: d['type'],
            region: d['region'],
            coordinate: LatLng(
              (d['latitude'] as num).toDouble(),
              (d['longitude'] as num).toDouble(),
            ),
            intensity: (d['Intensity'] as num).toDouble(),
          ),
        );
      }
      try {
        await pipeline.start(
          source: 'whews',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        processor.apply(frame, receivedAt: frame.dataTime);
        detection.setStations(processor.stations);
        detection.processUpdate();
        await pipeline.injectArray(frame, frame.dataTime);
        expect(errors, isEmpty);
        expect(
          result!.stations.map(
            (s) => [
              s.code,
              s.level,
              s.continuousShindo,
              s.pgaObservation?.pga,
              s.pgvObservation?.pgv,
              s.isActive,
            ],
          ),
          processor.stations.map(
            (s) => [
              s.code,
              s.level,
              s.continuousShindo,
              s.pgaObservation?.pga,
              s.pgvObservation?.pgv,
              s.isActive,
            ],
          ),
        );
        expect(result!.original, frame.originalJson);
        expect(result!.historyPreparedByOwner, isFalse);
        final archived = <dynamic>[];
        void record(dynamic value) => archived.add(value);
        final capture = StationHistoryCapture.instance;
        capture.addListener(record);
        try {
          await pipeline.injectArray(frame, frame.dataTime);
          expect(result!.historyPreparedByOwner, isTrue);
          expect(archived, isNotEmpty);
          expect(archived.last.snapshot, result!.history);
          expect(archived.last.originalJson, frame.originalJson);
        } finally {
          capture.removeListener(record);
        }
        await pipeline.injectArray(frame, frame.dataTime);
        expect(result!.historyPreparedByOwner, isFalse);
        final request = StationSummaryRequest(
          nied: result!.stations,
          kma: const [],
          cwa: const [],
          palert: const [],
          seisjs: seisjs,
          snet: const [],
          detection: result!.detection,
          lpgm: null,
          windowEnd: frame.dataTime,
        );
        final expected = reference.project(
          nied: result!.stations,
          kma: const [],
          cwa: const [],
          palert: const [],
          seisjs: seisjs,
          snet: const [],
          detection: result!.detection,
          lpgm: null,
          windowEnd: frame.dataTime,
        );
        final actual = await summary.project(request);
        expect(actual!.processingIsolate, 'station-summary-data-owner');
        expect(actual.niedMaxStation?.code, expected.niedMaxStation?.code);
        expect(actual.niedMaxStation?.level, expected.niedMaxStation?.level);
        expect(actual.seisJsMaxStation?.id, expected.seisJsMaxStation?.id);
        expect(actual.preparedUiSignature, isNotEmpty);
        expect(actual.preparedDetectUiSignature, isNotEmpty);
        final incremental = await summary.project(
          StationSummaryRequest(
            nied: const [],
            kma: const [],
            cwa: const [],
            palert: const [],
            seisjs: seisjs,
            snet: const [],
            detection: result!.detection,
            lpgm: null,
            windowEnd: frame.dataTime,
            changed: const {'seisjs'},
          ),
        );
        expect(incremental!.niedMaxStation?.code, actual.niedMaxStation?.code);
        expect(incremental.niedMaxStation?.level, actual.niedMaxStation?.level);
        final clear = await summary.project(
          StationSummaryRequest(
            nied: const [],
            kma: const [],
            cwa: const [],
            palert: const [],
            seisjs: const [],
            snet: const [],
            detection: result!.detection,
            lpgm: null,
            windowEnd: frame.dataTime,
            changed: const {'seisjs'},
          ),
        );
        expect(clear!.seisJsMaxStation, isNull);
        expect(clear.niedMaxStation?.code, actual.niedMaxStation?.code);
        expect(
          File('test/fixtures/whews_nied/stations.json').readAsBytesSync(),
          metadataBytes,
        );
        expect(
          File('test/fixtures/whews_nied/observations.json').readAsBytesSync(),
          dataBytes,
        );
      } finally {
        pipeline.dispose();
        summary.dispose();
        reference.dispose();
        processor.dispose();
        detection.reset(detachStations: true);
      }
    },
  );
  test(
    'original GIF ingress through KA, detection, archive and UI projection stays off UI',
    () async {
      final originals =
          Directory('test/fixtures/nied_recovery')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.gif'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final image = LmoniImageService()..start();
      final pipeline = NiedRealtimePipeline(testMode: true);
      final detector = ShakeDetectionService.forSource('nied');
      List<NiedStation> reference = const [];
      var referenceDetection = ShakeDetectionService.idleSnapshot;
      NiedPipelineFrame? result;
      NiedPipelineFrame? firstLazyFrame;
      Object? firstExpectedHistory;
      final errors = <Object>[];
      final sub = image.stationStream.listen((stations) {
        if (stations != null) reference = stations;
      });
      detector.onDetectionSnapshotChanged = (snapshot) =>
          referenceDetection = snapshot;
      pipeline.onFrame = (frame) => result = frame;
      pipeline.onError = errors.add;
      try {
        await pipeline.start(
          source: 'lmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        for (final file in originals) {
          final bytes = file.readAsBytesSync();
          final before = sha256.convert(bytes);
          final stamp = RegExp(r'(\d{14})').firstMatch(file.path)!.group(1)!;
          final time = DateTime.parse(
            '${stamp.substring(0, 8)}T${stamp.substring(8)}',
          );
          final received = time.toUtc();
          final scan = await NiedBackgroundWorker.instance.scanFrame(
            surfaceBytes: bytes,
            configs: image.backgroundScanConfigs,
            configSignature: image.backgroundScanConfigSignature,
          );
          image.processSampledFrame(
            scan!,
            surfaceGifBytes: bytes,
            dataTime: time,
            receivedAt: received,
          );
          await Future<void>.delayed(Duration.zero);
          detector.setStations(reference);
          detector.processUpdate();
          await pipeline.injectGif(bytes, time, received);
          expect(errors, isEmpty);
          expect(result, isNotNull);
          expect(result!.processingIsolate, 'nied-realtime-data-owner');
          expect(result!.historyPreparedByOwner, isFalse);
          firstLazyFrame ??= result;
          firstExpectedHistory ??= snapshotSourcePayload(
            ForegroundStationPayload.nied(
              reference,
              source: 'lmoni',
              includeTrackingHistory: false,
            ),
          )['stations'];
          expect(
            result!.stations.map(
              (s) => [
                s.code,
                s.level,
                s.ascend,
                s.activity,
                s.triggerStamp,
                s.isActive,
                s.detectState,
                s.lastDataTime,
                s.lastReceivedAt,
              ],
            ),
            reference.map(
              (s) => [
                s.code,
                s.level,
                s.ascend,
                s.activity,
                s.triggerStamp,
                s.isActive,
                s.detectState,
                s.lastDataTime,
                s.lastReceivedAt,
              ],
            ),
          );
          expect(result!.detection.stage, referenceDetection.stage);
          expect(
            result!.detection.detectedCount,
            referenceDetection.detectedCount,
          );
          expect(
            result!.stations.every(
              (s) => s.activeTimer == null && s.recentLevel.isEmpty,
            ),
            isTrue,
          );
          if (!identical(result, firstLazyFrame)) {
            expect(result!.history['stations'], hasLength(reference.length));
            expect(
              StationHistoryCapture.instance.latest
                  .where((f) => f.kind == 'nied')
                  .last
                  .snapshot,
              result!.history,
            );
          }
          expect(sha256.convert(bytes), before);
        }
        pipeline.stop();
        expect(firstLazyFrame!.history['stations'], firstExpectedHistory);
        final saved = result;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(result, same(saved));
      } finally {
        pipeline.dispose();
        await sub.cancel();
        image.stop();
        detector.reset(detachStations: true);
        NiedBackgroundWorker.instance.stop();
      }
    },
  );
  test(
    'original 51-frame Nara inference reaches UI and owners release on source changes',
    () async {
      final directory = Directory('tmp/captures/20260610_180130_jst_nara_m36');
      if (!directory.existsSync()) {
        markTestSkipped('Local original Nara GIF capture is required.');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final baselineHistory = NativeKaHistorySession.diagnostics['kaSessions'];
      final baselineDetector =
          NativeKaDetector.diagnostics['kaDetectorSessions'];
      final baselineSummary = NativeStationSummary.diagnostics['sessions'];
      final pipeline = NiedRealtimePipeline(testMode: true);
      final summary = StationSummaryWorker();
      final image = LmoniImageService()..start();
      final detector = ShakeDetectionService.forSource('nied')
        ..setSensitivity(2);
      final driver = NiedSourceEstimationDriver();
      final tracker = StationEventTracker.instance..resetNied();
      NiedSourceEstimationResult? actual;
      NiedPipelineFrame? frame;
      final errors = <Object>[];
      pipeline.onFrame = (value) => frame = value;
      pipeline.onEstimate = (value) => actual = value;
      pipeline.onError = errors.add;
      var estimates = 0;
      var maxSerialUs = 0, maxSubmitUs = 0, maxUiGapUs = 0, ticks = 0;
      try {
        await pipeline.start(
          source: 'lmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: true,
        );
        for (var second = 20; second <= 70; second++) {
          final stamp = DateTime(2026, 6, 10, 18, 1, second);
          final file = File(
            '${directory.path}/${formatNiedTimeKey(stamp)}.lmoni.jma_s.gif',
          );
          final decoded = (await decodeNiedGifFile(file))!;
          final serialClock = Stopwatch()..start();
          final next = image.stationStream.firstWhere((value) => value != null);
          image.processPixels(
            decoded.packedRgb,
            surfaceGifBytes: decoded.gifBytes,
            dataTime: stamp,
            receivedAt: stamp,
          );
          final stations = (await next)!;
          detector.setStations(stations);
          detector.processUpdate();
          final detection = driver.processStations(stations, observedAt: stamp);
          if (serialClock.elapsedMicroseconds > maxSerialUs) {
            maxSerialUs = serialClock.elapsedMicroseconds;
          }
          final expected = sourceValues(tracker.currentNiedEvent.value);
          actual = null;
          final uiClock = Stopwatch()..start();
          var lastTickUs = 0;
          final heartbeat = Timer.periodic(const Duration(milliseconds: 8), (
            _,
          ) {
            final now = uiClock.elapsedMicroseconds;
            final gap = now - lastTickUs;
            if (gap > maxUiGapUs) maxUiGapUs = gap;
            lastTickUs = now;
            ticks++;
          });
          addTearDown(heartbeat.cancel);
          final submitClock = Stopwatch()..start();
          final pendingFrame = pipeline.injectGif(
            decoded.gifBytes,
            stamp,
            stamp,
          );
          if (submitClock.elapsedMicroseconds > maxSubmitUs) {
            maxSubmitUs = submitClock.elapsedMicroseconds;
          }
          await pendingFrame;
          expect(errors, isEmpty);
          expect(
            frame!.stations.map(
              (s) => [
                s.code,
                s.level,
                s.continuousShindo,
                s.ascend,
                s.activity,
                s.triggerStamp,
                s.isActive,
                s.detectState,
                s.gifLayerQualityFlags,
                s.lastDataTime,
              ],
            ),
            stations.map(
              (s) => [
                s.code,
                s.level,
                s.continuousShindo,
                s.ascend,
                s.activity,
                s.triggerStamp,
                s.isActive,
                s.detectState,
                s.gifLayerQualityFlags,
                s.lastDataTime,
              ],
            ),
            reason: '$stamp stations',
          );
          expect(actual, isNotNull, reason: '$stamp');
          expect(actual!.detection.state, detection.state);
          expect(sourceValues(actual!.event), expected, reason: '$stamp');
          expect(
            actual!.event?.stationRecords.values.every(
                  (record) => record.observationHistory.frames.isEmpty,
                ) ??
                true,
            isTrue,
          );
          if (actual!.event?.estimate != null) estimates++;
          final ui = await summary.project(
            StationSummaryRequest(
              nied: frame!.stations,
              kma: const [],
              cwa: const [],
              palert: const [],
              seisjs: const [],
              snet: const [],
              detection: frame!.detection,
              lpgm: null,
              windowEnd: stamp,
            ),
          );
          expect(ui!.processingIsolate, 'station-summary-data-owner');
          final tailGap = uiClock.elapsedMicroseconds - lastTickUs;
          if (tailGap > maxUiGapUs) maxUiGapUs = tailGap;
          heartbeat.cancel();
        }
        expect(estimates, greaterThan(0));
        stdout.writeln(
          'NIED_PIPELINE originalFrames=51 stations=1634 estimates=$estimates '
          'maxSerialTurnUs=$maxSerialUs maxSubmitUs=$maxSubmitUs '
          'heartbeat8msTicks=$ticks maxUiGapUs=$maxUiGapUs',
        );
        pipeline.stop();
        final saved = frame;
        await pipeline.start(
          source: 'kmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        final file = File('${directory.path}/20260610180120.lmoni.jma_s.gif');
        final stamp = DateTime(2026, 6, 10, 18, 1, 20);
        await pipeline.injectGif(file.readAsBytesSync(), stamp, stamp);
        expect(frame!.source, 'kmoni');
        expect(identical(frame, saved), isFalse);
        pipeline.stop();
        final pending = pipeline.start(
          source: 'lmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        pipeline.stop();
        await pending;
      } finally {
        pipeline.dispose();
        summary.dispose();
        driver.dispose();
        image.stop();
        detector.reset(detachStations: true);
        tracker.resetNied();
        NiedBackgroundWorker.instance.stop();
      }
      for (var i = 0; i < 100; i++) {
        if (NativeKaHistorySession.diagnostics['kaSessions'] ==
                baselineHistory &&
            NativeKaDetector.diagnostics['kaDetectorSessions'] ==
                baselineDetector &&
            NativeStationSummary.diagnostics['sessions'] == baselineSummary) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(NativeKaHistorySession.diagnostics['kaSessions'], baselineHistory);
      expect(
        NativeKaDetector.diagnostics['kaDetectorSessions'],
        baselineDetector,
      );
      expect(NativeStationSummary.diagnostics['sessions'], baselineSummary);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
