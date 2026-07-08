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
    '.dart_tool/static_intensity_calibration/report.json';
const _defaultMarkdownPath =
    'docs/baselines/static_intensity_calibration.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildStaticIntensityCalibrationJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(staticIntensityCalibrationMarkdown(report));

  stdout.writeln('wrote static intensity calibration report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildStaticIntensityCalibrationJson({
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
  final forecasts = _buildForecastCases(dataset, model);
  if (forecasts.isEmpty) errors.add('no_validation_cases_produced');

  final rows = [
    for (final offset in _calibrationOffsets)
      _CalibrationRow.fromCases(offset: offset, cases: forecasts),
  ];
  final baseline = rows.firstWhere((row) => row.offset == 0);
  final recommended = _selectRecommended(rows);

  return {
    'schemaVersion': 'static_intensity_calibration_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'modelPath': modelPath,
    'validationDatasetPath': validationDatasetPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'calibrationType': 'global_additive_intensity_offset_scan',
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime observed intensity',
      'surfaceDefaultAlignment':
          'diagnostic recalibration target before production use',
    },
    'baselineOffset': baseline.toJson(),
    'recommendedDiagnosticOffset': recommended.toJson(),
    'offsets': [for (final row in rows) row.toJson()],
    'errors': errors,
  };
}

