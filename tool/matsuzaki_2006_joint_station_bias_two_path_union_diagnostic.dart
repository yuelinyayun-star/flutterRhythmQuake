import 'dart:convert';
import 'dart:io';

const _modelNames = <String>['published', 'finiteFaultSemanticFrozen2017'];

void main(List<String> arguments) {
  final baselinePath = _value(arguments, '--baseline-report');
  final hardCoarsePath = _value(arguments, '--hard-coarse-report');
  final outputDirectoryPath =
      _value(arguments, '--output-dir') ??
      '.dart_tool/matsuzaki_2006_joint_station_bias_two_path_union_diagnostic';
  if (baselinePath == null || hardCoarsePath == null) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_joint_station_bias_two_path_union_diagnostic.dart '
      '--baseline-report <station-bias-report.json> '
      '--hard-coarse-report <hard-coarse-report.json> '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }

  final baseline = _readJsonMap(baselinePath);
  final hardCoarse = _readJsonMap(hardCoarsePath);
  final baselineEvents = _eventsById(baseline);
  final hardCoarseEvents = _eventsById(hardCoarse);
  if (!baselineEvents.keys.toSet().containsAll(hardCoarseEvents.keys) ||
      !hardCoarseEvents.keys.toSet().containsAll(baselineEvents.keys)) {
    throw StateError(
      'Baseline and hard-coarse reports contain different events.',
    );
  }

  final eventRows = <Map<String, Object?>>[];
  for (final eventId in baselineEvents.keys.toList()..sort()) {
    final baselineEvent = baselineEvents[eventId]!;
    final hardCoarseEvent = hardCoarseEvents[eventId]!;
    final modelRows = <String, Object?>{};
    for (final modelName in _modelNames) {
      final baselineModel = _map(baselineEvent['models'], '$eventId.models');
      final baselineResult = _map(
        baselineModel[modelName],
        '$eventId.$modelName',
      );
      final hardModel = _map(hardCoarseEvent['models'], '$eventId.hard.models');
      final hardModelDiagnostic = _map(
        hardModel[modelName],
        '$eventId.hard.$modelName',
      );
      final hardStart = _map(
        hardModelDiagnostic['hardCoarseStart'],
        '$eventId.hard.$modelName.hardCoarseStart',
      );
      final hardResult = _map(
        hardStart['stationBias'],
        '$eventId.hard.$modelName.stationBias',
      );
      final hardCandidate = _map(
        hardResult['bestCandidate'],
        '$eventId.hard.$modelName.stationBias.bestCandidate',
      );

      final baselineRms = _number(baselineResult['minimumIntensityRms']);
      final hardRms = _number(hardCandidate['intensityRms']);
      if (baselineRms == null || hardRms == null) {
        throw StateError('Missing station-bias RMS for $eventId/$modelName.');
      }
      final chooseHard = hardRms < baselineRms;
      final selectedStatus = chooseHard
          ? hardResult['status']
          : baselineResult['status'];
      final baselineEpicentralError = _number(
        baselineResult['epicentralErrorKmMaximumEquivalent'],
      );
      final selectedEpicentralError = chooseHard
          ? _number(hardResult['epicentralErrorKm'])
          : baselineEpicentralError;
      final baselineDepthError = _number(
        baselineResult['depthAbsoluteErrorKmMaximumEquivalent'],
      );
      final selectedDepthError = chooseHard
          ? _number(hardResult['depthAbsoluteErrorKm'])
          : baselineDepthError;
      final baselineMagnitudeError = _number(
        baselineResult['magnitudeAbsoluteErrorMaximumEquivalent'],
      );
      final selectedMagnitudeError = chooseHard
          ? _number(hardResult['magnitudeAbsoluteError'])
          : baselineMagnitudeError;
      final baselineElapsed = _number(baselineResult['elapsedMilliseconds']);
      final hardElapsed = _number(hardResult['elapsedMilliseconds']);
      final unionElapsed = baselineElapsed == null || hardElapsed == null
          ? null
          : baselineElapsed + hardElapsed;

      modelRows[modelName] = <String, Object?>{
        'baselineIntensityRms': baselineRms,
        'hardCoarseIntensityRms': hardRms,
        'selectedPath': chooseHard ? 'hardCoarseStart' : 'baseline',
        'selectedStatus': selectedStatus,
        'selectedIntensityRms': chooseHard ? hardRms : baselineRms,
        'baselineEpicentralErrorKm': baselineEpicentralError,
        'selectedEpicentralErrorKm': selectedEpicentralError,
        'epicentralErrorDeltaFromBaselineKm': _difference(
          selectedEpicentralError,
          baselineEpicentralError,
        ),
        'baselineDepthAbsoluteErrorKm': baselineDepthError,
        'selectedDepthAbsoluteErrorKm': selectedDepthError,
        'depthAbsoluteErrorDeltaFromBaselineKm': _difference(
          selectedDepthError,
          baselineDepthError,
        ),
        'baselineMagnitudeAbsoluteError': baselineMagnitudeError,
        'selectedMagnitudeAbsoluteError': selectedMagnitudeError,
        'magnitudeAbsoluteErrorDeltaFromBaseline': _difference(
          selectedMagnitudeError,
          baselineMagnitudeError,
        ),
        'baselineElapsedMilliseconds': baselineElapsed,
        'hardCoarseElapsedMilliseconds': hardElapsed,
        'unionElapsedMilliseconds': unionElapsed,
        'additionalElapsedMilliseconds':
            unionElapsed == null || baselineElapsed == null
            ? null
            : unionElapsed - baselineElapsed,
      };
    }
    eventRows.add(<String, Object?>{'eventId': eventId, 'models': modelRows});
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_joint_station_bias_two_path_union_v1',
    'baselineReportPath': baselinePath,
    'hardCoarseReportPath': hardCoarsePath,
    'protocolStatus': baseline['protocolStatus'],
    'strategy': {
      'name': 'two_path_best_of_returned_candidates',
      'paths': ['baseline', 'hardCoarseStart'],
      'selection': 'choose lower frozen-station-bias intensity RMS',
      'tieRule': 'keep baseline when RMS is equal',
      'truthUsedForSelection': false,
      'scope':
          'The union contains only the best returned candidate from each path; '
          'it is not a full candidate-set union.',
    },
    'eventCount': eventRows.length,
    'modelSummaries': {
      for (final modelName in _modelNames)
        modelName: _summary(eventRows, modelName),
    },
    'events': eventRows,
  };

  final outputDirectory = Directory(outputDirectoryPath)
    ..createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json')
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
      encoding: utf8,
    );
  final markdownFile = File('${outputDirectory.path}/report.md')
    ..writeAsStringSync(_markdown(report), encoding: utf8);
  stdout.writeln(jsonEncode(report['modelSummaries']));
  stdout.writeln('wrote ${jsonFile.path}');
  stdout.writeln('wrote ${markdownFile.path}');
}

