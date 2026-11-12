import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_detection.dart';
import 'package:flutterrhythmquake/services/sources/native_http_client.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_projection.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'support/palert_level_history_before_20261015.dart';

Future<void> until(bool Function() predicate, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('P-Alert native response timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

List<StationHistoryFrame> earthquakeFrames() {
  const root = 'test/fixtures/palert_cwa_1150077_20261017';
  final manifest =
      jsonDecode(File('$root/manifest.json').readAsStringSync()) as List;
  final frames = <StationHistoryFrame>[];
  for (final entry in manifest) {
    final stored = jsonDecode(
      File('$root/${entry['file']}').readAsStringSync(),
    );
    frames.addAll(
      StationJsonArchive.decode(StationArchiveStorage.decode(stored['value'])),
    );
  }
  return frames..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original earthquake archive matches levels, confirmed detection and retained JSON',
    () async {
      final frames = earthquakeFrames();
      final native = NativeStationRuntime();
      final referenceClock = FakeAsync();
      late Zone referenceZone;
      late PAlertDetector detector;
      final expectedSignals = <int>[], nativeSignals = <int>[];
      final gate = PAlertDetectionGate();
      referenceClock.run((_) {
        referenceZone = Zone.current;
        detector = PAlertDetector();
        detector.onCwaIntensityChanged = (value) {
          final signal = gate.update(value);
          if (signal == PAlertDetectionSignal.expired) expectedSignals.add(-1);
          if (signal == PAlertDetectionSignal.detected) {
            expectedSignals.add(value);
          }
        };
      });
      final history = DartPAlertLevelHistoryReference();
      Map<String, dynamic>? latest;
      native.onFrame = (f) {
        latest = f;
        nativeSignals.addAll((f['signals'] as List).cast<int>());
      };
      native.start({'kind': 'palert', 'testing': true});
      try {
        await until(() => latest != null);
        final metadata = frames.first.originalJson!['metadata'] as Map;
        native.injectOriginal(
          utf8.encode(jsonEncode(metadata)),
          frames.first.receivedAt,
        );
        await until(() => (latest!['stations'] as List).isNotEmpty);
        final stations = ForegroundStationPayload.decodePAlert(
          latest!['stations'],
        );
        final ids = [for (final s in stations) s.id];
        history.setStations(ids);
        final held = <String, int?>{for (final id in ids) id: null};
        var count = 0, active = 0;
        DateTime? previousReceived;
        for (final saved in frames) {
          final raw = saved.originalJson!['data'] as Map;
          final stamp = PAlertService.parseTimestamp(
            raw['data']['pga']['timestamp'],
          )!;
          if (latest!['dataTime'] == stamp.toIso8601String()) continue;
          native.injectOriginal(utf8.encode(jsonEncode(raw)), saved.receivedAt);
          await until(() => latest!['frames'] == count + 1);
          count++;
          final a = raw['data']['pga'], b = raw['data']['pgv'];
          final expected = history.process(
            stamp,
            Map<String, double>.from(a['dataVals']),
            a['timestamp'] == b['timestamp']
                ? Map<String, double>.from(b['dataVals'])
                : const {},
          );
          final rows = latest!['stations'] as List;
          for (var i = 0; i < ids.length; i++) {
            if (a['dataVals'][ids[i]] != null) {
              held[ids[i]] = expected[i * 2 + 1];
            }
          }
          expect(
            [for (final row in rows) row['heldLevel']],
            [for (final id in ids) held[id]],
            reason: 'held frame $count',
          );
          final views = ForegroundStationPayload.decodePAlert(rows);
          if (previousReceived != null) {
            referenceClock.elapse(
              saved.receivedAt.difference(previousReceived),
            );
          }
          previousReceived = saved.receivedAt;
          referenceZone.run(
            () => detector.update(views, now: saved.receivedAt),
          );
          expect(
            latest!['detectedStationIds'],
            detector.snapshot.detectedStations.map((s) => s.code).toList(),
            reason: 'detected frame $count',
          );
          expect(
            latest!['detection']['maxShindo'],
            detector.snapshot.maxShindo,
            reason: 'max frame $count',
          );
          if ((latest!['detectedStationIds'] as List).isNotEmpty) active++;
          expect(native.original!['data'], raw);
          expect(
            nativeSignals,
            expectedSignals,
            reason: 'voice effect frame $count',
          );
          final expectedGrids =
              [
                for (final cell in detector.snapshot.gridCells.values)
                  [cell.center.latitude, cell.center.longitude, cell.level],
              ]..sort(
                (a, b) =>
                    a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]),
              );
          final grids =
              [
                for (final row in latest!['detectionGrid'] as List)
                  (row as List).cast<num>(),
              ]..sort(
                (a, b) =>
                    a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]),
              );
          expect(grids, expectedGrids, reason: 'map cells frame $count');
        }
        expect(active, greaterThan(0));
        debugPrint(
          'NATIVE_PALERT originalFrames=$count activeFrames=$active stations=${ids.length}',
        );
      } finally {
        native.stop();
        referenceZone.run(detector.dispose);
        await until(() => NativeStationRuntime.workers == 0);
      }
    },
    skip: !NativeStationRuntime.supported,
  );

  test(
    'production bridge carries prepared stations, effects and lazy original archive',
    () async {
      final service = PAlertService.nativeForTesting(
        settings: {'testing': true},
      );
      var updates = 0;
      final captured = <StationHistoryFrame>[];
      void capture(StationHistoryFrame frame) {
        if (frame.kind == 'palert') captured.add(frame);
      }

      StationHistoryCapture.instance.addListener(capture);
      addTearDown(() => StationHistoryCapture.instance.removeListener(capture));
      final legacyProjection = StationSummaryProjection(),
          preparedProjection = StationSummaryProjection();
      final subscription = service.stationStream.listen((_) {
        updates++;
      });
      try {
        service.start();
        await until(() => service.nativeSummary != null);
        final saved = earthquakeFrames();
        service.handleOriginalForTesting(
          utf8.encode(jsonEncode(saved.first.originalJson!['metadata'])),
          saved.first.receivedAt,
        );
        await until(() => service.stations.length == 787);
        var count = 0;
        for (final f in saved) {
          final time = PAlertService.parseTimestamp(
            f.originalJson!['data']['data']['pga']['timestamp'],
          )!;
          if (service.dataTimeNotifier.value == time) continue;
          service.handleOriginalForTesting(
            utf8.encode(jsonEncode(f.originalJson!['data'])),
            f.receivedAt,
          );
          count++;
          await until(() => service.nativeFrameCount == count);
          expect(captured.last.originalJson!['data'], f.originalJson!['data']);
          expect(captured.last.snapshot['stations'], isNotEmpty);
          // The direct native archive writer must preserve every station field
          // consumed by replay, independently of the live numeric UI message.
          List<Object?> values(PAlertStation s) => [
            s.id,
            s.network,
            s.name,
            s.area,
            s.coordinate.latitude,
            s.coordinate.longitude,
            s.pgaGal,
            s.pgvCms,
            s.cwaIntensityIndex,
            s.heldCwaIntensityIndex,
            s.heldLevel,
            s.sampledLevel ?? -1,
            s.dataTime?.millisecondsSinceEpoch,
            s.receivedAt?.millisecondsSinceEpoch,
          ];
          expect(
            ForegroundStationPayload.decodePAlert(
              captured.last.snapshot['stations'],
            ).map(values).toList(),
            service.stations.map(values).toList(),
            reason: 'archive and live station values frame $count',
          );
          expect(
            captured.last.snapshot['detectedStationIds'],
            service.detectionSnapshot.detectedStations
                .map((s) => s.code)
                .toList(),
          );
          expect(service.processingIsolateName, 'rust-palert-runtime');
          expect(
            service.stations.every(
              (s) => s.sampledLevel != null || s.dataTime == null,
            ),
            isTrue,
          );
          expect(
            service.historySnapshot(
              includeOriginalJson: true,
            )['originalJson']['data'],
            f.originalJson!['data'],
          );
          dynamic project(StationSummaryProjection p, bool prepared) =>
              p.project(
                nied: [],
                kma: [],
                cwa: [],
                palert: prepared ? [] : service.stations,
                palertSummary: prepared ? service.nativeSummary : null,
                seisjs: [],
                snet: [],
                detection: ShakeDetectionService.idleSnapshot,
                lpgm: null,
                windowEnd: f.receivedAt,
              );
          expect(
            project(preparedProjection, true).pAlertMaxStation?.id,
            project(legacyProjection, false).pAlertMaxStation?.id,
            reason: 'sidebar frame $count',
          );
        }
        expect(service.nativeLayerSignature, isNotEmpty);
        expect(updates, greaterThan(1));
        expect(
          ForegroundStationPayload.decodePAlert(
            service.historySnapshot()['stations'],
          ).every((s) => s.preparedMapRecent == null),
          isTrue,
          reason: 'historical playback uses its own observation clock',
        );
        final countBefore = service.nativeFrameCount;
        service.handleOriginalForTesting(
          utf8.encode(jsonEncode(saved.last.originalJson!['data'])),
          saved.last.receivedAt.add(const Duration(seconds: 7)),
        );
        await until(() => service.nativeStatus == 'error');
        expect(service.nativeFrameCount, countBefore);
        expect(service.detectionSnapshot.detectedStations, isEmpty);
        expect(service.nativeGrids, isEmpty);
      } finally {
        legacyProjection.dispose();
        preparedProjection.dispose();
        service.stop();
        await subscription.cancel();
        await until(() => NativeStationRuntime.workers == 0);
      }
    },
    skip: !NativeStationRuntime.supported,
  );

  test(
    'official P-Alert connection uses native HTTP and releases its owner',
    () async {
      final service = PAlertService.nativeForTesting();
      try {
        service.start();
        try {
          await until(() => service.nativeFrameCount >= 2, seconds: 30);
        } finally {
          debugPrint(
            'P-Alert live status=${service.nativeStatus} stations=${service.stations.length} frames=${service.nativeFrameCount} error=${service.nativeError}',
          );
        }
        expect(service.nativeStatus, 'connected');
        expect(service.stations, isNotEmpty);
        final raw = service.historySnapshot(includeOriginalJson: true);
        File(
          'tmp/native_palert_runtime_20261017/live-original.json',
        ).writeAsStringSync(jsonEncode(raw['originalJson']));
        debugPrint(
          'NATIVE_PALERT_LIVE stations=${service.stations.length} frames=${service.nativeFrameCount} dataTime=${service.dataTimeNotifier.value}',
        );
      } finally {
        service.stop();
        await until(() => NativeStationRuntime.workers == 0);
      }
    },
    skip: Platform.environment['RQ_PALERT_LIVE'] != '1',
    timeout: const Timeout(Duration(seconds: 35)),
  );

  test(
    'native HTTP retries invalid metadata, retains original bytes and clears on failure',
    () async {
      final frames = earthquakeFrames();
      final metadata = frames.first.originalJson!['metadata'];
      var metadataRequests = 0, frameIndex = 0;
      var failing = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        if (body['query'].toString().contains('stationList')) {
          metadataRequests++;
          if (metadataRequests == 1) {
            request.response.add(utf8.encode('invalid JSON transport fixture'));
          } else {
            request.response.add(utf8.encode(jsonEncode(metadata)));
          }
        } else if (failing) {
          request.response.statusCode = 503;
        } else {
          request.response.add(
            utf8.encode(jsonEncode(frames[frameIndex].originalJson!['data'])),
          );
        }
        await request.response.close();
      });
      final service = PAlertService.nativeForTesting(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/graphql/'),
        pollInterval: const Duration(milliseconds: 40),
      );
      try {
        service.start();
        await until(() => service.nativeFrameCount == 1);
        expect(metadataRequests, 2);
        final next = frames.indexWhere(
          (f) =>
              PAlertService.parseTimestamp(
                f.originalJson!['data']['data']['pga']['timestamp'],
              ) !=
              service.dataTimeNotifier.value,
        );
        frameIndex = next;
        await until(() => service.nativeFrameCount == 2);
        expect(
          service.historySnapshot(
            includeOriginalJson: true,
          )['originalJson']['data'],
          frames[next].originalJson!['data'],
        );
        failing = true;
        await until(() => service.nativeStatus == 'error');
        expect(service.detectionSnapshot.detectedStations, isEmpty);
        expect(service.nativeError, contains('503'));
        expect(metadataRequests, 2);
      } finally {
        service.stop();
        await subscription.cancel();
        await server.close(force: true);
        await until(
          () =>
              NativeStationRuntime.workers == 0 &&
              NativeHttpClient.activeClients == 0 &&
              NativeHttpClient.activeRequests == 0,
        );
      }
    },
    skip: !NativeStationRuntime.supported,
  );
}
