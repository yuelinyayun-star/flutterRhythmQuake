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
const _defaultOutputPath = '.dart_tool/plum_evidence_shape/report.json';
const _defaultMarkdownPath = 'docs/baselines/plum_evidence_shape.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumEvidenceShapeReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumEvidenceShapeMarkdown(report));

  stdout.writeln('wrote PLUM evidence shape report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumEvidenceShapeReportJson({
  String validationDatasetPath = _defaultDatasetPath,
  String modelPath = _defaultModelPath,
  List<EvidenceShapeConfig>? shapeConfigs,
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
  final configs = shapeConfigs ?? _defaultShapeConfigs;
  final evaluations = [
    _ShapeEvaluation(configId: 'baseline_no_shape_gate', config: null),
    for (final config in configs)
      _ShapeEvaluation(configId: config.id, config: config),
  ];
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictor = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
  );
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
    final actualMax = event.stations
        .map((station) => station.intensity)
        .fold<double>(-3.0, math.max);
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
          observedStations: retained,
        );
        forecastsByConfig['baseline_no_shape_gate']!.add(
          _StationForecast(
            actual: station.intensity,
            predicted: math.max(jmaPredicted, plumPrediction.intensity),
          ),
        );
        for (final evaluation in evaluations.skip(1)) {
          final result = _applyShapeGate(
            config: evaluation.config!,
            targetStation: station,
            observedStations: retained,
            plumPrediction: plumPrediction,
          );
          evaluation.addShapeResult(result);
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

  if (stationForecastCount == 0) {
    errors.add('no_evidence_shape_station_forecasts');
  }
  final baseline = evaluations.first;
  final baseline4 = baseline.metrics.thresholdMetrics(_thresholds[1]);
  final candidates =
      evaluations.skip(1).where((evaluation) {
        final shindo4 = evaluation.metrics.thresholdMetrics(_thresholds[1]);
        return shindo4.falsePositive < baseline4.falsePositive &&
            shindo4.recall >= baseline4.recall - 0.10 &&
            shindo4.f1 >= baseline4.f1;
      }).toList()..sort((left, right) {
        final left4 = left.metrics.thresholdMetrics(_thresholds[1]);
        final right4 = right.metrics.thresholdMetrics(_thresholds[1]);
        final leftScore = left4.f1 + 0.25 * left4.precision;
        final rightScore = right4.f1 + 0.25 * right4.precision;
        return rightScore.compareTo(leftScore);
      });

  return {
    'schemaVersion': 'plum_evidence_shape_report_v1',
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
      'rawProductionIntensityMutated': false,
      'method':
          'validation-only PLUM strong-evidence neighborhood shape candidates',
    },
    'baseMethod': const {
      'methodId': 'max_jma_style_plum_like_r30_d0_50',
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
    },
    'coverage': {
      'stationForecastCount': stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'recommendedForReplayValidation': candidates.isEmpty
        ? null
        : candidates.first.configId,
    'evaluations': [
      for (final evaluation in evaluations) evaluation.toJson(baseline),
    ],
    'decision': {
      'advanceToProduction': false,
      'advanceToFrozenTest': false,
      'nextAction': candidates.isEmpty
          ? 'revise_shape_features_on_validation_only'
          : 'run_recommended_shape_candidate_on_replay',
    },
    'errors': errors,
  };
}

String plumEvidenceShapeMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Evidence Shape Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `${policy['split']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln(
      '- Raw production intensity mutated: '
      '`${policy['rawProductionIntensityMutated']}`',
    )
    ..writeln(
      '- Recommended for replay validation: '
      '`${report['recommendedForReplayValidation'] ?? 'none'}`',
    )
    ..writeln('- Station forecasts: `${coverage['stationForecastCount']}`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- Baseline is `max(JMA-style, PLUM r30/d0.50)` on validation only.',
    )
    ..writeln(
      '- Shape candidates suppress only diagnostic PLUM high-threshold '
      'predictions when nearby strong evidence is isolated or not spatially '
      'spread.',
    )
    ..writeln(
      '- Production predicted intensity, UI, notifications and wording remain '
      'disconnected.',
    )
    ..writeln()
    ..writeln('## Evaluation')
    ..writeln()
    ..writeln(
      '| Config | Suppressed | Shindo4 P/R/F1 | Shindo4 FP/FN | Shindo5- P/R/F1 | Max MAE | Under |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['evaluations'])) {
    final row = _map(raw);
    final summary = _map(row['summary']);
    final thresholds = _map(row['thresholds']);
    final shindo4 = _map(thresholds['shindo4']);
    final shindo5 = _map(thresholds['shindo5-']);
    final shape = _map(row['shape']);
    buffer.writeln(
      '| `${row['configId']}` | ${shape['suppressedCount'] ?? 0} | '
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
    ..writeln('- Frozen test remains closed.')
    ..writeln(
      '- Any recommended shape candidate must be checked on real replay before '
      'wording, UI, notification, or frozen-test criteria work.',
    )
    ..writeln();
  return buffer.toString();
}

class EvidenceShapeConfig {
  final String id;
  final double threshold;
  final int minimumStrongEvidenceCount;
  final double supportRadiusKm;
  final double evidenceMargin;
  final double minimumEvidenceSpreadKm;

  const EvidenceShapeConfig({
    required this.id,
    required this.threshold,
    required this.minimumStrongEvidenceCount,
    required this.supportRadiusKm,
    required this.evidenceMargin,
    required this.minimumEvidenceSpreadKm,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'threshold': threshold,
    'minimumStrongEvidenceCount': minimumStrongEvidenceCount,
    'supportRadiusKm': supportRadiusKm,
    'evidenceMargin': evidenceMargin,
    'minimumEvidenceSpreadKm': minimumEvidenceSpreadKm,
  };
}

const _defaultShapeConfigs = [
  EvidenceShapeConfig(
    id: 'shape_t4_min2_r30_margin0_5_spread0',
    threshold: 3.5,
    minimumStrongEvidenceCount: 2,
    supportRadiusKm: 30,
    evidenceMargin: 0.5,
    minimumEvidenceSpreadKm: 0,
  ),
  EvidenceShapeConfig(
    id: 'shape_t4_min2_r30_margin0_5_spread10',
    threshold: 3.5,
    minimumStrongEvidenceCount: 2,
    supportRadiusKm: 30,
    evidenceMargin: 0.5,
    minimumEvidenceSpreadKm: 10,
  ),
  EvidenceShapeConfig(
    id: 'shape_t4_min3_r30_margin0_5_spread10',
    threshold: 3.5,
    minimumStrongEvidenceCount: 3,
    supportRadiusKm: 30,
    evidenceMargin: 0.5,
    minimumEvidenceSpreadKm: 10,
  ),
  EvidenceShapeConfig(
    id: 'shape_t5_min2_r30_margin0_5_spread10',
    threshold: 4.5,
    minimumStrongEvidenceCount: 2,
    supportRadiusKm: 30,
    evidenceMargin: 0.5,
    minimumEvidenceSpreadKm: 10,
  ),
];

class _ShapeEvaluation {
  final String configId;
  final EvidenceShapeConfig? config;
  final metrics = _MetricAccumulator();
  var supportPassCount = 0;
  var suppressedCount = 0;

  _ShapeEvaluation({required this.configId, required this.config});

  void addShapeResult(_ShapeResult result) {
    if (result.supportPassed) supportPassCount++;
    if (result.suppressed) suppressedCount++;
  }

  Map<String, Object?> toJson(_ShapeEvaluation baseline) {
    final shindo4 = metrics.thresholdMetrics(_thresholds[1]);
    final baseline4 = baseline.metrics.thresholdMetrics(_thresholds[1]);
    return {
      'configId': configId,
      'config': config?.toJson(),
      'summary': metrics.toJson(),
      'thresholds': {
        for (final threshold in _thresholds)
          threshold.label: metrics.thresholdMetrics(threshold).toJson(),
      },
      'deltasVsBaseline': {
        'shindo4Precision': shindo4.precision - baseline4.precision,
        'shindo4Recall': shindo4.recall - baseline4.recall,
        'shindo4F1': shindo4.f1 - baseline4.f1,
        'shindo4FalsePositive': shindo4.falsePositive - baseline4.falsePositive,
        'shindo4FalseNegative': shindo4.falseNegative - baseline4.falseNegative,
      },
      'shape': {
        'supportPassCount': supportPassCount,
        'suppressedCount': suppressedCount,
      },
    };
  }
}

class _ShapeResult {
  final double guardedPlumIntensity;
  final bool supportPassed;
  final bool suppressed;

  const _ShapeResult({
    required this.guardedPlumIntensity,
    required this.supportPassed,
    required this.suppressed,
  });
}

_ShapeResult _applyShapeGate({
  required EvidenceShapeConfig config,
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> observedStations,
  required PlumLikeIntensityPrediction plumPrediction,
}) {
  if (plumPrediction.intensity < config.threshold) {
    return _ShapeResult(
      guardedPlumIntensity: plumPrediction.intensity,
      supportPassed: false,
      suppressed: false,
    );
  }
  final supporting = <StaticIntensityStation>[];
  for (final observed in observedStations) {
    if (observed.stationId == targetStation.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      observed.latitude,
      observed.longitude,
    );
    if (distance > config.supportRadiusKm) continue;
    final propagated =
        observed.intensity - _plumDampingPer10Km * (distance / 10);
    if (propagated >= config.threshold - config.evidenceMargin) {
      supporting.add(observed);
    }
  }
  final spread = _maxPairDistance(supporting);
  final passed =
      supporting.length >= config.minimumStrongEvidenceCount &&
      spread >= config.minimumEvidenceSpreadKm;
  if (passed) {
    return _ShapeResult(
      guardedPlumIntensity: plumPrediction.intensity,
      supportPassed: true,
      suppressed: false,
    );
  }
  return const _ShapeResult(
    guardedPlumIntensity: -3.0,
    supportPassed: false,
    suppressed: true,
  );
}

double _maxPairDistance(List<StaticIntensityStation> stations) {
  var maxDistance = 0.0;
  for (var i = 0; i < stations.length; i++) {
    for (var j = i + 1; j < stations.length; j++) {
      maxDistance = math.max(
        maxDistance,
        QuakeCalculator.haversineDistance(
          stations[i].latitude,
          stations[i].longitude,
          stations[j].latitude,
          stations[j].longitude,
        ),
      );
    }
  }
  return maxDistance;
}

Map<String, Object?> _emptyReport({
  required String validationDatasetPath,
  required String modelPath,
  required List<String> errors,
}) => {
  'schemaVersion': 'plum_evidence_shape_report_v1',
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
    'rawProductionIntensityMutated': false,
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
