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
    '.dart_tool/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusFamily = 'mismatch/one_sided/compact';
const _minRemainderSupportForRanking = 3;
const _threshold = _Threshold('shindo4', 3.5);
const _featureFamilyOrder = [
  'localMismatchBand',
  'sourceTriggerFamily',
  'sourceWinnerFamily',
  'quadrantCoverageBand',
  'evidenceCountBand',
  'nearestEvidenceDistanceBand',
  'centroidOffsetBand',
  'maxSpreadBand',
  'topContributionShareBand',
  'contributionHhiBand',
  'meanContributionMarginBand',
  'effectiveSupportCountBand',
  'localMismatchBand|quadrantCoverageBand',
];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report =
      buildPlumTohokuMismatchOneSidedCompactModeSignalSeparationDiagnosticJson(
        dataDirectory: dataDirectory,
        modelPath: modelPath,
      );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMismatchOneSidedCompactModeSignalSeparationDiagnosticMarkdown(
      report,
    ),
  );

  stdout.writeln(
    'wrote PLUM Tohoku mismatch/one_sided/compact mode signal separation diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?>
buildPlumTohokuMismatchOneSidedCompactModeSignalSeparationDiagnosticJson({
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
    final splitAccumulator = splitName == 'validation'
        ? validationAccumulator
        : testAccumulator;
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
  final validationFamilySamples = [
    for (final sample in validationSamples)
      if (sample.eventFamilyLabel == _focusFamily) sample,
  ];
  final remainderFamilySamples = [
    for (final sample in testSamples)
      if (sample.eventId != dominantEventId &&
          sample.eventFamilyLabel == _focusFamily)
        sample,
  ];

  final validationNearThresholdPositive = [
    for (final sample in validationFamilySamples)
      if (sample.isNearThresholdPositiveMode) sample,
  ];
  final validationFalseMiddleTransition = [
    for (final sample in validationFamilySamples)
      if (sample.isFalseMiddleTransitionMode) sample,
  ];
  final remainderNearThresholdPositive = [
    for (final sample in remainderFamilySamples)
      if (sample.isNearThresholdPositiveMode) sample,
  ];
  final remainderFalseMiddleTransition = [
    for (final sample in remainderFamilySamples)
      if (sample.isFalseMiddleTransitionMode) sample,
  ];

  final featureFamilies = {
    for (final family in _featureFamilyOrder)
      family: _buildFeatureFamilyJson(
        family: family,
        validationNearThresholdPositive: validationNearThresholdPositive,
        validationFalseMiddleTransition: validationFalseMiddleTransition,
        remainderNearThresholdPositive: remainderNearThresholdPositive,
        remainderFalseMiddleTransition: remainderFalseMiddleTransition,
      ),
  };

  return {
    'schemaVersion':
        'plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method':
          'PLUM Tohoku mismatch/one_sided/compact mode signal separation diagnostic',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'suppressionApplied': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
      'minimumRemainderSupportForRanking': _minRemainderSupportForRanking,
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'splits': ['validation', 'test'],
      'threshold': _threshold.label,
      'family': _focusFamily,
    },
    'scope': {
      'removedDominantEvent': dominantEventId,
      'estimatedSourceRegion': _focusRegion,
      'minimumEvidenceCount': _focusMinimumEvidenceCount,
      'maximumNearestEvidenceDistanceKm':
          _focusMaximumNearestEvidenceDistanceKm,
      'baselineThresholdCrossingRequired': true,
    },
    'modeDefinitions': const {
      'nearThresholdPositive':
          'family mismatch/one_sided/compact with actualGapBand=0.0_to_1.0 and evidenceGapBand=lt_1.0',
      'falseMiddleTransition':
          'family mismatch/one_sided/compact with actualGapBand=-1.0_to_0.0 and evidenceGapBand=1.0_to_2.0',
      'productionFeatureBoundary':
          'feature buckets use only runtime-visible source/support/evidence signals; truth-dependent labels stay offline diagnostic only',
    },
    'featureDefinitions': const {
      'localMismatchBand':
          'banded localBelowThresholdShare10Km within the 10 km local neighborhood',
      'sourceTriggerFamily':
          'which source branch crosses threshold: jma_only, plum_only, or both',
      'sourceWinnerFamily':
          'which source branch predicts higher intensity: jma_higher, plum_higher, or tied',
      'quadrantCoverageBand':
          'supporting evidence quadrant coverage, split as q1 or q2 inside one_sided family',
      'evidenceCountBand': 'PLUM supporting evidence count band',
      'nearestEvidenceDistanceBand':
          'nearest supporting evidence distance band in km',
      'centroidOffsetBand':
          'distance from target station to support centroid in km',
      'maxSpreadBand': 'supporting evidence maximum pairwise spread band in km',
      'topContributionShareBand':
          'largest propagated excess share within supporting evidence',
      'contributionHhiBand':
          'Herfindahl concentration index over normalized propagated excess',
      'meanContributionMarginBand':
          'mean propagated excess above threshold inside supporting evidence',
      'effectiveSupportCountBand':
          'soft effective-support count proxy defined as 1 / HHI',
      'localMismatchBand|quadrantCoverageBand':
          'joint view of local mismatch and support quadrant coverage',
    },
    'coverage': {
      'validationFamilySamples': validationFamilySamples.length,
      'remainderFamilySamples': remainderFamilySamples.length,
      'validationNearThresholdPositiveCount':
          validationNearThresholdPositive.length,
      'validationFalseMiddleTransitionCount':
          validationFalseMiddleTransition.length,
      'remainderNearThresholdPositiveCount':
          remainderNearThresholdPositive.length,
      'remainderFalseMiddleTransitionCount':
          remainderFalseMiddleTransition.length,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'modeFeatureMeans': {
      'validationNearThresholdPositive': _ModeSummary.fromSamples(
        validationNearThresholdPositive,
      ).toJson(),
      'validationFalseMiddleTransition': _ModeSummary.fromSamples(
        validationFalseMiddleTransition,
      ).toJson(),
      'remainderNearThresholdPositive': _ModeSummary.fromSamples(
        remainderNearThresholdPositive,
      ).toJson(),
      'remainderFalseMiddleTransition': _ModeSummary.fromSamples(
        remainderFalseMiddleTransition,
      ).toJson(),
    },
    'featureFamilies': featureFamilies,
    'rankedSeparators': _buildRankedSeparators(featureFamilies),
    'errors': errors,
  };
}

Map<String, Object?> _buildFeatureFamilyJson({
  required String family,
  required List<_Sample> validationNearThresholdPositive,
  required List<_Sample> validationFalseMiddleTransition,
  required List<_Sample> remainderNearThresholdPositive,
  required List<_Sample> remainderFalseMiddleTransition,
}) {
  final validationNearBuckets = _bucketCounts(
    validationNearThresholdPositive,
    family,
  );
  final validationFalseBuckets = _bucketCounts(
    validationFalseMiddleTransition,
    family,
  );
  final remainderNearBuckets = _bucketCounts(
    remainderNearThresholdPositive,
    family,
  );
  final remainderFalseBuckets = _bucketCounts(
    remainderFalseMiddleTransition,
    family,
  );
  final keys = {
    ...validationNearBuckets.keys,
    ...validationFalseBuckets.keys,
    ...remainderNearBuckets.keys,
    ...remainderFalseBuckets.keys,
  }.toList()..sort();
  return {
    'validationNearThresholdPositiveCount':
        validationNearThresholdPositive.length,
    'validationFalseMiddleTransitionCount':
        validationFalseMiddleTransition.length,
    'remainderNearThresholdPositiveCount':
        remainderNearThresholdPositive.length,
    'remainderFalseMiddleTransitionCount':
        remainderFalseMiddleTransition.length,
    'buckets': [
      for (final key in keys)
        _bucketRow(
          family: family,
          bucket: key,
          validationNearCount: validationNearBuckets[key] ?? 0,
          validationNearTotal: validationNearThresholdPositive.length,
          validationFalseCount: validationFalseBuckets[key] ?? 0,
          validationFalseTotal: validationFalseMiddleTransition.length,
          remainderNearCount: remainderNearBuckets[key] ?? 0,
          remainderNearTotal: remainderNearThresholdPositive.length,
          remainderFalseCount: remainderFalseBuckets[key] ?? 0,
          remainderFalseTotal: remainderFalseMiddleTransition.length,
        ),
    ],
  };
}

Map<String, int> _bucketCounts(List<_Sample> samples, String family) {
  final counts = <String, int>{};
  for (final sample in samples) {
    final bucket = sample.bucketForFamily(family);
    counts[bucket] = (counts[bucket] ?? 0) + 1;
  }
  return counts;
}

Map<String, Object?> _bucketRow({
  required String family,
  required String bucket,
  required int validationNearCount,
  required int validationNearTotal,
  required int validationFalseCount,
  required int validationFalseTotal,
  required int remainderNearCount,
  required int remainderNearTotal,
  required int remainderFalseCount,
  required int remainderFalseTotal,
}) {
  final validationNearShare = validationNearTotal == 0
      ? 0.0
      : validationNearCount / validationNearTotal;
  final validationFalseShare = validationFalseTotal == 0
      ? 0.0
      : validationFalseCount / validationFalseTotal;
  final remainderNearShare = remainderNearTotal == 0
      ? 0.0
      : remainderNearCount / remainderNearTotal;
  final remainderFalseShare = remainderFalseTotal == 0
      ? 0.0
      : remainderFalseCount / remainderFalseTotal;
  final remainderSupportCount = remainderNearCount + remainderFalseCount;
  final remainderTotalModes = remainderNearTotal + remainderFalseTotal;
  final remainderPurity = remainderSupportCount == 0
      ? 0.0
      : math.max(remainderNearCount, remainderFalseCount) /
            remainderSupportCount;
  final remainderCaptureShare = remainderTotalModes == 0
      ? 0.0
      : remainderSupportCount / remainderTotalModes;
  final remainderShareGap = (remainderNearShare - remainderFalseShare).abs();
  final proxyScore =
      remainderShareGap * remainderPurity * remainderCaptureShare;
  return {
    'family': family,
    'bucket': bucket,
    'validationNearCount': validationNearCount,
    'validationNearShare': validationNearShare,
    'validationFalseCount': validationFalseCount,
    'validationFalseShare': validationFalseShare,
    'validationShareGap': validationNearShare - validationFalseShare,
    'remainderNearCount': remainderNearCount,
    'remainderNearShare': remainderNearShare,
    'remainderFalseCount': remainderFalseCount,
    'remainderFalseShare': remainderFalseShare,
    'remainderShareGap': remainderNearShare - remainderFalseShare,
    'remainderSupportCount': remainderSupportCount,
    'remainderDominantMode': remainderNearCount == remainderFalseCount
        ? 'tied'
        : remainderNearCount > remainderFalseCount
        ? 'near_threshold_positive'
        : 'false_middle_transition',
    'remainderPurity': remainderPurity,
    'remainderCaptureShare': remainderCaptureShare,
    'proxyScore': proxyScore,
  };
}

List<Map<String, Object?>> _buildRankedSeparators(
  Map<String, Object?> featureFamilies,
) {
  final rows = <Map<String, Object?>>[];
  for (final family in _featureFamilyOrder) {
    final buckets = _list(_map(featureFamilies[family])['buckets']);
    for (final raw in buckets) {
      final row = _map(raw);
      if (_int(row['remainderSupportCount']) < _minRemainderSupportForRanking) {
        continue;
      }
      rows.add(row);
    }
  }
  rows.sort((left, right) {
    final scoreCmp = _number(
      right['proxyScore'],
    ).compareTo(_number(left['proxyScore']));
    if (scoreCmp != 0) return scoreCmp;
    final gapCmp = _number(
      _number(right['remainderShareGap']).abs(),
    ).compareTo(_number(_number(left['remainderShareGap']).abs()));
    if (gapCmp != 0) return gapCmp;
    return _int(
      right['remainderSupportCount'],
    ).compareTo(_int(left['remainderSupportCount']));
  });
  return rows.take(20).toList();
}

_Sample _buildSample({
  required StaticIntensityEvent event,
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
  final contribution = _supportContributionSummary(
    threshold: threshold.value,
    evidenceStations: supportingEvidence,
  );

  return _Sample(
    eventId: event.eventId,
    thresholdValue: threshold.value,
    actual: targetStation.intensity,
    jma: jmaPredictedIntensity,
    plum: plum.intensity,
    r20: r20,
    r30D075: r30D075,
    evidenceCount: plum.evidenceCount,
    nearestEvidenceDistanceKm: plum.nearestEvidenceDistanceKm,
    evidenceTargetGap: strongestEvidence == null
        ? double.nan
        : strongestEvidence.station.intensity - targetStation.intensity,
    localBelowThresholdShare10Km: local10.belowThresholdShare,
    supportingEvidenceQuadrantCoverage: supportShape.quadrantCoverage,
    supportingEvidenceCentroidOffsetKm: supportShape.centroidOffsetKm,
    supportingEvidenceMaxSpreadKm: supportShape.maxSpreadKm,
    topContributionShare: contribution.topContributionShare,
    contributionHhi: contribution.contributionHhi,
    meanContributionMargin: contribution.meanMargin,
    effectiveSupportCount: contribution.effectiveSupportCount,
  );
}

_ContributionSummary _supportContributionSummary({
  required double threshold,
  required List<_EvidenceStation> evidenceStations,
}) {
  if (evidenceStations.isEmpty) {
    return const _ContributionSummary(
      topContributionShare: 0,
      contributionHhi: 0,
      meanMargin: 0,
      effectiveSupportCount: 0,
    );
  }
  final margins = [
    for (final evidence in evidenceStations)
      math.max(0.0, evidence.propagatedIntensity - threshold),
  ]..sort((left, right) => right.compareTo(left));
  final total = margins.fold<double>(0.0, (sum, value) => sum + value);
  final contributionHhi = total <= 0
      ? 0.0
      : margins
            .map((margin) => margin / total)
            .fold<double>(0.0, (sum, share) => sum + share * share);
  final top1 = margins.first;
  return _ContributionSummary(
    topContributionShare: total <= 0 ? 0.0 : top1 / total,
    contributionHhi: contributionHhi,
    meanMargin: total / margins.length,
    effectiveSupportCount: contributionHhi <= 0 ? 0.0 : 1.0 / contributionHhi,
  );
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
    final propagated =
        observed.intensity - _plumDampingPer10Km * (distance / 10.0);
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
    return const _SupportShape(
      quadrantCoverage: 0,
      centroidOffsetKm: 0,
      maxSpreadKm: 0,
    );
  }
  final quadrants = <int>{};
  var sumLat = 0.0;
  var sumLng = 0.0;
  for (final evidence in evidenceStations) {
    sumLat += evidence.station.latitude;
    sumLng += evidence.station.longitude;
    quadrants.add(
      _quadrant(
        targetLatitude: targetStation.latitude,
        targetLongitude: targetStation.longitude,
        stationLatitude: evidence.station.latitude,
        stationLongitude: evidence.station.longitude,
      ),
    );
  }
  final centroidLat = sumLat / evidenceStations.length;
  final centroidLng = sumLng / evidenceStations.length;
  var maxSpreadKm = 0.0;
  for (var i = 0; i < evidenceStations.length; i++) {
    for (var j = i + 1; j < evidenceStations.length; j++) {
      final left = evidenceStations[i].station;
      final right = evidenceStations[j].station;
      final spread = QuakeCalculator.haversineDistance(
        left.latitude,
        left.longitude,
        right.latitude,
        right.longitude,
      );
      if (spread > maxSpreadKm) maxSpreadKm = spread;
    }
  }
  return _SupportShape(
    quadrantCoverage: quadrants.length,
    centroidOffsetKm: QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      centroidLat,
      centroidLng,
    ),
    maxSpreadKm: maxSpreadKm,
  );
}

int _quadrant({
  required double targetLatitude,
  required double targetLongitude,
  required double stationLatitude,
  required double stationLongitude,
}) {
  final north = stationLatitude >= targetLatitude;
  final east = stationLongitude >= targetLongitude;
  if (north && east) return 0;
  if (north) return 1;
  if (east) return 2;
  return 3;
}

String plumTohokuMismatchOneSidedCompactModeSignalSeparationDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final scope = _map(report['scope']);
  final modeDefinitions = _map(report['modeDefinitions']);
  final modeFeatureMeans = _map(report['modeFeatureMeans']);
  final featureFamilies = _map(report['featureFamilies']);
  final rankedSeparators = _list(report['rankedSeparators']);
  final buffer = StringBuffer()
    ..writeln(
      '# PLUM Tohoku mismatch/one_sided/compact Mode Signal Separation Diagnostic',
    )
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
    ..writeln('| Slice | Count |')
    ..writeln('| --- | ---: |')
    ..writeln(
      '| `validation family samples` | ${coverage['validationFamilySamples']} |',
    )
    ..writeln(
      '| `remainder family samples` | ${coverage['remainderFamilySamples']} |',
    )
    ..writeln(
      '| `validation near-threshold positives` | ${coverage['validationNearThresholdPositiveCount']} |',
    )
    ..writeln(
      '| `validation false middle-transition` | ${coverage['validationFalseMiddleTransitionCount']} |',
    )
    ..writeln(
      '| `remainder near-threshold positives` | ${coverage['remainderNearThresholdPositiveCount']} |',
    )
    ..writeln(
      '| `remainder false middle-transition` | ${coverage['remainderFalseMiddleTransitionCount']} |',
    )
    ..writeln()
    ..writeln('## Scope')
    ..writeln()
    ..writeln('- Removed dominant event: `${scope['removedDominantEvent']}`')
    ..writeln('- Estimated-source region: `${scope['estimatedSourceRegion']}`')
    ..writeln(
      '- Fixed family: `${report['inputs'] is Map ? _map(report['inputs'])['family'] : _focusFamily}`',
    )
    ..writeln('- Minimum evidence count: `${scope['minimumEvidenceCount']}`')
    ..writeln(
      '- Maximum nearest evidence distance: '
      '`${scope['maximumNearestEvidenceDistanceKm']} km`',
    )
    ..writeln()
    ..writeln('## Mode Definitions')
    ..writeln()
    ..writeln(
      '- `near_threshold_positive`: `${modeDefinitions['nearThresholdPositive']}`',
    )
    ..writeln(
      '- `false_middle_transition`: `${modeDefinitions['falseMiddleTransition']}`',
    )
    ..writeln(
      '- Feature boundary: `${modeDefinitions['productionFeatureBoundary']}`',
    )
    ..writeln()
    ..writeln('## Remainder Mode Feature Means')
    ..writeln()
    ..writeln(
      '| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final mode in const [
    'remainderNearThresholdPositive',
    'remainderFalseMiddleTransition',
  ]) {
    final row = _map(modeFeatureMeans[mode]);
    buffer.writeln(
      '| `$mode` | ${row['count']} | ${_fmt(row['localBelowThresholdShare10Km'])} | '
      '${_fmt(row['evidenceCount'])} | ${_fmt(row['nearestEvidenceDistanceKm'])} | '
      '${_fmt(row['supportingEvidenceQuadrantCoverage'])} | ${_fmt(row['supportingEvidenceCentroidOffsetKm'])} | '
      '${_fmt(row['supportingEvidenceMaxSpreadKm'])} | ${_fmt(row['topContributionShare'])} | '
      '${_fmt(row['contributionHhi'])} | ${_fmt(row['meanContributionMargin'])} | '
      '${_fmt(row['effectiveSupportCount'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Validation Mode Feature Means')
    ..writeln()
    ..writeln(
      '| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final mode in const [
    'validationNearThresholdPositive',
    'validationFalseMiddleTransition',
  ]) {
    final row = _map(modeFeatureMeans[mode]);
    buffer.writeln(
      '| `$mode` | ${row['count']} | ${_fmt(row['localBelowThresholdShare10Km'])} | '
      '${_fmt(row['evidenceCount'])} | ${_fmt(row['nearestEvidenceDistanceKm'])} | '
      '${_fmt(row['supportingEvidenceQuadrantCoverage'])} | ${_fmt(row['supportingEvidenceCentroidOffsetKm'])} | '
      '${_fmt(row['supportingEvidenceMaxSpreadKm'])} | ${_fmt(row['topContributionShare'])} | '
      '${_fmt(row['contributionHhi'])} | ${_fmt(row['meanContributionMargin'])} | '
      '${_fmt(row['effectiveSupportCount'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Ranked Separators')
    ..writeln()
    ..writeln(
      '| Family | Bucket | Remainder Near | Remainder False | Near Share | False Share | Support | Dominant | Purity | Capture | Score |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |',
    );
  for (final raw in rankedSeparators) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['family']}` | `${row['bucket']}` | ${row['remainderNearCount']} | ${row['remainderFalseCount']} | '
      '${_pct(row['remainderNearShare'])} | ${_pct(row['remainderFalseShare'])} | '
      '${row['remainderSupportCount']} | `${row['remainderDominantMode']}` | '
      '${_pct(row['remainderPurity'])} | ${_pct(row['remainderCaptureShare'])} | ${_fmt(row['proxyScore'])} |',
    );
  }
  for (final family in _featureFamilyOrder) {
    final familyJson = _map(featureFamilies[family]);
    final buckets = _list(familyJson['buckets']);
    buffer
      ..writeln()
      ..writeln('## `$family`')
      ..writeln()
      ..writeln(
        '| Bucket | Val Near | Val False | Rem Near | Rem False | Val Gap | Rem Gap | Support | Dominant | Score |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |',
      );
    for (final raw in buckets) {
      final row = _map(raw);
      buffer.writeln(
        '| `${row['bucket']}` | ${row['validationNearCount']} | ${row['validationFalseCount']} | '
        '${row['remainderNearCount']} | ${row['remainderFalseCount']} | '
        '${_signedPct(_number(row['validationShareGap']))} | ${_signedPct(_number(row['remainderShareGap']))} | '
        '${row['remainderSupportCount']} | `${row['remainderDominantMode']}` | ${_fmt(row['proxyScore'])} |',
      );
    }
  }

  return '$buffer';
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

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final samples = <_Sample>[];

  void add(_Sample sample) => samples.add(sample);
}

class _Sample {
  final String eventId;
  final double thresholdValue;
  final double actual;
  final double jma;
  final double plum;
  final double r20;
  final double r30D075;
  final int evidenceCount;
  final double nearestEvidenceDistanceKm;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceCentroidOffsetKm;
  final double supportingEvidenceMaxSpreadKm;
  final double topContributionShare;
  final double contributionHhi;
  final double meanContributionMargin;
  final double effectiveSupportCount;

  const _Sample({
    required this.eventId,
    required this.thresholdValue,
    required this.actual,
    required this.jma,
    required this.plum,
    required this.r20,
    required this.r30D075,
    required this.evidenceCount,
    required this.nearestEvidenceDistanceKm,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceCentroidOffsetKm,
    required this.supportingEvidenceMaxSpreadKm,
    required this.topContributionShare,
    required this.contributionHhi,
    required this.meanContributionMargin,
    required this.effectiveSupportCount,
  });

  bool get actualPositive => actual >= thresholdValue;

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

  bool get isNearThresholdPositiveMode =>
      actualPositive &&
      actualGapBand == '0.0_to_1.0' &&
      evidenceGapBand == 'lt_1.0' &&
      eventFamilyLabel == _focusFamily;

  bool get isFalseMiddleTransitionMode =>
      !actualPositive &&
      actualGapBand == '-1.0_to_0.0' &&
      evidenceGapBand == '1.0_to_2.0' &&
      eventFamilyLabel == _focusFamily;

  String get localMismatchBand {
    final share = localBelowThresholdShare10Km;
    if (share < 0.67) return '0.50_to_0.67';
    if (share < 0.85) return '0.67_to_0.85';
    return 'gte_0.85';
  }

  String get quadrantCoverageBand =>
      supportingEvidenceQuadrantCoverage <= 1 ? 'q1' : 'q2';

  String get evidenceCountBand {
    if (evidenceCount < 12) return '8_to_11';
    if (evidenceCount < 16) return '12_to_15';
    return 'gte_16';
  }

  String get nearestEvidenceDistanceBand {
    if (nearestEvidenceDistanceKm < 2.5) return 'lt_2.5';
    if (nearestEvidenceDistanceKm < 5.0) return '2.5_to_5.0';
    return '5.0_to_10.0';
  }

  String get centroidOffsetBand {
    if (supportingEvidenceCentroidOffsetKm < 5.0) return 'lt_5';
    if (supportingEvidenceCentroidOffsetKm < 10.0) return '5_to_10';
    return 'gte_10';
  }

  String get maxSpreadBand {
    if (supportingEvidenceMaxSpreadKm < 10.0) return 'lt_10';
    if (supportingEvidenceMaxSpreadKm < 15.0) return '10_to_15';
    return '15_to_20';
  }

  String get topContributionShareBand {
    if (topContributionShare < 0.20) return 'lt_0.20';
    if (topContributionShare < 0.25) return '0.20_to_0.25';
    if (topContributionShare < 0.33) return '0.25_to_0.33';
    return 'gte_0.33';
  }

  String get contributionHhiBand {
    if (contributionHhi < 0.10) return 'lt_0.10';
    if (contributionHhi < 0.14) return '0.10_to_0.14';
    if (contributionHhi < 0.20) return '0.14_to_0.20';
    return 'gte_0.20';
  }

  String get meanContributionMarginBand {
    if (meanContributionMargin < 0.25) return 'lt_0.25';
    if (meanContributionMargin < 0.40) return '0.25_to_0.40';
    if (meanContributionMargin < 0.60) return '0.40_to_0.60';
    return 'gte_0.60';
  }

  String get effectiveSupportCountBand {
    if (effectiveSupportCount < 4.0) return 'lt_4';
    if (effectiveSupportCount < 6.0) return '4_to_6';
    if (effectiveSupportCount < 8.0) return '6_to_8';
    return 'gte_8';
  }

  String bucketForFamily(String family) {
    switch (family) {
      case 'localMismatchBand':
        return localMismatchBand;
      case 'sourceTriggerFamily':
        return sourceTriggerFamily;
      case 'sourceWinnerFamily':
        return sourceWinnerFamily;
      case 'quadrantCoverageBand':
        return quadrantCoverageBand;
      case 'evidenceCountBand':
        return evidenceCountBand;
      case 'nearestEvidenceDistanceBand':
        return nearestEvidenceDistanceBand;
      case 'centroidOffsetBand':
        return centroidOffsetBand;
      case 'maxSpreadBand':
        return maxSpreadBand;
      case 'topContributionShareBand':
        return topContributionShareBand;
      case 'contributionHhiBand':
        return contributionHhiBand;
      case 'meanContributionMarginBand':
        return meanContributionMarginBand;
      case 'effectiveSupportCountBand':
        return effectiveSupportCountBand;
      case 'localMismatchBand|quadrantCoverageBand':
        return '$localMismatchBand|$quadrantCoverageBand';
      default:
        return 'unknown';
    }
  }
}

class _ModeSummary {
  final int count;
  final double localBelowThresholdShare10Km;
  final double evidenceCount;
  final double nearestEvidenceDistanceKm;
  final double supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceCentroidOffsetKm;
  final double supportingEvidenceMaxSpreadKm;
  final double topContributionShare;
  final double contributionHhi;
  final double meanContributionMargin;
  final double effectiveSupportCount;

  const _ModeSummary({
    required this.count,
    required this.localBelowThresholdShare10Km,
    required this.evidenceCount,
    required this.nearestEvidenceDistanceKm,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceCentroidOffsetKm,
    required this.supportingEvidenceMaxSpreadKm,
    required this.topContributionShare,
    required this.contributionHhi,
    required this.meanContributionMargin,
    required this.effectiveSupportCount,
  });

  factory _ModeSummary.fromSamples(List<_Sample> samples) {
    if (samples.isEmpty) {
      return const _ModeSummary(
        count: 0,
        localBelowThresholdShare10Km: 0,
        evidenceCount: 0,
        nearestEvidenceDistanceKm: 0,
        supportingEvidenceQuadrantCoverage: 0,
        supportingEvidenceCentroidOffsetKm: 0,
        supportingEvidenceMaxSpreadKm: 0,
        topContributionShare: 0,
        contributionHhi: 0,
        meanContributionMargin: 0,
        effectiveSupportCount: 0,
      );
    }
    return _ModeSummary(
      count: samples.length,
      localBelowThresholdShare10Km: _mean(
        samples.map((sample) => sample.localBelowThresholdShare10Km),
      ),
      evidenceCount: _mean(
        samples.map((sample) => sample.evidenceCount.toDouble()),
      ),
      nearestEvidenceDistanceKm: _mean(
        samples.map((sample) => sample.nearestEvidenceDistanceKm),
      ),
      supportingEvidenceQuadrantCoverage: _mean(
        samples.map(
          (sample) => sample.supportingEvidenceQuadrantCoverage.toDouble(),
        ),
      ),
      supportingEvidenceCentroidOffsetKm: _mean(
        samples.map((sample) => sample.supportingEvidenceCentroidOffsetKm),
      ),
      supportingEvidenceMaxSpreadKm: _mean(
        samples.map((sample) => sample.supportingEvidenceMaxSpreadKm),
      ),
      topContributionShare: _mean(
        samples.map((sample) => sample.topContributionShare),
      ),
      contributionHhi: _mean(samples.map((sample) => sample.contributionHhi)),
      meanContributionMargin: _mean(
        samples.map((sample) => sample.meanContributionMargin),
      ),
      effectiveSupportCount: _mean(
        samples.map((sample) => sample.effectiveSupportCount),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'localBelowThresholdShare10Km': localBelowThresholdShare10Km,
    'evidenceCount': evidenceCount,
    'nearestEvidenceDistanceKm': nearestEvidenceDistanceKm,
    'supportingEvidenceQuadrantCoverage': supportingEvidenceQuadrantCoverage,
    'supportingEvidenceCentroidOffsetKm': supportingEvidenceCentroidOffsetKm,
    'supportingEvidenceMaxSpreadKm': supportingEvidenceMaxSpreadKm,
    'topContributionShare': topContributionShare,
    'contributionHhi': contributionHhi,
    'meanContributionMargin': meanContributionMargin,
    'effectiveSupportCount': effectiveSupportCount,
  };
}

class _ContributionSummary {
  final double topContributionShare;
  final double contributionHhi;
  final double meanMargin;
  final double effectiveSupportCount;

  const _ContributionSummary({
    required this.topContributionShare,
    required this.contributionHhi,
    required this.meanMargin,
    required this.effectiveSupportCount,
  });
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

  const _NeighborSummary({
    required this.count,
    required this.belowThresholdShare,
  });
}

class _SupportShape {
  final int quadrantCoverage;
  final double centroidOffsetKm;
  final double maxSpreadKm;

  const _SupportShape({
    required this.quadrantCoverage,
    required this.centroidOffsetKm,
    required this.maxSpreadKm,
  });
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
  'schemaVersion':
      'plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method':
        'PLUM Tohoku mismatch/one_sided/compact mode signal separation diagnostic',
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'suppressionApplied': false,
    'plumRadiusKm': _plumRadiusKm,
    'plumDampingPer10Km': _plumDampingPer10Km,
    'minimumRemainderSupportForRanking': _minRemainderSupportForRanking,
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'modelPath': modelPath,
    'splits': ['validation', 'test'],
    'threshold': _threshold.label,
    'family': _focusFamily,
  },
  'scope': {
    'removedDominantEvent': 'none',
    'estimatedSourceRegion': _focusRegion,
    'minimumEvidenceCount': _focusMinimumEvidenceCount,
    'maximumNearestEvidenceDistanceKm': _focusMaximumNearestEvidenceDistanceKm,
    'baselineThresholdCrossingRequired': true,
  },
  'modeDefinitions': const {},
  'featureDefinitions': const {},
  'coverage': {
    'validationFamilySamples': 0,
    'remainderFamilySamples': 0,
    'validationNearThresholdPositiveCount': 0,
    'validationFalseMiddleTransitionCount': 0,
    'remainderNearThresholdPositiveCount': 0,
    'remainderFalseMiddleTransitionCount': 0,
    'skippedMissingMagnitudeEvents': 0,
    'skippedNoSourceEstimateVariants': 0,
  },
  'modeFeatureMeans': const {},
  'featureFamilies': const {},
  'rankedSeparators': const [],
  'errors': errors,
};

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

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

int _int(Object? value) => value is num ? value.toInt() : 0;

double _mean(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return 0.0;
  return list.fold<double>(0.0, (sum, value) => sum + value) / list.length;
}

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(double value) {
  final percent = value * 100;
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}pp';
}

String _fmt(Object? value) => _number(value).toStringAsFixed(3);
