import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final calibrationPaths = _values(arguments, '--calibration-input');
  final validationPaths = _values(arguments, '--validation-input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_nearfield_calibration',
  );
  if (calibrationPaths.isEmpty || validationPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_nearfield_calibration.dart '
      '--calibration-input <annual.json> [...] '
      '--validation-input <annual.json> [...] [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final allPaths = [...calibrationPaths, ...validationPaths];
  final missing = allPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final calibrationEvents = _loadBaselineEvents(
    calibrationPaths,
    expectedYears: {for (var year = 2010; year <= 2016; year++) year},
    evaluator: evaluator,
    minimumNearStationsToRetain: 2,
  );
  final validationEvents = _loadBaselineEvents(
    validationPaths,
    expectedYears: const {2017},
    evaluator: evaluator,
  );
  final commonValidationNear = _nearEvents(
    validationEvents,
    minimumNearStations: 2,
  );
  if (commonValidationNear.isEmpty) {
    throw StateError('The common nearfield validation set is empty.');
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
  const thresholds = [2, 5, 10];
  final experiments = <String, Object?>{};
  final commonValidationEvaluations = <String, Matsuzaki2006ModelEvaluation>{
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: Matsuzaki2006AttenuationCoefficients.published,
      events: commonValidationNear,
    ),
  };
  final allDistanceValidationEvaluations =
      <String, Matsuzaki2006ModelEvaluation>{
        'published': Matsuzaki2006ModelEvaluation(
          coefficients: Matsuzaki2006AttenuationCoefficients.published,
          events: validationEvents,
        ),
      };

  for (final threshold in thresholds) {
    final name = 'minimumNearStations$threshold';
    final trainingNear = _nearEvents(
      calibrationEvents,
      minimumNearStations: threshold,
    );
    final matchedValidationNear = _nearEvents(
      validationEvents,
      minimumNearStations: threshold,
    );
    stdout.writeln(
      'fitting $name trainingEvents=${trainingNear.length} '
      'trainingStations=${_stationCount(trainingNear)} '
      'matchedValidationEvents=${matchedValidationNear.length}',
    );
    final fit = calibrator.fitEventSourceStripped(
      trainingEvents: trainingNear,
      searchSpec: searchSpec,
    );
    final trainingEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: trainingNear,
    );
    final matchedValidationEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: matchedValidationNear,
    );
    final commonValidationEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: commonValidationNear,
    );
    final allDistanceValidationEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: fit.coefficients,
      events: validationEvents,
    );
    commonValidationEvaluations[name] = commonValidationEvaluation;
    allDistanceValidationEvaluations[name] = allDistanceValidationEvaluation;
    experiments[name] = {
      'minimumNearStationsPerEvent': threshold,
      'trainingNearEventCount': trainingNear.length,
      'trainingNearStationCount': _stationCount(trainingNear),
      'matchedValidationNearEventCount': matchedValidationNear.length,
      'matchedValidationNearStationCount': _stationCount(matchedValidationNear),
      'fit': fit.toJson(),
      'trainingNearEvaluation': trainingEvaluation.toJson(),
      'matchedValidationNearEvaluation': matchedValidationEvaluation.toJson(),
      'commonValidationNearEvaluation': commonValidationEvaluation.toJson(),
      'allDistanceValidationEvaluation': allDistanceValidationEvaluation
          .toJson(),
    };
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_nearfield_calibration_v1',
    'split': {
      'calibrationYears': [for (var year = 2010; year <= 2016; year++) year],
      'validationYears': [2017],
      'frozenYearsNotRead': [2018],
      'eventIsolation': true,
      'productionAdoption': false,
    },
    'nearfieldDefinition': {
      'distance': 'point_source_hypocentral_distance',
      'minimumKm': Matsuzaki2006AttenuationModel.minimumSourceDistanceKm,
      'maximumExclusiveKm': 30.0,
      'baselineMinimumTotalStationsPerEvent': evaluator.minimumStationsPerEvent,
      'thresholdsCompared': thresholds,
      'commonValidationMinimumNearStations': 2,
    },
    'input': {
      'calibrationPaths': calibrationPaths,
      'validationPaths': validationPaths,
      'calibrationNearEventsAtMinimum2': calibrationEvents.length,
      'validationAcceptedEventsBeforeNearFilter': validationEvents.length,
      'commonValidationNearEvents': commonValidationNear.length,
      'commonValidationNearStations': _stationCount(commonValidationNear),
    },
    'search': searchSpec.toJson(),
    'experiments': experiments,
    'commonValidationNearComparison': _evaluationsToJson(
      commonValidationEvaluations,
    ),
    'allDistanceValidationComparison': _evaluationsToJson(
      allDistanceValidationEvaluations,
    ),
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
      report: report,
      commonValidation: commonValidationEvaluations,
      allDistanceValidation: allDistanceValidationEvaluations,
    ),
    encoding: utf8,
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

