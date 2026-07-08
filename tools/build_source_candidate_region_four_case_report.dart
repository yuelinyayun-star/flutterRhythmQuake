import 'dart:convert';
import 'dart:io';

import 'build_source_local_support_separation_report.dart';
import 'build_source_residual_delayed_recovery_report.dart';

const _defaultOutputPath =
    '.dart_tool/source_candidate_region_four_case/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_candidate_region_four_case.generated.md';

void main(List<String> args) {
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceCandidateRegionFourCaseReportJson();

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source candidate-region four-case report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceCandidateRegionFourCaseReportJson({
  Map<String, Object?>? residualReport,
  Map<String, Object?>? localSupportReport,
}) {
  final residual =
      residualReport ?? buildSourceResidualDelayedRecoveryReportJson();
  final local =
      localSupportReport ?? buildSourceLocalSupportSeparationReportJson();
  final residualCases = _caseMap(residual['cases']);
  final localCases = _caseMap(local['cases']);
  final cases = <Map<String, Object?>>[
    _falseRecoveryGuardCase(
      residualCases['20260621_fukushima_offshore_m32_eq6'],
      localCases['20260621_fukushima_offshore_m32_eq6'],
    ),
    _residualDelayedCase(
      residualCases['20260622_kushiro_offshore_m30_jma'],
    ),
    _residualImmediateCase(
      residualCases['20260622_tomakomai_south_offshore_m35_hinet'],
    ),
    _localSupportDelayedCase(
      localCases['20260625_iwate_offshore_m32_jma'],
    ),
  ];

  final errors = <String>[
    ..._list(residual['errors']).map((entry) => 'residual:$entry'),
    ..._list(local['errors']).map((entry) => 'local_support:$entry'),
  ];
  final summary = _summary(cases);
  final validation = _validation(cases, summary, errors);
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_candidate_region_four_case_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': const {
      'residualDelayedRecoveryReport':
          '.dart_tool/source_residual_delayed_recovery_report/report.json',
      'localSupportSeparationReport':
          '.dart_tool/source_local_support_separation_report/report.json',
    },
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'This report compares the four current candidate-region guard cases without authorizing coordinate replacement or metric promotion.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _falseRecoveryGuardCase(
  Map<String, Object?>? residual,
  Map<String, Object?>? local,
) {
  return {
    'caseId': '20260621_fukushima_offshore_m32_eq6',
    'role': 'false_recovery_guard',
    'expectedOutcome': 'blocked_by_dual_residual_and_local_growth',
    'actualOutcome': _hasCase(residual) && _hasCase(local)
        ? 'blocked_by_dual_residual_and_local_growth'
        : 'missing_inputs',
    'residualDiagnosis': residual?['caseDiagnosis'],
    'localSupportDiagnosis': local?['diagnosis'],
    'candidateFrameCount': residual?['candidateFrameCount'],
    'rejectedPositiveFrameCount': residual?['rejectedPositiveFrameCount'],
    'dualRegressionRejectedPositiveFrameCount':
        residual?['dualRegressionRejectedPositiveFrameCount'],
    'delayedRecoveredPositiveFrameCount':
        residual?['delayedRecoveredPositiveFrameCount'],
    'localSupportConfirmedCount': local?['localSupportConfirmedCount'],
    'nearCompleteBlockedOnlyByGrowthCount':
        local?['nearCompleteBlockedOnlyByGrowthCount'],
    'productionCoordinateSwitchAllowedCount':
        _intValue(residual?['coordinateSwitchAllowedCount']) +
            _intValue(local?['productionCoordinateSwitchAllowedCount']),
  };
}

Map<String, Object?> _residualDelayedCase(Map<String, Object?>? residual) {
  return {
    'caseId': '20260622_kushiro_offshore_m30_jma',
    'role': 'residual_delayed_positive_guard',
    'expectedOutcome': 'same_region_residual_delayed_confirmation',
    'actualOutcome': _hasCase(residual)
        ? 'same_region_residual_delayed_confirmation'
        : 'missing_inputs',
    'residualDiagnosis': residual?['caseDiagnosis'],
    'localSupportDiagnosis': null,
    'candidateFrameCount': residual?['candidateFrameCount'],
    'rejectedPositiveFrameCount': residual?['rejectedPositiveFrameCount'],
    'delayedRecoveredPositiveFrameCount':
        residual?['delayedRecoveredPositiveFrameCount'],
    'residualConfirmedDelayedCount':
        residual?['residualConfirmedDelayedCount'],
    'acceptedPositiveFrameCount': residual?['acceptedPositiveFrameCount'],
    'productionCoordinateSwitchAllowedCount':
        _intValue(residual?['coordinateSwitchAllowedCount']),
  };
}

Map<String, Object?> _residualImmediateCase(Map<String, Object?>? residual) {
  return {
    'caseId': '20260622_tomakomai_south_offshore_m35_hinet',
    'role': 'residual_immediate_positive_guard',
    'expectedOutcome': 'dual_residual_immediate_confirmation',
    'actualOutcome': _hasCase(residual)
        ? 'dual_residual_immediate_confirmation'
        : 'missing_inputs',
    'residualDiagnosis': residual?['caseDiagnosis'],
    'localSupportDiagnosis': null,
    'candidateFrameCount': residual?['candidateFrameCount'],
    'acceptedPositiveFrameCount': residual?['acceptedPositiveFrameCount'],
    'rejectedPositiveFrameCount': residual?['rejectedPositiveFrameCount'],
    'confirmedImmediateCount': residual?['confirmedImmediateCount'],
    'productionCoordinateSwitchAllowedCount':
        _intValue(residual?['coordinateSwitchAllowedCount']),
  };
}

