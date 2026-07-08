import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_authenticated_export_review_report.dart';

void main() {
  test('authenticated export review script validates row intake first', () {
    final script = File(
      'tools/validate_hinet_authenticated_export_review.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains(r'[switch]$UseExistingExternalEvidenceTargets'));
    expect(script, contains(r'if (-not $UseExistingExternalEvidenceTargets)'));
    expect(
      script,
      contains('tools\\validate_hinet_external_evidence_targets.ps1'),
    );
    expect(
      script,
      contains('build_hinet_authenticated_export_review_report.dart'),
    );
    expect(
      script,
      contains('hinet_authenticated_export_review_report_test.dart'),
    );
    expect(script, contains('hinet_authenticated_export_row_import_test.dart'));
    expect(
      script,
      contains('build_hinet_authenticated_export_row_templates.dart'),
    );
    expect(
      script,
      contains('build_hinet_authenticated_export_review_packet.dart'),
    );
    expect(
      script,
      contains('hinet_authenticated_export_row_template_test.dart'),
    );
    expect(
      script,
      contains('hinet_authenticated_export_review_packet_test.dart'),
    );
    expect(
      script.indexOf('validate_hinet_external_evidence_targets.ps1'),
      lessThan(
        script.indexOf('build_hinet_authenticated_export_review_report.dart'),
      ),
    );
    expect(
      script.indexOf('build_hinet_authenticated_export_row_templates.dart'),
      lessThan(
        script.indexOf('build_hinet_authenticated_export_review_packet.dart'),
      ),
    );
  });

  test(
    'authenticated export review tracks real submitted rows as review-only',
    () {
      final reportFile = File(
        '.dart_tool/hinet_authenticated_export_review/report.json',
      );
      if (!reportFile.existsSync()) {
        markTestSkipped(
          'Missing authenticated export review report. Run '
          '`dart run tools/build_hinet_authenticated_export_review_report.dart`.',
        );
        return;
      }

      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['schemaVersion'], 'hinet_authenticated_export_review_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);
      expect(report['warnings'], isEmpty);
      expect(
        report['requestPath'],
        'docs/data/hinet_authenticated_export_request.json',
      );
      expect(
        report['rowsPath'],
        'docs/data/hinet_authenticated_export_rows.json',
      );
      expect(
        report['decisionPath'],
        'docs/data/hinet_truth_quality_review_decisions.json',
      );

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['rowCount'], 6);
      expect(summary['pendingExportCount'], 0);
      expect(summary['submittedForReviewCount'], 6);
      expect(summary['rejectedCount'], 0);
      expect(summary['validSubmittedRowCount'], 6);
      expect(summary['decisionEvidenceReadyCount'], 0);
      expect(summary['pendingDecisionCount'], 0);
      expect(summary['acceptedDecisionCount'], 6);
      expect(summary['validationErrorCount'], 0);

      final cases = (report['cases'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(cases, hasLength(6));
      final submittedCases = cases
          .where((item) => item['rowStatus'] == 'submitted_for_review')
          .toList(growable: false);
      expect(submittedCases, hasLength(6));
      final acceptedCases = submittedCases
          .where((item) => item['decisionStatus'] == 'accepted_constrained_reference')
          .toList(growable: false);
      expect(acceptedCases, hasLength(6));
      for (final item in acceptedCases) {
        expect(item['acceptedForConstrainedReferenceSplit'], isTrue);
        expect(item['submittedRowValid'], isTrue);
        expect(item['validationErrors'], isEmpty);
        expect(item['evidenceCandidate'], isA<Map>());
      }
      final pendingDecisionCases = submittedCases
          .where((item) => item['decisionStatus'] == 'pending_manual_review')
          .toList(growable: false);
      expect(pendingDecisionCases, isEmpty);
      final pendingCases = cases
          .where((item) => item['rowStatus'] == 'pending_export')
          .toList(growable: false);
      expect(pendingCases, isEmpty);
    },
  );

  test('pending rows remain inert in an empty intake ledger', () {
    final rows =
        jsonDecode(
              File(
                'docs/data/hinet_authenticated_export_rows.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    rows['rows'] = (rows['rows'] as List)
        .map((entry) {
          final row = (entry as Map).cast<String, Object?>();
          return {
            ...row,
            'status': 'pending_export',
            'submittedRow': null,
            'rejectionReason': null,
            'decisionImpact': 'none_pending_only',
          };
        })
        .toList(growable: false);

    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_authenticated_export_pending_review_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final rowsFile = File('${tempDir.path}/rows.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(rows)}\n',
      );
    final decisionsFile = _pendingDecisionsFile(tempDir);
    final report = buildHinetAuthenticatedExportReviewJson(
      rowsPath: rowsFile.path,
      decisionPath: decisionsFile.path,
    );
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['pendingExportCount'], 6);
    expect(summary['submittedForReviewCount'], 0);
    expect(summary['decisionEvidenceReadyCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    for (final item in cases) {
      expect(item['rowStatus'], 'pending_export');
      expect(item['decisionStatus'], 'pending_manual_review');
      expect(item['acceptedForConstrainedReferenceSplit'], isFalse);
      expect(item['submittedRowValid'], isFalse);
      expect(item['decisionEvidenceReady'], isFalse);
      expect(item['validationErrors'], isEmpty);
      expect(item['evidenceCandidate'], isNull);
    }
  });

  test('valid submitted row becomes evidence candidate only', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_authenticated_export_review_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final rows =
        jsonDecode(
              File(
                'docs/data/hinet_authenticated_export_rows.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final rawRows = (rows['rows'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .map(
          (entry) => {
            ...entry,
            'status': 'pending_export',
            'submittedRow': null,
            'rejectionReason': null,
            'decisionImpact': 'none_pending_only',
          },
        )
        .toList(growable: false);
    rawRows[0]
      ..['status'] = 'submitted_for_review'
      ..['submittedRow'] = {
        'caseId': '20260622_iwate_east_offshore_m30_hinet',
        'sourceType': 'hinet_jma_unified_catalog',
        'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
        'sourceVersionOrPageDate': '2026-06-26 authenticated page',
        'checkedAtUtc': '2026-06-26T06:00:00Z',
        'reviewer': 'reviewer-id',
        'originTimeJst': '2026-06-22T11:26:50',
        'latitude': 39.91,
        'longitude': 142.347,
        'depthKm': 42.4,
        'magnitude': 3.0,
        'region': 'Iwate east offshore',
        'rawRowText': '2026-06-22 11:26:50 39.91 142.347 42.4 M3.0',
      };
    rows['rows'] = rawRows;

    final rowsFile = File('${tempDir.path}/rows.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(rows)}\n',
      );
    final decisionsFile = _pendingDecisionsFile(tempDir);
    final report = buildHinetAuthenticatedExportReviewJson(
      rowsPath: rowsFile.path,
      decisionPath: decisionsFile.path,
    );
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['submittedForReviewCount'], 1);
    expect(summary['validSubmittedRowCount'], 1);
    expect(summary['decisionEvidenceReadyCount'], 1);
    expect(summary['acceptedDecisionCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final iwate = cases.singleWhere(
      (entry) => entry['caseId'] == '20260622_iwate_east_offshore_m30_hinet',
    );
    expect(iwate['submittedRowValid'], isTrue);
    expect(iwate['decisionEvidenceReady'], isTrue);
    final evidence = (iwate['evidenceCandidate'] as Map)
        .cast<String, Object?>();
    expect(evidence['type'], 'authenticated_hinet_export_row');
    expect(evidence['sourceType'], 'hinet_jma_unified_catalog');
    expect(evidence['reviewer'], 'reviewer-id');
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
