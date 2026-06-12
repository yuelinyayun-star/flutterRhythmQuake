import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

class _DecodedGifFrame {
  final List<int> packedRgb;
  final Uint8List gifBytes;

  const _DecodedGifFrame({
    required this.packedRgb,
    required this.gifBytes,
  });
}

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

Future<_DecodedGifFrame?> _decodeGifFile(File file) async {
  if (!file.existsSync()) return null;
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    image.dispose();
    codec.dispose();
    return null;
  }

  final pixels = List<int>.filled(image.width * image.height, 0);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    final r = byteData.getUint8(offset);
    final g = byteData.getUint8(offset + 1);
    final b = byteData.getUint8(offset + 2);
    pixels[i] = (r << 16) | (g << 8) | b;
  }

  image.dispose();
  codec.dispose();
  return _DecodedGifFrame(
    packedRgb: pixels,
    gifBytes: Uint8List.fromList(bytes),
  );
}

double _roundTo1(double v) => (v * 10).roundToDouble() / 10;

Future<List<NiedStation>> _buildYahooStations(File sitelistFile) async {
  if (!sitelistFile.existsSync()) {
    throw StateError('Missing Yahoo sitelist: ${sitelistFile.path}');
  }
  final data =
      jsonDecode(await sitelistFile.readAsString()) as Map<String, dynamic>;
  final items = data['items'] as List<dynamic>? ?? const [];

  final db = NiedStationDb.stations;
  final list = <NiedStation>[];
  int k = -1;
  const maxTry = 10;

  for (int i = 0; i < items.length; i++) {
    final item = items[i] as List<dynamic>;
    final targetLat = _roundTo1((item[0] as num).toDouble());
    final targetLng = _roundTo1((item[1] as num).toDouble());

    int? matchedIdx;
    for (int j = 0; j < maxTry && (k + j + 1) < db.length; j++) {
      final s = db[k + j + 1];
      final lat = _roundTo1((s['lat'] as num).toDouble());
      final lng = _roundTo1((s['lng'] as num).toDouble());
      if (lat == targetLat && lng == targetLng) {
        matchedIdx = k + j + 1;
        break;
      }
    }

    if (matchedIdx != null) {
      k = matchedIdx;
      final s = db[matchedIdx];
      list.add(
        NiedStation(
          id: i,
          code: s['code'] as String,
          name: s['name'] as String,
          coordinate: LatLng(
            (s['lat'] as num).toDouble(),
            (s['lng'] as num).toDouble(),
          ),
          network: (s['network'] as String?) ?? 'K-NET',
          prefecture: (s['pref'] as String?) ?? '',
          expireSeconds: 30,
        ),
      );
    } else {
      list.add(
        NiedStation(
          id: i,
          code: 'YAH$i',
          name: '',
          coordinate: LatLng(
            (item[0] as num).toDouble(),
            (item[1] as num).toDouble(),
          ),
          network: 'K-NET',
          prefecture: '',
          expireSeconds: 30,
        ),
      );
    }
  }

  return list;
}

String _formatTimeKey(DateTime jst) {
  final ymd =
      '${jst.year}${jst.month.toString().padLeft(2, '0')}${jst.day.toString().padLeft(2, '0')}';
  final hms =
      '${jst.hour.toString().padLeft(2, '0')}${jst.minute.toString().padLeft(2, '0')}${jst.second.toString().padLeft(2, '0')}';
  return '$ymd$hms';
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
  final active =
      stations.where((s) => s.level >= 0).toList()
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
    final stamp = _formatTimeKey(jst);
    final surface = await _decodeGifFile(File('${dir.path}\\$stamp.jma_s.gif'));
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
    final borehole = await _decodeGifFile(File('${dir.path}\\$stamp.jma_b.gif'));
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
  final stations = await _buildYahooStations(File('${dir.path}\\sitelist.json'));
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
    final timeKey = _formatTimeKey(jst);
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

    final data =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final rtData = data['realTimeData'] as Map<String, dynamic>?;
    final intensityStr = rtData?['intensity'] as String?;
    if (intensityStr == null) {
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

    final stamp = DateTime.now();
    for (int index = 0;
        index < stations.length && index < intensityStr.length;
        index++) {
      final detectLevel = intensityStr.codeUnitAt(index) - 100;
      final level = JpShindoScale.levelFromKanameishiLevel(detectLevel);
      final station = stations[index];
      station.update(level, newDetectLevel: detectLevel);
      station.lastUpdate = stamp;
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
  print('=== $label  ${_formatTimeKey(startJst)} ~ ${_formatTimeKey(reports.last.jst)} JST ===');
  print('fetched=${reports.where((r) => r.fetched).length}/${reports.length} triggered=${triggered.length}');
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

  test('compare recent GIF and Yahoo replay windows around 51-52', () async {
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
      final key = _formatTimeKey(start).substring(0, 12);
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
  }, timeout: const Timeout(Duration(minutes: 10)));
}
