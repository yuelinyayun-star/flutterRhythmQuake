import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final calibrationPaths = _values(arguments, '--calibration-input');
  final validationPaths = _values(arguments, '--validation-input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_near_far_balance',
  );
  if (calibrationPaths.isEmpty || validationPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_near_far_balance.dart '
      '--calibration-input <annual.json> [...] '
      '--validation-input <annual.json> [...] [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final missing = [
    ...calibrationPaths,
    ...validationPaths,
  ].where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final calibrationEvents = _loadEvents(
    calibrationPaths,
    expectedYears: {for (var year = 2010; year <= 2016; year++) year},
    evaluator: evaluator,
  );
  final calibrationMixedEvents = _eventsWithMinimumNearStations(
    calibrationEvents,
    minimumNearStations: 2,
    retainAllStations: true,
  );
  final validationEvents = _loadEvents(
    validationPaths,
    expectedYears: const {2017},
    evaluator: evaluator,
  );
  final validationMixedEvents = _eventsWithMinimumNearStations(
    validationEvents,
    minimumNearStations: 2,
    retainAllStations: true,
  );
  final validationNearOnly = _eventsWithMinimumNearStations(
    validationEvents,
    minimumNearStations: 2,
    retainAllStations: false,
  );
  if (calibrationMixedEvents.isEmpty || validationNearOnly.isEmpty) {
    throw StateError('Near/far calibration or validation events are empty.');
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
  final fits = <String, Matsuzaki2006CoefficientFit>{};
  stdout.writeln('fitting natural within-event station weights...');
  fits['naturalMixedSource'] = calibrator.fitEventSourceStripped(
    trainingEvents: calibrationMixedEvents,
    searchSpec: searchSpec,
  );
  fits['naturalAllSource'] = calibrator.fitEventSourceStripped(
    trainingEvents: calibrationMixedEvents,
    sourceTermEvents: calibrationEvents,
    searchSpec: searchSpec,
  );
  for (final nearWeight in const [0.25, 0.5, 0.75]) {
    final prefix = 'nearGroupWeight${(nearWeight * 100).round()}';
    stdout.writeln('fitting ${prefix}MixedSource...');
    fits['${prefix}MixedSource'] = calibrator
        .fitEventSourceStrippedDistanceBalanced(
          trainingEvents: calibrationMixedEvents,
          searchSpec: searchSpec,
          balanceSpec: Matsuzaki2006DistanceBalanceSpec(
            nearDistanceThresholdKm: 30,
            nearGroupWeight: nearWeight,
          ),
        );
    stdout.writeln('fitting ${prefix}AllSource...');
    fits['${prefix}AllSource'] = calibrator
        .fitEventSourceStrippedDistanceBalanced(
          trainingEvents: calibrationMixedEvents,
          sourceTermEvents: calibrationEvents,
          searchSpec: searchSpec,
          balanceSpec: Matsuzaki2006DistanceBalanceSpec(
            nearDistanceThresholdKm: 30,
            nearGroupWeight: nearWeight,
          ),
        );
  }

  const published = Matsuzaki2006AttenuationCoefficients.published;
  stdout.writeln('fitting fixedNaturalAllSource...');
  fits['fixedNaturalAllSource'] = calibrator
      .fitEventSourceStrippedWithFixedSaturation(
        trainingEvents: calibrationMixedEvents,
        sourceTermEvents: calibrationEvents,
        saturationCoefficient: published.saturationCoefficient,
        saturationMagnitudeExponent: published.saturationMagnitudeExponent,
      );
  for (final nearWeight in const [0.25, 0.5, 0.75]) {
    final prefix = 'fixedNearWeight${(nearWeight * 100).round()}AllSource';
    stdout.writeln('fitting $prefix...');
    fits[prefix] = calibrator.fitEventSourceStrippedWithFixedSaturation(
      trainingEvents: calibrationMixedEvents,
      sourceTermEvents: calibrationEvents,
      saturationCoefficient: published.saturationCoefficient,
      saturationMagnitudeExponent: published.saturationMagnitudeExponent,
      balanceSpec: Matsuzaki2006DistanceBalanceSpec(
        nearDistanceThresholdKm: 30,
        nearGroupWeight: nearWeight,
      ),
    );
  }

  final nearEvaluations = <String, Matsuzaki2006ModelEvaluation>{
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: validationNearOnly,
    ),
  };
  final mixedEvaluations = <String, Matsuzaki2006ModelEvaluation>{
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: validationMixedEvents,
    ),
  };
  final allEvaluations = <String, Matsuzaki2006ModelEvaluation>{
    'published': Matsuzaki2006ModelEvaluation(
      coefficients: published,
      events: validationEvents,
    ),
  };
  for (final entry in fits.entries) {
    nearEvaluations[entry.key] = Matsuzaki2006ModelEvaluation(
      coefficients: entry.value.coefficients,
      events: validationNearOnly,
    );
    mixedEvaluations[entry.key] = Matsuzaki2006ModelEvaluation(
      coefficients: entry.value.coefficients,
      events: validationMixedEvents,
    );
    allEvaluations[entry.key] = Matsuzaki2006ModelEvaluation(
      coefficients: entry.value.coefficients,
      events: validationEvents,
    );
  }
  final publishedNearRms = _eventRms(nearEvaluations['published']!);
  final publishedAllRms = _eventRms(allEvaluations['published']!);
  final acceptance = <String, Object?>{};
  for (final entry in fits.entries) {
    final name = entry.key;
    final nearRms = _eventRms(nearEvaluations[name]!);
    final allRms = _eventRms(allEvaluations[name]!);
    final passesMetricGate =
        nearRms < publishedNearRms && allRms <= publishedAllRms;
    final structuralGate =
        entry.value.method ==
            Matsuzaki2006CalibrationMethod.eventSourceStrippedFixedSaturation &&
        entry.value.coefficients.saturationCoefficient ==
            published.saturationCoefficient &&
        entry.value.coefficients.saturationMagnitudeExponent ==
            published.saturationMagnitudeExponent;
    acceptance[name] = {
      'nearValidationEventRms': nearRms,
      'publishedNearValidationEventRms': publishedNearRms,
      'nearImprovesPublished': nearRms < publishedNearRms,
      'allDistanceValidationEventRms': allRms,
      'publishedAllDistanceValidationEventRms': publishedAllRms,
      'allDistanceDoesNotWorsenPublished': allRms <= publishedAllRms,
      'passesMetricGate': passesMetricGate,
      'structuralGate': structuralGate,
      'passesAllPredeclaredConditions': passesMetricGate && structuralGate,
    };
  }

  final acceptedFixedModels =
      fits.keys.where((name) {
        final value = acceptance[name]! as Map<String, Object?>;
        return value['passesAllPredeclaredConditions']! as bool;
      }).toList()..sort(
        (left, right) => _eventRms(
          nearEvaluations[left]!,
        ).compareTo(_eventRms(nearEvaluations[right]!)),
      );
  final selectedModel = acceptedFixedModels.isEmpty
      ? null
      : acceptedFixedModels.first;

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_near_far_balance_v2',
    'split': {
      'calibrationYears': [for (var year = 2010; year <= 2016; year++) year],
      'validationYears': [2017],
      'frozenYearsNotRead': [2018],
      'eventIsolation': true,
      'productionAdoption': false,
    },
    'trainingSelection': {
      'requiresAtLeastNearStations': 2,
      'nearDistanceThresholdKm': 30.0,
      'retainsAllFarStationsForSelectedEvents': true,
      'selectedEvents': calibrationMixedEvents.length,
      'selectedStations': _stationCount(calibrationMixedEvents),
      'allSourceTermEvents': calibrationEvents.length,
      'allSourceTermStations': _stationCount(calibrationEvents),
    },
    'validation': {
      'allAcceptedEvents': validationEvents.length,
      'allAcceptedStations': _stationCount(validationEvents),
      'mixedNearFarEvents': validationMixedEvents.length,
      'mixedNearFarStations': _stationCount(validationMixedEvents),
      'nearOnlyEvents': validationNearOnly.length,
      'nearOnlyStations': _stationCount(validationNearOnly),
    },
    'predeclaredMetricGate': {
      'nearCondition': 'event_rms_strictly_below_published',
      'allDistanceCondition': 'event_rms_not_above_published',
      'structuralCondition':
          'published_saturation_coefficient_and_exponent_fixed',
      'openFrozenYearOnlyAfterAllConditions': true,
    },
    'frozenYearDecision': {
      'acceptedFixedModels': acceptedFixedModels,
      'selectionRule': 'lowest_2017_near_validation_event_rms',
      'selectedModel': selectedModel,
      'selectedCoefficients': selectedModel == null
          ? null
          : fits[selectedModel]!.coefficients.toJson(),
      'year2018ReadByThisTool': false,
      'nextAction': selectedModel == null
          ? 'keep_2018_frozen'
          : 'freeze_selected_model_then_evaluate_2018_once',
    },
    'search': searchSpec.toJson(),
    'fits': {for (final entry in fits.entries) entry.key: entry.value.toJson()},
    'nearValidation': _evaluationsToJson(nearEvaluations),
    'mixedEventAllDistanceValidation': _evaluationsToJson(mixedEvaluations),
    'allEventAllDistanceValidation': _evaluationsToJson(allEvaluations),
    'acceptance': acceptance,
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
      fits: fits,
      nearEvaluations: nearEvaluations,
      mixedEvaluations: mixedEvaluations,
      allEvaluations: allEvaluations,
      acceptance: acceptance,
      selectedModel: selectedModel,
    ),
    encoding: utf8,
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

