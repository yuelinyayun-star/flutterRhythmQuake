import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';

void main(List<String> args) {
  final outputDirectory = _argument(args, '--output');
  final inputs = _arguments(args, '--input');
  if (outputDirectory == null || inputs.isEmpty) {
    stderr.writeln(
      'Usage: dart run tools/build_jma_intensity_dataset.dart '
      '--input <annual.json> [--input <annual.json> ...] --output <directory>',
    );
    exitCode = 64;
    return;
  }

  final annualDatasets = <Map<String, Object?>>[];
  for (final input in inputs) {
    final file = File(input);
    if (!file.existsSync()) {
      stderr.writeln('Input does not exist: ${file.path}');
      exitCode = 66;
      return;
    }
    annualDatasets.add(decodeJmaIntensityDataset(file.readAsStringSync()));
  }

  final result = const JmaIntensityDatasetBuilder().build(annualDatasets);
  final output = Directory(outputDirectory)..createSync(recursive: true);
  _writeJson(File('${output.path}/dataset_manifest.json'), result.manifest);
  _writeJson(File('${output.path}/splits.json'), result.splits);
  _writeJson(File('${output.path}/quality_report.json'), result.qualityReport);
  File(
    '${output.path}/quality_report.md',
  ).writeAsStringSync(result.qualityReportMarkdown());
  stdout.writeln(jsonEncode(result.qualityReport['totals']));
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

void _writeJson(File file, Map<String, Object?> value) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}
