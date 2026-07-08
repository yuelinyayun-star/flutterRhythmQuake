import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultOutputPath = '.dart_tool/plum_like_intensity/report.json';
const _defaultMarkdownPath = 'docs/baselines/plum_like_intensity.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumLikeIntensityReportJson(
    validationDatasetPath: datasetPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumLikeIntensityReportMarkdown(report));

  stdout.writeln('wrote PLUM-like intensity report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumLikeIntensityReportJson({
  String validationDatasetPath = _defaultDatasetPath,
  List<PlumLikeReportConfig>? configs,
}) {
  final errors = <String>[];
  final datasetFile = File(validationDatasetPath);
  if (!datasetFile.existsSync()) {
    errors.add('validation_dataset_missing:$validationDatasetPath');
    return _emptyReport(
      errors: errors,
      validationDatasetPath: validationDatasetPath,
    );
  }

  final dataset =
      jsonDecode(datasetFile.readAsStringSync()) as Map<String, Object?>;
  final events = [
    for (final rawEvent in _list(dataset['events']))
      StaticIntensityEvent.fromJson(_map(rawEvent)),
  ];
  final evaluationEvents = [
    for (final event in events) _PlumEvaluationEvent.fromEvent(event),
  ];
  final configGrid = configs ?? _defaultConfigs;

  final configReports = [
    for (final config in configGrid) _evaluateConfig(evaluationEvents, config),
  ]..sort((left, right) => right.selectionScore.compareTo(left.selectionScore));
  if (configReports.isEmpty || configReports.first.metrics.caseCount == 0) {
    errors.add('no_plum_like_validation_cases_produced');
  }
  final selected = configReports.isEmpty ? null : configReports.first;

  return {
    'schemaVersion': 'plum_like_intensity_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'validationDatasetPath': validationDatasetPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'method': 'PLUM-like observed-shaking propagation diagnostic',
      'sourceIndependent': true,
      'usesSourceLatitudeLongitudeDepthMagnitude': false,
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime lead-time validation',
      'selfObservationExcluded': true,
    },
    'selectedConfig': selected?.config.toJson(),
    'selectedSummary': selected?.metrics.toJson() ?? const {},
    'selectedThresholds': selected == null
        ? const {}
        : {
            for (final threshold in _thresholds)
              threshold.label: selected.metrics
                  .thresholdMetrics(threshold)
                  .toJson(),
          },
    'configReports': [
      for (final report in configReports.take(12)) report.toJson(),
    ],
    'errors': errors,
  };
}

_ConfigReport _evaluateConfig(
  List<_PlumEvaluationEvent> events,
  PlumLikeReportConfig config,
) {
  final metrics = _MetricAccumulator();
  for (final event in events) {
    for (final variant in event.variants) {
      final observedStations = [
        for (final id in variant.retainedStationIds)
          if (event.stationIndexById[id] != null) event.stationIndexById[id]!,
      ];
      if (observedStations.isEmpty) continue;
      final stationForecasts = <_StationForecast>[];
      var noPredictionCount = 0;
      for (
        var stationIndex = 0;
        stationIndex < event.stations.length;
        stationIndex++
      ) {
        final predicted = _predictFromDistanceMatrix(
          event: event,
          targetStationIndex: stationIndex,
          observedStationIndexes: observedStations,
          config: config,
        );
        if (predicted.evidenceCount < config.minimumEvidenceCount) {
          noPredictionCount++;
        }
        final station = event.stations[stationIndex];
        stationForecasts.add(
          _StationForecast(
            actual: station.intensity,
            predicted: predicted.intensity,
          ),
        );
      }
      final actualMax = event.stations
          .map((station) => station.intensity)
          .fold<double>(-3.0, math.max);
      final predictedMax = stationForecasts
          .map((station) => station.predicted)
          .fold<double>(-3.0, math.max);
      metrics.add(
        _ForecastCase(
          actualMax: actualMax,
          predictedMax: predictedMax,
          stationForecasts: stationForecasts,
          noPredictionCount: noPredictionCount,
        ),
      );
    }
  }
  final shindo4 = metrics.thresholdMetrics(_thresholds[3]);
  final shindo5 = metrics.thresholdMetrics(_thresholds[4]);
  final selectionScore = shindo4.f1 + 0.5 * shindo5.f1;
  return _ConfigReport(
    config: config,
    metrics: metrics,
    selectionScore: selectionScore,
  );
}

