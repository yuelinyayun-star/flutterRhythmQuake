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
    final shindo = JpShindoScale.rawShindoFromLevel(s.level);
    if (shindo > max) {
      max = shindo;
    }
  }
  return max;
}

List<String> _topStationSummaries(List<NiedStation> stations) {
  final active = stations.where((s) => s.level >= 0).toList()
    ..sort((a, b) => b.level.compareTo(a.level));
  return active.take(8).map((s) {
    final shindo = JpShindoScale.rawShindoFromLevel(s.level);
    return '${s.code}:${shindo.toStringAsFixed(2)}';
  }).toList();
}

Future<List<_FrameReport>> _runGifWindow({
  required DateTime startJst,
  required int seconds,
  required Directory dir,
}) async {
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
  detector.onDetectionSnapshotChanged = (snapshot) {
    latestSnapshot = snapshot;
  };
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
          stations: const [],
        ),
      );
      continue;
    }
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

Future<List<_FrameReport>> _runYahooWindow({
  required DateTime startJst,
  required int seconds,
  required Directory dir,
}) async {
  final stations = await buildYahooReplayStations(
    File('${dir.path}\\sitelist.json'),
    includeUnmatchedPlaceholders: true,
  );
  final detector = ShakeDetectionService()..setSensitivity(2);
  ShakeDetectionSnapshot latestSnapshot = const ShakeDetectionSnapshot(
    stage: ShakeDetectStage.idle,
    weakCount: 0,
    detectedCount: 0,
    strongCount: 0,
    maxShindo: -1,
  );
  detector.onDetectionSnapshotChanged = (snapshot) {
    latestSnapshot = snapshot;
  };

  final reports = <_FrameReport>[];
  for (var i = 0; i < seconds; i++) {
    final jst = startJst.add(Duration(seconds: i));
    final timeKey = formatNiedTimeKey(jst);
    final file = File('${dir.path}\\$timeKey.json');
    if (!file.existsSync()) {
      reports.add(
        _FrameReport(
          jst: jst,
          fetched: false,
          maxStationShindo: -3.0,
          stage: ShakeDetectStage.idle,
          maxDetectJma: -1,
          gridCount: 0,
          stations: const [],
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
          stations: const [],
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
        stations: _topStationSummaries(stations),
      ),
    );
  }
  return reports;
}

void _printWindowSummary(
  String label,
  DateTime startJst,
  List<_FrameReport> reports,
) {
  final triggered = reports
      .where((r) => r.stage != ShakeDetectStage.idle || r.maxDetectJma >= 0)
      .toList();
  print('');
  print(
    '=== $label  ${formatNiedTimeKey(startJst)} ~ '
    '${formatNiedTimeKey(reports.last.jst)} JST ===',
  );
  print(
    'fetched=${reports.where((r) => r.fetched).length}/${reports.length} triggered=${triggered.length}',
  );
  for (final r in triggered) {
    final hhmmss =
        '${r.jst.hour.toString().padLeft(2, '0')}:${r.jst.minute.toString().padLeft(2, '0')}:${r.jst.second.toString().padLeft(2, '0')}';
    print(
      '$hhmmss fetched=${r.fetched} maxStation=${r.maxStationShindo.toStringAsFixed(2)} '
      'stage=${r.stage.name} detectMax=${r.maxDetectJma} grids=${r.gridCount} '
      'tops=${r.stations.join(", ")}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'compare recent GIF and Yahoo replay windows around 51-52',
    () async {
      const windowSeconds = 120;
      final baseDir = Directory('.dart_tool\\nied_compare_recent');
      if (!baseDir.existsSync()) {
        markTestSkipped('Missing offline replay directory: ${baseDir.path}');
        return;
      }
      final candidateStarts = <DateTime>[
        DateTime(2026, 6, 9, 15, 51, 0),
        DateTime(2026, 6, 9, 16, 51, 0),
      ];

      for (final start in candidateStarts) {
        final key = formatNiedTimeKey(start).substring(0, 12);
        final dir = Directory('${baseDir.path}\\$key');
        if (!dir.existsSync()) {
          print('skip missing dir: ${dir.path}');
          continue;
        }
        final gifReports = await _runGifWindow(
          startJst: start,
          seconds: windowSeconds,
          dir: dir,
        );
        final yahooReports = await _runYahooWindow(
          startJst: start,
          seconds: windowSeconds,
          dir: dir,
        );
        _printWindowSummary('GIF', start, gifReports);
        _printWindowSummary('Yahoo', start, yahooReports);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
