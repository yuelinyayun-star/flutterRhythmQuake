import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_tohoku_upstream_source_family_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_upstream_source_family_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _threshold = _Threshold('shindo4', 3.5);

const _sourceTriggerFamilies = ['jma_only', 'plum_only', 'both'];
const _sourceWinnerFamilies = ['jma_higher', 'plum_higher', 'tied'];
const _transitionLabels = ['middle_transition_zone', 'other_focus_samples'];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuUpstreamSourceFamilyDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuUpstreamSourceFamilyDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku upstream source-family diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuUpstreamSourceFamilyDiagnosticJson({
  String dataDirectory = _defaultDataDirectory,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final modelFile = File(modelPath);
  final splitFile = File('$dataDirectory/splits.json');
  final annualFiles = [
    File('$dataDirectory/jma_final_intensity_2020.json'),
    File('$dataDirectory/jma_final_intensity_2021.json'),
    File('$dataDirectory/jma_final_intensity_2022.json'),
  ];
  if (!modelFile.existsSync()) errors.add('model_missing:$modelPath');
  if (!splitFile.existsSync()) {
    errors.add('split_manifest_missing:${splitFile.path}');
  }
  for (final file in annualFiles) {
    if (!file.existsSync()) errors.add('annual_dataset_missing:${file.path}');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      dataDirectory: dataDirectory,
      modelPath: modelPath,
    );
  }

  final annualDatasets = [
    for (final file in annualFiles)
      decodeJmaIntensityDataset(file.readAsStringSync()),
  ];
  final splits =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final synthetic = const SyntheticRevealDatasetBuilder(
    generatedSplits: ['validation', 'test'],
  ).build(annualDatasets: annualDatasets, splitManifest: splits);

  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictor = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
  );
  final plumR20D050 = const PlumLikeIntensityPredictor(
    radiusKm: 20.0,
    dampingPer10Km: 0.50,
  );
  final plumR30D075 = const PlumLikeIntensityPredictor(
    radiusKm: 30.0,
    dampingPer10Km: 0.75,
  );

  final splitAccumulators = {
    'validation': _SplitAccumulator(),
    'test': _SplitAccumulator(),
  };
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final splitName in const ['validation', 'test']) {
    final dataset = synthetic.datasetsBySplit[splitName]!;
    final splitAccumulator = splitAccumulators[splitName]!;
    for (final rawEvent in _list(dataset['events'])) {
      final event = StaticIntensityEvent.fromJson(_map(rawEvent));
      final magnitude = event.magnitude;
      if (magnitude == null || !magnitude.isFinite) {
        skippedMissingMagnitude++;
        continue;
      }
      final stationsById = {
        for (final station in event.stations) station.stationId: station,
      };
      for (final variant in event.variants) {
        final retained = [
          for (final id in variant.retainedStationIds)
            if (stationsById[id] != null) stationsById[id]!,
        ];
        final estimate = locator.locate(retained);
        if (estimate == null) {
          skippedNoEstimate++;
          continue;
        }
        splitAccumulator.variantCount++;
        if (_eventLatitudeBucket(estimate.latitude) != _focusRegion) continue;

        for (final station in event.stations) {
          splitAccumulator.stationForecastCount++;
          final jma = jmaPredictor
              .predict(
                magnitude: magnitude,
                sourceLatitude: estimate.latitude,
                sourceLongitude: estimate.longitude,
                depthKm: estimate.depthKm,
                stationLatitude: station.latitude,
                stationLongitude: station.longitude,
              )
              .intensity;
          final plum = plumPredictor.predict(
            targetStation: station,
            observedStations: retained,
          );
          final baselineRaw = math.max(jma, plum.intensity);
          if (baselineRaw < _threshold.value) continue;
          if (plum.evidenceCount < _focusMinimumEvidenceCount) continue;
          if (!plum.nearestEvidenceDistanceKm.isFinite ||
              plum.nearestEvidenceDistanceKm >=
                  _focusMaximumNearestEvidenceDistanceKm) {
            continue;
          }

          final r20 = plumR20D050.predict(
            targetStation: station,
            observedStations: retained,
          );
          final r30D075 = plumR30D075.predict(
            targetStation: station,
            observedStations: retained,
          );
          splitAccumulator.add(
            _buildSample(
              event: event,
              variant: variant,
              targetStation: station,
              retainedStations: retained,
              threshold: _threshold,
              jmaPredictedIntensity: jma,
              plum: plum,
              r20: r20.intensity,
              r30D075: r30D075.intensity,
            ),
          );
        }
      }
    }
  }

  final validation = splitAccumulators['validation']!;
  final test = splitAccumulators['test']!;

  return {
    'schemaVersion': 'plum_tohoku_upstream_source_family_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku upstream source-family diagnostic',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'suppressionApplied': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'splits': ['validation', 'test'],
      'threshold': _threshold.label,
    },
    'focusFilter': {
      'estimatedSourceRegion': _focusRegion,
      'minimumEvidenceCount': _focusMinimumEvidenceCount,
      'maximumNearestEvidenceDistanceKm':
          _focusMaximumNearestEvidenceDistanceKm,
      'baselineThresholdCrossingRequired': true,
      'plumMarginGateApplied': false,
    },
    'familyDefinitions': {
      'sourceTriggerFamily': {
        'jma_only': 'JMA-style crosses threshold, PLUM r30/d0.50 does not',
        'plum_only': 'PLUM r30/d0.50 crosses threshold, JMA-style does not',
        'both': 'both JMA-style and PLUM r30/d0.50 cross threshold',
      },
      'sourceWinnerFamily': {
        'jma_higher': 'JMA-style predicted intensity > PLUM r30/d0.50',
        'plum_higher': 'PLUM r30/d0.50 predicted intensity > JMA-style',
        'tied': 'JMA-style predicted intensity == PLUM r30/d0.50',
      },
      'eventFamily': {
        'localConsistency':
            'consistent if below-threshold share in 10km < 0.25, mixed if < 0.50, else mismatch',
        'geometry': 'surrounded if supporting quadrants >= 3, else one_sided',
        'spread':
            'compact if max evidence spread < 20km, moderate if < 40km, else wide',
      },
    },
    'labelDefinition': const {
      'positiveLabel': 'middle_transition_zone',
      'truthInputs': [
        'actualGapBand in {-1.0_to_0.0, 0.0_to_1.0}',
        'evidenceGapBand in {1.0_to_2.0, 2.0_to_3.0}',
        'localConsistencyLabel == mismatch',
      ],
      'negativeLabel': 'other_focus_samples',
      'purpose':
          'use the middle-transition label only as diagnostic context while auditing broader source-family transfer',
    },
    'coverage': {
      'validationVariants': validation.variantCount,
      'testVariants': test.variantCount,
      'validationStationForecasts': validation.stationForecastCount,
      'testStationForecasts': test.stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'splitSummaries': {
      'validation': _summaryJson(validation.samples),
      'test': _summaryJson(test.samples),
    },
    'sourceTriggerFamilyTransfer': _buildFamilyTransferRows(
      validation.samples,
      test.samples,
      familyOrder: _sourceTriggerFamilies,
      selector: (sample) => sample.sourceTriggerFamily,
    ),
    'sourceWinnerFamilyTransfer': _buildFamilyTransferRows(
      validation.samples,
      test.samples,
      familyOrder: _sourceWinnerFamilies,
      selector: (sample) => sample.sourceWinnerFamily,
    ),
    'sourceWinnerTransitionTransfer': _buildJointTransferRows(
      validation.samples,
      test.samples,
      firstOrder: _sourceWinnerFamilies,
      secondOrder: _transitionLabels,
      firstSelector: (sample) => sample.sourceWinnerFamily,
      secondSelector: (sample) => sample.transitionLabel,
    ),
    'sourceWinnerEventFamilyTransfer': _buildJointTransferRows(
      validation.samples,
      test.samples,
      firstOrder: _sourceWinnerFamilies,
      secondOrder: _eventFamilies(validation.samples, test.samples),
      firstSelector: (sample) => sample.sourceWinnerFamily,
      secondSelector: (sample) => sample.eventFamilyLabel,
    ),
    'dominantTestEvents': _buildEventRows(test.samples),
    'errors': errors,
  };
}

