import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

// 默认数据/输出路径。参数来自现有 model 和 frozen evaluation 工具的固定配置。
const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/raw_intensity_frozen_source_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/raw_intensity_frozen_source_diagnostic.generated.md';

// 与 frozen evaluation 工具完全一致的 PLUM 配置。
const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;

// 阈值定义,与 frozen regression diagnostic 一致。
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];

// region/distance 桶顺序,与 frozen regression diagnostic 一致。
const _regions = ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'];
const _distances = [
  '000_030km',
  '030_060km',
  '060_100km',
  '100_200km',
  'gt_200km',
];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildRawIntensityFrozenSourceDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(rawIntensityFrozenSourceDiagnosticMarkdown(report));

  stdout.writeln('wrote raw intensity frozen source diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildRawIntensityFrozenSourceDiagnosticJson({
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

  // 1. 同时构建 validation 和 test 两个 split 的 synthetic reveal 数据集。
  // 注意:confidence band frozen evaluation 工具只生成 test,这里同时生成两个 split。
  final annualDatasets = [
    for (final file in annualFiles)
      decodeJmaIntensityDataset(file.readAsStringSync()),
  ];
  final splits =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final synthetic = const SyntheticRevealDatasetBuilder(
    generatedSplits: ['validation', 'test'],
  ).build(annualDatasets: annualDatasets, splitManifest: splits);
  final validationDataset = synthetic.datasetsBySplit['validation']!;
  final testDataset = synthetic.datasetsBySplit['test']!;

  // 2. 加载模型与预测器,与 frozen evaluation 工具完全一致。
  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumR30D050 = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
  );

  // 3. 对每个 split 累计 TP/FP/FN/TN、region/distance 分桶、FP 触发源。
  final thresholdAccumulators = {
    for (final threshold in _thresholds)
      threshold.label: _ThresholdAccumulator(),
  };
  var validationStationForecasts = 0;
  var testStationForecasts = 0;
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  validationStationForecasts = _accumulateSplit(
    splitName: 'validation',
    dataset: validationDataset,
    locator: locator,
    jmaPredictor: jmaPredictor,
    plumPredictor: plumR30D050,
    thresholdAccumulators: thresholdAccumulators,
    onMissingMagnitude: () => skippedMissingMagnitude++,
    onNoEstimate: () => skippedNoEstimate++,
  );
  testStationForecasts = _accumulateSplit(
    splitName: 'test',
    dataset: testDataset,
    locator: locator,
    jmaPredictor: jmaPredictor,
    plumPredictor: plumR30D050,
    thresholdAccumulators: thresholdAccumulators,
    onMissingMagnitude: () => skippedMissingMagnitude++,
    onNoEstimate: () => skippedNoEstimate++,
  );

  if (validationStationForecasts == 0 && testStationForecasts == 0) {
    errors.add('no_raw_intensity_station_forecasts');
  }

  // 4. 汇总输出。
  return _assembleReport(
    errors: errors,
    validationStationForecasts: validationStationForecasts,
    testStationForecasts: testStationForecasts,
    skippedMissingMagnitude: skippedMissingMagnitude,
    skippedNoEstimate: skippedNoEstimate,
    thresholdAccumulators: thresholdAccumulators,
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );
}

