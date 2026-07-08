import 'dart:convert';
import 'dart:io';

import 'build_hinet_authenticated_export_review_report.dart';
import 'build_source_hinet_evidence_review_report.dart';
import 'build_source_hinet_reviewer_decision_staging_report.dart';
import 'build_source_hinet_reviewer_decision_template_packet.dart';
import 'import_hinet_authenticated_export_row.dart';

const _defaultWorklistPath =
    '.dart_tool/source_hinet_evidence_intake_worklist/report.json';
const _defaultRowsPath = 'docs/data/hinet_authenticated_export_rows.json';
const _defaultNoRowFindingsPath =
    'docs/data/source_hinet_no_row_found_findings.json';
const _defaultDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_evidence_propagation_rehearsal/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_evidence_propagation_rehearsal.generated.md';

void main(List<String> args) {
  final worklistPath = _argument(args, '--worklist') ?? _defaultWorklistPath;
  final rowsPath = _argument(args, '--rows') ?? _defaultRowsPath;
  final noRowFindingsPath =
      _argument(args, '--no-row-findings') ?? _defaultNoRowFindingsPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetEvidencePropagationRehearsalJson(
    worklistPath: worklistPath,
    rowsPath: rowsPath,
    noRowFindingsPath: noRowFindingsPath,
    decisionPath: decisionPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net evidence propagation rehearsal');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetEvidencePropagationRehearsalJson({
  String worklistPath = _defaultWorklistPath,
  String rowsPath = _defaultRowsPath,
  String noRowFindingsPath = _defaultNoRowFindingsPath,
  String decisionPath = _defaultDecisionPath,
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

  final rehearsalCase = _map(_list(worklist['cases']).firstOrNull);
  final templatePath =
      rehearsalCase['authenticatedRowTemplateFile']?.toString() ?? '';
  final template = _readTemplate(templatePath, errors);
  final simulatedRow = _simulatedSubmittedRow(template);
  final importValidationErrors = validateHinetAuthenticatedExportRowInput(
    rowsJson: rows,
    inputJson: simulatedRow,
  );

  Map<String, Object?> authReview = const {};
  Map<String, Object?> evidenceReview = const {};
  Map<String, Object?> staging = const {};
  Map<String, Object?> reviewerTemplates = const {};
  Directory? tempDir;
  if (errors.isEmpty && importValidationErrors.isEmpty) {
    tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_evidence_rehearsal_',
    );
    try {
      final simulatedRows = _rowsWithSubmittedCase(
        rows,
        simulatedRow['caseId']?.toString() ?? '',
        simulatedRow,
      );
      final rowsFile = File('${tempDir.path}/rows.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(simulatedRows)}\n',
        );
      authReview = buildHinetAuthenticatedExportReviewJson(
        rowsPath: rowsFile.path,
        decisionPath: decisionPath,
      );
      final authReviewFile = File('${tempDir.path}/auth_review.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(authReview)}\n',
        );
      evidenceReview = buildSourceHinetEvidenceReviewReportJson(
        authenticatedReviewPath: authReviewFile.path,
        noRowFindingsPath: noRowFindingsPath,
        decisionPath: decisionPath,
      );
      final evidenceReviewFile = File('${tempDir.path}/evidence_review.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(evidenceReview)}\n',
        );
      staging = buildSourceHinetReviewerDecisionStagingReportJson(
        evidenceReviewPath: evidenceReviewFile.path,
        decisionPath: decisionPath,
      );
      final stagingFile = File('${tempDir.path}/staging.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(staging)}\n',
        );
      reviewerTemplates = buildSourceHinetReviewerDecisionTemplatePacketJson(
        stagingPath: stagingFile.path,
        templateDirectory: '${tempDir.path}/reviewer_templates',
        writeTemplateFiles: false,
      );
    } finally {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  }

  final caseId = simulatedRow['caseId']?.toString() ?? '';
  final authCase = _caseById(authReview, caseId);
  final evidenceCase = _caseById(evidenceReview, caseId);
  final stagingCase = _caseById(staging, caseId);
  final templateCase = _caseById(reviewerTemplates, caseId);
  final summary = {
    'rehearsalCaseId': caseId,
    'importValidationErrorCount': importValidationErrors.length,
    'authenticatedEvidenceReady': authCase['decisionEvidenceReady'] == true,
    'sourceEvidenceReady': _list(evidenceCase['readyEvidenceTypes']).isNotEmpty,
    'reviewerDecisionEligible': stagingCase['reviewerDecisionEligible'] == true,
    'reviewerDecisionTemplateEmitted': templateCase['templateEmitted'] == true,
    'realEvidenceLedgerWrites': 0,
    'realDecisionLedgerWrites': 0,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
  };
  final validation = _validation(
    errors: errors,
    importValidationErrors: importValidationErrors,
    authReview: authReview,
    evidenceReview: evidenceReview,
    staging: staging,
    reviewerTemplates: reviewerTemplates,
    summary: summary,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_evidence_propagation_rehearsal_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceHinetEvidenceIntakeWorklist': worklistPath,
      'hinetAuthenticatedExportRows': rowsPath,
      'sourceHinetNoRowFoundFindings': noRowFindingsPath,
      'hinetTruthQualityReviewDecisions': decisionPath,
    },
    'policy': const {
      'rehearsalOnly': true,
      'usesSyntheticSubmittedRow': true,
      'writesRealEvidenceLedger': false,
      'writesRealDecisionLedger': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'notes':
          'This report verifies propagation after a valid evidence import using temporary files only.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'simulatedSubmittedRow': simulatedRow,
    'importValidationErrors': importValidationErrors,
    'rehearsal': {
      'authenticatedReviewStatus': authReview['status'],
      'sourceEvidenceReviewStatus': evidenceReview['status'],
      'reviewerDecisionStagingStatus': staging['status'],
      'reviewerDecisionTemplatesStatus': reviewerTemplates['status'],
      'authenticatedCase': authCase,
      'sourceEvidenceCase': evidenceCase,
      'stagingCase': stagingCase,
      'reviewerTemplateCase': templateCase,
    },
  };
}

Map<String, Object?> _rowsWithSubmittedCase(
  Map<String, Object?> rowsJson,
  String caseId,
  Map<String, Object?> submittedRow,
) {
  final copy = Map<String, Object?>.from(rowsJson);
  final rows = _list(rowsJson['rows'])
      .map((entry) => Map<String, Object?>.from(_map(entry)))
      .toList(growable: true);
  final index = rows.indexWhere((entry) => entry['caseId'] == caseId);
  if (index >= 0) {
    rows[index] = {
      'caseId': caseId,
      'status': 'submitted_for_review',
      'submittedRow': {
        for (final field in _stringList(rowsJson['submittedRowRequiredFields']))
          field: submittedRow[field],
      },
      'rejectionReason': null,
      'decisionImpact': 'none_review_required',
    };
  }
  copy['rows'] = rows;
  return copy;
}

Map<String, Object?> _simulatedSubmittedRow(Map<String, Object?> template) {
  final target = _map(template['_queryTarget']);
  return {
    ...template,
    'sourceVersionOrPageDate': 'rehearsal-authenticated-page',
    'checkedAtUtc': DateTime.utc(2026, 6, 27, 0, 0).toIso8601String(),
    'reviewer': 'rehearsal-only',
    'originTimeJst': target['targetOriginTimeJst'],
    'latitude': target['targetLatitude'],
    'longitude': target['targetLongitude'],
    'depthKm': target['targetDepthKm'],
    'magnitude': target['targetMagnitude'],
    'region': target['targetRegion'],
    'rawRowText': 'rehearsal synthetic authenticated row',
  };
}

Map<String, Object?> _caseById(Map<String, Object?> report, String caseId) {
  for (final raw in _list(report['cases'])) {
    final entry = _map(raw);
    if (entry['caseId'] == caseId) return entry;
  }
  return const {};
}

Map<String, Object?> _validation({
  required List<String> errors,
  required List<String> importValidationErrors,
  required Map<String, Object?> authReview,
  required Map<String, Object?> evidenceReview,
  required Map<String, Object?> staging,
  required Map<String, Object?> reviewerTemplates,
  required Map<String, Object?> summary,
}) {
  final violations = <String>[];
  if (importValidationErrors.isNotEmpty) {
    violations.add('simulated_row_failed_import_validation');
  }
  if (authReview['status'] != 'pass') {
    violations.add('authenticated_review_not_pass');
  }
  if (evidenceReview['status'] != 'pass') {
    violations.add('source_evidence_review_not_pass');
  }
  if (staging['status'] != 'pass') {
    violations.add('reviewer_decision_staging_not_pass');
  }
  if (reviewerTemplates['status'] != 'pass') {
    violations.add('reviewer_decision_templates_not_pass');
  }
  if (summary['authenticatedEvidenceReady'] != true) {
    violations.add('authenticated_evidence_not_ready_after_rehearsal');
  }
  if (summary['sourceEvidenceReady'] != true) {
    violations.add('source_evidence_not_ready_after_rehearsal');
  }
  if (summary['reviewerDecisionEligible'] != true) {
    violations.add('reviewer_decision_not_eligible_after_rehearsal');
  }
  if (summary['reviewerDecisionTemplateEmitted'] != true) {
    violations.add('reviewer_decision_template_not_emitted_after_rehearsal');
  }
  if (summary['realEvidenceLedgerWrites'] != 0 ||
      summary['realDecisionLedgerWrites'] != 0 ||
      summary['truthQualityAcceptanceAllowed'] != false ||
      summary['metricPromotionAllowed'] != false ||
      summary['splitAssignmentAllowed'] != false) {
    violations.add('rehearsal_mutation_guard_failed');
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
    ..writeln('# Source Hi-net Evidence Propagation Rehearsal')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Rehearsal case: `${summary['rehearsalCaseId']}`')
    ..writeln(
      '- Import validation errors: '
      '`${summary['importValidationErrorCount']}`',
    )
    ..writeln(
      '- Authenticated evidence ready: '
      '`${summary['authenticatedEvidenceReady']}`',
    )
    ..writeln('- Source evidence ready: `${summary['sourceEvidenceReady']}`')
    ..writeln(
      '- Reviewer-decision eligible: '
      '`${summary['reviewerDecisionEligible']}`',
    )
    ..writeln(
      '- Reviewer-decision template emitted: '
      '`${summary['reviewerDecisionTemplateEmitted']}`',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- A valid authenticated-row evidence import would propagate to reviewer-decision staging.',
    )
    ..writeln(
      '- This rehearsal uses temporary files and does not mutate real evidence or decision ledgers.',
    )
    ..writeln(
      '- Truth quality, split assignment and metric eligibility remain separate guarded steps.',
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

Map<String, Object?> _readTemplate(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('authenticated_template_missing:$path');
    return const {};
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _codeList(List<Object?> values) =>
    values.map((value) => '`$value`').join(', ');

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((entry) => entry.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
