import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final calibrationPaths = _values(arguments, '--calibration-input');
  final validationPaths = _values(arguments, '--validation-input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_finite_fault_semantic_calibration',
  );
  if (calibrationPaths.isEmpty || validationPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_finite_fault_semantic_calibration.dart '
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
  final pointSourceCalibrationEvents = _loadEvents(
    calibrationPaths,
    expectedYears: {for (var year = 2010; year <= 2016; year++) year},
    evaluator: evaluator,
  );
  final semanticApplication =
      Matsuzaki2006SourceBackedDistanceOverrides.applyUnambiguousCalibrationOverrides(
        pointSourceCalibrationEvents,
      );
  final calibrationEvents = semanticApplication.events;
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
  final validationNearOnly = _eventsWithMinimumNearStations(
    validationEvents,
    minimumNearStations: 2,
    retainAllStations: false,
  );
  if (calibrationMixedEvents.isEmpty || validationNearOnly.isEmpty) {
    throw StateError('Finite-fault calibration or validation is empty.');
  }

  const published = Matsuzaki2006AttenuationCoefficients.published;
  const calibrator = Matsuzaki2006CoefficientCalibrator();
  final fits = <String, Matsuzaki2006CoefficientFit>{};
  stdout.writeln('fitting fixedNaturalAllSource...');
  fits['fixedNaturalAllSource'] = calibrator
      .fitEventSourceStrippedWithFixedSaturation(
        trainingEvents: calibrationMixedEvents,
        sourceTermEvents: calibrationEvents,
        saturationCoefficient: published.saturationCoefficient,
        saturationMagnitudeExponent: published.saturationMagnitudeExponent,
      );
  for (final nearWeight in const [0.25, 0.5, 0.75]) {
    final name = 'fixedNearWeight${(nearWeight * 100).round()}AllSource';
    stdout.writeln('fitting $name...');
    fits[name] = calibrator.fitEventSourceStrippedWithFixedSaturation(
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
    allEvaluations[entry.key] = Matsuzaki2006ModelEvaluation(
      coefficients: entry.value.coefficients,
      events: validationEvents,
    );
  }

  final publishedNearRms = _eventRms(nearEvaluations['published']!);
  final publishedAllRms = _eventRms(allEvaluations['published']!);
  final acceptance = <String, Map<String, Object>>{};
  for (final entry in fits.entries) {
    final nearRms = _eventRms(nearEvaluations[entry.key]!);
    final allRms = _eventRms(allEvaluations[entry.key]!);
    acceptance[entry.key] = {
      'nearValidationEventRms': nearRms,
      'publishedNearValidationEventRms': publishedNearRms,
      'nearImprovesPublished': nearRms < publishedNearRms,
      'allDistanceValidationEventRms': allRms,
      'publishedAllDistanceValidationEventRms': publishedAllRms,
      'allDistanceDoesNotWorsenPublished': allRms <= publishedAllRms,
      'passesAllPredeclaredConditions':
          nearRms < publishedNearRms && allRms <= publishedAllRms,
    };
  }
  final acceptedModels =
      fits.keys.where((name) {
        return acceptance[name]!['passesAllPredeclaredConditions']! as bool;
      }).toList()..sort(
        (left, right) => _eventRms(
          nearEvaluations[left]!,
        ).compareTo(_eventRms(nearEvaluations[right]!)),
      );
  final selectedModel = acceptedModels.isEmpty ? null : acceptedModels.first;

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_finite_fault_semantic_calibration_v1',
    'split': {
      'calibrationYears': [for (var year = 2010; year <= 2016; year++) year],
      'validationYear': 2017,
      'frozenEvaluationYearNotRead': 2018,
      'year2018ReadByThisTool': false,
      'productionAdoption': false,
    },
    'distanceSemantics': {
      'sourceBackedTargetStrongEvents':
          'minimum_3d_distance_to_finite_fault_union',
      'otherAcceptedEvents': 'point_source_hypocentral_distance',
      'outsidePublishedDomainPolicy':
          'preserve_geometry_record_but_exclude_from_formula_without_clamping',
      'overriddenEvents': [
        for (final override in semanticApplication.overrides)
          {
            'eventId': override.originalEvent.eventId,
            'year': override.originalEvent.year,
            'regionName': override.geometry.regionName,
            'geometryVariantId': override.variant.id,
            'originalAcceptedStations': override.stations.length,
            'retainedPublishedDomainStations':
                override.stations.length -
                override.excludedOutsidePublishedDistanceDomainCount,
            'excludedOutsidePublishedDistanceDomain':
                override.excludedOutsidePublishedDistanceDomainCount,
          },
      ],
      'excludedOutsidePublishedDistanceDomainTotal':
          semanticApplication.excludedOutsidePublishedDistanceDomainCount,
    },
    'trainingSelection': {
      'requiresAtLeastNearStations': 2,
      'nearDistanceThresholdKm': 30.0,
      'nearSelectionUsesFinalSourceDistanceSemantics': true,
      'retainsAllFarStationsForSelectedEvents': true,
      'allAcceptedEvents': calibrationEvents.length,
      'allAcceptedStationsBeforeDistanceOverride': _stationCount(
        pointSourceCalibrationEvents,
      ),
      'allAcceptedStationsAfterDomainExclusion': _stationCount(
        calibrationEvents,
      ),
      'selectedEvents': calibrationMixedEvents.length,
      'selectedStations': _stationCount(calibrationMixedEvents),
      'sourceTermEvents': calibrationEvents.length,
      'sourceTermStations': _stationCount(calibrationEvents),
    },
    'validation': {
      'distanceSemantics': 'point_source_no_source_backed_override_candidate',
      'allAcceptedEvents': validationEvents.length,
      'allAcceptedStations': _stationCount(validationEvents),
      'nearOnlyEvents': validationNearOnly.length,
      'nearOnlyStations': _stationCount(validationNearOnly),
    },
    'fixedStructure': {
      'saturationCoefficient': published.saturationCoefficient,
      'saturationMagnitudeExponent': published.saturationMagnitudeExponent,
      'candidateModels': fits.keys.toList(),
    },
    'predeclaredSelection': {
      'nearCondition': '2017_event_rms_strictly_below_published',
      'allDistanceCondition': '2017_event_rms_not_above_published',
      'selectionRule': 'lowest_2017_near_event_rms_among_passing_models',
      'acceptedModels': acceptedModels,
      'selectedModel': selectedModel,
      'selectedCoefficients': selectedModel == null
          ? null
          : fits[selectedModel]!.coefficients.toJson(),
    },
    'fits': {for (final entry in fits.entries) entry.key: entry.value.toJson()},
    'nearValidation': _evaluationsToJson(nearEvaluations),
    'allDistanceValidation': _evaluationsToJson(allEvaluations),
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
      semanticApplication: semanticApplication,
      calibrationEvents: calibrationEvents,
      calibrationMixedEvents: calibrationMixedEvents,
      validationEvents: validationEvents,
      validationNearOnly: validationNearOnly,
      fits: fits,
      nearEvaluations: nearEvaluations,
      allEvaluations: allEvaluations,
      acceptance: acceptance,
      selectedModel: selectedModel,
    ),
    encoding: utf8,
  );
  stdout.writeln('selectedModel=$selectedModel');
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