_Sample _buildSample({
  required StaticIntensityEvent event,
  required StaticIntensityVariant variant,
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> retainedStations,
  required _Threshold threshold,
  required double jmaPredictedIntensity,
  required PlumLikeIntensityPrediction plum,
  required double r20,
  required double r30D075,
}) {
  final supportingEvidence = _supportingEvidence(
    retainedStations: retainedStations,
    targetStation: targetStation,
    threshold: threshold.value,
  );
  final strongestEvidence = supportingEvidence.isEmpty
      ? null
      : supportingEvidence.reduce((left, right) {
          if (left.propagatedIntensity == right.propagatedIntensity) {
            return left.targetDistanceKm <= right.targetDistanceKm
                ? left
                : right;
          }
          return left.propagatedIntensity >= right.propagatedIntensity
              ? left
              : right;
        });
  final local10 = _localNeighborSummary(
    event.stations,
    targetStation,
    threshold.value,
    10.0,
  );
  final supportShape = _supportShape(
    targetStation: targetStation,
    evidenceStations: supportingEvidence,
  );

  return _Sample(
    eventId: event.eventId,
    variantId: variant.variantId,
    stationId: targetStation.stationId,
    thresholdValue: threshold.value,
    actual: targetStation.intensity,
    jma: jmaPredictedIntensity,
    plum: plum.intensity,
    r20: r20,
    r30D075: r30D075,
    evidenceTargetGap: strongestEvidence == null
        ? double.nan
        : strongestEvidence.station.intensity - targetStation.intensity,
    localBelowThresholdShare10Km: local10.belowThresholdShare,
    supportingEvidenceQuadrantCoverage: supportShape.quadrantCoverage,
    supportingEvidenceMaxSpreadKm: supportShape.maxSpreadKm,
  );
}

