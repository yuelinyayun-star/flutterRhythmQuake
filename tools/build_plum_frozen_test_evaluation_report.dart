import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';

import 'build_combined_intensity_prediction_report.dart' as combined_report;

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultCriteriaPath =
    '.dart_tool/plum_frozen_test_acceptance_criteria/report.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputDirectory = '.dart_tool/plum_frozen_test_evaluation';
const _defaultMarkdownPath =
    'docs/baselines/plum_frozen_test_evaluation.generated.md';

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final criteriaPath = _argument(args, '--criteria') ?? _defaultCriteriaPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputDirectory =
      _argument(args, '--output-directory') ?? _defaultOutputDirectory;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumFrozenTestEvaluationReportJson(
    dataDirectory: dataDirectory,
    criteriaPath: criteriaPath,
    modelPath: modelPath,
    outputDirectory: outputDirectory,
  );

  final output = File('$outputDirectory/report.json')
    ..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumFrozenTestEvaluationMarkdown(report));

  stdout.writeln('wrote PLUM frozen-test evaluation report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumFrozenTestEvaluationReportJson({
  String dataDirectory = _defaultDataDirectory,
  String criteriaPath = _defaultCriteriaPath,
  String modelPath = _defaultModelPath,
  String outputDirectory = _defaultOutputDirectory,
}) {
  final errors = <String>[];
  final warnings = <String>[];
  final criteriaFile = File(criteriaPath);
  final modelFile = File(modelPath);
  final splitFile = File('$dataDirectory/splits.json');
  final annualFiles = [
    File('$dataDirectory/jma_final_intensity_2020.json'),
    File('$dataDirectory/jma_final_intensity_2021.json'),
    File('$dataDirectory/jma_final_intensity_2022.json'),
  ];
  if (!criteriaFile.existsSync()) errors.add('criteria_missing:$criteriaPath');
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
      warnings: warnings,
      dataDirectory: dataDirectory,
      criteriaPath: criteriaPath,
      modelPath: modelPath,
      outputDirectory: outputDirectory,
    );
  }

  final criteria =
      jsonDecode(criteriaFile.readAsStringSync()) as Map<String, Object?>;
  if (criteria['schemaVersion'] != 'plum_frozen_test_acceptance_criteria_v1') {
    errors.add('invalid_criteria_schema:${criteria['schemaVersion']}');
  }
  if (criteria['status'] != 'pass') errors.add('criteria_not_pass');
  final criteriaPolicy = _map(criteria['policy']);
  if (criteriaPolicy['frozenTestEvaluated'] != false) {
    errors.add('criteria_already_evaluated_frozen_test');
  }
  if (criteriaPolicy['productionReady'] != false ||
      criteriaPolicy['productionUiConnected'] != false) {
    errors.add('criteria_crosses_production_boundary');
  }

  final annualDatasets = [
    for (final file in annualFiles)
      decodeJmaIntensityDataset(file.readAsStringSync()),
  ];
  final splits =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final synthetic = const SyntheticRevealDatasetBuilder(
    generatedSplits: ['test'],
  ).build(annualDatasets: annualDatasets, splitManifest: splits);
  final outputDir = Directory(outputDirectory)..createSync(recursive: true);
  final testDatasetPath = '${outputDir.path}/synthetic_reveal_test.json';
  _writeJson(
    File('${outputDir.path}/synthetic_reveal_manifest.json'),
    synthetic.manifest,
  );
  _writeJson(File(testDatasetPath), synthetic.datasetsBySplit['test']!);
  _writeJson(
    File('${outputDir.path}/synthetic_reveal_quality_report.json'),
    synthetic.qualityReport,
  );

  final combined = combined_report.buildCombinedIntensityPredictionReportJson(
    validationDatasetPath: testDatasetPath,
    modelPath: modelPath,
    reportSplit: 'test',
    frozenTestEvaluated: true,
  );
  _writeJson(File('${outputDir.path}/combined_report.json'), combined);
  if (combined['status'] != 'pass') {
    errors.add('combined_frozen_report_not_pass');
  }
  final selected = _map(criteria['selectedOperatingPoint']);
  final methodId = selected['maxMethodId']?.toString() ?? '';
  final method = _map(_map(combined['methods'])[methodId]);
  if (method.isEmpty) errors.add('selected_method_missing:$methodId');
  final checks = _checks(criteria: criteria, method: method);
  final failedChecks = [
    for (final entry in checks.entries)
      if (entry.value['status'] == 'fail') entry.key,
  ];
  final warnChecks = [
    for (final entry in checks.entries)
      if (entry.value['status'] == 'warn') entry.key,
  ];
  if (warnChecks.isNotEmpty) {
    warnings.add('frozen_criteria_warning:${warnChecks.join(',')}');
  }
  final outcome = failedChecks.isEmpty
      ? (warnChecks.isEmpty ? 'pass' : 'warn')
      : 'fail';

  return {
    'schemaVersion': 'plum_frozen_test_evaluation_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'split': 'test',
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'selectedForProduction': false,
      'rawIntensityFieldMutated': false,
      'sourceEstimationCoordinateSwitchAllowed': false,
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'criteriaPath': criteriaPath,
      'modelPath': modelPath,
      'syntheticRevealTestPath': testDatasetPath,
      'combinedReportPath': '${outputDir.path}/combined_report.json',
    },
    'selectedOperatingPoint': selected,
    'syntheticRevealQuality': synthetic.qualityReport,
    'combinedSummary': _map(method['summary']),
    'combinedThresholds': _map(method['thresholds']),
    'criteriaChecks': checks,
    'outcome': {
      'frozenEvaluationStatus': outcome,
      'failedChecks': failedChecks,
      'warningChecks': warnChecks,
      'advanceToProduction': false,
      'nextAction': outcome == 'pass'
          ? 'write_production_readiness_gate'
          : 'diagnose_frozen_test_regression_before_any_production_gate',
    },
    'warnings': warnings,
    'errors': errors,
  };
}

