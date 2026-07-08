import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hi-net review script regenerates readiness first', () {
    final script = File(
      'tools/validate_hinet_truth_quality_review.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains(r'[switch]$UseExistingReadiness'));
    expect(script, contains(r'if (-not $UseExistingReadiness)'));
    expect(
      script,
      contains('validate_source_estimation_split_assignment_readiness.ps1'),
    );
    expect(script, contains('build_hinet_truth_quality_review_report.dart'));
    expect(script, contains('hinet_truth_quality_review_report_test.dart'));
    expect(
      script.indexOf('validate_source_estimation_split_assignment_readiness'),
      lessThan(script.indexOf('build_hinet_truth_quality_review_report')),
    );
  });

  test('Hi-net review report keeps preliminary labels reference-only', () {
    final reportFile = File(
      '.dart_tool/hinet_truth_quality_review/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing Hi-net truth-quality review report. Run '
        '`dart run tools/build_hinet_truth_quality_review_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'hinet_truth_quality_review_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['warnings'], isEmpty);
    expect(report['readinessStatus'], 'pass');
    expect(
      report['decisionPath'],
      'docs/data/hinet_truth_quality_review_decisions.json',
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['hinetReviewCaseCount'], 7);
    expect(summary['decisionCaseCount'], 7);
    expect(summary['pendingDecisionCount'], 1);
    expect(summary['acceptedForConstrainedReferenceSplitCount'], 6);
    expect(summary['blockingEvidenceCaseCount'], 1);
    expect(summary['blockingEvidenceCount'], 1);
    expect(summary['captureDirectoryExistsCount'], 7);
    expect(summary['captureManifestExistsCount'], 7);
    expect(summary['captureProvenanceCompleteCount'], 6);
    expect(summary['captureManifestFailureCount'], 1);
    expect(summary['referenceIsolatedCount'], 2);
    expect(summary['manualReviewReadyCount'], 2);
    expect(summary['catalogTruthFlagMismatchCount'], 0);

    final flagCounts = (summary['reviewFlagCounts'] as Map)
        .cast<String, Object?>();
    expect(flagCounts['review_decision_pending'], 1);
    expect(flagCounts['preliminary'], 4);
    expect(flagCounts['user_provided_not_preliminary'], 3);
    expect(flagCounts['capture_manifest_has_failed_gifs'], 1);
    expect(flagCounts['capture_manifest_has_missing_frames'], 1);
    expect(flagCounts['capture_provenance_incomplete'], 1);
    expect(flagCounts['not_isolated_from_frozen_metrics'], 5);

    final blockingEvidenceTypeCounts =
        (summary['blockingEvidenceTypeCounts'] as Map).cast<String, Object?>();
    expect(blockingEvidenceTypeCounts['capture_repair_attempt'], 1);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      cases.map((entry) => entry['caseId']),
      containsAll([
        '20260620_iwate_offshore_m34_ref',
        '20260621_fukushima_offshore_m32_eq6',
        '20260622_iwate_east_offshore_m30_hinet',
        '20260622_iwate_offshore_m30_eq10',
        '20260622_tomakomai_south_offshore_m35_hinet',
        '20260622_wakayama_south_m25_hinet',
        '20260623_tokachi_southeast_offshore_m34_hinet',
      ]),
    );
    for (final item in cases) {
      expect(item['captureDirectoryExists'], isTrue);
      expect(item['captureManifestExists'], isTrue);
      expect(item['includeInDetectionMetrics'], isFalse);
      expect(item['decisionRequiredActions'], isNotEmpty);
      if (item['splitStatus'] == 'validation_reference') {
        expect(item['referenceIsolated'], isFalse);
        expect(item['manualReviewReady'], isFalse);
        expect(
          item['reviewFlags'],
          contains('not_isolated_from_frozen_metrics'),
        );
      } else {
        expect(item['referenceIsolated'], isTrue);
        expect(item['manualReviewReady'], isTrue);
        expect(item['splitStatus'], 'unassigned_reference');
      }
      if (item['acceptedForConstrainedReferenceSplit'] == true) {
        expect(item['decisionStatus'], 'accepted_constrained_reference');
        expect(item['reviewFlags'], isNot(contains('review_decision_pending')));
      } else {
        expect(item['decisionStatus'], 'pending_manual_review');
        expect(item['reviewFlags'], contains('review_decision_pending'));
      }
    }

    final iwateM34 = cases.singleWhere(
      (entry) => entry['caseId'] == '20260620_iwate_offshore_m34_ref',
    );
    expect(iwateM34['captureExpectedGifCount'], 302);
    expect(iwateM34['captureDownloadedGifCount'], 301);
    expect(iwateM34['captureFailedGifCount'], 1);
    expect(iwateM34['captureMissingFrameCount'], 1);
    expect(iwateM34['captureProvenanceComplete'], isFalse);
    final blockingEvidence = (iwateM34['blockingEvidence'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(blockingEvidence, hasLength(1));
    expect(blockingEvidence.single['type'], 'capture_repair_attempt');
    expect(blockingEvidence.single['result'], 'http_404_not_found');
    expect(blockingEvidence.single['affectedFile'], '20260620212727.jma_b.gif');
    expect(
      iwateM34['reviewFlags'],
      containsAll([
        'capture_manifest_has_failed_gifs',
        'capture_manifest_has_missing_frames',
        'capture_provenance_incomplete',
      ]),
    );

    final completeCaptures = cases.where(
      (entry) => entry['captureProvenanceComplete'] == true,
    );
    expect(completeCaptures.length, 6);
  });
}
