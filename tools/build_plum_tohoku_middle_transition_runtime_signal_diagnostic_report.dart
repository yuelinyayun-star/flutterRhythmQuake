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
    '.dart_tool/plum_tohoku_middle_transition_runtime_signal_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_middle_transition_runtime_signal_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusMinimumMargin = 1.0;
const _localNeighbor10Km = 10.0;
const _minTestSamplesForRanking = 20;
const _threshold = _Threshold('shindo4', 3.5);
const _featureFamilyOrder = [
  'topContributionShareBand',
  'top2ContributionShareBand',
  'contributionHhiBand',
  'dominanceShareGapBand',
  'dominanceMarginGapBand',
  'marginStdDevBand',
  'marginRangeBand',
  'meanContributionMarginBand',
  'effectiveSupportCountBand',
  'topContributionShareBand|geometrySpread',
  'contributionHhiBand|plumMarginBand',
  'marginStdDevBand|plumMarginBand',
];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuMiddleTransitionRuntimeSignalDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMiddleTransitionRuntimeSignalDiagnosticMarkdown(report),
  );

  stdout.writeln(
    'wrote PLUM Tohoku middle-transition runtime-signal diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?>
buildPlumTohokuMiddleTransitionRuntimeSignalDiagnosticJson({
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
        final region = _eventLatitudeBucket(estimate.latitude);
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
          final margin = plum.intensity - _threshold.value;
          if (region != _focusRegion) continue;
          if (baselineRaw < _threshold.value) continue;
          if (plum.evidenceCount < _focusMinimumEvidenceCount) continue;
          if (!plum.nearestEvidenceDistanceKm.isFinite ||
              plum.nearestEvidenceDistanceKm >=
                  _focusMaximumNearestEvidenceDistanceKm) {
            continue;
          }
          if (margin < _focusMinimumMargin) continue;

          final r20 = plumR20D050.predict(
            targetStation: station,
            observedStations: retained,
          );
          final r30D075 = plumR30D075.predict(
            targetStation: station,
            observedStations: retained,
          );
          final sample = _buildSignalSample(
            event: event,
            targetStation: station,
            retainedStations: retained,
            threshold: _threshold,
            jmaPredictedIntensity: jma,
            plum: plum,
            r20: r20.intensity,
            r30D075: r30D075.intensity,
          );
          splitAccumulator.add(sample);
        }
      }
    }
  }

  final validation = splitAccumulators['validation']!;
  final test = splitAccumulators['test']!;
  final featureFamilies = {
    for (final family in _featureFamilyOrder)
      family: _buildFamilyJson(
        family: family,
        validation: validation,
        test: test,
      ),
  };

  return {
    'schemaVersion':
        'plum_tohoku_middle_transition_runtime_signal_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku middle-transition runtime-signal diagnostic',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'suppressionApplied': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
      'minimumTestSamplesForRanking': _minTestSamplesForRanking,
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
      'minimumPredictionMarginShindo': _focusMinimumMargin,
      'baselineThresholdCrossingRequired': true,
    },
    'labelDefinition': const {
      'positiveLabel': 'middle_transition_zone',
      'truthInputs': [
        'actualGapBand in {-1.0_to_0.0, 0.0_to_1.0}',
        'evidenceGapBand in {1.0_to_2.0, 2.0_to_3.0}',
        'localConsistencyLabel == mismatch',
      ],
      'negativeLabel': 'all_other_focus_samples',
      'productionFeatureBoundary':
          'candidate signals must use only runtime-visible support contributions and support geometry',
    },
    'featureDefinitions': const {
      'topContributionShareBand':
          'largest propagated excess share within supporting evidence',
      'top2ContributionShareBand':
          'combined top-2 propagated excess share within supporting evidence',
      'contributionHhiBand':
          'Herfindahl concentration index over normalized propagated excess',
      'dominanceShareGapBand':
          'top1 share minus top2 share within supporting evidence',
      'dominanceMarginGapBand':
          'top1 propagated excess minus top2 propagated excess',
      'marginStdDevBand':
          'standard deviation of supporting propagated excess values',
      'marginRangeBand': 'max-minus-min supporting propagated excess',
      'meanContributionMarginBand': 'mean supporting propagated excess',
      'effectiveSupportCountBand':
          '1 / HHI as a soft effective-support count proxy',
    },
    'coverage': {
      'validationVariants': validation.variantCount,
      'testVariants': test.variantCount,
      'validationStationForecasts': validation.stationForecastCount,
      'testStationForecasts': test.stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'labelSummary': {
      'validation': validation.summary.toJson(),
      'test': test.summary.toJson(),
    },
    'testOutcomeFeatureMeans': _buildOutcomeFeatureMeans(test),
    'featureFamilies': featureFamilies,
    'rankedCandidates': _buildRankedCandidates(featureFamilies),
    'errors': errors,
  };
}

