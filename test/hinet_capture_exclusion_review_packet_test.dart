import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_capture_exclusion_review_packet.dart';

void main() {
  test('capture exclusion review packet is empty after exclusion approved', () {
    final report = buildHinetCaptureExclusionReviewPacketJson();

    expect(report['schemaVersion'], 'hinet_capture_exclusion_review_packet_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 0);
    expect(summary['manualReviewRequiredCount'], 0);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['ledgerMutationCount'], 0);
    expect(summary['readyAfterExclusionCount'], 0);
    expect(summary['missingGifArchiveCopyCount'], 0);

    final packets = (report['packets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(packets, isEmpty);
  });
}
