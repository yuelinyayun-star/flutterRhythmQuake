import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
        '.dart_tool/matsuzaki_2006_structure_identifiability',
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

  final freeSearchSpec = Matsuzaki2006CalibrationSearchSpec(
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
  final coefficientSearchSpec = Matsuzaki2006PositiveParameterSearchSpec(
    starts: const [0.0016875, 0.00675, 0.027],
    initialSimplexStep: 0.5,
    objectiveTolerance: 1e-12,
    parameterTolerance: 1e-8,
    maximumIterationsPerStart: 500,
  );
  final exponentSearchSpec = Matsuzaki2006PositiveParameterSearchSpec(
    starts: const [0.25, 0.5, 1.0],
    initialSimplexStep: 0.5,
    objectiveTolerance: 1e-12,
    parameterTolerance: 1e-8,
    maximumIterationsPerStart: 500,
  );
  const calibrator = Matsuzaki2006CoefficientCalibrator();
  const published = Matsuzaki2006AttenuationCoefficients.published;
  final trainingEvents = eventsByYear[2020]!;
  stdout.writeln(
    'accepted events: 2020=${trainingEvents.length}, '
    '2021=${eventsByYear[2021]!.length}, '
    '2022=${eventsByYear[2022]!.length}',
  );

  stdout.writeln('fitting unconstrained saturation reference...');
  final freeGlobal = calibrator.fitGlobalStationWeighted(
    trainingEvents: trainingEvents,
    searchSpec: freeSearchSpec,
  );
  stdout.writeln('fitting linear terms with published c and d...');
  final fixedSaturation = calibrator.fitGlobalWithFixedSaturation(
    trainingEvents: trainingEvents,
    saturationCoefficient: published.saturationCoefficient,
    saturationMagnitudeExponent: published.saturationMagnitudeExponent,
  );
  stdout.writeln('fitting c with published d fixed...');
  final fixedExponent = calibrator.fitGlobalWithFixedExponent(
    trainingEvents: trainingEvents,
    saturationMagnitudeExponent: published.saturationMagnitudeExponent,
    coefficientSearchSpec: coefficientSearchSpec,
  );
  stdout.writeln('fitting d with published c fixed...');
  final fixedCoefficient = calibrator.fitGlobalWithFixedCoefficient(
    trainingEvents: trainingEvents,
    saturationCoefficient: published.saturationCoefficient,
    exponentSearchSpec: exponentSearchSpec,
  );

  final fits = <String, Matsuzaki2006CoefficientFit>{
    'freeGlobalReference': freeGlobal,
    'fixedPublishedSaturation': fixedSaturation,
    'fixedPublishedExponent': fixedExponent,
    'fixedPublishedCoefficient': fixedCoefficient,
  };
  final coefficients = <String, Matsuzaki2006AttenuationCoefficients>{
    'published': published,
    for (final entry in fits.entries) entry.key: entry.value.coefficients,
  };
  Map<String, Matsuzaki2006ModelEvaluation> evaluateYear(int year) => {
    for (final entry in coefficients.entries)
      entry.key: Matsuzaki2006ModelEvaluation(
        coefficients: entry.value,
        events: eventsByYear[year]!,
      ),
  };

  final training = evaluateYear(2020);
  final validation = evaluateYear(2021);
  const structureCandidates = [
    'fixedPublishedSaturation',
    'fixedPublishedExponent',
    'fixedPublishedCoefficient',
  ];
  final statisticalBestOnValidation = _selectByEventEqualRms(
    validation,
    structureCandidates,
  );
  final reusedHoldout = evaluateYear(2022);

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_structure_identifiability_v1',
    'split': {
      'trainingYear': 2020,
      'validationYear': 2021,
      'reusedHoldoutYear': 2022,
      'eventIsolation': true,
      'holdoutStatus':
          'previously_opened_reuse_diagnostic_not_independent_frozen_test',
      'selectionMetric': 'validation_mean_of_event_root_mean_square_residuals',
      'selectionCandidates': structureCandidates,
      'statisticalBestOnValidation': statisticalBestOnValidation,
      'productionAdoption': false,
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
    'search': {
      'freeGlobal': freeSearchSpec.toJson(),
      'fixedExponentCoefficientSearch': coefficientSearchSpec.toJson(
        parameterName: 'saturationCoefficient',
      ),
      'fixedCoefficientExponentSearch': exponentSearchSpec.toJson(
        parameterName: 'saturationMagnitudeExponent',
      ),
    },
    'fits': {for (final entry in fits.entries) entry.key: entry.value.toJson()},
    'evaluations': {
      'training2020': _evaluationsToJson(training),
      'validation2021': _evaluationsToJson(validation),
      'reusedHoldout2022': _evaluationsToJson(reusedHoldout),
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
      statisticalBestOnValidation: statisticalBestOnValidation,
      fits: fits,
      training: training,
      validation: validation,
      reusedHoldout: reusedHoldout,
    ),
    encoding: utf8,
  );
  stdout.writeln('statisticalBestOnValidation=$statisticalBestOnValidation');
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

String _selectByEventEqualRms(
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
  List<String> candidates,
) {
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
  required String statisticalBestOnValidation,
  required Map<String, Matsuzaki2006CoefficientFit> fits,
  required Map<String, Matsuzaki2006ModelEvaluation> training,
  required Map<String, Matsuzaki2006ModelEvaluation> validation,
  required Map<String, Matsuzaki2006ModelEvaluation> reusedHoldout,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Structure Identifiability')
    ..writeln()
    ..writeln('2020 is training and 2021 is validation. The 2022 data were')
    ..writeln(
      'already opened by the preceding experiment, so this report labels',
    )
    ..writeln('them as reused holdout diagnostics, not a new frozen test.')
    ..writeln()
    ..writeln('Lowest validation event RMS: `$statisticalBestOnValidation`.')
    ..writeln('This numerical ranking is not a structural-validity or')
    ..writeln('production-adoption decision.')
    ..writeln()
    ..writeln('## Coefficients')
    ..writeln()
    ..writeln(
      '| Model | a | b | c | d | e | intercept | Saturation km at M5 | Saturation km at M8.2 |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  _writeCoefficientRow(
    buffer,
    'published',
    Matsuzaki2006AttenuationCoefficients.published,
  );
  for (final entry in fits.entries) {
    _writeCoefficientRow(buffer, entry.key, entry.value.coefficients);
  }
  _writeOverallTable(buffer, 'Training 2020', training);
  _writeOverallTable(buffer, 'Validation 2021', validation);
  _writeOverallTable(buffer, 'Reused Holdout 2022', reusedHoldout);
  _writeGroupedTables(buffer, 'Training 2020', training);
  _writeGroupedTables(buffer, 'Validation 2021', validation);
  _writeGroupedTables(buffer, 'Reused Holdout 2022', reusedHoldout);
  buffer
    ..writeln()
    ..writeln('## Parameter Policies')
    ..writeln();
  for (final entry in fits.entries) {
    buffer.writeln(
      '- `${entry.key}`: `${jsonEncode(entry.value.parameterPolicy)}`',
    );
  }
  return buffer.toString();
}

void _writeCoefficientRow(
  StringBuffer buffer,
  String name,
  Matsuzaki2006AttenuationCoefficients value,
) {
  final atMinimum = _saturationDistance(value, 5.0);
  final atMaximum = _saturationDistance(value, 8.2);
  buffer.writeln(
    '| $name | ${_number(value.magnitudeCoefficient)} | '
    '${_number(value.logDistanceCoefficient)} | '
    '${_number(value.saturationCoefficient)} | '
    '${_number(value.saturationMagnitudeExponent)} | '
    '${_number(value.depthCoefficient)} | ${_number(value.intercept)} | '
    '${atMinimum.toStringAsPrecision(12)} | '
    '${atMaximum.toStringAsPrecision(12)} |',
  );
}

double _saturationDistance(
  Matsuzaki2006AttenuationCoefficients coefficients,
  double magnitude,
) =>
    coefficients.saturationCoefficient *
    math
        .pow(10, coefficients.saturationMagnitudeExponent * magnitude)
        .toDouble();

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
