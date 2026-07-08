// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

import 'support/nied_replay_fixture.dart';

class _FrameReport {
  final DateTime jst;
  final bool fetched;
  final double maxStationShindo;
  final ShakeDetectStage stage;
  final int maxDetectJma;
  final int gridCount;

  const _FrameReport({
    required this.jst,
    required this.fetched,
    required this.maxStationShindo,
    required this.stage,
    required this.maxDetectJma,
    required this.gridCount,
  });
}

double _maxStationShindo(List<NiedStation> stations) {
  var max = -3.0;
  for (final s in stations) {
    if (s.level < 0) continue;
    final shindo = JpShindoScale.rawShindoFromLevel(s.level);
    if (shindo > max) max = shindo;
  }
  return max;
}

Future<List<_FrameReport>> _runGifWindow(
  DateTime startJst,
  int seconds,
  Directory dir,
) async {
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
  detector.onDetectionSnapshotChanged = (snapshot) => latestSnapshot = snapshot;
  final sub = service.stationStream.listen((stations) {
    if (stations == null) return;
    latestStations = stations;
    detector.setStations(stations);
    detector.processUpdate();
  });

  final reports = <_FrameReport>[];
  for (var i = 0; i < seconds; i++) {
    final jst = startJst.add(Duration(seconds: i));
    final stamp = formatNiedTimeKey(jst);
    final surface = await decodeNiedGifFile(
      File('${dir.path}\\$stamp.jma_s.gif'),
    );
    if (surface == null) {
      reports.add(
        _FrameReport(
          jst: jst,
          fetched: false,
          maxStationShindo: -3.0,
          stage: ShakeDetectStage.idle,
          maxDetectJma: -1,
          gridCount: 0,
        ),
      );
      continue;
    }
    final borehole = await decodeNiedGifFile(
      File('${dir.path}\\$stamp.jma_b.gif'),
    );
    service.processPixels(
      surface.packedRgb,
      surfaceGifBytes: surface.gifBytes,
      dataTime: jst,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    reports.add(
      _FrameReport(
        jst: jst,
        fetched: true,
        maxStationShindo: _maxStationShindo(latestStations),
        stage: latestSnapshot.stage,
        maxDetectJma: latestSnapshot.maxShindo,
        gridCount: latestSnapshot.gridCells.length,
      ),
    );
  }

  await sub.cancel();
  service.stop();
  return reports;
}

Future<List<_FrameReport>> _runYahooWindow(
  DateTime startJst,
  int seconds,
  Directory dir,
) async {
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
  detector.onDetectionSnapshotChanged = (snapshot) => latestSnapshot = snapshot;

  final reports = <_FrameReport>[];
  for (var i = 0; i < seconds; i++) {
    final jst = startJst.add(Duration(seconds: i));
    final stamp = formatNiedTimeKey(jst);
    final file = File('${dir.path}\\$stamp.json');
    if (!file.existsSync()) {
      reports.add(
        _FrameReport(
          jst: jst,
          fetched: false,
          maxStationShindo: -3.0,
          stage: ShakeDetectStage.idle,
          maxDetectJma: -1,
          gridCount: 0,
        ),
      );
      continue;
    }

    final data = await readNiedJsonFile(file);
    if (!applyYahooReplayFrame(stations, data, jst)) {
      reports.add(
        _FrameReport(
          jst: jst,
          fetched: false,
          maxStationShindo: -3.0,
          stage: ShakeDetectStage.idle,
          maxDetectJma: -1,
          gridCount: 0,
        ),
      );
      continue;
    }

    detector.setStations(stations);
    detector.processUpdate();
    reports.add(
      _FrameReport(
        jst: jst,
        fetched: true,
        maxStationShindo: _maxStationShindo(stations),
        stage: latestSnapshot.stage,
        maxDetectJma: latestSnapshot.maxShindo,
        gridCount: latestSnapshot.gridCells.length,
      ),
    );
  }
  return reports;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'continuous compare around JST 2026-06-14 17:56:04',
    () async {
      final dir = workspaceDirectory(
        'tmp/captures/20260614_175604_jst_window41',
      );
      expect(dir.existsSync(), isTrue);

      final start = DateTime(2026, 6, 14, 17, 55, 44);
      const seconds = 41;

      final gifReports = await _runGifWindow(start, seconds, dir);
      final yahooReports = await _runYahooWindow(start, seconds, dir);

      print('');
      print('=== Continuous compare @ JST 2026-06-14 17:55:44 ~ 17:56:24 ===');
      for (var i = 0; i < seconds; i++) {
        final g = gifReports[i];
        final y = yahooReports[i];
        final hhmmss =
            '${g.jst.hour.toString().padLeft(2, '0')}:${g.jst.minute.toString().padLeft(2, '0')}:${g.jst.second.toString().padLeft(2, '0')}';
        final delta = (g.maxStationShindo - y.maxStationShindo).toStringAsFixed(
          2,
        );
        print(
          '$hhmmss '
          'GIF[max=${g.maxStationShindo.toStringAsFixed(2)} stage=${g.stage.name} det=${g.maxDetectJma} grids=${g.gridCount}] '
          'Yahoo[max=${y.maxStationShindo.toStringAsFixed(2)} stage=${y.stage.name} det=${y.maxDetectJma} grids=${y.gridCount}] '
          'delta=$delta',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
