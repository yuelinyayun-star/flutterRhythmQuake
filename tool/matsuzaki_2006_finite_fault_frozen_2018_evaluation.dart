import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final selectionPath = _value(arguments, '--selection-report');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_finite_fault_frozen_2018_evaluation',
  );
  if (inputPath == null || selectionPath == null) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_finite_fault_frozen_2018_evaluation.dart '
      '--input <2018.json> --selection-report <calibration-report.json> '
      '--allow-opened-2018 [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (!arguments.contains('--allow-opened-2018')) {
    stderr.writeln(
      'Refusing to evaluate 2018 without explicit --allow-opened-2018.',
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
  final selectedModel = _readSelectedModel(selection);
  final coefficients = _readSelectedCoefficients(selection);
  final dataset = _readJsonObject(inputPath);
  if (dataset['year'] != 2018) {
    throw FormatException('Expected opened frozen year 2018 in $inputPath.');
  }
  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final baseline = evaluator.evaluate([dataset]);
  final osakaGeometry = Matsuzaki2006SourceBackedDistanceOverrides
      .eventGeometries
      .singleWhere((geometry) => geometry.year == 2018);
  final osakaPointEvent = baseline.events.singleWhere(
    (event) => event.eventId == osakaGeometry.eventId,
  );

  final scenarioEvents = <String, List<Matsuzaki2006EventBaseline>>{
    'point_source': baseline.events,
  };
  final osakaOverrides = <String, Matsuzaki2006EventDistanceOverride>{};
  for (final variant in osakaGeometry.variants) {
    final override = Matsuzaki2006SourceBackedDistanceOverrides.evaluateVariant(
      event: osakaPointEvent,
      geometry: osakaGeometry,
      variant: variant,
    );
    osakaOverrides[variant.id] = override;
    scenarioEvents[variant.id] = [
      for (final event in baseline.events)
        if (event.eventId == osakaPointEvent.eventId)
          override.toPublishedDomainEvent()
        else
          event,
    ];
  }

  final scenarioReports = <String, Object?>{};
  for (final entry in scenarioEvents.entries) {
    final nearEvents = _nearOnlyEvents(entry.value);
    final selectedEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: coefficients,
      events: entry.value,
    );
    final selectedNearEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: coefficients,
      events: nearEvents,
    );
    final publishedEvaluation = Matsuzaki2006ModelEvaluation(
      coefficients: Matsuzaki2006AttenuationCoefficients.published,
      events: entry.value,
    );
    final osakaEvent = entry.value.singleWhere(
      (event) => event.eventId == osakaPointEvent.eventId,
    );
    final osakaNearStations = osakaEvent.stationResiduals
        .where((station) => station.sourceDistanceKm < 30)
        .toList();
    scenarioReports[entry.key] = {
      'distanceSemantics': entry.key == 'point_source'
          ? 'point_source_hypocentral_distance'
          : 'minimum_3d_distance_to_source_backed_finite_fault_union',
      'allAcceptedEventCount': entry.value.length,
      'allAcceptedStationCount': _stationCount(entry.value),
      'nearfieldEventCount': nearEvents.length,
      'nearfieldStationCount': _stationCount(nearEvents),
      'selectedCoefficientEvaluation': selectedEvaluation.toJson(),
      'selectedCoefficientNearfieldEvaluation': selectedNearEvaluation.toJson(),
      'publishedCoefficientEvaluation': publishedEvaluation.toJson(),
      'osaka': {
        'acceptedStationCount': osakaEvent.stationResiduals.length,
        'nearfieldStationCount': osakaNearStations.length,
        'selectedCoefficientAllStationEvaluation': Matsuzaki2006ModelEvaluation(
          coefficients: coefficients,
          events: [osakaEvent],
        ).toJson(),
        'selectedCoefficientNearStationEvaluation': osakaNearStations.isEmpty
            ? null
            : Matsuzaki2006ModelEvaluation(
                coefficients: coefficients,
                events: [
                  _copyEvent(osakaEvent, stationResiduals: osakaNearStations),
                ],
              ).toJson(),
      },
    };
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_finite_fault_frozen_2018_evaluation_v1',
    'selectionReportPath': selectionPath,
    'selectedModel': selectedModel,
    'selectedCoefficients': coefficients.toJson(),
    'selectionReportDeclared2018Unread': true,
    'selectionWasNotModified': true,
    'productionAdoption': false,
    'branchPolicy': {
      'pointSourceBranch': 'diagnostic_reference_only',
      'osakaSingleAndDoubleBranches': 'both_preserved_for_frozen_comparison',
      'preferredGeometryVariantId': osakaGeometry.preferredVariant.id,
      'preferredGeometrySelectionBasis':
          'independent_aftershock_relocation_focal_mechanism_full_waveform_and_geodetic_source_structure_evidence',
      'geometryDecisionMadeAfterFrozenEvaluation': true,
      'geometryDecisionUsesFrozenEvaluationResidual': false,
      'coefficientRefit': false,
      'modelSelection': false,
    },
    'inputCounts': {
      'events': baseline.events.length,
      'stations': baseline.stationResidualCount,
    },
    'osakaGeometryBranches': [
      for (final variant in osakaGeometry.variants)
        {
          'id': variant.id,
          'label': variant.label,
          'originalPointSourceStationCount':
              osakaPointEvent.stationResiduals.length,
          'retainedPublishedDomainStationCount': osakaOverrides[variant.id]!
              .toPublishedDomainEvent()
              .stationResiduals
              .length,
          'excludedOutsidePublishedDistanceDomain': osakaOverrides[variant.id]!
              .excludedOutsidePublishedDistanceDomainCount,
        },
    ],
    'scenarios': scenarioReports,
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
      scenarioReports: scenarioReports,
      osakaGeometry: osakaGeometry,
      osakaOverrides: osakaOverrides,
    ),
    encoding: utf8,
  );
  stdout.writeln(
    'evaluated 2018 frozen branches=${scenarioEvents.keys.join(',')}',
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

String _readSelectedModel(Map<String, Object?> report) {
  final split = report['split'];
  final selection = report['predeclaredSelection'];
  if (report['schemaVersion'] !=
          'matsuzaki_2006_finite_fault_semantic_calibration_v1' ||
      split is! Map<String, Object?> ||
      split['frozenEvaluationYearNotRead'] != 2018 ||
      split['year2018ReadByThisTool'] != false ||
      selection is! Map<String, Object?>) {
    throw const FormatException(
      'Selection report does not prove that 2018 remained unread.',
    );
  }
  final selectedModel = selection['selectedModel'];
  if (selectedModel is! String || selectedModel.isEmpty) {
    throw const FormatException('Selection report has no selected model.');
  }
  return selectedModel;
}

Matsuzaki2006AttenuationCoefficients _readSelectedCoefficients(
  Map<String, Object?> report,
) {
  final selection = report['predeclaredSelection'];
  if (selection is! Map<String, Object?> ||
      selection['selectedCoefficients'] is! Map<String, Object?>) {
    throw const FormatException(
      'Selection report has no selected coefficients.',
    );
  }
  final raw = selection['selectedCoefficients']! as Map<String, Object?>;
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
      'Selected coefficients do not retain fixed c=0.00675 and d=0.5.',
    );
  }
  return coefficients;
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
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
      _copyEvent(
        event,
        stationResiduals: event.stationResiduals
            .where((station) => station.sourceDistanceKm < 30)
            .toList(),
      ),
];

