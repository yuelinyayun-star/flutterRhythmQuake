// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

import 'support/nied_replay_fixture.dart';

class _CompareResult {
  final String source;
  final ShakeDetectStage stage;
  final int maxDetectJma;
  final int gridCount;
  final double maxStationShindo;
  final List<String> topStations;
  final List<String> detectedStations;

  const _CompareResult({
    required this.source,
    required this.stage,
    required this.maxDetectJma,
    required this.gridCount,
    required this.maxStationShindo,
    required this.topStations,
    required this.detectedStations,
  });

  Map<String, Object?> toJson() => {
    'source': source,
    'stage': stage.name,
    'maxDetectJma': maxDetectJma,
    'gridCount': gridCount,
    'maxStationShindo': maxStationShindo,
    'topStations': topStations,
    'detectedStations': detectedStations,
  };
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

List<String> _topStationSummaries(List<NiedStation> stations) {
  final active = stations.where((s) => s.level >= 0).toList()
    ..sort((a, b) => b.level.compareTo(a.level));
  return active.take(8).map((s) {
    final display = JpShindoScale.rawShindoFromLevel(
      s.level,
    ).toStringAsFixed(2);
    return '${s.code}:disp=$display det21=${s.detectLevel}';
  }).toList();
}

List<String> _detectedStationSummaries(ShakeDetectionSnapshot snapshot) {
  return snapshot.detectedStations.take(12).map((s) {
    return '${s.code}:jma=${s.jmaShindo} lv=${s.level} state=${s.detectState}';
  }).toList();
}

Future<_CompareResult> _runGif(Directory dir, DateTime jst) async {
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

  final stamp = '20260614165604';
  final surface = await decodeNiedGifFile(
    File('${dir.path}\\$stamp.lmoni.jma_s.gif'),
  );
  final borehole = await decodeNiedGifFile(
    File('${dir.path}\\$stamp.lmoni.jma_b.gif'),
  );
  expect(surface, isNotNull);
  service.processPixels(
    surface!.packedRgb,
    surfaceGifBytes: surface.gifBytes,
    dataTime: jst,
  );
  await Future<void>.delayed(const Duration(milliseconds: 10));

  await sub.cancel();
  service.stop();

  return _CompareResult(
    source: 'gif',
    stage: latestSnapshot.stage,
    maxDetectJma: latestSnapshot.maxShindo,
    gridCount: latestSnapshot.gridCells.length,
    maxStationShindo: _maxStationShindo(latestStations),
    topStations: _topStationSummaries(latestStations),
    detectedStations: _detectedStationSummaries(latestSnapshot),
  );
}

Future<_CompareResult> _runYahoo(Directory dir, DateTime jst) async {
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
  detector.onDetectionSnapshotChanged = (snapshot) {
    latestSnapshot = snapshot;
  };

  final file = File('${dir.path}\\20260614165604.yahoo.parsed.json');
  expect(file.existsSync(), isTrue);
  final data = await readNiedJsonFile(file);
  expect(applyYahooReplayFrame(stations, data, jst), isTrue);
  detector.setStations(stations);
  detector.processUpdate();

  return _CompareResult(
    source: 'yahoo',
    stage: latestSnapshot.stage,
    maxDetectJma: latestSnapshot.maxShindo,
    gridCount: latestSnapshot.gridCells.length,
    maxStationShindo: _maxStationShindo(stations),
    topStations: _topStationSummaries(stations),
    detectedStations: _detectedStationSummaries(latestSnapshot),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'compare GIF vs Yahoo on captured JST 2026-06-14 16:56:04',
    () async {
      final dir = workspaceDirectory('tmp/captures/20260614_165604_jst');
      expect(dir.existsSync(), isTrue);
      final jst = DateTime(2026, 6, 14, 16, 56, 4);

      final gif = await _runGif(dir, jst);
      final yahoo = await _runYahoo(dir, jst);

      print('');
      print('=== NIED compare @ JST 2026-06-14 16:56:04 ===');
      print(jsonEncode(gif.toJson()));
      print(jsonEncode(yahoo.toJson()));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
