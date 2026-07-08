import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/nied_gif_observation_export.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('exports surface jma_s observations from a capture package', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nied_gif_observation_export_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final gifFile = File(
      '${tempDir.path}${Platform.pathSeparator}sample.jma_s.gif',
    );
    final image = image_lib.Image(width: 352, height: 400);
    image.clear(image_lib.ColorRgb8(0, 0, 0));
    image.setPixelRgb(166, 268, 0, 255, 134);
    gifFile.writeAsBytesSync(Uint8List.fromList(image_lib.encodePng(image)));

    final manifest = {
      'caseId': 'test_case',
      'decoderVersion': 'nied_gif_shindo_v1',
      'stationDbVersion': 'kanameishi_niedsitepub_1749_v1',
      'sensorSelectionPolicy': 'surface_default_v1',
      'records': [
        {
          'observedAt': '2026-06-20T21:24:57+09:00',
          'layer': 'jma_s',
          'file': 'sample.jma_s.gif',
          'ok': true,
          'qualityFlags': ['from_test'],
        },
      ],
    };
    File(
      '${tempDir.path}${Platform.pathSeparator}capture_manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

    final exported = const NiedGifObservationExporter()
        .exportFromCaptureDirectory(tempDir.path);

    expect(exported['schemaVersion'], niedGifStationSecondObservationsVersion);
    expect(exported['sourceLayer'], 'jma_s');
    expect(exported['sensorRole'], 'surface');
    final observations = (exported['observations']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final aic001 = observations.firstWhere(
      (row) => row['stationCode'] == 'AIC001',
    );
    final expectedShindo = NiedGifValueDecoder.decodeObservationFromRgba(
      0,
      255,
      134,
      layer: NiedGifLayer.realtimeShindo,
    )!.shindo!;
    expect(aic001['observedAtUtc'], '2026-06-20T12:24:57.000Z');
    expect(aic001['gifDecodedShindo'], closeTo(expectedShindo, 1e-9));
    expect(aic001['sensorRole'], 'surface');
    expect(aic001['qualityFlags'], ['from_test']);
  });
}