Matsuzaki2006EventBaseline _copyEvent(
  Matsuzaki2006EventBaseline event, {
  required List<Matsuzaki2006StationResidual> stationResiduals,
}) => Matsuzaki2006EventBaseline(
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
  stationResiduals: stationResiduals,
);

int _stationCount(List<Matsuzaki2006EventBaseline> events) =>
    events.fold(0, (sum, event) => sum + event.stationResiduals.length);

String _toMarkdown({
  required String selectedModel,
  required Matsuzaki2006AttenuationCoefficients coefficients,
  required Map<String, Object?> scenarioReports,
  required Matsuzaki2006SourceBackedEventGeometry osakaGeometry,
  required Map<String, Matsuzaki2006EventDistanceOverride> osakaOverrides,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Finite-Fault Frozen 2018 Evaluation')
    ..writeln()
    ..writeln('The `$selectedModel` coefficients were frozen using 2010-2016')
    ..writeln('calibration and 2017 selection before this tool read 2018.')
    ..writeln(
      'No coefficient or model choice is written back from this report.',
    )
    ..writeln()
    ..writeln('Selected coefficients: `${coefficients.toJson()}`.')
    ..writeln()
    ..writeln('## Osaka Geometry Branches')
    ..writeln()
    ..writeln('| Branch | Original | Retained | Excluded |')
    ..writeln('|---|---:|---:|---:|');
  for (final variant in osakaGeometry.variants) {
    final override = osakaOverrides[variant.id]!;
    buffer.writeln(
      '| `${variant.id}` | ${override.stations.length} | '
      '${override.stations.length - override.excludedOutsidePublishedDistanceDomainCount} | '
      '${override.excludedOutsidePublishedDistanceDomainCount} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Frozen Scenario Metrics')
    ..writeln()
    ..writeln(
      '| Scenario | All stations | Near stations | All event RMS | Near event RMS | Osaka all RMS | Osaka near RMS |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final entry in scenarioReports.entries) {
    final scenario = entry.value! as Map<String, Object?>;
    final all =
        scenario['selectedCoefficientEvaluation']! as Map<String, Object?>;
    final near =
        scenario['selectedCoefficientNearfieldEvaluation']!
            as Map<String, Object?>;
    final osaka = scenario['osaka']! as Map<String, Object?>;
    final osakaAll =
        osaka['selectedCoefficientAllStationEvaluation']!
            as Map<String, Object?>;
    final osakaNear =
        osaka['selectedCoefficientNearStationEvaluation']
            as Map<String, Object?>?;
    buffer.writeln(
      '| `${entry.key}` | ${scenario['allAcceptedStationCount']} | '
      '${scenario['nearfieldStationCount']} | ${_eventRmsFromJson(all)} | '
      '${_eventRmsFromJson(near)} | ${_eventRmsFromJson(osakaAll)} | '
      '${osakaNear == null ? 'n/a' : _eventRmsFromJson(osakaNear)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('Both Osaka branches remain visible in the frozen comparison.')
    ..writeln(
      'Independent source-structure evidence selects '
      '`${osakaGeometry.preferredVariant.id}` as the preferred physical '
      'geometry; the single rectangle remains a lower-resolution GNSS '
      'simplification. This geometry decision was recorded after the frozen '
      'evaluation and does not use its residual values.',
    );
  return buffer.toString();
}

String _eventRmsFromJson(Map<String, Object?> evaluation) {
  final eventEqual = evaluation['eventEqual']! as Map<String, Object?>;
  return (eventEqual['meanOfEventRootMeanSquareResiduals']! as num)
      .toDouble()
      .toStringAsFixed(6);
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}
