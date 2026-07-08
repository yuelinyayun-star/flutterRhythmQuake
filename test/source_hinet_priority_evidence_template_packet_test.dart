import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_priority_evidence_template_packet.dart';

void main() {
  test('source Hi-net priority evidence validator runs prerequisites', () {
    final script = File(
      'tools/validate_source_hinet_priority_evidence_templates.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_hinet_truth_quality_triage.ps1'));
    expect(script, contains('validate_hinet_authenticated_export_review.ps1'));
    expect(script, contains('-UseExistingExternalEvidenceTargets'));
    expect(
      script,
      contains('build_source_hinet_priority_evidence_template_packet.dart'),
    );
    expect(
      script,
      contains('source_hinet_priority_evidence_template_packet_test.dart'),
    );
  });

  test('priority evidence templates cover source Priority 1 only', () {
    final report = buildSourceHinetPriorityEvidenceTemplatePacketJson();

    expect(
      report['schemaVersion'],
      'source_hinet_priority_evidence_template_packet_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['manualTemplateOnly'], isTrue);
    expect(policy['writesDecisionLedger'], isFalse);
    expect(policy['submitsRows'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);
    expect(policy['credentialFieldsAllowed'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 0);
    expect(summary['expectedPacketCount'], 0);
    expect(summary['pendingExportCount'], 0);
    expect(summary['submittedForReviewCount'], 0);
    expect(summary['templateFileCount'], 0);
    expect(summary['missingTemplateFieldCaseCount'], 0);
    expect(summary['credentialFieldPresentCount'], 0);
    expect(summary['decisionEvidenceReadyCount'], 0);
    expect(summary['acceptedForConstrainedReferenceSplitCount'], 0);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['decisionLedgerWriteAllowedCount'], 0);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);

    final validation = (report['validation'] as Map).cast<String, Object?>();
    expect(validation['status'], 'pass');
    expect(validation['violations'], isEmpty);

    final packets = {
      for (final rawPacket in report['packets'] as List)
        (rawPacket as Map)['caseId'] as String: rawPacket
            .cast<String, Object?>(),
    };
    expect(packets.keys, isEmpty);

    final reportFile = File(
      '.dart_tool/source_hinet_priority_evidence_template_packet/report.json',
    );
    if (reportFile.existsSync()) {
      final generated =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(generated['schemaVersion'], report['schemaVersion']);
    }
  });
}