List<Matsuzaki2006EventBaseline> _loadEvents(
  List<String> paths, {
  required Set<int> expectedYears,
  required Matsuzaki2006JmaBaselineEvaluator evaluator,
}) {
  final events = <Matsuzaki2006EventBaseline>[];
  final loadedYears = <int>{};
  for (final path in paths) {
    final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Expected a JSON object in $path.');
    }
    final yearValue = decoded['year'];
    if (yearValue is! num) {
      throw FormatException('Annual dataset has no numeric year in $path.');
    }
    final year = yearValue.toInt();
    if (!expectedYears.contains(year) || !loadedYears.add(year)) {
      throw FormatException('Unexpected or duplicate year $year in $path.');
    }
    final result = evaluator.evaluate([decoded]);
    events.addAll(result.events);
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
  required Matsuzaki2006DistanceSemanticApplication semanticApplication,
  required List<Matsuzaki2006EventBaseline> calibrationEvents,
  required List<Matsuzaki2006EventBaseline> calibrationMixedEvents,
  required List<Matsuzaki2006EventBaseline> validationEvents,
  required List<Matsuzaki2006EventBaseline> validationNearOnly,
  required Map<String, Matsuzaki2006CoefficientFit> fits,
  required Map<String, Matsuzaki2006ModelEvaluation> nearEvaluations,
  required Map<String, Matsuzaki2006ModelEvaluation> allEvaluations,
  required Map<String, Map<String, Object>> acceptance,
  required String? selectedModel,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Finite-Fault Distance Semantic Calibration')
    ..writeln()
    ..writeln('Calibration uses 2010-2016 only. Source-backed target strong')
    ..writeln('events use finite-fault minimum distance; all other accepted')
    ..writeln(
      'events retain point-source hypocentral distance. Validation uses',
    )
    ..writeln('2017 point-source semantics because no accepted source-backed')
    ..writeln('finite-fault replacement candidate exists in that year.')
    ..writeln()
    ..writeln('The tool does not read 2018. Osaka is evaluated later as two')
    ..writeln(
      'parallel frozen geometry branches and never enters coefficient fit.',
    )
    ..writeln()
    ..writeln('## Distance Overrides')
    ..writeln()
    ..writeln('| Event | Region | Variant | Original | Retained | Excluded |')
    ..writeln('|---|---|---|---:|---:|---:|');
  for (final override in semanticApplication.overrides) {
    buffer.writeln(
      '| `${override.originalEvent.eventId}` | ${override.geometry.regionName} | '
      '`${override.variant.id}` | ${override.stations.length} | '
      '${override.stations.length - override.excludedOutsidePublishedDistanceDomainCount} | '
      '${override.excludedOutsidePublishedDistanceDomainCount} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('All calibration events/stations after domain exclusion: ')
    ..writeln(
      '${calibrationEvents.length}/${_stationCount(calibrationEvents)}. '
      'Distance-shape events/stations: ${calibrationMixedEvents.length}/'
      '${_stationCount(calibrationMixedEvents)}.',
    )
    ..writeln(
      'Validation all events/stations: ${validationEvents.length}/'
      '${_stationCount(validationEvents)}; near events/stations: '
      '${validationNearOnly.length}/${_stationCount(validationNearOnly)}.',
    )
    ..writeln()
    ..writeln('## Fits')
    ..writeln()
    ..writeln('| Model | a | b | c | d | e | intercept |')
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final entry in fits.entries) {
    final coefficients = entry.value.coefficients;
    buffer.writeln(
      '| ${entry.key} | ${_precision(coefficients.magnitudeCoefficient)} | '
      '${_precision(coefficients.logDistanceCoefficient)} | '
      '${_precision(coefficients.saturationCoefficient)} | '
      '${_precision(coefficients.saturationMagnitudeExponent)} | '
      '${_precision(coefficients.depthCoefficient)} | '
      '${_precision(coefficients.intercept)} |',
    );
  }
  _writeEvaluation(buffer, '2017 Nearfield Validation', nearEvaluations);
  _writeEvaluation(buffer, '2017 All-Distance Validation', allEvaluations);
  buffer
    ..writeln()
    ..writeln('## Predeclared Gate')
    ..writeln()
    ..writeln('| Model | Near improves | All distance not worse | Passes |')
    ..writeln('|---|---|---|---|');
  for (final entry in acceptance.entries) {
    buffer.writeln(
      '| ${entry.key} | ${entry.value['nearImprovesPublished']} | '
      '${entry.value['allDistanceDoesNotWorsenPublished']} | '
      '${entry.value['passesAllPredeclaredConditions']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('Selected by the unchanged 2017 rule: `$selectedModel`.')
    ..writeln('This is an experiment result, not production adoption.');
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
    ..writeln('| Model | Events | Stations | Station RMS | Event RMS |')
    ..writeln('|---|---:|---:|---:|---:|');
  for (final entry in evaluations.entries) {
    buffer.writeln(
      '| ${entry.key} | ${entry.value.events.length} | '
      '${entry.value.stationWeightedSummary.count} | '
      '${_metric(entry.value.stationWeightedSummary.rootMeanSquareResidual)} | '
      '${_metric(_eventRms(entry.value))} |',
    );
  }
}

String _precision(double value) => value.toStringAsPrecision(9);
String _metric(double value) => value.toStringAsFixed(6);

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
