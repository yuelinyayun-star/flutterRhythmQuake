import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';
import 'package:image/image.dart' as image_lib;

void main(List<String> args) {
  final captureDirectory = _argument(args, '--capture');
  final outputPath = _argument(args, '--output');
  final markdownPath = _argument(args, '--markdown');
  if (captureDirectory == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/build_nied_layer_alignment_report.dart '
      '--capture <directory> --output <report.json> [--markdown <report.md>]',
    );
    exitCode = 64;
    return;
  }

  final capture = Directory(captureDirectory);
  final manifest =
      jsonDecode(
            File(
              '${capture.path}${Platform.pathSeparator}capture_manifest.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final records = (manifest['records']! as List<Object?>)
      .cast<Map<String, Object?>>();
  const layerIds = ['jma', 'acmap', 'vcmap', 'dcmap'];
  final recordsByTime = <String, Map<String, Map<String, Object?>>>{};
  for (final record in records) {
    if (record['ok'] != true) continue;
    final observedAt = record['observedAt']! as String;
    recordsByTime.putIfAbsent(
      observedAt,
      () => {},
    )[record['layer']! as String] = record;
  }
  final rows = <Map<String, Object?>>[];
  final decodedLayerKeys = <String>{};
  final sortedTimes = recordsByTime.keys.toList(growable: false)..sort();
  for (final observedAt in sortedTimes) {
    final decoded = <String, image_lib.Image>{};
    for (final layerId in layerIds) {
      for (final suffix in const ['s', 'b']) {
        final key = '${layerId}_$suffix';
        final record = recordsByTime[observedAt]![key];
        if (record == null) continue;
        final file = File(
          '${capture.path}${Platform.pathSeparator}${record['file']}',
        );
        final image = image_lib.decodeImage(file.readAsBytesSync());
        if (image != null) {
          decoded[key] = image;
          decodedLayerKeys.add(key);
        }
      }
    }
    for (final station in NiedStationDb.stations) {
      final code = station['code'] as String;
      final position = NiedScanPositions.positions[code];
      if (position == null) continue;
      const suffix = 's';
      final values = <String, double?>{};
      for (final layerId in layerIds) {
        values[layerId] = _positionAt(
          decoded['${layerId}_$suffix'],
          position[0],
          position[1],
        );
      }
      rows.add({
        'observedAt': observedAt,
        'stationCode': code,
        'sensorRole': 'surface',
        ...values,
      });
    }
  }

  final stationCodes = rows.map((row) => row['stationCode']! as String).toSet();
  final complete = rows
      .where((row) => layerIds.every((layer) => row[layer] is double))
      .toList(growable: false);
  final pairMetrics = <String, Object?>{};
  for (final layerId in layerIds.skip(1)) {
    final pairs = rows
        .where((row) => row['jma'] is double && row[layerId] is double)
        .map((row) => (row['jma']! as double, row[layerId]! as double))
        .toList(growable: false);
    pairMetrics['jma_vs_$layerId'] = {
      'stationSecondCount': pairs.length,
      'colorPositionMae': _mean(pairs.map((pair) => (pair.$1 - pair.$2).abs())),
      'colorPositionCorrelation': _correlation(pairs),
    };
  }

  final report = <String, Object?>{
    'schemaVersion': 'nied_layer_alignment_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'captureDirectory': captureDirectory,
    'decoderVersion': manifest['decoderVersion'],
    'startTimeJst': manifest['startTimeJst'],
    'endTimeJst': manifest['endTimeJst'],
    'timestampCount': sortedTimes.length,
    'layers': decodedLayerKeys.toList(growable: false)..sort(),
    'stationCount': stationCodes.length,
    'stationSecondCount': rows.length,
    'completeStationSecondCount': complete.length,
    'completeStationRate': rows.isEmpty ? 0 : complete.length / rows.length,
    'decodableByLayer': {
      for (final layerId in layerIds)
        layerId: rows.where((row) => row[layerId] is double).length,
    },
    'pairMetrics': pairMetrics,
    'limitations': const [
      'pixel_sampling_uses_project_station_coordinates',
      'correlation_does_not_imply_interchangeable_physical_quantities',
    ],
  };

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  if (markdownPath != null) {
    final markdown = File(markdownPath)..parent.createSync(recursive: true);
    markdown.writeAsStringSync(_markdown(report));
  }
  stdout.writeln(
    'wrote layer alignment report for ${rows.length} station-seconds '
    '(${complete.length} complete)',
  );
}

double? _positionAt(image_lib.Image? image, int x, int y) {
  if (image == null ||
      x < 0 ||
      y < 0 ||
      x >= image.width ||
      y >= image.height) {
    return null;
  }
  final pixel = image.getPixel(x, y);
  final position = ShindoColorUtil.rgbaToPosition(
    pixel.r.toInt(),
    pixel.g.toInt(),
    pixel.b.toInt(),
  );
  return position != null && position.isFinite ? position : null;
}

double? _mean(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    sum += value;
    count++;
  }
  return count == 0 ? null : sum / count;
}

double? _correlation(List<(double, double)> pairs) {
  if (pairs.length < 2) return null;
  final meanX = _mean(pairs.map((pair) => pair.$1))!;
  final meanY = _mean(pairs.map((pair) => pair.$2))!;
  var covariance = 0.0;
  var varianceX = 0.0;
  var varianceY = 0.0;
  for (final pair in pairs) {
    final x = pair.$1 - meanX;
    final y = pair.$2 - meanY;
    covariance += x * y;
    varianceX += x * x;
    varianceY += y * y;
  }
  final denominator = math.sqrt(varianceX * varianceY);
  return denominator <= 0 ? null : covariance / denominator;
}

String _markdown(Map<String, Object?> report) {
  final decodable = report['decodableByLayer']! as Map<String, Object?>;
  final pairs = report['pairMetrics']! as Map<String, Object?>;
  final timestampCount = report['timestampCount']! as int;
  final buffer = StringBuffer()
    ..writeln(
      timestampCount > 1
          ? '# NIED Event Layer Alignment'
          : '# NIED Layer Alignment Probe',
    )
    ..writeln()
    ..writeln(
      '- Window: `${report['startTimeJst']}` to `${report['endTimeJst']}`',
    )
    ..writeln('- Decoder: `${report['decoderVersion']}`')
    ..writeln('- Timestamps: ${report['timestampCount']}')
    ..writeln('- Stations: ${report['stationCount']}')
    ..writeln('- Station-seconds: ${report['stationSecondCount']}')
    ..writeln(
      '- Complete four-layer station-seconds: '
      '${report['completeStationSecondCount']} '
      '(${((report['completeStationRate']! as num) * 100).toStringAsFixed(1)}%)',
    )
    ..writeln()
    ..writeln('| Layer | Decodable station-seconds |')
    ..writeln('|---|---:|');
  for (final entry in decodable.entries) {
    buffer.writeln('| `${entry.key}` | ${entry.value} |');
  }
  buffer
    ..writeln()
    ..writeln('| Pair | Station-seconds | Position MAE | Correlation |')
    ..writeln('|---|---:|---:|---:|');
  for (final entry in pairs.entries) {
    final value = entry.value! as Map<String, Object?>;
    buffer.writeln(
      '| `${entry.key}` | ${value['stationSecondCount']} | '
      '${_format(value['colorPositionMae'])} | '
      '${_format(value['colorPositionCorrelation'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'The layers are distinct physical quantities and must not be treated '
      'as interchangeable even when their color positions correlate.',
    );
  return buffer.toString();
}

String _format(Object? value) => value is num ? value.toStringAsFixed(4) : '-';

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
