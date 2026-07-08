import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_evidence_robustness_calibration/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_evidence_robustness_calibration.generated.md';

// 置信带门槛:经验 precision 落入哪个区间,决定 bucket 标签。
// 这些是诊断分桶边界,不是生产阈值,且不修改预测震度。
const _highBandMinPrecision = 0.75;
const _mediumBandMinPrecision = 0.55;
const _minSampleForBandAssignment = 20;

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumEvidenceRobustnessCalibrationReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumEvidenceRobustnessCalibrationMarkdown(report),
  );

  stdout.writeln('wrote PLUM evidence robustness calibration report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumEvidenceRobustnessCalibrationReportJson({
  String validationDatasetPath = _defaultDatasetPath,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final datasetFile = File(validationDatasetPath);
  final modelFile = File(modelPath);
  if (!datasetFile.existsSync()) {
    errors.add('validation_dataset_missing:$validationDatasetPath');
  }
  if (!modelFile.existsSync()) {
    errors.add('static_attenuation_model_missing:$modelPath');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      validationDatasetPath: validationDatasetPath,
      modelPath: modelPath,
      errors: errors,
    );
  }

  final dataset =
      jsonDecode(datasetFile.readAsStringSync()) as Map<String, Object?>;
  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumR30D050 = const PlumLikeIntensityPredictor(
    radiusKm: 30,
    dampingPer10Km: 0.50,
  );
  final plumR20D050 = const PlumLikeIntensityPredictor(
    radiusKm: 20,
    dampingPer10Km: 0.50,
  );
  final plumR30D075 = const PlumLikeIntensityPredictor(
    radiusKm: 30,
    dampingPer10Km: 0.75,
  );

  final summaries = {
    for (final threshold in _thresholds) threshold.label: _ThresholdSummary(),
  };
  var stationForecastCount = 0;
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

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
      for (final station in event.stations) {
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
        final r30 = plumR30D050.predict(
          targetStation: station,
          observedStations: retained,
        );
        final r20 = plumR20D050.predict(
          targetStation: station,
          observedStations: retained,
        );
        final r30D075 = plumR30D075.predict(
          targetStation: station,
          observedStations: retained,
        );
        final sample = _RobustnessSample(
          actual: station.intensity,
          baselineRaw: math.max(jma, r30.intensity),
          jma: jma,
          r20: r20.intensity,
          r30D075: r30D075.intensity,
          maskRate: variant.maskRate,
          retainedCount: retained.length,
          evidenceCount: r30.evidenceCount,
          nearestEvidenceDistanceKm: r30.nearestEvidenceDistanceKm,
        );
        for (final threshold in _thresholds) {
          summaries[threshold.label]!.add(sample, threshold.value);
        }
        stationForecastCount++;
      }
    }
  }

  if (stationForecastCount == 0) {
    errors.add('no_robustness_calibration_station_forecasts');
  }

  return {
    'schemaVersion': 'plum_evidence_robustness_calibration_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'validationDatasetPath': validationDatasetPath,
    'modelPath': modelPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'rawPredictedIntensityMutated': false,
      'method':
          'non-suppressive joint robustness calibration: maps branch agreement '
          'and robustness score to empirical confidence bands without changing '
          'predicted intensity',
    },
    'baseMethod': const {
      'methodId': 'max_jma_style_plum_like_r30_d0_50',
      'plumRadiusKm': 30.0,
      'plumDampingPer10Km': 0.50,
    },
    'bandDefinitions': const {
      'high': {
        'minPrecision': _highBandMinPrecision,
        'label': 'high',
      },
      'medium': {
        'minPrecision': _mediumBandMinPrecision,
        'label': 'medium',
      },
      'low': {
        'minPrecision': 0.0,
        'label': 'low',
      },
      'minSampleForBandAssignment': _minSampleForBandAssignment,
    },
    'coverage': {
      'stationForecastCount': stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'thresholds': {
      for (final threshold in _thresholds)
        threshold.label: summaries[threshold.label]!.toJson(),
    },
    'decision': const {
      'advanceToProduction': false,
      'advanceToFrozenTest': false,
      'nextAction':
          'use_joint_calibration_table_to_design_wording_only_confidence_layer',
    },
    'errors': errors,
  };
}

String plumEvidenceRobustnessCalibrationMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final bandDefs = _map(report['bandDefinitions']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Evidence Robustness Calibration Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `${policy['split']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln(
      '- Raw predicted intensity mutated: '
      '`${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln('- Station forecasts: `${coverage['stationForecastCount']}`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This report does not suppress, cap, replace, or hide predicted '
      'intensity.',
    )
    ..writeln(
      '- It builds a joint calibration table over `branchAgreement` x '
      '`robustnessScore` for high-threshold predictions, and maps each '
      'non-empty bucket to an empirical confidence band.',
    )
    ..writeln(
      '- Confidence bands are diagnostic labels only; they do not change the '
      'raw predicted intensity field and must not feed notifications or UI '
      'wording until explicit wording-only acceptance criteria exist.',
    )
    ..writeln()
    ..writeln('## Band Definitions')
    ..writeln()
    ..writeln('| Band | Min empirical precision |')
    ..writeln('| --- | ---: |')
    ..writeln(
      '| `high` | `${_pct(bandDefs['high'] is Map ? _map(bandDefs['high'])['minPrecision'] : null)}` |',
    )
    ..writeln(
      '| `medium` | `${_pct(bandDefs['medium'] is Map ? _map(bandDefs['medium'])['minPrecision'] : null)}` |',
    )
    ..writeln('| `low` | `0.0%` |')
    ..writeln(
      '- Min sample for band assignment: '
      '`${bandDefs['minSampleForBandAssignment']}`',
    );
  final thresholds = _map(report['thresholds']);
  for (final threshold in _thresholds) {
    final row = _map(thresholds[threshold.label]);
    buffer
      ..writeln()
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('- Baseline P/R/F1: `${_triplet(_map(row['baseline']))}`')
      ..writeln()
      ..writeln('### Joint Calibration Table')
      ..writeln()
      ..writeln(
        '| branchAgreement | robustnessScore | Pred+ | TP | FP | Precision | Band |',
      )
      ..writeln('| --- | --- | ---: | ---: | ---: | ---: | --- |');
    final jointBuckets = _list(row['jointBuckets']);
    for (final raw in jointBuckets) {
      final bucket = _map(raw);
      buffer.writeln(
        '| `${bucket['branchAgreement']}` | `${bucket['robustnessScore']}` | '
        '${bucket['predictedPositive']} | ${bucket['truePositive']} | '
        '${bucket['falsePositive']} | ${_pct(bucket['precision'])} | '
        '`${bucket['band']}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Band Summary')
      ..writeln()
      ..writeln('| Band | Buckets | Pred+ | TP | FP | Precision |')
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
    final bandSummary = _map(row['bandSummary']);
    for (final bandName in const ['high', 'medium', 'low', 'insufficient']) {
      final band = _map(bandSummary[bandName]);
      buffer.writeln(
        '| `$bandName` | ${band['bucketCount']} | '
        '${band['predictedPositive']} | ${band['truePositive']} | '
        '${band['falsePositive']} | ${_pct(band['precision'])} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Production remains blocked.')
    ..writeln('- Frozen test remains closed.')
    ..writeln(
      '- Use the joint calibration table to design a future wording-only '
      'confidence layer; do not replace, cap, or hide predicted intensity.',
    )
    ..writeln();
  return buffer.toString();
}

class _ThresholdSummary {
  final baseline = _ThresholdCounts();
  final jointBuckets = <String, _JointBucket>{};
  final marginalBranchAgreement = <String, _PredictedBucket>{};
  final marginalRobustnessScore = <String, _PredictedBucket>{};

  void add(_RobustnessSample sample, double threshold) {
    final actual = sample.actual >= threshold;
    final predicted = sample.baselineRaw >= threshold;
    baseline.add(actual: actual, predicted: predicted);
    if (!predicted) return;
    final branch = sample.branchAgreement(threshold);
    final score = sample.robustnessScore(threshold);
    final jointKey = '$branch|$score';
    jointBuckets
        .putIfAbsent(jointKey, _JointBucket.new)
        .add(branch: branch, score: score, actualPositive: actual);
    marginalBranchAgreement
        .putIfAbsent(branch, _PredictedBucket.new)
        .add(actualPositive: actual);
    marginalRobustnessScore
        .putIfAbsent(score, _PredictedBucket.new)
        .add(actualPositive: actual);
  }

  Map<String, Object?> toJson() {
    final joint = jointBuckets.values.toList()
      ..sort((a, b) {
        final branchCmp = a.branch.compareTo(b.branch);
        if (branchCmp != 0) return branchCmp;
        return a.score.compareTo(b.score);
      });
    final bandAccumulators = {
      'high': _BandAccumulator(),
      'medium': _BandAccumulator(),
      'low': _BandAccumulator(),
      'insufficient': _BandAccumulator(),
    };
    final jointJson = <Map<String, Object?>>[];
    for (final bucket in joint) {
      final band = _bandFor(bucket);
      bandAccumulators[band]!.addBucket(bucket);
      jointJson.add({
        'branchAgreement': bucket.branch,
        'robustnessScore': bucket.score,
        'predictedPositive': bucket.predictedPositive,
        'truePositive': bucket.truePositive,
        'falsePositive': bucket.falsePositive,
        'precision': bucket.precision,
        'band': band,
      });
    }
    return {
      'baseline': baseline.toMetrics().toJson(),
      'jointBuckets': jointJson,
      'bandSummary': {
        for (final entry in bandAccumulators.entries)
          entry.key: entry.value.toJson(),
      },
      'marginalBranchAgreement': {
        for (final entry in marginalBranchAgreement.entries)
          entry.key: entry.value.toJson(),
      },
      'marginalRobustnessScore': {
        for (final entry in marginalRobustnessScore.entries)
          entry.key: entry.value.toJson(),
      },
    };
  }

  String _bandFor(_JointBucket bucket) {
    if (bucket.predictedPositive < _minSampleForBandAssignment) {
      return 'insufficient';
    }
    if (bucket.precision >= _highBandMinPrecision) return 'high';
    if (bucket.precision >= _mediumBandMinPrecision) return 'medium';
    return 'low';
  }
}

class _RobustnessSample {
  final double actual;
  final double baselineRaw;
  final double jma;
  final double r20;
  final double r30D075;
  final double maskRate;
  final int retainedCount;
  final int evidenceCount;
  final double nearestEvidenceDistanceKm;

  const _RobustnessSample({
    required this.actual,
    required this.baselineRaw,
    required this.jma,
    required this.r20,
    required this.r30D075,
    required this.maskRate,
    required this.retainedCount,
    required this.evidenceCount,
    required this.nearestEvidenceDistanceKm,
  });

  String branchAgreement(double threshold) {
    final agree = [
      jma >= threshold,
      r20 >= threshold,
      r30D075 >= threshold,
    ].where((value) => value).length;
    return 'agree_$agree';
  }

  String robustnessScore(double threshold) {
    return 'score_${_score(threshold)}';
  }

  int _score(double threshold) {
    var score = 0;
    if (maskRate <= 0.5) score++;
    if (retainedCount >= 8) score++;
    if (evidenceCount >= 2) score++;
    if (nearestEvidenceDistanceKm <= 20) score++;
    score += [
      jma >= threshold,
      r20 >= threshold,
      r30D075 >= threshold,
    ].where((value) => value).length;
    return score;
  }
}

class _JointBucket {
  var branch = '';
  var score = '';
  var predictedPositive = 0;
  var truePositive = 0;
  var falsePositive = 0;

  void add({
    required String branch,
    required String score,
    required bool actualPositive,
  }) {
    this.branch = branch;
    this.score = score;
    predictedPositive++;
    if (actualPositive) {
      truePositive++;
    } else {
      falsePositive++;
    }
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;
}

class _PredictedBucket {
  var predictedPositive = 0;
  var truePositive = 0;
  var falsePositive = 0;

  void add({required bool actualPositive}) {
    predictedPositive++;
    if (actualPositive) {
      truePositive++;
    } else {
      falsePositive++;
    }
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;

  Map<String, Object?> toJson() => {
    'predictedPositive': predictedPositive,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'precision': precision,
  };
}

class _BandAccumulator {
  var bucketCount = 0;
  var predictedPositive = 0;
  var truePositive = 0;
  var falsePositive = 0;

  void addBucket(_JointBucket bucket) {
    bucketCount++;
    predictedPositive += bucket.predictedPositive;
    truePositive += bucket.truePositive;
    falsePositive += bucket.falsePositive;
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;

  Map<String, Object?> toJson() => {
    'bucketCount': bucketCount,
    'predictedPositive': predictedPositive,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'precision': precision,
  };
}

class _ThresholdCounts {
  var truePositive = 0;
  var falsePositive = 0;
  var falseNegative = 0;
  var trueNegative = 0;

  void add({required bool actual, required bool predicted}) {
    if (actual && predicted) {
      truePositive++;
    } else if (!actual && predicted) {
      falsePositive++;
    } else if (actual && !predicted) {
      falseNegative++;
    } else {
      trueNegative++;
    }
  }

  _ThresholdMetrics toMetrics() => _ThresholdMetrics(
    truePositive: truePositive,
    falsePositive: falsePositive,
    falseNegative: falseNegative,
    trueNegative: trueNegative,
  );
}

class _ThresholdMetrics {
  final int truePositive;
  final int falsePositive;
  final int falseNegative;
  final int trueNegative;

  const _ThresholdMetrics({
    required this.truePositive,
    required this.falsePositive,
    required this.falseNegative,
    required this.trueNegative,
  });

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object?> toJson() => {
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'trueNegative': trueNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];

Map<String, Object?> _emptyReport({
  required String validationDatasetPath,
  required String modelPath,
  required List<String> errors,
}) => {
  'schemaVersion': 'plum_evidence_robustness_calibration_report_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'modelPath': modelPath,
  'policy': const {
    'split': 'validation',
    'frozenTestEvaluated': false,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'rawPredictedIntensityMutated': false,
  },
  'bandDefinitions': const {
    'high': {'minPrecision': _highBandMinPrecision, 'label': 'high'},
    'medium': {'minPrecision': _mediumBandMinPrecision, 'label': 'medium'},
    'low': {'minPrecision': 0.0, 'label': 'low'},
    'minSampleForBandAssignment': _minSampleForBandAssignment,
  },
  'thresholds': const {},
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

List<Object?> _list(Object? value) => value is List ? value : const [];

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(value?.toString() ?? '0');
}

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';

String _triplet(Map<String, Object?> metrics) {
  return '${_pct(metrics['precision'])} / ${_pct(metrics['recall'])} / '
      '${_pct(metrics['f1'])}';
}
