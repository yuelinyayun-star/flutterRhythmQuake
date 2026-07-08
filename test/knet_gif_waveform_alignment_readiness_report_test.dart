import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('K-NET/GIF alignment readiness report captures current overlap state', () {
    final reportFile = File(
      '.dart_tool/knet_gif_waveform_alignment_readiness/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing K-NET/GIF alignment readiness report. Run '
        '`dart run tools/build_knet_gif_waveform_alignment_readiness_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'knet_gif_waveform_alignment_readiness_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['captureFixtureCount'], 22);
    expect(summary['waveformCandidateCount'], 16);
    expect(summary['matchedCaptureWaveformCandidateCount'], 10);
    expect(summary['readyForAlignmentCount'], 0);
    expect(summary['candidateDirectoryUnconfirmedCount'], 10);
    expect(summary['waveformDownloadedNeedsFeatureBuildCount'], 0);
    expect(summary['captureOnlyNeedsWaveformCandidateCount'], 12);
    expect(summary['waveformOnlyNoLocalCaptureCount'], 6);

    final captureCases = {
      for (final raw in report['captureCases'] as List)
        (raw as Map)['caseId'] as String: raw.cast<String, Object?>(),
    };
    final iwate = captureCases['20260621_iwate_offshore_m33_eq8']!;
    expect(
      iwate['matchedWaveformEventId'],
      'iwate_offshore_20260621_m33_equake_ref',
    );
    expect(iwate['matchedNiedDirectoryId'], '20260621113200');
    expect(iwate['readiness'], 'candidate_directory_id_unconfirmed');
    expect(
      iwate['nextAction'],
      'confirm_nied_directory_id_then_download_waveforms',
    );

    final kushiro = captureCases['20260622_kushiro_offshore_m30_jma']!;
    expect(
      kushiro['matchedWaveformEventId'],
      'kushiro_offshore_20260622_m30_jma',
    );
    expect(kushiro['readiness'], 'candidate_directory_id_unconfirmed');

    final fukushimaAizu =
        captureCases['20260627_fukushima_aizu_m36_jma_equake17']!;
    expect(
      fukushimaAizu['matchedWaveformEventId'],
      'fukushima_aizu_20260627_m36_jma_equake17',
    );
    expect(fukushimaAizu['readiness'], 'candidate_directory_id_unconfirmed');
    expect(
      fukushimaAizu['nextAction'],
      'confirm_nied_directory_id_then_download_waveforms',
    );

    final yamanashi =
        captureCases['20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21']!;
    expect(
      yamanashi['matchedWaveformEventId'],
      'yamanashi_east_fuji_five_lakes_20260626_m56_jma_equake21',
    );
    expect(yamanashi['readiness'], 'candidate_directory_id_unconfirmed');

    final yamanashiM26 =
        captureCases['20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p']!;
    expect(
      yamanashiM26['matchedWaveformEventId'],
      'yamanashi_east_fuji_five_lakes_20260626_m26_jma_p2p',
    );
    expect(yamanashiM26['matchedNiedDirectoryId'], '20260626230400');
    expect(yamanashiM26['readiness'], 'candidate_directory_id_unconfirmed');

    final yamanashiM24 =
        captureCases['20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p']!;
    expect(
      yamanashiM24['matchedWaveformEventId'],
      'yamanashi_east_fuji_five_lakes_20260627_m24_jma_p2p',
    );
    expect(yamanashiM24['matchedNiedDirectoryId'], '20260627003300');
    expect(yamanashiM24['readiness'], 'candidate_directory_id_unconfirmed');

    final waveformOnlyCases = {
      for (final raw in report['waveformOnlyCases'] as List)
        (raw as Map)['eventId'] as String: raw.cast<String, Object?>(),
    };
    expect(waveformOnlyCases.keys, contains('kumamoto_20160416_m73'));
    expect(waveformOnlyCases.keys, contains('noto_peninsula_20240101_m76'));
    expect(waveformOnlyCases['kumamoto_20160416_m73']!['featureCount'], 2);
    expect(
      waveformOnlyCases.containsKey('iwate_offshore_20260621_m33_equake_ref'),
      isFalse,
    );
    expect(
      waveformOnlyCases['fukushima_offshore_20220316_m74']!['downloadStatus'],
      contains('failed:4'),
    );
  });
}
