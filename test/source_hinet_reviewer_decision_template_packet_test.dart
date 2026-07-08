import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_reviewer_decision_staging_report.dart';
import '../tools/build_source_hinet_reviewer_decision_template_packet.dart';
import '../tools/build_source_hinet_evidence_review_report.dart';

void main() {
  test('reviewer decision templates expose imported rows for review', () {
    final report = buildSourceHinetReviewerDecisionTemplatePacketJson();

    expect(
      report['schemaVersion'],
      'source_hinet_reviewer_decision_templates_v1',
    );
    expect(report['status'], 'pass');

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['manualTemplateOnly'], isTrue);
    expect(policy['writesDecisionLedger'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 3);
    expect(summary['reviewerDecisionEligibleCount'], 0);
    expect(summary['templateEmittedCount'], 0);
    expect(summary['blockedCount'], 3);
    expect(summary['decisionLedgerWriteAllowedCount'], 0);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);
  });

  test('reviewer decision templates are emitted for eligible cases only', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_templates_',
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
    cases[1]
      ..['combinedEvidenceStatus'] = 'authenticated_hinet_export_row_ready'
      ..['readyEvidenceTypes'] = ['authenticated_hinet_export_row'];
    evidenceReview['cases'] = cases;
    final evidenceFile = File('${tempDir.path}/evidence.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(evidenceReview)}\n',
      );
    final staging = buildSourceHinetReviewerDecisionStagingReportJson(
      evidenceReviewPath: evidenceFile.path,
      decisionPath: _pendingDecisionsFile(tempDir).path,
    );
    final stagingFile = File('${tempDir.path}/staging.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(staging)}\n',
      );

    final report = buildSourceHinetReviewerDecisionTemplatePacketJson(
      stagingPath: stagingFile.path,
      templateDirectory: '${tempDir.path}/files',
      writeTemplateFiles: true,
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['reviewerDecisionEligibleCount'], 2);
    expect(summary['templateEmittedCount'], 2);

    final templates = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .where((entry) => entry['templateEmitted'] == true)
        .toList(growable: false);
    expect(templates, hasLength(2));
    final templateFile = File(templates.first['templateFile'].toString());
    expect(templateFile.existsSync(), isTrue);
    final payload =
        jsonDecode(templateFile.readAsStringSync()) as Map<String, Object?>;
    expect(payload['caseId'], templates.first['caseId']);
    expect(payload['evidenceType'], 'authenticated_hinet_export_row');
    expect(payload['splitAssignmentAllowed'], isFalse);
    expect(payload['metricPromotionAllowed'], isFalse);
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