List<Matsuzaki2006EventBaseline> _loadEvents(
  List<String> paths, {
  required Set<int> expectedYears,
  required Matsuzaki2006JmaBaselineEvaluator evaluator,
  int? retainOnlyEventsWithMinimumNearStations,
}) {
  final events = <Matsuzaki2006EventBaseline>[];
  final loadedYears = <int>{};
  for (final path in paths) {
    final dataset =
        jsonDecode(File(path).readAsStringSync(encoding: utf8))
            as Map<String, Object?>;
    final year = (dataset['year']! as num).toInt();
    if (!expectedYears.contains(year) || !loadedYears.add(year)) {
      throw FormatException('Unexpected or duplicate year $year in $path.');
    }
    final result = evaluator.evaluate([dataset]);
    events.addAll(
      retainOnlyEventsWithMinimumNearStations == null
          ? result.events
          : _eventsWithMinimumNearStations(
              result.events,
              minimumNearStations: retainOnlyEventsWithMinimumNearStations,
              retainAllStations: true,
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

List<Matsuzaki2006EventBaseline> _eventsWithMinimumNearStations(
  List<Matsuzaki2006EventBaseline> source, {
  required int minimumNearStations,
  required bool retainAllStations,
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
        stationResiduals: retainAllStations
            ? event.stationResiduals
            : event.stationResiduals
                  .where((station) => station.sourceDistanceKm < 30)
                  .toList(),
      ),
];

double _eventRms(Matsuzaki2006ModelEvaluation evaluation) =>
    evaluation.eventEqualMetrics['meanOfEventRootMeanSquareResiduals']!
        as double;

int _stationCount(List<Matsuzaki2006EventBaseline> events) =>
    events.fold(0, (sum, event) => sum + event.stationResiduals.length);

Map<String, Object> _evaluationsToJson(
  Map<String, Matsuzaki2006ModelEvaluation> evaluations,
) => {for (final entry in evaluations.entries) entry.key: entry.value.toJson()};

String _toMarkdown({
  required Map<String, Matsuzaki2006CoefficientFit> fits,
  required Map<String, Matsuzaki2006ModelEvaluation> nearEvaluations,
  required Map<String, Matsuzaki2006ModelEvaluation> mixedEvaluations,
  required Map<String, Matsuzaki2006ModelEvaluation> allEvaluations,
  required Map<String, Object?> acceptance,
  required String? selectedModel,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Near/Far Balance')
    ..writeln()
    ..writeln('Calibration uses 2010-2016 events with at least two nearfield')
    ..writeln('stations and retains every farfield station in those events.')
    ..writeln(
      'Validation is 2017. The predeclared 2018 frozen year is not read.',
    )
    ..writeln()
    ..writeln('## Fits')
    ..writeln()
    ..writeln(
      '| Model | a | b | c | d | e | intercept | M5 saturation km | M8.2 saturation km |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final entry in fits.entries) {
    final fit = entry.value;
    final c = fit.coefficients;
    buffer.writeln(
      '| ${entry.key} | ${_precision(c.magnitudeCoefficient)} | '
      '${_precision(c.logDistanceCoefficient)} | '
      '${_precision(c.saturationCoefficient)} | '
      '${_precision(c.saturationMagnitudeExponent)} | '
      '${_precision(c.depthCoefficient)} | ${_precision(c.intercept)} | '
      '${_precision(fit.saturationDistanceAtMinimumMagnitudeKm)} | '
      '${_precision(fit.saturationDistanceAtMaximumMagnitudeKm)} |',
    );
  }
  _writeEvaluation(buffer, 'Nearfield Validation', nearEvaluations);
  _writeEvaluation(
    buffer,
    'Mixed-Event All-Distance Validation',
    mixedEvaluations,
  );
  _writeEvaluation(buffer, 'All-Event All-Distance Validation', allEvaluations);
  buffer
    ..writeln()
    ..writeln('## Predeclared Gate')
    ..writeln()
    ..writeln(
      '| Model | Near improves | All distance not worse | Metric gate | Structural gate | All conditions |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final entry in acceptance.entries) {
    final value = entry.value! as Map<String, Object?>;
    buffer.writeln(
      '| ${entry.key} | ${value['nearImprovesPublished']} | '
      '${value['allDistanceDoesNotWorsenPublished']} | '
      '${value['passesMetricGate']} | ${value['structuralGate']} | '
      '${value['passesAllPredeclaredConditions']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Frozen-Year Decision')
    ..writeln()
    ..writeln(
      selectedModel == null
          ? 'No fixed-structure model passed every predeclared condition. '
                'The 2018 frozen year remains unread.'
          : 'Selected `$selectedModel` by the lowest 2017 nearfield event '
                'RMS among models passing every condition. This tool did not '
                'read the 2018 frozen year.',
    );
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

String _precision(double value) => value.toStringAsPrecision(9);
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
