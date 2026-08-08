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
  final List<String> stations;

  const _FrameReport({
    required this.jst,
    required this.fetched,
    required this.maxStationShindo,
    required this.stage,
    required this.maxDetectJma,
    required this.gridCount,
    required this.stations,
  });
}

double _maxStationShindo(List<NiedStation> stations) {
  var max = -3.0;
  for (final s in stations) {
    if (s.level < 0) continue;
    final shindo = JpShindoScale.rawShindoFromKanameishiLevel(s.level);
    if (shindo > max) max = shindo;
  }
  return max;
}

List<String> _topStationSummaries(List<NiedStation> stations) {
  final active = stations.where((s) => s.level >= 0).toList()
    ..sort((a, b) => b.level.compareTo(a.level));
  return active.take(8).map((s) {
    final shindo = JpShindoScale.rawShindoFromKanameishiLevel(s.level);
    return '${s.code}:${shindo.toStringAsFixed(2)}';
  }).toList();
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
    if (surface == null) continue;
    final borehole = await decodeNiedGifFile(
      File('${dir.path}\\$stamp.jma_b.gif'),
    );
    service.processPixels(
      surface.packedRgb,
      boreholePackedRgb: borehole?.packedRgb,
      surfaceGifBytes: surface.gifBytes,
      boreholeGifBytes: borehole?.gifBytes,
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
        stations: _topStationSummaries(latestStations),
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
    if (!file.existsSync()) continue;
    final data = await readNiedJsonFile(file);
    if (!applyYahooReplayFrame(stations, data, jst)) continue;
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
        stations: _topStationSummaries(stations),
      ),
    );
  }
  return reports;
}

void _printSummary(String label, List<_FrameReport> reports) {
  final triggered = reports
      .where((r) => r.stage != ShakeDetectStage.idle || r.maxDetectJma >= 0)
      .toList();
  print('');
  print('=== $label ===');
  print('frames=${reports.length} triggered=${triggered.length}');
  for (final r in triggered) {
    final hhmmss =
        '${r.jst.hour.toString().padLeft(2, '0')}:${r.jst.minute.toString().padLeft(2, '0')}:${r.jst.second.toString().padLeft(2, '0')}';
    print(
      '$hhmmss maxStation=${r.maxStationShindo.toStringAsFixed(2)} '
      'stage=${r.stage.name} detectMax=${r.maxDetectJma} grids=${r.gridCount} '
      'tops=${r.stations.join(", ")}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'compare 2026-06-09 18:51 JST GIF vs Yahoo offline window',
    () async {
      final dir = Directory('.dart_tool\\nied_compare_recent\\202606091851');
      if (!dir.existsSync()) {
        markTestSkipped('Missing offline replay directory: ${dir.path}');
        return;
      }
      final start = DateTime(2026, 6, 9, 18, 51, 0);
      const seconds = 91;
      final gifReports = await _runGifWindow(start, seconds, dir);
      final yahooReports = await _runYahooWindow(start, seconds, dir);
      _printSummary('GIF', gifReports);
      _printSummary('Yahoo', yahooReports);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
