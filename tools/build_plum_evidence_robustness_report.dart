import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath = '.dart_tool/plum_evidence_robustness/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_evidence_robustness.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumEvidenceRobustnessReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumEvidenceRobustnessMarkdown(report));

  stdout.writeln('wrote PLUM evidence robustness report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumEvidenceRobustnessReportJson({
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
    errors.add('no_evidence_robustness_station_forecasts');
  }

  return {
    'schemaVersion': 'plum_evidence_robustness_report_v1',
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
          'non-suppressive evidence robustness scoring for high-threshold predictions',
    },
    'baseMethod': const {
      'methodId': 'max_jma_style_plum_like_r30_d0_50',
      'plumRadiusKm': 30.0,
      'plumDampingPer10Km': 0.50,
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
          'use_robustness_buckets_to_design_non_suppressive_confidence_or_calibration_features',
    },
    'errors': errors,
  };
}

String plumEvidenceRobustnessMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Evidence Robustness Diagnostic')
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
      '- It stratifies baseline high-threshold predictions by evidence '
      'robustness features: mask rate, retained station count, PLUM evidence '
      'count, nearest evidence distance, and branch agreement.',
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
      ..writeln('| Feature | Bucket | Pred+ | Precision | TP | FP |')
      ..writeln('| --- | --- | ---: | ---: | ---: | ---: |');
    final features = _map(row['features']);
    for (final feature in _featureOrder) {
      final buckets = _map(features[feature]);
      for (final bucketName in buckets.keys.toList()..sort()) {
        final bucket = _map(buckets[bucketName]);
        buffer.writeln(
          '| `$feature` | `$bucketName` | ${bucket['predictedPositive']} | '
          '${_pct(bucket['precision'])} | ${bucket['truePositive']} | '
          '${bucket['falsePositive']} |',
        );
      }
    }
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Production remains blocked.')
    ..writeln('- Frozen test remains closed.')
    ..writeln(
      '- Use these buckets to design non-suppressive confidence or calibration '
      'features; do not replace predicted intensity.',
    )
    ..writeln();
  return buffer.toString();
}

class _ThresholdSummary {
  final baseline = _ThresholdCounts();
  final featureBuckets = {
    for (final feature in _featureOrder) feature: <String, _PredictedBucket>{},
  };

  void add(_RobustnessSample sample, double threshold) {
    final actual = sample.actual >= threshold;
    final predicted = sample.baselineRaw >= threshold;
    baseline.add(actual: actual, predicted: predicted);
    if (!predicted) return;
    final buckets = sample.buckets(threshold);
    for (final entry in buckets.entries) {
      featureBuckets[entry.key]!
          .putIfAbsent(entry.value, _PredictedBucket.new)
          .add(actualPositive: actual);
    }
  }

  Map<String, Object?> toJson() => {
    'baseline': baseline.toMetrics().toJson(),
    'features': {
      for (final feature in _featureOrder)
        feature: {
          for (final entry in featureBuckets[feature]!.entries)
            entry.key: entry.value.toJson(),
        },
    },
  };
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

  Map<String, String> buckets(double threshold) {
    final agreement = [
      jma >= threshold,
      r20 >= threshold,
      r30D075 >= threshold,
    ].where((value) => value).length;
    return {
      'maskRate': '${(maskRate * 100).round()}pct',
      'retainedCount': _retainedBucket(retainedCount),
      'plumEvidenceCount': _evidenceBucket(evidenceCount),
      'nearestEvidenceDistance': _nearestBucket(nearestEvidenceDistanceKm),
      'branchAgreement': 'agree_$agreement',
      'robustnessScore': 'score_${_score(agreement)}',
    };
  }

  int _score(int agreement) {
    var score = 0;
    if (maskRate <= 0.5) score++;
    if (retainedCount >= 8) score++;
    if (evidenceCount >= 2) score++;
    if (nearestEvidenceDistanceKm <= 20) score++;
    score += agreement;
    return score;
  }
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

const _featureOrder = [
  'maskRate',
  'retainedCount',
  'plumEvidenceCount',
  'nearestEvidenceDistance',
  'branchAgreement',
  'robustnessScore',
];

String _retainedBucket(int count) {
  if (count < 8) return 'lt_8';
  if (count < 16) return '08_15';
  return 'ge_16';
}

String _evidenceBucket(int count) {
  if (count <= 0) return '0';
  if (count == 1) return '1';
  if (count == 2) return '2';
  return 'ge_3';
}

String _nearestBucket(double distanceKm) {
  if (!distanceKm.isFinite) return 'none';
  if (distanceKm < 10) return '000_010km';
  if (distanceKm < 20) return '010_020km';
  if (distanceKm < 30) return '020_030km';
  return 'gt_030km';
}

Map<String, Object?> _emptyReport({
  required String validationDatasetPath,
  required String modelPath,
  required List<String> errors,
}) => {
  'schemaVersion': 'plum_evidence_robustness_report_v1',
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