List<Matsuzaki2006EventBaseline> _loadBaselineEvents(
  List<String> paths, {
  required Set<int> expectedYears,
  required Matsuzaki2006JmaBaselineEvaluator evaluator,
  int? minimumNearStationsToRetain,
}) {
  final events = <Matsuzaki2006EventBaseline>[];
  final loadedYears = <int>{};
  for (final path in paths) {
    final dataset =
        jsonDecode(File(path).readAsStringSync(encoding: utf8))
            as Map<String, Object?>;
    final year = (dataset['year']! as num).toInt();
    if (!expectedYears.contains(year)) {
      throw FormatException(
        'Unexpected year $year in $path; expected $expectedYears.',
      );
    }
    if (!loadedYears.add(year)) {
      throw FormatException('Duplicate annual dataset for year $year.');
    }
    final result = evaluator.evaluate([dataset]);
    events.addAll(
      minimumNearStationsToRetain == null
          ? result.events
          : _nearEvents(
              result.events,
              minimumNearStations: minimumNearStationsToRetain,
            ),
    );
    stdout.writeln(
      'loaded year=$year accepted=${result.events.length} '
      'stations=${result.stationResidualCount}',
    );
  }
  if (!loadedYears.containsAll(expectedYears)) {
    throw FormatException(
      'Missing expected years: ${expectedYears.difference(loadedYears)}.',
    );
  }
  events.sort((left, right) => left.originTime.compareTo(right.originTime));
  return events;
}

List<Matsuzaki2006EventBaseline> _nearEvents(
  List<Matsuzaki2006EventBaseline> source, {
  required int minimumNearStations,
}) => [
  for (final event in source)
    if (event.stationResiduals
            .where((station) => station.sourceDistanceKm < 30)
            .length >=
        minimumNearStations)
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

Map<String, Object> _evaluationsToJson(
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) => {for (final entry in evaluations.entries) entry.key: entry.value.toJson()};

String _toMarkdown({
  required Map<String, Object?> report,
  required Map<String, Matsuzaki2006ModelEvaluation> commonValidation,
  required Map<String, Matsuzaki2006ModelEvaluation> allDistanceValidation,
}) {
  final experiments = report['experiments']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Nearfield Calibration Sensitivity')
    ..writeln()
    ..writeln('Calibration years are 2010-2016 and validation year is 2017.')
    ..writeln('The predeclared 2018 frozen year is not read.')
    ..writeln(
      'Every fit uses event-source stripping and equal total weight per',
    )
    ..writeln('event for the within-event distance-shape objective.')
    ..writeln()
    ..writeln('## Fits')
    ..writeln()
    ..writeln(
      '| Model | Train events | Train stations | a | b | c | d | e | intercept | M5 saturation km | M8.2 saturation km |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final entry in experiments.entries) {
    final experiment = entry.value! as Map<String, Object?>;
    final fit = experiment['fit']! as Map<String, Object?>;
    final coefficients = fit['coefficients']! as Map<String, Object?>;
    buffer.writeln(
      '| ${entry.key} | ${experiment['trainingNearEventCount']} | '
      '${experiment['trainingNearStationCount']} | '
      '${_precision(coefficients['magnitudeCoefficient'])} | '
      '${_precision(coefficients['logDistanceCoefficient'])} | '
      '${_precision(coefficients['saturationCoefficient'])} | '
      '${_precision(coefficients['saturationMagnitudeExponent'])} | '
      '${_precision(coefficients['depthCoefficient'])} | '
      '${_precision(coefficients['intercept'])} | '
      '${_precision(fit['saturationDistanceAtMinimumMagnitudeKm'])} | '
      '${_precision(fit['saturationDistanceAtMaximumMagnitudeKm'])} |',
    );
  }
  _writeComparison(
    buffer,
    'Common Nearfield Validation (2017, minimum 2 near stations)',
    commonValidation,
  );
  _writeComparison(
    buffer,
    'All-Distance Validation (all accepted 2017 events)',
    allDistanceValidation,
  );
  return buffer.toString();
}

void _writeComparison(
  StringBuffer buffer,
  String title,
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) {
  buffer
    ..writeln()
    ..writeln('## $title')
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

String _precision(Object? value) =>
    (value! as num).toDouble().toStringAsPrecision(9);
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
