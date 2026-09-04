import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_capture_repair_probe_report.dart';

void main() {
  test('capture repair probe script regenerates provenance review first', () {
    final script = File(
      'tools/validate_hinet_capture_repair_probe.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('UseExistingProvenanceReview'));
    expect(
      script,
      contains('tools\\validate_hinet_capture_provenance_review.ps1'),
    );
    expect(script, contains('build_hinet_capture_repair_probe_report.dart'));
    expect(script, contains('hinet_capture_repair_probe_report_test.dart'));
    expect(script, contains('hinet_capture_repair_candidate_import_test.dart'));
    expect(
      script.indexOf('validate_hinet_capture_provenance_review.ps1'),
      lessThan(script.indexOf('build_hinet_capture_repair_probe_report.dart')),
    );
  });

  test('capture repair probe has no cases after exclusion approved', () {
    final reportFile = File(
      '.dart_tool/hinet_capture_repair_probe/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing capture repair probe report. Run '
        '`dart run tools/build_hinet_capture_repair_probe_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'hinet_capture_repair_probe_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(
      report['reviewPath'],
      '.dart_tool/hinet_capture_provenance_review/report.json',
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 0);
    expect(summary['affectedFileCount'], 0);
    expect(summary['repairInputTemplateCount'], 0);
    expect(summary['manualReviewRequiredCount'], 0);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['localCandidateCount'], 0);
    expect(summary['validGifCandidateCount'], 0);
    expect(summary['remoteHintCount'], 0);
    expect(summary['invalidCandidateCount'], 0);
    expect(summary['repairCandidateReadyCount'], 0);
    expect(summary['unresolvedRepairCaseCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(cases, isEmpty);

    final templates = (report['repairInputTemplates'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(templates, isEmpty);
  });

  test('capture repair probe recognizes a valid local GIF candidate', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_capture_repair_probe_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final candidate = File('${tempDir.path}/20260620212727.jma_b.gif')
      ..writeAsBytesSync([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0, 59]);

    final reviewReport = _buildPendingReviewReport(tempDir.path);
    final reviewFile = File('${tempDir.path}/review.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(reviewReport)}\n',
      );

    final report = buildHinetCaptureRepairProbeJson(
      reviewPath: reviewFile.path,
      scanRoots: [tempDir.path],
      templateDirectory: '${tempDir.path}/templates',
    );
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['localCandidateCount'], 1);
    expect(summary['validGifCandidateCount'], 1);
    expect(summary['repairInputTemplateCount'], 1);
    expect(summary['manualReviewRequiredCount'], 1);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['remoteHintCount'], 1);
    expect(summary['repairCandidateReadyCount'], 1);
    expect(summary['unresolvedRepairCaseCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final affectedFiles = (cases.single['affectedFiles'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final candidates = (affectedFiles.single['candidates'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      candidates.single['path'].toString().replaceAll('\\', '/'),
      candidate.path.replaceAll('\\', '/'),
    );
    expect(candidates.single['isGif'], isTrue);
    expect(candidates.single['sha256'], isA<String>());
    final repairTemplate = (affectedFiles.single['repairInputTemplate'] as Map)
        .cast<String, Object?>();
    expect(
      repairTemplate['candidateStatus'],
      'prefilled_from_single_valid_candidate',
    );
    expect(repairTemplate['manualReviewRequired'], isTrue);
    expect(repairTemplate['automaticClearance'], isFalse);
    final remoteHints = (affectedFiles.single['remoteHints'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(remoteHints.single['source'], 'nied_kmoni_realtime_image');
    expect(remoteHints.single['remoteRetrievalAllowed'], isFalse);
  });
}

Map<String, Object?> _buildPendingReviewReport(String captureDirectory) {
  return {
    'schemaVersion': 'hinet_capture_provenance_review_v1',
    'createdAtUtc': '2026-06-29T00:00:00Z',
    'status': 'pass',
    'truthReviewPath': '.dart_tool/hinet_truth_quality_review/report.json',
    'decisionPath': 'docs/data/hinet_capture_provenance_review_decisions.json',
    'summary': {
      'caseCount': 1,
      'pendingRepairOrExclusionCount': 1,
      'exclusionApprovedCount': 0,
      'readyAfterExclusionCount': 0,
      'unresolvedCaptureIssueCount': 1,
      'failedGifCount': 1,
      'missingFrameCount': 1,
      'blockingEvidenceCount': 1,
    },
    'errors': <String>[],
    'warnings': <String>[],
    'cases': [
      {
        'caseId': '20260620_iwate_offshore_m34_ref',
        'captureDirectory':
            'tmp/captures/20260620_212527_jst_iwate_offshore_m34_ref',
        'captureExpectedGifCount': 302,
        'captureDownloadedGifCount': 301,
        'captureFailedGifCount': 1,
        'captureMissingFrameCount': 1,
        'captureProvenanceComplete': false,
        'blockingEvidence': [
          {
            'type': 'capture_repair_attempt',
            'checkedAtUtc': '2026-06-25T18:10:00Z',
            'url':
                'https://smi.lmoniexp.bosai.go.jp/data/map_img/RealTimeImg/jma_b/20260620/20260620212727.jma_b.gif',
            'result': 'http_404_not_found',
            'affectedFile': '20260620212727.jma_b.gif',
          },
        ],
        'decisionStatus': 'pending_capture_repair_or_exclusion',
        'exclusionApproved': false,
        'excludedFiles': <String>[],
        'readyAfterExclusion': false,
      },
    ],
  };
}
