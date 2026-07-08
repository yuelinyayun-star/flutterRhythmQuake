import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_authenticated_export_review_packet.dart';

void main() {
  test('authenticated export review packet is manual-only intake summary', () {
    final report = buildHinetAuthenticatedExportReviewPacketJson();

    expect(
      report['schemaVersion'],
      'hinet_authenticated_export_review_packet_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['packetCount'], 0);
    expect(summary['manualReviewRequiredCount'], 0);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['ledgerMutationCount'], 0);
    expect(summary['submittedForReviewCount'], 0);
    expect(summary['decisionEvidenceReadyCount'], 0);
    expect(summary['credentialFieldCount'], 0);

    final packets = (report['packets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(packets, isEmpty);
    for (final packet in packets) {
      expect(packet['rowStatus'], 'pending_export');
      expect(packet['preferredSourceType'], 'hinet_jma_unified_catalog');
      expect(packet['fallbackSourceType'], 'hinet_preliminary_catalog');
      expect(packet['preferredSourceUrl'], contains('hinetwww11.bosai.go.jp'));
      expect(packet['fallbackSourceUrl'], contains('hinetwww11.bosai.go.jp'));
      expect(packet['queryWindowJst'], contains('..'));
      expect(packet['templateFile'], contains('.dart_tool/'));
      expect(
        packet['templateFile'],
        contains('hinet_authenticated_export_row_templates/files'),
      );
      expect(
        packet['templateFields'],
        containsAll([
          'caseId',
          'sourceType',
          'sourceUrl',
          'sourceVersionOrPageDate',
          'checkedAtUtc',
          'reviewer',
          'originTimeJst',
          'latitude',
          'longitude',
          'depthKm',
          'magnitude',
          'region',
          'rawRowText',
        ]),
      );
      expect(
        packet['requiredReviewFields'],
        containsAll([
          'sourceVersionOrPageDate',
          'checkedAtUtc',
          'reviewer',
          'rawRowText',
        ]),
      );
      expect(
        packet['importDryRunCommand'],
        contains('import_hinet_authenticated_export_row.dart'),
      );
      expect(packet['importDryRunCommand'], contains('--dry-run'));
      expect(packet['manualReviewRequired'], isTrue);
      expect(packet['automaticClearance'], isFalse);
      expect(packet['ledgerMutation'], isFalse);
      expect(packet['blockerClearedByPacket'], isFalse);
    }
  });
}