int _accumulateSplit({
  required String splitName,
  required Map<String, Object?> dataset,
  required StaticIntensityLocator locator,
  required JmaStyleIntensityPredictor jmaPredictor,
  required PlumLikeIntensityPredictor plumPredictor,
  required Map<String, _ThresholdAccumulator> thresholdAccumulators,
  required void Function() onMissingMagnitude,
  required void Function() onNoEstimate,
}) {
  var stationForecastCount = 0;
  for (final rawEvent in _list(dataset['events'])) {
    final event = StaticIntensityEvent.fromJson(_map(rawEvent));
    final magnitude = event.magnitude;
    if (magnitude == null || !magnitude.isFinite) {
      onMissingMagnitude();
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
        onNoEstimate();
        continue;
      }
      // region 基于"估计震源"纬度,与 region/site calibration 一致。
      final region = _eventLatitudeBucket(estimate.latitude);
      for (final station in event.stations) {
        final jma = jmaPredictor
            .predict(
              magnitude: magnitude,
              sourceLatitude: estimate.latitude,
              sourceLongitude: estimate.longitude,
              depthKm: estimate.depthKm,
              stationLatitude: station.latitude,
              stationLongitude: station.longitude,
            )
            .intensity;
        final r30 = plumPredictor.predict(
          targetStation: station,
          observedStations: retained,
        );
        final baselineRaw = math.max(jma, r30.intensity);
        final actual = station.intensity;
        // StaticIntensityStation 不暴露 surfaceDistanceKm,这里用 estimate→station
        // 的 haversine 距离做距离桶,与 region 使用 estimate 一致(production-available)。
        final distance = QuakeCalculator.haversineDistance(
          estimate.latitude,
          estimate.longitude,
          station.latitude,
          station.longitude,
        );
        final distanceBucket = _distanceBucket(distance);
        for (final threshold in _thresholds) {
          final acc = thresholdAccumulators[threshold.label]!;
          final metrics = splitName == 'validation' ? acc.validation : acc.test;
          final regionMap = splitName == 'validation'
              ? acc.validationByRegion
              : acc.testByRegion;
          final distanceMap = splitName == 'validation'
              ? acc.validationByDistance
              : acc.testByDistance;
          final fpTrigger = splitName == 'validation'
              ? acc.validationFpTrigger
              : acc.testFpTrigger;

          final actualPos = actual >= threshold.value;
          final jmaPos = jma >= threshold.value;
          final plumPos = r30.intensity >= threshold.value;
          final baselinePos = baselineRaw >= threshold.value;

          metrics.jmaStyle.add(actual: actualPos, predicted: jmaPos);
          metrics.plumR30D050.add(actual: actualPos, predicted: plumPos);
          metrics.baselineMax.add(actual: actualPos, predicted: baselinePos);

          regionMap
              .putIfAbsent(region, _ComponentMetrics.new)
              .jmaStyle
              .add(actual: actualPos, predicted: jmaPos);
          regionMap
              .putIfAbsent(region, _ComponentMetrics.new)
              .plumR30D050
              .add(actual: actualPos, predicted: plumPos);
          regionMap
              .putIfAbsent(region, _ComponentMetrics.new)
              .baselineMax
              .add(actual: actualPos, predicted: baselinePos);

          distanceMap
              .putIfAbsent(distanceBucket, _ComponentMetrics.new)
              .jmaStyle
              .add(actual: actualPos, predicted: jmaPos);
          distanceMap
              .putIfAbsent(distanceBucket, _ComponentMetrics.new)
              .plumR30D050
              .add(actual: actualPos, predicted: plumPos);
          distanceMap
              .putIfAbsent(distanceBucket, _ComponentMetrics.new)
              .baselineMax
              .add(actual: actualPos, predicted: baselinePos);

          // baseline 的 FP 触发源分解:baseline=max(jma,plum),baseline>=threshold
          // 必至少一个跨阈,不会出现 neither。
          if (!actualPos && baselinePos) {
            if (jmaPos && !plumPos) {
              fpTrigger.jmaOnly++;
            } else if (plumPos && !jmaPos) {
              fpTrigger.plumOnly++;
            } else if (jmaPos && plumPos) {
              fpTrigger.both++;
            }
          }
        }
        stationForecastCount++;
      }
    }
  }
  return stationForecastCount;
}

