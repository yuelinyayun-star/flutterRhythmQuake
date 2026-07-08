import 'package:flutter_test/flutter_test.dart';

import '../tools/build_jma_final_catalog_review_packet.dart';

void main() {
  test('JMA final catalog review packet is manual-only while unavailable', () {
    final report = buildJmaFinalCatalogReviewPacketJson();

    expect(report['schemaVersion'], 'jma_final_catalog_review_packet_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 9);
    expect(summary['manualReviewRequiredCount'], 9);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['fixtureMutationCount'], 0);
    expect(summary['catalogTruthWriteCount'], 0);
    expect(summary['writeLinkAllowedCount'], 0);
    expect(summary['externalCatalogNotYetAvailableCount'], 9);

    final availability = (report['availability'] as Map)
        .cast<String, Object?>();
    expect(availability['latestAvailableFinalCatalogYear'], 2023);
    final evidence =
        (availability['latestAvailableFinalCatalogEvidence'] as Map)
            .cast<String, Object?>();
    expect(evidence['observedMissingYearLinks'], contains(2026));

    final packets = (report['packets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      packets.map((packet) => packet['caseId']),
      containsAll({
        '20260622_kushiro_offshore_m30_jma',
        '20260624_fukushima_aizu_m32_jma_eq5',
        '20260625_iwate_offshore_m32_jma',
        '20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p',
        '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
        '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        '20260627_fukushima_aizu_m36_jma_equake17',
        '20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p',
        '20260628_iwate_offshore_m41_jma',
      }),
    );

    for (final packet in packets) {
      expect(packet['truthSource'], 'jma_source_and_intensity_information');
      expect(packet['eventYear'], 2026);
      expect(packet['latestAvailableFinalCatalogYear'], 2023);
      expect(packet['coveredByAvailableCatalog'], isFalse);
      expect(packet['status'], 'external_catalog_not_yet_available');
      expect(
        packet['evidence'],
        'event_year_2026_after_latest_available_final_catalog_2023',
      );
      expect(packet['writeLinkAllowed'], isFalse);
      expect(packet['manualReviewRequired'], isTrue);
      expect(packet['automaticClearance'], isFalse);
      expect(packet['fixtureMutation'], isFalse);
      expect(packet['catalogTruthWrite'], isFalse);
      expect(packet['importCommand'], contains('import_jma_hypocenter.dart'));
      expect(packet['dryRunLinkCommand'], contains('link_jma_catalog.dart'));
      expect(packet['dryRunLinkCommand'], isNot(contains('--write')));
      expect(packet['writeLinkCommand'], contains('--write'));
      expect(packet['reviewFields'], contains('officialHypocenterFile'));
      expect(packet['reviewFields'], contains('sourceUrl'));
    }
  });
}
