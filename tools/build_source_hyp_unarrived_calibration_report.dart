import 'dart:convert';
import 'dart:io';

const _schemaVersion = 'source_hyp_unarrived_calibration_report_v1';
const _defaultInput = '.dart_tool/source_hyp_vs_hybrid_report/report.json';
const _defaultOutput =
    '.dart_tool/source_hyp_unarrived_calibration_report/report.json';
const _defaultMarkdown =
    'docs/baselines/source_hyp_unarrived_calibration_report.generated.md';
const _thresholds = [0.0, 2.0, 5.0, 10.0, 20.0, 40.0, 60.0, 80.0, 120.0, 160.0];

void main(List<String> args) {
  final inputPath = _argument(args, '--input') ?? _defaultInput;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = buildSourceHypUnarrivedCalibrationReportJson(
    inputFile: File(inputPath),
  );
  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(sourceHypUnarrivedCalibrationMarkdown(report));

  stdout.writeln('wrote HYP unarrived calibration report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

Map<String, Object?> buildSourceHypUnarrivedCalibrationReportJson({
  File? inputFile,
}) {
  final input = inputFile ?? File(_defaultInput);
  if (!input.existsSync()) {
    return {
      'schemaVersion': _schemaVersion,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'inputPath': input.path,
      'status': 'missing_input',
      'rows': const [],
      'thresholds': const [],
      'recommendation': null,
      'findings': const ['missing_hyp_vs_hybrid_report'],
    };
  }

  final decoded = jsonDecode(input.readAsStringSync());
  final sourceReport = _map(decoded);
  final rows = _list(sourceReport['rows']).map(_map).toList(growable: false);
  final thresholdRows = [
    for (final threshold in _thresholds)
      _thresholdRow(rows, threshold: threshold),
  ];
  final recommendation = _recommendedThreshold(thresholdRows);

  return {
    'schemaVersion': _schemaVersion,
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputPath': input.path,
    'status': 'pass',
    'policy': {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'calibrates': 'hyp_supported_unarrived_penalty_gate',
      'doesNotChangeCandidateSearch': true,
    },
    'baseline': {
      'sourceSchemaVersion': sourceReport['schemaVersion'],
      'caseCount': rows.length,
      'baseEligibleCount': rows.where(_baseEligible).length,
      'baseDepthEligibleCount': rows.where(_baseDepthEligible).length,
    },
    'thresholds': thresholdRows,
    'recommendation': recommendation,
    'findings': _findings(thresholdRows, recommendation),
  };
}

String sourceHypUnarrivedCalibrationMarkdown(Map<String, Object?> report) {
  final thresholds = _list(report['thresholds']).map(_map);
  final recommendation = _mapOrNull(report['recommendation']);
  final b = StringBuffer()
    ..writeln('# HYP unarrived-penalty calibration report')
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln('- Status: `${report['status']}`')
    ..writeln(
      '- Diagnostic only: `${_map(report['policy'])['diagnosticOnly']}`',
    );
  if (recommendation != null) {
    b
      ..writeln(
        '- Recommended max unarrived penalty: `${recommendation['threshold']}`',
      )
      ..writeln('- Reason: `${recommendation['reason']}`');
  }
  b
    ..writeln()
    ..writeln(
      '| Threshold | Supported | Depth supported | Improved | Regressed | Median HYP error | Median Δ | Verdict |',
    )
    ..writeln('|---:|---:|---:|---:|---:|---:|---:|---|');
  for (final row in thresholds) {
    b.writeln(
      '| ${_fmt(row['threshold'], digits: 0)} '
      '| ${row['supportedCount']} '
      '| ${row['depthSupportedCount']} '
      '| ${row['improvedCount']} '
      '| ${row['regressedCount']} '
      '| ${_fmt(row['medianHypErrorKm'])} '
      '| ${_fmt(row['medianDeltaKm'])} '
      '| ${row['verdict']} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Findings')
    ..writeln();
  for (final finding in _list(report['findings'])) {
    b.writeln('- `$finding`');
  }
  return b.toString();
}

Map<String, Object?> _thresholdRow(
  List<Map<String, Object?>> rows, {
  required double threshold,
}) {
  final supported = rows
      .where((row) => _baseEligible(row))
      .where(
        (row) =>
            (_number(row['hypUnarrivedPenalty']) ?? double.infinity) <=
            threshold,
      )
      .toList(growable: false);
  final depthSupported = supported
      .where(_baseDepthEligible)
      .toList(growable: false);
  final improved = supported
      .where((row) => _delta(row)! < 0)
      .toList(growable: false);
  final improvedBy10 = supported
      .where((row) => _delta(row)! <= -10)
      .toList(growable: false);
  final regressed = supported
      .where((row) => _delta(row)! > 10)
      .toList(growable: false);
  return {
    'threshold': threshold,
    'supportedCount': supported.length,
    'depthSupportedCount': depthSupported.length,
    'improvedCount': improved.length,
    'improvedBy10Count': improvedBy10.length,
    'regressedCount': regressed.length,
    'medianHypErrorKm': _median([
      for (final row in supported) _number(row['hypFinalErrorKm'])!,
    ]),
    'medianDeltaKm': _median([for (final row in supported) _delta(row)!]),
    'supportedCaseIds': [
      for (final row in supported) row['caseId']?.toString(),
    ],
    'regressedCaseIds': [
      for (final row in regressed) row['caseId']?.toString(),
    ],
    'improvedCaseIds': [for (final row in improved) row['caseId']?.toString()],
    'verdict': _verdict(
      supportedCount: supported.length,
      regressedCount: regressed.length,
    ),
  };
}

Map<String, Object?>? _recommendedThreshold(
  List<Map<String, Object?>> thresholdRows,
) {
  final safe = thresholdRows
      .where((row) => row['regressedCount'] == 0)
      .where((row) => (row['supportedCount'] as int) > 0)
      .toList(growable: false);
  if (safe.isEmpty) return null;
  safe.sort((a, b) {
    final supportCmp = (b['supportedCount'] as int).compareTo(
      a['supportedCount'] as int,
    );
    if (supportCmp != 0) return supportCmp;
    final medianA = _number(a['medianHypErrorKm']) ?? double.infinity;
    final medianB = _number(b['medianHypErrorKm']) ?? double.infinity;
    final medianCmp = medianA.compareTo(medianB);
    if (medianCmp != 0) return medianCmp;
    return (_number(a['threshold']) ?? double.infinity).compareTo(
      _number(b['threshold']) ?? double.infinity,
    );
  });
  final best = safe.first;
  return {
    'threshold': best['threshold'],
    'supportedCount': best['supportedCount'],
    'depthSupportedCount': best['depthSupportedCount'],
    'medianHypErrorKm': best['medianHypErrorKm'],
    'medianDeltaKm': best['medianDeltaKm'],
    'reason': 'max_supported_without_large_regression',
  };
}

List<String> _findings(
  List<Map<String, Object?>> thresholdRows,
  Map<String, Object?>? recommendation,
) {
  final findings = <String>[];
  if (recommendation == null) {
    findings.add('no_safe_unarrived_threshold_found');
    return findings;
  }
  findings.add(
    'recommended_threshold_${_fmt(recommendation['threshold'], digits: 0)}',
  );
  final unsafe = thresholdRows.where(
    (row) => (row['regressedCount'] as int) > 0,
  );
  if (unsafe.isNotEmpty) {
    findings.add('high_thresholds_admit_regressed_hyp_candidates');
  }
  final tooStrict = thresholdRows.where((row) => row['supportedCount'] == 0);
  if (tooStrict.isNotEmpty) findings.add('low_thresholds_are_too_strict');
  findings.add('calibration_is_gate_only_not_search_weight');
  return findings;
}

bool _baseEligible(Map<String, Object?> row) {
  final hypError = _number(row['hypFinalErrorKm']);
  final hybridError = _number(row['hybridFinalErrorKm']);
  final p = _integer(row['hypPhasePCount']) ?? 0;
  final s = _integer(row['hypPhaseSCount']) ?? 0;
  final residual = _number(row['hypPhaseMeanResidualSeconds']);
  final pair = _number(row['hypPairMeanResidualSeconds']);
  return hypError != null &&
      hybridError != null &&
      p >= 3 &&
      s >= 2 &&
      residual != null &&
      residual <= 2.8 &&
      pair != null &&
      pair <= 3.5;
}

bool _baseDepthEligible(Map<String, Object?> row) {
  final p = _integer(row['hypPhasePCount']) ?? 0;
  final s = _integer(row['hypPhaseSCount']) ?? 0;
  final residual = _number(row['hypPhaseMeanResidualSeconds']);
  final pair = _number(row['hypPairMeanResidualSeconds']);
  return _baseEligible(row) &&
      p >= 3 &&
      s >= 3 &&
      residual != null &&
      residual <= 2.2 &&
      pair != null &&
      pair <= 2.5;
}

double? _delta(Map<String, Object?> row) {
  final hyp = _number(row['hypFinalErrorKm']);
  final hybrid = _number(row['hybridFinalErrorKm']);
  if (hyp == null || hybrid == null) return null;
  return hyp - hybrid;
}

String _verdict({required int supportedCount, required int regressedCount}) {
  if (supportedCount == 0) return 'too_strict';
  if (regressedCount > 0) return 'unsafe';
  return 'safe';
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return <String, Object?>{};
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = List<double>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2.0;
}

String _fmt(Object? value, {int digits = 1}) {
  final number = _number(value);
  return number == null ? '--' : number.toStringAsFixed(digits);
}
