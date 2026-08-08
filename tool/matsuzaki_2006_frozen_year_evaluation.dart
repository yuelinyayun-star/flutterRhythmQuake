import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final selectionPath = _value(arguments, '--selection');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_frozen_2018_evaluation',
  );
  if (inputPath == null || selectionPath == null) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_frozen_year_evaluation.dart '
      '--input <2018.json> --selection <frozen-selection.json> '
      '--allow-frozen-year [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (!arguments.contains('--allow-frozen-year')) {
    stderr.writeln(
      'Refusing to evaluate 2018 without explicit --allow-frozen-year.',
    );
    exitCode = 65;
    return;
  }
  final missing = [
    inputPath,
    selectionPath,
  ].where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final selection = _readJsonObject(selectionPath);
  final coefficients = _readFrozenCoefficients(selection);
  final selectedModel = selection['selectedModel'];
  if (selection['status'] != 'frozen_before_2018_evaluation' ||
      selectedModel is! String ||
      selectedModel.isEmpty) {
    throw const FormatException(
      'Selection must be frozen before the 2018 evaluation.',
    );
  }
  final split = selection['split'];
  if (split is! Map<String, Object?> ||
      split['frozenEvaluationYear'] != 2018 ||
      split['year2018ReadDuringSelection'] != false) {
    throw const FormatException(
      'Selection does not declare an unopened 2018 frozen year.',
    );
  }

  final dataset = _readJsonObject(inputPath);
  if (dataset['year'] != 2018) {
    throw FormatException('Expected frozen year 2018 in $inputPath.');
  }
  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final baseline = evaluator.evaluate([dataset]);
  final nearOnlyEvents = _nearOnlyEvents(baseline.events);
  if (baseline.events.isEmpty || nearOnlyEvents.isEmpty) {
    throw StateError('The 2018 all-distance or nearfield event set is empty.');
  }

  const published = Matsuzaki2006AttenuationCoefficients.published;
  final allEvaluations = {
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: baseline.events,
    ),
    selectedModel: Matsuzaki2006ModelEvaluation(
      coefficients: coefficients,
      events: baseline.events,
    ),
  };
  final nearEvaluations = {
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: nearOnlyEvents,
    ),
    selectedModel: Matsuzaki2006ModelEvaluation(
      coefficients: coefficients,
      events: nearOnlyEvents,
    ),
  };
  final nearfieldEventComparison = _eventComparison(
    published: nearEvaluations['published']!,
    selected: nearEvaluations[selectedModel]!,
  );
  final nearPublishedStationRms = nearEvaluations['published']!
      .stationWeightedSummary
      .rootMeanSquareResidual;
  final nearSelectedStationRms = nearEvaluations[selectedModel]!
      .stationWeightedSummary
      .rootMeanSquareResidual;
  final nearPublishedEventRms = _eventRms(nearEvaluations['published']!);
  final nearSelectedEventRms = _eventRms(nearEvaluations[selectedModel]!);
  final allPublishedEventRms = _eventRms(allEvaluations['published']!);
  final allSelectedEventRms = _eventRms(allEvaluations[selectedModel]!);

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_frozen_2018_evaluation_v1',
    'evaluationDate': '2026-07-19',
    'inputYear': 2018,
    'selectionPath': selectionPath,
    'selectionStatusAtRead': selection['status'],
    'selectedModel': selectedModel,
    'selectedCoefficients': coefficients.toJson(),
    'selectionWasNotModified': true,
    'productionAdoption': false,
    'eventPolicy': {
      'magnitudeRange': [
        Matsuzaki2006AttenuationModel.minimumMagnitude,
        Matsuzaki2006AttenuationModel.maximumMagnitude,
      ],
      'magnitudeTypes': Matsuzaki2006JmaBaselineEvaluator
          .supportedMagnitudeTypes
          .toList(),
      'minimumStationsPerEvent': evaluator.minimumStationsPerEvent,
      'nearDistanceThresholdKm': 30.0,
      'minimumNearStationsForNearfieldEvent': 2,
      'nearfieldMetricUsesNearStationsOnly': true,
    },
    'counts': {
      'inputEvents': baseline.inputEventCount,
      'acceptedEvents': baseline.events.length,
      'acceptedStations': baseline.stationResidualCount,
      'nearfieldEvents': nearOnlyEvents.length,
      'nearfieldStations': _stationCount(nearOnlyEvents),
    },
    'eventRejectionCounts': baseline.eventRejectionCounts,
    'observationRejectionCounts': baseline.observationRejectionCounts,
    'nearfieldEvaluation': {
      for (final entry in nearEvaluations.entries)
        entry.key: entry.value.toJson(),
    },
    'comparisonSummary': {
      'nearfieldEventEqualRmsDeltaSelectedMinusPublished':
          nearSelectedEventRms - nearPublishedEventRms,
      'nearfieldStationWeightedRmsDeltaSelectedMinusPublished':
          nearSelectedStationRms - nearPublishedStationRms,
      'allDistanceEventEqualRmsDeltaSelectedMinusPublished':
          allSelectedEventRms - allPublishedEventRms,
      'selectionMetric': 'event_equal_nearfield_rms',
      'stationWeightedNearfieldWasNotASelectionMetric': true,
    },
    'nearfieldEventComparison': nearfieldEventComparison,
    'allDistanceEvaluation': {
      for (final entry in allEvaluations.entries)
        entry.key: entry.value.toJson(),
    },
  };

  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(
    _toMarkdown(
      selectedModel: selectedModel,
      coefficients: coefficients,
      baseline: baseline,
      nearOnlyEvents: nearOnlyEvents,
      nearEvaluations: nearEvaluations,
      allEvaluations: allEvaluations,
      nearfieldEventComparison: nearfieldEventComparison,
    ),
    encoding: utf8,
  );
  stdout.writeln(
    'evaluated frozen year=2018 accepted=${baseline.events.length} '
    'stations=${baseline.stationResidualCount} '
    'nearEvents=${nearOnlyEvents.length} '
    'nearStations=${_stationCount(nearOnlyEvents)}',
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

Matsuzaki2006AttenuationCoefficients _readFrozenCoefficients(
  Map<String, Object?> selection,
) {
  final raw = selection['coefficients'];
  if (raw is! Map<String, Object?>) {
    throw const FormatException('Frozen selection has no coefficients.');
  }
  final coefficients = Matsuzaki2006AttenuationCoefficients(
    magnitudeCoefficient: _finiteNumber(raw, 'magnitudeCoefficient'),
    logDistanceCoefficient: _finiteNumber(raw, 'logDistanceCoefficient'),
    saturationCoefficient: _finiteNumber(raw, 'saturationCoefficient'),
    saturationMagnitudeExponent: _finiteNumber(
      raw,
      'saturationMagnitudeExponent',
    ),
    depthCoefficient: _finiteNumber(raw, 'depthCoefficient'),
    intercept: _finiteNumber(raw, 'intercept'),
  );
  if (coefficients.saturationCoefficient != 0.00675 ||
      coefficients.saturationMagnitudeExponent != 0.5) {
    throw const FormatException(
      'Frozen selection does not retain the published c=0.00675 and d=0.5.',
    );
  }
  return coefficients;
}

double _finiteNumber(Map<String, Object?> values, String name) {
  final value = values[name];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('Invalid coefficient $name.');
  }
  return value.toDouble();
}

