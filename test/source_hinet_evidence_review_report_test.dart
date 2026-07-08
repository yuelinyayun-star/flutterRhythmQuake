import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_evidence_review_report.dart';

void main() {
  test('source Hi-net evidence review validator runs no-row chain first', () {
    final script = File(
      'tools/validate_source_hinet_evidence_review.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_hinet_no_row_found_review.ps1'));
    expect(script, contains('build_source_hinet_evidence_review_report.dart'));
    expect(script, contains('source_hinet_evidence_review_report_test.dart'));
  });

  test('source Hi-net evidence review tracks imported rows as review-only', () {
    final report = buildSourceHinetEvidenceReviewReportJson();

    expect(report['schemaVersion'], 'source_hinet_evidence_review_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['evidenceReviewOnly'], isTrue);
    expect(policy['writesDecisionLedger'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 6);
    expect(summary['pendingEvidenceCount'], 6);
    expect(summary['authenticatedEvidenceReadyCount'], 0);
    expect(summary['noRowEvidenceReadyCount'], 0);
    expect(summary['combinedEvidenceReadyCount'], 0);
    expect(summary['conflictingEvidenceReadyCount'], 0);
    expect(summary['acceptedDecisionCount'], 6);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);
    expect(summary['validationErrorCount'], 0);

    final validation = (report['validation'] as Map).cast<String, Object?>();
    expect(validation['status'], 'pass');
    expect(validation['violations'], isEmpty);

    final cases = {
      for (final rawCase in report['cases'] as List)
        (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
    };
    expect(cases.keys, {
      '20260621_fukushima_offshore_m32_eq6',
      '20260622_iwate_east_offshore_m30_hinet',
      '20260622_iwate_offshore_m30_eq10',
      '20260622_tomakomai_south_offshore_m35_hinet',
      '20260622_wakayama_south_m25_hinet',
      '20260623_tokachi_southeast_offshore_m34_hinet',
    });
    final acceptedCases = [
      cases['20260621_fukushima_offshore_m32_eq6']!,
      cases['20260622_iwate_east_offshore_m30_hinet']!,
      cases['20260622_iwate_offshore_m30_eq10']!,
      cases['20260622_tomakomai_south_offshore_m35_hinet']!,
      cases['20260622_wakayama_south_m25_hinet']!,
      cases['20260623_tokachi_southeast_offshore_m34_hinet']!,
    ];
    for (final entry in acceptedCases) {
      expect(entry['authenticatedRowStatus'], 'submitted_for_review');
      expect(entry['acceptedForConstrainedReferenceSplit'], isTrue);
      expect(entry['authenticatedEvidenceReady'], isFalse);
      expect(entry['noRowFindingStatus'], 'pending_finding');
      expect(entry['noRowEvidenceReady'], isFalse);
      expect(entry['combinedEvidenceStatus'], 'pending_evidence');
      expect(entry['decisionStatus'], 'accepted_constrained_reference');
      expect(entry['truthQualityAcceptanceAllowed'], isFalse);
      expect(entry['metricPromotionAllowed'], isFalse);
      expect(entry['splitAssignmentAllowed'], isFalse);
    }
  });

  test('submitted no-row finding becomes evidence-ready only', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_evidence_review_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final findings =
        jsonDecode(
              File(
                'docs/data/source_hinet_no_row_found_findings.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final rawFindings = (findings['findings'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    rawFindings[0]
      ..['status'] = 'submitted_no_row_found'
      ..['submittedFinding'] = {
        'caseId': '20260622_iwate_east_offshore_m30_hinet',
        'sourceType': 'hinet_jma_unified_catalog',
        'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
        'checkedAtUtc': '2026-06-27T00:00:00Z',
        'reviewer': 'reviewer-id',
        'queryWindowJst': '2026-06-22T11:21:50..2026-06-22T11:31:50',
        'searchResult': 'no_event_row_found',
        'searchedOriginTimeJst': '2026-06-22T11:26:50',
        'searchedLatitude': 39.91,
        'searchedLongitude': 142.347,
        'searchedMagnitude': 3.0,
        'notes': 'Authenticated event-level search returned no matching row.',
      };
    findings['findings'] = rawFindings;
    final findingsFile = File('${tempDir.path}/findings.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(findings)}\n',
      );
    final authReview =
        jsonDecode(
              File(
                '.dart_tool/hinet_authenticated_export_review/report.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    authReview['cases'] = (authReview['cases'] as List)
        .map((entry) {
          final item = (entry as Map).cast<String, Object?>();
          return {
            ...item,
            'rowStatus': 'pending_export',
            'submittedRowValid': false,
            'decisionEvidenceReady': false,
            'evidenceCandidate': null,
          };
        })
        .toList(growable: false);
    final authReviewFile = File('${tempDir.path}/auth_review.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(authReview)}\n',
      );
    final decisionsFile = _pendingDecisionsFile(tempDir);

    final report = buildSourceHinetEvidenceReviewReportJson(
      authenticatedReviewPath: authReviewFile.path,
      noRowFindingsPath: findingsFile.path,
      decisionPath: decisionsFile.path,
    );
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['noRowEvidenceReadyCount'], 1);
    expect(summary['combinedEvidenceReadyCount'], 1);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final iwate = cases.singleWhere(
      (entry) => entry['caseId'] == '20260622_iwate_east_offshore_m30_hinet',
    );
    expect(iwate['noRowFindingValid'], isTrue);
    expect(iwate['noRowEvidenceReady'], isTrue);
    expect(
      iwate['combinedEvidenceStatus'],
      'authenticated_hinet_no_row_found_ready',
    );
    expect(iwate['truthQualityAcceptanceAllowed'], isFalse);
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
