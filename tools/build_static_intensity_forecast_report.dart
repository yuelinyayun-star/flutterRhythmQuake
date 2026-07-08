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
const _defaultOutputPath =
    '.dart_tool/static_intensity_forecast_validation/report.json';
const _defaultMarkdownPath =
    'docs/baselines/static_intensity_forecast_validation.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildStaticIntensityForecastValidationJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(staticIntensityForecastValidationMarkdown(report));

  stdout.writeln('wrote static intensity forecast validation report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildStaticIntensityForecastValidationJson({
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

  final overall = _MetricAccumulator();
  final buckets = <String, _MetricAccumulator>{};
  final cases = <Map<String, Object?>>[];

  for (final rawEvent in _list(dataset['events'])) {
    final event = StaticIntensityEvent.fromJson(_map(rawEvent));
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
      if (estimate == null) continue;
      final predictions = <_StationForecast>[];
      for (final station in event.stations) {
        final predicted = _predictStationIntensity(model, estimate, station);
        predictions.add(
          _StationForecast(actual: station.intensity, predicted: predicted),
        );
      }
      final actualMaxClass = JpShindoScale.jmaIndexFromShindo(actualMax);
      final predictedMax = predictions
          .map((station) => station.predicted)
          .fold<double>(-3.0, math.max);
      final predictedMaxClass = JpShindoScale.jmaIndexFromShindo(predictedMax);
      final row = _ForecastCase(
        eventId: event.eventId,
        variantId: variant.variantId,
        maskRate: variant.maskRate,
        stationCount: event.stations.length,
        retainedStationCount: retainedStations.length,
        actualMax: actualMax,
        predictedMax: predictedMax,
        actualMaxClass: actualMaxClass,
        predictedMaxClass: predictedMaxClass,
        stationForecasts: predictions,
      );
      overall.add(row);
      final key = '${(variant.maskRate * 100).round()}pct';
      buckets.putIfAbsent(key, _MetricAccumulator.new).add(row);
      cases.add(row.toSummaryJson());
    }
  }

  if (overall.caseCount == 0) {
    errors.add('no_validation_cases_produced');
  }

  return {
    'schemaVersion': 'static_intensity_forecast_validation_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'modelPath': modelPath,
    'validationDatasetPath': validationDatasetPath,
    'model': {
      'modelId': model.modelId,
      'logDistanceCoefficient': model.logDistanceCoefficient,
      'linearDistanceCoefficient': model.linearDistanceCoefficient,
      'nearDistanceKm': model.nearDistanceKm,
      'centroidPenaltyPerKm': model.centroidPenaltyPerKm,
    },
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime observed intensity',
      'surfaceDefaultAlignment':
          'requires later recalibration before production use',
    },
    'summary': overall.toJson(),
    'byMaskRate': {
      for (final entry in buckets.entries) entry.key: entry.value.toJson(),
    },
    'thresholds': {
      for (final threshold in _thresholds)
        threshold.label: overall.thresholdMetrics(threshold).toJson(),
    },
    'errors': errors,
    'cases': cases,
  };
}

String staticIntensityForecastValidationMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final model = _map(report['model']);
  final buffer = StringBuffer()
    ..writeln('# Static Intensity Forecast Validation')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Model: `${model['modelId']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Cases | ${summary['caseCount']} |')
    ..writeln('| Station forecasts | ${summary['stationForecastCount']} |')
    ..writeln(
      '| Max-shindo class MAE | ${_fmt(summary['maxClassMae'])} classes |',
    )
    ..writeln(
      '| Max-shindo numeric MAE | ${_fmt(summary['maxIntensityMae'])} shindo |',
    )
    ..writeln(
      '| Station intensity MAE | ${_fmt(summary['stationIntensityMae'])} shindo |',
    )
    ..writeln(
      '| Max-shindo underestimation rate | ${_pct(summary['maxClassUnderestimateRate'])} |',
    )
    ..writeln(
      '| Exact max-shindo class accuracy | ${_pct(summary['maxClassExactAccuracy'])} |',
    )
    ..writeln(
      '| Within 1 class accuracy | ${_pct(summary['maxClassWithinOneAccuracy'])} |',
    )
    ..writeln()
    ..writeln('## Thresholds')
    ..writeln()
    ..writeln('| Threshold | Precision | Recall | F1 | TP | FP | FN |')
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  final thresholds = _map(report['thresholds']);
  for (final threshold in _thresholds) {
    final metrics = _map(thresholds[threshold.label]);
    buffer.writeln(
      '| `${threshold.label}` | ${_pct(metrics['precision'])} | '
      '${_pct(metrics['recall'])} | ${_pct(metrics['f1'])} | '
      '${metrics['truePositive']} | ${metrics['falsePositive']} | '
      '${metrics['falseNegative']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## By Mask Rate')
    ..writeln()
    ..writeln(
      '| Mask | Cases | Max class MAE | Station MAE | Underestimate rate |',
    )
    ..writeln('| ---: | ---: | ---: | ---: | ---: |');
  final byMask = _map(report['byMaskRate']);
  for (final key in byMask.keys.toList()..sort()) {
    final values = _map(byMask[key]);
    buffer.writeln(
      '| `$key` | ${values['caseCount']} | '
      '${_fmt(values['maxClassMae'])} | '
      '${_fmt(values['stationIntensityMae'])} | '
      '${_pct(values['maxClassUnderestimateRate'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This is a validation-only forecast metric report for the static '
      'intensity baseline.',
    )
    ..writeln(
      '- It uses final peak station intensity with synthetic reveal masks, so '
      'it must not be described as realtime measured lead time.',
    )
    ..writeln(
      '- Frozen test remains unopened and production UI/notification wording '
      'must not consume this report directly.',
    )
    ..writeln();
  return buffer.toString();
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'static_intensity_forecast_validation_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'modelPath': modelPath,
  'errors': errors,
  'summary': const {},
  'thresholds': const {},
  'byMaskRate': const {},
  'cases': const [],
};

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

double _predictStationIntensity(
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

class _ForecastCase {
  final String eventId;
  final String variantId;
  final double maskRate;
  final int stationCount;
  final int retainedStationCount;
  final double actualMax;
  final double predictedMax;
  final int actualMaxClass;
  final int predictedMaxClass;
  final List<_StationForecast> stationForecasts;

  const _ForecastCase({
    required this.eventId,
    required this.variantId,
    required this.maskRate,
    required this.stationCount,
    required this.retainedStationCount,
    required this.actualMax,
    required this.predictedMax,
    required this.actualMaxClass,
    required this.predictedMaxClass,
    required this.stationForecasts,
  });

  Map<String, Object?> toSummaryJson() => {
    'eventId': eventId,
    'variantId': variantId,
    'maskRate': maskRate,
    'stationCount': stationCount,
    'retainedStationCount': retainedStationCount,
    'actualMax': actualMax,
    'predictedMax': predictedMax,
    'actualMaxClass': actualMaxClass,
    'predictedMaxClass': predictedMaxClass,
    'maxClassError': predictedMaxClass - actualMaxClass,
    'stationIntensityMae':
        stationForecasts
            .map((station) => (station.predicted - station.actual).abs())
            .fold<double>(0, (sum, value) => sum + value) /
        stationForecasts.length,
  };
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
  _Threshold('shindo1', 0.5),
  _Threshold('shindo2', 1.5),
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
