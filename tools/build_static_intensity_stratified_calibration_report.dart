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
    '.dart_tool/static_intensity_stratified_calibration/report.json';
const _defaultMarkdownPath =
    'docs/baselines/static_intensity_stratified_calibration.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildStaticIntensityStratifiedCalibrationJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    staticIntensityStratifiedCalibrationMarkdown(report),
  );

  stdout.writeln('wrote static intensity stratified calibration report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildStaticIntensityStratifiedCalibrationJson({
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

  final baseline = _CalibrationMetrics.fromCases(
    cases: cases,
    offsetForCase: (_) => 0,
  );
  final strata = _buildStrata(cases);
  final selections = <String, _StratumSelection>{};
  for (final entry in strata.entries) {
    selections[entry.key] = _selectStratumOffset(entry.key, entry.value);
  }
  final stratified = _CalibrationMetrics.fromCases(
    cases: cases,
    offsetForCase: (item) => selections[item.stratumKey]?.selectedOffset ?? 0,
  );
  final stationDistanceDiagnostics = _stationDistanceDiagnostics(cases);

  return {
    'schemaVersion': 'static_intensity_stratified_calibration_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'modelPath': modelPath,
    'validationDatasetPath': validationDatasetPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'calibrationType':
          'predicted_max_class_and_location_uncertainty_stratified_offset_scan',
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime observed intensity',
      'selectionPolicy':
          'diagnostic safe-improvement only; fallback to offset 0 when constraints fail',
    },
    'summary': {
      'baseline': baseline.toJson(),
      'stratified': stratified.toJson(),
      'changedStrata': selections.values
          .where((selection) => selection.selectedOffset != 0)
          .length,
      'totalStrata': selections.length,
    },
    'strata': [
      for (final selection
          in selections.values.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
        selection.toJson(),
    ],
    'stationDistanceDiagnostics': stationDistanceDiagnostics,
    'errors': errors,
  };
}

