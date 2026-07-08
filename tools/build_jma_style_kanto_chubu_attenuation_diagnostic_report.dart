import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/jma_style_kanto_chubu_attenuation_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/jma_style_kanto_chubu_attenuation_diagnostic.generated.md';

const _targetRegion = 'kanto_chubu';
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];
const _sourceErrorBuckets = [
  '000_025km',
  '025_050km',
  '050_100km',
  '100_200km',
  'gt_200km',
];
const _distanceBuckets = [
  '000_030km',
  '030_060km',
  '060_100km',
  '100_200km',
  'gt_200km',
];
const _depthBuckets = ['000_020km', '020_050km', '050_100km', 'gt_100km'];
const _magnitudeBuckets = ['lt_m3', 'm3_m4', 'm4_m5', 'gte_m5'];
const _amplificationBuckets = ['default_arv', 'lt_0_8', '0_8_1_2', 'gte_1_2'];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildJmaStyleKantoChubuAttenuationDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    jmaStyleKantoChubuAttenuationDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote JMA-style kanto_chubu attenuation diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildJmaStyleKantoChubuAttenuationDiagnosticJson({
  String dataDirectory = _defaultDataDirectory,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final modelFile = File(modelPath);
  final splitFile = File('$dataDirectory/splits.json');
  final annualFiles = [
    File('$dataDirectory/jma_final_intensity_2020.json'),
    File('$dataDirectory/jma_final_intensity_2021.json'),
    File('$dataDirectory/jma_final_intensity_2022.json'),
  ];
  if (!modelFile.existsSync()) errors.add('model_missing:$modelPath');
  if (!splitFile.existsSync()) {
    errors.add('split_manifest_missing:${splitFile.path}');
  }
  for (final file in annualFiles) {
    if (!file.existsSync()) errors.add('annual_dataset_missing:${file.path}');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      dataDirectory: dataDirectory,
      modelPath: modelPath,
    );
  }

  final annualDatasets = [
    for (final file in annualFiles)
      decodeJmaIntensityDataset(file.readAsStringSync()),
  ];
  final splits =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final synthetic = const SyntheticRevealDatasetBuilder(
    generatedSplits: ['validation', 'test'],
  ).build(annualDatasets: annualDatasets, splitManifest: splits);

  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final locator = StaticIntensityLocator(model: model);
  final predictor = const JmaStyleIntensityPredictor();
  final acc = _ReportAccumulator();
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final splitName in const ['validation', 'test']) {
    final dataset = synthetic.datasetsBySplit[splitName]!;
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
        if (_eventLatitudeBucket(estimate.latitude) != _targetRegion) {
          continue;
        }

        final splitAcc = acc.split(splitName);
        splitAcc.variantCount++;
        final sourceErrorKm = QuakeCalculator.haversineDistance(
          event.latitude,
          event.longitude,
          estimate.latitude,
          estimate.longitude,
        );
        final sourceErrorBucket = _sourceErrorBucket(sourceErrorKm);
        final depthBucket = _depthBucket(estimate.depthKm);
        final magnitudeBucket = _magnitudeBucket(magnitude);
        for (final station in event.stations) {
          final site = predictor.nearestAmplification(
            stationLatitude: station.latitude,
            stationLongitude: station.longitude,
          );
          final estimatedPrediction = predictor.predict(
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
          final oraclePrediction = predictor.predict(
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
          final distanceKm = QuakeCalculator.haversineDistance(
            estimate.latitude,
            estimate.longitude,
            station.latitude,
            station.longitude,
          );
          final distanceBucket = _distanceBucket(distanceKm);
          final amplificationBucket = _amplificationBucket(
            estimatedPrediction.amplification,
            estimatedPrediction.amplificationSource,
          );
          splitAcc.stationForecastCount++;

          for (final threshold in _thresholds) {
            final thresholdAcc = splitAcc.threshold(threshold.label);
            final actualPos = station.intensity >= threshold.value;
            thresholdAcc.estimatedSource.add(
              actual: station.intensity,
              predicted: estimatedPrediction.intensity,
              threshold: threshold.value,
            );
            thresholdAcc.oracleSource.add(
              actual: station.intensity,
              predicted: oraclePrediction.intensity,
              threshold: threshold.value,
            );
            thresholdAcc.sourceErrorBuckets
                .putIfAbsent(sourceErrorBucket, _BucketStats.new)
                .add(
                  actual: station.intensity,
                  predicted: estimatedPrediction.intensity,
                  threshold: threshold.value,
                );
            thresholdAcc.distanceBuckets
                .putIfAbsent(distanceBucket, _BucketStats.new)
                .add(
                  actual: station.intensity,
                  predicted: estimatedPrediction.intensity,
                  threshold: threshold.value,
                );
            thresholdAcc.depthBuckets
                .putIfAbsent(depthBucket, _BucketStats.new)
                .add(
                  actual: station.intensity,
                  predicted: estimatedPrediction.intensity,
                  threshold: threshold.value,
                );
            thresholdAcc.magnitudeBuckets
                .putIfAbsent(magnitudeBucket, _BucketStats.new)
                .add(
                  actual: station.intensity,
                  predicted: estimatedPrediction.intensity,
                  threshold: threshold.value,
                );
            thresholdAcc.amplificationBuckets
                .putIfAbsent(amplificationBucket, _BucketStats.new)
                .add(
                  actual: station.intensity,
                  predicted: estimatedPrediction.intensity,
                  threshold: threshold.value,
                );
            if (!actualPos &&
                estimatedPrediction.intensity >= threshold.value) {
              thresholdAcc.falsePositiveSourceErrorKm.add(sourceErrorKm);
              thresholdAcc.falsePositiveDistanceKm.add(distanceKm);
            }
          }
        }
      }
    }
  }

  if (acc.validation.stationForecastCount == 0 &&
      acc.test.stationForecastCount == 0) {
    errors.add('no_kanto_chubu_jma_style_forecasts');
  }

  return _assembleReport(
    errors: errors,
    dataDirectory: dataDirectory,
    modelPath: modelPath,
    skippedMissingMagnitude: skippedMissingMagnitude,
    skippedNoEstimate: skippedNoEstimate,
    acc: acc,
  );
}