List<Matsuzaki2006EventBaseline> _nearOnlyEvents(
  List<Matsuzaki2006EventBaseline> events,
) => [
  for (final event in events)
    if (event.stationResiduals
            .where((station) => station.sourceDistanceKm < 30)
            .length >=
        2)
      Matsuzaki2006EventBaseline(
        eventId: event.eventId,
        year: event.year,
        originTime: event.originTime,
        latitude: event.latitude,
        longitude: event.longitude,
        depthKm: event.depthKm,
        magnitude: event.magnitude,
        magnitudeType: event.magnitudeType,
        maximumIntensityClass: event.maximumIntensityClass,
        determinationFlag: event.determinationFlag,
        stationResiduals: event.stationResiduals
            .where((station) => station.sourceDistanceKm < 30)
            .toList(),
      ),
];

int _stationCount(List<Matsuzaki2006EventBaseline> events) =>
    events.fold(0, (sum, event) => sum + event.stationResiduals.length);

double _eventRms(Matsuzaki2006ModelEvaluation evaluation) =>
    evaluation.eventEqualMetrics['meanOfEventRootMeanSquareResiduals']!
        as double;

List<Map<String, Object>> _eventComparison({
  required Matsuzaki2006ModelEvaluation published,
  required Matsuzaki2006ModelEvaluation selected,
}) {
  final selectedById = {
    for (final event in selected.events) event.eventId: event,
  };
  return [
    for (final publishedEvent in published.events)
      if (selectedById[publishedEvent.eventId] case final selectedEvent?)
        {
          'eventId': publishedEvent.eventId,
          'originTime': publishedEvent.originTime,
          'magnitude': publishedEvent.magnitude,
          'depthKm': publishedEvent.depthKm,
          'nearStationCount': publishedEvent.stationResiduals.length,
          'publishedMeanResidual': publishedEvent.residualSummary.meanResidual,
          'selectedMeanResidual': selectedEvent.residualSummary.meanResidual,
          'publishedRms': publishedEvent.residualSummary.rootMeanSquareResidual,
          'selectedRms': selectedEvent.residualSummary.rootMeanSquareResidual,
          'rmsDeltaSelectedMinusPublished':
              selectedEvent.residualSummary.rootMeanSquareResidual -
              publishedEvent.residualSummary.rootMeanSquareResidual,
        },
  ];
}

