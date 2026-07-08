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
    '.dart_tool/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusFamily = 'mismatch/one_sided/compact';
const _minorSliceExcludedEventId = '2022070605102497-38.4125-141.9545';
const _minimumMinorSliceSupportForRanking = 2;
const _threshold = _Threshold('shindo4', 3.5);
const _variantOrder = [
  'support_geometry_only',
  'support_geometry_plus_proximity',
  'full_score',
];
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
      buildPlumTohokuMismatchOneSidedCompactMinorEventPooledSignalDiagnosticJson(
        dataDirectory: dataDirectory,
        modelPath: modelPath,
      );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMismatchOneSidedCompactMinorEventPooledSignalDiagnosticMarkdown(
      report,
    ),
  );

  stdout.writeln(
    'wrote PLUM Tohoku mismatch/one_sided/compact minor-event pooled signal diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?>
buildPlumTohokuMismatchOneSidedCompactMinorEventPooledSignalDiagnosticJson({
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
  final validationTargetModes = [
    for (final sample in validationSamples)
      if (sample.eventFamilyLabel == _focusFamily &&
          (sample.isNearThresholdPositiveMode ||
              sample.isFalseMiddleTransitionMode))
        sample,
  ];
  final minorSliceTargetModes = [
    for (final sample in testSamples)
      if (sample.eventId != dominantEventId &&
          sample.eventId != _minorSliceExcludedEventId &&
          sample.eventFamilyLabel == _focusFamily &&
          (sample.isNearThresholdPositiveMode ||
              sample.isFalseMiddleTransitionMode))
        sample,
  ];

  final validationNearThresholdPositive = [
    for (final sample in validationTargetModes)
      if (sample.isNearThresholdPositiveMode) sample,
  ];
  final validationFalseMiddleTransition = [
    for (final sample in validationTargetModes)
      if (sample.isFalseMiddleTransitionMode) sample,
  ];
  final minorNearThresholdPositive = [
    for (final sample in minorSliceTargetModes)
      if (sample.isNearThresholdPositiveMode) sample,
  ];
  final minorFalseMiddleTransition = [
    for (final sample in minorSliceTargetModes)
      if (sample.isFalseMiddleTransitionMode) sample,
  ];

  final featureFamilies = {
    for (final family in _featureFamilyOrder)
      family: _buildFeatureFamilyJson(
        family: family,
        validationNearThresholdPositive: validationNearThresholdPositive,
        validationFalseMiddleTransition: validationFalseMiddleTransition,
        remainderNearThresholdPositive: minorNearThresholdPositive,
        remainderFalseMiddleTransition: minorFalseMiddleTransition,
      ),
  };
  final minorEventCounts = _eventCounts(minorSliceTargetModes);
  final variantComparison = _buildVariantComparison(
    validationTargetModes: validationTargetModes,
    sliceTargetModes: minorSliceTargetModes,
  );
  final sampleLedger = [
    for (final sample in _sortedSamples(minorSliceTargetModes))
      sample.toLedgerJson(),
  ];

  return {
    'schemaVersion':
        'plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method':
          'PLUM Tohoku mismatch/one_sided/compact minor-event pooled signal diagnostic',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'suppressionApplied': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
      'minimumMinorSliceSupportForRanking': _minimumMinorSliceSupportForRanking,
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'splits': ['validation', 'test'],
      'threshold': _threshold.label,
      'family': _focusFamily,
      'variants': _variantOrder,
    },
    'scope': {
      'removedDominantEvent': dominantEventId,
      'minorSliceExcludedEvent': _minorSliceExcludedEventId,
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
      'maxSpreadBand':
          'supporting evidence maximum pairwise spread band in km',
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
      'validationTargetModes': validationTargetModes.length,
      'minorSliceTargetModes': minorSliceTargetModes.length,
      'validationNearThresholdPositiveCount':
          validationNearThresholdPositive.length,
      'validationFalseMiddleTransitionCount':
          validationFalseMiddleTransition.length,
      'minorNearThresholdPositiveCount': minorNearThresholdPositive.length,
      'minorFalseMiddleTransitionCount': minorFalseMiddleTransition.length,
      'minorSliceEventCount': minorEventCounts.length,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'modeFeatureMeans': {
      'validationNearThresholdPositive':
          _ModeSummary.fromSamples(validationNearThresholdPositive).toJson(),
      'validationFalseMiddleTransition':
          _ModeSummary.fromSamples(validationFalseMiddleTransition).toJson(),
      'minorNearThresholdPositive':
          _ModeSummary.fromSamples(minorNearThresholdPositive).toJson(),
      'minorFalseMiddleTransition':
          _ModeSummary.fromSamples(minorFalseMiddleTransition).toJson(),
    },
    'minorSliceEvents': [
      for (final entry in minorEventCounts.entries)
        {'eventId': entry.key, 'count': entry.value},
    ],
    'variantComparison': variantComparison,
    'featureFamilies': featureFamilies,
    'rankedSeparators': _buildRankedSeparators(featureFamilies),
    'sampleLedger': sampleLedger,
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
  }.toList()
    ..sort();
  return {
    'validationNearThresholdPositiveCount': validationNearThresholdPositive.length,
    'validationFalseMiddleTransitionCount':
        validationFalseMiddleTransition.length,
    'remainderNearThresholdPositiveCount': remainderNearThresholdPositive.length,
    'remainderFalseMiddleTransitionCount': remainderFalseMiddleTransition.length,
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
      : math.max(remainderNearCount, remainderFalseCount) / remainderSupportCount;
  final remainderCaptureShare = remainderTotalModes == 0
      ? 0.0
      : remainderSupportCount / remainderTotalModes;
  final remainderShareGap = (remainderNearShare - remainderFalseShare).abs();
  final proxyScore = remainderShareGap * remainderPurity * remainderCaptureShare;
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
      if (_int(row['remainderSupportCount']) <
          _minimumMinorSliceSupportForRanking) {
        continue;
      }
      rows.add(row);
    }
  }
  rows.sort((left, right) {
    final scoreCmp =
        _number(right['proxyScore']).compareTo(_number(left['proxyScore']));
    if (scoreCmp != 0) return scoreCmp;
    final gapCmp = _number(_number(right['remainderShareGap']).abs()).compareTo(
      _number(_number(left['remainderShareGap']).abs()),
    );
    if (gapCmp != 0) return gapCmp;
    return _int(right['remainderSupportCount'])
        .compareTo(_int(left['remainderSupportCount']));
  });
  return rows.take(20).toList();
}

Map<String, Object?> _buildVariantComparison({
  required List<_Sample> validationTargetModes,
  required List<_Sample> sliceTargetModes,
}) {
  final variants = <String, Object?>{};
  for (final variant in _variantOrder) {
    final anchors = _ScoreAnchors.fromScores([
      for (final sample in validationTargetModes) sample.scoreForVariant(variant),
    ]);
    variants[variant] = {
      'scoreDefinition': _scoreDefinitionForVariant(variant),
      'scoreAnchors': anchors.toJson(),
      'validationModeMeans': {
        'nearThresholdPositive':
            _ScoreMeanAccumulator.fromSamples(
              validationTargetModes.where(
                (sample) => sample.isNearThresholdPositiveMode,
              ),
              variant: variant,
            ).toJson(),
        'falseMiddleTransition':
            _ScoreMeanAccumulator.fromSamples(
              validationTargetModes.where(
                (sample) => sample.isFalseMiddleTransitionMode,
              ),
              variant: variant,
            ).toJson(),
      },
      'minorSliceModeMeans': {
        'nearThresholdPositive':
            _ScoreMeanAccumulator.fromSamples(
              sliceTargetModes.where((sample) => sample.isNearThresholdPositiveMode),
              variant: variant,
            ).toJson(),
        'falseMiddleTransition':
            _ScoreMeanAccumulator.fromSamples(
              sliceTargetModes.where((sample) => sample.isFalseMiddleTransitionMode),
              variant: variant,
            ).toJson(),
      },
      'validationAnchoredBandTransfer': {
        'validation': _buildBandRows(
          validationTargetModes,
          anchors,
          variant: variant,
        ),
        'minorSlice': _buildBandRows(
          sliceTargetModes,
          anchors,
          variant: variant,
        ),
      },
      'minorSliceQuartiles': _buildQuartiles(sliceTargetModes, variant: variant),
      'minorSliceMonotonicity': _buildMonotonicity(
        _buildQuartiles(sliceTargetModes, variant: variant),
      ),
      'summary': _buildVariantSummary(
        validationTargetModes,
        sliceTargetModes,
        anchors,
        variant: variant,
      ),
    };
  }
  return variants;
}

Map<String, Object?> _scoreDefinitionForVariant(String variant) {
  switch (variant) {
    case 'support_geometry_only':
      return const {
        'weights': {'supportGeometry': 1.0},
        'components': {
          'supportGeometry':
              'mean(inverse(local mismatch, desirable <= 0.60, weak >= 0.85), direct(quadrants, weak <= 1, desirable >= 2), inverse(centroid offset, desirable <= 5 km, weak >= 10 km))',
        },
      };
    case 'support_geometry_plus_proximity':
      return const {
        'weights': {'supportGeometry': 0.7, 'evidenceProximity': 0.3},
        'components': {
          'supportGeometry':
              'same as supportGeometry-only',
          'evidenceProximity':
              'inverse(nearest evidence distance, desirable <= 2.5 km, weak >= 5 km)',
        },
      };
    default:
      return const {
        'weights': {
          'supportGeometry': 0.45,
          'concentration': 0.35,
          'evidenceProximity': 0.20,
        },
        'components': {
          'supportGeometry':
              'same as supportGeometry-only',
          'concentration':
              'mean(inverse(top contribution share, desirable <= 0.20, weak >= 0.33), inverse(HHI, desirable <= 0.10, weak >= 0.20))',
          'evidenceProximity':
              'inverse(nearest evidence distance, desirable <= 2.5 km, weak >= 5 km)',
        },
      };
  }
}

Map<String, Object?> _buildVariantSummary(
  List<_Sample> validationSamples,
  List<_Sample> sliceSamples,
  _ScoreAnchors anchors, {
  required String variant,
}) {
  final validationNear = _mean(
    validationSamples
        .where((sample) => sample.isNearThresholdPositiveMode)
        .map((sample) => sample.scoreForVariant(variant)),
  );
  final validationFalse = _mean(
    validationSamples
        .where((sample) => sample.isFalseMiddleTransitionMode)
        .map((sample) => sample.scoreForVariant(variant)),
  );
  final sliceNear = _mean(
    sliceSamples
        .where((sample) => sample.isNearThresholdPositiveMode)
        .map((sample) => sample.scoreForVariant(variant)),
  );
  final sliceFalse = _mean(
    sliceSamples
        .where((sample) => sample.isFalseMiddleTransitionMode)
        .map((sample) => sample.scoreForVariant(variant)),
  );
  final bandRows = _buildBandRows(sliceSamples, anchors, variant: variant);
  final lowBand = _map(
    bandRows.firstWhere(
      (raw) => _map(raw)['band'] == 'low',
      orElse: () => const <String, Object?>{},
    ),
  );
  final highBand = _map(
    bandRows.firstWhere(
      (raw) => _map(raw)['band'] == 'high',
      orElse: () => const <String, Object?>{},
    ),
  );
  final quartiles = _buildQuartiles(sliceSamples, variant: variant);
  final monotonicity = _buildMonotonicity(quartiles);
  return {
    'validationMeanGap': validationNear - validationFalse,
    'minorSliceMeanGap': sliceNear - sliceFalse,
    'lowBandFalseCaptureShare': _number(lowBand['negativeCaptureShare']),
    'lowBandNearCaptureShare': _number(lowBand['positiveCaptureShare']),
    'highBandNearRate': _number(highBand['positiveRate']),
    'highBandFalseRate': _number(highBand['negativeRate']),
    'highToLowPositiveLift':
        _number(monotonicity['highToLowPositiveLift']),
    'highToLowFalseRatio': _number(monotonicity['highToLowFalseRatio']),
    'stabilityLabel': _stabilityLabel(
      sampleCount: sliceSamples.length,
      monotonicity: monotonicity,
      bandRows: bandRows,
    ),
  };
}

List<Map<String, Object?>> _buildBandRows(
  List<_Sample> samples,
  _ScoreAnchors anchors, {
  required String variant,
}) {
  final rows = {
    'low': _BandAccumulator(),
    'mid_low': _BandAccumulator(),
    'mid_high': _BandAccumulator(),
    'high': _BandAccumulator(),
  };
  for (final sample in samples) {
    rows[anchors.bandFor(sample.scoreForVariant(variant))]!.add(sample);
  }
  final total = samples.length;
  final positiveTotal =
      samples.where((sample) => sample.isNearThresholdPositiveMode).length;
  final negativeTotal =
      samples.where((sample) => sample.isFalseMiddleTransitionMode).length;
  return [
    for (final band in const ['low', 'mid_low', 'mid_high', 'high'])
      rows[band]!.toJson(
        band: band,
        total: total,
        positiveTotal: positiveTotal,
        negativeTotal: negativeTotal,
      ),
  ];
}

List<Map<String, Object?>> _buildQuartiles(
  List<_Sample> samples, {
  required String variant,
}) {
  if (samples.isEmpty) return const [];
  final sorted = [...samples]
    ..sort((left, right) {
      return left.scoreForVariant(variant).compareTo(right.scoreForVariant(variant));
    });
  final rows = <Map<String, Object?>>[];
  final positiveTotal =
      samples.where((sample) => sample.isNearThresholdPositiveMode).length;
  final negativeTotal =
      samples.where((sample) => sample.isFalseMiddleTransitionMode).length;
  for (var quartile = 0; quartile < 4; quartile++) {
    final start = (sorted.length * quartile / 4).floor();
    final end = (sorted.length * (quartile + 1) / 4).floor();
    final bucket = sorted.sublist(start, end);
    final positive =
        bucket.where((sample) => sample.isNearThresholdPositiveMode).length;
    final negative =
        bucket.where((sample) => sample.isFalseMiddleTransitionMode).length;
    rows.add({
      'quartile': quartile + 1,
      'scoreMin': bucket.isEmpty ? 0.0 : bucket.first.scoreForVariant(variant),
      'scoreMax': bucket.isEmpty ? 0.0 : bucket.last.scoreForVariant(variant),
      'count': bucket.length,
      'positiveCount': positive,
      'negativeCount': negative,
      'positiveRate': bucket.isEmpty ? 0.0 : positive / bucket.length,
      'negativeRate': bucket.isEmpty ? 0.0 : negative / bucket.length,
      'positiveCaptureShare': positiveTotal == 0 ? 0.0 : positive / positiveTotal,
      'negativeCaptureShare': negativeTotal == 0 ? 0.0 : negative / negativeTotal,
    });
  }
  return rows;
}

Map<String, Object?> _buildMonotonicity(List<Map<String, Object?>> quartiles) {
  var positiveNonDecreasing = 0;
  var positiveDecreasing = 0;
  var negativeNonIncreasing = 0;
  var negativeIncreasing = 0;
  for (var i = 1; i < quartiles.length; i++) {
    final prev = _map(quartiles[i - 1]);
    final next = _map(quartiles[i]);
    final prevPositive = _number(prev['positiveRate']);
    final nextPositive = _number(next['positiveRate']);
    if (nextPositive >= prevPositive) {
      positiveNonDecreasing++;
    } else {
      positiveDecreasing++;
    }
    final prevNegative = _number(prev['negativeRate']);
    final nextNegative = _number(next['negativeRate']);
    if (nextNegative <= prevNegative) {
      negativeNonIncreasing++;
    } else {
      negativeIncreasing++;
    }
  }
  final low = quartiles.isEmpty ? const <String, Object?>{} : _map(quartiles.first);
  final high =
      quartiles.isEmpty ? const <String, Object?>{} : _map(quartiles.last);
  final lowPositive = _number(low['positiveRate']);
  final highPositive = _number(high['positiveRate']);
  final lowNegative = _number(low['negativeRate']);
  final highNegative = _number(high['negativeRate']);
  return {
    'highQuartilePositiveRate': highPositive,
    'lowQuartilePositiveRate': lowPositive,
    'highToLowPositiveLift': lowPositive == 0 ? 0.0 : highPositive / lowPositive,
    'lowQuartileNegativeRate': lowNegative,
    'highQuartileNegativeRate': highNegative,
    'highToLowFalseRatio': lowNegative == 0 ? 0.0 : highNegative / lowNegative,
    'positiveNonDecreasingAdjacentPairs': positiveNonDecreasing,
    'positiveDecreasingAdjacentPairs': positiveDecreasing,
    'negativeNonIncreasingAdjacentPairs': negativeNonIncreasing,
    'negativeIncreasingAdjacentPairs': negativeIncreasing,
  };
}

String _stabilityLabel({
  required int sampleCount,
  required Map<String, Object?> monotonicity,
  required List<Map<String, Object?>> bandRows,
}) {
  if (sampleCount < 8) return 'sample_sparse';
  final highBand = _map(
    bandRows.firstWhere(
      (row) => _map(row)['band'] == 'high',
      orElse: () => const <String, Object?>{},
    ),
  );
  final lowBand = _map(
    bandRows.firstWhere(
      (row) => _map(row)['band'] == 'low',
      orElse: () => const <String, Object?>{},
    ),
  );
  final directional =
      _number(highBand['positiveRate']) >= _number(lowBand['positiveRate']) &&
      _number(highBand['negativeRate']) <= _number(lowBand['negativeRate']);
  final monotone =
      _number(monotonicity['positiveDecreasingAdjacentPairs']) == 0 &&
      _number(monotonicity['negativeIncreasingAdjacentPairs']) == 0;
  if (directional && monotone) return 'stable';
  if (directional) return 'directional_but_noisy';
  return 'not_stable';
}

Map<String, int> _eventCounts(List<_Sample> samples) {
  final counts = <String, int>{};
  for (final sample in samples) {
    counts[sample.eventId] = (counts[sample.eventId] ?? 0) + 1;
  }
  return Map.fromEntries(
    counts.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        if (byCount != 0) return byCount;
        return left.key.compareTo(right.key);
      }),
  );
}

