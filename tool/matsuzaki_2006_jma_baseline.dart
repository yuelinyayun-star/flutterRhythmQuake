import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputs = _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_jma_baseline',
  );
  final inputPaths = inputs.isEmpty
      ? const [
          'tmp/jma_intensity_pretraining/jma_final_intensity_2020.json',
          'tmp/jma_intensity_pretraining/jma_final_intensity_2021.json',
          'tmp/jma_intensity_pretraining/jma_final_intensity_2022.json',
        ]
      : inputs;
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final datasets = [
    for (final path in inputPaths)
      jsonDecode(File(path).readAsStringSync(encoding: utf8))
          as Map<String, Object?>,
  ];
  final result = const Matsuzaki2006JmaBaselineEvaluator().evaluate(datasets);
  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(result.toJson()),
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(result.toMarkdown(), encoding: utf8);

  final summary = result.overallResidualSummary;
  stdout.writeln(
    'events=${result.events.length}/${result.inputEventCount}, '
    'stations=${summary.count}, '
    'mean=${summary.meanResidual.toStringAsFixed(3)}, '
    'mae=${summary.meanAbsoluteResidual.toStringAsFixed(3)}, '
    'rms=${summary.rootMeanSquareResidual.toStringAsFixed(3)}',
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

List<String> _values(List<String> arguments, String name) {
  final values = <String>[];
  for (var index = 0; index < arguments.length - 1; index++) {
    if (arguments[index] == name) values.add(arguments[index + 1]);
  }
  return values;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}
