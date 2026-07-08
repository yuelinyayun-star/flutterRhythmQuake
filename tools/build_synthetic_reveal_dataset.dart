import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';

void main(List<String> args) {
  final outputDirectory = _argument(args, '--output');
  final splitPath = _argument(args, '--splits');
  final inputs = _arguments(args, '--input');
  if (outputDirectory == null || splitPath == null || inputs.isEmpty) {
    stderr.writeln(
      'Usage: dart run tools/build_synthetic_reveal_dataset.dart '
      '--input <annual.json> [--input <annual.json> ...] '
      '--splits <splits.json> --output <directory>',
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
  final splitFile = File(splitPath);
  if (!splitFile.existsSync()) {
    stderr.writeln('Split manifest does not exist: ${splitFile.path}');
    exitCode = 66;
    return;
  }
  final splitManifest =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final result = const SyntheticRevealDatasetBuilder().build(
    annualDatasets: annualDatasets,
    splitManifest: splitManifest,
  );
  final output = Directory(outputDirectory)..createSync(recursive: true);
  _writeJson(
    File('${output.path}/synthetic_reveal_manifest.json'),
    result.manifest,
  );
  for (final entry in result.datasetsBySplit.entries) {
    _writeJson(
      File('${output.path}/synthetic_reveal_${entry.key}.json'),
      entry.value,
    );
  }
  _writeJson(
    File('${output.path}/synthetic_reveal_quality_report.json'),
    result.qualityReport,
  );
  File(
    '${output.path}/synthetic_reveal_quality_report.md',
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
