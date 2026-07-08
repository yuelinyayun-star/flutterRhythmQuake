import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath = '.dart_tool/plum_confidence_gate/report.json';
const _defaultMarkdownPath = 'docs/baselines/plum_confidence_gate.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumConfidenceGateReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumConfidenceGateMarkdown(report));

  stdout.writeln('wrote PLUM confidence gate report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumConfidenceGateReportJson({
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

  final gates = [
    for (final config in _confidenceConfigs) _GateEvaluation(config),
  ];
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
        final r30d050 = plumR30D050
            .predict(targetStation: station, observedStations: retained)
            .intensity;
        final r20d050 = plumR20D050
            .predict(targetStation: station, observedStations: retained)
            .intensity;
        final r30d075 = plumR30D075
            .predict(targetStation: station, observedStations: retained)
            .intensity;
        final sample = _PredictionSample(
          actual: station.intensity,
          baselineRaw: math.max(jma, r30d050),
          jma: jma,
          r20d050: r20d050,
          r30d075: r30d075,
        );
        for (final gate in gates) {
          gate.add(sample);
        }
        stationForecastCount++;
      }
    }
  }

  if (stationForecastCount == 0) {
    errors.add('no_confidence_gate_station_forecasts');
  }

  final baseline = gates.firstWhere(
    (gate) => gate.config.id == 'baseline_raw_threshold',
  );
  final candidates =
      gates.skip(1).where((gate) {
        final shindo4 = gate.metricsFor('shindo4');
        final baselineShindo4 = baseline.metricsFor('shindo4');
        return shindo4.precision >= baselineShindo4.precision + 0.03 &&
            shindo4.recall >= baselineShindo4.recall - 0.15 &&
            shindo4.f1 >= baselineShindo4.f1 - 0.02;
      }).toList()..sort((left, right) {
        final left4 = left.metricsFor('shindo4');
        final right4 = right.metricsFor('shindo4');
        final leftScore = left4.precision + left4.f1;
        final rightScore = right4.precision + right4.f1;
        return rightScore.compareTo(leftScore);
      });

  return {
    'schemaVersion': 'plum_confidence_gate_report_v1',
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
      'rawIntensityFieldMutated': false,
      'gateSemantics':
          'threshold confidence decision only; raw predicted intensity is preserved',
    },
    'coverage': {
      'stationForecastCount': stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'recommendedForReplayValidation': candidates.isEmpty
        ? null
        : candidates.first.config.id,
    'evaluations': [for (final gate in gates) gate.toJson(baseline: baseline)],
    'decision': {
      'advanceToProduction': false,
      'advanceToFrozenTest': false,
      'nextAction': candidates.isEmpty
          ? 'revise_confidence_features_on_validation_only'
          : 'run_recommended_confidence_gate_on_replay',
    },
    'errors': errors,
  };
}

String plumConfidenceGateMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Confidence Gate Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `${policy['split']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln(
      '- Raw intensity field mutated: `${policy['rawIntensityFieldMutated']}`',
    )
    ..writeln(
      '- Recommended for replay validation: '
      '`${report['recommendedForReplayValidation'] ?? 'none'}`',
    )
    ..writeln('- Station forecasts: `${coverage['stationForecastCount']}`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln('- Baseline raw signal is `max(JMA-style, PLUM r30/d0.50)`.')
    ..writeln(
      '- Confidence gates do not change the predicted intensity field; they '
      'only decide whether a high-threshold prediction is considered '
      'confidence-supported.',
    )
    ..writeln()
    ..writeln('## Evaluation')
    ..writeln()
    ..writeln(
      '| Gate | Shindo4 P/R/F1 | Shindo4 FP/FN | Shindo5- P/R/F1 | Shindo5- FP/FN |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['evaluations'])) {
    final row = _map(raw);
    final thresholds = _map(row['thresholds']);
    final shindo4 = _map(thresholds['shindo4']);
    final shindo5 = _map(thresholds['shindo5-']);
    buffer.writeln(
      '| `${row['gateId']}` | ${_triplet(shindo4)} | '
      '${shindo4['falsePositive']} / ${shindo4['falseNegative']} | '
      '${_triplet(shindo5)} | '
      '${shindo5['falsePositive']} / ${shindo5['falseNegative']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Production remains blocked.')
    ..writeln('- Frozen test remains closed.')
    ..writeln(
      '- A recommended gate must pass real replay validation before any future '
      'acceptance criteria are written.',
    )
    ..writeln();
  return buffer.toString();
}

const _confidenceConfigs = [
  _ConfidenceGateConfig(
    id: 'baseline_raw_threshold',
    support: _ConfidenceSupport.baselineOnly,
  ),
  _ConfidenceGateConfig(
    id: 'jma_or_plum_r20_d0_50',
    support: _ConfidenceSupport.jmaOrR20D050,
  ),
  _ConfidenceGateConfig(
    id: 'jma_or_plum_r30_d0_75',
    support: _ConfidenceSupport.jmaOrR30D075,
  ),
  _ConfidenceGateConfig(
    id: 'plum_r20_d0_50_only',
    support: _ConfidenceSupport.r20D050,
  ),
  _ConfidenceGateConfig(
    id: 'two_of_jma_r20_d0_50_r30_d0_75',
    support: _ConfidenceSupport.twoOfThree,
  ),
];

enum _ConfidenceSupport {
  baselineOnly,
  jmaOrR20D050,
  jmaOrR30D075,
  r20D050,
  twoOfThree,
}

class _ConfidenceGateConfig {
  final String id;
  final _ConfidenceSupport support;

  const _ConfidenceGateConfig({required this.id, required this.support});

  bool predicts(_PredictionSample sample, double threshold) {
    if (sample.baselineRaw < threshold) return false;
    return switch (support) {
      _ConfidenceSupport.baselineOnly => true,
      _ConfidenceSupport.jmaOrR20D050 =>
        sample.jma >= threshold || sample.r20d050 >= threshold,
      _ConfidenceSupport.jmaOrR30D075 =>
        sample.jma >= threshold || sample.r30d075 >= threshold,
      _ConfidenceSupport.r20D050 => sample.r20d050 >= threshold,
      _ConfidenceSupport.twoOfThree =>
        [
              sample.jma >= threshold,
              sample.r20d050 >= threshold,
              sample.r30d075 >= threshold,
            ].where((value) => value).length >=
            2,
    };
  }
}

class _PredictionSample {
  final double actual;
  final double baselineRaw;
  final double jma;
  final double r20d050;
  final double r30d075;

  const _PredictionSample({
    required this.actual,
    required this.baselineRaw,
    required this.jma,
    required this.r20d050,
    required this.r30d075,
  });
}

class _GateEvaluation {
  final _ConfidenceGateConfig config;
  final thresholdCounts = {
    for (final threshold in _thresholds) threshold.label: _ThresholdCounts(),
  };

  _GateEvaluation(this.config);

  void add(_PredictionSample sample) {
    for (final threshold in _thresholds) {
      thresholdCounts[threshold.label]!.add(
        actual: sample.actual >= threshold.value,
        predicted: config.predicts(sample, threshold.value),
      );
    }
  }

  _ThresholdMetrics metricsFor(String label) =>
      thresholdCounts[label]!.toMetrics();

  Map<String, Object?> toJson({required _GateEvaluation baseline}) {
    final baseline4 = baseline.metricsFor('shindo4');
    final current4 = metricsFor('shindo4');
    return {
      'gateId': config.id,
      'thresholds': {
        for (final threshold in _thresholds)
          threshold.label: metricsFor(threshold.label).toJson(),
      },
      'deltasVsBaseline': {
        'shindo4Precision': current4.precision - baseline4.precision,
        'shindo4Recall': current4.recall - baseline4.recall,
        'shindo4F1': current4.f1 - baseline4.f1,
        'shindo4FalsePositive':
            current4.falsePositive - baseline4.falsePositive,
        'shindo4FalseNegative':
            current4.falseNegative - baseline4.falseNegative,
      },
    };
  }
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];

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

Map<String, Object?> _emptyReport({
  required String validationDatasetPath,
  required String modelPath,
  required List<String> errors,
}) => {
  'schemaVersion': 'plum_confidence_gate_report_v1',
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
    'rawIntensityFieldMutated': false,
  },
  'evaluations': const [],
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
