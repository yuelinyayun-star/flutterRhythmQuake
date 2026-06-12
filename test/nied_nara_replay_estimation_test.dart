import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/hypocenter_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

class _DecodedGifFrame {
  final List<int> packedRgb;
  final Uint8List gifBytes;
  const _DecodedGifFrame({required this.packedRgb, required this.gifBytes});
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

String _formatTimeKey(DateTime jst) {
  final ymd =
      '${jst.year}${jst.month.toString().padLeft(2, '0')}${jst.day.toString().padLeft(2, '0')}';
  final hms =
      '${jst.hour.toString().padLeft(2, '0')}${jst.minute.toString().padLeft(2, '0')}${jst.second.toString().padLeft(2, '0')}';
  return '$ymd$hms';
}

double _haversineKm(LatLng a, LatLng b) {
  const distance = Distance();
  return distance.as(LengthUnit.Kilometer, a, b);
}

Future<Map<String, dynamic>> _readJsonFile(File file) async {
  final bytes = await file.readAsBytes();
  List<int> decoded = bytes;
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    decoded = gzip.decode(bytes);
  }
  return jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
}

Future<List<NiedStation>> _buildYahooStations(File sitelistFile) async {
  final bytes = await sitelistFile.readAsBytes();
  List<int> decoded = bytes;
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    decoded = gzip.decode(bytes);
  }
  final data = jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
  final items = data['items'] as List<dynamic>? ?? const [];
  final db = NiedStationDb.stations;
  final list = <NiedStation>[];
  var k = -1;

  double roundTo1(double v) => (v * 10).roundToDouble() / 10;

  for (int i = 0; i < items.length; i++) {
    final item = items[i] as List<dynamic>;
    final targetLat = roundTo1((item[0] as num).toDouble());
    final targetLng = roundTo1((item[1] as num).toDouble());

    int? matchedIdx;
    for (int j = 0; j < 10 && (k + j + 1) < db.length; j++) {
      final s = db[k + j + 1];
      final lat = roundTo1((s['lat'] as num).toDouble());
      final lng = roundTo1((s['lng'] as num).toDouble());
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
    }
  }
  return list;
}

void main() {
  test('replay 2026-06-10 18:01:30 JST Nara event estimation snapshot', () async {
    final dir = Directory(
      'D:\\flutterApp\\flutterrhythmquake\\tmp\\captures\\20260610_180130_jst_nara_m36',
    );
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
        final stamp = _formatTimeKey(jst);
        final surface = await _decodeGifFile(
          File('${dir.path}\\$stamp.lmoni.jma_s.gif'),
        );
        if (surface == null) continue;
        final borehole = await _decodeGifFile(
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
                  '${s.code}:${JpShindoScale.rawShindoFromLevel(s.level).toStringAsFixed(2)}',
            )
            .take(8)
            .toList(),
      };
    }

    Future<Map<String, Object?>> runYahoo() async {
      final stations = await _buildYahooStations(
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
        final stamp = _formatTimeKey(jst);
        final file = File('${dir.path}\\$stamp.yahoo.json');
        if (!file.existsSync()) continue;
        final data = await _readJsonFile(file);
        final rtData = data['realTimeData'] as Map<String, dynamic>?;
        final intensityStr = rtData?['intensity'] as String?;
        if (intensityStr == null) continue;

        for (
          int idx = 0;
          idx < stations.length && idx < intensityStr.length;
          idx++
        ) {
          final detectLevel = intensityStr.codeUnitAt(idx) - 100;
          final level = JpShindoScale.levelFromKanameishiLevel(detectLevel);
          final station = stations[idx];
          station.update(level, newDetectLevel: detectLevel);
          station.lastUpdate = jst;
          station.lastDataTime = jst;
        }
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
                  '${s.code}:${JpShindoScale.rawShindoFromLevel(s.level).toStringAsFixed(2)}',
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