PlumLikeIntensityPrediction _predictFromDistanceMatrix({
  required _PlumEvaluationEvent event,
  required int targetStationIndex,
  required List<int> observedStationIndexes,
  required PlumLikeReportConfig config,
}) {
  var evidenceCount = 0;
  var nearestDistance = double.infinity;
  var bestIntensity = -double.infinity;
  String? bestStationId;
  final targetDistances = event.distanceMatrixKm[targetStationIndex];
  final targetStationId = event.stations[targetStationIndex].stationId;
  for (final observedIndex in observedStationIndexes) {
    final observed = event.stations[observedIndex];
    if (observed.stationId == targetStationId) continue;
    final distance = targetDistances[observedIndex];
    if (distance > config.radiusKm) continue;
    evidenceCount++;
    if (distance < nearestDistance) nearestDistance = distance;
    final propagated =
        observed.intensity - config.dampingPer10Km * (distance / 10.0);
    if (propagated > bestIntensity) {
      bestIntensity = propagated;
      bestStationId = observed.stationId;
    }
  }
  if (evidenceCount < config.minimumEvidenceCount) {
    return PlumLikeIntensityPrediction(
      intensity: -3.0,
      evidenceCount: evidenceCount,
      nearestEvidenceDistanceKm: nearestDistance,
    );
  }
  return PlumLikeIntensityPrediction(
    intensity: bestIntensity,
    evidenceCount: evidenceCount,
    nearestEvidenceDistanceKm: nearestDistance,
    strongestEvidenceStationId: bestStationId,
  );
}

String plumLikeIntensityReportMarkdown(Map<String, Object?> report) {
  final selectedConfig = _map(report['selectedConfig']);
  final summary = _map(report['selectedSummary']);
  final buffer = StringBuffer()
    ..writeln('# PLUM-Like Intensity Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Source independent: `true`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This report evaluates observed-shaking propagation from retained '
      'stations to target stations.',
    )
    ..writeln(
      '- It excludes the target station itself from evidence to avoid direct '
      'final-peak leakage.',
    )
    ..writeln(
      '- It scans radius, damping and minimum evidence count. The selected '
      'configuration maximizes `shindo4 F1 + 0.5 * shindo5- F1` on validation.',
    )
    ..writeln(
      '- It still uses synthetic reveal of final peak station intensity, so it '
      'is not realtime lead-time validation.',
    )
    ..writeln()
    ..writeln('## Selected Config')
    ..writeln()
    ..writeln('| Parameter | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Radius | ${_fmt(selectedConfig['radiusKm'])} km |')
    ..writeln(
      '| Damping | ${_fmt(selectedConfig['dampingPer10Km'])} shindo / 10 km |',
    )
    ..writeln(
      '| Minimum evidence stations | ${selectedConfig['minimumEvidenceCount']} |',
    )
    ..writeln()
    ..writeln('## Selected Summary')
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
    ..writeln(
      '| No-prediction station rate | ${_pct(summary['noPredictionStationRate'])} |',
    )
    ..writeln()
    ..writeln('## Selected Thresholds')
    ..writeln()
    ..writeln('| Threshold | Precision | Recall | F1 | TP | FP | FN |')
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  final thresholds = _map(report['selectedThresholds']);
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
    ..writeln('## Top Configs')
    ..writeln()
    ..writeln(
      '| Radius | Damping/10km | Min evidence | Score | Shindo4 P/R/F1 | Shindo5- P/R/F1 |',
    )
    ..writeln('| ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['configReports'])) {
    final row = _map(raw);
    final config = _map(row['config']);
    final thresholds = _map(row['thresholds']);
    buffer.writeln(
      '| ${_fmt(config['radiusKm'])} | '
      '${_fmt(config['dampingPer10Km'])} | '
      '${config['minimumEvidenceCount']} | '
      '${_fmt(row['selectionScore'])} | '
      '${_thresholdSummary(_map(thresholds['shindo4']))} | '
      '${_thresholdSummary(_map(thresholds['shindo5-']))} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Keep this diagnostic separate from source estimation, production UI '
      'and notifications.',
    )
    ..writeln(
      '- Next comparison should evaluate `max(traditional, PLUM-like)` and then '
      'replace synthetic reveal with real per-frame observations.',
    )
    ..writeln();
  return buffer.toString();
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
}) => {
  'schemaVersion': 'plum_like_intensity_report_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'errors': errors,
  'selectedConfig': const {},
  'selectedSummary': const {},
  'selectedThresholds': const {},
  'configReports': const [],
};

