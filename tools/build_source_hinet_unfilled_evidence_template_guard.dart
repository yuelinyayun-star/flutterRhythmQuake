import 'dart:convert';
import 'dart:io';

import 'import_hinet_authenticated_export_row.dart';
import 'import_source_hinet_no_row_found_finding.dart';

const _defaultWorklistPath =
    '.dart_tool/source_hinet_evidence_intake_worklist/report.json';
const _defaultRowsPath = 'docs/data/hinet_authenticated_export_rows.json';
const _defaultFindingsPath =
    'docs/data/source_hinet_no_row_found_findings.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_unfilled_evidence_template_guard/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_unfilled_evidence_template_guard.generated.md';

const _expectedCaseIds = {
  '20260622_iwate_east_offshore_m30_hinet',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260623_tokachi_southeast_offshore_m34_hinet',
};

void main(List<String> args) {
  final worklistPath = _argument(args, '--worklist') ?? _defaultWorklistPath;
  final rowsPath = _argument(args, '--rows') ?? _defaultRowsPath;
  final findingsPath = _argument(args, '--findings') ?? _defaultFindingsPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetUnfilledEvidenceTemplateGuardJson(
    worklistPath: worklistPath,
    rowsPath: rowsPath,
    findingsPath: findingsPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net unfilled evidence template guard');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetUnfilledEvidenceTemplateGuardJson({
  String worklistPath = _defaultWorklistPath,
  String rowsPath = _defaultRowsPath,
  String findingsPath = _defaultFindingsPath,
}) {
  final errors = <String>[];
  final worklist = _readJsonFile(
    worklistPath,
    errors,
    expectedSchema: 'source_hinet_evidence_intake_worklist_v1',
    missingError: 'source_hinet_evidence_intake_worklist_missing',
  );
  final rows = _readJsonFile(
    rowsPath,
    errors,
    expectedSchema: 'hinet_authenticated_export_rows_v1',
    missingError: 'hinet_authenticated_export_rows_missing',
  );
  final findings = _readJsonFile(
    findingsPath,
    errors,
    expectedSchema: 'source_hinet_no_row_found_findings_v1',
    missingError: 'source_hinet_no_row_found_findings_missing',
  );

  final cases =
      _list(worklist['cases'])
          .map(_map)
          .map(
            (entry) => _guardCase(
              worklistCase: entry,
              rowsJson: rows,
              findingsJson: findings,
            ),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left['caseId'].toString().compareTo(right['caseId'].toString()),
        );

  final summary = _summary(cases);
  final validation = _validation(
    worklist: worklist,
    cases: cases,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_unfilled_evidence_template_guard_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceHinetEvidenceIntakeWorklist': worklistPath,
      'hinetAuthenticatedExportRows': rowsPath,
      'sourceHinetNoRowFoundFindings': findingsPath,
    },
    'policy': const {
      'guardOnly': true,
      'executesImports': false,
      'writesEvidenceLedger': false,
      'writesDecisionLedger': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'notes':
          'This guard verifies generated unfilled templates are rejected by import validators.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _guardCase({
  required Map<String, Object?> worklistCase,
  required Map<String, Object?> rowsJson,
  required Map<String, Object?> findingsJson,
}) {
  final authTemplateFile =
      worklistCase['authenticatedRowTemplateFile']?.toString() ?? '';
  final noRowTemplateFile =
      worklistCase['noRowFindingTemplateFile']?.toString() ?? '';
  final authPayload = _readTemplate(authTemplateFile);
  final noRowPayload = _readTemplate(noRowTemplateFile);
  final authErrors = authPayload == null
      ? ['template_missing_or_unreadable']
      : validateHinetAuthenticatedExportRowInput(
          rowsJson: rowsJson,
          inputJson: authPayload,
        );
  final noRowErrors = noRowPayload == null
      ? ['template_missing_or_unreadable']
      : validateSourceHinetNoRowFoundFindingInput(
          findingsJson: findingsJson,
          inputJson: noRowPayload,
        );
  final authRejected = authErrors.isNotEmpty;
  final noRowRejected = noRowErrors.isNotEmpty;

  return {
    'caseId': worklistCase['caseId'],
    'authenticatedRowTemplateFile': authTemplateFile,
    'authenticatedRowTemplateExists':
        authTemplateFile.isNotEmpty && File(authTemplateFile).existsSync(),
    'authenticatedTemplateRejected': authRejected,
    'authenticatedTemplateErrors': authErrors,
    'authenticatedTemplateContainsCredentialField': _containsSensitiveKey(
      authPayload,
    ),
    'noRowFindingTemplateFile': noRowTemplateFile,
    'noRowFindingTemplateExists':
        noRowTemplateFile.isNotEmpty && File(noRowTemplateFile).existsSync(),
    'noRowTemplateRejected': noRowRejected,
    'noRowTemplateErrors': noRowErrors,
    'noRowTemplateContainsCredentialField': _containsSensitiveKey(noRowPayload),
    'accidentalImportableTemplate': !authRejected || !noRowRejected,
    'writesEvidenceLedger': false,
    'writesDecisionLedger': false,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
  };
}

