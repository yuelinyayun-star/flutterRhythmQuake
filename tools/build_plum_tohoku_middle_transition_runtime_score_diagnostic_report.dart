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
    '.dart_tool/plum_tohoku_middle_transition_runtime_score_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_middle_transition_runtime_score_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusMinimumMargin = 1.0;
const _localNeighbor10Km = 10.0;
const _threshold = _Threshold('shindo4', 3.5);
const _scoreWeights = {
  'concentration': 0.40,
  'spreadVariance': 0.35,
  'plumMargin': 0.25,
};

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuMiddleTransitionRuntimeScoreDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMiddleTransitionRuntimeScoreDiagnosticMarkdown(report),
  );

  stdout.writeln(
    'wrote PLUM Tohoku middle-transition runtime-score diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuMiddleTransitionRuntimeScoreDiagnosticJson({
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
          final sample = _buildScoreSample(
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
  final validationAnchors = _ScoreAnchors.fromScores(
    validation.samples.map((sample) => sample.runtimeScore).toList(),
  );

  return {
    'schemaVersion':
        'plum_tohoku_middle_transition_runtime_score_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku middle-transition runtime-score diagnostic',
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
      'minimumPredictionMarginShindo': _focusMinimumMargin,
      'baselineThresholdCrossingRequired': true,
    },
    'scoreDefinition': {
      'weights': _scoreWeights,
      'components': {
        'concentration':
            '0.5 * inverse(topContributionShare, desirable <= 0.20, weak >= 0.33) + 0.5 * inverse(HHI, desirable <= 0.10, weak >= 0.20)',
        'spreadVariance':
            'triangular(stddev of propagated excess, center 0.40, half-width 0.20)',
        'plumMargin':
            'triangular(PLUM-threshold margin, center 1.25, half-width 0.75)',
      },
      'scoreRange': [0.0, 1.0],
      'validationAnchoredBands': {
        'low': '<= q25',
        'mid_low': '(q25, q50]',
        'mid_high': '(q50, q75]',
        'high': '> q75',
      },
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
          'score components must use only runtime-visible support concentration, spread variance, and PLUM margin',
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
    'scoreAnchors': validationAnchors.toJson(),
    'testOutcomeScoreMeans': _buildOutcomeScoreMeans(test),
    'validationAnchoredBandTransfer': {
      'validation': _buildBandRows(
        validation,
        validationAnchors,
        includeLabels: false,
      ),
      'test': _buildBandRows(test, validationAnchors, includeLabels: true),
    },
    'testDeciles': _buildTestDeciles(test),
    'monotonicitySummary': _buildMonotonicitySummary(test),
    'errors': errors,
  };
}

List<Map<String, Object?>> _buildBandRows(
  _SplitAccumulator split,
  _ScoreAnchors anchors, {
  required bool includeLabels,
}) {
  final rows = {
    'low': _BandAccumulator(),
    'mid_low': _BandAccumulator(),
    'mid_high': _BandAccumulator(),
    'high': _BandAccumulator(),
  };
  for (final sample in split.samples) {
    rows[anchors.bandFor(sample.runtimeScore)]!.add(sample);
  }
  final total = split.summary.focusSampleCount;
  final positiveTotal = split.summary.middleTransitionCount;
  return [
    for (final band in const ['low', 'mid_low', 'mid_high', 'high'])
      rows[band]!.toJson(
        band: band,
        total: total,
        positiveTotal: positiveTotal,
        includeLabels: includeLabels,
      ),
  ];
}

List<Map<String, Object?>> _buildTestDeciles(_SplitAccumulator test) {
  if (test.samples.isEmpty) return const [];
  final sorted = [...test.samples]
    ..sort((left, right) => left.runtimeScore.compareTo(right.runtimeScore));
  final rows = <Map<String, Object?>>[];
  final positiveTotal = test.summary.middleTransitionCount;
  for (var decile = 0; decile < 10; decile++) {
    final start = (sorted.length * decile / 10).floor();
    final end = (sorted.length * (decile + 1) / 10).floor();
    final bucket = sorted.sublist(start, end);
    final positive = bucket
        .where((sample) => sample.isMiddleTransitionZone)
        .length;
    rows.add({
      'decile': decile + 1,
      'scoreMin': bucket.first.runtimeScore,
      'scoreMax': bucket.last.runtimeScore,
      'count': bucket.length,
      'positiveCount': positive,
      'positiveRate': bucket.isEmpty ? 0.0 : positive / bucket.length,
      'captureShare': positiveTotal == 0 ? 0.0 : positive / positiveTotal,
    });
  }
  return rows;
}

Map<String, Object?> _buildMonotonicitySummary(_SplitAccumulator test) {
  final deciles = _buildTestDeciles(test);
  var nonDecreasingPairs = 0;
  var decreasingPairs = 0;
  for (var i = 1; i < deciles.length; i++) {
    final prev = _number(_map(deciles[i - 1])['positiveRate']);
    final next = _number(_map(deciles[i])['positiveRate']);
    if (next >= prev) {
      nonDecreasingPairs++;
    } else {
      decreasingPairs++;
    }
  }
  final top = deciles.isEmpty ? const {} : _map(deciles.last);
  final bottom = deciles.isEmpty ? const {} : _map(deciles.first);
  final topRate = _number(top['positiveRate']);
  final bottomRate = _number(bottom['positiveRate']);
  return {
    'topDecileRate': topRate,
    'bottomDecileRate': bottomRate,
    'topToBottomLift': bottomRate == 0 ? 0.0 : topRate / bottomRate,
    'nonDecreasingAdjacentPairs': nonDecreasingPairs,
    'decreasingAdjacentPairs': decreasingPairs,
  };
}

Map<String, Object?> _buildOutcomeScoreMeans(_SplitAccumulator split) {
  final positive = _ScoreMeanAccumulator();
  final negative = _ScoreMeanAccumulator();
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

_ScoreSample _buildScoreSample({
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
  final contribution = _supportContributionSummary(
    threshold: threshold.value,
    evidenceStations: supportingEvidence,
  );
  return _ScoreSample(
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
    topContributionShare: contribution.topContributionShare,
    contributionHhi: contribution.contributionHhi,
    contributionMarginStdDev: contribution.marginStdDev,
  );
}

_ContributionSummary _supportContributionSummary({
  required double threshold,
  required List<_EvidenceStation> evidenceStations,
}) {
  if (evidenceStations.isEmpty) {
    return const _ContributionSummary(
      topContributionShare: 0.0,
      contributionHhi: 0.0,
      marginStdDev: 0.0,
    );
  }
  final margins = [
    for (final evidence in evidenceStations)
      math.max(0.0, evidence.propagatedIntensity - threshold),
  ];
  final sorted = [...margins]..sort((left, right) => right.compareTo(left));
  final total = margins.fold<double>(0.0, (sum, value) => sum + value);
  final mean = total / margins.length;
  final variance =
      margins.fold<double>(
        0.0,
        (sum, margin) => sum + math.pow(margin - mean, 2).toDouble(),
      ) /
      margins.length;
  final topContributionShare = total <= 0 ? 0.0 : sorted.first / total;
  final contributionHhi = total <= 0
      ? 0.0
      : sorted
            .map((margin) => margin / total)
            .fold<double>(0.0, (sum, share) => sum + share * share);
  return _ContributionSummary(
    topContributionShare: topContributionShare,
    contributionHhi: contributionHhi,
    marginStdDev: math.sqrt(variance),
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

String plumTohokuMiddleTransitionRuntimeScoreDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final scoreDefinition = _map(report['scoreDefinition']);
  final labelSummary = _map(report['labelSummary']);
  final anchors = _map(report['scoreAnchors']);
  final outcomeMeans = _map(report['testOutcomeScoreMeans']);
  final transfer = _map(report['validationAnchoredBandTransfer']);
  final validationBands = _list(transfer['validation']);
  final testBands = _list(transfer['test']);
  final deciles = _list(report['testDeciles']);
  final monotonicity = _map(report['monotonicitySummary']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Middle-Transition Runtime-Score Diagnostic')
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
    ..writeln('## Score Definition')
    ..writeln()
    ..writeln(
      '- Weights: concentration `${_fmt(_map(scoreDefinition['weights'])['concentration'])}`, '
      'spreadVariance `${_fmt(_map(scoreDefinition['weights'])['spreadVariance'])}`, '
      'plumMargin `${_fmt(_map(scoreDefinition['weights'])['plumMargin'])}`.',
    )
    ..writeln(
      '- Validation anchors: q25 `${_fmt(anchors['q25'])}`, q50 `${_fmt(anchors['q50'])}`, q75 `${_fmt(anchors['q75'])}`.',
    )
    ..writeln()
    ..writeln('## Test Outcome Score Means')
    ..writeln()
    ..writeln(
      '| Outcome | Concentration | Spread Variance | PLUM Margin | Runtime Score |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  for (final outcome in const ['middleTransitionZone', 'otherFocusSamples']) {
    final row = _map(outcomeMeans[outcome]);
    buffer.writeln(
      '| `$outcome` | ${_fmt(row['concentrationScore'])} | '
      '${_fmt(row['spreadVarianceScore'])} | ${_fmt(row['plumMarginScore'])} | '
      '${_fmt(row['runtimeScore'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Validation-Anchored Band Transfer')
    ..writeln()
    ..writeln(
      '| Band | Val Samples | Val Share | Test Samples | Test Share | Test Middle | Test Rate | Lift | Capture Share |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (var i = 0; i < validationBands.length; i++) {
    final left = _map(validationBands[i]);
    final right = _map(testBands[i]);
    buffer.writeln(
      '| `${left['band']}` | ${left['count']} | ${_pct(left['share'])} | '
      '${right['count']} | ${_pct(right['share'])} | ${right['positiveCount']} | '
      '${_pct(right['positiveRate'])} | ${_fmtMultiplier(_number(right['lift']))} | '
      '${_pct(right['captureShare'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Test Deciles')
    ..writeln()
    ..writeln(
      '| Decile | Score Min | Score Max | Samples | Middle | Rate | Capture Share |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in deciles) {
    final row = _map(raw);
    buffer.writeln(
      '| ${row['decile']} | ${_fmt(row['scoreMin'])} | ${_fmt(row['scoreMax'])} | '
      '${row['count']} | ${row['positiveCount']} | ${_pct(row['positiveRate'])} | '
      '${_pct(row['captureShare'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Monotonicity')
    ..writeln()
    ..writeln(
      '- Top decile rate: `${_pct(monotonicity['topDecileRate'])}`; bottom decile rate: `${_pct(monotonicity['bottomDecileRate'])}`.',
    )
    ..writeln(
      '- Top-to-bottom lift: `${_fmtMultiplier(_number(monotonicity['topToBottomLift']))}`.',
    )
    ..writeln(
      '- Non-decreasing adjacent pairs: `${monotonicity['nonDecreasingAdjacentPairs']}`; decreasing pairs: `${monotonicity['decreasingAdjacentPairs']}`.',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report remains diagnostic-only. It checks whether a small '
      'continuous runtime score is more useful than the prior discrete buckets '
      'for the `shindo4` middle-transition regime.',
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
  final samples = <_ScoreSample>[];

  void add(_ScoreSample sample) => samples.add(sample);

  _LabelSummary get summary {
    final middle = samples
        .where((sample) => sample.isMiddleTransitionZone)
        .length;
    return _LabelSummary(
      focusSampleCount: samples.length,
      middleTransitionCount: middle,
    );
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

class _BandAccumulator {
  int count = 0;
  int positiveCount = 0;

  void add(_ScoreSample sample) {
    count++;
    if (sample.isMiddleTransitionZone) positiveCount++;
  }

  Map<String, Object?> toJson({
    required String band,
    required int total,
    required int positiveTotal,
    required bool includeLabels,
  }) {
    final share = total == 0 ? 0.0 : count / total;
    final positiveRate = count == 0 ? 0.0 : positiveCount / count;
    final captureShare = positiveTotal == 0
        ? 0.0
        : positiveCount / positiveTotal;
    final baseline = total == 0 ? 0.0 : positiveTotal / total;
    return {
      'band': band,
      'count': count,
      'share': share,
      if (includeLabels) 'positiveCount': positiveCount,
      if (includeLabels) 'positiveRate': positiveRate,
      if (includeLabels) 'captureShare': captureShare,
      if (includeLabels) 'lift': baseline == 0 ? 0.0 : positiveRate / baseline,
    };
  }
}

class _ScoreMeanAccumulator {
  int count = 0;
  double concentrationScore = 0.0;
  double spreadVarianceScore = 0.0;
  double plumMarginScore = 0.0;
  double runtimeScore = 0.0;

  void add(_ScoreSample sample) {
    count++;
    concentrationScore += sample.concentrationScore;
    spreadVarianceScore += sample.spreadVarianceScore;
    plumMarginScore += sample.plumMarginScore;
    runtimeScore += sample.runtimeScore;
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'concentrationScore': count == 0 ? 0.0 : concentrationScore / count,
    'spreadVarianceScore': count == 0 ? 0.0 : spreadVarianceScore / count,
    'plumMarginScore': count == 0 ? 0.0 : plumMarginScore / count,
    'runtimeScore': count == 0 ? 0.0 : runtimeScore / count,
  };
}

class _ScoreSample {
  final double thresholdValue;
  final double actual;
  final double jma;
  final double plum;
  final double r20;
  final double r30D075;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final double topContributionShare;
  final double contributionHhi;
  final double contributionMarginStdDev;

  const _ScoreSample({
    required this.thresholdValue,
    required this.actual,
    required this.jma,
    required this.plum,
    required this.r20,
    required this.r30D075,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.topContributionShare,
    required this.contributionHhi,
    required this.contributionMarginStdDev,
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

  double get spreadVarianceScore =>
      _triangular(contributionMarginStdDev, center: 0.40, halfWidth: 0.20);

  double get plumMarginScore =>
      _triangular(plum - thresholdValue, center: 1.25, halfWidth: 0.75);

  double get runtimeScore => _clamp01(
    _scoreWeights['concentration']! * concentrationScore +
        _scoreWeights['spreadVariance']! * spreadVarianceScore +
        _scoreWeights['plumMargin']! * plumMarginScore,
  );
}

class _ContributionSummary {
  final double topContributionShare;
  final double contributionHhi;
  final double marginStdDev;

  const _ContributionSummary({
    required this.topContributionShare,
    required this.contributionHhi,
    required this.marginStdDev,
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
  'schemaVersion': 'plum_tohoku_middle_transition_runtime_score_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM Tohoku middle-transition runtime-score diagnostic',
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
    'maximumNearestEvidenceDistanceKm': _focusMaximumNearestEvidenceDistanceKm,
    'minimumPredictionMarginShindo': _focusMinimumMargin,
    'baselineThresholdCrossingRequired': true,
  },
  'scoreDefinition': {'weights': _scoreWeights},
  'labelDefinition': const {'positiveLabel': 'middle_transition_zone'},
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
  'scoreAnchors': const {'q25': 0.0, 'q50': 0.0, 'q75': 0.0},
  'testOutcomeScoreMeans': const {},
  'validationAnchoredBandTransfer': const {'validation': [], 'test': []},
  'testDeciles': const [],
  'monotonicitySummary': const {},
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

double _triangular(
  double value, {
  required double center,
  required double halfWidth,
}) {
  final distance = (value - center).abs();
  if (distance >= halfWidth) return 0.0;
  return 1.0 - distance / halfWidth;
}

double _inverseLinear(
  double value, {
  required double desirableCeiling,
  required double weakFloor,
}) {
  if (value <= desirableCeiling) return 1.0;
  if (value >= weakFloor) return 0.0;
  return 1.0 - (value - desirableCeiling) / (weakFloor - desirableCeiling);
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0.0;
  if (sorted.length == 1) return sorted.first;
  final index = (sorted.length - 1) * p;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = index - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

double _clamp01(double value) {
  if (value < 0.0) return 0.0;
  if (value > 1.0) return 1.0;
  return value;
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

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _fmtMultiplier(double value) => '${value.toStringAsFixed(2)}x';

String _fmt(Object? value) => _number(value).toStringAsFixed(3);
