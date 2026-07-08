import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_evidence_intake_worklist.dart';

void main() {
  test(
    'evidence intake worklist keeps accepted cases waiting for split gate',
    () {
      final report = buildSourceHinetEvidenceIntakeWorklistJson();

      expect(
        report['schemaVersion'],
        'source_hinet_evidence_intake_worklist_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['worklistOnly'], isTrue);
      expect(policy['writesEvidenceLedger'], isFalse);
      expect(policy['writesDecisionLedger'], isFalse);
      expect(policy['acceptsTruthQuality'], isFalse);
      expect(policy['assignsSplits'], isFalse);
      expect(policy['changesMetricEligibility'], isFalse);
      expect(policy['credentialFieldsAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 3);
      expect(summary['authenticatedTemplateReadyCount'], 0);
      expect(summary['noRowTemplateReadyCount'], 0);
      expect(summary['authenticatedEvidenceReadyCount'], 0);
      expect(summary['noRowEvidenceReadyCount'], 0);
      expect(summary['reviewerDecisionTemplateEmittedCount'], 0);
      expect(summary['acceptedForConstrainedReferenceSplitCount'], 3);
      expect(summary['writesEvidenceLedgerCount'], 0);
      expect(summary['writesDecisionLedgerCount'], 0);
      expect(summary['truthQualityAcceptanceAllowedCount'], 0);
      expect(summary['metricPromotionAllowedCount'], 0);
      expect(summary['splitAssignmentAllowedCount'], 0);

      final nextActionCounts = (summary['nextActionCounts'] as Map)
          .cast<String, Object?>();
      expect(
        nextActionCounts['accepted_constrained_reference_waiting_split_gate'],
        3,
      );
      expect(nextActionCounts['fill_reviewer_decision_template'], isNull);
      expect(
        nextActionCounts['fill_authenticated_row_or_no_row_finding'],
        isNull,
      );

      final cases = (report['cases'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      final acceptedCases = cases
          .where(
            (entry) => entry['acceptedForConstrainedReferenceSplit'] == true,
          )
          .toList(growable: false);
      expect(acceptedCases, hasLength(3));
      for (final entry in acceptedCases) {
        expect(
          entry['nextAction'],
          'accepted_constrained_reference_waiting_split_gate',
        );
        expect(entry['decisionStatus'], 'accepted_constrained_reference');
        expect(entry['reviewerDecisionTemplateEmitted'], isFalse);
        expect(entry['reviewerDecisionTemplateFile'], isNull);
        expect(entry['reviewerDecisionImportDryRunCommand'], isNull);
        expect(entry['reviewerDecisionImportCommand'], isNull);
        expect(entry['truthQualityAcceptanceAllowed'], isFalse);
        expect(entry['splitAssignmentAllowed'], isFalse);
      }

      for (final entry in cases) {
        expect(entry['manualReviewRequired'], isFalse);
        expect(entry['truthQualityAcceptanceAllowed'], isFalse);
        expect(entry['splitAssignmentAllowed'], isFalse);
      }
    },
  );

  test('evidence intake worklist moves to staging after evidence ready', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_evidence_intake_worklist_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final priorityEvidence =
        jsonDecode(
              File(
                '.dart_tool/source_hinet_priority_evidence_template_packet/report.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final priorityPackets = (priorityEvidence['packets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    priorityPackets[0]
      ..['decisionStatus'] = 'pending_manual_review'
      ..['acceptedForConstrainedReferenceSplit'] = false;
    priorityEvidence['packets'] = priorityPackets;
    final priorityFile = File('${tempDir.path}/priority.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(priorityEvidence)}\n',
      );

    final evidenceReview =
        jsonDecode(
              File(
                '.dart_tool/source_hinet_evidence_review/report.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final cases = (evidenceReview['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    cases[0]
      ..['authenticatedEvidenceReady'] = true
      ..['decisionStatus'] = 'pending_manual_review'
      ..['acceptedForConstrainedReferenceSplit'] = false
      ..['combinedEvidenceStatus'] = 'authenticated_hinet_export_row_ready'
      ..['readyEvidenceTypes'] = ['authenticated_hinet_export_row'];
    evidenceReview['cases'] = cases;
    final evidenceFile = File('${tempDir.path}/evidence.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(evidenceReview)}\n',
      );

    final reviewerDecisionTemplates = {
      'schemaVersion': 'source_hinet_reviewer_decision_templates_v1',
      'status': 'pass',
      'cases': [
        for (final entry in cases)
          {
            'caseId': entry['caseId'],
            'templateEmitted': false,
            'templateFile': null,
          },
      ],
    };
    final reviewerTemplatesFile = File('${tempDir.path}/reviewer.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(reviewerDecisionTemplates)}\n',
      );

    final report = buildSourceHinetEvidenceIntakeWorklistJson(
      priorityEvidencePath: priorityFile.path,
      evidenceReviewPath: evidenceFile.path,
      reviewerDecisionTemplatesPath: reviewerTemplatesFile.path,
    );
    final worklistCases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final ready = worklistCases.firstWhere(
      (entry) => entry['authenticatedEvidenceReady'] == true,
    );
    expect(ready['nextAction'], 'rerun_reviewer_decision_staging');
  });
}
