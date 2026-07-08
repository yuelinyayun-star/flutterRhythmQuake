import 'dart:convert';
import 'dart:io';

import 'import_source_hinet_no_row_found_finding.dart';

const _defaultAuthenticatedReviewPath =
    '.dart_tool/hinet_authenticated_export_review/report.json';
const _defaultNoRowFindingsPath =
    'docs/data/source_hinet_no_row_found_findings.json';
const _defaultDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_evidence_review/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_evidence_review.generated.md';

const _expectedCaseIds = {
  '20260621_fukushima_offshore_m32_eq6',
  '20260622_iwate_east_offshore_m30_hinet',
  '20260622_iwate_offshore_m30_eq10',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260622_wakayama_south_m25_hinet',
  '20260623_tokachi_southeast_offshore_m34_hinet',
};

void main(List<String> args) {
  final authenticatedReviewPath =
      _argument(args, '--authenticated-review') ??
      _defaultAuthenticatedReviewPath;
  final noRowFindingsPath =
      _argument(args, '--no-row-findings') ?? _defaultNoRowFindingsPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetEvidenceReviewReportJson(
    authenticatedReviewPath: authenticatedReviewPath,
    noRowFindingsPath: noRowFindingsPath,
    decisionPath: decisionPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net evidence review report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetEvidenceReviewReportJson({
  String authenticatedReviewPath = _defaultAuthenticatedReviewPath,
  String noRowFindingsPath = _defaultNoRowFindingsPath,
  String decisionPath = _defaultDecisionPath,
}) {
  final errors = <String>[];
  final authenticatedReview = _readJsonFile(
    authenticatedReviewPath,
    errors,
    expectedSchema: 'hinet_authenticated_export_review_v1',
    missingError: 'hinet_authenticated_export_review_missing',
  );
  final noRowFindings = _readJsonFile(
    noRowFindingsPath,
    errors,
    expectedSchema: 'source_hinet_no_row_found_findings_v1',
    missingError: 'source_hinet_no_row_found_findings_missing',
  );
  final decisions = _readJsonFile(
    decisionPath,
    errors,
    expectedSchema: 'hinet_truth_quality_review_decisions_v1',
    missingError: 'hinet_truth_quality_review_decisions_missing',
  );

  final authCases = {
    for (final entry in _list(authenticatedReview['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final noRowCases = {
    for (final entry in _list(noRowFindings['findings']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final decisionCases = {
    for (final entry in _list(decisions['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');

  final caseIds = {...authCases.keys, ...noRowCases.keys}.toList()..sort();
  final cases = caseIds
      .map((caseId) {
        return _caseReview(
          caseId: caseId,
          authCase: authCases[caseId] ?? const <String, Object?>{},
          noRowCase: noRowCases[caseId] ?? const <String, Object?>{},
          decision: decisionCases[caseId] ?? const <String, Object?>{},
          noRowFindings: noRowFindings,
        );
      })
      .toList(growable: false);

  final summary = _summary(cases);
  final validation = _validation(
    authenticatedReview: authenticatedReview,
    cases: cases,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_evidence_review_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'hinetAuthenticatedExportReview': authenticatedReviewPath,
      'sourceHinetNoRowFoundFindings': noRowFindingsPath,
      'hinetTruthQualityReviewDecisions': decisionPath,
    },
    'policy': const {
      'evidenceReviewOnly': true,
      'writesDecisionLedger': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'notes':
          'Authenticated rows and no-row-found findings can become evidence-ready, but only a separate accepted reviewer decision can clear truth quality.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _caseReview({
  required String caseId,
  required Map<String, Object?> authCase,
  required Map<String, Object?> noRowCase,
  required Map<String, Object?> decision,
  required Map<String, Object?> noRowFindings,
}) {
  final noRowValidationErrors = <String>[];
  final noRowStatus = noRowCase['status']?.toString() ?? 'missing';
  final submittedFinding = _map(noRowCase['submittedFinding']);
  var noRowFindingValid = false;
  Map<String, Object?>? noRowEvidenceCandidate;
  if (noRowStatus == 'submitted_no_row_found') {
    noRowValidationErrors.addAll(
      validateSourceHinetNoRowFoundFindingInput(
        findingsJson: _withSinglePendingFinding(noRowFindings, caseId),
        inputJson: submittedFinding,
      ),
    );
    noRowFindingValid = noRowValidationErrors.isEmpty;
    if (noRowFindingValid) {
      noRowEvidenceCandidate = {
        'type': 'authenticated_hinet_no_row_found',
        'sourceType': submittedFinding['sourceType'],
        'sourceUrl': submittedFinding['sourceUrl'],
        'checkedAtUtc': submittedFinding['checkedAtUtc'],
        'reviewer': submittedFinding['reviewer'],
        'queryWindowJst': submittedFinding['queryWindowJst'],
        'searchResult': submittedFinding['searchResult'],
        'notes': submittedFinding['notes'],
      };
    }
  } else if (noRowStatus == 'pending_finding') {
    if (noRowCase['submittedFinding'] != null) {
      noRowValidationErrors.add('pending_no_row_must_not_have_payload');
    }
  } else if (noRowStatus == 'rejected') {
    if ((noRowCase['rejectionReason']?.toString() ?? '').trim().isEmpty) {
      noRowValidationErrors.add('rejected_no_row_missing_rejection_reason');
    }
  } else {
    noRowValidationErrors.add('unsupported_no_row_status:$noRowStatus');
  }

  final authenticatedEvidenceReady = authCase['decisionEvidenceReady'] == true;
  final noRowEvidenceReady =
      noRowFindingValid &&
      decision['decisionStatus'] == 'pending_manual_review' &&
      decision['acceptedForConstrainedReferenceSplit'] != true;
  final readyEvidenceTypes = [
    if (authenticatedEvidenceReady) 'authenticated_hinet_export_row',
    if (noRowEvidenceReady) 'authenticated_hinet_no_row_found',
  ];
  final combinedEvidenceStatus = readyEvidenceTypes.isEmpty
      ? 'pending_evidence'
      : readyEvidenceTypes.length == 1
      ? '${readyEvidenceTypes.single}_ready'
      : 'conflicting_evidence_ready';

  return {
    'caseId': caseId,
    'decisionStatus': decision['decisionStatus'] ?? 'missing_decision',
    'acceptedForConstrainedReferenceSplit':
        decision['acceptedForConstrainedReferenceSplit'] == true,
    'authenticatedRowStatus': authCase['rowStatus'] ?? 'missing',
    'authenticatedEvidenceReady': authenticatedEvidenceReady,
    'authenticatedEvidenceCandidate': authCase['evidenceCandidate'],
    'noRowFindingStatus': noRowStatus,
    'noRowFindingValid': noRowFindingValid,
    'noRowEvidenceReady': noRowEvidenceReady,
    'noRowValidationErrors': noRowValidationErrors,
    'noRowEvidenceCandidate': noRowEvidenceCandidate,
    'combinedEvidenceStatus': combinedEvidenceStatus,
    'readyEvidenceTypes': readyEvidenceTypes,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
  };
}

Map<String, Object?> _withSinglePendingFinding(
  Map<String, Object?> findingsJson,
  String caseId,
) {
  final copy = Map<String, Object?>.from(findingsJson);
  copy['findings'] = [
    {
      'caseId': caseId,
      'status': 'pending_finding',
      'submittedFinding': null,
      'rejectionReason': null,
      'decisionImpact': 'none_pending_only',
    },
  ];
  return copy;
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'pendingEvidenceCount': cases
        .where((entry) => entry['combinedEvidenceStatus'] == 'pending_evidence')
        .length,
    'authenticatedEvidenceReadyCount': cases
        .where((entry) => entry['authenticatedEvidenceReady'] == true)
        .length,
    'noRowEvidenceReadyCount': cases
        .where((entry) => entry['noRowEvidenceReady'] == true)
        .length,
    'combinedEvidenceReadyCount': cases
        .where((entry) => _list(entry['readyEvidenceTypes']).isNotEmpty)
        .length,
    'conflictingEvidenceReadyCount': cases
        .where(
          (entry) =>
              entry['combinedEvidenceStatus'] == 'conflicting_evidence_ready',
        )
        .length,
    'acceptedDecisionCount': cases
        .where((entry) => entry['acceptedForConstrainedReferenceSplit'] == true)
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
    'validationErrorCount': cases.fold<int>(
      0,
      (total, entry) => total + _list(entry['noRowValidationErrors']).length,
    ),
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> authenticatedReview,
  required List<Map<String, Object?>> cases,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (authenticatedReview['status'] != 'pass') {
    violations.add('hinet_authenticated_export_review_not_pass');
  }
  final actualCaseIds = cases
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (actualCaseIds.length != _expectedCaseIds.length ||
      !actualCaseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_evidence_review_case_set');
  }
  if (_intValue(summary['caseCount']) != 6) {
    violations.add('unexpected_case_count');
  }
  if (_intValue(summary['conflictingEvidenceReadyCount']) != 0) {
    violations.add('conflicting_evidence_ready');
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
  if (_intValue(summary['validationErrorCount']) != 0) {
    violations.add('evidence_validation_errors_present');
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
    ..writeln('# Source Hi-net Evidence Review')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln('- Pending evidence: `${summary['pendingEvidenceCount']}`')
    ..writeln(
      '- Authenticated evidence ready: '
      '`${summary['authenticatedEvidenceReadyCount']}`',
    )
    ..writeln(
      '- No-row evidence ready: `${summary['noRowEvidenceReadyCount']}`',
    )
    ..writeln(
      '- Combined evidence ready: '
      '`${summary['combinedEvidenceReadyCount']}`',
    )
    ..writeln('- Accepted decisions: `${summary['acceptedDecisionCount']}`')
    ..writeln(
      '- Truth-quality acceptance allowed: '
      '`${summary['truthQualityAcceptanceAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Auth row | Auth ready | No-row | No-row ready | Combined status | Decision |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['authenticatedRowStatus']}` | '
      '`${entry['authenticatedEvidenceReady']}` | '
      '`${entry['noRowFindingStatus']}` | `${entry['noRowEvidenceReady']}` | '
      '`${entry['combinedEvidenceStatus']}` | `${entry['decisionStatus']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Evidence readiness is not truth-quality acceptance.')
    ..writeln(
      '- Authenticated rows and no-row-found findings both remain blocked until a separate reviewer decision accepts the case.',
    )
    ..writeln(
      '- This report does not write the decision ledger, assign splits or change metric eligibility.',
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
