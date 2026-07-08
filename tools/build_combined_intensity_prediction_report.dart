import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

import 'build_static_intensity_probability_gate_report.dart'
    as probability_gate;

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/combined_intensity_prediction/report.json';
const _defaultMarkdownPath =
    'docs/baselines/combined_intensity_prediction.generated.md';

const _selectedPlumMinimumEvidenceCount = 1;
const _baselinePlumConfig = _PlumMethodConfig(
  methodId: 'plum_like',
  maxMethodId: 'max_jma_style_plum_like',
  radiusKm: 30.0,
  dampingPer10Km: 0.25,
  description: 'baseline replay-recall operating point',
);
const _plumCandidateConfigs = [
  _baselinePlumConfig,
  _PlumMethodConfig(
    methodId: 'plum_like_r20_d0_50',
    maxMethodId: 'max_jma_style_plum_like_r20_d0_50',
    radiusKm: 20.0,
    dampingPer10Km: 0.50,
    description: 'candidate false-positive control from replay grid',
  ),
  _PlumMethodConfig(
    methodId: 'plum_like_r30_d0_50',
    maxMethodId: 'max_jma_style_plum_like_r30_d0_50',
    radiusKm: 30.0,
    dampingPer10Km: 0.50,
    description: 'candidate false-positive control from replay grid',
  ),
];

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildCombinedIntensityPredictionReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(combinedIntensityPredictionMarkdown(report));

  stdout.writeln('wrote combined intensity prediction report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildCombinedIntensityPredictionReportJson({
  String validationDatasetPath = _defaultDatasetPath,
  String modelPath = _defaultModelPath,
  String reportSplit = 'validation',
  bool frozenTestEvaluated = false,
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
  final modelJson =
      jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>;
  final model = _modelFromJson(modelJson);
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictors = {
    for (final config in _plumCandidateConfigs)
      config.methodId: PlumLikeIntensityPredictor(
        radiusKm: config.radiusKm,
        dampingPer10Km: config.dampingPer10Km,
        minimumEvidenceCount: _selectedPlumMinimumEvidenceCount,
      ),
  };

  final p3Static = _MetricAccumulator();
  final jmaStyle = _MetricAccumulator();
  final plumLike = {
    for (final config in _plumCandidateConfigs)
      config.methodId: _MetricAccumulator(),
  };
  final combined = {
    for (final config in _plumCandidateConfigs)
      config.maxMethodId: _MetricAccumulator(),
  };
  var skippedMissingMagnitude = 0;
  var skippedNoSourceEstimate = 0;
  final noPlumPredictionStations = {
    for (final config in _plumCandidateConfigs) config.methodId: 0,
  };
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

      final p3Forecasts = <_StationForecast>[];
      final jmaForecasts = <_StationForecast>[];
      final plumForecasts = {
        for (final config in _plumCandidateConfigs)
          config.methodId: <_StationForecast>[],
      };
      final combinedForecasts = {
        for (final config in _plumCandidateConfigs)
          config.maxMethodId: <_StationForecast>[],
      };

      for (final station in event.stations) {
        final p3Predicted = _predictStaticIntensity(model, estimate, station);
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
        p3Forecasts.add(
          _StationForecast(actual: station.intensity, predicted: p3Predicted),
        );
        jmaForecasts.add(
          _StationForecast(actual: station.intensity, predicted: jmaPredicted),
        );
        for (final config in _plumCandidateConfigs) {
          final plumPrediction = plumPredictors[config.methodId]!.predict(
            targetStation: station,
            observedStations: retainedStations,
          );
          if (plumPrediction.evidenceCount <
              _selectedPlumMinimumEvidenceCount) {
            noPlumPredictionStations[config.methodId] =
                noPlumPredictionStations[config.methodId]! + 1;
          }
          final plumPredicted = plumPrediction.intensity;
          plumForecasts[config.methodId]!.add(
            _StationForecast(
              actual: station.intensity,
              predicted: plumPredicted,
            ),
          );
          combinedForecasts[config.maxMethodId]!.add(
            _StationForecast(
              actual: station.intensity,
              predicted: math.max(jmaPredicted, plumPredicted),
            ),
          );
        }
        stationForecastCount++;
      }

      p3Static.add(_case(actualMax, p3Forecasts));
      jmaStyle.add(_case(actualMax, jmaForecasts));
      for (final config in _plumCandidateConfigs) {
        plumLike[config.methodId]!.add(
          _case(actualMax, plumForecasts[config.methodId]!),
        );
        combined[config.maxMethodId]!.add(
          _case(actualMax, combinedForecasts[config.maxMethodId]!),
        );
      }
    }
  }

  if (p3Static.caseCount == 0) {
    errors.add('no_combined_validation_cases_produced');
  }

  final gateReport = probability_gate.buildStaticIntensityProbabilityGateJson(
    validationDatasetPath: validationDatasetPath,
    modelPath: modelPath,
  );
  if (gateReport['status'] != 'pass') {
    errors.add('probability_gate_report_failed');
  }

  return {
    'schemaVersion': 'combined_intensity_prediction_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'validationDatasetPath': validationDatasetPath,
    'modelPath': modelPath,
    'policy': {
      'split': reportSplit,
      'frozenTestEvaluated': frozenTestEvaluated,
      'productionReady': false,
      'productionUiConnected': false,
      'method':
          'validation-only station-level comparison of static, JMA-style, PLUM-like and max(JMA-style, PLUM-like)',
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime lead-time validation',
      'sourceSemantics':
          'uses P3-estimated source for static and JMA-style branches; PLUM-like branch is source-independent',
    },
    'plumConfig': {
      'radiusKm': _baselinePlumConfig.radiusKm,
      'dampingPer10Km': _baselinePlumConfig.dampingPer10Km,
      'minimumEvidenceCount': _selectedPlumMinimumEvidenceCount,
    },
    'plumOperatingPointCandidates': {
      for (final config in _plumCandidateConfigs)
        config.methodId: {
          'maxMethodId': config.maxMethodId,
          'radiusKm': config.radiusKm,
          'dampingPer10Km': config.dampingPer10Km,
          'minimumEvidenceCount': _selectedPlumMinimumEvidenceCount,
          'description': config.description,
          'diagnosticOnly': true,
          'selectedForProduction': false,
        },
    },
    'coverage': {
      'stationForecastCount': stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoSourceEstimate,
      'noPlumPredictionStations': noPlumPredictionStations,
      'noPlumPredictionStationRates': {
        for (final entry in noPlumPredictionStations.entries)
          entry.key: stationForecastCount == 0
              ? 0.0
              : entry.value / stationForecastCount,
      },
    },
    'methods': {
      'p3_static_raw': _methodJson(p3Static),
      'jma_style_p3_source': _methodJson(jmaStyle),
      for (final config in _plumCandidateConfigs)
        config.methodId: _methodJson(plumLike[config.methodId]!),
      for (final config in _plumCandidateConfigs)
        config.maxMethodId: _methodJson(combined[config.maxMethodId]!),
    },
    'probabilityGate': _probabilityGateJson(gateReport),
    'errors': errors,
  };
}

