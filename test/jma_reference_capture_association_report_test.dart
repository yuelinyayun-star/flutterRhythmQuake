import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JMA capture-association script builds report before testing', () {
    final script = File(
      'tools/validate_jma_reference_capture_association.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('build_jma_reference_capture_association_report.dart'),
    );
    expect(script, contains('build_jma_reference_capture_review_packet.dart'));
    expect(
      script,
      contains('jma_reference_capture_association_report_test.dart'),
    );
    expect(script, contains('jma_reference_capture_review_packet_test.dart'));
    expect(script, contains('jma_reference_capture_package_import_test.dart'));
    expect(
      script.indexOf('build_jma_reference_capture_association_report.dart'),
      lessThan(
        script.indexOf('build_jma_reference_capture_review_packet.dart'),
      ),
    );
    expect(
      script.indexOf('build_jma_reference_capture_review_packet.dart'),
      lessThan(
        script.indexOf('jma_reference_capture_association_report_test.dart'),
      ),
    );
  });

  test('JMA reference candidates report capture association state', () {
    final reportFile = File(
      '.dart_tool/jma_reference_capture_association/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing JMA reference capture-association report. Run '
        '`dart run tools/build_jma_reference_capture_association_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'jma_reference_capture_association_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['warnings'], isEmpty);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['eventCount'], 7);
    expect(summary['pendingCaptureCount'], 2);
    expect(summary['captureAssociatedCount'], 5);
    expect(summary['captureAssociationMissingCount'], 2);
    expect(summary['localCaptureCandidateMatchCount'], 4);
    expect(summary['localFixtureCandidateMatchCount'], 0);
    expect(summary['captureDirectoryMissingCount'], 0);
    expect(summary['captureReplayManifestMissingCount'], 0);

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final iwateM46 = cases.singleWhere(
      (entry) => entry['eventId'] == '20260625_iwate_offshore_m46_jma_eqsc9',
    );
    expect(iwateM46['status'], 'pending_capture_association');
    expect(iwateM46['originTimeJst'], '2026-06-26T01:11:51+09:00');
    expect(iwateM46['captureDirectory'], isNull);
    expect(iwateM46['captureDirectoryExists'], isFalse);
    expect(iwateM46['replayManifestExists'], isFalse);
    expect(iwateM46['localCaptureCandidates'], isEmpty);
    expect(iwateM46['localFixtureCandidates'], isEmpty);

    final yamanashiM26 = cases.singleWhere(
      (entry) =>
          entry['eventId'] == '20260626_yamanashi_central_west_m26_jma_equake5',
    );
    expect(yamanashiM26['status'], 'pending_capture_association');
    expect(yamanashiM26['originTimeJst'], '2026-06-26T15:41:13+09:00');
    expect(yamanashiM26['captureDirectory'], isNull);
    expect(yamanashiM26['captureDirectoryExists'], isFalse);
    expect(yamanashiM26['replayManifestExists'], isFalse);
    expect(yamanashiM26['localCaptureCandidates'], isEmpty);
    expect(yamanashiM26['localFixtureCandidates'], isEmpty);

    final yamanashiM56 = cases.singleWhere(
      (entry) =>
          entry['eventId'] ==
          '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
    );
    expect(yamanashiM56['status'], 'capture_associated_pending_final_catalog');
    expect(yamanashiM56['originTimeJst'], '2026-06-26T22:29:02+09:00');
    expect(
      yamanashiM56['captureDirectory'],
      'tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m56_jma_p2p',
    );
    expect(yamanashiM56['captureDirectoryExists'], isTrue);
    expect(yamanashiM56['replayManifestExists'], isTrue);
    expect(yamanashiM56['localFixtureCandidates'], isEmpty);

    final yamanashiM33 = cases.singleWhere(
      (entry) =>
          entry['eventId'] ==
          '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
    );
    expect(yamanashiM33['status'], 'capture_associated_pending_final_catalog');
    expect(yamanashiM33['originTimeJst'], '2026-06-26T23:17:46+09:00');
    expect(
      yamanashiM33['captureDirectory'],
      'tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m33_jma_p2p',
    );
    expect(yamanashiM33['captureDirectoryExists'], isTrue);
    expect(yamanashiM33['replayManifestExists'], isTrue);
    expect(yamanashiM33['localCaptureCandidates'], isEmpty);
    expect(yamanashiM33['localFixtureCandidates'], isEmpty);

    final yamanashiM26P2p = cases.singleWhere(
      (entry) =>
          entry['eventId'] ==
          '20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p',
    );
    expect(
      yamanashiM26P2p['status'],
      'capture_associated_pending_final_catalog',
    );
    expect(yamanashiM26P2p['originTimeJst'], '2026-06-26T23:04:00+09:00');
    expect(yamanashiM26P2p['captureDirectoryExists'], isTrue);
    expect(yamanashiM26P2p['replayManifestExists'], isTrue);

    final yamanashiM24P2p = cases.singleWhere(
      (entry) =>
          entry['eventId'] ==
          '20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p',
    );
    expect(
      yamanashiM24P2p['status'],
      'capture_associated_pending_final_catalog',
    );
    expect(yamanashiM24P2p['originTimeJst'], '2026-06-27T00:33:00+09:00');
    expect(yamanashiM24P2p['captureDirectoryExists'], isTrue);
    expect(yamanashiM24P2p['replayManifestExists'], isTrue);

    final fukushimaAizuM36 = cases.singleWhere(
      (entry) => entry['eventId'] == '20260627_fukushima_aizu_m36_jma_equake17',
    );
    expect(
      fukushimaAizuM36['status'],
      'capture_associated_pending_final_catalog',
    );
    expect(fukushimaAizuM36['originTimeJst'], '2026-06-27T02:33:00+09:00');
    expect(
      fukushimaAizuM36['captureDirectory'],
      'tmp/captures/20260627_fukushima_aizu_m36_jma_equake17',
    );
    expect(fukushimaAizuM36['captureDirectoryExists'], isTrue);
    expect(fukushimaAizuM36['replayManifestExists'], isTrue);
  });
}