String staticIntensityStratifiedCalibrationMarkdown(
  Map<String, Object?> report,
) {
  final summary = _map(report['summary']);
  final baseline = _map(summary['baseline']);
  final stratified = _map(summary['stratified']);
  final buffer = StringBuffer()
    ..writeln('# Static Intensity Stratified Calibration')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln(
      '- Changed strata: `${summary['changedStrata']}/${summary['totalStrata']}`',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This is a validation-only stratified offset scan by predicted maximum '
      'class and location-uncertainty bucket.',
    )
    ..writeln(
      '- It remains diagnostic-only: no production coordinate, UI, notification '
      'or warning wording may consume these offsets.',
    )
    ..writeln(
      '- It uses final peak station intensity with synthetic reveal masks, so '
      'it is not realtime lead-time validation.',
    )
    ..writeln()
    ..writeln('## Overall')
    ..writeln()
    ..writeln('| Metric | Baseline | Stratified |')
    ..writeln('| --- | ---: | ---: |')
    ..writeln(
      '| Max class MAE | ${_fmt(baseline['maxClassMae'])} | ${_fmt(stratified['maxClassMae'])} |',
    )
    ..writeln(
      '| Numeric max MAE | ${_fmt(baseline['maxIntensityMae'])} | ${_fmt(stratified['maxIntensityMae'])} |',
    )
    ..writeln(
      '| Station MAE | ${_fmt(baseline['stationIntensityMae'])} | ${_fmt(stratified['stationIntensityMae'])} |',
    )
    ..writeln(
      '| Underestimate rate | ${_pct(baseline['maxClassUnderestimateRate'])} | ${_pct(stratified['maxClassUnderestimateRate'])} |',
    )
    ..writeln(
      '| Exact / within-one | ${_pct(baseline['maxClassExactAccuracy'])} / ${_pct(baseline['maxClassWithinOneAccuracy'])} | ${_pct(stratified['maxClassExactAccuracy'])} / ${_pct(stratified['maxClassWithinOneAccuracy'])} |',
    )
    ..writeln()
    ..writeln('## High-Shindo Thresholds')
    ..writeln()
    ..writeln('| Threshold | Baseline P/R/F1 | Stratified P/R/F1 |')
    ..writeln('| --- | ---: | ---: |');
  final baselineThresholds = _map(baseline['thresholds']);
  final stratifiedThresholds = _map(stratified['thresholds']);
  for (final threshold in const ['shindo3', 'shindo4', 'shindo5-']) {
    buffer.writeln(
      '| `$threshold` | '
      '${_thresholdSummary(_map(baselineThresholds[threshold]))} | '
      '${_thresholdSummary(_map(stratifiedThresholds[threshold]))} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Strata')
    ..writeln()
    ..writeln(
      '| Stratum | Cases | Offset | Baseline MAE | Selected MAE | Baseline under | Selected under |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['strata'])) {
    final row = _map(raw);
    final before = _map(row['baseline']);
    final after = _map(row['selected']);
    buffer.writeln(
      '| `${row['key']}` | ${row['caseCount']} | `${_fmt(row['selectedOffset'])}` | '
      '${_fmt(before['maxClassMae'])} | ${_fmt(after['maxClassMae'])} | '
      '${_pct(before['maxClassUnderestimateRate'])} | '
      '${_pct(after['maxClassUnderestimateRate'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Station Distance Diagnostics')
    ..writeln()
    ..writeln(
      '| Distance | Count | Mean residual | MAE | Shindo4 P/R/F1 | Shindo5- P/R/F1 |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['stationDistanceDiagnostics'])) {
    final row = _map(raw);
    final thresholds = _map(row['thresholds']);
    buffer.writeln(
      '| `${row['bucket']}` | ${row['count']} | '
      '${_fmt(row['meanResidual'])} | ${_fmt(row['mae'])} | '
      '${_thresholdSummary(_map(thresholds['shindo4']))} | '
      '${_thresholdSummary(_map(thresholds['shindo5-']))} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Next Step')
    ..writeln()
    ..writeln(
      '- If the stratified offsets improve high-shindo precision without '
      'materially increasing underestimation, promote the same buckets to a '
      'probability-calibration experiment. Otherwise keep the baseline and '
      'add more features rather than hiding the error with offsets.',
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
      final predictedMax = stationForecasts
          .map((station) => station.predicted)
          .fold<double>(-3.0, math.max);
      cases.add(
        _ForecastCase(
          actualMax: actualMax,
          predictedMax: predictedMax,
          p90RadiusKm: estimate.p90RadiusKm,
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

Map<String, List<_ForecastCase>> _buildStrata(List<_ForecastCase> cases) {
  final result = <String, List<_ForecastCase>>{};
  for (final item in cases) {
    result.putIfAbsent(item.stratumKey, () => []).add(item);
  }
  return result;
}

_StratumSelection _selectStratumOffset(String key, List<_ForecastCase> cases) {
  final baseline = _CalibrationMetrics.fromCases(
    cases: cases,
    offsetForCase: (_) => 0,
  );
  final rows = [
    for (final offset in _calibrationOffsets)
      _CalibrationMetrics.fromCases(cases: cases, offsetForCase: (_) => offset),
  ];
  final allowed = rows.where((row) {
    final baselineShindo4 = baseline.thresholds['shindo4']!;
    final baselineShindo5 = baseline.thresholds['shindo5-']!;
    final rowShindo4 = row.thresholds['shindo4']!;
    final rowShindo5 = row.thresholds['shindo5-']!;
    return row.maxClassMae <= baseline.maxClassMae + 0.12 &&
        row.stationIntensityMae <= baseline.stationIntensityMae + 0.05 &&
        row.maxClassUnderestimateRate <=
            math.min(0.95, baseline.maxClassUnderestimateRate + 0.08) &&
        rowShindo4.falsePositive <= baselineShindo4.falsePositive &&
        rowShindo5.falsePositive <= baselineShindo5.falsePositive &&
        rowShindo4.recall >= math.max(0, baselineShindo4.recall - 0.1) &&
        rowShindo5.recall >= math.max(0, baselineShindo5.recall - 0.15);
  }).toList();
  final pool = allowed.isEmpty ? [baseline] : allowed;
  pool.sort((left, right) {
    final objectiveOrder = left.highShindoObjective.compareTo(
      right.highShindoObjective,
    );
    if (objectiveOrder != 0) return objectiveOrder;
    return left.maxClassMae.compareTo(right.maxClassMae);
  });
  return _StratumSelection(
    key: key,
    caseCount: cases.length,
    selectedOffset: pool.first.offset,
    baseline: baseline,
    selected: pool.first,
  );
}

List<Map<String, Object?>> _stationDistanceDiagnostics(
  List<_ForecastCase> cases,
) {
  final buckets = <String, _StationDistanceBucket>{};
  for (final item in cases) {
    for (final station in item.stationForecasts) {
      buckets
          .putIfAbsent(
            _distanceBucket(station.distanceKm),
            _StationDistanceBucket.new,
          )
          .add(station);
    }
  }
  return [
    for (final key in _distanceBucketOrder)
      if (buckets[key] != null) {'bucket': key, ...buckets[key]!.toJson()},
  ];
}

class _ForecastCase {
  final double actualMax;
  final double predictedMax;
  final double p90RadiusKm;
  final List<_StationForecast> stationForecasts;

  const _ForecastCase({
    required this.actualMax,
    required this.predictedMax,
    required this.p90RadiusKm,
    required this.stationForecasts,
  });

  String get predictedMaxBand {
    final predictedClass = JpShindoScale.jmaIndexFromShindo(predictedMax);
    if (predictedClass <= 2) return 'pred_le_2';
    if (predictedClass == 3) return 'pred_3';
    return 'pred_ge_4';
  }

  String get uncertaintyBucket {
    if (p90RadiusKm <= 25) return 'p90_le_25km';
    if (p90RadiusKm <= 50) return 'p90_25_50km';
    if (p90RadiusKm <= 100) return 'p90_50_100km';
    return 'p90_gt_100km';
  }

  String get stratumKey => '$predictedMaxBand/$uncertaintyBucket';
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

class _CalibrationMetrics {
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

  const _CalibrationMetrics({
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

  factory _CalibrationMetrics.fromCases({
    required List<_ForecastCase> cases,
    required double Function(_ForecastCase item) offsetForCase,
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
    var representativeOffset = 0.0;
    for (final item in cases) {
      final offset = offsetForCase(item);
      representativeOffset = offset;
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
    return _CalibrationMetrics(
      offset: representativeOffset,
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
    return (1 - shindo4.precision) * 0.7 +
        (1 - shindo5.precision) * 0.7 +
        (1 - shindo4.recall) * 0.3 +
        (1 - shindo5.recall) * 0.3 +
        maxClassMae * 0.25 +
        maxClassUnderestimateRate * 0.25;
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

class _StratumSelection {
  final String key;
  final int caseCount;
  final double selectedOffset;
  final _CalibrationMetrics baseline;
  final _CalibrationMetrics selected;

  const _StratumSelection({
    required this.key,
    required this.caseCount,
    required this.selectedOffset,
    required this.baseline,
    required this.selected,
  });

  Map<String, Object?> toJson() => {
    'key': key,
    'caseCount': caseCount,
    'selectedOffset': selectedOffset,
    'baseline': baseline.toJson(),
    'selected': selected.toJson(),
  };
}

class _StationDistanceBucket {
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

  Map<String, Object?> toJson() => {
    'count': residuals.length,
    'meanResidual': _mean(residuals),
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
  'schemaVersion': 'static_intensity_stratified_calibration_v1',
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
  'strata': const [],
  'stationDistanceDiagnostics': const [],
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
