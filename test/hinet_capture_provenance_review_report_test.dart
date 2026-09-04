import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_capture_provenance_review_report.dart';

void main() {
  test('capture provenance review script regenerates truth review first', () {
    final script = File(
      'tools/validate_hinet_capture_provenance_review.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('UseExistingTruthReview'));
    expect(script, contains('tools\\validate_hinet_truth_quality_review.ps1'));
    expect(
      script,
      contains('build_hinet_capture_provenance_review_report.dart'),
    );
    expect(
      script,
      contains('build_hinet_capture_exclusion_template_report.dart'),
    );
    expect(
      script,
      contains('build_hinet_capture_exclusion_review_packet.dart'),
    );
    expect(
      script,
      contains('hinet_capture_provenance_review_report_test.dart'),
    );
    expect(
      script,
      contains('hinet_capture_exclusion_template_report_test.dart'),
    );
    expect(script, contains('hinet_capture_exclusion_review_packet_test.dart'));
    expect(
      script,
      contains('hinet_capture_exclusion_decision_import_test.dart'),
    );
    expect(
      script.indexOf('validate_hinet_truth_quality_review.ps1'),
      lessThan(
        script.indexOf('build_hinet_capture_provenance_review_report.dart'),
      ),
    );
  });

  test(
    'capture provenance review reflects approved exclusion for incomplete capture',
    () {
      final reportFile = File(
        '.dart_tool/hinet_capture_provenance_review/report.json',
      );
      if (!reportFile.existsSync()) {
        markTestSkipped(
          'Missing capture provenance review report. Run '
          '`dart run tools/build_hinet_capture_provenance_review_report.dart`.',
        );
        return;
      }

      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['schemaVersion'], 'hinet_capture_provenance_review_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);
      expect(report['warnings'], isEmpty);
      expect(
        report['truthReviewPath'],
        '.dart_tool/hinet_truth_quality_review/report.json',
      );
      expect(
        report['decisionPath'],
        'docs/data/hinet_capture_provenance_review_decisions.json',
      );

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 1);
      expect(summary['pendingRepairOrExclusionCount'], 0);
      expect(summary['exclusionApprovedCount'], 1);
      expect(summary['readyAfterExclusionCount'], 1);
      expect(summary['unresolvedCaptureIssueCount'], 0);
      expect(summary['failedGifCount'], 1);
      expect(summary['missingFrameCount'], 1);
      expect(summary['blockingEvidenceCount'], 1);

      final cases = (report['cases'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      final iwate = cases.single;
      expect(iwate['caseId'], '20260620_iwate_offshore_m34_ref');
      expect(iwate['decisionStatus'], 'capture_frame_exclusion_approved');
      expect(iwate['captureExpectedGifCount'], 302);
      expect(iwate['captureDownloadedGifCount'], 301);
      expect(iwate['captureFailedGifCount'], 1);
      expect(iwate['captureMissingFrameCount'], 1);
      expect(iwate['captureProvenanceComplete'], isFalse);
      expect(iwate['exclusionApproved'], isTrue);
      expect(iwate['readyAfterExclusion'], isTrue);
      final excludedFiles = (iwate['excludedFiles'] as List)
          .map((entry) => entry.toString())
          .toList(growable: false);
      expect(excludedFiles, contains('20260620212727.jma_b.gif'));
      expect(excludedFiles, contains('missing_frame_1'));
      final blockingEvidence = (iwate['blockingEvidence'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(blockingEvidence.single['type'], 'capture_repair_attempt');
      expect(
        blockingEvidence.single['affectedFile'],
        '20260620212727.jma_b.gif',
      );
    },
  );

  test('explicit exclusion decision can clear capture issue only in report', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_capture_provenance_review_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final decisions =
        jsonDecode(
              File(
                'docs/data/hinet_capture_provenance_review_decisions.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final cases = (decisions['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    cases[0]
      ..['decisionStatus'] = 'capture_frame_exclusion_approved'
      ..['reviewedAtUtc'] = '2026-06-26T06:30:00Z'
      ..['reviewer'] = 'reviewer-id'
      ..['exclusionApproved'] = true
      ..['excludedFiles'] = ['20260620212727.jma_b.gif', 'missing_frame_1']
      ..['exclusionReason'] =
          'Historical NIED GIF returned HTTP 404 and only one frame is missing.';
    decisions['cases'] = cases;

    final decisionFile = File('${tempDir.path}/decisions.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(decisions)}\n',
      );

    final report = buildHinetCaptureProvenanceReviewJson(
      decisionPath: decisionFile.path,
    );
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['exclusionApprovedCount'], 1);
    expect(summary['readyAfterExclusionCount'], 1);
    expect(summary['unresolvedCaptureIssueCount'], 0);

    final reportCases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final iwate = reportCases.single;
    expect(iwate['decisionStatus'], 'capture_frame_exclusion_approved');
    expect(iwate['exclusionApproved'], isTrue);
    expect(iwate['readyAfterExclusion'], isTrue);
  });
}
