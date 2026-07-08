import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/jma_hypocenter_record.dart';

void main(List<String> args) {
  final inputPath = _argument(args, '--input');
  final outputPath = _argument(args, '--output');
  final catalogId = _argument(args, '--catalog-id');
  final revision = _argument(args, '--revision');
  final sourceUrl = _argument(args, '--source-url');
  if ([inputPath, outputPath, catalogId, revision, sourceUrl].contains(null)) {
    stderr.writeln(
      'Usage: dart run tools/import_jma_hypocenter.dart '
      '--input <hypocenter-file> --output <catalog.json> '
      '--catalog-id <id> --revision <revision> --source-url <official-url>',
    );
    exitCode = 64;
    return;
  }

  final bytes = File(inputPath!).readAsBytesSync();
  final lines = latin1
      .decode(bytes, allowInvalid: true)
      .split(RegExp(r'\r?\n'));
  const parser = JmaHypocenterRecordParser();
  final events = lines.map(parser.parse).nonNulls.toList(growable: false);
  final output = {
    'schemaVersion': 1,
    'catalogId': catalogId,
    'revision': revision,
    'sourceUrl': sourceUrl,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'events': events.map((event) => event.toJson()).toList(growable: false),
  };
  final outputFile = File(outputPath!);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln(jsonEncode({'events': events.length, 'output': outputPath}));
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
