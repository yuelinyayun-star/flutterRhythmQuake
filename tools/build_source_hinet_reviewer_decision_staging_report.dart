import 'dart:convert';
import 'dart:io';

const _defaultEvidenceReviewPath =
    '.dart_tool/source_hinet_evidence_review/report.json';
const _defaultDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_reviewer_decision_staging/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_reviewer_decision_staging.generated.md';

const _expectedCaseIds = {
  '20260621_fukushima_offshore_m32_eq6',
  '20260622_iwate_east_offshore_m30_hinet',
  '20260622_iwate_offshore_m30_eq10',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260622_wakayama_south_m25_hinet',
  '20260623_tokachi_southeast_offshore_m34_hinet',
};

void main(List<String> args) {
  final evidenceReviewPath =
      _argument(args, '--evidence-review') ?? _defaultEvidenceReviewPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetReviewerDecisionStagingReportJson(
    evidenceReviewPath: evidenceReviewPath,
    decisionPath: decisionPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net reviewer-decision staging report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetReviewerDecisionStagingReportJson({
  String evidenceReviewPath = _defaultEvidenceReviewPath,
  String decisionPath = _defaultDecisionPath,
}) {
  final errors = <String>[];
  final evidenceReview = _readJsonFile(
    evidenceReviewPath,
    errors,
    expectedSchema: 'source_hinet_evidence_review_v1',
    missingError: 'source_hinet_evidence_review_missing',
  );
  final decisions = _readJsonFile(
    decisionPath,
    errors,
    expectedSchema: 'hinet_truth_quality_review_decisions_v1',
    missingError: 'hinet_truth_quality_review_decisions_missing',
  );
  final decisionByCaseId = {
    for (final entry in _list(decisions['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');

  final cases =
      _list(evidenceReview['cases'])
          .map(_map)
          .map(
            (entry) => _stagingCase(
              entry,
              decisionByCaseId[entry['caseId']?.toString() ?? ''] ??
                  const <String, Object?>{},
            ),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left['caseId'].toString().compareTo(right['caseId'].toString()),
        );

  final summary = _summary(cases);
  final validation = _validation(
    evidenceReview: evidenceReview,
    cases: cases,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_reviewer_decision_staging_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceHinetEvidenceReview': evidenceReviewPath,
      'hinetTruthQualityReviewDecisions': decisionPath,
    },
    'policy': const {
      'stagingOnly': true,
      'writesDecisionLedger': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'notes':
          'This report only stages human reviewer work. Eligible means ready for manual decision, not accepted.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _stagingCase(
  Map<String, Object?> evidenceCase,
  Map<String, Object?> decision,
) {
  final readyEvidenceTypes = _stringList(evidenceCase['readyEvidenceTypes']);
  final decisionStatus = decision['decisionStatus']?.toString() ?? 'missing';
  final accepted = decision['acceptedForConstrainedReferenceSplit'] == true;
  final blockers = <String>[
    if (readyEvidenceTypes.isEmpty) 'evidence_not_ready',
    if (decisionStatus != 'pending_manual_review')
      'decision_not_pending_manual_review',
    if (accepted) 'already_accepted',
    if (evidenceCase['combinedEvidenceStatus'] == 'conflicting_evidence_ready')
      'conflicting_evidence_ready',
  ];
  final eligible = blockers.isEmpty;

  return {
    'caseId': evidenceCase['caseId'],
    'combinedEvidenceStatus': evidenceCase['combinedEvidenceStatus'],
    'readyEvidenceTypes': readyEvidenceTypes,
    'decisionStatus': decisionStatus,
    'acceptedForConstrainedReferenceSplit': accepted,
    'reviewerDecisionEligible': eligible,
    'blockingReasons': blockers,
    'suggestedDecisionStatus': eligible
        ? 'accepted_constrained_reference_or_rejected_after_review'
        : 'keep_pending_manual_review',
    'requiredReviewerFields': const [
      'reviewedAtUtc',
      'reviewer',
      'evidence',
      'notes',
    ],
    'decisionLedgerWriteAllowed': false,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'reviewerDecisionEligibleCount': cases
        .where((entry) => entry['reviewerDecisionEligible'] == true)
        .length,
    'blockedCount': cases
        .where((entry) => entry['reviewerDecisionEligible'] != true)
        .length,
    'evidenceNotReadyCount': cases
        .where(
          (entry) =>
              _list(entry['blockingReasons']).contains('evidence_not_ready'),
        )
        .length,
    'conflictingEvidenceReadyCount': cases
        .where(
          (entry) => _list(
            entry['blockingReasons'],
          ).contains('conflicting_evidence_ready'),
        )
        .length,
    'alreadyAcceptedCount': cases
        .where((entry) => entry['acceptedForConstrainedReferenceSplit'] == true)
        .length,
    'decisionLedgerWriteAllowedCount': cases
        .where((entry) => entry['decisionLedgerWriteAllowed'] == true)
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
  required Map<String, Object?> evidenceReview,
  required List<Map<String, Object?>> cases,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (evidenceReview['status'] != 'pass') {
    violations.add('source_hinet_evidence_review_not_pass');
  }
  final actualCaseIds = cases
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (actualCaseIds.length != _expectedCaseIds.length ||
      !actualCaseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_reviewer_staging_case_set');
  }
  if (_intValue(summary['caseCount']) != 6) {
    violations.add('unexpected_case_count');
  }
  if (_intValue(summary['decisionLedgerWriteAllowedCount']) != 0) {
    violations.add('decision_ledger_write_allowed');
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
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Hi-net Reviewer-Decision Staging')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- Reviewer-decision eligible: '
      '`${summary['reviewerDecisionEligibleCount']}`',
    )
    ..writeln('- Blocked: `${summary['blockedCount']}`')
    ..writeln('- Evidence not ready: `${summary['evidenceNotReadyCount']}`')
    ..writeln(
      '- Decision ledger writes allowed: '
      '`${summary['decisionLedgerWriteAllowedCount']}`',
    )
    ..writeln(
      '- Truth-quality acceptance allowed: '
      '`${summary['truthQualityAcceptanceAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Evidence status | Ready evidence | Eligible | Blockers | Suggested decision |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['combinedEvidenceStatus']}` | '
      '`${_stringList(entry['readyEvidenceTypes']).join('`, `')}` | '
      '`${entry['reviewerDecisionEligible']}` | '
      '`${_stringList(entry['blockingReasons']).join('`, `')}` | '
      '`${entry['suggestedDecisionStatus']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- No truth-quality decision is written by this report.')
    ..writeln(
      '- A case is eligible only after evidence is ready and the existing decision remains pending.',
    )
    ..writeln('- Split assignment and metric eligibility remain unchanged.')
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
