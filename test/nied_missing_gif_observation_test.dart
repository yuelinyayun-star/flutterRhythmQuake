import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_realtime_pipeline.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_station_frame.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';
import 'package:image/image.dart' as image;

// The same unchanged original 20261102 GIFs used to diagnose the regression.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory(
    Platform.environment['NIED_DIAGNOSTIC_CAPTURE'] ??
        'tmp/captures/nied_false_detection_20261102_111827_jst_lmoni',
  );
  test(
    'original missing pixels stay missing through Rust sampling, KA, detection and display transport',
    () async {
      final manifest = jsonDecode(
        File('${dir.path}/capture_manifest.json').readAsStringSync(),
      );
      final originals = (manifest['records'] as List)
          .cast<Map<String, dynamic>>();
      for (final r in originals) {
        expect(
          sha256
              .convert(File('${dir.path}/${r['file']}').readAsBytesSync())
              .toString(),
          r['sha256'],
        );
      }
      final records = originals.where((r) => r['layer'] == 'jma_s').toList();
      final before = NativeNiedDetectionOwner.diagnostics;
      final kaBefore = NativeKaHistorySession.diagnostics['kaSessions'];
      final runs = <Object>[];
      var exactValidComparisons = 0, missingComparisons = 0;
      for (final sensitivity in [1, 2, 3]) {
        final service = LmoniImageService()..start();
        final encoder = NiedSourceStationEncoder();
        final displayDecoder = NiedSourceStationDecoder();
        NativeNiedDetectionOwner? owner;
        List<NiedStation>? previous;
        List<dynamic>? view;
        final frames = <Map<String, dynamic>>[];
        final start = DateTime.parse(records.first['observedAt']);
        try {
          for (final r in records) {
            final bytes = File('${dir.path}/${r['file']}').readAsBytesSync();
            final time = DateTime.parse(r['observedAt']);
            final clock = time.difference(start).inMilliseconds;
            owner?.tick(clock);
            if (previous != null) owner?.rebind(previous);
            final scan = await NiedBackgroundWorker.instance.scanFrame(
              surfaceBytes: bytes,
              configs: service.backgroundScanConfigs,
              configSignature: service.backgroundScanConfigSignature,
            );
            expect(scan?.backend, 'rust-abi-1');
            if (sensitivity == 2) {
              final raw = image.decodeImage(bytes)!;
              for (var i = 0; i < scan!.samples.length; i++) {
                final xy = service.backgroundScanConfigs[i];
                final pixel = raw.getPixel(xy.pixelX, xy.pixelY);
                final sample = scan.samples[i];
                if (pixel.a == 0) {
                  expect(sample.surfacePosition, isNull);
                  expect(sample.surfaceShindo, isNull);
                  expect(sample.missingReason, 'pixel_transparent');
                  missingComparisons++;
                } else {
                  final a = pixel.a.toInt();
                  final red = (pixel.r.toInt() * a + 127) ~/ 255;
                  final green = (pixel.g.toInt() * a + 127) ~/ 255;
                  final blue = (pixel.b.toInt() * a + 127) ~/ 255;
                  final oldShindo = ShindoColorUtil.rgbaToShindo(
                    red,
                    green,
                    blue,
                  );
                  final oldPosition = oldShindo == null
                      ? null
                      : ShindoColorUtil.rgbaToPosition(red, green, blue);
                  expect(
                    sample.surfacePosition,
                    oldPosition,
                    reason: '${r['file']} pixel ${xy.pixelX},${xy.pixelY}',
                  );
                  if (oldPosition == null) {
                    expect(sample.surfaceShindo, oldShindo);
                  }
                  exactValidComparisons++;
                }
              }
            }
            final ready = service.stationStream.firstWhere((v) => v != null);
            service.processSampledFrame(
              scan!,
              surfaceGifBytes: bytes,
              dataTime: time,
              receivedAt: DateTime.now(),
            );
            final stations = (await ready)!;
            previous = stations;
            owner ??= NativeNiedDetectionOwner(
              stations,
              manualClock: true,
              onUpdate: (result) {
                if (result[2] != null) view = result[2];
              },
            );
            owner.process(stations, sensitivity, clock: clock);
            owner.rebind(stations);
            final display = displayDecoder.apply(encoder.capture(stations));
            for (var i = 0; i < stations.length; i++) {
              expect(
                display[i].isRealtimeObservationMissing,
                stations[i].isRealtimeObservationMissing,
              );
              expect(display[i].level, stations[i].level);
            }
            final toyama = stations.firstWhere((s) => s.code == 'TYM002');
            if (r['file'] == '20261102111601.jma_s.gif') {
              expect(toyama.gifObservation, isNull);
              expect(toyama.recentKaLevel.first, -1);
              expect(
                toyama.level,
                3,
                reason: 'existing short missing hold, not invented level 0',
              );
              expect(toyama.isRealtimeObservationMissing, isTrue);
            }
            if (r['file'] == '20261102111602.jma_s.gif') {
              expect(
                toyama.ascend,
                0,
                reason:
                    'identical valid pixel restored after missing cannot become 3->0->3',
              );
              expect(toyama.isRealtimeObservationMissing, isFalse);
            }
            frames.add({
              'timeJst': r['observedAt'],
              'stage': view?[0],
              'weak': view?[1],
              'detected': view?[2],
              'strong': view?[3],
              'grids': (view?[6] as List?)?.length ?? 0,
              'missingStations': stations
                  .where((s) => s.isRealtimeObservationMissing)
                  .length,
              'toyama': {
                'level': toyama.level,
                'ascend': toyama.ascend,
                'activity': toyama.activity,
                'shindo': toyama.gifObservation?.shindo,
                'missing': toyama.isRealtimeObservationMissing,
              },
            });
          }
        } finally {
          owner?.dispose();
          service.stop();
          NiedBackgroundWorker.instance.stop();
        }
        final target = frames.firstWhere(
          (v) => v['timeJst'] == '2026-11-02T11:18:26+09:00',
        );
        // ignore: avoid_print
        print('FIXED_NIED sensitivity=$sensitivity ${jsonEncode(target)}');
        runs.add({'sensitivity': sensitivity, 'frames': frames});
      }
      expect(missingComparisons, greaterThan(0));
      expect(exactValidComparisons, greaterThan(0));
      expect(
        NativeNiedDetectionOwner.diagnostics['sessions'],
        before['sessions'],
      );
      expect(
        NativeNiedDetectionOwner.diagnostics['workers'],
        before['workers'],
      );
      expect(NativeKaHistorySession.diagnostics['kaSessions'], kaBefore);
      File(
        '${dir.path}/missing-fixed-native-diagnostic.json',
      ).writeAsStringSync(
        jsonEncode({
          'runs': runs,
          'originalFilesVerified': originals.length,
          'exactValidComparisons': exactValidComparisons,
          'transparentMissingComparisons': missingComparisons,
          'ownersReleased': true,
          'historicalReceivedAt': null,
        }),
      );
    },
    skip: !NativeNiedDetectionOwner.supported || !dir.existsSync(),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'fixed original one-second GIF production ingress has no missing-pixel detection and carries gray refresh state',
    () async {
      final manifest = jsonDecode(
        File('${dir.path}/capture_manifest.json').readAsStringSync(),
      );
      final records = (manifest['records'] as List)
          .cast<Map<String, dynamic>>()
          .where((r) => r['layer'] == 'jma_s')
          .toList();
      final baseline = NativeNiedDetectionOwner.diagnostics;
      final kaBefore = NativeKaHistorySession.diagnostics['kaSessions'];
      final pipeline = NiedRealtimePipeline(testMode: true);
      final errors = <Object>[];
      final rows = <Object>[];
      final watch = Stopwatch();
      NiedPipelineFrame? latest;
      pipeline.onFrame = (v) => latest = v;
      pipeline.onError = errors.add;
      try {
        await pipeline.start(
          source: 'lmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        watch.start();
        for (var i = 0; i < records.length; i++) {
          final remaining = i * 1000 - watch.elapsedMilliseconds;
          if (remaining > 0) {
            await Future<void>.delayed(Duration(milliseconds: remaining));
          }
          final r = records[i];
          final time = DateTime.parse(r['observedAt']);
          final bytes = File('${dir.path}/${r['file']}').readAsBytesSync();
          expect(sha256.convert(bytes).toString(), r['sha256']);
          await pipeline.injectGif(bytes, time, DateTime.now());
          expect(errors, isEmpty);
          expect(latest?.dataTime, time);
          final frame = latest!;
          expect(frame.detection.weakCount, 0, reason: r['file']);
          expect(frame.detection.detectedCount, 0, reason: r['file']);
          expect(frame.detection.strongCount, 0, reason: r['file']);
          expect(frame.detection.gridCells, isEmpty, reason: r['file']);
          final toyama = frame.stations.firstWhere((s) => s.code == 'TYM002');
          if (i == 1) {
            expect(toyama.level, 3);
            expect(toyama.isRealtimeObservationMissing, isTrue);
            expect(frame.layerSignature, contains('|${toyama.id}:3:0:missing'));
          }
          if (i == 2) {
            expect(toyama.isRealtimeObservationMissing, isFalse);
            expect(toyama.ascend, 0);
            expect(
              frame.layerSignature,
              isNot(contains('|${toyama.id}:3:0:missing')),
            );
          }
          rows.add({
            'timeJst': r['observedAt'],
            'stage': frame.detection.stage.name,
            'missing': frame.stations
                .where((s) => s.isRealtimeObservationMissing)
                .length,
            'weak': frame.detection.weakCount,
            'grids': frame.detection.gridCells.length,
            'elapsedMs': watch.elapsedMilliseconds,
          });
          if (i % 30 == 0 || i == 146) {
            // ignore: avoid_print
            print(
              'FIXED_PRODUCTION ${r['observedAt']} weak=${frame.detection.weakCount} grids=${frame.detection.gridCells.length}',
            );
          }
        }
      } finally {
        pipeline.dispose();
      }
      for (
        var i = 0;
        i < 100 &&
            NativeNiedDetectionOwner.diagnostics['sessions'] !=
                baseline['sessions'];
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        NativeNiedDetectionOwner.diagnostics['sessions'],
        baseline['sessions'],
      );
      expect(
        NativeNiedDetectionOwner.diagnostics['workers'],
        baseline['workers'],
      );
      expect(NativeKaHistorySession.diagnostics['kaSessions'], kaBefore);
      File(
        '${dir.path}/missing-fixed-production-ingress.json',
      ).writeAsStringSync(
        jsonEncode({
          'frames': rows,
          'ownersReleased': true,
          'originalCadenceSeconds': 1,
          'historicalReceivedAt': null,
          'testReceivedAt':
              'actual test ingestion time, not historical receive time',
        }),
      );
    },
    skip:
        !NativeNiedDetectionOwner.supported ||
        !dir.existsSync() ||
        Platform.environment['NIED_VERIFY_REALTIME'] != 'true',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
