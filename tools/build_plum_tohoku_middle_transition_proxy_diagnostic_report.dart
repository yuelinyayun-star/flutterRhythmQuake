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
    '.dart_tool/plum_tohoku_middle_transition_proxy_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_middle_transition_proxy_diagnostic.generated.md';

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
  'branchAgreement',
  'robustnessScore',
  'supportGeometry',
  'supportSpreadBand',
  'geometrySpread',
  'quadrantCoverageBand',
  'plumMarginBand',
  'evidenceCountBand',
  'centroidOffsetBand',
  'branchAgreement|geometrySpread',
  'robustnessScore|geometrySpread',
  'plumMarginBand|geometrySpread',
];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuMiddleTransitionProxyDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMiddleTransitionProxyDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku middle-transition proxy diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuMiddleTransitionProxyDiagnosticJson({
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
          final sample = _buildProxySample(
            event: event,
            variant: variant,
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
    'schemaVersion': 'plum_tohoku_middle_transition_proxy_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku middle-transition proxy diagnostic',
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
          'candidate proxy features must not use target actual intensity or evidence-target gap as input',
    },
    'featureDefinitions': const {
      'branchAgreement':
          'threshold-crossing agreement count across JMA-style, PLUM r20/d0.50, and PLUM r30/d0.75',
      'robustnessScore':
          'production-available evidence robustness score reused from prior diagnostics',
      'supportGeometry': 'one_sided if quadrants < 3 else surrounded',
      'supportSpreadBand': 'compact <20 km, moderate 20-40 km, wide >=40 km',
      'quadrantCoverageBand': 'q1, q2, q3_plus based on supporting evidence',
      'plumMarginBand':
          'PLUM minus threshold bucket using runtime prediction only',
      'evidenceCountBand': '8_9, 10_12, 13_15, gte_16',
      'centroidOffsetBand':
          'support centroid offset bucket in km using observed supporting evidence only',
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
  final keys = {
    ...validationBuckets.keys,
    ...testBuckets.keys,
  }.toList()
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
    'validationShare': validationTotal == 0 ? 0.0 : validationCount / validationTotal,
    'validationPositiveCount': validationPositiveCount,
    'validationPositiveRate': validationRate,
    'testCount': testCount,
    'testShare': testTotal == 0 ? 0.0 : testCount / testTotal,
    'testPositiveCount': testPositiveCount,
    'testPositiveRate': testRate,
    'testPositiveCaptureShare': testCaptureShare,
    'sampleShareDelta': (testTotal == 0 ? 0.0 : testCount / testTotal) -
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
    final scoreCmp =
        _number(right['proxyScore']).compareTo(_number(left['proxyScore']));
    if (scoreCmp != 0) return scoreCmp;
    final rateCmp = _number(right['testPositiveRate'])
        .compareTo(_number(left['testPositiveRate']));
    if (rateCmp != 0) return rateCmp;
    return _int(right['testPositiveCount']).compareTo(_int(left['testPositiveCount']));
  });
  return rows.take(15).toList();
}

