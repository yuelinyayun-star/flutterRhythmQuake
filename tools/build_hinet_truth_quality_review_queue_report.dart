import 'dart:convert';
import 'dart:io';

const _defaultReviewReport =
    '.dart_tool/hinet_truth_quality_review/report.json';
const _defaultOutput =
    '.dart_tool/hinet_truth_quality_review_queue/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_truth_quality_review_queue.generated.md';

void main(List<String> args) {
  final reviewReportPath =
      _argument(args, '--review-report') ?? _defaultReviewReport;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _HinetTruthQualityReviewQueueReport.build(
    reviewReport: File(reviewReportPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net truth-quality review queue report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _HinetTruthQualityReviewQueueReport {
  final String reviewReportPath;
  final List<_HinetReviewQueueCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _HinetTruthQualityReviewQueueReport({
    required this.reviewReportPath,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _HinetTruthQualityReviewQueueReport.build({
    required File reviewReport,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final cases = <_HinetReviewQueueCase>[];

    if (!reviewReport.existsSync()) {
      errors.add(
        'hinet_truth_quality_review_report_missing:${reviewReport.path}',
      );
    } else {
      final report =
          jsonDecode(reviewReport.readAsStringSync()) as Map<String, Object?>;
      if (report['schemaVersion'] != 'hinet_truth_quality_review_v1') {
        errors.add('unexpected_hinet_truth_quality_review_schema');
      }
      if (report['status'] != 'pass') {
        errors.add('hinet_truth_quality_review_report_not_pass');
      }
      for (final rawCase in _list(report['cases'])) {
        cases.add(_HinetReviewQueueCase.fromJson(_map(rawCase)));
      }
    }

    cases.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      return left.caseId.compareTo(right.caseId);
    });

    return _HinetTruthQualityReviewQueueReport(
      reviewReportPath: reviewReport.path,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final nextActionCounts = <String, int>{};
    for (final item in cases) {
      nextActionCounts[item.nextAction] =
          (nextActionCounts[item.nextAction] ?? 0) + 1;
    }
    return {
      'schemaVersion': 'hinet_truth_quality_review_queue_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'reviewReportPath': reviewReportPath,
      'summary': {
        'caseCount': cases.length,
        'priorityExternalEvidenceReviewCount': cases
            .where(
              (item) =>
                  item.nextAction ==
                  'collect_external_hinet_or_jma_revised_evidence',
            )
            .length,
        'captureRepairBlockedCount': cases
            .where((item) => item.nextAction == 'repair_capture_before_review')
            .length,
        'catalogFlagMismatchBlockedCount': cases
            .where(
              (item) =>
                  item.nextAction == 'resolve_catalog_truth_flag_mismatch',
            )
            .length,
        'externalEvidenceMissingCount': cases
            .where((item) => item.externalEvidenceMissing)
            .length,
        'acceptedForConstrainedReferenceSplitCount': cases
            .where((item) => item.acceptedForConstrainedReferenceSplit)
            .length,
        'nextActionCounts': nextActionCounts,
      },
      'errors': errors,
      'warnings': warnings,
      'cases': cases.map((item) => item.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final nextActionCounts = (summary['nextActionCounts'] as Map)
        .cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Truth-Quality Review Queue')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Review report: `$reviewReportPath`')
      ..writeln('- Cases: `${summary['caseCount']}`')
      ..writeln(
        '- Priority external-evidence reviews: '
        '`${summary['priorityExternalEvidenceReviewCount']}`',
      )
      ..writeln(
        '- Capture-repair blocked: '
        '`${summary['captureRepairBlockedCount']}`',
      )
      ..writeln(
        '- Catalog-flag-mismatch blocked: '
        '`${summary['catalogFlagMismatchBlockedCount']}`',
      )
      ..writeln(
        '- External evidence missing: '
        '`${summary['externalEvidenceMissingCount']}`',
      )
      ..writeln(
        '- Accepted constrained references: '
        '`${summary['acceptedForConstrainedReferenceSplitCount']}`',
      )
      ..writeln()
      ..writeln('## Next Action Counts')
      ..writeln()
      ..writeln('| Action | Count |')
      ..writeln('| --- | ---: |');
    for (final action in nextActionCounts.keys.toList()..sort()) {
      buffer.writeln('| `$action` | ${nextActionCounts[action]} |');
    }
    buffer
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Priority | Next action | Truth quality | Capture complete | Catalog mismatch | Required evidence |',
      )
      ..writeln('| --- | ---: | --- | --- | --- | --- | --- |');
    for (final item in cases) {
      buffer.writeln(
        '| `${item.caseId}` | ${item.priority} | `${item.nextAction}` | '
        '`${item.truthQuality}` | '
        '${item.captureProvenanceComplete ? 'yes' : 'no'} | '
        '${item.catalogTruthFlagMismatch ? 'yes' : 'no'} | '
        '`${item.requiredEvidence.join('`, `')}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This queue does not accept or split any Hi-net case. It only orders '
        'the current pending review cases by the evidence needed next.',
      )
      ..writeln(
        '- Cases in `collect_external_hinet_or_jma_revised_evidence` are the '
        'first practical review targets because their local capture packages '
        'are complete and they do not carry the catalog-truth flag mismatch.',
      )
      ..writeln(
        '- Cases with catalog-truth flag mismatch must first remove or justify '
        'that mismatch; Hi-net/user-provided labels are not JMA final catalog '
        'truth.',
      );
    return buffer.toString();
  }
}

class _HinetReviewQueueCase {
  final String caseId;
  final String truthSource;
  final String truthQuality;
  final String decisionStatus;
  final bool acceptedForConstrainedReferenceSplit;
  final bool captureProvenanceComplete;
  final bool catalogTruthFlagMismatch;
  final bool blockingEvidencePresent;
  final List<String> decisionRequiredActions;
  final List<String> requiredEvidence;
  final String nextAction;
  final int priority;

  const _HinetReviewQueueCase({
    required this.caseId,
    required this.truthSource,
    required this.truthQuality,
    required this.decisionStatus,
    required this.acceptedForConstrainedReferenceSplit,
    required this.captureProvenanceComplete,
    required this.catalogTruthFlagMismatch,
    required this.blockingEvidencePresent,
    required this.decisionRequiredActions,
    required this.requiredEvidence,
    required this.nextAction,
    required this.priority,
  });

  bool get externalEvidenceMissing =>
      decisionStatus == 'pending_manual_review' &&
      !acceptedForConstrainedReferenceSplit;

  factory _HinetReviewQueueCase.fromJson(Map<String, Object?> json) {
    final truthQuality = json['truthQuality']?.toString() ?? '';
    final captureProvenanceComplete = json['captureProvenanceComplete'] == true;
    final catalogTruthFlagMismatch = json['catalogTruthFlagMismatch'] == true;
    final blockingEvidencePresent = _list(json['blockingEvidence']).isNotEmpty;
    final decisionRequiredActions = _list(
      json['decisionRequiredActions'],
    ).map((entry) => entry.toString()).toList(growable: false);
    final requiredEvidence = _requiredEvidence(
      truthQuality: truthQuality,
      captureProvenanceComplete: captureProvenanceComplete,
      catalogTruthFlagMismatch: catalogTruthFlagMismatch,
      blockingEvidencePresent: blockingEvidencePresent,
    );
    final nextAction = _nextAction(
      captureProvenanceComplete: captureProvenanceComplete,
      catalogTruthFlagMismatch: catalogTruthFlagMismatch,
      blockingEvidencePresent: blockingEvidencePresent,
    );
    return _HinetReviewQueueCase(
      caseId: json['caseId']?.toString() ?? '',
      truthSource: json['truthSource']?.toString() ?? '',
      truthQuality: truthQuality,
      decisionStatus: json['decisionStatus']?.toString() ?? '',
      acceptedForConstrainedReferenceSplit:
          json['acceptedForConstrainedReferenceSplit'] == true,
      captureProvenanceComplete: captureProvenanceComplete,
      catalogTruthFlagMismatch: catalogTruthFlagMismatch,
      blockingEvidencePresent: blockingEvidencePresent,
      decisionRequiredActions: decisionRequiredActions,
      requiredEvidence: requiredEvidence,
      nextAction: nextAction,
      priority: _priority(nextAction),
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'truthSource': truthSource,
    'truthQuality': truthQuality,
    'decisionStatus': decisionStatus,
    'acceptedForConstrainedReferenceSplit':
        acceptedForConstrainedReferenceSplit,
    'captureProvenanceComplete': captureProvenanceComplete,
    'catalogTruthFlagMismatch': catalogTruthFlagMismatch,
    'blockingEvidencePresent': blockingEvidencePresent,
    'decisionRequiredActions': decisionRequiredActions,
    'requiredEvidence': requiredEvidence,
    'nextAction': nextAction,
    'priority': priority,
  };
}

List<String> _requiredEvidence({
  required String truthQuality,
  required bool captureProvenanceComplete,
  required bool catalogTruthFlagMismatch,
  required bool blockingEvidencePresent,
}) {
  return [
    if (!captureProvenanceComplete || blockingEvidencePresent)
      'complete_or_exclude_local_capture_package',
    if (catalogTruthFlagMismatch)
      'remove_or_justify_catalog_truth_verified_flag',
    if (truthQuality.contains('preliminary'))
      'revised_hinet_or_jma_final_catalog_link'
    else
      'external_hinet_or_jma_source_quality_evidence',
    'reviewer_and_review_timestamp',
  ];
}

String _nextAction({
  required bool captureProvenanceComplete,
  required bool catalogTruthFlagMismatch,
  required bool blockingEvidencePresent,
}) {
  if (!captureProvenanceComplete || blockingEvidencePresent) {
    return 'repair_capture_before_review';
  }
  if (catalogTruthFlagMismatch) {
    return 'resolve_catalog_truth_flag_mismatch';
  }
  return 'collect_external_hinet_or_jma_revised_evidence';
}

int _priority(String nextAction) {
  switch (nextAction) {
    case 'collect_external_hinet_or_jma_revised_evidence':
      return 1;
    case 'resolve_catalog_truth_flag_mismatch':
      return 2;
    case 'repair_capture_before_review':
      return 3;
    default:
      return 99;
  }
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}
