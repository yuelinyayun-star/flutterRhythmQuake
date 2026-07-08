import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

import 'build_plum_evidence_robustness_calibration_report.dart' as calibration;

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultValidationDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_confidence_band_frozen_evaluation/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_confidence_band_frozen_evaluation.generated.md';

// F-criteria tolerances — pre-registered in the roadmap acceptance section.
// 这些容差在看到 frozen 结果前已写定,不得事后调整。
const _highBandPrecisionHoldTolerance = 0.05;
const _bandCollapseTolerance = 0.15;
const _coverageHoldRatio = 0.5;
const _shindo4Threshold = 3.5;

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final validationDatasetPath =
      _argument(args, '--validation') ?? _defaultValidationDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumConfidenceBandFrozenEvaluationJson(
    dataDirectory: dataDirectory,
    validationDatasetPath: validationDatasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumConfidenceBandFrozenEvaluationMarkdown(report));

  stdout.writeln('wrote PLUM confidence-band frozen evaluation report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumConfidenceBandFrozenEvaluationJson({
  String dataDirectory = _defaultDataDirectory,
  String validationDatasetPath = _defaultValidationDatasetPath,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final validationFile = File(validationDatasetPath);
  final modelFile = File(modelPath);
  final splitFile = File('$dataDirectory/splits.json');
  final annualFiles = [
    File('$dataDirectory/jma_final_intensity_2020.json'),
    File('$dataDirectory/jma_final_intensity_2021.json'),
    File('$dataDirectory/jma_final_intensity_2022.json'),
  ];
  if (!validationFile.existsSync()) {
    errors.add('validation_dataset_missing:$validationDatasetPath');
  }
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
      validationDatasetPath: validationDatasetPath,
      modelPath: modelPath,
    );
  }

  // 1. 在进程内重建 validation 校准查找表(确定性,与 validation split 一致)。
  final validationCalibration =
      calibration.buildPlumEvidenceRobustnessCalibrationReportJson(
    validationDatasetPath: validationDatasetPath,
    modelPath: modelPath,
  );
  if (validationCalibration['status'] != 'pass') {
    errors.add('validation_calibration_not_pass');
  }
  final validationShindo4 = _map(
    _map(validationCalibration['thresholds'])['shindo4'],
  );
  final lookup = <String, String>{};
  for (final raw in _list(validationShindo4['jointBuckets'])) {
    final bucket = _map(raw);
    final key = '${bucket['branchAgreement']}|${bucket['robustnessScore']}';
    lookup[key] = bucket['band'].toString();
  }
  final validationBandSummary = _map(validationShindo4['bandSummary']);
  final validationBands = {
    for (final name in const ['high', 'medium', 'low', 'insufficient'])
      name: _BandMetrics.fromJson(_map(validationBandSummary[name])),
  };
  final validationBaseline = _map(validationShindo4['baseline']);
  final validationTotalPred = validationBands.values
      .fold<int>(0, (sum, band) => sum + band.predictedPositive);
  final validationHighMediumShare = validationTotalPred == 0
      ? 0.0
      : (validationBands['high']!.predictedPositive +
              validationBands['medium']!.predictedPositive) /
          validationTotalPred;

  // 2. 构建 frozen test synthetic reveal 数据集(2022 年度事件)。
  final annualDatasets = [
    for (final file in annualFiles)
      decodeJmaIntensityDataset(file.readAsStringSync()),
  ];
  final splits =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final synthetic = const SyntheticRevealDatasetBuilder(
    generatedSplits: ['test'],
  ).build(annualDatasets: annualDatasets, splitManifest: splits);
  final testDataset = synthetic.datasetsBySplit['test']!;

  // 3. 加载模型与预测器(与校准工具完全一致)。
  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumR30D050 = const PlumLikeIntensityPredictor(
    radiusKm: 30,
    dampingPer10Km: 0.50,
  );
  final plumR20D050 = const PlumLikeIntensityPredictor(
    radiusKm: 20,
    dampingPer10Km: 0.50,
  );
  final plumR30D075 = const PlumLikeIntensityPredictor(
    radiusKm: 30,
    dampingPer10Km: 0.75,
  );

  // 4. 遍历 frozen test,对每个 shindo4 预测正例查 band,累计 TP/FP。
  final frozenBands = {
    for (final name in const ['high', 'medium', 'low', 'insufficient'])
      name: _BandMetrics(),
  };
  var truePositive = 0, falsePositive = 0, falseNegative = 0, trueNegative = 0;
  var stationForecastCount = 0;
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final rawEvent in _list(testDataset['events'])) {
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
        final r30 = plumR30D050.predict(
          targetStation: station,
          observedStations: retained,
        );
        final r20 = plumR20D050
            .predict(targetStation: station, observedStations: retained)
            .intensity;
        final r30D075 = plumR30D075
            .predict(targetStation: station, observedStations: retained)
            .intensity;
        final baselineRaw = math.max(jma, r30.intensity);
        final actual = station.intensity >= _shindo4Threshold;
        final predicted = baselineRaw >= _shindo4Threshold;
        if (actual && predicted) {
          truePositive++;
        } else if (!actual && predicted) {
          falsePositive++;
        } else if (actual && !predicted) {
          falseNegative++;
        } else {
          trueNegative++;
        }
        if (predicted) {
          final branch = _branchAgreement(
            jma: jma,
            r20: r20,
            r30D075: r30D075,
            threshold: _shindo4Threshold,
          );
          final score = _robustnessScore(
            maskRate: variant.maskRate,
            retainedCount: retained.length,
            evidenceCount: r30.evidenceCount,
            nearestEvidenceDistanceKm: r30.nearestEvidenceDistanceKm,
            jma: jma,
            r20: r20,
            r30D075: r30D075,
            threshold: _shindo4Threshold,
          );
          final key = '$branch|score_$score';
          final band = lookup[key] ?? 'insufficient';
          frozenBands[band]!.add(actualPositive: actual);
        }
        stationForecastCount++;
      }
    }
  }

  if (stationForecastCount == 0) {
    errors.add('no_frozen_station_forecasts');
  }

  final frozenTotalPred = frozenBands.values
      .fold<int>(0, (sum, band) => sum + band.predictedPositive);
  final frozenHighMediumShare = frozenTotalPred == 0
      ? 0.0
      : (frozenBands['high']!.predictedPositive +
              frozenBands['medium']!.predictedPositive) /
          frozenTotalPred;

  // 5. 检查 F1-F4。
  final checks = <String, Map<String, Object?>>{};
  final frozenHigh = frozenBands['high']!;
  final frozenMedium = frozenBands['medium']!;
  final frozenLow = frozenBands['low']!;
  checks['F1_band_monotonicity'] = _monotonicityCheck(
    frozenHigh.precision,
    frozenMedium.precision,
    frozenLow.precision,
  );
  checks['F2_high_precision_hold'] = _minCheck(
    actual: frozenHigh.precision,
    limit: validationBands['high']!.precision - _highBandPrecisionHoldTolerance,
    note:
        'frozen P(high) >= validation P(high) '
        '(${_pct(validationBands['high']!.precision)}) - '
        '${_pct(_highBandPrecisionHoldTolerance)}',
  );
  for (final name in const ['high', 'medium', 'low']) {
    checks['F3_no_collapse_$name'] = _minCheck(
      actual: frozenBands[name]!.precision,
      limit: validationBands[name]!.precision - _bandCollapseTolerance,
      note:
          'frozen P($name) >= validation P($name) '
          '(${_pct(validationBands[name]!.precision)}) - '
          '${_pct(_bandCollapseTolerance)}',
    );
  }
  checks['F4_coverage_hold'] = _minCheck(
    actual: frozenHighMediumShare,
    limit: validationHighMediumShare * _coverageHoldRatio,
    note:
        'frozen share(high+medium) >= '
        '${_pct(_coverageHoldRatio)} * validation share(high+medium) '
        '(${_pct(validationHighMediumShare)})',
  );

  final failedChecks = [
    for (final entry in checks.entries)
      if (entry.value['status'] == 'fail') entry.key,
  ];
  final outcome = failedChecks.isEmpty ? 'pass' : 'fail';

  return {
    'schemaVersion': 'plum_confidence_band_frozen_evaluation_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'split': 'test',
      'frozenTestEvaluated': true,
      'oneShot': true,
      'productionReady': false,
      'productionUiConnected': false,
      'rawPredictedIntensityMutated': false,
      'diagnosticOnly': true,
      'method':
          'one-shot frozen evaluation of the validation-derived confidence '
          'band lookup against F1-F4; band labels come from validation only '
          'and are not recomputed on test',
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'validationDatasetPath': validationDatasetPath,
      'modelPath': modelPath,
      'validationCalibrationSchemaVersion':
          validationCalibration['schemaVersion'],
      'validationCoverage': _map(validationCalibration['coverage']),
    },
    'validationReference': {
      'shindo4BaselinePrecision': validationBaseline['precision'],
      'bandPrecision': {
        for (final name in const ['high', 'medium', 'low', 'insufficient'])
          name: validationBands[name]!.precision,
      },
      'bandPredictedPositive': {
        for (final name in const ['high', 'medium', 'low', 'insufficient'])
          name: validationBands[name]!.predictedPositive,
      },
      'highMediumShare': validationHighMediumShare,
    },
    'frozenCoverage': {
      'stationForecastCount': stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
      'totalPredictedPositive': frozenTotalPred,
    },
    'frozenBaseline': {
      'truePositive': truePositive,
      'falsePositive': falsePositive,
      'falseNegative': falseNegative,
      'trueNegative': trueNegative,
      'precision': truePositive + falsePositive == 0
          ? 0.0
          : truePositive / (truePositive + falsePositive),
      'recall': truePositive + falseNegative == 0
          ? 0.0
          : truePositive / (truePositive + falseNegative),
    },
    'frozenBands': {
      for (final name in const ['high', 'medium', 'low', 'insufficient'])
        name: frozenBands[name]!.toJson(),
    },
    'frozenHighMediumShare': frozenHighMediumShare,
    'criteriaChecks': checks,
    'outcome': {
      'frozenEvaluationStatus': outcome,
      'failedChecks': failedChecks,
      'advanceToProductionUi': false,
      'nextAction': outcome == 'pass'
          ? 'write_ui_wording_readiness_gate'
          : 'block_ui_wording_keep_confidence_band_validation_only',
    },
    'errors': errors,
  };
}

String plumConfidenceBandFrozenEvaluationMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final frozenCoverage = _map(report['frozenCoverage']);
  final frozenBaseline = _map(report['frozenBaseline']);
  final validationRef = _map(report['validationReference']);
  final frozenBands = _map(report['frozenBands']);
  final checks = _map(report['criteriaChecks']);
  final outcome = _map(report['outcome']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Confidence-Band Frozen Evaluation')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `${policy['split']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- One-shot: `${policy['oneShot']}`')
    ..writeln('- Production UI connected: `${policy['productionUiConnected']}`')
    ..writeln(
      '- Raw predicted intensity mutated: '
      '`${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln('- Outcome: `${outcome['frozenEvaluationStatus']}`')
    ..writeln()
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This is the single one-shot frozen evaluation of the shindo4 '
      'confidence-band wording layer. Band labels are looked up from the '
      'validation calibration table only; they are not recomputed on test.',
    )
    ..writeln(
      '- Raw predicted intensity is not modified. The band is a separate '
      'diagnostic field layered on top.',
    )
    ..writeln(
      '- F1-F4 are pre-registered in the roadmap acceptance section and were '
      'not tuned after seeing frozen results.',
    )
    ..writeln()
    ..writeln('## Validation Reference (shindo4)')
    ..writeln()
    ..writeln('| Band | Validation precision | Validation pred+ |')
    ..writeln('| --- | ---: | ---: |');
  final valPrecision = _map(validationRef['bandPrecision']);
  final valPred = _map(validationRef['bandPredictedPositive']);
  for (final name in const ['high', 'medium', 'low', 'insufficient']) {
    buffer.writeln(
      '| `$name` | ${_pct(valPrecision[name])} | ${valPred[name]} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Frozen Test (shindo4)')
    ..writeln()
    ..writeln(
      '- Station forecasts: `${frozenCoverage['stationForecastCount']}`',
    )
    ..writeln(
      '- Total predicted positives: `${frozenCoverage['totalPredictedPositive']}`',
    )
    ..writeln(
      '- Baseline P/R: `${_pct(frozenBaseline['precision'])} / '
      '${_pct(frozenBaseline['recall'])}`',
    )
    ..writeln()
    ..writeln('| Band | Frozen pred+ | Frozen TP | Frozen FP | Frozen precision |')
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  for (final name in const ['high', 'medium', 'low', 'insufficient']) {
    final band = _map(frozenBands[name]);
    buffer.writeln(
      '| `$name` | ${band['predictedPositive']} | ${band['truePositive']} | '
      '${band['falsePositive']} | ${_pct(band['precision'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Criteria Checks (F1-F4)')
    ..writeln()
    ..writeln('| Check | Status | Actual | Required |')
    ..writeln('| --- | --- | ---: | ---: |');
  for (final entry in checks.entries) {
    final check = _map(entry.value);
    final actual = check['actual'];
    final actualText = actual is Map
        ? 'high=${_pct(_map(actual)['high'])} / '
            'medium=${_pct(_map(actual)['medium'])} / '
            'low=${_pct(_map(actual)['low'])}'
        : _pct(actual);
    buffer.writeln(
      '| `${entry.key}` | `${check['status']}` | '
      '$actualText | `${check['note']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Advance to production UI: `${outcome['advanceToProductionUi']}`')
    ..writeln('- Next action: `${outcome['nextAction']}`')
    ..writeln()
    ..writeln(
      'This is the single one-shot frozen evaluation for the shindo4 '
      'confidence-band wording layer. It does not authorize production UI, '
      'notifications or warning wording.',
    )
    ..writeln();
  return buffer.toString();
}

class _BandMetrics {
  var predictedPositive = 0;
  var truePositive = 0;
  var falsePositive = 0;

  _BandMetrics();

  factory _BandMetrics.fromJson(Map<String, Object?> json) {
    final band = _BandMetrics();
    band.predictedPositive = _int(json['predictedPositive']);
    band.truePositive = _int(json['truePositive']);
    band.falsePositive = _int(json['falsePositive']);
    return band;
  }

  void add({required bool actualPositive}) {
    predictedPositive++;
    if (actualPositive) {
      truePositive++;
    } else {
      falsePositive++;
    }
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;

  Map<String, Object?> toJson() => {
    'predictedPositive': predictedPositive,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'precision': precision,
  };
}

Map<String, Object?> _monotonicityCheck(
  double high,
  double medium,
  double low,
) {
  final pass = high > medium && medium > low;
  return {
    'actual': {'high': high, 'medium': medium, 'low': low},
    'limit': 'P(high) > P(medium) > P(low)',
    'note': 'frozen band monotonicity P(high)>P(medium)>P(low)',
    'status': pass ? 'pass' : 'fail',
  };
}

Map<String, Object?> _minCheck({
  required double actual,
  required double limit,
  required String note,
}) => {
  'actual': actual,
  'limit': limit,
  'note': note,
  'status': actual >= limit ? 'pass' : 'fail',
};

// 与校准工具完全一致的 branchAgreement / robustnessScore 定义。复制以保持工具自包含。
String _branchAgreement({
  required double jma,
  required double r20,
  required double r30D075,
  required double threshold,
}) {
  final agree = [
    jma >= threshold,
    r20 >= threshold,
    r30D075 >= threshold,
  ].where((value) => value).length;
  return 'agree_$agree';
}

int _robustnessScore({
  required double maskRate,
  required int retainedCount,
  required int evidenceCount,
  required double nearestEvidenceDistanceKm,
  required double jma,
  required double r20,
  required double r30D075,
  required double threshold,
}) {
  var score = 0;
  if (maskRate <= 0.5) score++;
  if (retainedCount >= 8) score++;
  if (evidenceCount >= 2) score++;
  if (nearestEvidenceDistanceKm <= 20) score++;
  score += [
    jma >= threshold,
    r20 >= threshold,
    r30D075 >= threshold,
  ].where((value) => value).length;
  return score;
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'plum_confidence_band_frozen_evaluation_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': const {
    'split': 'test',
    'frozenTestEvaluated': true,
    'oneShot': true,
    'productionReady': false,
    'productionUiConnected': false,
    'rawPredictedIntensityMutated': false,
    'diagnosticOnly': true,
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'validationDatasetPath': validationDatasetPath,
    'modelPath': modelPath,
  },
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

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value?.toString() ?? '0');
}

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';
