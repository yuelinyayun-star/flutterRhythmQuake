import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_reviewer_decision_staging_report.dart';
import '../tools/build_source_hinet_evidence_review_report.dart';

void main() {
  test('reviewer decision staging validator runs evidence review first', () {
    final script = File(
      'tools/validate_source_hinet_reviewer_decision_staging.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_hinet_evidence_review.ps1'));
    expect(
      script,
      contains('build_source_hinet_reviewer_decision_staging_report.dart'),
    );
    expect(
      script,
      contains('source_hinet_reviewer_decision_staging_report_test.dart'),
    );
  });

  test('reviewer decision staging exposes imported rows for manual review', () {
    final report = buildSourceHinetReviewerDecisionStagingReportJson();

    expect(
      report['schemaVersion'],
      'source_hinet_reviewer_decision_staging_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['stagingOnly'], isTrue);
    expect(policy['writesDecisionLedger'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 6);
    expect(summary['reviewerDecisionEligibleCount'], 0);
    expect(summary['blockedCount'], 6);
    expect(summary['evidenceNotReadyCount'], 6);
    expect(summary['conflictingEvidenceReadyCount'], 0);
    expect(summary['alreadyAcceptedCount'], 6);
    expect(summary['decisionLedgerWriteAllowedCount'], 0);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);

    final validation = (report['validation'] as Map).cast<String, Object?>();
    expect(validation['status'], 'pass');
    expect(validation['violations'], isEmpty);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final eligibleCases = cases
        .where((entry) => entry['reviewerDecisionEligible'] == true)
        .toList(growable: false);
    expect(eligibleCases, isEmpty);

    final blockedCases = cases
        .where((entry) => entry['reviewerDecisionEligible'] == false)
        .toList(growable: false);
    expect(blockedCases, hasLength(6));
    for (final entry in blockedCases) {
      expect(entry['blockingReasons'], contains('already_accepted'));
      expect(entry['decisionLedgerWriteAllowed'], isFalse);
      expect(entry['truthQualityAcceptanceAllowed'], isFalse);
      expect(entry['metricPromotionAllowed'], isFalse);
      expect(entry['splitAssignmentAllowed'], isFalse);
    }
  });

  test('ready evidence becomes reviewer-eligible only', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_staging_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final evidenceReview = buildSourceHinetEvidenceReviewReportJson();
    final cases = (evidenceReview['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    for (final entry in cases) {
      entry
        ..['combinedEvidenceStatus'] = 'pending_evidence'
        ..['readyEvidenceTypes'] = <String>[];
    }
    cases[0]
      ..['combinedEvidenceStatus'] = 'authenticated_hinet_export_row_ready'
      ..['readyEvidenceTypes'] = ['authenticated_hinet_export_row'];
    evidenceReview['cases'] = cases;
    evidenceReview['summary'] = {
      ...(evidenceReview['summary'] as Map).cast<String, Object?>(),
      'pendingEvidenceCount': 2,
      'authenticatedEvidenceReadyCount': 1,
      'combinedEvidenceReadyCount': 1,
    };
    final evidenceFile = File('${tempDir.path}/evidence.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(evidenceReview)}\n',
      );
    final decisionsFile = _pendingDecisionsFile(tempDir);

    final report = buildSourceHinetReviewerDecisionStagingReportJson(
      evidenceReviewPath: evidenceFile.path,
      decisionPath: decisionsFile.path,
    );
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['reviewerDecisionEligibleCount'], 1);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);

    final stagedCases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final ready = stagedCases.firstWhere(
      (entry) => entry['reviewerDecisionEligible'] == true,
    );
    expect(ready['blockingReasons'], isEmpty);
    expect(
      ready['suggestedDecisionStatus'],
      'accepted_constrained_reference_or_rejected_after_review',
    );
    expect(ready['truthQualityAcceptanceAllowed'], isFalse);
  });
}

File _pendingDecisionsFile(Directory tempDir) {
  final decisions =
      jsonDecode(
            File(
              'docs/data/hinet_truth_quality_review_decisions.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  decisions['cases'] = (decisions['cases'] as List)
      .map((entry) {
        final item = (entry as Map).cast<String, Object?>();
        return {
          ...item,
          'decisionStatus': 'pending_manual_review',
          'acceptedForConstrainedReferenceSplit': false,
          'reviewedAtUtc': null,
          'reviewer': null,
          'evidence': <String>[],
        }..remove('decisionImport');
      })
      .toList(growable: false);
  return File('${tempDir.path}/decisions.json')..writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(decisions)}\n',
  );
}