List<Map<String, Object?>> _buildFamilyTransferRows(
  List<_Sample> validation,
  List<_Sample> test, {
  required List<String> familyOrder,
  required String Function(_Sample sample) selector,
}) {
  return [
    for (final family in familyOrder)
      _familyTransferRow(
        family: family,
        validation: validation.where((sample) => selector(sample) == family).toList(),
        validationTotal: validation.length,
        test: test.where((sample) => selector(sample) == family).toList(),
        testTotal: test.length,
      ),
  ];
}

Map<String, Object?> _familyTransferRow({
  required String family,
  required List<_Sample> validation,
  required int validationTotal,
  required List<_Sample> test,
  required int testTotal,
}) {
  final validationJson = _familySnapshot(validation, validationTotal);
  final testJson = _familySnapshot(test, testTotal);
  return {
    'family': family,
    'validation': validationJson,
    'test': testJson,
    'deltaShare': _number(testJson['share']) - _number(validationJson['share']),
    'deltaPrecision':
        _number(testJson['precision']) - _number(validationJson['precision']),
    'deltaMiddleTransitionRate':
        _number(testJson['middleTransitionRate']) -
        _number(validationJson['middleTransitionRate']),
    'deltaMeanPlumMinusJma':
        _number(testJson['meanPlumMinusJma']) -
        _number(validationJson['meanPlumMinusJma']),
  };
}

Map<String, Object?> _familySnapshot(List<_Sample> samples, int total) {
  final actualPositiveCount =
      samples.where((sample) => sample.actualPositive).length;
  final middleTransitionCount =
      samples.where((sample) => sample.isMiddleTransitionZone).length;
  final plumOnlyFalsePositiveCount =
      samples.where((sample) => sample.plumOnlyFalsePositive).length;
  final meanPlumMinusJma = samples.isEmpty
      ? 0.0
      : samples
              .map((sample) => sample.plumMinusJma)
              .fold<double>(0.0, (sum, gap) => sum + gap) /
          samples.length;
  return {
    'count': samples.length,
    'share': total == 0 ? 0.0 : samples.length / total,
    'actualPositiveCount': actualPositiveCount,
    'precision': samples.isEmpty ? 0.0 : actualPositiveCount / samples.length,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionRate':
        samples.isEmpty ? 0.0 : middleTransitionCount / samples.length,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
    'meanPlumMinusJma': meanPlumMinusJma,
  };
}