Map<String, Object?> _buildFamilyJson({
  required String family,
  required _SplitAccumulator validation,
  required _SplitAccumulator test,
}) {
  final validationBuckets = validation.bucketsForFamily(family);
  final testBuckets = test.bucketsForFamily(family);
  final keys = {...validationBuckets.keys, ...testBuckets.keys}.toList()
    ..sort();
  return {
    'validationPositiveCount': validation.summary.middleTransitionCount,
    'testPositiveCount': test.summary.middleTransitionCount,
    'buckets': [
      for (final key in keys)
        _bucketRow(
          family: family,
          bucket: key,
          validationBucket: validationBuckets[key],
          testBucket: testBuckets[key],
          validationTotal: validation.summary.focusSampleCount,
          testTotal: test.summary.focusSampleCount,
          validationPositiveTotal: validation.summary.middleTransitionCount,
          testPositiveTotal: test.summary.middleTransitionCount,
          testBaselineRate: test.summary.middleTransitionRate,
        ),
    ],
  };
}

Map<String, Object?> _bucketRow({
  required String family,
  required String bucket,
  required _BucketStats? validationBucket,
  required _BucketStats? testBucket,
  required int validationTotal,
  required int testTotal,
  required int validationPositiveTotal,
  required int testPositiveTotal,
  required double testBaselineRate,
}) {
  final validationCount = validationBucket?.count ?? 0;
  final validationPositiveCount = validationBucket?.positiveCount ?? 0;
  final testCount = testBucket?.count ?? 0;
  final testPositiveCount = testBucket?.positiveCount ?? 0;
  final validationRate = validationCount == 0
      ? 0.0
      : validationPositiveCount / validationCount;
  final testRate = testCount == 0 ? 0.0 : testPositiveCount / testCount;
  final testCaptureShare = testPositiveTotal == 0
      ? 0.0
      : testPositiveCount / testPositiveTotal;
  final proxyScore = (testRate + testCaptureShare) == 0
      ? 0.0
      : 2 * testRate * testCaptureShare / (testRate + testCaptureShare);
  final testLift = testBaselineRate == 0 ? 0.0 : testRate / testBaselineRate;
  return {
    'family': family,
    'bucket': bucket,
    'validationCount': validationCount,
    'validationShare': validationTotal == 0
        ? 0.0
        : validationCount / validationTotal,
    'validationPositiveCount': validationPositiveCount,
    'validationPositiveRate': validationRate,
    'testCount': testCount,
    'testShare': testTotal == 0 ? 0.0 : testCount / testTotal,
    'testPositiveCount': testPositiveCount,
    'testPositiveRate': testRate,
    'testPositiveCaptureShare': testCaptureShare,
    'sampleShareDelta':
        (testTotal == 0 ? 0.0 : testCount / testTotal) -
        (validationTotal == 0 ? 0.0 : validationCount / validationTotal),
    'positiveRateDelta': testRate - validationRate,
    'testLift': testLift,
    'proxyScore': proxyScore,
  };
}

List<Map<String, Object?>> _buildRankedCandidates(
  Map<String, Object?> featureFamilies,
) {
  final rows = <Map<String, Object?>>[];
  for (final family in _featureFamilyOrder) {
    final buckets = _list(_map(featureFamilies[family])['buckets']);
    for (final raw in buckets) {
      final row = _map(raw);
      if (_int(row['testCount']) < _minTestSamplesForRanking) continue;
      rows.add(row);
    }
  }
  rows.sort((left, right) {
    final scoreCmp = _number(
      right['proxyScore'],
    ).compareTo(_number(left['proxyScore']));
    if (scoreCmp != 0) return scoreCmp;
    final liftCmp = _number(
      right['testLift'],
    ).compareTo(_number(left['testLift']));
    if (liftCmp != 0) return liftCmp;
    return _int(
      right['testPositiveCount'],
    ).compareTo(_int(left['testPositiveCount']));
  });
  return rows.take(20).toList();
}

