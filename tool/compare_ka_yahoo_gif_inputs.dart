import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/intensity_reconstruction.dart';

void main(List<String> arguments) {
  final directories = _values(arguments, '--capture');
  final outputPath = _value(arguments, '--output');
  if (directories.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/compare_ka_yahoo_gif_inputs.dart '
      '--capture <directory> [--capture <directory> ...] '
      '[--output <report.json>]',
    );
    exitCode = 64;
    return;
  }

  const extractor = KaCaptureInputExtractor();
  final reports = [
    for (final directory in directories) extractor.compareDirectory(directory),
  ];
  final output = {
    'schemaVersion': 'ka_yahoo_gif_input_comparison_collection_v1',
    'reports': reports
        .map((report) => report.toJson(includePairs: true))
        .toList(),
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(output);
  if (outputPath == null) {
    stdout.writeln(encoded);
    return;
  }
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(encoded, encoding: utf8);
  for (final report in reports) {
    stdout.writeln(
      '${report.eventId}: pairs=${report.pairs.length}, '
      'exact=${(report.exactMatchRate * 100).toStringAsFixed(2)}%, '
      'meanDelta=${report.meanDifference.toStringAsFixed(3)}, '
      'rmse=${report.rmse.toStringAsFixed(3)}, '
      'unmatchedYahoo=${report.unmatchedYahooCount}, '
      'unmatchedGif=${report.unmatchedGifCount}',
    );
  }
  stdout.writeln('wrote ${outputFile.path}');
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
