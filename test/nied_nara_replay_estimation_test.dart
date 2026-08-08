import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/hypocenter_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

import 'support/nied_replay_fixture.dart';

double _haversineKm(LatLng a, LatLng b) {
  const distance = Distance();
  return distance.as(LengthUnit.Kilometer, a, b);
}

void main() {
  test('replay 2026-06-10 18:01:30 JST Nara event estimation snapshot', () async {
    final dir = workspaceDirectory('tmp/captures/20260610_180130_jst_nara_m36');
    expect(dir.existsSync(), isTrue);

    const actual = LatLng(34.2, 135.8);
    final startJst = DateTime(2026, 6, 10, 18, 1, 20);
    final targetJst = DateTime(2026, 6, 10, 18, 2, 10);

    Future<Map<String, Object?>> runGif() async {
      final service = LmoniImageService()..start();
      final detector = ShakeDetectionService()..setSensitivity(2);
      ShakeDetectionSnapshot latestSnapshot = const ShakeDetectionSnapshot(
        stage: ShakeDetectStage.idle,
        weakCount: 0,
        detectedCount: 0,
        strongCount: 0,
        maxShindo: -1,
      );
      List<NiedStation> latestStations = const [];
      DateTime? firstDetectAt;
      detector.onDetectionSnapshotChanged = (snapshot) {
        latestSnapshot = snapshot;
      };
      final sub = service.stationStream.listen((stations) {
        if (stations == null) return;
        latestStations = stations;
        detector.setStations(stations);
        detector.processUpdate();
      });

      StationEventTracker.instance.resetNied();
      for (var i = 0; i <= 50; i++) {
        final jst = startJst.add(Duration(seconds: i));
        final stamp = formatNiedTimeKey(jst);
        final surface = await decodeNiedGifFile(
          File('${dir.path}\\$stamp.lmoni.jma_s.gif'),
        );
        if (surface == null) continue;
        final borehole = await decodeNiedGifFile(
          File('${dir.path}\\$stamp.lmoni.jma_b.gif'),
        );
        service.processPixels(
          surface.packedRgb,
          boreholePackedRgb: borehole?.packedRgb,
          surfaceGifBytes: surface.gifBytes,
          boreholeGifBytes: borehole?.gifBytes,
          dataTime: jst,
        );
        if (latestSnapshot.stage != ShakeDetectStage.idle) {
          firstDetectAt ??= jst;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await sub.cancel();
      service.stop();

      final estimatePoint =
          latestSnapshot.hypoLat != null && latestSnapshot.hypoLng != null
          ? LatLng(latestSnapshot.hypoLat!, latestSnapshot.hypoLng!)
          : null;
      final activeStations = latestStations
          .where((s) => s.isActive && s.level >= 0)
          .toList();
      final scratchEstimate = HypocenterEstimator.estimate(latestStations);
      final scratchPoint = scratchEstimate == null
          ? null
          : LatLng(scratchEstimate.latitude, scratchEstimate.longitude);

      return {
        'stage': latestSnapshot.stage.name,
        'firstDetectAt': firstDetectAt?.toIso8601String(),
        'maxShindo': latestSnapshot.maxShindo,
        'gridCount': latestSnapshot.gridCells.length,
        'activeStationCount': activeStations.length,
        'newEstimate': estimatePoint == null
            ? null
            : '${estimatePoint.latitude.toStringAsFixed(3)},${estimatePoint.longitude.toStringAsFixed(3)}',
        'newErrorKm': estimatePoint == null
            ? null
            : _haversineKm(actual, estimatePoint).toStringAsFixed(1),
        'scratchEstimate': scratchPoint == null
            ? null
            : '${scratchPoint.latitude.toStringAsFixed(3)},${scratchPoint.longitude.toStringAsFixed(3)}',
        'scratchErrorKm': scratchPoint == null
            ? null
            : _haversineKm(actual, scratchPoint).toStringAsFixed(1),
        'topStations': activeStations
            .map(
              (s) =>
                  '${s.code}:${JpShindoScale.rawShindoFromKanameishiLevel(s.level).toStringAsFixed(2)}',
            )
            .take(8)
            .toList(),
      };
    }

    Future<Map<String, Object?>> runYahoo() async {
      final stations = await buildYahooReplayStations(
        File('${dir.path}\\sitelist.json'),
      );
      final detector = ShakeDetectionService()..setSensitivity(2);
      ShakeDetectionSnapshot latestSnapshot = const ShakeDetectionSnapshot(
        stage: ShakeDetectStage.idle,
        weakCount: 0,
        detectedCount: 0,
        strongCount: 0,
        maxShindo: -1,
      );
      DateTime? firstDetectAt;
      detector.onDetectionSnapshotChanged = (snapshot) {
        latestSnapshot = snapshot;
      };

      StationEventTracker.instance.resetNied();
      for (var i = 0; i <= 50; i++) {
        final jst = startJst.add(Duration(seconds: i));
        final stamp = formatNiedTimeKey(jst);
        final file = File('${dir.path}\\$stamp.yahoo.json');
        if (!file.existsSync()) continue;
        final data = await readNiedJsonFile(file);
        if (!applyYahooReplayFrame(stations, data, jst)) continue;
        detector.setStations(stations);
        detector.processUpdate();
        if (latestSnapshot.stage != ShakeDetectStage.idle) {
          firstDetectAt ??= jst;
        }
      }

      final estimatePoint =
          latestSnapshot.hypoLat != null && latestSnapshot.hypoLng != null
          ? LatLng(latestSnapshot.hypoLat!, latestSnapshot.hypoLng!)
          : null;
      final activeStations = stations
          .where((s) => s.isActive && s.level >= 0)
          .toList();
      final scratchEstimate = HypocenterEstimator.estimate(stations);
      final scratchPoint = scratchEstimate == null
          ? null
          : LatLng(scratchEstimate.latitude, scratchEstimate.longitude);

      return {
        'stage': latestSnapshot.stage.name,
        'firstDetectAt': firstDetectAt?.toIso8601String(),
        'maxShindo': latestSnapshot.maxShindo,
        'gridCount': latestSnapshot.gridCells.length,
        'activeStationCount': activeStations.length,
        'newEstimate': estimatePoint == null
            ? null
            : '${estimatePoint.latitude.toStringAsFixed(3)},${estimatePoint.longitude.toStringAsFixed(3)}',
        'newErrorKm': estimatePoint == null
            ? null
            : _haversineKm(actual, estimatePoint).toStringAsFixed(1),
        'scratchEstimate': scratchPoint == null
            ? null
            : '${scratchPoint.latitude.toStringAsFixed(3)},${scratchPoint.longitude.toStringAsFixed(3)}',
        'scratchErrorKm': scratchPoint == null
            ? null
            : _haversineKm(actual, scratchPoint).toStringAsFixed(1),
        'topStations': activeStations
            .map(
              (s) =>
                  '${s.code}:${JpShindoScale.rawShindoFromKanameishiLevel(s.level).toStringAsFixed(2)}',
            )
            .take(8)
            .toList(),
      };
    }

    final gif = await runGif();
    final yahoo = await runYahoo();

    // ignore: avoid_print
    print('Nara $targetJst GIF => ${jsonEncode(gif)}');
    // ignore: avoid_print
    print('Nara $targetJst Yahoo => ${jsonEncode(yahoo)}');

    expect(gif['stage'], isNotNull);
    expect(yahoo['stage'], isNotNull);
  });
}
