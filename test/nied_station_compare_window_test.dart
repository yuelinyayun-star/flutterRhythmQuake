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

double _roundTo1(double v) => (v * 10).roundToDouble() / 10;

String _formatTimeKey(DateTime jst) {
  final ymd =
      '${jst.year}${jst.month.toString().padLeft(2, '0')}${jst.day.toString().padLeft(2, '0')}';
  final hms =
      '${jst.hour.toString().padLeft(2, '0')}${jst.minute.toString().padLeft(2, '0')}${jst.second.toString().padLeft(2, '0')}';
  return '$ymd$hms';
}

Future<List<NiedStation>> _buildYahooStations(File sitelistFile) async {
  final data =
      jsonDecode(await sitelistFile.readAsString()) as Map<String, dynamic>;
  final items = data['items'] as List<dynamic>? ?? const [];
  final db = NiedStationDb.stations;
  final list = <NiedStation>[];
  var k = -1;

  for (int i = 0; i < items.length; i++) {
    final item = items[i] as List<dynamic>;
    final targetLat = _roundTo1((item[0] as num).toDouble());
    final targetLng = _roundTo1((item[1] as num).toDouble());

    int? matchedIdx;
    for (int j = 0; j < 10 && (k + j + 1) < db.length; j++) {
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
    }
  }
  return list;
}

Future<Map<String, dynamic>> _readJsonFile(File file) async {
  final bytes = await file.readAsBytes();
  List<int> decoded = bytes;
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    decoded = gzip.decode(bytes);
  }
  return jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
}

double _kanameishiMidpointShindo(int detectLevel) {
  if (detectLevel < 0) return double.nan;
  if (detectLevel == 0) return -3.0;
  if (detectLevel >= 20) return 6.5;
  return (detectLevel + 0.5 - 7) / 2;
}

String _gifLine(DateTime jst, NiedStation? station) {
  final hhmmss =
      '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}:${jst.second.toString().padLeft(2, '0')}';
  if (station == null) return '$hhmmss GIF missing';
  final display = station.level >= 0
      ? JpShindoScale.rawShindoFromLevel(station.level).toStringAsFixed(2)
      : '--';
  final cont = station.level >= 0
      ? station.continuousShindo.toStringAsFixed(3)
      : '--';
  return '$hhmmss GIF ${station.code} cont=$cont raw30=${station.level} '
      'disp=$display det21=${station.detectLevel}';
}

String _yahooLine(DateTime jst, NiedStation? station) {
  final hhmmss =
      '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}:${jst.second.toString().padLeft(2, '0')}';
  if (station == null) return '$hhmmss Yahoo missing';
  final display = station.level >= 0
      ? JpShindoScale.rawShindoFromLevel(station.level).toStringAsFixed(2)
      : '--';
  final midpoint = station.detectLevel >= 0
      ? _kanameishiMidpointShindo(station.detectLevel).toStringAsFixed(2)
      : '--';
  return '$hhmmss Yahoo ${station.code} mid21=$midpoint raw30=${station.level} '
      'disp=$display det21=${station.detectLevel}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('print GIF vs Yahoo station values around 2026-06-09 18:52 JST', () async {
    final dir = Directory('.dart_tool\\nied_compare_recent\\202606091851');
    if (!dir.existsSync()) {
      markTestSkipped('Missing offline replay directory: ${dir.path}');
      return;
    }

    const watchCodes = ['OSK006', 'CHB015', 'IBRH21'];
    final start = DateTime(2026, 6, 9, 18, 52, 0);
    const seconds = 8;

    final gifService = LmoniImageService()..start();
    List<NiedStation> gifStations = const [];
    final gifSub = gifService.stationStream.listen((stations) {
      if (stations != null) gifStations = stations;
    });

    final yahooStations = await _buildYahooStations(File('${dir.path}\\sitelist.json'));

    print('');
    print('=== Station compare 2026-06-09 18:52 JST ===');
    for (var i = 0; i < seconds; i++) {
      final jst = start.add(Duration(seconds: i));
      final stamp = _formatTimeKey(jst);

      final surface = await _decodeGifFile(File('${dir.path}\\$stamp.jma_s.gif'));
      final borehole = await _decodeGifFile(File('${dir.path}\\$stamp.jma_b.gif'));
      if (surface != null) {
        gifService.processPixels(
          surface.packedRgb,
          boreholePackedRgb: borehole?.packedRgb,
          surfaceGifBytes: surface.gifBytes,
          boreholeGifBytes: borehole?.gifBytes,
          dataTime: jst,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final jsonFile = File('${dir.path}\\$stamp.json');
      if (jsonFile.existsSync()) {
        final data = await _readJsonFile(jsonFile);
        final rtData = data['realTimeData'] as Map<String, dynamic>?;
        final intensityStr = rtData?['intensity'] as String?;
        if (intensityStr != null) {
          final now = DateTime.now();
          for (int idx = 0;
              idx < yahooStations.length && idx < intensityStr.length;
              idx++) {
            final detectLevel = intensityStr.codeUnitAt(idx) - 100;
            final level = JpShindoScale.levelFromKanameishiLevel(detectLevel);
            final station = yahooStations[idx];
            station.update(level, newDetectLevel: detectLevel);
            station.lastUpdate = now;
          }
        }
      }

      for (final code in watchCodes) {
        final gifStation = gifStations.cast<NiedStation?>().firstWhere(
          (s) => s?.code == code,
          orElse: () => null,
        );
        final yahooStation = yahooStations.cast<NiedStation?>().firstWhere(
          (s) => s?.code == code,
          orElse: () => null,
        );
        print(_gifLine(jst, gifStation));
        print(_yahooLine(jst, yahooStation));
      }
      print('---');
    }

    await gifSub.cancel();
    gifService.stop();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
