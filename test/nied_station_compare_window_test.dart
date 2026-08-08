// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

import 'support/nied_replay_fixture.dart';

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
      ? JpShindoScale.rawShindoFromKanameishiLevel(
          station.level,
        ).toStringAsFixed(2)
      : '--';
  final cont = station.level >= 0
      ? station.continuousShindo.toStringAsFixed(3)
      : '--';
  return '$hhmmss GIF ${station.code} cont=$cont level=${station.level} '
      'shindo=$display';
}

String _yahooLine(DateTime jst, NiedStation? station) {
  final hhmmss =
      '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}:${jst.second.toString().padLeft(2, '0')}';
  if (station == null) return '$hhmmss Yahoo missing';
  final display = station.level >= 0
      ? JpShindoScale.rawShindoFromKanameishiLevel(
          station.level,
        ).toStringAsFixed(2)
      : '--';
  final midpoint = station.level >= 0
      ? _kanameishiMidpointShindo(station.level).toStringAsFixed(2)
      : '--';
  return '$hhmmss Yahoo ${station.code} midpoint=$midpoint '
      'level=${station.level} shindo=$display';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'print GIF vs Yahoo station values around 2026-06-09 18:52 JST',
    () async {
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

      final yahooStations = await buildYahooReplayStations(
        File('${dir.path}\\sitelist.json'),
      );

      print('');
      print('=== Station compare 2026-06-09 18:52 JST ===');
      for (var i = 0; i < seconds; i++) {
        final jst = start.add(Duration(seconds: i));
        final stamp = formatNiedTimeKey(jst);

        final surface = await decodeNiedGifFile(
          File('${dir.path}\\$stamp.jma_s.gif'),
        );
        final borehole = await decodeNiedGifFile(
          File('${dir.path}\\$stamp.jma_b.gif'),
        );
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
          final data = await readNiedJsonFile(jsonFile);
          applyYahooReplayFrame(yahooStations, data, jst);
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
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
