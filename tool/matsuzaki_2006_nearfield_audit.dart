import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputPaths = _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_nearfield_audit',
  );
  final allowFrozenYear = arguments.contains('--allow-frozen-year');
  if (inputPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_nearfield_audit.dart '
      '--input <annual.json> [--input <annual.json> ...] '
      '[--output-dir <directory>] [--allow-frozen-year]',
    );
    exitCode = 64;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final annual = <Map<String, Object?>>[];
  final nearEvents = <Map<String, Object?>>[];
  final nearResiduals = <double>[];
  final residualsByDistance = <String, List<double>>{};
  final countsByRole = <String, _RoleCounts>{};
  final aggregateEventRejections = <String, int>{};
  final aggregateObservationRejections = <String, int>{};
  var inputEventCount = 0;
  var acceptedEventCount = 0;
  var acceptedStationCount = 0;

  for (final inputPath in inputPaths) {
    final dataset =
        jsonDecode(File(inputPath).readAsStringSync(encoding: utf8))
            as Map<String, Object?>;
    final year = (dataset['year']! as num).toInt();
    if (year == 2018 && !allowFrozenYear) {
      stderr.writeln(
        'Refusing to audit predeclared frozen year 2018. '
        'Pass --allow-frozen-year only after model selection.',
      );
      exitCode = 65;
      return;
    }
    final role = _roleForYear(year);
    final result = evaluator.evaluate([dataset]);
    final yearNearResiduals = <double>[];
    final yearNearStationIds = <String>{};
    var yearNearEventCount = 0;
    for (final event in result.events) {
      final stations = event.stationResiduals
          .where((station) => station.sourceDistanceKm < 30)
          .toList();
      if (stations.isEmpty) continue;
      yearNearEventCount++;
      final eventResiduals = stations
          .map((station) => station.residual)
          .toList();
      yearNearResiduals.addAll(eventResiduals);
      nearResiduals.addAll(eventResiduals);
      for (final station in stations) {
        yearNearStationIds.add(station.stationId);
        residualsByDistance
            .putIfAbsent(
              _nearDistanceBand(station.sourceDistanceKm),
              () => <double>[],
            )
            .add(station.residual);
      }
      nearEvents.add({
        'eventId': event.eventId,
        'year': event.year,
        'role': role,
        'originTime': event.originTime,
        'latitude': event.latitude,
        'longitude': event.longitude,
        'depthKm': event.depthKm,
        'magnitude': event.magnitude,
        'magnitudeType': event.magnitudeType,
        'totalStationCount': event.stationResiduals.length,
        'nearStationCount': stations.length,
        'minimumSourceDistanceKm': stations
            .map((station) => station.sourceDistanceKm)
            .reduce((left, right) => left < right ? left : right),
        'nearResidualSummary': Matsuzaki2006ResidualSummary.fromResiduals(
          eventResiduals,
        ).toJson(),
        'nearStations': [
          for (final station in stations)
            {
              'stationId': station.stationId,
              'latitude': station.latitude,
              'longitude': station.longitude,
              'sourceDistanceKm': station.sourceDistanceKm,
              'observedIntensity': station.observedIntensity,
              'publishedModelPrediction': station.predictedIntensity,
              'residual': station.residual,
            },
        ],
      });
    }
    final roleCounts = countsByRole.putIfAbsent(role, _RoleCounts.new);
    roleCounts
      ..inputEvents += result.inputEventCount
      ..acceptedEvents += result.events.length
      ..acceptedStations += result.stationResidualCount
      ..nearEvents += yearNearEventCount
      ..nearStations += yearNearResiduals.length;
    _mergeCounts(aggregateEventRejections, result.eventRejectionCounts);
    _mergeCounts(
      aggregateObservationRejections,
      result.observationRejectionCounts,
    );
    inputEventCount += result.inputEventCount;
    acceptedEventCount += result.events.length;
    acceptedStationCount += result.stationResidualCount;
    annual.add({
      'year': year,
      'role': role,
      'inputPath': inputPath,
      'datasetId': dataset['datasetId'],
      'sourceUrl': dataset['sourceUrl'],
      'inputEvents': result.inputEventCount,
      'acceptedEvents': result.events.length,
      'acceptedStations': result.stationResidualCount,
      'nearEvents': yearNearEventCount,
      'nearStations': yearNearResiduals.length,
      'uniqueNearStations': yearNearStationIds.length,
      'nearResidualSummary': Matsuzaki2006ResidualSummary.fromResiduals(
        yearNearResiduals,
      ).toJson(),
      'eventRejectionCounts': result.eventRejectionCounts,
      'observationRejectionCounts': result.observationRejectionCounts,
    });
    stdout.writeln(
      'year=$year role=$role accepted=${result.events.length} '
      'stations=${result.stationResidualCount} nearEvents=$yearNearEventCount '
      'nearStations=${yearNearResiduals.length}',
    );
  }
  annual.sort(
    (left, right) => (left['year']! as int).compareTo(right['year']! as int),
  );
  nearEvents.sort(
    (left, right) => (left['originTime']! as String).compareTo(
      right['originTime']! as String,
    ),
  );
  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_nearfield_audit_v1',
    'nearfieldDefinition': {
      'distance': 'point_source_hypocentral_distance',
      'minimumKm': Matsuzaki2006AttenuationModel.minimumSourceDistanceKm,
      'maximumExclusiveKm': 30.0,
      'magnitudeRange': [
        Matsuzaki2006AttenuationModel.minimumMagnitude,
        Matsuzaki2006AttenuationModel.maximumMagnitude,
      ],
      'supportedMagnitudeTypes': Matsuzaki2006JmaBaselineEvaluator
          .supportedMagnitudeTypes
          .toList(),
      'minimumStationsPerEvent': evaluator.minimumStationsPerEvent,
    },
    'evaluationPolicy': {
      'calibrationYears': [for (var year = 2010; year <= 2016; year++) year],
      'validationYears': [2017],
      'frozenYears': [2018],
      'previouslyOpenedAuditYears': [2019, 2020, 2021, 2022],
      'frozenYearIncluded': annual.any((entry) => entry['year'] == 2018),
    },
    'counts': {
      'inputEvents': inputEventCount,
      'acceptedEvents': acceptedEventCount,
      'acceptedStations': acceptedStationCount,
      'nearEvents': nearEvents.length,
      'nearStations': nearResiduals.length,
    },
    'countsByRole': {
      for (final entry in countsByRole.entries) entry.key: entry.value.toJson(),
    },
    'nearResidualSummary': Matsuzaki2006ResidualSummary.fromResiduals(
      nearResiduals,
    ).toJson(),
    'nearResidualsByDistance': {
      for (final key in _orderedNearDistanceBands)
        key: Matsuzaki2006ResidualSummary.fromResiduals(
          residualsByDistance[key] ?? const <double>[],
        ).toJson(),
    },
    'eventRejectionCounts': _sortedCounts(aggregateEventRejections),
    'observationRejectionCounts': _sortedCounts(aggregateObservationRejections),
    'annual': annual,
    'nearEvents': nearEvents,
  };
  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(_toMarkdown(report), encoding: utf8);
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

