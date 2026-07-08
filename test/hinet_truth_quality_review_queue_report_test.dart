import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hi-net review queue script regenerates source review first', () {
    final script = File(
      'tools/validate_hinet_truth_quality_review_queue.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('UseExistingTruthReview'));
    expect(script, contains('validate_hinet_truth_quality_review.ps1'));
    expect(
      script,
      contains('build_hinet_truth_quality_review_queue_report.dart'),
    );
    expect(
      script,
      contains('hinet_truth_quality_review_queue_report_test.dart'),
    );
    expect(
      script.indexOf('validate_hinet_truth_quality_review.ps1'),
      lessThan(
        script.indexOf('build_hinet_truth_quality_review_queue_report.dart'),
      ),
    );
  });

  test('Hi-net review queue separates external-evidence targets', () {
    final reportFile = File(
      '.dart_tool/hinet_truth_quality_review_queue/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing Hi-net truth-quality review queue report. Run '
        '`dart run tools/build_hinet_truth_quality_review_queue_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'hinet_truth_quality_review_queue_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['warnings'], isEmpty);
    expect(
      report['reviewReportPath'],
      '.dart_tool/hinet_truth_quality_review/report.json',
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 7);
    expect(summary['priorityExternalEvidenceReviewCount'], 6);
    expect(summary['captureRepairBlockedCount'], 1);
    expect(summary['catalogFlagMismatchBlockedCount'], 0);
    expect(summary['externalEvidenceMissingCount'], 1);
    expect(summary['acceptedForConstrainedReferenceSplitCount'], 6);

    final nextActionCounts = (summary['nextActionCounts'] as Map)
        .cast<String, Object?>();
    expect(
      nextActionCounts['collect_external_hinet_or_jma_revised_evidence'],
      6,
    );
    expect(nextActionCounts['repair_capture_before_review'], 1);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final priorityCases = cases
        .where(
          (entry) =>
              entry['nextAction'] ==
              'collect_external_hinet_or_jma_revised_evidence',
        )
        .map((entry) => entry['caseId'])
        .toSet();
    expect(priorityCases, {
      '20260621_fukushima_offshore_m32_eq6',
      '20260622_iwate_east_offshore_m30_hinet',
      '20260622_iwate_offshore_m30_eq10',
      '20260622_tomakomai_south_offshore_m35_hinet',
      '20260622_wakayama_south_m25_hinet',
      '20260623_tokachi_southeast_offshore_m34_hinet',
    });

    final captureBlocked = cases.singleWhere(
      (entry) => entry['caseId'] == '20260620_iwate_offshore_m34_ref',
    );
    expect(captureBlocked['nextAction'], 'repair_capture_before_review');
    expect(
      captureBlocked['requiredEvidence'],
      contains('complete_or_exclude_local_capture_package'),
    );

    final mismatchCases = cases
        .where(
          (entry) =>
              entry['nextAction'] == 'resolve_catalog_truth_flag_mismatch',
        )
        .map((entry) => entry['caseId'])
        .toSet();
    expect(mismatchCases, isEmpty);
  });
}
