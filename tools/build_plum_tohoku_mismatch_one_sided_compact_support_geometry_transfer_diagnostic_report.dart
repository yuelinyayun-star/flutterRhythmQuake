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
    '.dart_tool/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusFamily = 'mismatch/one_sided/compact';
const _minimumEventSliceSamples = 4;
const _threshold = _Threshold('shindo4', 3.5);

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report =
      buildPlumTohokuMismatchOneSidedCompactSupportGeometryTransferDiagnosticJson(
        dataDirectory: dataDirectory,
        modelPath: modelPath,
      );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMismatchOneSidedCompactSupportGeometryTransferDiagnosticMarkdown(
      report,
    ),
  );

  stdout.writeln(
    'wrote PLUM Tohoku mismatch/one_sided/compact support-geometry transfer diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?>
buildPlumTohokuMismatchOneSidedCompactSupportGeometryTransferDiagnosticJson({
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

  final validationTargetModes = [
    for (final sample in validationSamples)
      if (sample.eventFamilyLabel == _focusFamily &&
          (sample.isNearThresholdPositiveMode ||
              sample.isFalseMiddleTransitionMode))
        sample,
  ];
  final remainderTargetModes = [
    for (final sample in testSamples)
      if (sample.eventId != dominantEventId &&
          sample.eventFamilyLabel == _focusFamily &&
          (sample.isNearThresholdPositiveMode ||
              sample.isFalseMiddleTransitionMode))
        sample,
  ];
  final anchors = _ScoreAnchors.fromScores(
    validationTargetModes.map((sample) => sample.supportGeometryScore).toList(),
  );

  final slices = <Map<String, Object?>>[
    _buildSliceReport(
      sliceId: 'all_remainder',
      label: 'all remainder target modes',
      samples: remainderTargetModes,
      anchors: anchors,
    ),
  ];

  final byEvent = <String, List<_ScoreSample>>{};
  for (final sample in remainderTargetModes) {
    byEvent.putIfAbsent(sample.eventId, () => []).add(sample);
  }
  final eventEntries = byEvent.entries.toList()
    ..sort((left, right) {
      final byCount = right.value.length.compareTo(left.value.length);
      if (byCount != 0) return byCount;
      return left.key.compareTo(right.key);
    });
  for (final entry in eventEntries) {
    if (entry.value.length < _minimumEventSliceSamples) continue;
    slices.add(
      _buildSliceReport(
        sliceId: entry.key,
        label: 'event',
        samples: entry.value,
        anchors: anchors,
      ),
    );
  }

  return {
    'schemaVersion':
        'plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method':
          'PLUM Tohoku mismatch/one_sided/compact support-geometry transfer diagnostic',
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
      'family': _focusFamily,
      'scoreVariant': 'supportGeometry-only',
    },
    'scope': {
      'removedDominantEvent': dominantEventId,
      'estimatedSourceRegion': _focusRegion,
      'minimumEvidenceCount': _focusMinimumEvidenceCount,
      'maximumNearestEvidenceDistanceKm':
          _focusMaximumNearestEvidenceDistanceKm,
      'baselineThresholdCrossingRequired': true,
      'minimumEventSliceSamples': _minimumEventSliceSamples,
    },
    'labelDefinition': const {
      'positiveLabel': 'near_threshold_positive',
      'negativeLabel': 'false_middle_transition',
      'truthInputs': [
        'family mismatch/one_sided/compact only',
        'near_threshold_positive := actualGapBand=0.0_to_1.0 and evidenceGapBand=lt_1.0',
        'false_middle_transition := actualGapBand=-1.0_to_0.0 and evidenceGapBand=1.0_to_2.0',
      ],
      'productionFeatureBoundary':
          'score uses only runtime-visible support geometry: local mismatch, quadrant coverage, and centroid offset',
    },
    'scoreDefinition': {
      'weights': const {'supportGeometry': 1.0},
      'components': {
        'supportGeometry':
            'mean(inverse(local mismatch, desirable <= 0.60, weak >= 0.85), direct(quadrants, weak <= 1, desirable >= 2), inverse(centroid offset, desirable <= 5 km, weak >= 10 km))',
      },
      'validationAnchors': anchors.toJson(),
    },
    'coverage': {
      'validationTargetModeCount': validationTargetModes.length,
      'validationNearThresholdPositiveCount': validationTargetModes
          .where((sample) => sample.isNearThresholdPositiveMode)
          .length,
      'validationFalseMiddleTransitionCount': validationTargetModes
          .where((sample) => sample.isFalseMiddleTransitionMode)
          .length,
      'remainderTargetModeCount': remainderTargetModes.length,
      'remainderNearThresholdPositiveCount': remainderTargetModes
          .where((sample) => sample.isNearThresholdPositiveMode)
          .length,
      'remainderFalseMiddleTransitionCount': remainderTargetModes
          .where((sample) => sample.isFalseMiddleTransitionMode)
          .length,
      'evaluatedSliceCount': slices.length,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'validationModeMeans': {
      'nearThresholdPositive': _mean(
        validationTargetModes
            .where((sample) => sample.isNearThresholdPositiveMode)
            .map((sample) => sample.supportGeometryScore),
      ),
      'falseMiddleTransition': _mean(
        validationTargetModes
            .where((sample) => sample.isFalseMiddleTransitionMode)
            .map((sample) => sample.supportGeometryScore),
      ),
    },
    'sliceReports': slices,
    'errors': errors,
  };
}

Map<String, Object?> _buildSliceReport({
  required String sliceId,
  required String label,
  required List<_ScoreSample> samples,
  required _ScoreAnchors anchors,
}) {
  final nearCount = samples
      .where((sample) => sample.isNearThresholdPositiveMode)
      .length;
  final falseCount = samples
      .where((sample) => sample.isFalseMiddleTransitionMode)
      .length;
  final meanNear = _mean(
    samples
        .where((sample) => sample.isNearThresholdPositiveMode)
        .map((sample) => sample.supportGeometryScore),
  );
  final meanFalse = _mean(
    samples
        .where((sample) => sample.isFalseMiddleTransitionMode)
        .map((sample) => sample.supportGeometryScore),
  );
  final bandRows = _buildBandRows(samples, anchors);
  final quartiles = _buildQuartiles(samples);
  final monotonicity = _buildMonotonicity(quartiles);
  return {
    'sliceId': sliceId,
    'label': label,
    'count': samples.length,
    'nearCount': nearCount,
    'falseCount': falseCount,
    'nearRate': samples.isEmpty ? 0.0 : nearCount / samples.length,
    'falseRate': samples.isEmpty ? 0.0 : falseCount / samples.length,
    'meanNearScore': meanNear,
    'meanFalseScore': meanFalse,
    'meanGap': meanNear - meanFalse,
    'stabilityLabel': _stabilityLabel(
      sampleCount: samples.length,
      monotonicity: monotonicity,
      bandRows: bandRows,
    ),
    'validationAnchoredBandTransfer': bandRows,
    'quartiles': quartiles,
    'monotonicity': monotonicity,
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

List<Map<String, Object?>> _buildBandRows(
  List<_ScoreSample> samples,
  _ScoreAnchors anchors,
) {
  final rows = {
    'low': _BandAccumulator(),
    'mid_low': _BandAccumulator(),
    'mid_high': _BandAccumulator(),
    'high': _BandAccumulator(),
  };
  for (final sample in samples) {
    rows[anchors.bandFor(sample.supportGeometryScore)]!.add(sample);
  }
  final total = samples.length;
  final positiveTotal = samples
      .where((sample) => sample.isNearThresholdPositiveMode)
      .length;
  final negativeTotal = samples
      .where((sample) => sample.isFalseMiddleTransitionMode)
      .length;
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

List<Map<String, Object?>> _buildQuartiles(List<_ScoreSample> samples) {
  if (samples.isEmpty) return const [];
  final sorted = [...samples]
    ..sort(
      (left, right) =>
          left.supportGeometryScore.compareTo(right.supportGeometryScore),
    );
  final rows = <Map<String, Object?>>[];
  final positiveTotal = samples
      .where((sample) => sample.isNearThresholdPositiveMode)
      .length;
  final negativeTotal = samples
      .where((sample) => sample.isFalseMiddleTransitionMode)
      .length;
  for (var quartile = 0; quartile < 4; quartile++) {
    final start = (sorted.length * quartile / 4).floor();
    final end = (sorted.length * (quartile + 1) / 4).floor();
    final bucket = sorted.sublist(start, end);
    final positive = bucket
        .where((sample) => sample.isNearThresholdPositiveMode)
        .length;
    final negative = bucket
        .where((sample) => sample.isFalseMiddleTransitionMode)
        .length;
    rows.add({
      'quartile': quartile + 1,
      'scoreMin': bucket.isEmpty ? 0.0 : bucket.first.supportGeometryScore,
      'scoreMax': bucket.isEmpty ? 0.0 : bucket.last.supportGeometryScore,
      'count': bucket.length,
      'positiveCount': positive,
      'negativeCount': negative,
      'positiveRate': bucket.isEmpty ? 0.0 : positive / bucket.length,
      'negativeRate': bucket.isEmpty ? 0.0 : negative / bucket.length,
      'positiveCaptureShare': positiveTotal == 0
          ? 0.0
          : positive / positiveTotal,
      'negativeCaptureShare': negativeTotal == 0
          ? 0.0
          : negative / negativeTotal,
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
    final prev = quartiles[i - 1];
    final next = quartiles[i];
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
  final low = quartiles.isEmpty ? const <String, Object?>{} : quartiles.first;
  final high = quartiles.isEmpty ? const <String, Object?>{} : quartiles.last;
  final lowPositive = _number(low['positiveRate']);
  final highPositive = _number(high['positiveRate']);
  final lowNegative = _number(low['negativeRate']);
  final highNegative = _number(high['negativeRate']);
  return {
    'highQuartilePositiveRate': highPositive,
    'lowQuartilePositiveRate': lowPositive,
    'highToLowPositiveLift': lowPositive == 0
        ? 0.0
        : highPositive / lowPositive,
    'lowQuartileNegativeRate': lowNegative,
    'highQuartileNegativeRate': highNegative,
    'highToLowFalseRatio': lowNegative == 0 ? 0.0 : highNegative / lowNegative,
    'positiveNonDecreasingAdjacentPairs': positiveNonDecreasing,
    'positiveDecreasingAdjacentPairs': positiveDecreasing,
    'negativeNonIncreasingAdjacentPairs': negativeNonIncreasing,
    'negativeIncreasingAdjacentPairs': negativeIncreasing,
  };
}

_ScoreSample _buildSample({
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
  return _ScoreSample(
    eventId: event.eventId,
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
    supportingEvidenceCentroidOffsetKm: supportShape.centroidOffsetKm,
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
    return const _SupportShape(quadrantCoverage: 0, centroidOffsetKm: 0.0);
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
  return _SupportShape(
    quadrantCoverage: quadrants.length,
    centroidOffsetKm: QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      centroidLat,
      centroidLng,
    ),
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

String
plumTohokuMismatchOneSidedCompactSupportGeometryTransferDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final scoreDefinition = _map(report['scoreDefinition']);
  final anchors = _map(scoreDefinition['validationAnchors']);
  final validationMeans = _map(report['validationModeMeans']);
  final slices = _list(report['sliceReports']);
  final buffer = StringBuffer()
    ..writeln(
      '# PLUM Tohoku mismatch/one_sided/compact Support-Geometry Transfer Diagnostic',
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
      '- Raw predicted intensity mutated: `${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln()
    ..writeln('## Coverage')
    ..writeln()
    ..writeln('| Slice | Count |')
    ..writeln('| --- | ---: |')
    ..writeln(
      '| `validation target modes` | ${coverage['validationTargetModeCount']} |',
    )
    ..writeln(
      '| `remainder target modes` | ${coverage['remainderTargetModeCount']} |',
    )
    ..writeln('| `evaluated slices` | ${coverage['evaluatedSliceCount']} |')
    ..writeln()
    ..writeln('## Score Definition')
    ..writeln()
    ..writeln(
      '- Validation anchors: q25 `${_fmt(anchors['q25'])}`, q50 `${_fmt(anchors['q50'])}`, q75 `${_fmt(anchors['q75'])}`.',
    )
    ..writeln(
      '- Validation near-threshold mean: `${_fmt(validationMeans['nearThresholdPositive'])}`; false-middle-transition mean: `${_fmt(validationMeans['falseMiddleTransition'])}`.',
    )
    ..writeln()
    ..writeln('## Slice Summary')
    ..writeln()
    ..writeln(
      '| Slice | Label | Samples | Near | False | Mean Gap | Stability | Low False Capture | Low Near Capture | High Near Rate | High False Rate | High/Low Near Lift | High/Low False Ratio |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final raw in slices) {
    final row = _map(raw);
    final bandRows = _list(row['validationAnchoredBandTransfer']);
    final lowBand = _map(
      bandRows.firstWhere(
        (entry) => _map(entry)['band'] == 'low',
        orElse: () => const <String, Object?>{},
      ),
    );
    final highBand = _map(
      bandRows.firstWhere(
        (entry) => _map(entry)['band'] == 'high',
        orElse: () => const <String, Object?>{},
      ),
    );
    final monotonicity = _map(row['monotonicity']);
    buffer.writeln(
      '| `${row['sliceId']}` | `${row['label']}` | ${row['count']} | ${row['nearCount']} | ${row['falseCount']} | ${_fmt(row['meanGap'])} | `${row['stabilityLabel']}` | ${_pct(lowBand['negativeCaptureShare'])} | ${_pct(lowBand['positiveCaptureShare'])} | ${_pct(highBand['positiveRate'])} | ${_pct(highBand['negativeRate'])} | ${_fmtMultiplier(_number(monotonicity['highToLowPositiveLift']))} | ${_fmtMultiplier(_number(monotonicity['highToLowFalseRatio']))} |',
    );
  }

  for (final raw in slices) {
    final row = _map(raw);
    final bandRows = _list(row['validationAnchoredBandTransfer']);
    final quartiles = _list(row['quartiles']);
    final monotonicity = _map(row['monotonicity']);
    buffer
      ..writeln()
      ..writeln('## `${row['sliceId']}`')
      ..writeln()
      ..writeln(
        '- Label: `${row['label']}`; stability: `${row['stabilityLabel']}`.',
      )
      ..writeln(
        '- Near count `${row['nearCount']}`, false count `${row['falseCount']}`, mean gap `${_fmt(row['meanGap'])}`.',
      )
      ..writeln()
      ..writeln('### Validation-Anchored Band Transfer')
      ..writeln()
      ..writeln(
        '| Band | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final bandRaw in bandRows) {
      final band = _map(bandRaw);
      buffer.writeln(
        '| `${band['band']}` | ${band['count']} | ${band['positiveCount']} | ${band['negativeCount']} | ${_pct(band['positiveRate'])} | ${_pct(band['negativeRate'])} | ${_pct(band['positiveCaptureShare'])} | ${_pct(band['negativeCaptureShare'])} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Quartiles')
      ..writeln()
      ..writeln(
        '| Quartile | Score Min | Score Max | Count | Near | False | Near Rate | False Rate | Near Capture | False Capture |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final quartileRaw in quartiles) {
      final quartile = _map(quartileRaw);
      buffer.writeln(
        '| ${quartile['quartile']} | ${_fmt(quartile['scoreMin'])} | ${_fmt(quartile['scoreMax'])} | ${quartile['count']} | ${quartile['positiveCount']} | ${quartile['negativeCount']} | ${_pct(quartile['positiveRate'])} | ${_pct(quartile['negativeRate'])} | ${_pct(quartile['positiveCaptureShare'])} | ${_pct(quartile['negativeCaptureShare'])} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Monotonicity')
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
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report remains diagnostic-only. It checks whether the family-local `supportGeometry-only` score keeps its ranking behavior across additional event slices rather than only on the pooled remainder.',
    )
    ..writeln(
      '- It does not tune PLUM, suppress predictions, or authorize production UI/wording/notification changes.',
    );
  return buffer.toString();
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final samples = <_ScoreSample>[];

  void add(_ScoreSample sample) => samples.add(sample);
}

class _BandAccumulator {
  int count = 0;
  int positiveCount = 0;
  int negativeCount = 0;

  void add(_ScoreSample sample) {
    count++;
    if (sample.isNearThresholdPositiveMode) positiveCount++;
    if (sample.isFalseMiddleTransitionMode) negativeCount++;
  }

  Map<String, Object?> toJson({
    required String band,
    required int total,
    required int positiveTotal,
    required int negativeTotal,
  }) {
    final share = total == 0 ? 0.0 : count / total;
    final positiveRate = count == 0 ? 0.0 : positiveCount / count;
    final negativeRate = count == 0 ? 0.0 : negativeCount / count;
    return {
      'band': band,
      'count': count,
      'share': share,
      'positiveCount': positiveCount,
      'negativeCount': negativeCount,
      'positiveRate': positiveRate,
      'negativeRate': negativeRate,
      'positiveCaptureShare': positiveTotal == 0
          ? 0.0
          : positiveCount / positiveTotal,
      'negativeCaptureShare': negativeTotal == 0
          ? 0.0
          : negativeCount / negativeTotal,
    };
  }
}

class _ScoreSample {
  final String eventId;
  final double thresholdValue;
  final double actual;
  final double jma;
  final double plum;
  final double r20;
  final double r30D075;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceCentroidOffsetKm;

  const _ScoreSample({
    required this.eventId,
    required this.thresholdValue,
    required this.actual,
    required this.jma,
    required this.plum,
    required this.r20,
    required this.r30D075,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceCentroidOffsetKm,
  });

  bool get actualPositive => actual >= thresholdValue;

  String get localConsistencyLabel {
    if (localBelowThresholdShare10Km < 0.25) return 'consistent';
    if (localBelowThresholdShare10Km < 0.50) return 'mixed';
    return 'mismatch';
  }

  String get geometryBand =>
      supportingEvidenceQuadrantCoverage >= 3 ? 'surrounded' : 'one_sided';

  String get spreadBand =>
      supportingEvidenceQuadrantCoverage < 3 ? 'compact' : 'unknown';

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

  const _SupportShape({
    required this.quadrantCoverage,
    required this.centroidOffsetKm,
  });
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
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

  Map<String, Object?> toJson() => {'q25': q25, 'q50': q50, 'q75': q75};
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
  'schemaVersion':
      'plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method':
        'PLUM Tohoku mismatch/one_sided/compact support-geometry transfer diagnostic',
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
    'family': _focusFamily,
    'scoreVariant': 'supportGeometry-only',
  },
  'scope': {
    'removedDominantEvent': 'none',
    'estimatedSourceRegion': _focusRegion,
    'minimumEvidenceCount': _focusMinimumEvidenceCount,
    'maximumNearestEvidenceDistanceKm': _focusMaximumNearestEvidenceDistanceKm,
    'baselineThresholdCrossingRequired': true,
    'minimumEventSliceSamples': _minimumEventSliceSamples,
  },
  'labelDefinition': const {},
  'scoreDefinition': const {
    'weights': {'supportGeometry': 1.0},
    'components': {},
    'validationAnchors': {'q25': 0.0, 'q50': 0.0, 'q75': 0.0},
  },
  'coverage': const {},
  'validationModeMeans': const {
    'nearThresholdPositive': 0.0,
    'falseMiddleTransition': 0.0,
  },
  'sliceReports': const [],
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

String _dominantEventId(List<_ScoreSample> samples) {
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

double _inverseLinear(
  double value, {
  required double desirableCeiling,
  required double weakFloor,
}) {
  if (value <= desirableCeiling) return 1.0;
  if (value >= weakFloor) return 0.0;
  return (weakFloor - value) / (weakFloor - desirableCeiling);
}

double _directLinear(
  double value, {
  required double weakFloor,
  required double desirableCeiling,
}) {
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
  final fraction = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
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

double _mean(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return 0.0;
  return list.fold<double>(0.0, (sum, value) => sum + value) / list.length;
}

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _fmt(Object? value) => _number(value).toStringAsFixed(3);

String _fmtMultiplier(double value) => '${value.toStringAsFixed(2)}x';