class _RoleCounts {
  var inputEvents = 0;
  var acceptedEvents = 0;
  var acceptedStations = 0;
  var nearEvents = 0;
  var nearStations = 0;

  Map<String, int> toJson() => {
    'inputEvents': inputEvents,
    'acceptedEvents': acceptedEvents,
    'acceptedStations': acceptedStations,
    'nearEvents': nearEvents,
    'nearStations': nearStations,
  };
}

const _orderedNearDistanceBands = [
  '1-<5 km',
  '5-<10 km',
  '10-<15 km',
  '15-<20 km',
  '20-<25 km',
  '25-<30 km',
];

String _roleForYear(int year) {
  if (year >= 2010 && year <= 2016) return 'calibration';
  if (year == 2017) return 'validation';
  if (year == 2018) return 'frozen';
  return 'previously_opened_audit';
}

String _nearDistanceBand(double distanceKm) {
  if (distanceKm < 5) return '1-<5 km';
  if (distanceKm < 10) return '5-<10 km';
  if (distanceKm < 15) return '10-<15 km';
  if (distanceKm < 20) return '15-<20 km';
  if (distanceKm < 25) return '20-<25 km';
  return '25-<30 km';
}

void _mergeCounts(Map<String, int> target, Map<String, int> source) {
  for (final entry in source.entries) {
    target[entry.key] = (target[entry.key] ?? 0) + entry.value;
  }
}

Map<String, int> _sortedCounts(Map<String, int> values) {
  final keys = values.keys.toList()..sort();
  return {for (final key in keys) key: values[key]!};
}

String _toMarkdown(Map<String, Object?> report) {
  final counts = report['counts']! as Map<String, Object?>;
  final annual = report['annual']! as List<Object?>;
  final byRole = report['countsByRole']! as Map<String, Object?>;
  final byDistance = report['nearResidualsByDistance']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 JMA Nearfield Audit')
    ..writeln()
    ..writeln('Nearfield means point-source hypocentral distance in')
    ..writeln('`[1 km, 30 km)`, after the same strict baseline selection.')
    ..writeln('The predeclared 2018 frozen year is excluded.')
    ..writeln()
    ..writeln('## Counts')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|');
  for (final entry in counts.entries) {
    buffer.writeln('| ${entry.key} | ${entry.value} |');
  }
  buffer
    ..writeln()
    ..writeln('## Annual')
    ..writeln()
    ..writeln(
      '| Year | Role | Input events | Accepted events | Stations | Near events | Near stations | Unique near stations |',
    )
    ..writeln('|---:|---|---:|---:|---:|---:|---:|---:|');
  for (final raw in annual) {
    final entry = raw! as Map<String, Object?>;
    buffer.writeln(
      '| ${entry['year']} | ${entry['role']} | ${entry['inputEvents']} | '
      '${entry['acceptedEvents']} | ${entry['acceptedStations']} | '
      '${entry['nearEvents']} | ${entry['nearStations']} | '
      '${entry['uniqueNearStations']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## By Role')
    ..writeln()
    ..writeln(
      '| Role | Input events | Accepted | Stations | Near events | Near stations |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|');
  for (final entry in byRole.entries) {
    final value = entry.value! as Map<String, Object?>;
    buffer.writeln(
      '| ${entry.key} | ${value['inputEvents']} | ${value['acceptedEvents']} | '
      '${value['acceptedStations']} | ${value['nearEvents']} | '
      '${value['nearStations']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Nearfield Distance Residuals')
    ..writeln()
    ..writeln('| Distance | Stations | Mean | MAE | RMS |')
    ..writeln('|---|---:|---:|---:|---:|');
  for (final key in _orderedNearDistanceBands) {
    final value = byDistance[key]! as Map<String, Object?>;
    buffer.writeln(
      '| $key | ${value['count']} | ${_metric(value['meanResidual'])} | '
      '${_metric(value['meanAbsoluteResidual'])} | '
      '${_metric(value['rootMeanSquareResidual'])} |',
    );
  }
  return buffer.toString();
}

String _metric(Object? value) => (value! as num).toDouble().toStringAsFixed(3);

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