List<Map<String, Object?>> _buildJointTransferRows(
  List<_Sample> validation,
  List<_Sample> test, {
  required List<String> firstOrder,
  required List<String> secondOrder,
  required String Function(_Sample sample) firstSelector,
  required String Function(_Sample sample) secondSelector,
}) {
  final rows = <Map<String, Object?>>[];
  for (final first in firstOrder) {
    for (final second in secondOrder) {
      final validationRows = validation
          .where(
            (sample) =>
                firstSelector(sample) == first && secondSelector(sample) == second,
          )
          .toList();
      final testRows = test
          .where(
            (sample) =>
                firstSelector(sample) == first && secondSelector(sample) == second,
          )
          .toList();
      if (validationRows.isEmpty && testRows.isEmpty) continue;
      rows.add({
        'first': first,
        'second': second,
        'validation': _familySnapshot(validationRows, validation.length),
        'test': _familySnapshot(testRows, test.length),
        'deltaShare':
            (test.isEmpty ? 0.0 : testRows.length / test.length) -
            (validation.isEmpty
                ? 0.0
                : validationRows.length / validation.length),
      });
    }
  }
  rows.sort((left, right) {
    final rightTest = _number(_map(right['test'])['count']);
    final leftTest = _number(_map(left['test'])['count']);
    final byTest = rightTest.compareTo(leftTest);
    if (byTest != 0) return byTest;
    final rightValidation = _number(_map(right['validation'])['count']);
    final leftValidation = _number(_map(left['validation'])['count']);
    return rightValidation.compareTo(leftValidation);
  });
  return rows;
}

List<String> _eventFamilies(List<_Sample> validation, List<_Sample> test) {
  final families = <String>{};
  for (final sample in [...validation, ...test]) {
    families.add(sample.eventFamilyLabel);
  }
  final ordered = families.toList()..sort();
  return ordered;
}

List<Map<String, Object?>> _buildEventRows(List<_Sample> samples) {
  final byEvent = <String, _EventAccumulator>{};
  for (final sample in samples) {
    byEvent.putIfAbsent(sample.eventId, _EventAccumulator.new).add(sample);
  }
  final rows = [
    for (final entry in byEvent.entries) entry.value.toJson(eventId: entry.key),
  ];
  rows.sort((left, right) {
    final byCount =
        _number(right['count']).compareTo(_number(left['count']));
    if (byCount != 0) return byCount;
    return _number(right['middleTransitionCount']).compareTo(
      _number(left['middleTransitionCount']),
    );
  });
  return rows;
}

Map<String, Object?> _summaryJson(List<_Sample> samples) {
  final actualPositiveCount =
      samples.where((sample) => sample.actualPositive).length;
  final middleTransitionCount =
      samples.where((sample) => sample.isMiddleTransitionZone).length;
  final plumOnlyFalsePositiveCount =
      samples.where((sample) => sample.plumOnlyFalsePositive).length;
  return {
    'focusSampleCount': samples.length,
    'truePositiveCount': actualPositiveCount,
    'falsePositiveCount': samples.length - actualPositiveCount,
    'precision': samples.isEmpty ? 0.0 : actualPositiveCount / samples.length,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionShare':
        samples.isEmpty ? 0.0 : middleTransitionCount / samples.length,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
  };
}

List<_EvidenceStation> _supportingEvidence({
  required List<StaticIntensityStation> retainedStations,
  required StaticIntensityStation targetStation,
  required double threshold,
}) {
  final supportingEvidence = <_EvidenceStation>[];
  for (final observed in retainedStations) {
    if (observed.stationId == targetStation.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      observed.latitude,
      observed.longitude,
    );
    if (distance > _plumRadiusKm) continue;
    final propagated = observed.intensity -
        _plumDampingPer10Km * (distance / 10.0);
    if (propagated >= threshold) {
      supportingEvidence.add(
        _EvidenceStation(
          station: observed,
          targetDistanceKm: distance,
          propagatedIntensity: propagated,
        ),
      );
    }
  }
  return supportingEvidence;
}

_NeighborSummary _localNeighborSummary(
  List<StaticIntensityStation> stations,
  StaticIntensityStation target,
  double threshold,
  double radiusKm,
) {
  var count = 0;
  var below = 0;
  for (final station in stations) {
    if (station.stationId == target.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      target.latitude,
      target.longitude,
      station.latitude,
      station.longitude,
    );
    if (distance > radiusKm) continue;
    count++;
    if (station.intensity < threshold) below++;
  }
  return _NeighborSummary(
    count: count,
    belowThresholdShare: count == 0 ? 0.0 : below / count,
  );
}

