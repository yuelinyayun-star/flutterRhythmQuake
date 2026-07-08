import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_features.dart';

void main(List<String> args) {
  final inputs = _arguments(args, '--input');
  final outputPath = _argument(args, '--output');
  final includeChannelSamples = args.contains('--include-channel-samples');

  if (inputs.isEmpty || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/build_knet_waveform_features.dart '
      '--input <ascii|csv|zip> [--input <...>] --output <features.json> '
      '[--include-channel-samples]',
    );
    exitCode = 64;
    return;
  }

  final parser = KnetWaveformArchiveParser();
  final channels = <KnetWaveformChannel>[];
  for (final input in inputs) {
    final file = File(input);
    if (!file.existsSync()) {
      throw FileSystemException('Input not found', input);
    }
    channels.addAll(_parseInput(parser, file));
  }

  final extractor = KnetWaveformFeatureExtractor();
  final features = extractor.extract(channels);
  final output = {
    'schema': 'knet_waveform_feature_package_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputs': inputs,
    'channelCount': channels.length,
    'seriesCount': features.length,
    'parserVersion': knetWaveformParserVersion,
    'featureVersion': knetWaveformFeatureVersion,
    'qualityNotes': [
      'PGA is computed from offset-corrected vector acceleration.',
      'PGV is integrated from offset-corrected acceleration without instrument response correction.',
      'jmaIntensityApprox is an unfiltered 0.3s duration proxy, not official JMA instrumental intensity.',
    ],
    'channels': channels
        .map((channel) => channel.toJson(includeSamples: includeChannelSamples))
        .toList(),
    'features': features.map((series) => series.toJson()).toList(),
  };

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(output),
  );
  stdout.writeln(
    'wrote ${features.length} feature series from ${channels.length} channels to $outputPath',
  );
}

List<KnetWaveformChannel> _parseInput(
  KnetWaveformArchiveParser parser,
  File file,
) {
  final path = file.path;
  final lower = path.toLowerCase();
  if (lower.endsWith('.zip')) {
    return parser.parseZipBytes(file.readAsBytesSync(), sourcePath: path);
  }

  final text = file.readAsStringSync();
  if (lower.endsWith('.csv')) {
    return parser.parseCsv(text, sourcePath: path);
  }
  if (RegExp(r'\.(ns|ew|ud|ns1|ew1|ud1|ns2|ew2|ud2)$').hasMatch(lower)) {
    return [parser.parseAscii(text, sourcePath: path)];
  }
  throw FormatException('Unsupported K-NET/KiK-net waveform input: $path');
}

List<String> _arguments(List<String> args, String name) {
  final values = <String>[];
  for (var index = 0; index < args.length - 1; index++) {
    if (args[index] == name) values.add(args[index + 1]);
  }
  return values;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
