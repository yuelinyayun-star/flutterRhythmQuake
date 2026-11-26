import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_realtime_pipeline.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_worker.dart';
import 'package:flutterrhythmquake/services/sources/native_nied_detection_owner.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capture = Directory('tmp/captures/20260610_180130_jst_nara_m36');
  test(
    'Original Nara GIF production pipeline runs SREV HYP and magnitude; switch and disable',
    () async {
      final pipeline = NiedRealtimePipeline(testMode: true);
      final errors = <Object>[];
      final results = <Map<String, Object?>>[];
      NiedPipelineFrame? frame;
      NiedSourceEstimationResult? result;
      pipeline.onFrame = (f) => frame = f;
      pipeline.onEstimate = (r) => result = r;
      pipeline.onError = errors.add;
      try {
        await pipeline.start(
          source: 'lmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: true,
        );
        for (var second = 20; second <= 70; second++) {
          final time = DateTime.utc(2026, 6, 10, 9, 1, second);
          final stamp = DateTime(2026, 6, 10, 18, 1, second);
          String pad(int x) => x.toString().padLeft(2, '0');
          final name =
              '20260610${pad(stamp.hour)}${pad(stamp.minute)}${pad(stamp.second)}.lmoni.jma_s.gif';
          final f = File('${capture.path}/$name');
          result = null;
          await pipeline.injectGif(f.readAsBytesSync(), time, time);
          expect(errors, isEmpty, reason: name);
          expect(frame!.source, 'lmoni');
          expect(result, isNotNull, reason: name);
          final estimate = result!.event?.estimate;
          if (estimate != null) {
            expect(estimate.method, SrevSourceProjection.method);
            expect(estimate.magnitude, isNotNull);
            expect(
              estimate.magnitude,
              estimate.diagnostics['rq_magnitude_shadow'],
            );
            expect(estimate.diagnostics['srev_original_magnitude'], isNotNull);
            results.add({
              'time': time.toIso8601String(),
              'lat': estimate.latitude,
              'lon': estimate.longitude,
              'depth': estimate.depthKm,
              'magnitude': estimate.magnitude,
              'origin': estimate.originTime?.toIso8601String(),
              'count': estimate.supportingStationCount,
              'residual': estimate.diagnostics['srev_error'],
              for (final key in [
                'srev_original_magnitude',
                'magnitude_model',
                'rq_magnitude_shadow',
                'rq_magnitude_shadow_current',
                'rq_magnitude_shadow_input',
                'rq_magnitude_shadow_peak',
                'rq_magnitude_shadow_distance_km',
                'rq_magnitude_uncalibrated_current',
              ])
                key: estimate.diagnostics[key],
              'computeUs': result!.computationMicroseconds,
              'stations': frame!.stations.length,
            });
          }
        }
        expect(results, isNotEmpty);
        File(
          "tmp/srev_nied_migration_20261125/nara_gif_rq_magnitude.json",
        ).writeAsStringSync(jsonEncode(results));
        stdout.writeln(
          'LIVE_SREV_HYP ${results.length}/51 estimates; first=${results.first}; last=${results.last}',
        );
        pipeline.stop();
        await pipeline.start(
          source: 'kmoni',
          replay: const NiedReplayConfig.disabled(),
          sensitivity: 2,
          estimate: false,
        );
        result = null;
        final file = File('${capture.path}/20260610180120.lmoni.jma_s.gif');
        final time = DateTime.utc(2026, 6, 10, 9, 1, 20);
        await pipeline.injectGif(file.readAsBytesSync(), time, time);
        expect(frame!.source, 'kmoni');
        expect(result, isNull);
        expect(errors, isEmpty);
      } finally {
        pipeline.dispose();
        NiedBackgroundWorker.instance.stop();
      }
    },
    skip: !NativeNiedDetectionOwner.supported || !capture.existsSync(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
