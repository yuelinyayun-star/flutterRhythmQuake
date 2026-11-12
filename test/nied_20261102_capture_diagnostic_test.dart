import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_history.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/nied_realtime_pipeline.dart';
import 'support/shake_detection_before_20261019.dart' as frozen;

// Historical original GIF evidence. No production rules or input values change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '20261102 original frames through native KA and detection owners',
    () async {
      final dir = Directory(
        Platform.environment['NIED_DIAGNOSTIC_CAPTURE'] ??
            'tmp/captures/nied_false_detection_20261102_111827_jst',
      );
      final manifest = jsonDecode(
        File('${dir.path}/capture_manifest.json').readAsStringSync(),
      );
      final records = (manifest['records'] as List)
          .cast<Map<String, dynamic>>();
      for (final record in records) {
        final bytes = File('${dir.path}/${record['file']}').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), record['sha256']);
      }
      final surface = records.where((r) => r['layer'] == 'jma_s').toList();
      final baseline = NativeNiedDetectionOwner.diagnostics;
      final kaBefore = NativeKaHistorySession.diagnostics['kaSessions'];
      final report = <String, dynamic>{
        'input': '${dir.path}/capture_manifest.json',
        'allOriginalFilesVerified': records.length,
        'historicalReceivedAt': null,
        'clock':
            'monotonic milliseconds derived from original observedAt deltas; test receive time is not historical receive time',
        'runs': <Object>[],
      };
      for (final sensitivity in [1, 2, 3]) {
        final image = LmoniImageService()
          ..useNativeKaHistory =
              Platform.environment['NIED_DIAGNOSTIC_DART_HISTORY'] != 'true'
          ..start();
        NativeNiedDetectionOwner? owner;
        List<NiedStation>? previous;
        List<dynamic>? view;
        final frames = <Object>[];
        try {
          final start = DateTime.parse(surface.first['observedAt']);
          for (final r in surface) {
            final time = DateTime.parse(r['observedAt']);
            final clock = time.difference(start).inMilliseconds;
            final bytes = File('${dir.path}/${r['file']}').readAsBytesSync();
            final pixels = decodeStationImageCpu(bytes)!;
            final rgb = pixels.packedRgb;
            owner?.tick(clock);
          if (previous != null) owner?.rebind(previous);
            final ready = image.stationStream.firstWhere((v) => v != null);
            image.processPixels(
              rgb,
              dataTime: time,
              receivedAt: DateTime.now(),
            );
            final stations = (await ready)!;
            previous = stations;
            owner ??= NativeNiedDetectionOwner(
              stations,
              manualClock: true,
              onUpdate: (v) {
                if (v[2] != null) view = v[2] as List<dynamic>;
              },
            );
            owner.process(stations, sensitivity, clock: clock);
            owner.rebind(stations);
            final active = stations.where((s) => s.isActive).toList();
            final details = [
              for (final s in active)
                {
                  'code': s.code,
                  'prefecture': s.prefecture,
                  'rgb': rgb[s.pixelY * pixels.width + s.pixelX]
                      .toRadixString(16)
                      .padLeft(6, '0'),
                  'shindo': s.continuousShindo,
                  'kaLevel': s.kaLevel,
                  'activity': s.activity,
                  'ascend': s.ascend,
                  'detectState': s.detectState,
                  'reason': s.detectReason,
                  'triggerStamp': s.triggerStamp,
                },
            ];
            frames.add({
              'timeJst': r['observedAt'],
              'file': r['file'],
              'stage': view?[0],
              'weak': view?[1],
              'detected': view?[2],
              'strong': view?[3],
              'maxShindo': view?[4],
              'grids': view?[6],
              'activeCount': active.length,
              'probes': [
                for (final s in stations.where(
                  (s) => const ['AIC001', 'TYM002', 'TYM005'].contains(s.code),
                ))
                  {
                    'code': s.code,
                    'rgba': pixels.rgba.sublist(
                      (s.pixelY * pixels.width + s.pixelX) * 4,
                      (s.pixelY * pixels.width + s.pixelX) * 4 + 4,
                    ),
                    'shindo': s.gifObservation?.shindo,
                    'kaLevel': s.kaLevel,
                    'activity': s.activity,
                    'ascend': s.ascend,
                    'history': s.recentKaLevel.take(8).toList(),
                  },
              ],
              'stations': details,
            });
          }
        } finally {
          owner?.dispose();
          image.stop();
        }
        (report['runs'] as List).add({
          'sensitivity': sensitivity,
          'frames': frames,
        });
        final target = (frames.cast<Map<String, dynamic>>()).firstWhere(
          (f) => f['file'] == '20261102111826.jma_s.gif',
        );
        // ignore: avoid_print
        print(
          'CAPTURE_RESULT sensitivity=$sensitivity ${jsonEncode({
            for (final key in ['timeJst', 'stage', 'weak', 'detected', 'strong', 'activeCount']) key: target[key],
          })}',
        );
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
      report['ownersReleased'] = true;
      final name =
          Platform.environment['NIED_DIAGNOSTIC_DART_HISTORY'] == 'true'
          ? 'dart-history-diagnostic.json'
          : 'native-diagnostic.json';
      File('${dir.path}/$name').writeAsStringSync(jsonEncode(report));
      LmoniImageService().useNativeKaHistory = true;
    },
    skip: !NativeNiedDetectionOwner.supported,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'actual background GIF ingress at original one-second cadence',
    () async {
      final dir = Directory(
        Platform.environment['NIED_DIAGNOSTIC_CAPTURE'] ??
            'tmp/captures/nied_false_detection_20261102_111827_jst',
      );
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
      final referenceImage = LmoniImageService()..start();
      final referenceDetector = frozen.FrozenShakeDetectionService.forSource(
        'nied',
      );
      var referenceDetection = frozen.FrozenShakeDetectionService.idleSnapshot;
      referenceDetector.onDetectionSnapshotChanged = (v) =>
          referenceDetection = v;
      final rows = <Object>[];
      final errors = <Object>[];
      NiedPipelineFrame? latest;
      pipeline.onFrame = (v) => latest = v;
      pipeline.onError = errors.add;
      final watch = Stopwatch();
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
          final bytes = File('${dir.path}/${r['file']}').readAsBytesSync();
          expect(sha256.convert(bytes).toString(), r['sha256']);
          final time = DateTime.parse(r['observedAt']);
          final ready = referenceImage.stationStream.firstWhere(
            (v) => v != null,
          );
          referenceImage.processPixels(
            decodeStationImageCpu(bytes)!.packedRgb,
            dataTime: time,
            receivedAt: DateTime.now(),
          );
          final referenceStations = (await ready)!;
          referenceDetector.setStations(referenceStations);
          referenceDetector.processUpdate();
          await pipeline.injectGif(bytes, time, DateTime.now());
          expect(errors, isEmpty);
          expect(latest?.dataTime, time);
          final frame = latest!;
          final detection = frame.detection;
          rows.add({
            'timeJst': r['observedAt'],
            'elapsedMs': watch.elapsedMilliseconds,
            'stage': detection.stage.name,
            'weak': detection.weakCount,
            'detected': detection.detectedCount,
            'strong': detection.strongCount,
            'maxShindo': detection.maxShindo,
            'grids': [
              for (final cell in detection.gridCells.entries)
                [cell.key, cell.value.level],
            ],
            'activeCount': frame.stations.where((s) => s.isActive).length,
            'before20261019': {
              'stage': referenceDetection.stage.name,
              'weak': referenceDetection.weakCount,
              'detected': referenceDetection.detectedCount,
              'strong': referenceDetection.strongCount,
              'grids': referenceDetection.gridCells.length,
            },
            'samplerDifferences': [
              for (var j = 0; j < referenceStations.length; j++)
                if (referenceStations[j].continuousShindo !=
                        frame.stations[j].continuousShindo ||
                    referenceStations[j].level != frame.stations[j].level)
                  [
                    referenceStations[j].code,
                    referenceStations[j].continuousShindo,
                    frame.stations[j].continuousShindo,
                    referenceStations[j].level,
                    frame.stations[j].level,
                  ],
            ],
            'stations': [
              for (final s in frame.stations.where((s) => s.isActive))
                {
                  'code': s.code,
                  'prefecture': s.prefecture,
                  'shindo': s.continuousShindo,
                  'kaLevel': s.level,
                  'activity': s.activity,
                  'ascend': s.ascend,
                  'detectState': s.detectState,
                  'reason': s.detectReason,
                },
            ],
          });
          if (i % 30 == 0 || i == 146 || i == 147) {
            // ignore: avoid_print
            print(
              'PRODUCTION_GIF ${r['observedAt']} stage=${detection.stage.name} weak=${detection.weakCount} detected=${detection.detectedCount} grids=${detection.gridCells.length}',
            );
          }
        }
      } finally {
        pipeline.dispose();
        referenceDetector.reset(detachStations: true, emitSnapshot: false);
        referenceImage.stop();
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
      File('${dir.path}/production-ingress-diagnostic.json').writeAsStringSync(
        jsonEncode({
          'source': 'lmoni',
          'sensitivity': 2,
          'historicalReceivedAt': null,
          'testReceivedAt':
              'actual replay ingestion time, not historical receive time',
          'originalCadenceSeconds': 1,
          'ownersReleased': true,
          'frames': rows,
        }),
      );
      expect(rows, hasLength(181));
    },
    skip: !NativeNiedDetectionOwner.supported,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