Map<String, Object?> _assembleReport({
  required List<String> errors,
  required int validationStationForecasts,
  required int testStationForecasts,
  required int skippedMissingMagnitude,
  required int skippedNoEstimate,
  required Map<String, _ThresholdAccumulator> thresholdAccumulators,
  required String dataDirectory,
  required String modelPath,
}) {
  final thresholdsJson = <String, Object?>{};
  for (final threshold in _thresholds) {
    final acc = thresholdAccumulators[threshold.label]!;
    final validationPrecision = {
      'jmaStyle': acc.validation.jmaStyle.precision,
      'plumR30D050': acc.validation.plumR30D050.precision,
      'baselineMax': acc.validation.baselineMax.precision,
    };
    final testPrecision = {
      'jmaStyle': acc.test.jmaStyle.precision,
      'plumR30D050': acc.test.plumR30D050.precision,
      'baselineMax': acc.test.baselineMax.precision,
    };
    final precisionDelta = {
      'jmaStyle': testPrecision['jmaStyle']! - validationPrecision['jmaStyle']!,
      'plumR30D050':
          testPrecision['plumR30D050']! - validationPrecision['plumR30D050']!,
      'baselineMax':
          testPrecision['baselineMax']! - validationPrecision['baselineMax']!,
    };
    // drop 最大 = precision delta 最小(最负)。并列时按声明顺序取首个。
    final largestDropComponent = _largestDropComponent(precisionDelta);

    thresholdsJson[threshold.label] = {
      'splits': {
        'validation': {
          'jmaStyle': acc.validation.jmaStyle.toJson(),
          'plumR30D050': acc.validation.plumR30D050.toJson(),
          'baselineMax': acc.validation.baselineMax.toJson(),
        },
        'test': {
          'jmaStyle': acc.test.jmaStyle.toJson(),
          'plumR30D050': acc.test.plumR30D050.toJson(),
          'baselineMax': acc.test.baselineMax.toJson(),
        },
      },
      'precisionDelta': precisionDelta,
      'largestDropComponent': largestDropComponent,
      'regionBuckets': {
        'validation': _bucketJson(acc.validationByRegion),
        'test': _bucketJson(acc.testByRegion),
      },
      'distanceBuckets': {
        'validation': _bucketJson(acc.validationByDistance),
        'test': _bucketJson(acc.testByDistance),
      },
      'fpTriggerSource': {
        'validation': acc.validationFpTrigger.toJson(),
        'test': acc.testFpTrigger.toJson(),
      },
    };
  }

  return {
    'schemaVersion': 'raw_intensity_frozen_source_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'oneShotCompliance':
          '此诊断不违反 confidence band wording 层 one-shot spent 原则,'
          '因为它不涉及 wording 层、不调参、不重跑 confidence band 评估;'
          '它只分解 raw intensity 在 frozen test 上的表现',
      'method':
          'decompose baseline max(JMA-style, PLUM r30/d0.50) frozen test '
          'precision drop into per-component contributions across validation '
          'and test splits, by region/distance bucket and FP trigger source',
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'method': 'max_jma_style_plum_like_r30_d0_50',
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
      'splits': ['validation', 'test'],
    },
    'coverage': {
      'validationStationForecasts': validationStationForecasts,
      'testStationForecasts': testStationForecasts,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'thresholds': thresholdsJson,
    'errors': errors,
  };
}

Map<String, Object?> _bucketJson(Map<String, _ComponentMetrics> buckets) {
  // 每个桶的每个组件只记 TP/FP/FN + precision(用于算 precision)。
  final result = <String, Object?>{};
  for (final entry in buckets.entries) {
    result[entry.key] = {
      'jmaStyle': entry.value.jmaStyle.toPrecisionJson(),
      'plumR30D050': entry.value.plumR30D050.toPrecisionJson(),
      'baselineMax': entry.value.baselineMax.toPrecisionJson(),
    };
  }
  return result;
}

String _largestDropComponent(Map<String, double> precisionDelta) {
  // drop 最大 = delta 最小(最负)。并列时按声明顺序取首个。
  const order = ['jmaStyle', 'plumR30D050', 'baselineMax'];
  var best = order.first;
  var bestValue = precisionDelta[best]!;
  for (final name in order.skip(1)) {
    final value = precisionDelta[name]!;
    if (value < bestValue) {
      best = name;
      bestValue = value;
    }
  }
  return best;
}

String rawIntensityFrozenSourceDiagnosticMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final inputs = _map(report['inputs']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# Raw Intensity Frozen Source Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Splits: `${inputs['splits']}`')
    ..writeln('- Method: `${inputs['method']}`')
    ..writeln(
      '- Frozen test evaluated (diagnostic only): '
      '`${policy['frozenTestEvaluated']}`',
    )
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
    ..writeln(
      '- Validation station forecasts: '
      '`${coverage['validationStationForecasts']}`',
    )
    ..writeln(
      '- Test station forecasts: `${coverage['testStationForecasts']}`',
    )
    ..writeln(
      '- Skipped missing-magnitude events: '
      '`${coverage['skippedMissingMagnitudeEvents']}`',
    )
    ..writeln(
      '- Skipped no-source-estimate variants: '
      '`${coverage['skippedNoSourceEstimateVariants']}`',
    )
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This is a non-suppressive diagnostic: it does not modify raw '
      'predicted intensity, does not connect to UI/wording, and does not '
      'tune any parameter.',
    )
    ..writeln(
      '- It reuses `SyntheticRevealDatasetBuilder` to build validation and '
      'test synthetic reveal datasets, and reuses `StaticIntensityLocator`, '
      '`JmaStyleIntensityPredictor`, `PlumLikeIntensityPredictor(r=30km, '
      'd=0.50/km)` exactly as the frozen evaluation tool does.',
    )
    ..writeln(
      '- baseline = `max(JMA-style, PLUM r30/d0.50)`. Region bucket uses '
      'estimated-source latitude (production-available); distance bucket '
      'uses estimated-source → station haversine distance.',
    )
    ..writeln(
      '- FP trigger source decomposes each baseline FP into `jma_only`, '
      '`plum_only`, or `both` based on which component crossed the threshold.',
    )
    ..writeln(
      '- One-shot compliance: this diagnostic does not touch the confidence '
      'band wording layer, does not tune parameters, and does not re-run the '
      'confidence band frozen evaluation. It only decomposes raw intensity '
      'performance on the frozen test split.',
    )
    ..writeln();

  for (final threshold in _thresholds) {
    final tJson = _map(thresholds[threshold.label]);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Three-Component P/R/F1 (validation vs test)')
      ..writeln()
      ..writeln('| Component | Split | TP | FP | FN | TN | Precision | Recall | F1 |')
      ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    final splits = _map(tJson['splits']);
    for (final splitName in const ['validation', 'test']) {
      final split = _map(splits[splitName]);
      for (final component in const ['jmaStyle', 'plumR30D050', 'baselineMax']) {
        final c = _map(split[component]);
        buffer.writeln(
          '| `$component` | $splitName | ${c['truePositive']} | '
          '${c['falsePositive']} | ${c['falseNegative']} | '
          '${c['trueNegative']} | ${_pct(c['precision'])} | '
          '${_pct(c['recall'])} | ${_pct(c['f1'])} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('### Precision Delta (test − validation)')
      ..writeln()
      ..writeln('| Component | Validation P | Test P | Delta |')
      ..writeln('| --- | ---: | ---: | ---: |');
    final precisionDelta = _map(tJson['precisionDelta']);
    final splits2 = _map(tJson['splits']);
    final valSplit = _map(splits2['validation']);
    final testSplit = _map(splits2['test']);
    final largestDrop = tJson['largestDropComponent'].toString();
    for (final component in const ['jmaStyle', 'plumR30D050', 'baselineMax']) {
      final valP = _number(_map(valSplit[component])['precision']);
      final testP = _number(_map(testSplit[component])['precision']);
      final delta = _number(precisionDelta[component]);
      final marker = component == largestDrop ? ' **(largest drop)**' : '';
      buffer.writeln(
        '| `$component` | ${_pct(valP)} | ${_pct(testP)} | '
        '${_signedPct(delta)}$marker |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Region Buckets (precision by estimated-source latitude)')
      ..writeln()
      ..writeln('| Region | Split | jmaStyle P | plumR30D050 P | baselineMax P |')
      ..writeln('| --- | --- | ---: | ---: | ---: |');
    final regionBuckets = _map(tJson['regionBuckets']);
    final valRegions = _map(regionBuckets['validation']);
    final testRegions = _map(regionBuckets['test']);
    for (final region in _regions) {
      final vRow = _map(valRegions[region]);
      final tRow = _map(testRegions[region]);
      buffer.writeln(
        '| `$region` | validation | ${_pct(_map(vRow['jmaStyle'])['precision'])} | '
        '${_pct(_map(vRow['plumR30D050'])['precision'])} | '
        '${_pct(_map(vRow['baselineMax'])['precision'])} |',
      );
      buffer.writeln(
        '| `$region` | test | ${_pct(_map(tRow['jmaStyle'])['precision'])} | '
        '${_pct(_map(tRow['plumR30D050'])['precision'])} | '
        '${_pct(_map(tRow['baselineMax'])['precision'])} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Distance Buckets (precision by estimated-source → station)')
      ..writeln()
      ..writeln('| Distance | Split | jmaStyle P | plumR30D050 P | baselineMax P |')
      ..writeln('| --- | --- | ---: | ---: | ---: |');
    final distanceBuckets = _map(tJson['distanceBuckets']);
    final valDistances = _map(distanceBuckets['validation']);
    final testDistances = _map(distanceBuckets['test']);
    for (final distance in _distances) {
      final vRow = _map(valDistances[distance]);
      final tRow = _map(testDistances[distance]);
      buffer.writeln(
        '| `$distance` | validation | ${_pct(_map(vRow['jmaStyle'])['precision'])} | '
        '${_pct(_map(vRow['plumR30D050'])['precision'])} | '
        '${_pct(_map(vRow['baselineMax'])['precision'])} |',
      );
      buffer.writeln(
        '| `$distance` | test | ${_pct(_map(tRow['jmaStyle'])['precision'])} | '
        '${_pct(_map(tRow['plumR30D050'])['precision'])} | '
        '${_pct(_map(tRow['baselineMax'])['precision'])} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### FP Trigger Source (baseline FP decomposition)')
      ..writeln()
      ..writeln('| Split | jma_only | plum_only | both |')
      ..writeln('| --- | ---: | ---: | ---: |');
    final fpTrigger = _map(tJson['fpTriggerSource']);
    for (final splitName in const ['validation', 'test']) {
      final row = _map(fpTrigger[splitName]);
      buffer.writeln(
        '| $splitName | ${row['jma_only']} | ${row['plum_only']} | '
        '${row['both']} |',
      );
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Non-suppressive: this diagnostic does not modify raw predicted '
        'intensity, does not connect to UI/notifications/wording, and does not '
        'tune any parameter.')
    ..writeln('- One-shot compliance: it does not re-run the confidence band '
        'wording layer frozen evaluation and therefore does not spend the '
        'one-shot budget for that layer.')
    ..writeln('- This is a prerequisite diagnostic for improving raw intensity '
        'frozen migration; results here do not authorize production UI.')
    ..writeln();
  return buffer.toString();
}

class _ThresholdAccumulator {
  final validation = _ComponentMetrics();
  final test = _ComponentMetrics();
  final validationByRegion = <String, _ComponentMetrics>{};
  final testByRegion = <String, _ComponentMetrics>{};
  final validationByDistance = <String, _ComponentMetrics>{};
  final testByDistance = <String, _ComponentMetrics>{};
  final validationFpTrigger = _FpTriggerCounts();
  final testFpTrigger = _FpTriggerCounts();
}

class _ComponentMetrics {
  final jmaStyle = _ComponentCounts();
  final plumR30D050 = _ComponentCounts();
  final baselineMax = _ComponentCounts();
}

class _ComponentCounts {
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

  double get precision => truePositive + falsePositive == 0
      ? 0.0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0.0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0.0
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

  // 分桶里每个组件只记 TP/FP/FN + precision(用于算 precision)。
  Map<String, Object?> toPrecisionJson() => {
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'precision': precision,
  };
}

class _FpTriggerCounts {
  var jmaOnly = 0;
  var plumOnly = 0;
  var both = 0;

  Map<String, Object?> toJson() => {
    'jma_only': jmaOnly,
    'plum_only': plumOnly,
    'both': both,
  };
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

// region 分桶:估计震源纬度带,与 frozen regression diagnostic 的
// _eventLatitudeBucket 一致。
String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

// distance 分桶:与 frozen regression diagnostic 的 _distanceBucket 一致。
String _distanceBucket(double distanceKm) {
  if (distanceKm < 30) return '000_030km';
  if (distanceKm < 60) return '030_060km';
  if (distanceKm < 100) return '060_100km';
  if (distanceKm < 200) return '100_200km';
  return 'gt_200km';
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
  'schemaVersion': 'raw_intensity_frozen_source_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'oneShotCompliance':
        '此诊断不违反 confidence band wording 层 one-shot spent 原则,'
        '因为它不涉及 wording 层、不调参、不重跑 confidence band 评估;'
        '它只分解 raw intensity 在 frozen test 上的表现',
    'method':
        'decompose baseline max(JMA-style, PLUM r30/d0.50) frozen test '
        'precision drop into per-component contributions across validation '
        'and test splits, by region/distance bucket and FP trigger source',
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'modelPath': modelPath,
    'method': 'max_jma_style_plum_like_r30_d0_50',
    'plumRadiusKm': _plumRadiusKm,
    'plumDampingPer10Km': _plumDampingPer10Km,
    'splits': ['validation', 'test'],
  },
  'coverage': {
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

List<Object?> _list(Object? value) => value is List ? value : const [];

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(value?.toString() ?? '0');
}

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(Object? value) {
  final number = _number(value);
  final sign = number > 0 ? '+' : '';
  return '$sign${(number * 100).toStringAsFixed(1)}%';
}
