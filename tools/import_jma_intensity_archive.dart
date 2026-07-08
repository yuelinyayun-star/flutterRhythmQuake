import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/jma_intensity_archive.dart';

void main(List<String> args) {
  final intensityPath = _argument(args, '--intensity');
  final stationsPath = _argument(args, '--stations');
  final outputPath = _argument(args, '--output');
  final sourceUrl = _argument(args, '--source-url');
  final year = int.tryParse(_argument(args, '--year') ?? '');
  if (intensityPath == null ||
      stationsPath == null ||
      outputPath == null ||
      sourceUrl == null ||
      year == null) {
    stderr.writeln(
      'Usage: dart run tools/import_jma_intensity_archive.dart '
      '--intensity <iYYYY.dat> --stations <code_p.dat> '
      '--output <dataset.json> --year <YYYY> --source-url <official-url>',
    );
    exitCode = 64;
    return;
  }

  final stations = const JmaIntensityStationTableParser().parse(
    File(stationsPath).readAsBytesSync(),
  );
  final events = const JmaIntensityArchiveParser().parse(
    File(intensityPath).readAsBytesSync(),
  );
  final observedStationIds = {
    for (final event in events)
      for (final observation in event.observations) observation.stationId,
  };
  final missingStationIds = observedStationIds.difference(
    stations.keys.toSet(),
  );
  final output = {
    'schemaVersion': 1,
    'datasetId': 'jma_final_intensity_$year',
    'domain': 'jma_final_intensity',
    'year': year,
    'source': 'JMA earthquake monthly catalog intensity archive',
    'sourceUrl': sourceUrl,
    'importedAt': DateTime.now().toUtc().toIso8601String(),
    'processingVersion': 'jma_intensity_archive_v1',
    'stationTable': {
      'stationCount': stations.length,
      'observedStationCount': observedStationIds.length,
      'missingStationIds': missingStationIds.toList()..sort(),
    },
    'events': events
        .map((event) => event.toJson(stations))
        .toList(growable: false),
  };
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'events': events.length,
      'stations': stations.length,
      'observedStations': observedStationIds.length,
      'missingStations': missingStationIds.length,
      'output': outputFile.path,
    }),
  );
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
