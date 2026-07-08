import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath = '.dart_tool/plum_validation_guard/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_validation_guard.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _plumMinimumEvidenceCount = 1;
const _guardThreshold = 3.5;

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumValidationGuardReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumValidationGuardMarkdown(report));

  stdout.writeln('wrote PLUM validation guard report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumValidationGuardReportJson({
  String validationDatasetPath = _defaultDatasetPath,
  String modelPath = _defaultModelPath,
  List<LocalContrastGuardConfig>? guardConfigs,
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
      errors: errors,
      validationDatasetPath: validationDatasetPath,
      modelPath: modelPath,
    );
  }

  final dataset =
      jsonDecode(datasetFile.readAsStringSync()) as Map<String, Object?>;
  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final configs = guardConfigs ?? _defaultGuardConfigs;
  final baseline = _GuardEvaluation(
    configId: 'baseline_no_guard',
    guardConfig: null,
  );
  final evaluations = [
    baseline,
    for (final config in configs)
      _GuardEvaluation(configId: config.id, guardConfig: config),
  ];

  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictor = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
    minimumEvidenceCount: _plumMinimumEvidenceCount,
  );

  var skippedMissingMagnitude = 0;
  var skippedNoSourceEstimate = 0;
  var stationForecastCount = 0;

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
    final actualMax = event.stations
        .map((station) => station.intensity)
        .fold<double>(-3.0, math.max);

    for (final variant in event.variants) {
      final retainedStations = [
        for (final id in variant.retainedStationIds)
          if (stationsById[id] != null) stationsById[id]!,
      ];
      final estimate = locator.locate(retainedStations);
      if (estimate == null) {
        skippedNoSourceEstimate++;
        continue;
      }

      final forecastsByConfig = {
        for (final evaluation in evaluations)
          evaluation.configId: <_StationForecast>[],
      };

      for (final station in event.stations) {
        final jmaPredicted = jmaPredictor
            .predict(
              magnitude: magnitude,
              sourceLatitude: estimate.latitude,
              sourceLongitude: estimate.longitude,
              depthKm: estimate.depthKm,
              stationLatitude: station.latitude,
              stationLongitude: station.longitude,
            )
            .intensity;
        final plumPrediction = plumPredictor.predict(
          targetStation: station,
          observedStations: retainedStations,
        );
        final baselinePredicted = math.max(
          jmaPredicted,
          plumPrediction.intensity,
        );
        forecastsByConfig[baseline.configId]!.add(
          _StationForecast(
            actual: station.intensity,
            predicted: baselinePredicted,
          ),
        );

        for (final evaluation in evaluations.skip(1)) {
          final guard = evaluation.guardConfig!;
          final result = _applyLocalContrastGuard(
            config: guard,
            targetStation: station,
            observedStations: retainedStations,
            plumPrediction: plumPrediction,
          );
          evaluation.addGuardResult(result);
          forecastsByConfig[evaluation.configId]!.add(
            _StationForecast(
              actual: station.intensity,
              predicted: math.max(jmaPredicted, result.guardedPlumIntensity),
            ),
          );
        }
        stationForecastCount++;
      }

      for (final evaluation in evaluations) {
        final forecasts = forecastsByConfig[evaluation.configId]!;
        evaluation.metrics.add(
          _ForecastCase(
            actualMax: actualMax,
            predictedMax: forecasts
                .map((forecast) => forecast.predicted)
                .fold<double>(-3.0, math.max),
            stationForecasts: forecasts,
          ),
        );
      }
    }
  }

  if (baseline.metrics.caseCount == 0) {
    errors.add('no_validation_guard_cases_produced');
  }

  final baselineShindo4 = baseline.metrics.thresholdMetrics(_thresholds[1]);
  final rows = [
    for (final evaluation in evaluations) evaluation.toJson(baseline),
  ];
  final candidates =
      evaluations.skip(1).where((evaluation) {
        final shindo4 = evaluation.metrics.thresholdMetrics(_thresholds[1]);
        return shindo4.f1 >= baselineShindo4.f1 &&
            shindo4.recall >= baselineShindo4.recall - 0.05 &&
            shindo4.falsePositive < baselineShindo4.falsePositive;
      }).toList()..sort((left, right) {
        final leftShindo4 = left.metrics.thresholdMetrics(_thresholds[1]);
        final rightShindo4 = right.metrics.thresholdMetrics(_thresholds[1]);
        final leftScore = leftShindo4.f1 + 0.25 * leftShindo4.precision;
        final rightScore = rightShindo4.f1 + 0.25 * rightShindo4.precision;
        return rightScore.compareTo(leftScore);
      });

  return {
    'schemaVersion': 'plum_validation_guard_report_v1',
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
      'doesNotTuneFrozenTest': true,
      'guardFamily': 'local_weak_neighborhood_contrast',
    },
    'baseMethod': const {
      'methodId': 'max_jma_style_plum_like_r30_d0_50',
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
      'plumMinimumEvidenceCount': _plumMinimumEvidenceCount,
    },
    'coverage': {
      'stationForecastCount': stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoSourceEstimate,
    },
    'recommendedForFurtherValidation': candidates.isEmpty
        ? null
        : candidates.first.configId,
    'evaluations': rows,
    'decision': {
      'advanceToProduction': false,
      'advanceToFrozenTest': false,
      'nextAction': candidates.isEmpty
          ? 'revise_guard_family_on_validation_only'
          : 'test_recommended_guard_on_real_replay_validation_only',
    },
    'errors': errors,
  };
}

String plumValidationGuardMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Validation Guard Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `${policy['split']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln('- Diagnostic only: `${policy['diagnosticOnly']}`')
    ..writeln(
      '- Recommended for further validation: '
      '`${report['recommendedForFurtherValidation'] ?? 'none'}`',
    )
    ..writeln('- Station forecasts: `${coverage['stationForecastCount']}`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- Baseline is `max_jma_style_plum_like_r30_d0_50` on validation only.',
    )
    ..writeln(
      '- Guard candidates cap only the PLUM branch when the nearest retained '
      'neighbor inside a local radius is weak.',
    )
    ..writeln(
      '- JMA-style and raw observed station values are not mutated; production '
      'UI and notifications remain disconnected.',
    )
    ..writeln()
    ..writeln('## Evaluation')
    ..writeln()
    ..writeln(
      '| Config | Triggered | Shindo4 P/R/F1 | Shindo4 FP/FN | Shindo5- P/R/F1 | Max MAE | Under |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['evaluations'])) {
    final row = _map(raw);
    final summary = _map(row['summary']);
    final thresholds = _map(row['thresholds']);
    final shindo4 = _map(thresholds['shindo4']);
    final shindo5 = _map(thresholds['shindo5-']);
    final guard = _map(row['guard']);
    buffer.writeln(
      '| `${row['configId']}` | ${guard['triggeredCount'] ?? 0} | '
      '${_triplet(shindo4)} | '
      '${shindo4['falsePositive']} / ${shindo4['falseNegative']} | '
      '${_triplet(shindo5)} | ${_fmt(summary['maxClassMae'])} | '
      '${_pct(summary['maxClassUnderestimateRate'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Production remains blocked.')
    ..writeln('- Frozen test remains closed for this guard family.')
    ..writeln(
      '- If a guard is recommended, the next step is real replay validation, '
      'not production wiring.',
    )
    ..writeln();
  return buffer.toString();
}

class LocalContrastGuardConfig {
  final String id;
  final double localRadiusKm;
  final double weakMaxIntensity;
  final int minimumWeakEvidenceCount;
  final double capMargin;

  const LocalContrastGuardConfig({
    required this.id,
    required this.localRadiusKm,
    required this.weakMaxIntensity,
    required this.minimumWeakEvidenceCount,
    required this.capMargin,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'localRadiusKm': localRadiusKm,
    'weakMaxIntensity': weakMaxIntensity,
    'minimumWeakEvidenceCount': minimumWeakEvidenceCount,
    'capMargin': capMargin,
  };
}

const _defaultGuardConfigs = [
  LocalContrastGuardConfig(
    id: 'local_contrast_r20_w2_5_m1_cap0_5',
    localRadiusKm: 20,
    weakMaxIntensity: 2.5,
    minimumWeakEvidenceCount: 1,
    capMargin: 0.5,
  ),
  LocalContrastGuardConfig(
    id: 'local_contrast_r20_w3_0_m1_cap0_5',
    localRadiusKm: 20,
    weakMaxIntensity: 3.0,
    minimumWeakEvidenceCount: 1,
    capMargin: 0.5,
  ),
  LocalContrastGuardConfig(
    id: 'local_contrast_r30_w2_5_m1_cap0_5',
    localRadiusKm: 30,
    weakMaxIntensity: 2.5,
    minimumWeakEvidenceCount: 1,
    capMargin: 0.5,
  ),
  LocalContrastGuardConfig(
    id: 'local_contrast_r30_w3_0_m1_cap0_5',
    localRadiusKm: 30,
    weakMaxIntensity: 3.0,
    minimumWeakEvidenceCount: 1,
    capMargin: 0.5,
  ),
  LocalContrastGuardConfig(
    id: 'local_contrast_r30_w3_0_m2_cap0_5',
    localRadiusKm: 30,
    weakMaxIntensity: 3.0,
    minimumWeakEvidenceCount: 2,
    capMargin: 0.5,
  ),
];

class _GuardEvaluation {
  final String configId;
  final LocalContrastGuardConfig? guardConfig;
  final metrics = _MetricAccumulator();
  var triggeredCount = 0;
  var weakNeighborMatchCount = 0;

  _GuardEvaluation({required this.configId, required this.guardConfig});

  void addGuardResult(_GuardResult result) {
    if (result.weakNeighborMatched) weakNeighborMatchCount++;
    if (result.triggered) triggeredCount++;
  }

  Map<String, Object?> toJson(_GuardEvaluation baseline) {
    final baselineShindo4 = baseline.metrics.thresholdMetrics(_thresholds[1]);
    final shindo4 = metrics.thresholdMetrics(_thresholds[1]);
    return {
      'configId': configId,
      'config': guardConfig?.toJson(),
      'summary': metrics.toJson(),
      'thresholds': {
        for (final threshold in _thresholds)
          threshold.label: metrics.thresholdMetrics(threshold).toJson(),
      },
      'deltasVsBaseline': {
        'shindo4Precision': shindo4.precision - baselineShindo4.precision,
        'shindo4Recall': shindo4.recall - baselineShindo4.recall,
        'shindo4F1': shindo4.f1 - baselineShindo4.f1,
        'shindo4FalsePositive':
            shindo4.falsePositive - baselineShindo4.falsePositive,
        'shindo4FalseNegative':
            shindo4.falseNegative - baselineShindo4.falseNegative,
      },
      'guard': {
        'weakNeighborMatchCount': weakNeighborMatchCount,
        'triggeredCount': triggeredCount,
      },
    };
  }
}

class _GuardResult {
  final double guardedPlumIntensity;
  final bool weakNeighborMatched;
  final bool triggered;

  const _GuardResult({
    required this.guardedPlumIntensity,
    required this.weakNeighborMatched,
    required this.triggered,
  });
}

_GuardResult _applyLocalContrastGuard({
  required LocalContrastGuardConfig config,
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> observedStations,
  required PlumLikeIntensityPrediction plumPrediction,
}) {
  if (plumPrediction.intensity < _guardThreshold) {
    return _GuardResult(
      guardedPlumIntensity: plumPrediction.intensity,
      weakNeighborMatched: false,
      triggered: false,
    );
  }
  var localWeakCount = 0;
  var nearestLocalDistance = double.infinity;
  var nearestLocalIntensity = -double.infinity;
  for (final observed in observedStations) {
    if (observed.stationId == targetStation.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      observed.latitude,
      observed.longitude,
    );
    if (distance > config.localRadiusKm) continue;
    if (distance < nearestLocalDistance) {
      nearestLocalDistance = distance;
      nearestLocalIntensity = observed.intensity;
    }
    if (observed.intensity <= config.weakMaxIntensity) {
      localWeakCount++;
    }
  }
  final weakMatched =
      localWeakCount >= config.minimumWeakEvidenceCount &&
      nearestLocalIntensity <= config.weakMaxIntensity;
  if (!weakMatched) {
    return _GuardResult(
      guardedPlumIntensity: plumPrediction.intensity,
      weakNeighborMatched: false,
      triggered: false,
    );
  }
  final capped = math.min(
    plumPrediction.intensity,
    nearestLocalIntensity + config.capMargin,
  );
  return _GuardResult(
    guardedPlumIntensity: capped,
    weakNeighborMatched: true,
    triggered: capped < plumPrediction.intensity,
  );
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'plum_validation_guard_report_v1',
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
  },
  'evaluations': const [],
  'errors': errors,
};

class _ForecastCase {
  final double actualMax;
  final double predictedMax;
  final List<_StationForecast> stationForecasts;

  const _ForecastCase({
    required this.actualMax,
    required this.predictedMax,
    required this.stationForecasts,
  });

  int get actualMaxClass => JpShindoScale.jmaIndexFromShindo(actualMax);
  int get predictedMaxClass => JpShindoScale.jmaIndexFromShindo(predictedMax);
}

class _StationForecast {
  final double actual;
  final double predicted;

  const _StationForecast({required this.actual, required this.predicted});
}

class _MetricAccumulator {
  final maxClassErrors = <int>[];
  final maxIntensityErrors = <double>[];
  final stationIntensityErrors = <double>[];
  final thresholdCounts = {
    for (final threshold in _thresholds) threshold.label: _ThresholdCounts(),
  };
  var underestimatedMaxClass = 0;
  var exactMaxClass = 0;
  var withinOneMaxClass = 0;
  var stationForecastCount = 0;

  int get caseCount => maxClassErrors.length;

  void add(_ForecastCase row) {
    final classError = row.predictedMaxClass - row.actualMaxClass;
    maxClassErrors.add(classError.abs());
    maxIntensityErrors.add((row.predictedMax - row.actualMax).abs());
    if (classError < 0) underestimatedMaxClass++;
    if (classError == 0) exactMaxClass++;
    if (classError.abs() <= 1) withinOneMaxClass++;
    for (final station in row.stationForecasts) {
      stationForecastCount++;
      stationIntensityErrors.add((station.predicted - station.actual).abs());
      for (final threshold in _thresholds) {
        thresholdCounts[threshold.label]!.add(
          actual: station.actual >= threshold.value,
          predicted: station.predicted >= threshold.value,
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    'caseCount': caseCount,
    'stationForecastCount': stationForecastCount,
    'maxClassMae': _mean(maxClassErrors.map((value) => value.toDouble())),
    'maxIntensityMae': _mean(maxIntensityErrors),
    'stationIntensityMae': _mean(stationIntensityErrors),
    'maxClassUnderestimateRate': caseCount == 0
        ? 0.0
        : underestimatedMaxClass / caseCount,
    'maxClassExactAccuracy': caseCount == 0 ? 0.0 : exactMaxClass / caseCount,
    'maxClassWithinOneAccuracy': caseCount == 0
        ? 0.0
        : withinOneMaxClass / caseCount,
  };

  _ThresholdMetrics thresholdMetrics(_Threshold threshold) =>
      thresholdCounts[threshold.label]!.toMetrics();
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

const _thresholds = [
  _Threshold('shindo3', 2.5),
  _Threshold('shindo4', 3.5),
  _Threshold('shindo5-', 4.5),
];

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

double _mean(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    if (!value.isFinite) continue;
    sum += value;
    count++;
  }
  return count == 0 ? 0.0 : sum / count;
}

String _fmt(Object? value) => _number(value).toStringAsFixed(2);

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';

String _triplet(Map<String, Object?> metrics) {
  return '${_pct(metrics['precision'])} / ${_pct(metrics['recall'])} / '
      '${_pct(metrics['f1'])}';
}