Map<String, Object?> _assembleReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
  required int skippedMissingMagnitude,
  required int skippedNoEstimate,
  required _ReportAccumulator acc,
}) {
  final thresholds = <String, Object?>{};
  for (final threshold in _thresholds) {
    final validation = acc.validation.threshold(threshold.label);
    final test = acc.test.threshold(threshold.label);
    thresholds[threshold.label] = {
      'splits': {'validation': validation.toJson(), 'test': test.toJson()},
      'estimatedSourcePrecisionDelta':
          test.estimatedSource.precision - validation.estimatedSource.precision,
      'oracleSourcePrecisionDelta':
          test.oracleSource.precision - validation.oracleSource.precision,
    };
  }

  return {
    'schemaVersion': 'jma_style_kanto_chubu_attenuation_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'targetRegion': _targetRegion,
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'method':
          'diagnose JMA-style attenuation migration in kanto_chubu by '
          'comparing estimated-source and oracle-source JMA-style forecasts '
          'across validation/test splits and source-error/distance/depth/'
          'magnitude/amplification buckets',
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'splits': ['validation', 'test'],
      'targetRegion': _targetRegion,
    },
    'coverage': {
      'validationVariants': acc.validation.variantCount,
      'testVariants': acc.test.variantCount,
      'validationStationForecasts': acc.validation.stationForecastCount,
      'testStationForecasts': acc.test.stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'thresholds': thresholds,
    'errors': errors,
  };
}

String jmaStyleKantoChubuAttenuationDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# JMA-Style Kanto/Chubu Attenuation Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Target region: `${policy['targetRegion']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln('- Production UI connected: `${policy['productionUiConnected']}`')
    ..writeln('- Diagnostic only: `${policy['diagnosticOnly']}`')
    ..writeln('- Parameters tuned: `${policy['parametersTuned']}`')
    ..writeln(
      '- Raw predicted intensity mutated: '
      '`${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln()
    ..writeln('## Coverage')
    ..writeln()
    ..writeln('| Split | Variants | Station forecasts |')
    ..writeln('| --- | ---: | ---: |')
    ..writeln(
      '| validation | ${coverage['validationVariants']} | '
      '${coverage['validationStationForecasts']} |',
    )
    ..writeln(
      '| test | ${coverage['testVariants']} | '
      '${coverage['testStationForecasts']} |',
    )
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This is a diagnostic-only drilldown for the JMA-style attenuation '
      'branch. It does not tune parameters, does not modify raw predicted '
      'intensity, and does not connect to UI/notifications/wording.',
    )
    ..writeln(
      '- The target sample is synthetic-reveal variants whose estimated-source '
      'latitude falls in `kanto_chubu` (34.5 <= lat < 37.5).',
    )
    ..writeln(
      '- `estimatedSourceJma` uses the same estimated source produced by '
      '`StaticIntensityLocator`; `oracleSourceJma` uses the catalog source '
      'with the same JMA-style PGV attenuation formula. Bucket tables below '
      'use `estimatedSourceJma`.',
    )
    ..writeln();

  for (final threshold in _thresholds) {
    final t = _map(thresholds[threshold.label]);
    final splits = _map(t['splits']);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Estimated vs Oracle Source')
      ..writeln()
      ..writeln(
        '| Split | Branch | TP | FP | FN | Precision | Recall | F1 | Mean error | MAE |',
      )
      ..writeln(
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final splitName in const ['validation', 'test']) {
      final split = _map(splits[splitName]);
      for (final branch in const ['estimatedSourceJma', 'oracleSourceJma']) {
        final row = _map(split[branch]);
        buffer.writeln(
          '| $splitName | `$branch` | ${row['truePositive']} | '
          '${row['falsePositive']} | ${row['falseNegative']} | '
          '${_pct(row['precision'])} | ${_pct(row['recall'])} | '
          '${_pct(row['f1'])} | ${_fmt(row['meanError'])} | '
          '${_fmt(row['mae'])} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('### Precision Delta (test - validation)')
      ..writeln()
      ..writeln('| Branch | Delta |')
      ..writeln('| --- | ---: |')
      ..writeln(
        '| `estimatedSourceJma` | '
        '${_signedPct(t['estimatedSourcePrecisionDelta'])} |',
      )
      ..writeln(
        '| `oracleSourceJma` | '
        '${_signedPct(t['oracleSourcePrecisionDelta'])} |',
      )
      ..writeln();

    _writeBucketSection(
      buffer,
      title: 'Source Error Buckets',
      order: _sourceErrorBuckets,
      splits: splits,
      field: 'sourceErrorBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Estimated Source Distance Buckets',
      order: _distanceBuckets,
      splits: splits,
      field: 'distanceBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Estimated Depth Buckets',
      order: _depthBuckets,
      splits: splits,
      field: 'depthBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Magnitude Buckets',
      order: _magnitudeBuckets,
      splits: splits,
      field: 'magnitudeBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Amplification Buckets',
      order: _amplificationBuckets,
      splits: splits,
      field: 'amplificationBuckets',
    );
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Diagnostic-only. This report identifies where JMA-style attenuation '
      'migration fails in `kanto_chubu`; it does not authorize production '
      'coordinate, intensity, UI, wording, or notification changes.',
    )
    ..writeln();
  return buffer.toString();
}

void _writeBucketSection(
  StringBuffer buffer, {
  required String title,
  required List<String> order,
  required Map<String, Object?> splits,
  required String field,
}) {
  buffer
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Mean error | MAE |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final bucket in order) {
    for (final splitName in const ['validation', 'test']) {
      final split = _map(splits[splitName]);
      final buckets = _map(split[field]);
      final row = _map(buckets[bucket]);
      buffer.writeln(
        '| `$bucket` | $splitName | ${row['count'] ?? 0} | '
        '${row['truePositive'] ?? 0} | ${row['falsePositive'] ?? 0} | '
        '${row['falseNegative'] ?? 0} | ${_pct(row['precision'])} | '
        '${_pct(row['recall'])} | ${_fmt(row['meanError'])} | '
        '${_fmt(row['mae'])} |',
      );
    }
  }
  buffer.writeln();
}

class _ReportAccumulator {
  final validation = _SplitAccumulator();
  final test = _SplitAccumulator();

  _SplitAccumulator split(String splitName) =>
      splitName == 'validation' ? validation : test;
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final thresholds = <String, _ThresholdAccumulator>{};

  _ThresholdAccumulator threshold(String label) =>
      thresholds.putIfAbsent(label, _ThresholdAccumulator.new);
}

class _ThresholdAccumulator {
  final estimatedSource = _BucketStats();
  final oracleSource = _BucketStats();
  final sourceErrorBuckets = <String, _BucketStats>{};
  final distanceBuckets = <String, _BucketStats>{};
  final depthBuckets = <String, _BucketStats>{};
  final magnitudeBuckets = <String, _BucketStats>{};
  final amplificationBuckets = <String, _BucketStats>{};
  final falsePositiveSourceErrorKm = _NumberStats();
  final falsePositiveDistanceKm = _NumberStats();

  Map<String, Object?> toJson() => {
    'estimatedSourceJma': estimatedSource.toJson(),
    'oracleSourceJma': oracleSource.toJson(),
    'sourceErrorBuckets': _bucketJson(sourceErrorBuckets),
    'distanceBuckets': _bucketJson(distanceBuckets),
    'depthBuckets': _bucketJson(depthBuckets),
    'magnitudeBuckets': _bucketJson(magnitudeBuckets),
    'amplificationBuckets': _bucketJson(amplificationBuckets),
    'falsePositiveSourceErrorKm': falsePositiveSourceErrorKm.toJson(),
    'falsePositiveDistanceKm': falsePositiveDistanceKm.toJson(),
  };
}

class _BucketStats {
  int count = 0;
  int truePositive = 0;
  int falsePositive = 0;
  int falseNegative = 0;
  int trueNegative = 0;
  double errorSum = 0;
  double absoluteErrorSum = 0;

  void add({
    required double actual,
    required double predicted,
    required double threshold,
  }) {
    count++;
    final actualPos = actual >= threshold;
    final predictedPos = predicted >= threshold;
    if (actualPos && predictedPos) {
      truePositive++;
    } else if (!actualPos && predictedPos) {
      falsePositive++;
    } else if (actualPos && !predictedPos) {
      falseNegative++;
    } else {
      trueNegative++;
    }
    final error = predicted - actual;
    errorSum += error;
    absoluteErrorSum += error.abs();
  }

  double get precision => truePositive + falsePositive == 0
      ? 0.0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0.0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0.0
      : 2 * precision * recall / (precision + recall);
  double get meanError => count == 0 ? 0.0 : errorSum / count;
  double get mae => count == 0 ? 0.0 : absoluteErrorSum / count;

  Map<String, Object?> toJson() => {
    'count': count,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'trueNegative': trueNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'meanError': meanError,
    'mae': mae,
  };
}

class _NumberStats {
  int count = 0;
  double sum = 0;
  double max = 0;

  void add(double value) {
    count++;
    sum += value;
    if (value > max) max = value;
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'mean': count == 0 ? 0.0 : sum / count,
    'max': max,
  };
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

Map<String, Object?> _bucketJson(Map<String, _BucketStats> buckets) => {
  for (final entry in buckets.entries) entry.key: entry.value.toJson(),
};

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

String _sourceErrorBucket(double distanceKm) {
  if (distanceKm < 25) return '000_025km';
  if (distanceKm < 50) return '025_050km';
  if (distanceKm < 100) return '050_100km';
  if (distanceKm < 200) return '100_200km';
  return 'gt_200km';
}

String _distanceBucket(double distanceKm) {
  if (distanceKm < 30) return '000_030km';
  if (distanceKm < 60) return '030_060km';
  if (distanceKm < 100) return '060_100km';
  if (distanceKm < 200) return '100_200km';
  return 'gt_200km';
}

String _depthBucket(double depthKm) {
  if (depthKm < 20) return '000_020km';
  if (depthKm < 50) return '020_050km';
  if (depthKm < 100) return '050_100km';
  return 'gt_100km';
}

String _magnitudeBucket(double magnitude) {
  if (magnitude < 3) return 'lt_m3';
  if (magnitude < 4) return 'm3_m4';
  if (magnitude < 5) return 'm4_m5';
  return 'gte_m5';
}

String _amplificationBucket(double amplification, String source) {
  if (source == 'default_arv') return 'default_arv';
  if (amplification < 0.8) return 'lt_0_8';
  if (amplification < 1.2) return '0_8_1_2';
  return 'gte_1_2';
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
  'schemaVersion': 'jma_style_kanto_chubu_attenuation_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'targetRegion': _targetRegion,
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'method': 'diagnose JMA-style attenuation migration in kanto_chubu',
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'modelPath': modelPath,
    'splits': ['validation', 'test'],
    'targetRegion': _targetRegion,
  },
  'coverage': {
    'validationVariants': 0,
    'testVariants': 0,
    'validationStationForecasts': 0,
    'testStationForecasts': 0,
    'skippedMissingMagnitudeEvents': 0,
    'skippedNoSourceEstimateVariants': 0,
  },
  'thresholds': const {},
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

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(Object? value) {
  final number = _number(value) * 100;
  final sign = number >= 0 ? '+' : '';
  return '$sign${number.toStringAsFixed(1)}pp';
}

String _fmt(Object? value) => _number(value).toStringAsFixed(2);