Map<String, Object?> _summary(
  List<Map<String, Object?>> events,
  String modelName,
) {
  final rows = <Map<String, Object?>>[];
  for (final event in events) {
    final models = _map(event['models'], '${event['eventId']}.models');
    rows.add(_map(models[modelName], '${event['eventId']}.$modelName'));
  }
  final epicentralDeltas = _numbers(rows, 'epicentralErrorDeltaFromBaselineKm');
  final depthDeltas = _numbers(rows, 'depthAbsoluteErrorDeltaFromBaselineKm');
  final magnitudeDeltas = _numbers(
    rows,
    'magnitudeAbsoluteErrorDeltaFromBaseline',
  );
  final extraElapsed = _numbers(rows, 'additionalElapsedMilliseconds');
  final selectedHardCount = rows
      .where((row) => row['selectedPath'] == 'hardCoarseStart')
      .length;
  final selectedBaselineCount = rows.length - selectedHardCount;
  return <String, Object?>{
    'eventCount': rows.length,
    'selectedHardCoarseCount': selectedHardCount,
    'selectedBaselineCount': selectedBaselineCount,
    'lowerEpicentralErrorCount': epicentralDeltas
        .where((delta) => delta < 0)
        .length,
    'higherEpicentralErrorCount': epicentralDeltas
        .where((delta) => delta > 0)
        .length,
    'sameEpicentralErrorCount': epicentralDeltas
        .where((delta) => delta == 0)
        .length,
    'epicentralErrorDeltaMedianKm': _percentile(epicentralDeltas, 0.5),
    'epicentralErrorDeltaP90Km': _percentile(epicentralDeltas, 0.9),
    'depthAbsoluteErrorDeltaMedianKm': _percentile(depthDeltas, 0.5),
    'magnitudeAbsoluteErrorDeltaMedian': _percentile(magnitudeDeltas, 0.5),
    'additionalElapsedMillisecondsMedian': _percentile(extraElapsed, 0.5),
    'additionalElapsedMillisecondsP90': _percentile(extraElapsed, 0.9),
    'selectedStatusCounts': _counts(rows, 'selectedStatus'),
  };
}

String _markdown(Map<String, Object?> report) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki two-path returned-candidate union diagnostic')
    ..writeln()
    ..writeln(
      'Selection uses only frozen station-bias intensity RMS; truth is not used.',
    )
    ..writeln()
    ..writeln(
      '| Model | Events | Hard coarse selected | Epicentral improved | Epicentral worsened | Median delta km | Extra time median ms |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');
  final summaries = _map(report['modelSummaries'], 'modelSummaries');
  for (final modelName in _modelNames) {
    final summary = _map(summaries[modelName], modelName);
    buffer.writeln(
      '| `$modelName` | ${summary['eventCount']} | '
      '${summary['selectedHardCoarseCount']} | '
      '${summary['lowerEpicentralErrorCount']} | '
      '${summary['higherEpicentralErrorCount']} | '
      '${summary['epicentralErrorDeltaMedianKm']} | '
      '${summary['additionalElapsedMillisecondsMedian']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'The union contains only the best returned candidate from each path; it is not a full candidate-set union.',
    )
    ..writeln('Protocol: `${report['protocolStatus']}`.');
  return buffer.toString();
}

Map<String, int> _counts(List<Map<String, Object?>> rows, String key) {
  final counts = <String, int>{};
  for (final row in rows) {
    final value = row[key]?.toString() ?? 'null';
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}

List<double> _numbers(List<Map<String, Object?>> rows, String key) => [
  for (final row in rows)
    if (row[key] is num) (row[key]! as num).toDouble(),
];

double? _percentile(List<double> values, double probability) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final index = (sorted.length - 1) * probability;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = index - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

double? _difference(double? value, double? baseline) {
  if (value == null || baseline == null) return null;
  return value - baseline;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

Map<String, Object?> _map(Object? value, String context) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('Expected object at $context.');
}

Map<String, Map<String, Object?>> _eventsById(Map<String, Object?> report) {
  final events = report['events'];
  if (events is! List)
    throw const FormatException('Report has no events list.');
  final result = <String, Map<String, Object?>>{};
  for (final event in events) {
    final row = _map(event, 'events[]');
    final eventId = row['eventId'];
    if (eventId is! String)
      throw const FormatException('Event has no eventId.');
    result[eventId] = row;
  }
  return result;
}

Map<String, Object?> _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) throw StateError('Missing report: $path');
  return _map(jsonDecode(file.readAsStringSync(encoding: utf8)), path);
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}
