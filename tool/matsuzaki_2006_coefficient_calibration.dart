import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputPaths = _values(arguments, '--input').isEmpty
      ? const [
          'tmp/jma_intensity_pretraining/jma_final_intensity_2020.json',
          'tmp/jma_intensity_pretraining/jma_final_intensity_2021.json',
          'tmp/jma_intensity_pretraining/jma_final_intensity_2022.json',
        ]
      : _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_coefficient_calibration',
  );
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
  final baseline = const Matsuzaki2006JmaBaselineEvaluator().evaluate(datasets);
  final eventsByYear = <int, List<Matsuzaki2006EventBaseline>>{
    for (final year in const [2020, 2021, 2022])
      year: baseline.events.where((event) => event.year == year).toList(),
  };
  for (final year in const [2020, 2021, 2022]) {
    if (eventsByYear[year]!.isEmpty) {
      stderr.writeln('No accepted $year events in the supplied datasets.');
      exitCode = 65;
      return;
    }
  }

  final searchSpec = Matsuzaki2006CalibrationSearchSpec(
    starts: const [
      Matsuzaki2006NonlinearStart(
        saturationCoefficient: 0.00675,
        saturationMagnitudeExponent: 0.5,
      ),
      Matsuzaki2006NonlinearStart(
        saturationCoefficient: 0.0016875,
        saturationMagnitudeExponent: 0.5,
      ),
      Matsuzaki2006NonlinearStart(
        saturationCoefficient: 0.027,
        saturationMagnitudeExponent: 0.5,
      ),
      Matsuzaki2006NonlinearStart(
        saturationCoefficient: 0.00675,
        saturationMagnitudeExponent: 0.25,
      ),
      Matsuzaki2006NonlinearStart(
        saturationCoefficient: 0.00675,
        saturationMagnitudeExponent: 1.0,
      ),
    ],
    initialSimplexStep: 0.5,
    objectiveTolerance: 1e-12,
    parameterTolerance: 1e-8,
    maximumIterationsPerStart: 500,
  );
  const calibrator = Matsuzaki2006CoefficientCalibrator();
  final trainingEvents = eventsByYear[2020]!;
  stdout.writeln(
    'accepted events: 2020=${trainingEvents.length}, '
    '2021=${eventsByYear[2021]!.length}, '
    '2022=${eventsByYear[2022]!.length}',
  );
  stdout.writeln('fitting global station-weighted coefficients...');
  final globalFit = calibrator.fitGlobalStationWeighted(
    trainingEvents: trainingEvents,
    searchSpec: searchSpec,
  );
  stdout.writeln('fitting event-source-stripped coefficients...');
  final strippedFit = calibrator.fitEventSourceStripped(
    trainingEvents: trainingEvents,
    searchSpec: searchSpec,
  );

  const published = Matsuzaki2006AttenuationCoefficients.published;
  final trainEvaluations = {
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: trainingEvents,
    ),
    'globalStationWeighted': Matsuzaki2006ModelEvaluation(
      coefficients: globalFit.coefficients,
      events: trainingEvents,
    ),
    'eventSourceStripped': Matsuzaki2006ModelEvaluation(
      coefficients: strippedFit.coefficients,
      events: trainingEvents,
    ),
  };
  final validationEvaluations = {
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: eventsByYear[2021]!,
    ),
    'globalStationWeighted': Matsuzaki2006ModelEvaluation(
      coefficients: globalFit.coefficients,
      events: eventsByYear[2021]!,
    ),
    'eventSourceStripped': Matsuzaki2006ModelEvaluation(
      coefficients: strippedFit.coefficients,
      events: eventsByYear[2021]!,
    ),
  };
  final selectedName = _selectByValidationEventEqualRms(validationEvaluations);
  final selectedFit = selectedName == 'globalStationWeighted'
      ? globalFit
      : strippedFit;
  final testEvaluations = {
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: eventsByYear[2022]!,
    ),
    selectedName: Matsuzaki2006ModelEvaluation(
      coefficients: selectedFit.coefficients,
      events: eventsByYear[2022]!,
    ),
  };

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_jma_coefficient_calibration_v1',
    'split': {
      'trainingYear': 2020,
      'validationYear': 2021,
      'frozenTestYear': 2022,
      'eventIsolation': true,
      'selectionMetric': 'validation_mean_of_event_root_mean_square_residuals',
      'selectedForFrozenEvaluation': selectedName,
      'productionAdoption': false,
      'frozenTestModelsEvaluated': ['published', selectedName],
    },
    'inputPaths': inputPaths,
    'baselineSelection': {
      'acceptedEventsByYear': {
        for (final year in const [2020, 2021, 2022])
          year.toString(): eventsByYear[year]!.length,
      },
      'minimumStationsPerEvent': baseline.minimumStationsPerEvent,
      'supportedMagnitudeTypes': Matsuzaki2006JmaBaselineEvaluator
          .supportedMagnitudeTypes
          .toList(),
      'observationDomain': 'JMA_archive_reported_intensity_1_or_higher',
      'compoundEventPolicy':
          'exclude_events_with_unassigned_alternate_hypocenters',
    },
    'search': searchSpec.toJson(),
    'fits': {
      'globalStationWeighted': globalFit.toJson(),
      'eventSourceStripped': strippedFit.toJson(),
    },
    'evaluations': {
      'training2020': _evaluationsToJson(trainEvaluations),
      'validation2021': _evaluationsToJson(validationEvaluations),
      'frozenTest2022': _evaluationsToJson(testEvaluations),
    },
  };
  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(
    _toMarkdown(
      report: report,
      globalFit: globalFit,
      strippedFit: strippedFit,
      training: trainEvaluations,
      validation: validationEvaluations,
      frozenTest: testEvaluations,
    ),
    encoding: utf8,
  );
  stdout.writeln('selected=$selectedName');
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