Map<String, Map<String, Object?>> _checks({
  required Map<String, Object?> criteria,
  required Map<String, Object?> method,
}) {
  final synthetic = _map(criteria['syntheticRevealFrozenCriteria']);
  final summary = _map(method['summary']);
  final thresholds = _map(method['thresholds']);
  final shindo4 = _map(thresholds['shindo4']);
  final shindo5 = _map(thresholds['shindo5-']);
  return {
    'maxClassMae': _maxCheck(
      actual: _number(summary['maxClassMae']),
      limit: _number(synthetic['maxClassMaeMax']),
    ),
    'maxClassUnderestimateRate': _maxCheck(
      actual: _number(summary['maxClassUnderestimateRate']),
      limit: _number(synthetic['maxClassUnderestimateRateMax']),
    ),
    'maxClassWithinOneAccuracy': _minCheck(
      actual: _number(summary['maxClassWithinOneAccuracy']),
      limit: _number(synthetic['maxClassWithinOneAccuracyMin']),
    ),
    'shindo4Precision': _minCheck(
      actual: _number(shindo4['precision']),
      limit: _number(synthetic['shindo4PrecisionMin']),
    ),
    'shindo4Recall': _minCheck(
      actual: _number(shindo4['recall']),
      limit: _number(synthetic['shindo4RecallMin']),
    ),
    'shindo4F1': _minCheck(
      actual: _number(shindo4['f1']),
      limit: _number(synthetic['shindo4F1Min']),
    ),
    'shindo5MinusPrecision': _minCheck(
      actual: _number(shindo5['precision']),
      limit: _number(synthetic['shindo5MinusPrecisionMin']),
    ),
    'shindo5MinusRecall': _minCheck(
      actual: _number(shindo5['recall']),
      limit: _number(synthetic['shindo5MinusRecallMin']),
    ),
    'shindo5MinusF1': _minCheck(
      actual: _number(shindo5['f1']),
      limit: _number(synthetic['shindo5MinusF1Min']),
    ),
  };
}

Map<String, Object?> _minCheck({double? actual, double? limit}) => {
  'actual': actual,
  'limit': limit,
  'operator': '>=',
  'status': actual == null || limit == null
      ? 'fail'
      : (actual >= limit ? 'pass' : 'fail'),
};

Map<String, Object?> _maxCheck({double? actual, double? limit}) => {
  'actual': actual,
  'limit': limit,
  'operator': '<=',
  'status': actual == null || limit == null
      ? 'fail'
      : (actual <= limit ? 'pass' : 'fail'),
};

String plumFrozenTestEvaluationMarkdown(Map<String, Object?> report) {
  final selected = _map(report['selectedOperatingPoint']);
  final summary = _map(report['combinedSummary']);
  final outcome = _map(report['outcome']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Frozen-Test Evaluation')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `test`')
    ..writeln('- Frozen test evaluated: `true`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Production UI connected: `false`')
    ..writeln('- Candidate: `${selected['candidateId']}`')
    ..writeln('- Outcome: `${outcome['frozenEvaluationStatus']}`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Cases | `${summary['caseCount']}` |')
    ..writeln('| Max-class MAE | `${_fmt(summary['maxClassMae'])}` |')
    ..writeln(
      '| Max-class underestimation | `${_pct(summary['maxClassUnderestimateRate'])}` |',
    )
    ..writeln(
      '| Max-class within one | `${_pct(summary['maxClassWithinOneAccuracy'])}` |',
    )
    ..writeln()
    ..writeln('## Criteria Checks')
    ..writeln()
    ..writeln('| Check | Status | Actual | Required |')
    ..writeln('| --- | --- | ---: | ---: |');
  for (final entry in _map(report['criteriaChecks']).entries) {
    final check = _map(entry.value);
    buffer.writeln(
      '| `${entry.key}` | `${check['status']}` | '
      '`${_fmtCheck(entry.key, check['actual'])}` | '
      '`${check['operator']} ${_fmtCheck(entry.key, check['limit'])}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Advance to production: `${outcome['advanceToProduction']}`')
    ..writeln('- Next action: `${outcome['nextAction']}`')
    ..writeln()
    ..writeln(
      'This is the single frozen-test evaluation for the frozen diagnostic '
      'operating point. It does not authorize production UI, notifications or '
      'warning wording.',
    )
    ..writeln();
  return buffer.toString();
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required List<String> warnings,
  required String dataDirectory,
  required String criteriaPath,
  required String modelPath,
  required String outputDirectory,
}) => {
  'schemaVersion': 'plum_frozen_test_evaluation_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': const {
    'split': 'test',
    'frozenTestEvaluated': false,
    'productionReady': false,
    'productionUiConnected': false,
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'criteriaPath': criteriaPath,
    'modelPath': modelPath,
    'outputDirectory': outputDirectory,
  },
  'outcome': const {
    'frozenEvaluationStatus': 'not_run',
    'advanceToProduction': false,
  },
  'warnings': warnings,
  'errors': errors,
};

void _writeJson(File file, Map<String, Object?> value) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
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

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _fmt(Object? value) {
  final number = _number(value);
  return number == null ? '-' : number.toStringAsFixed(3);
}

String _fmtCheck(String metric, Object? value) {
  final number = _number(value);
  if (number == null) return '-';
  if (metric.endsWith('Mae')) return number.toStringAsFixed(3);
  return _pct(number);
}

String _pct(Object? value) {
  final number = _number(value);
  return number == null ? '-' : '${(number * 100).toStringAsFixed(1)}%';
}