final _defaultConfigs = [
  for (final radius in [30.0, 50.0, 80.0])
    for (final damping in [0.0, 0.25, 0.5, 1.0])
      for (final minEvidence in [1, 2])
        PlumLikeReportConfig(
          radiusKm: radius,
          dampingPer10Km: damping,
          minimumEvidenceCount: minEvidence,
        ),
];

class PlumLikeReportConfig {
  final double radiusKm;
  final double dampingPer10Km;
  final int minimumEvidenceCount;

  const PlumLikeReportConfig({
    required this.radiusKm,
    required this.dampingPer10Km,
    required this.minimumEvidenceCount,
  });

  Map<String, Object?> toJson() => {
    'radiusKm': radiusKm,
    'dampingPer10Km': dampingPer10Km,
    'minimumEvidenceCount': minimumEvidenceCount,
  };
}

class _ConfigReport {
  final PlumLikeReportConfig config;
  final _MetricAccumulator metrics;
  final double selectionScore;

  const _ConfigReport({
    required this.config,
    required this.metrics,
    required this.selectionScore,
  });

  Map<String, Object?> toJson() => {
    'config': config.toJson(),
    'selectionScore': selectionScore,
    'summary': metrics.toJson(),
    'thresholds': {
      for (final threshold in _thresholds)
        threshold.label: metrics.thresholdMetrics(threshold).toJson(),
    },
  };
}

class _PlumEvaluationEvent {
  final List<StaticIntensityStation> stations;
  final List<StaticIntensityVariant> variants;
  final Map<String, int> stationIndexById;
  final List<List<double>> distanceMatrixKm;

  const _PlumEvaluationEvent({
    required this.stations,
    required this.variants,
    required this.stationIndexById,
    required this.distanceMatrixKm,
  });

  factory _PlumEvaluationEvent.fromEvent(StaticIntensityEvent event) {
    final stationIndexById = <String, int>{};
    for (var i = 0; i < event.stations.length; i++) {
      stationIndexById[event.stations[i].stationId] = i;
    }
    final matrix = [
      for (final target in event.stations)
        [
          for (final observed in event.stations)
            target.stationId == observed.stationId
                ? 0.0
                : _stationDistanceKm(target, observed),
        ],
    ];
    return _PlumEvaluationEvent(
      stations: event.stations,
      variants: event.variants,
      stationIndexById: stationIndexById,
      distanceMatrixKm: matrix,
    );
  }
}

class _ForecastCase {
  final double actualMax;
  final double predictedMax;
  final List<_StationForecast> stationForecasts;
  final int noPredictionCount;

  const _ForecastCase({
    required this.actualMax,
    required this.predictedMax,
    required this.stationForecasts,
    required this.noPredictionCount,
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
  var noPredictionStationCount = 0;

  int get caseCount => maxClassErrors.length;

  void add(_ForecastCase row) {
    final classError = row.predictedMaxClass - row.actualMaxClass;
    maxClassErrors.add(classError.abs());
    maxIntensityErrors.add((row.predictedMax - row.actualMax).abs());
    if (classError < 0) underestimatedMaxClass++;
    if (classError == 0) exactMaxClass++;
    if (classError.abs() <= 1) withinOneMaxClass++;
    noPredictionStationCount += row.noPredictionCount;
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
    'noPredictionStationRate': stationForecastCount == 0
        ? 0.0
        : noPredictionStationCount / stationForecastCount,
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

double _stationDistanceKm(
  StaticIntensityStation target,
  StaticIntensityStation observed,
) {
  return QuakeCalculator.haversineDistance(
    target.latitude,
    target.longitude,
    observed.latitude,
    observed.longitude,
  );
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
