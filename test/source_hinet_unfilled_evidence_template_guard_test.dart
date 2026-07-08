import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_evidence_intake_worklist.dart';
import '../tools/build_source_hinet_unfilled_evidence_template_guard.dart';

void main() {
  test('unfilled evidence template guard rejects all generated templates', () {
    final report = buildSourceHinetUnfilledEvidenceTemplateGuardJson();

    expect(
      report['schemaVersion'],
      'source_hinet_unfilled_evidence_template_guard_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['guardOnly'], isTrue);
    expect(policy['executesImports'], isFalse);
    expect(policy['writesEvidenceLedger'], isFalse);
    expect(policy['writesDecisionLedger'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 3);
    expect(summary['authenticatedTemplateExistsCount'], 3);
    expect(summary['noRowTemplateExistsCount'], 3);
    expect(summary['authenticatedTemplateRejectedCount'], 3);
    expect(summary['noRowTemplateRejectedCount'], 3);
    expect(summary['credentialFieldPresentCount'], 0);
    expect(summary['accidentalImportableTemplateCount'], 0);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    for (final entry in cases) {
      expect(entry['authenticatedTemplateRejected'], isTrue);
      expect(entry['noRowTemplateRejected'], isTrue);
      expect(entry['accidentalImportableTemplate'], isFalse);
      expect(entry['authenticatedTemplateErrors'], isNotEmpty);
      expect(entry['noRowTemplateErrors'], isNotEmpty);
    }
  });

  test('guard fails if an unfilled template becomes importable', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_unfilled_template_guard_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final authTemplate = File('${tempDir.path}/auth.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_validAuthPayload())}\n',
      );
    final noRowTemplate = File('${tempDir.path}/no_row.json')
      ..writeAsStringSync(
        File(
          '.dart_tool/source_hinet_no_row_found_review/files/20260622_iwate_east_offshore_m30_hinet.no_row_found.json',
        ).readAsStringSync(),
      );
    final worklist = buildSourceHinetEvidenceIntakeWorklistJson();
    final cases = (worklist['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    cases[0]
      ..['authenticatedRowTemplateFile'] = authTemplate.path
      ..['noRowFindingTemplateFile'] = noRowTemplate.path;
    worklist['cases'] = [cases[0], ...cases.skip(1)];
    final worklistFile = File('${tempDir.path}/worklist.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(worklist)}\n',
      );

    final report = buildSourceHinetUnfilledEvidenceTemplateGuardJson(
      worklistPath: worklistFile.path,
    );
    expect(report['status'], 'fail');
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['accidentalImportableTemplateCount'], 1);
    final validation = (report['validation'] as Map).cast<String, Object?>();
    expect(
      validation['violations'],
      contains('unfilled_authenticated_template_importable'),
    );
  });
}

Map<String, Object?> _validAuthPayload() => {
  'caseId': '20260622_iwate_east_offshore_m30_hinet',
  'sourceType': 'hinet_jma_unified_catalog',
  'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
  'sourceVersionOrPageDate': '2026-06-27 authenticated page',
  'checkedAtUtc': '2026-06-27T01:30:00Z',
  'reviewer': 'manual-reviewer',
  'originTimeJst': '2026-06-22T11:26:50',
  'latitude': 39.91,
  'longitude': 142.347,
  'depthKm': 42.4,
  'magnitude': 3.0,
  'region': 'Iwate east offshore',
  'rawRowText': '2026-06-22 11:26:50 39.91 142.347 42.4 M3.0',
};