_ProxySample _buildProxySample({
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
    _localNeighbor10Km,
  );
  final supportShape = _supportShape(
    targetStation: targetStation,
    evidenceStations: supportingEvidence,
  );
  return _ProxySample(
    variantId: variant.variantId,
    stationId: targetStation.stationId,
    thresholdValue: threshold.value,
    actual: targetStation.intensity,
    jma: jmaPredictedIntensity,
    plum: plum.intensity,
    r20: r20,
    r30D075: r30D075,
    evidenceCount: plum.evidenceCount,
    nearestEvidenceDistanceKm: plum.nearestEvidenceDistanceKm,
    strongestEvidenceIntensity: strongestEvidence?.station.intensity,
    strongestEvidencePropagatedIntensity: strongestEvidence?.propagatedIntensity,
    evidenceTargetGap: strongestEvidence == null
        ? double.nan
        : strongestEvidence.station.intensity - targetStation.intensity,
    localBelowThresholdShare10Km: local10.belowThresholdShare,
    supportingEvidenceCount: supportingEvidence.length,
    supportingEvidenceQuadrantCoverage: supportShape.quadrantCoverage,
    supportingEvidenceCentroidOffsetKm: supportShape.centroidOffsetKm,
    supportingEvidenceMeanDistanceKm: supportShape.meanDistanceKm,
    supportingEvidenceMaxSpreadKm: supportShape.maxSpreadKm,
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
      meanDistanceKm: 0,
      maxSpreadKm: 0,
    );
  }
  final quadrants = <int>{};
  var sumLat = 0.0;
  var sumLng = 0.0;
  var sumDist = 0.0;
  for (final evidence in evidenceStations) {
    sumLat += evidence.station.latitude;
    sumLng += evidence.station.longitude;
    sumDist += evidence.targetDistanceKm;
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
    meanDistanceKm: sumDist / evidenceStations.length,
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

String plumTohokuMiddleTransitionProxyDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final labelSummary = _map(report['labelSummary']);
  final featureFamilies = _map(report['featureFamilies']);
  final rankedCandidates = _list(report['rankedCandidates']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Middle-Transition Proxy Diagnostic')
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
    ..writeln('| Split | Variants | Station forecasts | Focus samples | Middle-transition samples | Rate |')
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
    ..writeln('## Ranked Proxy Candidates')
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
      '- This report remains diagnostic-only. It uses truth-defined labels only '
      'to score proxy candidates; the candidate features themselves are limited '
      'to production-available evidence and support-shape signals.',
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
  final samples = <_ProxySample>[];

  void add(_ProxySample sample) => samples.add(sample);

  _LabelSummary get summary {
    final middle = samples.where((sample) => sample.isMiddleTransitionZone).length;
    return _LabelSummary(
      focusSampleCount: samples.length,
      middleTransitionCount: middle,
    );
  }

  Map<String, _BucketStats> bucketsForFamily(String family) {
    final buckets = <String, _BucketStats>{};
    for (final sample in samples) {
      final key = sample.bucketForFamily(family);
      buckets.putIfAbsent(key, _BucketStats.new).add(sample.isMiddleTransitionZone);
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

  double get middleTransitionRate => focusSampleCount == 0
      ? 0.0
      : middleTransitionCount / focusSampleCount;

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

class _ProxySample {
  final String variantId;
  final String stationId;
  final double thresholdValue;
  final double actual;
  final double jma;
  final double plum;
  final double r20;
  final double r30D075;
  final int evidenceCount;
  final double nearestEvidenceDistanceKm;
  final double? strongestEvidenceIntensity;
  final double? strongestEvidencePropagatedIntensity;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final int supportingEvidenceCount;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceCentroidOffsetKm;
  final double supportingEvidenceMeanDistanceKm;
  final double supportingEvidenceMaxSpreadKm;

  const _ProxySample({
    required this.variantId,
    required this.stationId,
    required this.thresholdValue,
    required this.actual,
    required this.jma,
    required this.plum,
    required this.r20,
    required this.r30D075,
    required this.evidenceCount,
    required this.nearestEvidenceDistanceKm,
    required this.strongestEvidenceIntensity,
    required this.strongestEvidencePropagatedIntensity,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.supportingEvidenceCount,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceCentroidOffsetKm,
    required this.supportingEvidenceMeanDistanceKm,
    required this.supportingEvidenceMaxSpreadKm,
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

  String branchAgreement() {
    final agree = [
      jma >= thresholdValue,
      r20 >= thresholdValue,
      r30D075 >= thresholdValue,
    ].where((value) => value).length;
    return 'agree_$agree';
  }

  String robustnessScore() {
    var score = 0;
    if (evidenceCount >= 4) score++;
    if (nearestEvidenceDistanceKm <= 20.0) score++;
    if (jma >= thresholdValue) score++;
    if (r20 >= thresholdValue) score++;
    if (r30D075 >= thresholdValue) score++;
    if ((plum - thresholdValue) >= 0.5) score++;
    if ((plum - thresholdValue) >= 1.0) score++;
    return 'score_$score';
  }

  String supportGeometry() =>
      supportingEvidenceQuadrantCoverage >= 3 ? 'surrounded' : 'one_sided';

  String supportSpreadBand() {
    if (supportingEvidenceMaxSpreadKm < 20.0) return 'compact';
    if (supportingEvidenceMaxSpreadKm < 40.0) return 'moderate';
    return 'wide';
  }

  String geometrySpread() => '${supportGeometry()}/${supportSpreadBand()}';

  String quadrantCoverageBand() {
    if (supportingEvidenceQuadrantCoverage <= 1) return 'q1';
    if (supportingEvidenceQuadrantCoverage == 2) return 'q2';
    return 'q3_plus';
  }

  String plumMarginBand() {
    final margin = plum - thresholdValue;
    if (margin < 1.5) return '1.0_to_1.5';
    if (margin < 2.0) return '1.5_to_2.0';
    if (margin < 3.0) return '2.0_to_3.0';
    return 'gte_3.0';
  }

  String evidenceCountBand() {
    if (evidenceCount <= 9) return '8_9';
    if (evidenceCount <= 12) return '10_12';
    if (evidenceCount <= 15) return '13_15';
    return 'gte_16';
  }

  String centroidOffsetBand() {
    if (supportingEvidenceCentroidOffsetKm < 8.0) return 'lt_8';
    if (supportingEvidenceCentroidOffsetKm < 12.0) return '8_to_12';
    return 'gte_12';
  }

  String bucketForFamily(String family) {
    switch (family) {
      case 'branchAgreement':
        return branchAgreement();
      case 'robustnessScore':
        return robustnessScore();
      case 'supportGeometry':
        return supportGeometry();
      case 'supportSpreadBand':
        return supportSpreadBand();
      case 'geometrySpread':
        return geometrySpread();
      case 'quadrantCoverageBand':
        return quadrantCoverageBand();
      case 'plumMarginBand':
        return plumMarginBand();
      case 'evidenceCountBand':
        return evidenceCountBand();
      case 'centroidOffsetBand':
        return centroidOffsetBand();
      case 'branchAgreement|geometrySpread':
        return '${branchAgreement()}|${geometrySpread()}';
      case 'robustnessScore|geometrySpread':
        return '${robustnessScore()}|${geometrySpread()}';
      case 'plumMarginBand|geometrySpread':
        return '${plumMarginBand()}|${geometrySpread()}';
      default:
        return 'unknown';
    }
  }
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
  final double meanDistanceKm;
  final double maxSpreadKm;

  const _SupportShape({
    required this.quadrantCoverage,
    required this.centroidOffsetKm,
    required this.meanDistanceKm,
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
        'schemaVersion': 'plum_tohoku_middle_transition_proxy_diagnostic_v1',
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'status': 'fail',
        'policy': {
          'method': 'PLUM Tohoku middle-transition proxy diagnostic',
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
