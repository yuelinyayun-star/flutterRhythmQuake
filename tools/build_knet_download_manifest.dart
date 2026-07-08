import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/knet_waveform_event_manifest.dart';

void main(List<String> args) {
  final inputPath = _argument(args, '--input');
  final outputPath = _argument(args, '--output');
  final collections = _arguments(
    args,
    '--collection',
  ).map(_collection).toList(growable: false);
  final formats = _arguments(args, '--format');

  if (inputPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/build_knet_download_manifest.dart '
      '--input <events.json> --output <manifest.json> '
      '[--collection all|knet|kik|kik0] [--format ascii|csv]',
    );
    exitCode = 64;
    return;
  }

  final input = jsonDecode(File(inputPath).readAsStringSync());
  final eventObjects = input is List<Object?>
      ? input
      : (input as Map<String, Object?>)['events']! as List<Object?>;
  final events = eventObjects
      .cast<Map<String, Object?>>()
      .map(parseKnetWaveformEventCandidate)
      .toList(growable: false);
  final planner = KnetWaveformDownloadPlanner();
  final plan = planner.buildPlan(
    events,
    collections: collections.isEmpty
        ? const [
            KnetDownloadCollection.all,
            KnetDownloadCollection.knet,
            KnetDownloadCollection.kik,
          ]
        : collections,
    formats: formats.isEmpty ? const ['ascii', 'csv'] : formats,
  );

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(plan.toJson()),
  );
  stdout.writeln(
    'wrote ${events.length} K-NET/KiK-net download events to $outputPath',
  );
}

KnetDownloadCollection _collection(String value) {
  return KnetDownloadCollection.values.firstWhere(
    (collection) => collection.name == value,
    orElse: () => throw FormatException('Unknown collection: $value'),
  );
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