_SupportShape _supportShape({
  required StaticIntensityStation targetStation,
  required List<_EvidenceStation> evidenceStations,
}) {
  if (evidenceStations.isEmpty) {
    return const _SupportShape(quadrantCoverage: 0, maxSpreadKm: 0.0);
  }
  final quadrants = <int>{};
  var maxSpread = 0.0;
  for (final evidence in evidenceStations) {
    quadrants.add(
      _quadrant(
        targetLat: targetStation.latitude,
        targetLng: targetStation.longitude,
        lat: evidence.station.latitude,
        lng: evidence.station.longitude,
      ),
    );
  }
  for (var i = 0; i < evidenceStations.length; i++) {
    for (var j = i + 1; j < evidenceStations.length; j++) {
      final distance = QuakeCalculator.haversineDistance(
        evidenceStations[i].station.latitude,
        evidenceStations[i].station.longitude,
        evidenceStations[j].station.latitude,
        evidenceStations[j].station.longitude,
      );
      if (distance > maxSpread) maxSpread = distance;
    }
  }
  return _SupportShape(
    quadrantCoverage: quadrants.length,
    maxSpreadKm: maxSpread,
  );
}

int _quadrant({
  required double targetLat,
  required double targetLng,
  required double lat,
  required double lng,
}) {
  final north = lat >= targetLat;
  final east = lng >= targetLng;
  if (north && east) return 0;
  if (north && !east) return 1;
  if (!north && east) return 2;
  return 3;
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
        'schemaVersion': 'plum_tohoku_upstream_source_family_diagnostic_v1',
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'status': 'fail',
        'policy': {
          'method': 'PLUM Tohoku upstream source-family diagnostic',
          'rawPredictedIntensityMutated': false,
          'frozenTestEvaluated': true,
          'productionReady': false,
          'productionUiConnected': false,
          'diagnosticOnly': true,
          'parametersTuned': false,
          'suppressionApplied': false,
          'plumRadiusKm': _plumRadiusKm,
          'plumDampingPer10Km': _plumDampingPer10Km,
        },
        'inputs': {
          'dataDirectory': dataDirectory,
          'modelPath': modelPath,
          'splits': ['validation', 'test'],
          'threshold': _threshold.label,
        },
        'focusFilter': {
          'estimatedSourceRegion': _focusRegion,
          'minimumEvidenceCount': _focusMinimumEvidenceCount,
          'maximumNearestEvidenceDistanceKm':
              _focusMaximumNearestEvidenceDistanceKm,
          'baselineThresholdCrossingRequired': true,
          'plumMarginGateApplied': false,
        },
        'splitSummaries': {
          'validation': _summaryJson(const []),
          'test': _summaryJson(const []),
        },
        'sourceTriggerFamilyTransfer': const [],
        'sourceWinnerFamilyTransfer': const [],
        'sourceWinnerTransitionTransfer': const [],
        'sourceWinnerEventFamilyTransfer': const [],
        'dominantTestEvents': const [],
        'errors': errors,
      };

String plumTohokuUpstreamSourceFamilyDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final familyDefinitions = _map(report['familyDefinitions']);
  final splitSummaries = _map(report['splitSummaries']);
  final sourceTriggerFamilyTransfer = _list(report['sourceTriggerFamilyTransfer']);
  final sourceWinnerFamilyTransfer = _list(report['sourceWinnerFamilyTransfer']);
  final sourceWinnerTransitionTransfer =
      _list(report['sourceWinnerTransitionTransfer']);
  final sourceWinnerEventFamilyTransfer =
      _list(report['sourceWinnerEventFamilyTransfer']);
  final dominantTestEvents = _list(report['dominantTestEvents']);

  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Upstream Source-Family Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Method: `${policy['method']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln('- Production UI connected: `${policy['productionUiConnected']}`')
    ..writeln('- Diagnostic only: `${policy['diagnosticOnly']}`')
    ..writeln('- Parameters tuned: `${policy['parametersTuned']}`')
    ..writeln('- Suppression applied: `${policy['suppressionApplied']}`')
    ..writeln(
      '- Raw predicted intensity mutated: '
      '`${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln()
    ..writeln('## Coverage')
    ..writeln()
    ..writeln(
      '- Validation variants: `${coverage['validationVariants']}`',
    )
    ..writeln('- Test variants: `${coverage['testVariants']}`')
    ..writeln(
      '- Validation station forecasts: `${coverage['validationStationForecasts']}`',
    )
    ..writeln('- Test station forecasts: `${coverage['testStationForecasts']}`')
    ..writeln()
    ..writeln('## Focus Filter')
    ..writeln()
    ..writeln(
      '- Estimated-source region: `${focusFilter['estimatedSourceRegion']}`',
    )
    ..writeln(
      '- Minimum evidence count: `${focusFilter['minimumEvidenceCount']}`',
    )
    ..writeln(
      '- Maximum nearest evidence distance: '
      '`${focusFilter['maximumNearestEvidenceDistanceKm']} km`',
    )
    ..writeln(
      '- Baseline threshold crossing required: '
      '`${focusFilter['baselineThresholdCrossingRequired']}`',
    )
    ..writeln(
      '- PLUM margin gate applied: `${focusFilter['plumMarginGateApplied']}`',
    )
    ..writeln()
    ..writeln('## Definitions')
    ..writeln();

  for (final definitionName in const [
    'sourceTriggerFamily',
    'sourceWinnerFamily',
    'eventFamily',
  ]) {
    final definition = _map(familyDefinitions[definitionName]);
    buffer.writeln('- `$definitionName`');
    for (final entry in definition.entries) {
      buffer.writeln('  - `${entry.key}`: ${entry.value}');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Split Summaries')
    ..writeln()
    ..writeln(
      '| Split | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final splitName in const ['validation', 'test']) {
    final summary = _map(splitSummaries[splitName]);
    buffer.writeln(
      '| $splitName | ${summary['focusSampleCount']} | '
      '${summary['truePositiveCount']} | ${summary['falsePositiveCount']} | '
      '${_pct(summary['precision'])} | ${summary['middleTransitionCount']} '
      '(${_pct(summary['middleTransitionShare'])}) | '
      '${summary['plumOnlyFalsePositiveCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Trigger Family Transfer')
    ..writeln()
    ..writeln(
      '| Family | Validation | Test | Delta Share | Delta Precision | Delta Middle Transition |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: |');
  for (final raw in sourceTriggerFamilyTransfer) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['family']}` | ${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['test']))} | ${_signedPct(row['deltaShare'])} | '
      '${_signedPct(row['deltaPrecision'])} | '
      '${_signedPct(row['deltaMiddleTransitionRate'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Winner Family Transfer')
    ..writeln()
    ..writeln(
      '| Family | Validation | Test | Delta Share | Delta Precision | Delta Middle Transition | Delta (PLUM-JMA) |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: |');
  for (final raw in sourceWinnerFamilyTransfer) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['family']}` | ${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['test']))} | ${_signedPct(row['deltaShare'])} | '
      '${_signedPct(row['deltaPrecision'])} | '
      '${_signedPct(row['deltaMiddleTransitionRate'])} | '
      '${_signed(row['deltaMeanPlumMinusJma'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Winner x Transition Transfer')
    ..writeln()
    ..writeln(
      '| Winner | Label | Validation | Test | Delta Share |',
    )
    ..writeln('| --- | --- | --- | --- | ---: |');
  for (final raw in sourceWinnerTransitionTransfer) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['first']}` | `${row['second']}` | '
      '${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['test']))} | '
      '${_signedPct(row['deltaShare'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Winner x Event Family Transfer')
    ..writeln()
    ..writeln(
      '| Winner | Event Family | Validation | Test | Delta Share |',
    )
    ..writeln('| --- | --- | --- | --- | ---: |');
  for (final raw in sourceWinnerEventFamilyTransfer.take(15)) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['first']}` | `${row['second']}` | '
      '${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['test']))} | '
      '${_signedPct(row['deltaShare'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Dominant Test Events')
    ..writeln()
    ..writeln(
      '| Event | Samples | TP | FP | Precision | Middle Transition | Dominant Winner | Dominant Event Family | Trigger Mix | Winner Mix |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |',
    );
  for (final raw in dominantTestEvents.take(12)) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['eventId']}` | ${row['count']} | ${row['truePositiveCount']} | '
      '${row['falsePositiveCount']} | ${_pct(row['precision'])} | '
      '${row['middleTransitionCount']} (${_pct(row['middleTransitionShare'])}) | '
      '`${row['dominantWinnerFamily']}` | `${row['dominantEventFamily']}` | '
      '${_mixCell(_map(row['sourceTriggerCounts']))} | '
      '${_mixCell(_map(row['sourceWinnerCounts']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report stays diagnostic-only and does not tune PLUM, mutate raw '
      'predicted intensity, or connect anything to UI, wording, or notification.',
    )
    ..writeln(
      '- Its purpose is to identify whether the current frozen hotspot is '
      'primarily a PLUM-led source-family transfer problem before any future '
      'calibration or runtime change is considered.',
    )
    ..writeln();

  return buffer.toString();
}

String _familyCell(Map<String, Object?> row) {
  return '${row['count']} / ${_pct(row['share'])}, '
      'P ${_pct(row['precision'])}, '
      'MT ${_pct(row['middleTransitionRate'])}';
}

String _mixCell(Map<String, Object?> mix) {
  final entries = mix.entries.toList()
    ..sort((left, right) => _number(right.value).compareTo(_number(left.value)));
  return entries
      .where((entry) => _number(entry.value) > 0)
      .map((entry) => '${entry.key}:${entry.value}')
      .join(', ');
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final samples = <_Sample>[];

  void add(_Sample sample) => samples.add(sample);
}

class _EventAccumulator {
  int count = 0;
  int truePositiveCount = 0;
  int middleTransitionCount = 0;
  final sourceTriggerCounts = {
    for (final family in _sourceTriggerFamilies) family: 0,
  };
  final sourceWinnerCounts = {
    for (final family in _sourceWinnerFamilies) family: 0,
  };
  final eventFamilyCounts = <String, int>{};

  void add(_Sample sample) {
    count++;
    if (sample.actualPositive) truePositiveCount++;
    if (sample.isMiddleTransitionZone) middleTransitionCount++;
    sourceTriggerCounts[sample.sourceTriggerFamily] =
        sourceTriggerCounts[sample.sourceTriggerFamily]! + 1;
    sourceWinnerCounts[sample.sourceWinnerFamily] =
        sourceWinnerCounts[sample.sourceWinnerFamily]! + 1;
    eventFamilyCounts[sample.eventFamilyLabel] =
        (eventFamilyCounts[sample.eventFamilyLabel] ?? 0) + 1;
  }

  Map<String, Object?> toJson({required String eventId}) => {
        'eventId': eventId,
        'count': count,
        'truePositiveCount': truePositiveCount,
        'falsePositiveCount': count - truePositiveCount,
        'precision': count == 0 ? 0.0 : truePositiveCount / count,
        'middleTransitionCount': middleTransitionCount,
        'middleTransitionShare':
            count == 0 ? 0.0 : middleTransitionCount / count,
        'dominantWinnerFamily': _maxKey(sourceWinnerCounts),
        'dominantEventFamily': _maxKey(eventFamilyCounts),
        'sourceTriggerCounts': sourceTriggerCounts,
        'sourceWinnerCounts': sourceWinnerCounts,
      };
}

String _maxKey(Map<String, int> counts) {
  if (counts.isEmpty) return 'none';
  var bestKey = counts.keys.first;
  var bestValue = counts[bestKey]!;
  for (final entry in counts.entries.skip(1)) {
    if (entry.value > bestValue) {
      bestKey = entry.key;
      bestValue = entry.value;
    }
  }
  return bestKey;
}

class _Sample {
  final String eventId;
  final String variantId;
  final String stationId;
  final double thresholdValue;
  final double actual;
  final double jma;
  final double plum;
  final double r20;
  final double r30D075;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceMaxSpreadKm;

  const _Sample({
    required this.eventId,
    required this.variantId,
    required this.stationId,
    required this.thresholdValue,
    required this.actual,
    required this.jma,
    required this.plum,
    required this.r20,
    required this.r30D075,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceMaxSpreadKm,
  });

  bool get actualPositive => actual >= thresholdValue;

  bool get plumOnlyFalsePositive =>
      !actualPositive && plum >= thresholdValue && jma < thresholdValue;

  double get plumMinusJma => plum - jma;

  String get sourceTriggerFamily {
    final jmaPositive = jma >= thresholdValue;
    final plumPositive = plum >= thresholdValue;
    if (jmaPositive && !plumPositive) return 'jma_only';
    if (plumPositive && !jmaPositive) return 'plum_only';
    return 'both';
  }

  String get sourceWinnerFamily {
    if ((plum - jma).abs() < 1e-9) return 'tied';
    return plum > jma ? 'plum_higher' : 'jma_higher';
  }

  int get branchAgreementCount {
    var count = 0;
    if (jma >= thresholdValue) count++;
    if (r20 >= thresholdValue) count++;
    if (r30D075 >= thresholdValue) count++;
    return count;
  }

  String get localConsistencyLabel {
    if (localBelowThresholdShare10Km < 0.25) return 'consistent';
    if (localBelowThresholdShare10Km < 0.50) return 'mixed';
    return 'mismatch';
  }

  String get geometryBand =>
      supportingEvidenceQuadrantCoverage >= 3 ? 'surrounded' : 'one_sided';

  String get spreadBand {
    if (supportingEvidenceMaxSpreadKm < 20.0) return 'compact';
    if (supportingEvidenceMaxSpreadKm < 40.0) return 'moderate';
    return 'wide';
  }

  String get eventFamilyLabel =>
      '$localConsistencyLabel/$geometryBand/$spreadBand';

  String get actualGapBand {
    final gap = actual - thresholdValue;
    if (gap < -2.0) return 'lt_-2.0';
    if (gap < -1.0) return '-2.0_to_-1.0';
    if (gap < 0.0) return '-1.0_to_0.0';
    if (gap < 1.0) return '0.0_to_1.0';
    return 'gte_1.0';
  }

  String get evidenceGapBand {
    if (!evidenceTargetGap.isFinite) return 'missing';
    if (evidenceTargetGap < 1.0) return 'lt_1.0';
    if (evidenceTargetGap < 2.0) return '1.0_to_2.0';
    if (evidenceTargetGap < 3.0) return '2.0_to_3.0';
    return 'gte_3.0';
  }

  bool get isMiddleTransitionZone =>
      localConsistencyLabel == 'mismatch' &&
      const ['-1.0_to_0.0', '0.0_to_1.0'].contains(actualGapBand) &&
      const ['1.0_to_2.0', '2.0_to_3.0'].contains(evidenceGapBand);

  String get transitionLabel => isMiddleTransitionZone
      ? 'middle_transition_zone'
      : 'other_focus_samples';
}

class _EvidenceStation {
  final StaticIntensityStation station;
  final double targetDistanceKm;
  final double propagatedIntensity;

  const _EvidenceStation({
    required this.station,
    required this.targetDistanceKm,
    required this.propagatedIntensity,
  });
}

class _NeighborSummary {
  final int count;
  final double belowThresholdShare;

  const _NeighborSummary({required this.count, required this.belowThresholdShare});
}

class _SupportShape {
  final int quadrantCoverage;
  final double maxSpreadKm;

  const _SupportShape({
    required this.quadrantCoverage,
    required this.maxSpreadKm,
  });
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41.0) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

StaticAttenuationModel _modelFromJson(Map<String, Object?> json) {
  return StaticAttenuationModel(
    modelId: json['modelId']?.toString() ?? 'static_intensity_attenuation_v1',
    logDistanceCoefficient: _number(json['logDistanceCoefficient']),
    linearDistanceCoefficient: _number(json['linearDistanceCoefficient']),
    nearDistanceKm: _number(json['nearDistanceKm']),
    huberDelta: _number(json['huberDelta']),
    residualScale: _number(json['residualScale']),
    centroidPenaltyPerKm: _number(json['centroidPenaltyPerKm']),
    depthClassesKm: [
      for (final raw in _list(json['depthClassesKm'])) _number(raw),
    ],
  );
}

Map<String, Object?> _map(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Object?> _list(Object? value) => (value as List?)?.cast<Object?>() ?? const [];

double _number(Object? value) => (value as num?)?.toDouble() ?? 0.0;

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';

String _signedPct(Object? value) {
  final number = _number(value) * 100;
  final sign = number > 0 ? '+' : '';
  return '$sign${number.toStringAsFixed(1)}pp';
}

String _signed(Object? value) {
  final number = _number(value);
  final sign = number > 0 ? '+' : '';
  return '$sign${number.toStringAsFixed(2)}';
}
