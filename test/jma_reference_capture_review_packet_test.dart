import 'package:flutter_test/flutter_test.dart';

import '../tools/build_jma_reference_capture_review_packet.dart';

void main() {
  test('JMA reference capture review packet is manual-only', () {
    final report = buildJmaReferenceCaptureReviewPacketJson();

    expect(report['schemaVersion'], 'jma_reference_capture_review_packet_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 2);
    expect(summary['manualReviewRequiredCount'], 2);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['manifestMutationCount'], 0);
    expect(summary['captureAssociationClearedByPacketCount'], 0);
    expect(summary['finalCatalogTruthCount'], 0);
    expect(summary['localCandidateMatchCount'], 0);

    final packets = (report['packets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      packets.map((packet) => packet['eventId']),
      containsAll({
        '20260625_iwate_offshore_m46_jma_eqsc9',
        '20260626_yamanashi_central_west_m26_jma_equake5',
      }),
    );

    for (final packet in packets) {
      expect(packet['status'], 'pending_capture_association');
      expect(
        packet['truthQuality'],
        'jma_source_and_intensity_reference_pending_final_catalog',
      );
      expect(packet['localCaptureCandidates'], isEmpty);
      expect(packet['localFixtureCandidates'], isEmpty);
      expect(
        packet['associationTargetPath'],
        'docs/data/jma_reference_event_candidates.json',
      );
      expect(
        packet['requiredLocalFiles'],
        contains('manifest.json or replay_manifest.json'),
      );
      expect(packet['acceptedLocalRoots'], contains('tmp/captures'));
      expect(packet['reviewFields'], contains('captureDirectory'));
      expect(
        packet['validationCommand'],
        contains('validate_jma_reference_capture_association.ps1'),
      );
      expect(
        packet['dryRunCommand'],
        'dart run tools\\import_jma_reference_capture_package.dart '
        '--input <reviewed-capture-association.json> --dry-run',
      );
      expect(packet['manualReviewRequired'], isTrue);
      expect(packet['automaticClearance'], isFalse);
      expect(packet['manifestMutation'], isFalse);
      expect(packet['captureAssociationClearedByPacket'], isFalse);
      expect(packet['finalCatalogTruth'], isFalse);
    }

    final iwate = packets.singleWhere(
      (packet) => packet['eventId'] == '20260625_iwate_offshore_m46_jma_eqsc9',
    );
    expect(iwate['originTimeJst'], '2026-06-26T01:11:51+09:00');
    expect(iwate['maxShindo'], 3);

    final yamanashi = packets.singleWhere(
      (packet) =>
          packet['eventId'] ==
          '20260626_yamanashi_central_west_m26_jma_equake5',
    );
    expect(yamanashi['originTimeJst'], '2026-06-26T15:41:13+09:00');
    expect(yamanashi['maxShindo'], 1);
  });
}
