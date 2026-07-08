import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_truth_quality_triage_packet.dart';

void main() {
  test('source Hi-net truth-quality triage validator runs prerequisites', () {
    final script = File(
      'tools/validate_source_hinet_truth_quality_triage.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_metric_readiness_triage.ps1'));
    expect(script, contains('validate_hinet_truth_quality_review_queue.ps1'));
    expect(
      script,
      contains('build_source_hinet_truth_quality_triage_packet.dart'),
    );
    expect(
      script,
      contains('source_hinet_truth_quality_triage_packet_test.dart'),
    );
  });

  test('source Hi-net truth-quality triage remains manual-only', () {
    final report = buildSourceHinetTruthQualityTriagePacketJson();

    expect(
      report['schemaVersion'],
      'source_hinet_truth_quality_triage_packet_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['fixtureMutationAllowed'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);
    expect(policy['acceptsTruthQuality'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 1);
    expect(summary['expectedPacketCount'], 1);
    expect(summary['diagnosticReadyBlockedCount'], 0);
    expect(summary['metadataOnlyOrIncompleteCount'], 1);
    expect(summary['priorityExternalEvidenceReviewCount'], 0);
    expect(summary['catalogFlagMismatchBlockedCount'], 0);
    expect(summary['captureRepairBlockedCount'], 1);
    expect(summary['manualReviewRequiredCount'], 1);
    expect(summary['truthQualityAcceptanceAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);
    expect(summary['fixtureMutationAllowedCount'], 0);
    expect(summary['queueMappingMissingCount'], 0);

    final validation = (report['validation'] as Map).cast<String, Object?>();
    expect(validation['status'], 'pass');
    expect(validation['violations'], isEmpty);

    final packets = {
      for (final rawPacket in report['packets'] as List)
        (rawPacket as Map)['caseId'] as String: rawPacket
            .cast<String, Object?>(),
    };
    expect(
      packets.keys,
      containsAll({
        '20260620_iwate_offshore_m34_ref',
      }),
    );

    final priorityCases = packets.values
        .where(
          (packet) =>
              packet['queueNextAction'] ==
              'collect_external_hinet_or_jma_revised_evidence',
        )
        .map((packet) => packet['caseId'])
        .toSet();
    expect(priorityCases, isEmpty);

    final mismatchCases = packets.values
        .where(
          (packet) =>
              packet['queueNextAction'] ==
              'resolve_catalog_truth_flag_mismatch',
        )
        .map((packet) => packet['caseId'])
        .toSet();
    expect(mismatchCases, isEmpty);

    final repairCase = packets['20260620_iwate_offshore_m34_ref']!;
    expect(repairCase['triageTier'], 'metadata_only_or_incomplete');
    expect(repairCase['queueNextAction'], 'repair_capture_before_review');
    expect(
      repairCase['requiredEvidence'],
      contains('complete_or_exclude_local_capture_package'),
    );

    for (final packet in packets.values) {
      expect(packet['manualReviewRequired'], isTrue);
      expect(packet['truthQualityAcceptanceAllowed'], isFalse);
      expect(packet['splitAssignmentAllowed'], isFalse);
      expect(packet['metricPromotionAllowed'], isFalse);
      expect(packet['fixtureMutationAllowed'], isFalse);
      expect(
        packet['requiredEvidence'],
        contains('reviewer_and_review_timestamp'),
      );
    }

    final reportFile = File(
      '.dart_tool/source_hinet_truth_quality_triage_packet/report.json',
    );
    if (reportFile.existsSync()) {
      final generated =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(generated['schemaVersion'], report['schemaVersion']);
    }
  });
}