String staticIntensityCalibrationMarkdown(Map<String, Object?> report) {
  final baseline = _map(report['baselineOffset']);
  final recommended = _map(report['recommendedDiagnosticOffset']);
  final buffer = StringBuffer()
    ..writeln('# Static Intensity Calibration')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This is a validation-only global additive intensity-offset scan.',
    )
    ..writeln(
      '- It uses final peak station intensity with synthetic reveal masks, so '
      'it is not realtime lead-time validation.',
    )
    ..writeln(
      '- The recommended offset is diagnostic-only and must not be consumed by '
      'production UI, notifications or warning wording.',
    )
    ..writeln()
    ..writeln('## Baseline vs Recommended')
    ..writeln()
    ..writeln('| Metric | Baseline offset 0.00 | Recommended |')
    ..writeln('| --- | ---: | ---: |')
    ..writeln(
      '| Offset | `${_fmt(baseline['offset'])}` | `${_fmt(recommended['offset'])}` |',
    )
    ..writeln(
      '| Max class MAE | ${_fmt(baseline['maxClassMae'])} | ${_fmt(recommended['maxClassMae'])} |',
    )
    ..writeln(
      '| Numeric max MAE | ${_fmt(baseline['maxIntensityMae'])} | ${_fmt(recommended['maxIntensityMae'])} |',
    )
    ..writeln(
      '| Station MAE | ${_fmt(baseline['stationIntensityMae'])} | ${_fmt(recommended['stationIntensityMae'])} |',
    )
    ..writeln(
      '| Underestimate rate | ${_pct(baseline['maxClassUnderestimateRate'])} | ${_pct(recommended['maxClassUnderestimateRate'])} |',
    )
    ..writeln(
      '| High-shindo objective | ${_fmt(baseline['highShindoObjective'])} | ${_fmt(recommended['highShindoObjective'])} |',
    )
    ..writeln()
    ..writeln('## Threshold Tradeoff')
    ..writeln()
    ..writeln(
      '| Offset | Shindo3 P/R/F1 | Shindo4 P/R/F1 | Shindo5- P/R/F1 | Max MAE | Under |',
    )
    ..writeln('| ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final row in _list(report['offsets'])) {
    final values = _map(row);
    final thresholds = _map(values['thresholds']);
    final shindo3 = _map(thresholds['shindo3']);
    final shindo4 = _map(thresholds['shindo4']);
    final shindo5 = _map(thresholds['shindo5-']);
    buffer.writeln(
      '| `${_fmt(values['offset'])}` | '
      '${_thresholdSummary(shindo3)} | '
      '${_thresholdSummary(shindo4)} | '
      '${_thresholdSummary(shindo5)} | '
      '${_fmt(values['maxClassMae'])} | '
      '${_pct(values['maxClassUnderestimateRate'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Next Step')
    ..writeln()
    ..writeln(
      '- Use this report to choose explicit acceptance criteria, then rerun '
      'on a surface-default-aligned recalibrated model before opening the '
      'frozen test split.',
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
          ),
      ];
      cases.add(
        _ForecastCase(
          actualMax: actualMax,
          predictedMax: stationForecasts
              .map((station) => station.predicted)
              .fold<double>(-3.0, math.max),
          stationForecasts: stationForecasts,
        ),
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

_CalibrationRow _selectRecommended(List<_CalibrationRow> rows) {
  final candidates = rows.where((row) {
    final shindo4 = row.thresholds['shindo4']!;
    final shindo5 = row.thresholds['shindo5-']!;
    return shindo4.recall >= 0.65 &&
        shindo5.recall >= 0.45 &&
        row.maxClassMae <= 0.9;
  }).toList();
  final pool = candidates.isEmpty ? rows : candidates;
  pool.sort((left, right) {
    final objectiveOrder = left.highShindoObjective.compareTo(
      right.highShindoObjective,
    );
    if (objectiveOrder != 0) return objectiveOrder;
    return left.maxClassMae.compareTo(right.maxClassMae);
  });
  return pool.first;
}

class _ForecastCase {
  final double actualMax;
  final double predictedMax;
  final List<_StationForecast> stationForecasts;

  const _ForecastCase({
    required this.actualMax,
    required this.predictedMax,
    required this.stationForecasts,
  });
}

class _StationForecast {
  final double actual;
  final double predicted;

  const _StationForecast({required this.actual, required this.predicted});
}

class _CalibrationRow {
  final double offset;
  final int caseCount;
  final int stationForecastCount;
  final double maxClassMae;
  final double maxIntensityMae;
  final double stationIntensityMae;
  final double maxClassUnderestimateRate;
  final double maxClassExactAccuracy;
  final double maxClassWithinOneAccuracy;
  final Map<String, _ThresholdMetrics> thresholds;

  const _CalibrationRow({
    required this.offset,
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

  factory _CalibrationRow.fromCases({
    required double offset,
    required List<_ForecastCase> cases,
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
      final predictedMax = item.predictedMax + offset;
      final predictedMaxClass = JpShindoScale.jmaIndexFromShindo(predictedMax);
      final classError = predictedMaxClass - actualMaxClass;
      maxClassErrors.add(classError.abs());
      maxIntensityErrors.add((predictedMax - item.actualMax).abs());
      if (classError < 0) underestimatedMaxClass++;
      if (classError == 0) exactMaxClass++;
      if (classError.abs() <= 1) withinOneMaxClass++;
      for (final station in item.stationForecasts) {
        stationForecastCount++;
        final predicted = station.predicted + offset;
        stationIntensityErrors.add((predicted - station.actual).abs());
        for (final threshold in _thresholds) {
          thresholdCounts[threshold.label]!.add(
            actual: station.actual >= threshold.value,
            predicted: predicted >= threshold.value,
          );
        }
      }
    }

    return _CalibrationRow(
      offset: offset,
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

  double get highShindoObjective {
    final shindo4 = thresholds['shindo4']!;
    final shindo5 = thresholds['shindo5-']!;
    return (1 - shindo4.f1) + (1 - shindo5.f1) + maxClassMae * 0.25;
  }

  Map<String, Object?> toJson() => {
    'offset': offset,
    'caseCount': caseCount,
    'stationForecastCount': stationForecastCount,
    'maxClassMae': maxClassMae,
    'maxIntensityMae': maxIntensityMae,
    'stationIntensityMae': stationIntensityMae,
    'maxClassUnderestimateRate': maxClassUnderestimateRate,
    'maxClassExactAccuracy': maxClassExactAccuracy,
    'maxClassWithinOneAccuracy': maxClassWithinOneAccuracy,
    'highShindoObjective': highShindoObjective,
    'thresholds': {
      for (final entry in thresholds.entries) entry.key: entry.value.toJson(),
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

const _calibrationOffsets = [
  -1.0,
  -0.9,
  -0.8,
  -0.7,
  -0.6,
  -0.5,
  -0.4,
  -0.3,
  -0.2,
  -0.1,
  0.0,
  0.1,
  0.2,
  0.3,
  0.4,
  0.5,
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

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'static_intensity_calibration_v1',
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
  'baselineOffset': const {},
  'recommendedDiagnosticOffset': const {},
  'offsets': const [],
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

String _thresholdSummary(Map<String, Object?> metrics) {
  return '${_pct(metrics['precision'])} / '
      '${_pct(metrics['recall'])} / '
      '${_pct(metrics['f1'])}';
}