String _selectByValidationEventEqualRms(
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) {
  const candidates = ['globalStationWeighted', 'eventSourceStripped'];
  var best = candidates.first;
  var bestValue = _eventEqualRms(evaluations[best]!);
  for (final name in candidates.skip(1)) {
    final value = _eventEqualRms(evaluations[name]!);
    if (value < bestValue) {
      best = name;
      bestValue = value;
    }
  }
  return best;
}

double _eventEqualRms(Matsuzaki2006ModelEvaluation evaluation) =>
    evaluation.eventEqualMetrics['meanOfEventRootMeanSquareResiduals']!
        as double;

Map<String, Object> _evaluationsToJson(
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) => {for (final entry in evaluations.entries) entry.key: entry.value.toJson()};

String _toMarkdown({
  required Map<String, Object?> report,
  required Matsuzaki2006CoefficientFit globalFit,
  required Matsuzaki2006CoefficientFit strippedFit,
  required Map<String, Matsuzaki2006ModelEvaluation> training,
  required Map<String, Matsuzaki2006ModelEvaluation> validation,
  required Map<String, Matsuzaki2006ModelEvaluation> frozenTest,
}) {
  final split = report['split']! as Map<String, Object?>;
  final selected = split['selectedForFrozenEvaluation'];
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 JMA Coefficient Calibration')
    ..writeln()
    ..writeln('Event-level split: 2020 training, 2021 validation, and 2022')
    ..writeln(
      'frozen test. Only the published model and the fitted model chosen',
    )
    ..writeln('on 2021 are evaluated on 2022.')
    ..writeln()
    ..writeln('Selected for frozen evaluation: `$selected`. This is not a')
    ..writeln('production-adoption decision.')
    ..writeln()
    ..writeln('Residual is observed minus predicted instrumental intensity.')
    ..writeln('JMA archive selection remains conditional on reported intensity')
    ..writeln('1-or-higher stations; absent stations are not intensity zero.')
    ..writeln()
    ..writeln('## Coefficients')
    ..writeln()
    ..writeln(
      '| Model | a(M) | b(log distance) | c(saturation) | d(exponent) | e(depth) | intercept | converged |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---|');
  _writeCoefficientRow(
    buffer,
    'published',
    Matsuzaki2006AttenuationCoefficients.published,
    null,
  );
  _writeCoefficientRow(
    buffer,
    'globalStationWeighted',
    globalFit.coefficients,
    globalFit.converged,
  );
  _writeCoefficientRow(
    buffer,
    'eventSourceStripped',
    strippedFit.coefficients,
    strippedFit.converged,
  );
  _writeOverallTable(buffer, 'Training 2020', training);
  _writeOverallTable(buffer, 'Validation 2021', validation);
  _writeOverallTable(buffer, 'Frozen Test 2022', frozenTest);
  _writeNonlinearRuns(buffer, globalFit);
  _writeNonlinearRuns(buffer, strippedFit);
  _writeGroupedTables(buffer, 'Training 2020', training);
  _writeGroupedTables(buffer, 'Validation 2021', validation);
  _writeGroupedTables(buffer, 'Frozen Test 2022', frozenTest);
  buffer
    ..writeln()
    ..writeln('## Fit Semantics')
    ..writeln()
    ..writeln(
      '- `globalStationWeighted`: all six global coefficients are fitted',
    )
    ..writeln('  against station-weighted intensity squared error.')
    ..writeln(
      '- `eventSourceStripped`: each event is centered first; the distance',
    )
    ..writeln('  shape is fitted with equal total weight per event. Event-mean')
    ..writeln(
      '  intensity then fits magnitude, capped depth, and intercept with',
    )
    ..writeln('  one row per event.')
    ..writeln(
      '- The positive saturation coefficient and exponent are optimized',
    )
    ..writeln(
      '  in log coordinates without numeric bounds. Starts and tolerances',
    )
    ..writeln('  are recorded in `report.json`.');
  return buffer.toString();
}

