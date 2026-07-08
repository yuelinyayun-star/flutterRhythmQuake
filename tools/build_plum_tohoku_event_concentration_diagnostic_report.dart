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
    '.dart_tool/plum_tohoku_event_concentration_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_event_concentration_diagnostic.generated.md';

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

  final report = buildPlumTohokuEventConcentrationDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuEventConcentrationDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku event-concentration diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuEventConcentrationDiagnosticJson({
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

  final validationAccumulator = _SplitAccumulator();
  final testAccumulator = _SplitAccumulator();
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final splitName in const ['validation', 'test']) {
    final dataset = synthetic.datasetsBySplit[splitName]!;
    final splitAccumulator =
        splitName == 'validation' ? validationAccumulator : testAccumulator;
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

  final validationSamples = validationAccumulator.samples;
  final testSamples = testAccumulator.samples;
  final dominantEventId = _dominantEventId(testSamples);
  final dominantTestEventSamples = [
    for (final sample in testSamples)
      if (sample.eventId == dominantEventId) sample,
  ];
  final leaveTopEventOutSamples = [
    for (final sample in testSamples)
      if (sample.eventId != dominantEventId) sample,
  ];
  final eventRows = _buildEventRows(testSamples);

  return {
    'schemaVersion': 'plum_tohoku_event_concentration_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku event-concentration diagnostic',
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
    'labelDefinition': const {
      'positiveLabel': 'middle_transition_zone',
      'truthInputs': [
        'actualGapBand in {-1.0_to_0.0, 0.0_to_1.0}',
        'evidenceGapBand in {1.0_to_2.0, 2.0_to_3.0}',
        'localConsistencyLabel == mismatch',
      ],
      'negativeLabel': 'other_focus_samples',
    },
    'coverage': {
      'validationVariants': validationAccumulator.variantCount,
      'testVariants': testAccumulator.variantCount,
      'validationStationForecasts': validationAccumulator.stationForecastCount,
      'testStationForecasts': testAccumulator.stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'dominantEvent': {
      'eventId': dominantEventId,
      'testFocusCount': dominantTestEventSamples.length,
      'testFocusShare':
          testSamples.isEmpty ? 0.0 : dominantTestEventSamples.length / testSamples.length,
      'top3CumulativeShare': _topCumulativeShare(eventRows, 3, testSamples.length),
      'top5CumulativeShare': _topCumulativeShare(eventRows, 5, testSamples.length),
    },
    'sliceSummaries': {
      'validation': _summaryJson(validationSamples),
      'testFull': _summaryJson(testSamples),
      'dominantTestEventOnly': _summaryJson(dominantTestEventSamples),
      'testWithoutDominantEvent': _summaryJson(leaveTopEventOutSamples),
    },
    'summaryDelta': {
      'testFullVsLeaveTopEventOut': _deltaSummary(
        _summaryJson(testSamples),
        _summaryJson(leaveTopEventOutSamples),
      ),
      'validationVsLeaveTopEventOut': _deltaSummary(
        _summaryJson(validationSamples),
        _summaryJson(leaveTopEventOutSamples),
      ),
    },
    'sourceTriggerFamilySlices': _buildFamilySlices(
      validation: validationSamples,
      testFull: testSamples,
      dominantEventOnly: dominantTestEventSamples,
      leaveTopEventOut: leaveTopEventOutSamples,
      familyOrder: _sourceTriggerFamilies,
      selector: (sample) => sample.sourceTriggerFamily,
    ),
    'sourceWinnerFamilySlices': _buildFamilySlices(
      validation: validationSamples,
      testFull: testSamples,
      dominantEventOnly: dominantTestEventSamples,
      leaveTopEventOut: leaveTopEventOutSamples,
      familyOrder: _sourceWinnerFamilies,
      selector: (sample) => sample.sourceWinnerFamily,
    ),
    'sourceWinnerTransitionSlices': _buildJointSlices(
      validation: validationSamples,
      testFull: testSamples,
      dominantEventOnly: dominantTestEventSamples,
      leaveTopEventOut: leaveTopEventOutSamples,
      firstOrder: _sourceWinnerFamilies,
      secondOrder: _transitionLabels,
      firstSelector: (sample) => sample.sourceWinnerFamily,
      secondSelector: (sample) => sample.transitionLabel,
    ),
    'eventConcentrationTable': eventRows,
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

List<Map<String, Object?>> _buildFamilySlices({
  required List<_Sample> validation,
  required List<_Sample> testFull,
  required List<_Sample> dominantEventOnly,
  required List<_Sample> leaveTopEventOut,
  required List<String> familyOrder,
  required String Function(_Sample sample) selector,
}) {
  return [
    for (final family in familyOrder)
      {
        'family': family,
        'validation': _familySnapshot(
          validation.where((sample) => selector(sample) == family).toList(),
          validation.length,
        ),
        'testFull': _familySnapshot(
          testFull.where((sample) => selector(sample) == family).toList(),
          testFull.length,
        ),
        'dominantEventOnly': _familySnapshot(
          dominantEventOnly.where((sample) => selector(sample) == family).toList(),
          dominantEventOnly.length,
        ),
        'leaveTopEventOut': _familySnapshot(
          leaveTopEventOut.where((sample) => selector(sample) == family).toList(),
          leaveTopEventOut.length,
        ),
      },
  ];
}

List<Map<String, Object?>> _buildJointSlices({
  required List<_Sample> validation,
  required List<_Sample> testFull,
  required List<_Sample> dominantEventOnly,
  required List<_Sample> leaveTopEventOut,
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
      final testFullRows = testFull
          .where(
            (sample) =>
                firstSelector(sample) == first && secondSelector(sample) == second,
          )
          .toList();
      final dominantEventRows = dominantEventOnly
          .where(
            (sample) =>
                firstSelector(sample) == first && secondSelector(sample) == second,
          )
          .toList();
      final leaveTopEventOutRows = leaveTopEventOut
          .where(
            (sample) =>
                firstSelector(sample) == first && secondSelector(sample) == second,
          )
          .toList();
      if (validationRows.isEmpty &&
          testFullRows.isEmpty &&
          dominantEventRows.isEmpty &&
          leaveTopEventOutRows.isEmpty) {
        continue;
      }
      rows.add({
        'first': first,
        'second': second,
        'validation': _familySnapshot(validationRows, validation.length),
        'testFull': _familySnapshot(testFullRows, testFull.length),
        'dominantEventOnly':
            _familySnapshot(dominantEventRows, dominantEventOnly.length),
        'leaveTopEventOut':
            _familySnapshot(leaveTopEventOutRows, leaveTopEventOut.length),
      });
    }
  }
  rows.sort((left, right) {
    final byTest = _number(_map(right['testFull'])['count']).compareTo(
      _number(_map(left['testFull'])['count']),
    );
    if (byTest != 0) return byTest;
    return _number(_map(right['dominantEventOnly'])['count']).compareTo(
      _number(_map(left['dominantEventOnly'])['count']),
    );
  });
  return rows;
}

Map<String, Object?> _deltaSummary(
  Map<String, Object?> baseline,
  Map<String, Object?> comparison,
) {
  return {
    'sampleShareDelta':
        _number(comparison['focusSampleCount']) - _number(baseline['focusSampleCount']),
    'precisionDelta':
        _number(comparison['precision']) - _number(baseline['precision']),
    'middleTransitionShareDelta':
        _number(comparison['middleTransitionShare']) -
        _number(baseline['middleTransitionShare']),
    'plumOnlyFalsePositiveDelta':
        _number(comparison['plumOnlyFalsePositiveCount']) -
        _number(baseline['plumOnlyFalsePositiveCount']),
  };
}

Map<String, Object?> _summaryJson(List<_Sample> samples) {
  final truePositiveCount =
      samples.where((sample) => sample.actualPositive).length;
  final middleTransitionCount =
      samples.where((sample) => sample.isMiddleTransitionZone).length;
  final plumOnlyFalsePositiveCount =
      samples.where((sample) => sample.plumOnlyFalsePositive).length;
  return {
    'focusSampleCount': samples.length,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': samples.length - truePositiveCount,
    'precision': samples.isEmpty ? 0.0 : truePositiveCount / samples.length,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionShare':
        samples.isEmpty ? 0.0 : middleTransitionCount / samples.length,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
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

String _dominantEventId(List<_Sample> samples) {
  if (samples.isEmpty) return 'none';
  final counts = <String, int>{};
  for (final sample in samples) {
    counts[sample.eventId] = (counts[sample.eventId] ?? 0) + 1;
  }
  return counts.entries.reduce((left, right) {
    if (left.value == right.value) {
      return left.key.compareTo(right.key) <= 0 ? left : right;
    }
    return left.value > right.value ? left : right;
  }).key;
}

double _topCumulativeShare(
  List<Map<String, Object?>> eventRows,
  int topN,
  int total,
) {
  if (total == 0) return 0.0;
  final topCount = eventRows.take(topN).fold<int>(
    0,
    (sum, row) => sum + (_map(row)['count'] as int),
  );
  return topCount / total;
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
        'schemaVersion': 'plum_tohoku_event_concentration_diagnostic_v1',
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'status': 'fail',
        'policy': {
          'method': 'PLUM Tohoku event-concentration diagnostic',
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
        'dominantEvent': const {
          'eventId': 'none',
          'testFocusCount': 0,
          'testFocusShare': 0.0,
          'top3CumulativeShare': 0.0,
          'top5CumulativeShare': 0.0,
        },
        'sliceSummaries': {
          'validation': _summaryJson(const []),
          'testFull': _summaryJson(const []),
          'dominantTestEventOnly': _summaryJson(const []),
          'testWithoutDominantEvent': _summaryJson(const []),
        },
        'summaryDelta': const {},
        'sourceTriggerFamilySlices': const [],
        'sourceWinnerFamilySlices': const [],
        'sourceWinnerTransitionSlices': const [],
        'eventConcentrationTable': const [],
        'errors': errors,
      };

String plumTohokuEventConcentrationDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final dominantEvent = _map(report['dominantEvent']);
  final sliceSummaries = _map(report['sliceSummaries']);
  final sourceTriggerFamilySlices = _list(report['sourceTriggerFamilySlices']);
  final sourceWinnerFamilySlices = _list(report['sourceWinnerFamilySlices']);
  final sourceWinnerTransitionSlices =
      _list(report['sourceWinnerTransitionSlices']);
  final eventConcentrationTable = _list(report['eventConcentrationTable']);
  final summaryDelta = _map(report['summaryDelta']);

  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Event-Concentration Diagnostic')
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
    ..writeln('## Dominant Event')
    ..writeln()
    ..writeln('- Event: `${dominantEvent['eventId']}`')
    ..writeln(
      '- Test focus share: `${_pct(dominantEvent['testFocusShare'])}` '
      '(${dominantEvent['testFocusCount']} / '
      '${_map(sliceSummaries['testFull'])['focusSampleCount']})',
    )
    ..writeln(
      '- Top 3 cumulative share: `${_pct(dominantEvent['top3CumulativeShare'])}`',
    )
    ..writeln(
      '- Top 5 cumulative share: `${_pct(dominantEvent['top5CumulativeShare'])}`',
    )
    ..writeln()
    ..writeln('## Slice Summaries')
    ..writeln()
    ..writeln(
      '| Slice | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final sliceName in const [
    'validation',
    'testFull',
    'dominantTestEventOnly',
    'testWithoutDominantEvent',
  ]) {
    final summary = _map(sliceSummaries[sliceName]);
    buffer.writeln(
      '| `$sliceName` | ${summary['focusSampleCount']} | '
      '${summary['truePositiveCount']} | ${summary['falsePositiveCount']} | '
      '${_pct(summary['precision'])} | ${summary['middleTransitionCount']} '
      '(${_pct(summary['middleTransitionShare'])}) | '
      '${summary['plumOnlyFalsePositiveCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Summary Delta')
    ..writeln()
    ..writeln(
      '| Comparison | Sample Delta | Precision Delta | Middle Transition Delta | PLUM-only FP Delta |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: |');

  for (final entry in summaryDelta.entries) {
    final row = _map(entry.value);
    buffer.writeln(
      '| `${entry.key}` | ${_signed(row['sampleShareDelta'])} | '
      '${_signedPct(row['precisionDelta'])} | '
      '${_signedPct(row['middleTransitionShareDelta'])} | '
      '${_signed(row['plumOnlyFalsePositiveDelta'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Trigger Family Slices')
    ..writeln()
    ..writeln(
      '| Family | Validation | Test Full | Dominant Event | Leave-Top-Event-Out |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final raw in sourceTriggerFamilySlices) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['family']}` | ${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['testFull']))} | '
      '${_familyCell(_map(row['dominantEventOnly']))} | '
      '${_familyCell(_map(row['leaveTopEventOut']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Winner Family Slices')
    ..writeln()
    ..writeln(
      '| Family | Validation | Test Full | Dominant Event | Leave-Top-Event-Out |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final raw in sourceWinnerFamilySlices) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['family']}` | ${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['testFull']))} | '
      '${_familyCell(_map(row['dominantEventOnly']))} | '
      '${_familyCell(_map(row['leaveTopEventOut']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Source Winner x Transition Slices')
    ..writeln()
    ..writeln(
      '| Winner | Label | Validation | Test Full | Dominant Event | Leave-Top-Event-Out |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final raw in sourceWinnerTransitionSlices) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['first']}` | `${row['second']}` | '
      '${_familyCell(_map(row['validation']))} | '
      '${_familyCell(_map(row['testFull']))} | '
      '${_familyCell(_map(row['dominantEventOnly']))} | '
      '${_familyCell(_map(row['leaveTopEventOut']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Test Event Concentration')
    ..writeln()
    ..writeln(
      '| Event | Samples | TP | FP | Precision | Middle Transition | Winner | Family | Trigger Mix | Winner Mix |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |',
    );
  for (final raw in eventConcentrationTable.take(12)) {
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
      '- This report stays diagnostic-only and is only meant to test whether '
      'the current PLUM-led hotspot is dominated by one test event.',
    )
    ..writeln(
      '- It does not tune PLUM, mutate raw predicted intensity, or connect '
      'any result to UI, wording, notification, or runtime policy.',
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
  return '$sign${number.toStringAsFixed(1)}';
}
