import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_jma_catalog_link_triage_packet.dart';

void main() {
  test('source JMA catalog-link triage validator runs prerequisites', () {
    final script = File(
      'tools/validate_source_jma_catalog_link_triage.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_metric_readiness_triage.ps1'));
    expect(script, contains('validate_jma_catalog_availability.ps1'));
    expect(script, contains('-UseExistingReadiness'));
    expect(
      script,
      contains('build_source_jma_catalog_link_triage_packet.dart'),
    );
    expect(script, contains('source_jma_catalog_link_triage_packet_test.dart'));
  });

  test('source JMA catalog-link triage stays manual-only', () {
    final report = buildSourceJmaCatalogLinkTriagePacketJson();

    expect(report['schemaVersion'], 'source_jma_catalog_link_triage_packet_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['fixtureMutationAllowed'], isFalse);
    expect(policy['assignsSplits'], isFalse);
    expect(policy['changesMetricEligibility'], isFalse);
    expect(policy['promotesCatalogTruth'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 3);
    expect(summary['expectedPacketCount'], 3);
    expect(summary['latestAvailableFinalCatalogYear'], 2023);
    expect(summary['targetEventYear'], 2026);
    expect(summary['externalCatalogNotYetAvailableCount'], 3);
    expect(summary['manualReviewRequiredCount'], 3);
    expect(summary['writeLinkAllowedCount'], 0);
    expect(summary['metricPromotionAllowedCount'], 0);
    expect(summary['splitAssignmentAllowedCount'], 0);
    expect(summary['fixtureMutationAllowedCount'], 0);
    expect(summary['missingReviewPacketCount'], 0);

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
        '20260622_kushiro_offshore_m30_jma',
        '20260624_fukushima_aizu_m32_jma_eq5',
        '20260625_iwate_offshore_m32_jma',
      }),
    );

    for (final packet in packets.values) {
      expect(packet['triageTier'], 'diagnostic_ready_blocked');
      expect(packet['metricBlockingReason'], 'review_jma_catalog_link');
      expect(packet['truthSource'], 'jma_source_and_intensity_information');
      expect(packet['eventYear'], 2026);
      expect(packet['latestAvailableFinalCatalogYear'], 2023);
      expect(
        packet['catalogPacketStatus'],
        'external_catalog_not_yet_available',
      );
      expect(
        packet['catalogEvidence'],
        'event_year_2026_after_latest_available_final_catalog_2023',
      );
      expect(packet['writeLinkAllowed'], isFalse);
      expect(packet['manualReviewRequired'], isTrue);
      expect(packet['splitAssignmentAllowed'], isFalse);
      expect(packet['metricPromotionAllowed'], isFalse);
      expect(packet['fixtureMutationAllowed'], isFalse);
      expect(packet['dryRunLinkCommand'], contains('link_jma_catalog.dart'));
      expect(packet['dryRunLinkCommand'], isNot(contains('--write')));
      expect(packet['writeLinkCommand'], contains('--write'));
    }

    final reportFile = File(
      '.dart_tool/source_jma_catalog_link_triage_packet/report.json',
    );
    if (reportFile.existsSync()) {
      final generated =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(generated['schemaVersion'], report['schemaVersion']);
    }
  });
}
