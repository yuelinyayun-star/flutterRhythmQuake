import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_evidence_propagation_rehearsal.dart';

void main() {
  test('evidence propagation rehearsal is temporary and reaches staging', () {
    final beforeRows = File(
      'docs/data/hinet_authenticated_export_rows.json',
    ).readAsStringSync();
    final beforeDecisions = File(
      'docs/data/hinet_truth_quality_review_decisions.json',
    ).readAsStringSync();

    final report = buildSourceHinetEvidencePropagationRehearsalJson();

    expect(
      report['schemaVersion'],
      'source_hinet_evidence_propagation_rehearsal_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['importValidationErrors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['rehearsalOnly'], isTrue);
    expect(policy['usesSyntheticSubmittedRow'], isTrue);
    expect(policy['writesRealEvidenceLedger'], isFalse);
    expect(policy['writesRealDecisionLedger'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(
      summary['rehearsalCaseId'],
      '20260622_iwate_east_offshore_m30_hinet',
    );
    expect(summary['importValidationErrorCount'], 0);
    expect(summary['authenticatedEvidenceReady'], isTrue);
    expect(summary['sourceEvidenceReady'], isTrue);
    expect(summary['reviewerDecisionEligible'], isTrue);
    expect(summary['reviewerDecisionTemplateEmitted'], isTrue);
    expect(summary['realEvidenceLedgerWrites'], 0);
    expect(summary['realDecisionLedgerWrites'], 0);
    expect(summary['truthQualityAcceptanceAllowed'], isFalse);
    expect(summary['metricPromotionAllowed'], isFalse);
    expect(summary['splitAssignmentAllowed'], isFalse);

    final rehearsal = (report['rehearsal'] as Map).cast<String, Object?>();
    final sourceEvidenceCase = (rehearsal['sourceEvidenceCase'] as Map)
        .cast<String, Object?>();
    expect(
      sourceEvidenceCase['readyEvidenceTypes'],
      contains('authenticated_hinet_export_row'),
    );
    final stagingCase = (rehearsal['stagingCase'] as Map)
        .cast<String, Object?>();
    expect(stagingCase['reviewerDecisionEligible'], isTrue);
    final templateCase = (rehearsal['reviewerTemplateCase'] as Map)
        .cast<String, Object?>();
    expect(templateCase['templateEmitted'], isTrue);

    expect(
      File('docs/data/hinet_authenticated_export_rows.json').readAsStringSync(),
      beforeRows,
    );
    expect(
      File(
        'docs/data/hinet_truth_quality_review_decisions.json',
      ).readAsStringSync(),
      beforeDecisions,
    );
  });

  test('generated rehearsal report is readable when present', () {
    final reportFile = File(
      '.dart_tool/source_hinet_evidence_propagation_rehearsal/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing propagation rehearsal report. Run '
        '`dart run tools/build_source_hinet_evidence_propagation_rehearsal.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_hinet_evidence_propagation_rehearsal_v1',
    );
  });
}