List<_Sample> _sortedSamples(List<_Sample> samples) {
  final rows = [...samples];
  rows.sort((left, right) {
    final eventCmp = left.eventId.compareTo(right.eventId);
    if (eventCmp != 0) return eventCmp;
    final labelCmp = left.modeLabel.compareTo(right.modeLabel);
    if (labelCmp != 0) return labelCmp;
    return right.actual.compareTo(left.actual);
  });
  return rows;
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

String plumTohokuMismatchOneSidedCompactMinorEventPooledSignalDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final scope = _map(report['scope']);
  final modeDefinitions = _map(report['modeDefinitions']);
  final modeFeatureMeans = _map(report['modeFeatureMeans']);
  final variantComparison = _map(report['variantComparison']);
  final featureFamilies = _map(report['featureFamilies']);
  final rankedSeparators = _list(report['rankedSeparators']);
  final minorSliceEvents = _list(report['minorSliceEvents']);
  final sampleLedger = _list(report['sampleLedger']);
  final buffer = StringBuffer()
    ..writeln(
      '# PLUM Tohoku mismatch/one_sided/compact Minor-Event Pooled Signal Diagnostic',
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
      '| `validation target modes` | ${coverage['validationTargetModes']} |',
    )
    ..writeln(
      '| `minor-slice target modes` | ${coverage['minorSliceTargetModes']} |',
    )
    ..writeln(
      '| `validation near-threshold positives` | ${coverage['validationNearThresholdPositiveCount']} |',
    )
    ..writeln(
      '| `validation false middle-transition` | ${coverage['validationFalseMiddleTransitionCount']} |',
    )
    ..writeln(
      '| `minor-slice near-threshold positives` | ${coverage['minorNearThresholdPositiveCount']} |',
    )
    ..writeln(
      '| `minor-slice false middle-transition` | ${coverage['minorFalseMiddleTransitionCount']} |',
    )
    ..writeln(
      '| `minor-slice events` | ${coverage['minorSliceEventCount']} |',
    )
    ..writeln()
    ..writeln('## Scope')
    ..writeln()
    ..writeln(
      '- Removed dominant event: `${scope['removedDominantEvent']}`',
    )
    ..writeln(
      '- Additional excluded event for minor slice: `${scope['minorSliceExcludedEvent']}`',
    )
    ..writeln(
      '- Estimated-source region: `${scope['estimatedSourceRegion']}`',
    )
    ..writeln(
      '- Fixed family: `${report['inputs'] is Map ? _map(report['inputs'])['family'] : _focusFamily}`',
    )
    ..writeln(
      '- Minimum evidence count: `${scope['minimumEvidenceCount']}`',
    )
    ..writeln(
      '- Maximum nearest evidence distance: '
      '`${scope['maximumNearestEvidenceDistanceKm']} km`',
    )
    ..writeln()
    ..writeln('## Minor Slice Events')
    ..writeln()
    ..writeln('| Event | Count |')
    ..writeln('| --- | ---: |');
  for (final raw in minorSliceEvents) {
    final row = _map(raw);
    buffer.writeln('| `${row['eventId']}` | ${row['count']} |');
  }
  buffer
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
    ..writeln('## Variant Summary')
    ..writeln()
    ..writeln(
      '| Variant | Val Mean Gap | Minor Mean Gap | Stability | Low False Capture | Low Near Capture | High Near Rate | High False Rate | High/Low Near Lift | High/Low False Ratio |',
    )
    ..writeln(
      '| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final variant in _variantOrder) {
    final summary = _map(_map(variantComparison[variant])['summary']);
    buffer.writeln(
      '| `$variant` | ${_fmt(summary['validationMeanGap'])} | ${_fmt(summary['minorSliceMeanGap'])} | `${summary['stabilityLabel']}` | ${_pct(summary['lowBandFalseCaptureShare'])} | ${_pct(summary['lowBandNearCaptureShare'])} | ${_pct(summary['highBandNearRate'])} | ${_pct(summary['highBandFalseRate'])} | ${_fmtMultiplier(_number(summary['highToLowPositiveLift']))} | ${_fmtMultiplier(_number(summary['highToLowFalseRatio']))} |',
    );
  }
  for (final variant in _variantOrder) {
    final variantJson = _map(variantComparison[variant]);
    final definition = _map(variantJson['scoreDefinition']);
    final anchors = _map(variantJson['scoreAnchors']);
    final validationMeans = _map(variantJson['validationModeMeans']);
    final minorMeans = _map(variantJson['minorSliceModeMeans']);
    final transfer = _map(variantJson['validationAnchoredBandTransfer']);
    final validationBands = _list(transfer['validation']);
    final minorBands = _list(transfer['minorSlice']);
    final quartiles = _list(variantJson['minorSliceQuartiles']);
    final monotonicity = _map(variantJson['minorSliceMonotonicity']);
    buffer
      ..writeln()
      ..writeln('## `$variant`')
      ..writeln()
      ..writeln('- Weights: `${jsonEncode(definition['weights'])}`')
      ..writeln(
        '- Validation anchors: q25 `${_fmt(anchors['q25'])}`, q50 `${_fmt(anchors['q50'])}`, q75 `${_fmt(anchors['q75'])}`.',
      )
      ..writeln()
      ..writeln('### Mode Score Means')
      ..writeln()
      ..writeln('| Slice | Mode | Count | Score |')
      ..writeln('| --- | --- | ---: | ---: |')
      ..writeln(
        '| `validation` | `nearThresholdPositive` | ${_map(validationMeans['nearThresholdPositive'])['count']} | ${_fmt(_map(validationMeans['nearThresholdPositive'])['score'])} |',
      )
      ..writeln(
        '| `validation` | `falseMiddleTransition` | ${_map(validationMeans['falseMiddleTransition'])['count']} | ${_fmt(_map(validationMeans['falseMiddleTransition'])['score'])} |',
      )
      ..writeln(
        '| `minorSlice` | `nearThresholdPositive` | ${_map(minorMeans['nearThresholdPositive'])['count']} | ${_fmt(_map(minorMeans['nearThresholdPositive'])['score'])} |',
      )
      ..writeln(
        '| `minorSlice` | `falseMiddleTransition` | ${_map(minorMeans['falseMiddleTransition'])['count']} | ${_fmt(_map(minorMeans['falseMiddleTransition'])['score'])} |',
      )
      ..writeln()
      ..writeln('### Validation-Anchored Band Transfer')
      ..writeln()
      ..writeln(
        '| Band | Val Count | Val Near | Val False | Minor Count | Minor Near | Minor False | Minor Near Rate | Minor False Rate | Minor Near Capture | Minor False Capture |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (var i = 0; i < validationBands.length; i++) {
      final left = _map(validationBands[i]);
      final right = _map(minorBands[i]);
      buffer.writeln(
        '| `${left['band']}` | ${left['count']} | ${left['positiveCount']} | ${left['negativeCount']} | ${right['count']} | ${right['positiveCount']} | ${right['negativeCount']} | ${_pct(right['positiveRate'])} | ${_pct(right['negativeRate'])} | ${_pct(right['positiveCaptureShare'])} | ${_pct(right['negativeCaptureShare'])} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Minor Slice Quartiles')
      ..writeln()
      ..writeln(
        '| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final raw in quartiles) {
      final row = _map(raw);
      buffer.writeln(
        '| ${row['quartile']} | ${_fmt(row['scoreMin'])} | ${_fmt(row['scoreMax'])} | ${row['count']} | ${row['positiveCount']} | ${row['negativeCount']} | ${_pct(row['positiveRate'])} | ${_pct(row['negativeRate'])} | ${_pct(row['positiveCaptureShare'])} | ${_pct(row['negativeCaptureShare'])} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Minor Slice Monotonicity')
      ..writeln()
      ..writeln(
        '- High quartile near-positive rate: `${_pct(monotonicity['highQuartilePositiveRate'])}`; low quartile near-positive rate: `${_pct(monotonicity['lowQuartilePositiveRate'])}`.',
      )
      ..writeln(
        '- High-to-low near-positive lift: `${_fmtMultiplier(_number(monotonicity['highToLowPositiveLift']))}`.',
      )
      ..writeln(
        '- Low quartile false rate: `${_pct(monotonicity['lowQuartileNegativeRate'])}`; high quartile false rate: `${_pct(monotonicity['highQuartileNegativeRate'])}`.',
      )
      ..writeln(
        '- High/low false-rate ratio: `${_fmtMultiplier(_number(monotonicity['highToLowFalseRatio']))}`.',
      );
  }
  buffer
    ..writeln()
    ..writeln('## Minor Slice Mode Feature Means')
    ..writeln()
    ..writeln(
      '| Mode | Count | Local Mismatch | Evidence Count | Nearest Dist | Quadrants | Centroid Offset | Max Spread | Top1 Share | HHI | Mean Margin | Eff Support |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final mode in const [
    'minorNearThresholdPositive',
    'minorFalseMiddleTransition',
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
      '| Family | Bucket | Minor Near | Minor False | Near Share | False Share | Support | Dominant | Purity | Capture | Score |',
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

  buffer
    ..writeln()
    ..writeln('## Sample Ledger')
    ..writeln()
    ..writeln(
      '| Event | Mode | Actual | JMA | PLUM | Evidence | Nearest Dist | Local Mismatch | Quadrants | Centroid | SG Only | SG+Prox | Full |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final raw in sampleLedger) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['eventId']}` | `${row['modeLabel']}` | ${_fmt(row['actual'])} | ${_fmt(row['jma'])} | ${_fmt(row['plum'])} | ${row['evidenceCount']} | ${_fmt(row['nearestEvidenceDistanceKm'])} | ${_fmt(row['localMismatch'])} | ${row['quadrantCoverage']} | ${_fmt(row['centroidOffsetKm'])} | ${_fmt(row['supportGeometryOnlyScore'])} | ${_fmt(row['supportGeometryPlusProximityScore'])} | ${_fmt(row['fullScore'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report remains diagnostic-only. It inspects the minor-event pooled slice created by excluding the dominant residual event and the largest surviving residual event.',
    )
    ..writeln(
      '- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.',
    );

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

  String get modeLabel {
    if (isNearThresholdPositiveMode) return 'near_threshold_positive';
    if (isFalseMiddleTransitionMode) return 'false_middle_transition';
    return 'other';
  }

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

  double get supportGeometryScore {
    final localMismatchComponent = _inverseLinear(
      localBelowThresholdShare10Km,
      desirableCeiling: 0.60,
      weakFloor: 0.85,
    );
    final quadrantComponent = _directLinear(
      supportingEvidenceQuadrantCoverage.toDouble(),
      weakFloor: 1.0,
      desirableCeiling: 2.0,
    );
    final centroidOffsetComponent = _inverseLinear(
      supportingEvidenceCentroidOffsetKm,
      desirableCeiling: 5.0,
      weakFloor: 10.0,
    );
    return (localMismatchComponent +
            quadrantComponent +
            centroidOffsetComponent) /
        3.0;
  }

  double get concentrationScore {
    final topShareComponent = _inverseLinear(
      topContributionShare,
      desirableCeiling: 0.20,
      weakFloor: 0.33,
    );
    final hhiComponent = _inverseLinear(
      contributionHhi,
      desirableCeiling: 0.10,
      weakFloor: 0.20,
    );
    return 0.5 * topShareComponent + 0.5 * hhiComponent;
  }

  double get evidenceProximityScore => _inverseLinear(
        nearestEvidenceDistanceKm,
        desirableCeiling: 2.5,
        weakFloor: 5.0,
      );

  double scoreForVariant(String variant) {
    switch (variant) {
      case 'support_geometry_only':
        return _clamp01(supportGeometryScore);
      case 'support_geometry_plus_proximity':
        return _clamp01(
          0.70 * supportGeometryScore + 0.30 * evidenceProximityScore,
        );
      default:
        return _clamp01(
          0.45 * supportGeometryScore +
              0.35 * concentrationScore +
              0.20 * evidenceProximityScore,
        );
    }
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

  Map<String, Object?> toLedgerJson() => {
        'eventId': eventId,
        'modeLabel': modeLabel,
        'actual': actual,
        'jma': jma,
        'plum': plum,
        'evidenceCount': evidenceCount,
        'nearestEvidenceDistanceKm': nearestEvidenceDistanceKm,
        'localMismatch': localBelowThresholdShare10Km,
        'quadrantCoverage': supportingEvidenceQuadrantCoverage,
        'centroidOffsetKm': supportingEvidenceCentroidOffsetKm,
        'maxSpreadKm': supportingEvidenceMaxSpreadKm,
        'topContributionShare': topContributionShare,
        'contributionHhi': contributionHhi,
        'meanContributionMargin': meanContributionMargin,
        'effectiveSupportCount': effectiveSupportCount,
        'supportGeometryOnlyScore': scoreForVariant('support_geometry_only'),
        'supportGeometryPlusProximityScore':
            scoreForVariant('support_geometry_plus_proximity'),
        'fullScore': scoreForVariant('full_score'),
      };
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
        'supportingEvidenceQuadrantCoverage':
            supportingEvidenceQuadrantCoverage,
        'supportingEvidenceCentroidOffsetKm':
            supportingEvidenceCentroidOffsetKm,
        'supportingEvidenceMaxSpreadKm': supportingEvidenceMaxSpreadKm,
        'topContributionShare': topContributionShare,
        'contributionHhi': contributionHhi,
        'meanContributionMargin': meanContributionMargin,
        'effectiveSupportCount': effectiveSupportCount,
      };
}

class _BandAccumulator {
  int count = 0;
  int positiveCount = 0;
  int negativeCount = 0;

  void add(_Sample sample) {
    count++;
    if (sample.isNearThresholdPositiveMode) positiveCount++;
    if (sample.isFalseMiddleTransitionMode) negativeCount++;
  }

  Map<String, Object?> toJson({
    required String band,
    required int total,
    required int positiveTotal,
    required int negativeTotal,
  }) => {
        'band': band,
        'count': count,
        'share': total == 0 ? 0.0 : count / total,
        'positiveCount': positiveCount,
        'negativeCount': negativeCount,
        'positiveRate': count == 0 ? 0.0 : positiveCount / count,
        'negativeRate': count == 0 ? 0.0 : negativeCount / count,
        'positiveCaptureShare':
            positiveTotal == 0 ? 0.0 : positiveCount / positiveTotal,
        'negativeCaptureShare':
            negativeTotal == 0 ? 0.0 : negativeCount / negativeTotal,
      };
}

class _ScoreMeanAccumulator {
  final int count;
  final double mean;

  const _ScoreMeanAccumulator({required this.count, required this.mean});

  factory _ScoreMeanAccumulator.fromSamples(
    Iterable<_Sample> samples, {
    required String variant,
  }) {
    var count = 0;
    var sum = 0.0;
    for (final sample in samples) {
      count++;
      sum += sample.scoreForVariant(variant);
    }
    return _ScoreMeanAccumulator(
      count: count,
      mean: count == 0 ? 0.0 : sum / count,
    );
  }

  Map<String, Object?> toJson() => {'count': count, 'score': mean};
}

class _ScoreAnchors {
  final double q25;
  final double q50;
  final double q75;

  const _ScoreAnchors({
    required this.q25,
    required this.q50,
    required this.q75,
  });

  factory _ScoreAnchors.fromScores(List<double> scores) {
    if (scores.isEmpty) {
      return const _ScoreAnchors(q25: 0.0, q50: 0.0, q75: 0.0);
    }
    final sorted = [...scores]..sort();
    return _ScoreAnchors(
      q25: _percentile(sorted, 0.25),
      q50: _percentile(sorted, 0.50),
      q75: _percentile(sorted, 0.75),
    );
  }

  String bandFor(double score) {
    if (score <= q25) return 'low';
    if (score <= q50) return 'mid_low';
    if (score <= q75) return 'mid_high';
    return 'high';
  }

  Map<String, Object?> toJson() => {
        'q25': q25,
        'q50': q50,
        'q75': q75,
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

  const _NeighborSummary({required this.count, required this.belowThresholdShare});
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
          'plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': 'fail',
      'policy': {
        'method':
            'PLUM Tohoku mismatch/one_sided/compact minor-event pooled signal diagnostic',
        'rawPredictedIntensityMutated': false,
        'frozenTestEvaluated': true,
        'productionReady': false,
        'productionUiConnected': false,
        'diagnosticOnly': true,
        'parametersTuned': false,
        'suppressionApplied': false,
        'plumRadiusKm': _plumRadiusKm,
        'plumDampingPer10Km': _plumDampingPer10Km,
        'minimumMinorSliceSupportForRanking':
            _minimumMinorSliceSupportForRanking,
      },
      'inputs': {
        'dataDirectory': dataDirectory,
        'modelPath': modelPath,
        'splits': ['validation', 'test'],
        'threshold': _threshold.label,
        'family': _focusFamily,
        'variants': _variantOrder,
      },
      'scope': {
        'removedDominantEvent': 'none',
        'minorSliceExcludedEvent': _minorSliceExcludedEventId,
        'estimatedSourceRegion': _focusRegion,
        'minimumEvidenceCount': _focusMinimumEvidenceCount,
        'maximumNearestEvidenceDistanceKm':
            _focusMaximumNearestEvidenceDistanceKm,
        'baselineThresholdCrossingRequired': true,
      },
      'modeDefinitions': const {},
      'featureDefinitions': const {},
      'coverage': {
        'validationTargetModes': 0,
        'minorSliceTargetModes': 0,
        'validationNearThresholdPositiveCount': 0,
        'validationFalseMiddleTransitionCount': 0,
        'minorNearThresholdPositiveCount': 0,
        'minorFalseMiddleTransitionCount': 0,
        'minorSliceEventCount': 0,
        'skippedMissingMagnitudeEvents': 0,
        'skippedNoSourceEstimateVariants': 0,
      },
      'modeFeatureMeans': const {},
      'minorSliceEvents': const [],
      'variantComparison': const {},
      'featureFamilies': const {},
      'rankedSeparators': const [],
      'sampleLedger': const [],
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

double _clamp01(double value) {
  if (value.isNaN) return 0.0;
  if (value <= 0.0) return 0.0;
  if (value >= 1.0) return 1.0;
  return value;
}

double _inverseLinear(
  double value, {
  required double desirableCeiling,
  required double weakFloor,
}) {
  if (!value.isFinite) return 0.0;
  if (value <= desirableCeiling) return 1.0;
  if (value >= weakFloor) return 0.0;
  return 1.0 - (value - desirableCeiling) / (weakFloor - desirableCeiling);
}

double _directLinear(
  double value, {
  required double weakFloor,
  required double desirableCeiling,
}) {
  if (!value.isFinite) return 0.0;
  if (value <= weakFloor) return 0.0;
  if (value >= desirableCeiling) return 1.0;
  return (value - weakFloor) / (desirableCeiling - weakFloor);
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0.0;
  if (sorted.length == 1) return sorted.first;
  final position = (sorted.length - 1) * p;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
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

String _fmtMultiplier(double value) => '${value.toStringAsFixed(2)}x';
