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
    '.dart_tool/static_intensity_distance_residual_calibration/report.json';
const _defaultMarkdownPath =
    'docs/baselines/static_intensity_distance_residual_calibration.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildStaticIntensityDistanceResidualCalibrationJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    staticIntensityDistanceResidualCalibrationMarkdown(report),
  );

  stdout.writeln('wrote static intensity distance residual calibration report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildStaticIntensityDistanceResidualCalibrationJson({
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
  final cases = _buildForecastCases(dataset, model);
  if (cases.isEmpty) errors.add('no_validation_cases_produced');

  final residuals = _distanceResiduals(cases);
  final corrections = {
    for (final entry in residuals.entries) entry.key: -entry.value.meanResidual,
  };
  final targetedCorrections = {
    for (final key in _distanceBucketOrder)
      key: key == 'gt_200km' ? corrections[key] ?? 0.0 : 0.0,
  };

  final baseline = _Metrics.fromCases(
    cases: cases,
    correctionForStation: (_) => 0,
  );
  final allDistanceCorrected = _Metrics.fromCases(
    cases: cases,
    correctionForStation: (station) =>
        corrections[_distanceBucket(station.distanceKm)] ?? 0,
  );
  final farDistanceCorrected = _Metrics.fromCases(
    cases: cases,
    correctionForStation: (station) =>
        targetedCorrections[_distanceBucket(station.distanceKm)] ?? 0,
  );

  return {
    'schemaVersion': 'static_intensity_distance_residual_calibration_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'modelPath': modelPath,
    'validationDatasetPath': validationDatasetPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'calibrationType': 'station_distance_residual_correction',
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime observed intensity',
      'productionUse':
          'diagnostic only; do not apply to runtime intensity fields or warnings',
    },
    'summary': {
      'baseline': baseline.toJson(),
      'allDistanceCorrected': allDistanceCorrected.toJson(),
      'farDistanceCorrected': farDistanceCorrected.toJson(),
    },
    'distanceBuckets': [
      for (final key in _distanceBucketOrder)
        if (residuals[key] != null)
          {
            'bucket': key,
            'correction': corrections[key],
            'targetedCorrection': targetedCorrections[key],
            ...residuals[key]!.toJson(),
          },
    ],
    'errors': errors,
  };
}