Map<String, Object?> _buildOutcomeFeatureMeans(_SplitAccumulator split) {
  final positive = _FeatureMeanAccumulator();
  final negative = _FeatureMeanAccumulator();
  for (final sample in split.samples) {
    if (sample.isMiddleTransitionZone) {
      positive.add(sample);
    } else {
      negative.add(sample);
    }
  }
  return {
    'middleTransitionZone': positive.toJson(),
    'otherFocusSamples': negative.toJson(),
  };
}

_SignalSample _buildSignalSample({
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
    _localNeighbor10Km,
  );
  final supportShape = _supportShape(
    targetStation: targetStation,
    evidenceStations: supportingEvidence,
  );
  final contribution = _supportContributionSummary(
    threshold: threshold.value,
    evidenceStations: supportingEvidence,
  );
  return _SignalSample(
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
    top2ContributionShare: contribution.top2ContributionShare,
    contributionHhi: contribution.contributionHhi,
    dominanceShareGap: contribution.dominanceShareGap,
    dominanceMarginGap: contribution.dominanceMarginGap,
    contributionMarginStdDev: contribution.marginStdDev,
    contributionMarginRange: contribution.marginRange,
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
      top2ContributionShare: 0,
      contributionHhi: 0,
      dominanceShareGap: 0,
      dominanceMarginGap: 0,
      marginStdDev: 0,
      marginRange: 0,
      meanMargin: 0,
      effectiveSupportCount: 0,
    );
  }
  final margins = [
    for (final evidence in evidenceStations)
      math.max(0.0, evidence.propagatedIntensity - threshold),
  ]..sort((left, right) => right.compareTo(left));
  final total = margins.fold<double>(0.0, (sum, value) => sum + value);
  final top1 = margins.first;
  final top2 = margins.length > 1 ? margins[1] : 0.0;
  final topContributionShare = total <= 0 ? 0.0 : top1 / total;
  final top2ContributionShare = total <= 0 ? 0.0 : (top1 + top2) / total;
  final contributionHhi = total <= 0
      ? 0.0
      : margins
            .map((margin) => margin / total)
            .fold<double>(0.0, (sum, share) => sum + share * share);
  final mean = total / margins.length;
  final variance =
      margins.fold<double>(
        0.0,
        (sum, margin) => sum + math.pow(margin - mean, 2).toDouble(),
      ) /
      margins.length;
  final minMargin = margins.last;
  return _ContributionSummary(
    topContributionShare: topContributionShare,
    top2ContributionShare: top2ContributionShare,
    contributionHhi: contributionHhi,
    dominanceShareGap: total <= 0 ? 0.0 : (top1 - top2) / total,
    dominanceMarginGap: top1 - top2,
    marginStdDev: math.sqrt(variance),
    marginRange: top1 - minMargin,
    meanMargin: mean,
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

String plumTohokuMiddleTransitionRuntimeSignalDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final labelSummary = _map(report['labelSummary']);
  final outcomeMeans = _map(report['testOutcomeFeatureMeans']);
  final featureFamilies = _map(report['featureFamilies']);
  final rankedCandidates = _list(report['rankedCandidates']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Middle-Transition Runtime-Signal Diagnostic')
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
      '| Split | Variants | Station forecasts | Focus samples | Middle-transition samples | Rate |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
  for (final split in const ['validation', 'test']) {
    final summary = _map(labelSummary[split]);
    buffer.writeln(
      '| $split | ${coverage['${split}Variants']} | ${coverage['${split}StationForecasts']} | '
      '${summary['focusSampleCount']} | ${summary['middleTransitionCount']} | '
      '${_pct(summary['middleTransitionRate'])} |',
    );
  }
  buffer
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
      '- Minimum prediction margin: '
      '`${focusFilter['minimumPredictionMarginShindo']} shindo`',
    )
    ..writeln(
      '- Baseline threshold crossing required: '
      '`${focusFilter['baselineThresholdCrossingRequired']}`',
    )
    ..writeln()
    ..writeln('## Test Outcome Feature Means')
    ..writeln()
    ..writeln(
      '| Outcome | Top1 Share | Top2 Share | HHI | Dominance Share Gap | Dominance Margin Gap | Margin StdDev | Margin Range | Mean Margin | Effective Support Count |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final outcome in const ['middleTransitionZone', 'otherFocusSamples']) {
    final row = _map(outcomeMeans[outcome]);
    buffer.writeln(
      '| `$outcome` | ${_fmt(row['topContributionShare'])} | ${_fmt(row['top2ContributionShare'])} | '
      '${_fmt(row['contributionHhi'])} | ${_fmt(row['dominanceShareGap'])} | '
      '${_fmt(row['dominanceMarginGap'])} | ${_fmt(row['marginStdDev'])} | '
      '${_fmt(row['marginRange'])} | ${_fmt(row['meanContributionMargin'])} | '
      '${_fmt(row['effectiveSupportCount'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Ranked Runtime-Signal Candidates')
    ..writeln()
    ..writeln(
      '| Family | Bucket | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score | Share Delta |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in rankedCandidates) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['family']}` | `${row['bucket']}` | ${row['testCount']} | '
      '${row['testPositiveCount']} | ${_pct(row['testPositiveRate'])} | '
      '${_fmtMultiplier(_number(row['testLift']))} | '
      '${_pct(row['testPositiveCaptureShare'])} | ${_pct(row['proxyScore'])} | '
      '${_signedPct(_number(row['sampleShareDelta']))} |',
    );
  }
  for (final family in _featureFamilyOrder) {
    final buckets = _list(_map(featureFamilies[family])['buckets']);
    buffer
      ..writeln()
      ..writeln('## `$family`')
      ..writeln()
      ..writeln(
        '| Bucket | Val Samples | Val Rate | Test Samples | Test Middle | Test Rate | Lift | Capture Share | Proxy Score |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final raw in buckets) {
      final row = _map(raw);
      if (_int(row['validationCount']) == 0 && _int(row['testCount']) == 0) {
        continue;
      }
      buffer.writeln(
        '| `${row['bucket']}` | ${row['validationCount']} | ${_pct(row['validationPositiveRate'])} | '
        '${row['testCount']} | ${row['testPositiveCount']} | ${_pct(row['testPositiveRate'])} | '
        '${_fmtMultiplier(_number(row['testLift']))} | ${_pct(row['testPositiveCaptureShare'])} | ${_pct(row['proxyScore'])} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report remains diagnostic-only. It scores runtime-visible '
      'support-contribution signals against a truth-defined middle-transition '
      'label without changing PLUM or any production behavior.',
    )
    ..writeln(
      '- It does not tune PLUM, suppress predictions, or authorize production '
      'UI/wording/notification changes.',
    )
    ..writeln();
  return buffer.toString();
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final samples = <_SignalSample>[];

  void add(_SignalSample sample) => samples.add(sample);

  _LabelSummary get summary {
    final middle = samples
        .where((sample) => sample.isMiddleTransitionZone)
        .length;
    return _LabelSummary(
      focusSampleCount: samples.length,
      middleTransitionCount: middle,
    );
  }

  Map<String, _BucketStats> bucketsForFamily(String family) {
    final buckets = <String, _BucketStats>{};
    for (final sample in samples) {
      final key = sample.bucketForFamily(family);
      buckets
          .putIfAbsent(key, _BucketStats.new)
          .add(sample.isMiddleTransitionZone);
    }
    return buckets;
  }
}

class _LabelSummary {
  final int focusSampleCount;
  final int middleTransitionCount;

  const _LabelSummary({
    required this.focusSampleCount,
    required this.middleTransitionCount,
  });

  double get middleTransitionRate =>
      focusSampleCount == 0 ? 0.0 : middleTransitionCount / focusSampleCount;

  Map<String, Object?> toJson() => {
    'focusSampleCount': focusSampleCount,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionRate': middleTransitionRate,
  };
}

class _BucketStats {
  int count = 0;
  int positiveCount = 0;

  void add(bool positive) {
    count++;
    if (positive) positiveCount++;
  }
}

class _FeatureMeanAccumulator {
  int count = 0;
  double topContributionShare = 0.0;
  double top2ContributionShare = 0.0;
  double contributionHhi = 0.0;
  double dominanceShareGap = 0.0;
  double dominanceMarginGap = 0.0;
  double marginStdDev = 0.0;
  double marginRange = 0.0;
  double meanContributionMargin = 0.0;
  double effectiveSupportCount = 0.0;

  void add(_SignalSample sample) {
    count++;
    topContributionShare += sample.topContributionShare;
    top2ContributionShare += sample.top2ContributionShare;
    contributionHhi += sample.contributionHhi;
    dominanceShareGap += sample.dominanceShareGap;
    dominanceMarginGap += sample.dominanceMarginGap;
    marginStdDev += sample.contributionMarginStdDev;
    marginRange += sample.contributionMarginRange;
    meanContributionMargin += sample.meanContributionMargin;
    effectiveSupportCount += sample.effectiveSupportCount;
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'topContributionShare': count == 0 ? 0.0 : topContributionShare / count,
    'top2ContributionShare': count == 0 ? 0.0 : top2ContributionShare / count,
    'contributionHhi': count == 0 ? 0.0 : contributionHhi / count,
    'dominanceShareGap': count == 0 ? 0.0 : dominanceShareGap / count,
    'dominanceMarginGap': count == 0 ? 0.0 : dominanceMarginGap / count,
    'marginStdDev': count == 0 ? 0.0 : marginStdDev / count,
    'marginRange': count == 0 ? 0.0 : marginRange / count,
    'meanContributionMargin': count == 0 ? 0.0 : meanContributionMargin / count,
    'effectiveSupportCount': count == 0 ? 0.0 : effectiveSupportCount / count,
  };
}

class _SignalSample {
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
  final double top2ContributionShare;
  final double contributionHhi;
  final double dominanceShareGap;
  final double dominanceMarginGap;
  final double contributionMarginStdDev;
  final double contributionMarginRange;
  final double meanContributionMargin;
  final double effectiveSupportCount;

  const _SignalSample({
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
    required this.top2ContributionShare,
    required this.contributionHhi,
    required this.dominanceShareGap,
    required this.dominanceMarginGap,
    required this.contributionMarginStdDev,
    required this.contributionMarginRange,
    required this.meanContributionMargin,
    required this.effectiveSupportCount,
  });

  bool get isMiddleTransitionZone =>
      localConsistencyLabel == 'mismatch' &&
      const ['-1.0_to_0.0', '0.0_to_1.0'].contains(actualGapBand) &&
      const ['1.0_to_2.0', '2.0_to_3.0'].contains(evidenceGapBand);

  String get localConsistencyLabel {
    if (localBelowThresholdShare10Km < 0.25) return 'consistent';
    if (localBelowThresholdShare10Km < 0.50) return 'mixed';
    return 'mismatch';
  }

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

  String supportGeometry() =>
      supportingEvidenceQuadrantCoverage >= 3 ? 'surrounded' : 'one_sided';

  String supportSpreadBand() {
    if (supportingEvidenceMaxSpreadKm < 20.0) return 'compact';
    if (supportingEvidenceMaxSpreadKm < 40.0) return 'moderate';
    return 'wide';
  }

  String geometrySpread() => '${supportGeometry()}/${supportSpreadBand()}';

  String plumMarginBand() {
    final margin = plum - thresholdValue;
    if (margin < 1.5) return '1.0_to_1.5';
    if (margin < 2.0) return '1.5_to_2.0';
    if (margin < 3.0) return '2.0_to_3.0';
    return 'gte_3.0';
  }

  String topContributionShareBand() {
    if (topContributionShare < 0.20) return 'lt_0.20';
    if (topContributionShare < 0.25) return '0.20_to_0.25';
    if (topContributionShare < 0.33) return '0.25_to_0.33';
    return 'gte_0.33';
  }

  String top2ContributionShareBand() {
    if (top2ContributionShare < 0.35) return 'lt_0.35';
    if (top2ContributionShare < 0.45) return '0.35_to_0.45';
    if (top2ContributionShare < 0.60) return '0.45_to_0.60';
    return 'gte_0.60';
  }

  String contributionHhiBand() {
    if (contributionHhi < 0.10) return 'lt_0.10';
    if (contributionHhi < 0.14) return '0.10_to_0.14';
    if (contributionHhi < 0.20) return '0.14_to_0.20';
    return 'gte_0.20';
  }

  String dominanceShareGapBand() {
    if (dominanceShareGap < 0.05) return 'lt_0.05';
    if (dominanceShareGap < 0.10) return '0.05_to_0.10';
    if (dominanceShareGap < 0.20) return '0.10_to_0.20';
    return 'gte_0.20';
  }

  String dominanceMarginGapBand() {
    if (dominanceMarginGap < 0.10) return 'lt_0.10';
    if (dominanceMarginGap < 0.20) return '0.10_to_0.20';
    if (dominanceMarginGap < 0.40) return '0.20_to_0.40';
    return 'gte_0.40';
  }

  String marginStdDevBand() {
    if (contributionMarginStdDev < 0.15) return 'lt_0.15';
    if (contributionMarginStdDev < 0.30) return '0.15_to_0.30';
    if (contributionMarginStdDev < 0.50) return '0.30_to_0.50';
    return 'gte_0.50';
  }

  String marginRangeBand() {
    if (contributionMarginRange < 0.30) return 'lt_0.30';
    if (contributionMarginRange < 0.60) return '0.30_to_0.60';
    if (contributionMarginRange < 1.00) return '0.60_to_1.00';
    return 'gte_1.00';
  }

  String meanContributionMarginBand() {
    if (meanContributionMargin < 0.25) return 'lt_0.25';
    if (meanContributionMargin < 0.40) return '0.25_to_0.40';
    if (meanContributionMargin < 0.60) return '0.40_to_0.60';
    return 'gte_0.60';
  }

  String effectiveSupportCountBand() {
    if (effectiveSupportCount < 4.0) return 'lt_4';
    if (effectiveSupportCount < 6.0) return '4_to_6';
    if (effectiveSupportCount < 8.0) return '6_to_8';
    return 'gte_8';
  }

  String bucketForFamily(String family) {
    switch (family) {
      case 'topContributionShareBand':
        return topContributionShareBand();
      case 'top2ContributionShareBand':
        return top2ContributionShareBand();
      case 'contributionHhiBand':
        return contributionHhiBand();
      case 'dominanceShareGapBand':
        return dominanceShareGapBand();
      case 'dominanceMarginGapBand':
        return dominanceMarginGapBand();
      case 'marginStdDevBand':
        return marginStdDevBand();
      case 'marginRangeBand':
        return marginRangeBand();
      case 'meanContributionMarginBand':
        return meanContributionMarginBand();
      case 'effectiveSupportCountBand':
        return effectiveSupportCountBand();
      case 'topContributionShareBand|geometrySpread':
        return '${topContributionShareBand()}|${geometrySpread()}';
      case 'contributionHhiBand|plumMarginBand':
        return '${contributionHhiBand()}|${plumMarginBand()}';
      case 'marginStdDevBand|plumMarginBand':
        return '${marginStdDevBand()}|${plumMarginBand()}';
      default:
        return 'unknown';
    }
  }
}

class _ContributionSummary {
  final double topContributionShare;
  final double top2ContributionShare;
  final double contributionHhi;
  final double dominanceShareGap;
  final double dominanceMarginGap;
  final double marginStdDev;
  final double marginRange;
  final double meanMargin;
  final double effectiveSupportCount;

  const _ContributionSummary({
    required this.topContributionShare,
    required this.top2ContributionShare,
    required this.contributionHhi,
    required this.dominanceShareGap,
    required this.dominanceMarginGap,
    required this.marginStdDev,
    required this.marginRange,
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
  'schemaVersion': 'plum_tohoku_middle_transition_runtime_signal_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM Tohoku middle-transition runtime-signal diagnostic',
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'suppressionApplied': false,
    'plumRadiusKm': _plumRadiusKm,
    'plumDampingPer10Km': _plumDampingPer10Km,
    'minimumTestSamplesForRanking': _minTestSamplesForRanking,
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
    'maximumNearestEvidenceDistanceKm': _focusMaximumNearestEvidenceDistanceKm,
    'minimumPredictionMarginShindo': _focusMinimumMargin,
    'baselineThresholdCrossingRequired': true,
  },
  'labelDefinition': const {
    'positiveLabel': 'middle_transition_zone',
    'truthInputs': [
      'actualGapBand in {-1.0_to_0.0, 0.0_to_1.0}',
      'evidenceGapBand in {1.0_to_2.0, 2.0_to_3.0}',
      'localConsistencyLabel == mismatch',
    ],
  },
  'featureDefinitions': const {},
  'coverage': {
    'validationVariants': 0,
    'testVariants': 0,
    'validationStationForecasts': 0,
    'testStationForecasts': 0,
    'skippedMissingMagnitudeEvents': 0,
    'skippedNoSourceEstimateVariants': 0,
  },
  'labelSummary': const {
    'validation': {
      'focusSampleCount': 0,
      'middleTransitionCount': 0,
      'middleTransitionRate': 0.0,
    },
    'test': {
      'focusSampleCount': 0,
      'middleTransitionCount': 0,
      'middleTransitionRate': 0.0,
    },
  },
  'testOutcomeFeatureMeans': const {},
  'featureFamilies': const {},
  'rankedCandidates': const [],
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

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(double value) {
  final percent = value * 100;
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}pp';
}

String _fmtMultiplier(double value) => '${value.toStringAsFixed(2)}x';

String _fmt(Object? value) => _number(value).toStringAsFixed(3);