void _writeNonlinearRuns(StringBuffer buffer, Matsuzaki2006CoefficientFit fit) {
  buffer
    ..writeln()
    ..writeln('## ${fit.method.name} Nonlinear Runs')
    ..writeln()
    ..writeln(
      'Saturation change factor from Mj 5.0 to 8.2: '
      '`${fit.saturationChangeFactorAcrossMagnitudeRange.toStringAsPrecision(12)}`.',
    )
    ..writeln()
    ..writeln(
      '| Start | Start c | Start d | Final c | Final d | Objective | Converged | Iterations |',
    )
    ..writeln('|---:|---:|---:|---:|---:|---:|---|---:|');
  for (final run in fit.nonlinearRuns) {
    buffer.writeln(
      '| ${run.startIndex} | ${_number(run.start.saturationCoefficient)} | '
      '${_number(run.start.saturationMagnitudeExponent)} | '
      '${_number(run.finalSaturationCoefficient)} | '
      '${_number(run.finalSaturationMagnitudeExponent)} | '
      '${run.objective.toStringAsPrecision(10)} | ${run.converged} | '
      '${run.iterations} |',
    );
  }
}

void _writeCoefficientRow(
  StringBuffer buffer,
  String name,
  Matsuzaki2006AttenuationCoefficients value,
  bool? converged,
) {
  buffer.writeln(
    '| $name | ${_number(value.magnitudeCoefficient)} | '
    '${_number(value.logDistanceCoefficient)} | '
    '${_number(value.saturationCoefficient)} | '
    '${_number(value.saturationMagnitudeExponent)} | '
    '${_number(value.depthCoefficient)} | ${_number(value.intercept)} | '
    '${converged ?? '-'} |',
  );
}

void _writeOverallTable(
  StringBuffer buffer,
  String title,
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) {
  buffer
    ..writeln()
    ..writeln('## $title Overall')
    ..writeln()
    ..writeln(
      '| Model | Events | Stations | Station mean | Station MAE | Station RMS | Event mean | Event MAE | Event RMS |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final entry in evaluations.entries) {
    final station = entry.value.stationWeightedSummary;
    final event = entry.value.eventEqualMetrics;
    buffer.writeln(
      '| ${entry.key} | ${entry.value.events.length} | ${station.count} | '
      '${_metric(station.meanResidual)} | '
      '${_metric(station.meanAbsoluteResidual)} | '
      '${_metric(station.rootMeanSquareResidual)} | '
      '${_metric(event['meanOfEventMeanResiduals']! as double)} | '
      '${_metric(event['meanOfEventMeanAbsoluteResiduals']! as double)} | '
      '${_metric(event['meanOfEventRootMeanSquareResiduals']! as double)} |',
    );
  }
}

void _writeGroupedTables(
  StringBuffer buffer,
  String split,
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) {
  for (final entry in evaluations.entries) {
    _writeGroupedTable(
      buffer,
      '$split / ${entry.key} / Source Distance',
      entry.value.byDistanceBand,
    );
    _writeGroupedTable(
      buffer,
      '$split / ${entry.key} / Depth',
      entry.value.byDepthBand,
    );
    _writeGroupedTable(
      buffer,
      '$split / ${entry.key} / Mj',
      entry.value.byMagnitudeBand,
    );
  }
}

void _writeGroupedTable(
  StringBuffer buffer,
  String title,
  Map<String, Matsuzaki2006ResidualSummary> summaries,
) {
  buffer
    ..writeln()
    ..writeln('### $title')
    ..writeln()
    ..writeln('| Group | Stations | Mean | MAE | RMS |')
    ..writeln('|---|---:|---:|---:|---:|');
  for (final entry in summaries.entries) {
    buffer.writeln(
      '| ${entry.key} | ${entry.value.count} | '
      '${_metric(entry.value.meanResidual)} | '
      '${_metric(entry.value.meanAbsoluteResidual)} | '
      '${_metric(entry.value.rootMeanSquareResidual)} |',
    );
  }
}

String _number(double value) => value.toStringAsPrecision(9);
String _metric(double value) => value.toStringAsFixed(3);

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