String staticIntensityDistanceResidualCalibrationMarkdown(
  Map<String, Object?> report,
) {
  final summary = _map(report['summary']);
  final baseline = _map(summary['baseline']);
  final allDistance = _map(summary['allDistanceCorrected']);
  final farDistance = _map(summary['farDistanceCorrected']);
  final buffer = StringBuffer()
    ..writeln('# Static Intensity Distance Residual Calibration')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This is a validation-only station-distance residual correction '
      'diagnostic.',
    )
    ..writeln(
      '- It must not be applied to runtime intensity fields, UI, notifications '
      'or warning wording.',
    )
    ..writeln(
      '- It uses final peak station intensity with synthetic reveal masks, so '
      'it is not realtime lead-time validation.',
    )
    ..writeln()
    ..writeln('## Overall')
    ..writeln()
    ..writeln(
      '| Metric | Baseline | All-distance corrected | `gt_200km` corrected |',
    )
    ..writeln('| --- | ---: | ---: | ---: |');
  for (final metric in const [
    ('Max class MAE', 'maxClassMae', 'plain'),
    ('Numeric max MAE', 'maxIntensityMae', 'plain'),
    ('Station MAE', 'stationIntensityMae', 'plain'),
    ('Underestimate rate', 'maxClassUnderestimateRate', 'pct'),
    ('Exact accuracy', 'maxClassExactAccuracy', 'pct'),
    ('Within-one accuracy', 'maxClassWithinOneAccuracy', 'pct'),
  ]) {
    buffer.writeln(
      '| ${metric.$1} | ${_formatMetric(baseline[metric.$2], metric.$3)} | '
      '${_formatMetric(allDistance[metric.$2], metric.$3)} | '
      '${_formatMetric(farDistance[metric.$2], metric.$3)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## High-Shindo Thresholds')
    ..writeln()
    ..writeln(
      '| Threshold | Baseline P/R/F1 | All-distance P/R/F1 | `gt_200km` P/R/F1 |',
    )
    ..writeln('| --- | ---: | ---: | ---: |');
  final baselineThresholds = _map(baseline['thresholds']);
  final allThresholds = _map(allDistance['thresholds']);
  final farThresholds = _map(farDistance['thresholds']);
  for (final threshold in const ['shindo3', 'shindo4', 'shindo5-']) {
    buffer.writeln(
      '| `$threshold` | '
      '${_thresholdSummary(_map(baselineThresholds[threshold]))} | '
      '${_thresholdSummary(_map(allThresholds[threshold]))} | '
      '${_thresholdSummary(_map(farThresholds[threshold]))} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Distance Buckets')
    ..writeln()
    ..writeln(
      '| Bucket | Count | Mean residual | Correction | Targeted correction | MAE | Shindo4 P/R/F1 | Shindo5- P/R/F1 |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['distanceBuckets'])) {
    final bucket = _map(raw);
    final thresholds = _map(bucket['thresholds']);
    buffer.writeln(
      '| `${bucket['bucket']}` | ${bucket['count']} | '
      '${_fmt(bucket['meanResidual'])} | ${_fmt(bucket['correction'])} | '
      '${_fmt(bucket['targetedCorrection'])} | ${_fmt(bucket['mae'])} | '
      '${_thresholdSummary(_map(thresholds['shindo4']))} | '
      '${_thresholdSummary(_map(thresholds['shindo5-']))} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Next Step')
    ..writeln()
    ..writeln(
      '- If residual correction reduces high-shindo false positives without '
      'damaging maximum-shindo metrics, convert it into a probability '
      'calibration feature. Otherwise keep raw intensity unchanged and use '
      'distance only as confidence metadata.',
    )
    ..writeln();
  return buffer.toString();
}

List<_ForecastCase> _buildForecastCases(
  Map<String, Object?> dataset,
  StaticAttenuationModel model,
) {
  final locator = StaticIntensityLocator(model: model);
  final cases = <_ForecastCase>[];
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
      final stationForecasts = [
        for (final station in event.stations)
          _StationForecast(
            actual: station.intensity,
            predicted: _predictStationIntensity(model, estimate, station),
            distanceKm: _stationDistanceKm(estimate, station),
          ),
      ];
      cases.add(
        _ForecastCase(actualMax: actualMax, stationForecasts: stationForecasts),
      );
    }
  }
  return cases;
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

double _stationDistanceKm(
  StaticIntensityLocationEstimate estimate,
  StaticIntensityStation station,
) {
  final surfaceDistance = QuakeCalculator.haversineDistance(
    estimate.latitude,
    estimate.longitude,
    station.latitude,
    station.longitude,
  );
  return math.sqrt(
    surfaceDistance * surfaceDistance + estimate.depthKm * estimate.depthKm,
  );
}

Map<String, _DistanceResidualBucket> _distanceResiduals(
  List<_ForecastCase> cases,
) {
  final buckets = <String, _DistanceResidualBucket>{};
  for (final item in cases) {
    for (final station in item.stationForecasts) {
      buckets
          .putIfAbsent(
            _distanceBucket(station.distanceKm),
            _DistanceResidualBucket.new,
          )
          .add(station);
    }
  }
  return buckets;
}

class _ForecastCase {
  final double actualMax;
  final List<_StationForecast> stationForecasts;

  const _ForecastCase({
    required this.actualMax,
    required this.stationForecasts,
  });
}

class _StationForecast {
  final double actual;
  final double predicted;
  final double distanceKm;

  const _StationForecast({
    required this.actual,
    required this.predicted,
    required this.distanceKm,
  });
}

class _Metrics {
  final int caseCount;
  final int stationForecastCount;
  final double maxClassMae;
  final double maxIntensityMae;
  final double stationIntensityMae;
  final double maxClassUnderestimateRate;
  final double maxClassExactAccuracy;
  final double maxClassWithinOneAccuracy;
  final Map<String, _ThresholdMetrics> thresholds;

  const _Metrics({
    required this.caseCount,
    required this.stationForecastCount,
    required this.maxClassMae,
    required this.maxIntensityMae,
    required this.stationIntensityMae,
    required this.maxClassUnderestimateRate,
    required this.maxClassExactAccuracy,
    required this.maxClassWithinOneAccuracy,
    required this.thresholds,
  });

  factory _Metrics.fromCases({
    required List<_ForecastCase> cases,
    required double Function(_StationForecast station) correctionForStation,
  }) {
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
    for (final item in cases) {
      final actualMaxClass = JpShindoScale.jmaIndexFromShindo(item.actualMax);
      final correctedPredictions = [
        for (final station in item.stationForecasts)
          station.predicted + correctionForStation(station),
      ];
      final predictedMax = correctedPredictions.fold<double>(-3.0, math.max);
      final predictedMaxClass = JpShindoScale.jmaIndexFromShindo(predictedMax);
      final classError = predictedMaxClass - actualMaxClass;
      maxClassErrors.add(classError.abs());
      maxIntensityErrors.add((predictedMax - item.actualMax).abs());
      if (classError < 0) underestimatedMaxClass++;
      if (classError == 0) exactMaxClass++;
      if (classError.abs() <= 1) withinOneMaxClass++;
      for (var i = 0; i < item.stationForecasts.length; i++) {
        stationForecastCount++;
        final station = item.stationForecasts[i];
        final predicted = correctedPredictions[i];
        stationIntensityErrors.add((predicted - station.actual).abs());
        for (final threshold in _thresholds) {
          thresholdCounts[threshold.label]!.add(
            actual: station.actual >= threshold.value,
            predicted: predicted >= threshold.value,
          );
        }
      }
    }
    return _Metrics(
      caseCount: cases.length,
      stationForecastCount: stationForecastCount,
      maxClassMae: _mean(maxClassErrors.map((value) => value.toDouble())),
      maxIntensityMae: _mean(maxIntensityErrors),
      stationIntensityMae: _mean(stationIntensityErrors),
      maxClassUnderestimateRate: cases.isEmpty
          ? 0.0
          : underestimatedMaxClass / cases.length,
      maxClassExactAccuracy: cases.isEmpty ? 0.0 : exactMaxClass / cases.length,
      maxClassWithinOneAccuracy: cases.isEmpty
          ? 0.0
          : withinOneMaxClass / cases.length,
      thresholds: {
        for (final entry in thresholdCounts.entries)
          entry.key: entry.value.toMetrics(),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'caseCount': caseCount,
    'stationForecastCount': stationForecastCount,
    'maxClassMae': maxClassMae,
    'maxIntensityMae': maxIntensityMae,
    'stationIntensityMae': stationIntensityMae,
    'maxClassUnderestimateRate': maxClassUnderestimateRate,
    'maxClassExactAccuracy': maxClassExactAccuracy,
    'maxClassWithinOneAccuracy': maxClassWithinOneAccuracy,
    'thresholds': {
      for (final entry in thresholds.entries) entry.key: entry.value.toJson(),
    },
  };
}

class _DistanceResidualBucket {
  final residuals = <double>[];
  final errors = <double>[];
  final thresholdCounts = {
    for (final threshold in _thresholds) threshold.label: _ThresholdCounts(),
  };

  void add(_StationForecast station) {
    final residual = station.predicted - station.actual;
    residuals.add(residual);
    errors.add(residual.abs());
    for (final threshold in _thresholds) {
      thresholdCounts[threshold.label]!.add(
        actual: station.actual >= threshold.value,
        predicted: station.predicted >= threshold.value,
      );
    }
  }

  double get meanResidual => _mean(residuals);

  Map<String, Object?> toJson() => {
    'count': residuals.length,
    'meanResidual': meanResidual,
    'mae': _mean(errors),
    'thresholds': {
      for (final entry in thresholdCounts.entries)
        entry.key: entry.value.toMetrics().toJson(),
    },
  };
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

const _distanceBucketOrder = ['0_50km', '50_100km', '100_200km', 'gt_200km'];

String _distanceBucket(double distanceKm) {
  if (distanceKm <= 50) return '0_50km';
  if (distanceKm <= 100) return '50_100km';
  if (distanceKm <= 200) return '100_200km';
  return 'gt_200km';
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

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'static_intensity_distance_residual_calibration_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'modelPath': modelPath,
  'errors': errors,
  'policy': const {
    'split': 'validation',
    'frozenTestEvaluated': false,
    'productionReady': false,
  },
  'summary': const {},
  'distanceBuckets': const [],
};

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

String _formatMetric(Object? value, String kind) =>
    kind == 'pct' ? _pct(value) : _fmt(value);

String _thresholdSummary(Map<String, Object?> metrics) {
  return '${_pct(metrics['precision'])} / '
      '${_pct(metrics['recall'])} / '
      '${_pct(metrics['f1'])}';
}
