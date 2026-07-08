import 'dart:convert';
import 'dart:io';

const _defaultPriorityEvidencePath =
    '.dart_tool/source_hinet_priority_evidence_template_packet/report.json';
const _defaultNoRowPath =
    '.dart_tool/source_hinet_no_row_found_review_packet/report.json';
const _defaultEvidenceReviewPath =
    '.dart_tool/source_hinet_evidence_review/report.json';
const _defaultReviewerDecisionTemplatesPath =
    '.dart_tool/source_hinet_reviewer_decision_templates/report.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_evidence_intake_worklist/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_evidence_intake_worklist.generated.md';

const _expectedCaseIds = {
  '20260622_iwate_east_offshore_m30_hinet',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260623_tokachi_southeast_offshore_m34_hinet',
};

void main(List<String> args) {
  final priorityEvidencePath =
      _argument(args, '--priority-evidence') ?? _defaultPriorityEvidencePath;
  final noRowPath = _argument(args, '--no-row') ?? _defaultNoRowPath;
  final evidenceReviewPath =
      _argument(args, '--evidence-review') ?? _defaultEvidenceReviewPath;
  final reviewerDecisionTemplatesPath =
      _argument(args, '--reviewer-decision-templates') ??
      _defaultReviewerDecisionTemplatesPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetEvidenceIntakeWorklistJson(
    priorityEvidencePath: priorityEvidencePath,
    noRowPath: noRowPath,
    evidenceReviewPath: evidenceReviewPath,
    reviewerDecisionTemplatesPath: reviewerDecisionTemplatesPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net evidence intake worklist');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetEvidenceIntakeWorklistJson({
  String priorityEvidencePath = _defaultPriorityEvidencePath,
  String noRowPath = _defaultNoRowPath,
  String evidenceReviewPath = _defaultEvidenceReviewPath,
  String reviewerDecisionTemplatesPath = _defaultReviewerDecisionTemplatesPath,
}) {
  final errors = <String>[];
  final priorityEvidence = _readJsonFile(
    priorityEvidencePath,
    errors,
    expectedSchema: 'source_hinet_priority_evidence_template_packet_v1',
    missingError: 'source_hinet_priority_evidence_template_packet_missing',
  );
  final noRow = _readJsonFile(
    noRowPath,
    errors,
    expectedSchema: 'source_hinet_no_row_found_review_packet_v1',
    missingError: 'source_hinet_no_row_found_review_packet_missing',
  );
  final evidenceReview = _readJsonFile(
    evidenceReviewPath,
    errors,
    expectedSchema: 'source_hinet_evidence_review_v1',
    missingError: 'source_hinet_evidence_review_missing',
  );
  final reviewerDecisionTemplates = _readJsonFile(
    reviewerDecisionTemplatesPath,
    errors,
    expectedSchema: 'source_hinet_reviewer_decision_templates_v1',
    missingError: 'source_hinet_reviewer_decision_templates_missing',
  );

  final priorityByCaseId = {
    for (final entry in _list(priorityEvidence['packets']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final noRowByCaseId = {
    for (final entry in _list(noRow['packets']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final reviewByCaseId = {
    for (final entry in _list(evidenceReview['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final decisionTemplateByCaseId = {
    for (final entry in _list(reviewerDecisionTemplates['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');

  final caseIds = {
    ...priorityByCaseId.keys,
    ...noRowByCaseId.keys,
    ...reviewByCaseId.keys,
    ...decisionTemplateByCaseId.keys,
  }.toList()..sort();

  final cases = caseIds
      .map(
        (caseId) => _worklistCase(
          caseId: caseId,
          priority: priorityByCaseId[caseId] ?? const <String, Object?>{},
          noRow: noRowByCaseId[caseId] ?? const <String, Object?>{},
          review: reviewByCaseId[caseId] ?? const <String, Object?>{},
          decisionTemplate:
              decisionTemplateByCaseId[caseId] ?? const <String, Object?>{},
        ),
      )
      .toList(growable: false);

  final summary = _summary(cases);
  final validation = _validation(
    priorityEvidence: priorityEvidence,
    noRow: noRow,
    evidenceReview: evidenceReview,
    reviewerDecisionTemplates: reviewerDecisionTemplates,
    cases: cases,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_evidence_intake_worklist_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceHinetPriorityEvidenceTemplates': priorityEvidencePath,
      'sourceHinetNoRowFoundReviewPacket': noRowPath,
      'sourceHinetEvidenceReview': evidenceReviewPath,
      'sourceHinetReviewerDecisionTemplates': reviewerDecisionTemplatesPath,
    },
    'policy': const {
      'worklistOnly': true,
      'writesEvidenceLedger': false,
      'writesDecisionLedger': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'credentialFieldsAllowed': false,
      'notes':
          'This report chooses the next manual evidence intake action. It does not submit evidence or accept truth quality.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _worklistCase({
  required String caseId,
  required Map<String, Object?> priority,
  required Map<String, Object?> noRow,
  required Map<String, Object?> review,
  required Map<String, Object?> decisionTemplate,
}) {
  final authTemplate = priority['templateFile']?.toString() ?? '';
  final noRowTemplate = noRow['noRowFindingTemplateFile']?.toString() ?? '';
  final authReady = review['authenticatedEvidenceReady'] == true;
  final noRowReady = review['noRowEvidenceReady'] == true;
  final decisionTemplateEmitted = decisionTemplate['templateEmitted'] == true;
  final decisionStatus = review['decisionStatus']?.toString().isNotEmpty == true
      ? review['decisionStatus']?.toString()
      : priority['decisionStatus']?.toString();
  final acceptedForConstrainedReferenceSplit =
      review['acceptedForConstrainedReferenceSplit'] == true ||
      priority['acceptedForConstrainedReferenceSplit'] == true ||
      decisionStatus == 'accepted_constrained_reference';
  final nextAction = acceptedForConstrainedReferenceSplit
      ? 'accepted_constrained_reference_waiting_split_gate'
      : decisionTemplateEmitted
      ? 'fill_reviewer_decision_template'
      : authReady || noRowReady
      ? 'rerun_reviewer_decision_staging'
      : 'fill_authenticated_row_or_no_row_finding';
  return {
    'caseId': caseId,
    'plannedUse': priority['plannedUse'] ?? noRow['plannedUse'],
    'triageTier': priority['triageTier'],
    'priority': priority['priority'],
    'queryWindowJst': priority['queryWindowJst'] ?? noRow['queryWindowJst'],
    'preferredSourceType':
        priority['preferredSourceType'] ?? noRow['preferredSourceType'],
    'authenticatedRowStatus': review['authenticatedRowStatus'],
    'authenticatedEvidenceReady': authReady,
    'decisionStatus': decisionStatus,
    'acceptedForConstrainedReferenceSplit':
        acceptedForConstrainedReferenceSplit,
    'authenticatedRowTemplateFile': authTemplate,
    'authenticatedRowTemplateExists':
        authTemplate.isNotEmpty && File(authTemplate).existsSync(),
    'authenticatedRowImportDryRunCommand':
        acceptedForConstrainedReferenceSplit || authTemplate.isEmpty
        ? null
        : 'dart run tools\\import_hinet_authenticated_export_row.dart '
              '--input $authTemplate --dry-run',
    'authenticatedRowImportCommand':
        acceptedForConstrainedReferenceSplit || authTemplate.isEmpty
        ? null
        : 'dart run tools\\import_hinet_authenticated_export_row.dart '
              '--input $authTemplate',
    'noRowFindingStatus': review['noRowFindingStatus'],
    'noRowEvidenceReady': noRowReady,
    'noRowFindingTemplateFile': noRowTemplate,
    'noRowFindingTemplateExists':
        noRowTemplate.isNotEmpty && File(noRowTemplate).existsSync(),
    'noRowFindingImportDryRunCommand':
        acceptedForConstrainedReferenceSplit || noRowTemplate.isEmpty
        ? null
        : 'dart run tools\\import_source_hinet_no_row_found_finding.dart '
              '--input $noRowTemplate --dry-run',
    'noRowFindingImportCommand':
        acceptedForConstrainedReferenceSplit || noRowTemplate.isEmpty
        ? null
        : 'dart run tools\\import_source_hinet_no_row_found_finding.dart '
              '--input $noRowTemplate',
    'reviewerDecisionTemplateEmitted': decisionTemplateEmitted,
    'reviewerDecisionTemplateFile': decisionTemplate['templateFile'],
    'reviewerDecisionImportDryRunCommand':
        !acceptedForConstrainedReferenceSplit && decisionTemplateEmitted
        ? decisionTemplate['importDryRunCommand']
        : null,
    'reviewerDecisionImportCommand':
        !acceptedForConstrainedReferenceSplit && decisionTemplateEmitted
        ? 'dart run tools\\import_source_hinet_reviewer_decision.dart '
              '--input ${decisionTemplate['templateFile']}'
        : null,
    'nextAction': nextAction,
    'recommendedFirstPath': 'authenticated_row',
    'fallbackPath': 'no_row_found_after_authenticated_search',
    'manualReviewRequired': !acceptedForConstrainedReferenceSplit,
    'writesEvidenceLedger': false,
    'writesDecisionLedger': false,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'authenticatedTemplateReadyCount': cases
        .where((entry) => entry['authenticatedRowTemplateExists'] == true)
        .length,
    'noRowTemplateReadyCount': cases
        .where((entry) => entry['noRowFindingTemplateExists'] == true)
        .length,
    'authenticatedEvidenceReadyCount': cases
        .where((entry) => entry['authenticatedEvidenceReady'] == true)
        .length,
    'noRowEvidenceReadyCount': cases
        .where((entry) => entry['noRowEvidenceReady'] == true)
        .length,
    'reviewerDecisionTemplateEmittedCount': cases
        .where((entry) => entry['reviewerDecisionTemplateEmitted'] == true)
        .length,
    'acceptedForConstrainedReferenceSplitCount': cases
        .where((entry) => entry['acceptedForConstrainedReferenceSplit'] == true)
        .length,
    'nextActionCounts': _counts(cases.map((entry) => entry['nextAction'])),
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
  required Map<String, Object?> priorityEvidence,
  required Map<String, Object?> noRow,
  required Map<String, Object?> evidenceReview,
  required Map<String, Object?> reviewerDecisionTemplates,
  required List<Map<String, Object?>> cases,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (priorityEvidence['status'] != 'pass') {
    violations.add('source_hinet_priority_evidence_templates_not_pass');
  }
  if (noRow['status'] != 'pass') {
    violations.add('source_hinet_no_row_found_review_packet_not_pass');
  }
  if (evidenceReview['status'] != 'pass') {
    violations.add('source_hinet_evidence_review_not_pass');
  }
  if (reviewerDecisionTemplates['status'] != 'pass') {
    violations.add('source_hinet_reviewer_decision_templates_not_pass');
  }
  final caseIds = cases
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (caseIds.length != _expectedCaseIds.length ||
      !caseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_evidence_intake_case_set');
  }
  if (_intValue(summary['caseCount']) != 3) {
    violations.add('unexpected_case_count');
  }
  if (_intValue(summary['writesEvidenceLedgerCount']) != 0) {
    violations.add('worklist_writes_evidence_ledger');
  }
  if (_intValue(summary['writesDecisionLedgerCount']) != 0) {
    violations.add('worklist_writes_decision_ledger');
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
    final nextAction = entry['nextAction']?.toString();
    if (nextAction == 'fill_authenticated_row_or_no_row_finding') {
      if (!entry['authenticatedRowImportDryRunCommand'].toString().contains(
        '--dry-run',
      )) {
        violations.add('${entry['caseId']}:auth_import_dry_run_missing');
      }
      if (!entry['noRowFindingImportDryRunCommand'].toString().contains(
        '--dry-run',
      )) {
        violations.add('${entry['caseId']}:no_row_import_dry_run_missing');
      }
    }
    if (nextAction == 'fill_reviewer_decision_template' &&
        entry['reviewerDecisionTemplateEmitted'] != true) {
      violations.add('${entry['caseId']}:reviewer_template_missing');
    }
    if (nextAction == 'fill_reviewer_decision_template' &&
        !entry['reviewerDecisionImportDryRunCommand'].toString().contains(
          '--dry-run',
        )) {
      violations.add('${entry['caseId']}:reviewer_dry_run_missing');
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
  final nextActionCounts = _map(summary['nextActionCounts']);
  final buffer = StringBuffer()
    ..writeln('# Source Hi-net Evidence Intake Worklist')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- Authenticated-row templates ready: '
      '`${summary['authenticatedTemplateReadyCount']}`',
    )
    ..writeln(
      '- No-row-found templates ready: `${summary['noRowTemplateReadyCount']}`',
    )
    ..writeln(
      '- Authenticated evidence ready: '
      '`${summary['authenticatedEvidenceReadyCount']}`',
    )
    ..writeln(
      '- No-row evidence ready: `${summary['noRowEvidenceReadyCount']}`',
    )
    ..writeln(
      '- Reviewer-decision templates emitted: '
      '`${summary['reviewerDecisionTemplateEmittedCount']}`',
    )
    ..writeln(
      '- Accepted constrained references: '
      '`${summary['acceptedForConstrainedReferenceSplitCount']}`',
    )
    ..writeln('- Next-action counts: `$nextActionCounts`')
    ..writeln()
    ..writeln('## Worklist')
    ..writeln()
    ..writeln(
      '| Case | Next action | Decision status | Accepted constrained | Window JST | Auth template | No-row template |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['nextAction']}` | '
      '`${entry['decisionStatus']}` | '
      '`${entry['acceptedForConstrainedReferenceSplit']}` | '
      '`${entry['queryWindowJst']}` | '
      '`${entry['authenticatedRowTemplateFile']}` | '
      '`${entry['noRowFindingTemplateFile']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Commands')
    ..writeln();
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer
      ..writeln('### ${entry['caseId']}')
      ..writeln(
        '- Auth dry-run: `${entry['authenticatedRowImportDryRunCommand']}`',
      )
      ..writeln('- Auth import: `${entry['authenticatedRowImportCommand']}`')
      ..writeln(
        '- No-row dry-run: `${entry['noRowFindingImportDryRunCommand']}`',
      )
      ..writeln('- No-row import: `${entry['noRowFindingImportCommand']}`')
      ..writeln(
        '- Reviewer dry-run: '
        '`${entry['reviewerDecisionImportDryRunCommand']}`',
      )
      ..writeln(
        '- Reviewer import: `${entry['reviewerDecisionImportCommand']}`',
      )
      ..writeln();
  }
  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Fill an authenticated-row template first when a matching event row exists.',
    )
    ..writeln(
      '- Fill a no-row-found template only after an authenticated search finds no matching row.',
    )
    ..writeln(
      '- After any evidence import, rerun reviewer-decision staging/templates before importing a truth-quality decision.',
    )
    ..writeln(
      '- Accepted constrained references skip evidence intake and wait for the separate constrained split gate.',
    )
    ..writeln(
      '- This worklist does not submit evidence, accept truth quality, assign splits or change metric eligibility.',
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

Map<String, int> _counts(Iterable<Object?> values) {
  final result = <String, int>{};
  for (final value in values) {
    final key = value?.toString() ?? '';
    if (key.isEmpty) continue;
    result[key] = (result[key] ?? 0) + 1;
  }
  return result;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _codeList(List<Object?> values) =>
    values.map((value) => '`$value`').join(', ');

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