String _toMarkdown({
  required String selectedModel,
  required Matsuzaki2006AttenuationCoefficients coefficients,
  required Matsuzaki2006JmaBaselineResult baseline,
  required List<Matsuzaki2006EventBaseline> nearOnlyEvents,
  required Map<String, Matsuzaki2006ModelEvaluation> nearEvaluations,
  required Map<String, Matsuzaki2006ModelEvaluation> allEvaluations,
  required List<Map<String, Object>> nearfieldEventComparison,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Frozen 2018 Evaluation')
    ..writeln()
    ..writeln(
      'The model was frozen from 2010-2017 before this 2018 dataset was read.',
    )
    ..writeln('No fitting or model reselection is performed by this tool.')
    ..writeln()
    ..writeln('## Frozen Model')
    ..writeln()
    ..writeln('- Model: `$selectedModel`')
    ..writeln('- Coefficients: `${jsonEncode(coefficients.toJson())}`')
    ..writeln()
    ..writeln('## Counts')
    ..writeln()
    ..writeln('- Input events: ${baseline.inputEventCount}')
    ..writeln('- Accepted events: ${baseline.events.length}')
    ..writeln('- Accepted stations: ${baseline.stationResidualCount}')
    ..writeln('- Nearfield events: ${nearOnlyEvents.length}')
    ..writeln('- Nearfield stations: ${_stationCount(nearOnlyEvents)}');
  _writeEvaluation(buffer, 'Nearfield Evaluation', nearEvaluations);
  buffer
    ..writeln()
    ..writeln('## Nearfield Event Comparison')
    ..writeln()
    ..writeln(
      '| Origin time | Mj | Depth km | Stations | Published RMS | Selected RMS | Delta |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final event in nearfieldEventComparison) {
    buffer.writeln(
      '| ${event['originTime']} | ${event['magnitude']} | '
      '${event['depthKm']} | ${event['nearStationCount']} | '
      '${_metric(event['publishedRms']! as double)} | '
      '${_metric(event['selectedRms']! as double)} | '
      '${_signedMetric(event['rmsDeltaSelectedMinusPublished']! as double)} |',
    );
  }
  _writeEvaluation(buffer, 'All-Distance Evaluation', allEvaluations);
  return buffer.toString();
}

void _writeEvaluation(
  StringBuffer buffer,
  String title,
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) {
  buffer
    ..writeln()
    ..writeln('## $title')
    ..writeln()
    ..writeln(
      '| Model | Events | Stations | Station mean | Station RMS | Event mean | Event RMS |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final entry in evaluations.entries) {
    final station = entry.value.stationWeightedSummary;
    final event = entry.value.eventEqualMetrics;
    buffer.writeln(
      '| ${entry.key} | ${entry.value.events.length} | ${station.count} | '
      '${_metric(station.meanResidual)} | '
      '${_metric(station.rootMeanSquareResidual)} | '
      '${_metric(event['meanOfEventMeanResiduals']! as double)} | '
      '${_metric(event['meanOfEventRootMeanSquareResiduals']! as double)} |',
    );
  }
}

String _metric(double value) => value.toStringAsFixed(6);
String _signedMetric(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(6)}';

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}
