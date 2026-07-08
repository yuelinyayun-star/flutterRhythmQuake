import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath = '.dart_tool/jma_style_intensity/report.json';
const _defaultMarkdownPath = 'docs/baselines/jma_style_intensity.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildJmaStyleIntensityReportJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(jmaStyleIntensityReportMarkdown(report));

  stdout.writeln('wrote JMA-style intensity report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildJmaStyleIntensityReportJson({
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
  final sourceErrorLocator = StaticIntensityLocator(
    model: _modelFromJson(modelJson),
  );
  final predictor = const JmaStyleIntensityPredictor();
  final oracleOverall = _MetricAccumulator();
  final sourceErrorOverall = _MetricAccumulator();
  final cases = <Map<String, Object?>>[];
  final sourceErrorCases = <Map<String, Object?>>[];
  final amplificationByStationId = <String, (double, double, String)>{};
  var skippedMissingMagnitude = 0;
  var skippedSourceErrorNoEstimate = 0;
  var defaultAmplificationCount = 0;
  var stationPredictionCount = 0;
  var sourceErrorDefaultAmplificationCount = 0;
  var sourceErrorStationPredictionCount = 0;

  for (final rawEvent in _list(dataset['events'])) {
    final event = StaticIntensityEvent.fromJson(_map(rawEvent));
    final magnitude = event.magnitude;
    if (magnitude == null || !magnitude.isFinite) {
      skippedMissingMagnitude++;
      continue;
    }
    final stationForecasts = <_StationForecast>[];
    for (final station in event.stations) {
      final site = amplificationByStationId.putIfAbsent(
        station.stationId,
        () => predictor.nearestAmplification(
          stationLatitude: station.latitude,
          stationLongitude: station.longitude,
        ),
      );
      final prediction = predictor.predict(
        magnitude: magnitude,
        sourceLatitude: event.latitude,
        sourceLongitude: event.longitude,
        depthKm: event.depthKm,
        stationLatitude: station.latitude,
        stationLongitude: station.longitude,
        siteAmplification: site.$1,
        siteAmplificationDistanceKm: site.$2,
        siteAmplificationSource: site.$3,
      );
      if (prediction.amplificationSource == 'default_arv') {
        defaultAmplificationCount++;
      }
      stationPredictionCount++;
      stationForecasts.add(
        _StationForecast(
          actual: station.intensity,
          predicted: prediction.intensity,
        ),
      );
    }
    final actualMax = event.stations
        .map((station) => station.intensity)
        .fold<double>(-3.0, math.max);
    final predictedMax = stationForecasts
        .map((station) => station.predicted)
        .fold<double>(-3.0, math.max);
    final row = _ForecastCase(
      eventId: event.eventId,
      stationCount: event.stations.length,
      magnitude: magnitude,
      depthKm: event.depthKm,
      actualMax: actualMax,
      predictedMax: predictedMax,
      stationForecasts: stationForecasts,
    );
    oracleOverall.add(row);
    cases.add(row.toSummaryJson());

    final stationsById = {
      for (final station in event.stations) station.stationId: station,
    };
    for (final variant in event.variants) {
      final retainedStations = [
        for (final id in variant.retainedStationIds)
          if (stationsById[id] != null) stationsById[id]!,
      ];
      final estimate = sourceErrorLocator.locate(retainedStations);
      if (estimate == null) {
        skippedSourceErrorNoEstimate++;
        continue;
      }
      final sourceErrorForecasts = <_StationForecast>[];
      for (final station in event.stations) {
        final site = amplificationByStationId.putIfAbsent(
          station.stationId,
          () => predictor.nearestAmplification(
            stationLatitude: station.latitude,
            stationLongitude: station.longitude,
          ),
        );
        final prediction = predictor.predict(
          magnitude: magnitude,
          sourceLatitude: estimate.latitude,
          sourceLongitude: estimate.longitude,
          depthKm: estimate.depthKm,
          stationLatitude: station.latitude,
          stationLongitude: station.longitude,
          siteAmplification: site.$1,
          siteAmplificationDistanceKm: site.$2,
          siteAmplificationSource: site.$3,
        );
        if (prediction.amplificationSource == 'default_arv') {
          sourceErrorDefaultAmplificationCount++;
        }
        sourceErrorStationPredictionCount++;
        sourceErrorForecasts.add(
          _StationForecast(
            actual: station.intensity,
            predicted: prediction.intensity,
          ),
        );
      }
      final predictedMax = sourceErrorForecasts
          .map((station) => station.predicted)
          .fold<double>(-3.0, math.max);
      final row = _ForecastCase(
        eventId: event.eventId,
        variantId: variant.variantId,
        stationCount: event.stations.length,
        magnitude: magnitude,
        depthKm: estimate.depthKm,
        actualMax: actualMax,
        predictedMax: predictedMax,
        stationForecasts: sourceErrorForecasts,
      );
      sourceErrorOverall.add(row);
      sourceErrorCases.add(row.toSummaryJson());
    }
  }

  if (oracleOverall.caseCount == 0) {
    errors.add('no_jma_style_validation_cases_produced');
  }
  if (sourceErrorOverall.caseCount == 0) {
    errors.add('no_jma_style_source_error_cases_produced');
  }

  return {
    'schemaVersion': 'jma_style_intensity_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'validationDatasetPath': validationDatasetPath,
    'modelPath': modelPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'method':
          'JMA-style traditional source-parameter PGV attenuation diagnostic',
      'sourceSemantics':
          'oracle catalog source plus P3-estimated-source variants, not realtime EEW source error',
      'siteAmplification':
          'nearest JMA intensity station ARV within 5 km, otherwise 1.0',
      'plumIncluded': false,
    },
    'formula': const {
      'mwFromMjma': 'Mw = Mjma - 0.171',
      'pgv600':
          'log10(PGV600)=0.58Mw+0.0038D-1.29-log10(x+0.0028*10^(0.50Mw))-0.002x',
      'surfacePgv': 'PGVS = ARV700 * 0.90 * PGV600',
      'instrumentalIntensity': 'I = 2.68 + 1.72 log10(PGVS)',
    },
    'summary': oracleOverall.toJson(),
    'thresholds': {
      for (final threshold in _thresholds)
        threshold.label: oracleOverall.thresholdMetrics(threshold).toJson(),
    },
    'sourceErrorVariantSummary': sourceErrorOverall.toJson(),
    'sourceErrorVariantThresholds': {
      for (final threshold in _thresholds)
        threshold.label: sourceErrorOverall
            .thresholdMetrics(threshold)
            .toJson(),
    },
    'coverage': {
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedSourceErrorNoEstimateVariants': skippedSourceErrorNoEstimate,
      'stationPredictionCount': stationPredictionCount,
      'defaultAmplificationCount': defaultAmplificationCount,
      'defaultAmplificationRate': stationPredictionCount == 0
          ? 0.0
          : defaultAmplificationCount / stationPredictionCount,
      'sourceErrorStationPredictionCount': sourceErrorStationPredictionCount,
      'sourceErrorDefaultAmplificationCount':
          sourceErrorDefaultAmplificationCount,
      'sourceErrorDefaultAmplificationRate':
          sourceErrorStationPredictionCount == 0
          ? 0.0
          : sourceErrorDefaultAmplificationCount /
                sourceErrorStationPredictionCount,
    },
    'errors': errors,
    'cases': cases,
    'sourceErrorVariantCases': sourceErrorCases,
  };
}

String jmaStyleIntensityReportMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final sourceError = _map(report['sourceErrorVariantSummary']);
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# JMA-Style Intensity Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- PLUM included: `false`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This report evaluates a JMA-style traditional source-parameter PGV '
      'attenuation path using catalog source and magnitude.',
    )
    ..writeln(
      '- It includes an oracle-source diagnostic and a P3-estimated-source '
      'variant to expose source-location error sensitivity.',
    )
    ..writeln(
      '- Site amplification uses nearest JMA intensity station ARV within 5 km; '
      'otherwise ARV falls back to 1.0.',
    )
    ..writeln()
    ..writeln('## Oracle Source Summary')
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
    ..writeln('## P3-Estimated Source Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Cases | ${sourceError['caseCount']} |')
    ..writeln('| Station forecasts | ${sourceError['stationForecastCount']} |')
    ..writeln(
      '| Max-shindo class MAE | ${_fmt(sourceError['maxClassMae'])} classes |',
    )
    ..writeln(
      '| Max-shindo numeric MAE | ${_fmt(sourceError['maxIntensityMae'])} shindo |',
    )
    ..writeln(
      '| Station intensity MAE | ${_fmt(sourceError['stationIntensityMae'])} shindo |',
    )
    ..writeln(
      '| Max-shindo underestimation rate | ${_pct(sourceError['maxClassUnderestimateRate'])} |',
    )
    ..writeln(
      '| Exact max-shindo class accuracy | ${_pct(sourceError['maxClassExactAccuracy'])} |',
    )
    ..writeln(
      '| Within 1 class accuracy | ${_pct(sourceError['maxClassWithinOneAccuracy'])} |',
    )
    ..writeln()
    ..writeln('## Oracle Source Thresholds')
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
    ..writeln('## P3-Estimated Source Thresholds')
    ..writeln()
    ..writeln('| Threshold | Precision | Recall | F1 | TP | FP | FN |')
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
  final sourceErrorThresholds = _map(report['sourceErrorVariantThresholds']);
  for (final threshold in _thresholds) {
    final metrics = _map(sourceErrorThresholds[threshold.label]);
    buffer.writeln(
      '| `${threshold.label}` | ${_pct(metrics['precision'])} | '
      '${_pct(metrics['recall'])} | ${_pct(metrics['f1'])} | '
      '${metrics['truePositive']} | ${metrics['falsePositive']} | '
      '${metrics['falseNegative']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Coverage')
    ..writeln()
    ..writeln(
      '- Skipped missing-magnitude events: '
      '`${coverage['skippedMissingMagnitudeEvents']}`',
    )
    ..writeln(
      '- Skipped source-error variants without source estimate: '
      '`${coverage['skippedSourceErrorNoEstimateVariants']}`',
    )
    ..writeln(
      '- Default ARV rate: `${_pct(coverage['defaultAmplificationRate'])}`',
    )
    ..writeln(
      '- P3-estimated source default ARV rate: '
      '`${_pct(coverage['sourceErrorDefaultAmplificationRate'])}`',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Keep this diagnostic separate from production UI and notifications.',
    )
    ..writeln(
      '- Next comparison should add a PLUM-like observed-shaking path before '
      'any frozen test decision.',
    )
    ..writeln();
  return buffer.toString();
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'jma_style_intensity_report_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'modelPath': modelPath,
  'errors': errors,
  'summary': const {},
  'thresholds': const {},
  'sourceErrorVariantSummary': const {},
  'sourceErrorVariantThresholds': const {},
  'coverage': const {},
  'cases': const [],
  'sourceErrorVariantCases': const [],
};

class _ForecastCase {
  final String eventId;
  final String? variantId;
  final int stationCount;
  final double magnitude;
  final double depthKm;
  final double actualMax;
  final double predictedMax;
  final List<_StationForecast> stationForecasts;

  const _ForecastCase({
    required this.eventId,
    this.variantId,
    required this.stationCount,
    required this.magnitude,
    required this.depthKm,
    required this.actualMax,
    required this.predictedMax,
    required this.stationForecasts,
  });

  int get actualMaxClass => JpShindoScale.jmaIndexFromShindo(actualMax);
  int get predictedMaxClass => JpShindoScale.jmaIndexFromShindo(predictedMax);

  Map<String, Object?> toSummaryJson() => {
    'eventId': eventId,
    if (variantId != null) 'variantId': variantId,
    'stationCount': stationCount,
    'magnitude': magnitude,
    'depthKm': depthKm,
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