String combinedIntensityPredictionMarkdown(Map<String, Object?> report) {
  final methods = _map(report['methods']);
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# Combined Intensity Prediction Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `${_map(report['policy'])['split']}`')
    ..writeln(
      '- Frozen test evaluated: `${_map(report['policy'])['frozenTestEvaluated']}`',
    )
    ..writeln('- Production ready: `false`')
    ..writeln('- Production UI connected: `false`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This compares four validation-only station prediction branches on the '
      'same synthetic-reveal validation variants.',
    )
    ..writeln(
      '- `p3_static_raw` is the existing static intensity inversion forecast.',
    )
    ..writeln(
      '- `jma_style_p3_source` applies the JMA-style PGV path using the '
      'P3-estimated source.',
    )
    ..writeln(
      '- `plum_like` propagates observed shaking from retained stations and '
      'does not use source latitude, longitude, depth or magnitude.',
    )
    ..writeln(
      '- `plum_like_r20_d0_50` and `plum_like_r30_d0_50` are replay-grid '
      'false-positive-control candidates. They are not production-selected.',
    )
    ..writeln(
      '- `max_jma_style_plum_like` takes the station-level maximum of the '
      'traditional and PLUM-like branches. It is diagnostic-only.',
    )
    ..writeln()
    ..writeln('## Coverage')
    ..writeln()
    ..writeln('- Station forecasts: `${coverage['stationForecastCount']}`')
    ..writeln(
      '- No-PLUM-prediction station rate (baseline): '
      '`${_pct(_map(coverage['noPlumPredictionStationRates'])['plum_like'])}`',
    )
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln(
      '| Method | Cases | Max class MAE | Station MAE | Underestimate rate | Within 1 class |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
  for (final method in _methodOrder) {
    final summary = _map(_map(methods[method])['summary']);
    buffer.writeln(
      '| `$method` | ${summary['caseCount']} | '
      '${_fmt(summary['maxClassMae'])} | '
      '${_fmt(summary['stationIntensityMae'])} | '
      '${_pct(summary['maxClassUnderestimateRate'])} | '
      '${_pct(summary['maxClassWithinOneAccuracy'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Threshold Comparison')
    ..writeln()
    ..writeln(
      '| Threshold | P3 raw | P3 probability gate | JMA-style | PLUM baseline | PLUM r20/d0.50 | PLUM r30/d0.50 | max baseline | max r20/d0.50 | max r30/d0.50 |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  final gate = _map(report['probabilityGate']);
  for (final threshold in _thresholds) {
    buffer.writeln(
      '| `${threshold.label}` | '
      '${_thresholdSummary(_methodThreshold(methods, 'p3_static_raw', threshold.label))} | '
      '${_thresholdSummary(_map(gate[threshold.label]))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'jma_style_p3_source', threshold.label))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'plum_like', threshold.label))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'plum_like_r20_d0_50', threshold.label))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'plum_like_r30_d0_50', threshold.label))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'max_jma_style_plum_like', threshold.label))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'max_jma_style_plum_like_r20_d0_50', threshold.label))} | '
      '${_thresholdSummary(_methodThreshold(methods, 'max_jma_style_plum_like_r30_d0_50', threshold.label))} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Do not connect this report to production UI, notifications or warning '
      'wording.',
    )
    ..writeln(
      '- The `max(JMA-style, PLUM-like)` branch recovers high-shindo recall by '
      'construction, so it must be judged against false positives before any '
      'frozen-test decision.',
    )
    ..writeln(
      '- Next step: choose a diagnostic operating point by comparing the '
      'synthetic-reveal combined result with the real replay lead-time grid.',
    )
    ..writeln();
  return buffer.toString();
}

Map<String, Object?> _methodJson(_MetricAccumulator metrics) => {
  'summary': metrics.toJson(),
  'thresholds': {
    for (final threshold in _thresholds)
      threshold.label: metrics.thresholdMetrics(threshold).toJson(),
  },
};

Map<String, Object?> _probabilityGateJson(Map<String, Object?> report) {
  final result = <String, Object?>{};
  for (final raw in _list(report['thresholds'])) {
    final row = _map(raw);
    result[row['label'].toString()] = _map(row['probabilityGate']);
  }
  return result;
}

_ForecastCase _case(double actualMax, List<_StationForecast> stationForecasts) {
  final predictedMax = stationForecasts
      .map((station) => station.predicted)
      .fold<double>(-3.0, math.max);
  return _ForecastCase(
    actualMax: actualMax,
    predictedMax: predictedMax,
    stationForecasts: stationForecasts,
  );
}

StaticAttenuationModel _modelFromJson(Map<String, Object?> json) {
  return StaticAttenuationModel(
    modelId: json['modelId']?.toString() ?? 'static_intensity_attenuation_v1',
    logDistanceCoefficient: (json['logDistanceCoefficient']! as num).toDouble(),
    linearDistanceCoefficient: (json['linearDistanceCoefficient']! as num)
        .toDouble(),
    nearDistanceKm: (json['nearDistanceKm']! as num).toDouble(),
    huberDelta: (json['huberDelta']! as num).toDouble(),
    residualScale: (json['residualScale']! as num).toDouble(),
    centroidPenaltyPerKm:
        (json['centroidPenaltyPerKm'] as num?)?.toDouble() ?? 0,
    depthClassesKm: [
      for (final value in _list(json['depthClassesKm']))
        (value as num).toDouble(),
    ],
  );
}

double _predictStaticIntensity(
  StaticAttenuationModel model,
  StaticIntensityLocationEstimate estimate,
  StaticIntensityStation station,
) {
  final surfaceDistance = QuakeCalculator.haversineDistance(
    estimate.latitude,
    estimate.longitude,
    station.latitude,
    station.longitude,
  );
  final distance = math.sqrt(
    surfaceDistance * surfaceDistance + estimate.depthKm * estimate.depthKm,
  );
  return estimate.sourceScale -
      model.logDistanceCoefficient * _log10(distance + model.nearDistanceKm) -
      model.linearDistanceCoefficient * distance;
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'combined_intensity_prediction_report_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'modelPath': modelPath,
  'policy': const {
    'split': 'validation',
    'frozenTestEvaluated': false,
    'productionReady': false,
    'productionUiConnected': false,
  },
  'methods': const {},
  'probabilityGate': const {},
  'coverage': const {},
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

const _methodOrder = [
  'p3_static_raw',
  'jma_style_p3_source',
  'plum_like',
  'plum_like_r20_d0_50',
  'plum_like_r30_d0_50',
  'max_jma_style_plum_like',
  'max_jma_style_plum_like_r20_d0_50',
  'max_jma_style_plum_like_r30_d0_50',
];

class _PlumMethodConfig {
  final String methodId;
  final String maxMethodId;
  final double radiusKm;
  final double dampingPer10Km;
  final String description;

  const _PlumMethodConfig({
    required this.methodId,
    required this.maxMethodId,
    required this.radiusKm,
    required this.dampingPer10Km,
    required this.description,
  });
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

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

double _log10(double value) => math.log(value) / math.ln10;

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

double? _number(Object? value) => value is num ? value.toDouble() : null;

String _fmt(Object? value) {
  final number = _number(value);
  return number == null ? '-' : number.toStringAsFixed(2);
}

String _pct(Object? value) {
  final number = _number(value);
  return number == null ? '-' : '${(number * 100).toStringAsFixed(1)}%';
}

String _thresholdSummary(Map<String, Object?> metrics) {
  return '${_pct(metrics['precision'])} / ${_pct(metrics['recall'])} / '
      '${_pct(metrics['f1'])}';
}

Map<String, Object?> _methodThreshold(
  Map<String, Object?> methods,
  String method,
  String threshold,
) {
  return _map(_map(_map(methods[method])['thresholds'])[threshold]);
}
