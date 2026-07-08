import 'package:flutter_test/flutter_test.dart';

import '../tools/build_final_catalog_or_hinet_revision_review_packet.dart';

void main() {
  test('final catalog or Hi-net revision packet is manual-only', () {
    final report = buildFinalCatalogOrHinetRevisionReviewPacketJson();

    expect(
      report['schemaVersion'],
      'final_catalog_or_hinet_revision_review_packet_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 1);
    expect(summary['manualReviewRequiredCount'], 1);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['fixtureMutationCount'], 0);
    expect(summary['splitManifestMutationCount'], 0);
    expect(summary['truthPromotionCount'], 0);
    expect(summary['negativeAttemptOnlyCount'], 1);
    expect(summary['resolutionAllowedByPacketCount'], 0);

    final packets = (report['packets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(packets, hasLength(1));
    final packet = packets.single;
    expect(packet['caseId'], '20260621_iwate_offshore_m33_eq8');
    expect(packet['plannedUse'], 'offshore_reference_pool');
    expect(packet['splitStatus'], 'unassigned_reference');
    expect(
      packet['fixturePath'],
      'test/fixtures/source_estimation/iwate_offshore_m33_20260621_eq8.json',
    );
    expect(
      packet['truthSource'],
      'user_provided_equake_final_report_reference',
    );
    expect(packet['catalogTruthVerified'], isFalse);
    expect(packet['truthQuality'], 'reference_only');
    expect(packet['manualReviewRequired'], isTrue);
    expect(packet['automaticClearance'], isFalse);
    expect(packet['fixtureMutation'], isFalse);
    expect(packet['splitManifestMutation'], isFalse);
    expect(packet['truthPromotion'], isFalse);
    expect(packet['resolutionAllowedByPacket'], isFalse);

    final conditions = (packet['pendingConditions'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      conditions.map((condition) => condition['name']),
      contains('link_final_catalog_or_hinet_revision'),
    );

    final paths = (packet['requiredResolutionPaths'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      paths.map((entry) => entry['path']),
      containsAll([
        'versioned_jma_final_catalog_row',
        'authenticated_revised_hinet_or_jma_source_row',
      ]),
    );

    final attempts = (packet['negativeAttempts'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(attempts, hasLength(1));
    expect(
      attempts.single['attemptId'],
      '20260626_iwate_m33_eq8_final_catalog_or_hinet_revision_check',
    );
    expect(attempts.single['evidenceStrength'], 'negative_attempt_only');
    expect(attempts.single['automaticClearance'], isFalse);
  });
}