Map<String, Object?>? _readTemplate(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on Object {
    return null;
  }
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'authenticatedTemplateExistsCount': cases
        .where((entry) => entry['authenticatedRowTemplateExists'] == true)
        .length,
    'noRowTemplateExistsCount': cases
        .where((entry) => entry['noRowFindingTemplateExists'] == true)
        .length,
    'authenticatedTemplateRejectedCount': cases
        .where((entry) => entry['authenticatedTemplateRejected'] == true)
        .length,
    'noRowTemplateRejectedCount': cases
        .where((entry) => entry['noRowTemplateRejected'] == true)
        .length,
    'credentialFieldPresentCount': cases
        .where(
          (entry) =>
              entry['authenticatedTemplateContainsCredentialField'] == true ||
              entry['noRowTemplateContainsCredentialField'] == true,
        )
        .length,
    'accidentalImportableTemplateCount': cases
        .where((entry) => entry['accidentalImportableTemplate'] == true)
        .length,
    'writesEvidenceLedgerCount': cases
        .where((entry) => entry['writesEvidenceLedger'] == true)
        .length,
    'writesDecisionLedgerCount': cases
        .where((entry) => entry['writesDecisionLedger'] == true)
        .length,
    'truthQualityAcceptanceAllowedCount': cases
        .where((entry) => entry['truthQualityAcceptanceAllowed'] == true)
        .length,
    'metricPromotionAllowedCount': cases
        .where((entry) => entry['metricPromotionAllowed'] == true)
        .length,
    'splitAssignmentAllowedCount': cases
        .where((entry) => entry['splitAssignmentAllowed'] == true)
        .length,
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> worklist,
  required List<Map<String, Object?>> cases,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (worklist['status'] != 'pass') {
    violations.add('source_hinet_evidence_intake_worklist_not_pass');
  }
  final caseIds = cases
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (caseIds.length != _expectedCaseIds.length ||
      !caseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_unfilled_template_guard_case_set');
  }
  if (_intValue(summary['caseCount']) != 3) {
    violations.add('unexpected_case_count');
  }
  if (_intValue(summary['authenticatedTemplateExistsCount']) != 3) {
    violations.add('authenticated_template_missing');
  }
  if (_intValue(summary['noRowTemplateExistsCount']) != 3) {
    violations.add('no_row_template_missing');
  }
  if (_intValue(summary['authenticatedTemplateRejectedCount']) != 3) {
    violations.add('unfilled_authenticated_template_importable');
  }
  if (_intValue(summary['noRowTemplateRejectedCount']) != 3) {
    violations.add('unfilled_no_row_template_importable');
  }
  if (_intValue(summary['credentialFieldPresentCount']) != 0) {
    violations.add('template_contains_credential_field');
  }
  if (_intValue(summary['accidentalImportableTemplateCount']) != 0) {
    violations.add('accidental_importable_template');
  }
  if (_intValue(summary['writesEvidenceLedgerCount']) != 0) {
    violations.add('guard_writes_evidence_ledger');
  }
  if (_intValue(summary['writesDecisionLedgerCount']) != 0) {
    violations.add('guard_writes_decision_ledger');
  }
  if (_intValue(summary['truthQualityAcceptanceAllowedCount']) != 0) {
    violations.add('truth_quality_acceptance_allowed');
  }
  if (_intValue(summary['metricPromotionAllowedCount']) != 0) {
    violations.add('metric_promotion_allowed');
  }
  if (_intValue(summary['splitAssignmentAllowedCount']) != 0) {
    violations.add('split_assignment_allowed');
  }

  for (final entry in cases) {
    final authErrors = _stringList(entry['authenticatedTemplateErrors']);
    final noRowErrors = _stringList(entry['noRowTemplateErrors']);
    if (!authErrors.any(
      (error) =>
          error.startsWith('unresolved_placeholder:') ||
          error.startsWith('numeric_field_required:') ||
          error.endsWith('_not_parseable'),
    )) {
      violations.add('${entry['caseId']}:auth_template_missing_guard_error');
    }
    if (!noRowErrors.any(
      (error) =>
          error.startsWith('unresolved_placeholder:') ||
          error.startsWith('numeric_field_required:') ||
          error.endsWith('_not_parseable'),
    )) {
      violations.add('${entry['caseId']}:no_row_template_missing_guard_error');
    }
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
    ..writeln('# Source Hi-net Unfilled Evidence Template Guard')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- Auth templates rejected: '
      '`${summary['authenticatedTemplateRejectedCount']}`',
    )
    ..writeln(
      '- No-row templates rejected: `${summary['noRowTemplateRejectedCount']}`',
    )
    ..writeln(
      '- Credential fields present: `${summary['credentialFieldPresentCount']}`',
    )
    ..writeln(
      '- Accidental importable templates: '
      '`${summary['accidentalImportableTemplateCount']}`',
    )
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Auth rejected | Auth errors | No-row rejected | No-row errors |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['authenticatedTemplateRejected']}` | '
      '`${_stringList(entry['authenticatedTemplateErrors']).join('`, `')}` | '
      '`${entry['noRowTemplateRejected']}` | '
      '`${_stringList(entry['noRowTemplateErrors']).join('`, `')}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Generated templates are intentionally not importable until a reviewer fills real evidence.',
    )
    ..writeln(
      '- This guard calls validators directly; it does not execute import commands or write ledgers.',
    )
    ..writeln(
      '- Evidence, truth quality, split assignment and metric eligibility remain unchanged.',
    )
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation['status']}`.');
  final violations = _list(validation['violations']);
  if (violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln('- Violations: ${_codeList(violations)}.');
  }
  buffer.writeln();
  return buffer.toString();
}

Map<String, Object?> _readJsonFile(
  String path,
  List<String> errors, {
  required String expectedSchema,
  required String missingError,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$missingError:$path');
    return <String, Object?>{};
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (data['schemaVersion'] != expectedSchema) {
    errors.add('unexpected_schema:$path');
  }
  return data;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

bool _containsSensitiveKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key.contains('password') ||
          key.contains('cookie') ||
          key.contains('authorization') ||
          key.contains('session') ||
          key.contains('token') ||
          key == 'username' ||
          key == 'user') {
        return true;
      }
      if (_containsSensitiveKey(entry.value)) return true;
    }
  } else if (value is List) {
    return value.any(_containsSensitiveKey);
  }
  return false;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _codeList(List<Object?> values) =>
    values.map((value) => '`$value`').join(', ');

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((entry) => entry.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