Map<String, Object?> _localSupportDelayedCase(Map<String, Object?>? local) {
  return {
    'caseId': '20260625_iwate_offshore_m32_jma',
    'role': 'local_support_positive_guard',
    'expectedOutcome': 'local_support_delayed_confirmation',
    'actualOutcome': _hasCase(local)
        ? 'local_support_delayed_confirmation'
        : 'missing_inputs',
    'residualDiagnosis': null,
    'localSupportDiagnosis': local?['diagnosis'],
    'frameCount': local?['frameCount'],
    'localSupportConfirmedCount': local?['localSupportConfirmedCount'],
    'confirmedDelayedCount': local?['confirmedDelayedCount'],
    'minConfirmedMemberGrowth': local?['minConfirmedMemberGrowth'],
    'productionCoordinateSwitchAllowedCount':
        _intValue(local?['productionCoordinateSwitchAllowedCount']),
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'falseRecoveryBlockedCount': cases
        .where(
          (entry) =>
              entry['role'] == 'false_recovery_guard' &&
              entry['actualOutcome'] ==
                  'blocked_by_dual_residual_and_local_growth',
        )
        .length,
    'residualDelayedPositiveCount': cases
        .where(
          (entry) =>
              entry['actualOutcome'] ==
              'same_region_residual_delayed_confirmation',
        )
        .length,
    'residualImmediatePositiveCount': cases
        .where(
          (entry) =>
              entry['actualOutcome'] == 'dual_residual_immediate_confirmation',
        )
        .length,
    'localSupportDelayedPositiveCount': cases
        .where(
          (entry) =>
              entry['actualOutcome'] == 'local_support_delayed_confirmation',
        )
        .length,
    'productionCoordinateSwitchAllowedCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['productionCoordinateSwitchAllowedCount']),
    ),
  };
}

Map<String, Object?> _validation(
  List<Map<String, Object?>> cases,
  Map<String, Object?> summary,
  List<String> errors,
) {
  final violations = <String>[];
  final byId = {
    for (final entry in cases) entry['caseId']?.toString() ?? '': entry,
  }..remove('');

  final fukushima = byId['20260621_fukushima_offshore_m32_eq6'];
  final kushiro = byId['20260622_kushiro_offshore_m30_jma'];
  final tomakomai = byId['20260622_tomakomai_south_offshore_m35_hinet'];
  final iwate = byId['20260625_iwate_offshore_m32_jma'];

  if (_intValue(summary['caseCount']) != 4) {
    violations.add('missing_four_case_coverage');
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_present');
  }
  if (fukushima?['actualOutcome'] !=
      'blocked_by_dual_residual_and_local_growth') {
    violations.add('fukushima_guard_not_blocked');
  }
  if (_intValue(fukushima?['dualRegressionRejectedPositiveFrameCount']) < 1) {
    violations.add('fukushima_missing_dual_residual_rejection');
  }
  if (_intValue(fukushima?['localSupportConfirmedCount']) != 0) {
    violations.add('fukushima_local_support_false_recovery');
  }
  if (kushiro?['actualOutcome'] !=
      'same_region_residual_delayed_confirmation') {
    violations.add('kushiro_missing_delayed_confirmation');
  }
  if (_intValue(kushiro?['delayedRecoveredPositiveFrameCount']) != 3) {
    violations.add('kushiro_delayed_recovered_count_regressed');
  }
  if (_intValue(kushiro?['residualConfirmedDelayedCount']) != 1) {
    violations.add('kushiro_residual_delayed_count_regressed');
  }
  if (tomakomai?['actualOutcome'] !=
      'dual_residual_immediate_confirmation') {
    violations.add('tomakomai_missing_immediate_confirmation');
  }
  if (_intValue(tomakomai?['acceptedPositiveFrameCount']) != 3) {
    violations.add('tomakomai_accepted_positive_count_regressed');
  }
  if (iwate?['actualOutcome'] != 'local_support_delayed_confirmation') {
    violations.add('iwate_missing_local_support_confirmation');
  }
  if (_intValue(iwate?['localSupportConfirmedCount']) != 1) {
    violations.add('iwate_local_support_count_regressed');
  }
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Candidate-Region Four-Case Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- False-recovery guards blocked: `${summary['falseRecoveryBlockedCount']}`',
    )
    ..writeln(
      '- Residual delayed positives: `${summary['residualDelayedPositiveCount']}`',
    )
    ..writeln(
      '- Residual immediate positives: `${summary['residualImmediatePositiveCount']}`',
    )
    ..writeln(
      '- Local-support delayed positives: `${summary['localSupportDelayedPositiveCount']}`',
    )
    ..writeln(
      '- Production coordinate switches: `${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Case Summary')
    ..writeln()
    ..writeln(
      '| Case | Role | Outcome | Residual diagnosis | Local-support diagnosis | Switch |',
    )
    ..writeln('| --- | --- | --- | --- | --- | ---: |');

  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['role']}` | '
      '`${entry['actualOutcome']}` | '
      '`${entry['residualDiagnosis'] ?? '--'}` | '
      '`${entry['localSupportDiagnosis'] ?? '--'}` | '
      '${entry['productionCoordinateSwitchAllowedCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation['status']}`.');
  final violations = _list(validation['violations']);
  if (violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln(
      '- Violations: ${violations.map((entry) => '`$entry`').join(', ')}.',
    );
  }
  buffer.writeln();
  return buffer.toString();
}

Map<String, Map<String, Object?>> _caseMap(Object? cases) {
  return {
    for (final raw in _list(cases))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');
}

bool _hasCase(Map<String, Object?>? value) => value != null && value.isNotEmpty;

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
