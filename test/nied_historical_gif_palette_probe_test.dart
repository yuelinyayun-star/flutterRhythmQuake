import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

const _zipPath = String.fromEnvironment('NIED_HISTORICAL_GIF_ZIP');
const _sampleStride = int.fromEnvironment(
  'NIED_HISTORICAL_GIF_SAMPLE_STRIDE',
  defaultValue: 10,
);

void main() {
  test(
    'probes provided historical NIED jma_s and acmap_s GIF palette compatibility',
    () async {
      final zipFile = File(_zipPath);
      expect(zipFile.existsSync(), isTrue, reason: 'Missing historical ZIP');

      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      final entries = archive.files
          .where(
            (entry) =>
                entry.isFile &&
                RegExp(
                  r'^\d{6}/(?:jma_s|acmap_s)/\d{14}_\d+\.gif$',
                ).hasMatch(entry.name),
          )
          .toList(growable: false);
      expect(entries, isNotEmpty);

      final report = <String, Object?>{};
      for (final dateDirectory
          in entries
              .map((entry) => entry.name.split('/').first)
              .toSet()
              .toList()
            ..sort()) {
        final groupEntries = entries
            .where((entry) => entry.name.startsWith('$dateDirectory/'))
            .toList(growable: false);
        final layers = <String, List<ArchiveFile>>{};
        for (final entry in groupEntries) {
          final layer = entry.name.split('/')[1];
          (layers[layer] ??= <ArchiveFile>[]).add(entry);
        }
        expect(layers.keys, containsAll(const ['jma_s', 'acmap_s']));
        for (final entriesForLayer in layers.values) {
          entriesForLayer.sort((a, b) => a.name.compareTo(b.name));
        }

        final jma = await _probeLayer(layers['jma_s']!, isJma: true);
        final pga = await _probeLayer(layers['acmap_s']!, isJma: false);
        report[dateDirectory] = {
          'jma_s': jma.toJson(),
          'acmap_s': pga.toJson(),
        };
      }

      // This is a data probe, not a calibration assertion. The JSON is kept in
      // test output so old palettes can be evaluated before any decoder change.
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(report));
    },
    skip: _zipPath.isEmpty
        ? 'Pass --dart-define=NIED_HISTORICAL_GIF_ZIP=<path to GIFS.zip>.'
        : false,
  );
}

Future<_LayerProbe> _probeLayer(
  List<ArchiveFile> entries, {
  required bool isJma,
}) async {
  final stride = _sampleStride < 1 ? 1 : _sampleStride;
  final positions = NiedScanPositions.positions.values.toList(growable: false);
  var sampledFrameCount = 0;
  var maximumDecodableStations = 0;
  var maximumShindo = -3.0;
  var maximumPga = 0.0;
  var pgaSaturatedStationSamples = 0;
  final frameCoverage = <int>[];

  for (var index = 0; index < entries.length; index += stride) {
    final pixels = await _decodeGif(entries[index]);
    expect(pixels.width, 352);
    expect(pixels.height, 400);
    sampledFrameCount += 1;

    var decodable = 0;
    for (final position in positions) {
      final x = position[0];
      final y = position[1];
      if (x < 0 || x >= pixels.width || y < 0 || y >= pixels.height) {
        continue;
      }
      final rgb = pixels.packedRgb[y * pixels.width + x];
      final colorPosition = ShindoColorUtil.rgbaToPosition(
        (rgb >> 16) & 0xff,
        (rgb >> 8) & 0xff,
        rgb & 0xff,
      );
      if (colorPosition == null) continue;
      decodable += 1;
      if (isJma) {
        final observation = NiedGifValueDecoder.decodeObservationFromPosition(
          colorPosition,
          layer: NiedGifLayer.realtimeShindo,
        );
        final shindo = observation.shindo;
        if (shindo != null) {
          maximumShindo = maximumShindo > shindo ? maximumShindo : shindo;
        }
      } else {
        final pga = NiedGifValueDecoder.decodeObservationFromPosition(
          colorPosition,
          layer: NiedGifLayer.peakAcceleration,
        ).pga;
        if (pga != null && pga > maximumPga) maximumPga = pga;
        if (colorPosition >= 0.999) pgaSaturatedStationSamples += 1;
      }
    }
    frameCoverage.add(decodable);
    if (decodable > maximumDecodableStations) {
      maximumDecodableStations = decodable;
    }
  }

  return _LayerProbe(
    sourceFrameCount: entries.length,
    sampledFrameCount: sampledFrameCount,
    sampleStride: stride,
    maximumDecodableStations: maximumDecodableStations,
    medianDecodableStations: _median(frameCoverage),
    maximumContinuousShindo: isJma ? maximumShindo : null,
    maximumJmaIndex: isJma
        ? JpShindoScale.jmaIndexFromShindo(maximumShindo)
        : null,
    maximumPgaGal: isJma ? null : maximumPga,
    pgaSaturatedStationSamples: isJma ? null : pgaSaturatedStationSamples,
  );
}

Future<_DecodedGif> _decodeGif(ArchiveFile entry) async {
  final bytes = Uint8List.fromList(entry.content as List<int>);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) {
    image.dispose();
    codec.dispose();
    throw StateError('Unable to decode ${entry.name}');
  }
  final packedRgb = List<int>.filled(image.width * image.height, 0);
  for (var index = 0; index < packedRgb.length; index++) {
    final offset = index * 4;
    packedRgb[index] =
        (pixels.getUint8(offset) << 16) |
        (pixels.getUint8(offset + 1) << 8) |
        pixels.getUint8(offset + 2);
  }
  final result = _DecodedGif(
    width: image.width,
    height: image.height,
    packedRgb: packedRgb,
  );
  image.dispose();
  codec.dispose();
  return result;
}

double _median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = List<int>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

class _DecodedGif {
  const _DecodedGif({
    required this.width,
    required this.height,
    required this.packedRgb,
  });

  final int width;
  final int height;
  final List<int> packedRgb;
}

class _LayerProbe {
  const _LayerProbe({
    required this.sourceFrameCount,
    required this.sampledFrameCount,
    required this.sampleStride,
    required this.maximumDecodableStations,
    required this.medianDecodableStations,
    required this.maximumContinuousShindo,
    required this.maximumJmaIndex,
    required this.maximumPgaGal,
    required this.pgaSaturatedStationSamples,
  });

  final int sourceFrameCount;
  final int sampledFrameCount;
  final int sampleStride;
  final int maximumDecodableStations;
  final double medianDecodableStations;
  final double? maximumContinuousShindo;
  final int? maximumJmaIndex;
  final double? maximumPgaGal;
  final int? pgaSaturatedStationSamples;

  Map<String, Object?> toJson() => {
    'sourceFrameCount': sourceFrameCount,
    'sampledFrameCount': sampledFrameCount,
    'sampleStride': sampleStride,
    'maximumDecodableStations': maximumDecodableStations,
    'medianDecodableStations': medianDecodableStations,
    'maximumContinuousShindo': maximumContinuousShindo,
    'maximumJmaIndex': maximumJmaIndex,
    'maximumPgaGal': maximumPgaGal,
    'pgaSaturatedStationSamples': pgaSaturatedStationSamples,
  };
}
