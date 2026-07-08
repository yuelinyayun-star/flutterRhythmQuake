import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_like_replay_leadtime_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PLUM-like replay lead-time report uses real frames only',
    () async {
      final report = await buildPlumLikeReplayLeadtimeReportJson();

      expect(report['schemaVersion'], 'plum_like_replay_leadtime_report_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['sourceIndependent'], isTrue);
      expect(policy['usesSourceLatitudeLongitudeDepthMagnitude'], isFalse);
      expect(policy['temporalSemantics'], contains('real replay frames'));
      expect(policy['surfaceInputOnly'], isTrue);
      expect(policy['productionUiConnected'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 6);
      expect((summary['decodedFrameCount'] as int), greaterThan(0));
      expect((summary['stationFrameCount'] as int), greaterThan(0));
      final skippedCases = (report['skippedCases'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(skippedCases, hasLength(1));
      expect(
        skippedCases.single['caseId'],
        '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
      );
      expect(skippedCases.single['reason'], 'capture_manifest_failed_gifs');
      expect(skippedCases.single['failedGifCount'], 16);

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(
        thresholds.keys,
        containsAll(['shindo1', 'shindo2', 'shindo3', 'shindo4', 'shindo5-']),
      );

      final markdown = plumLikeReplayLeadtimeMarkdown(report);
      expect(markdown, contains('PLUM-Like Replay Lead-Time Diagnostic'));
      expect(markdown, contains('Input layer: `jma_s`'));
      expect(markdown, contains('does not use source coordinates'));
      expect(markdown, contains('r30_d0.50_local_contrast_r20_w3.0'));

      final output = File('.dart_tool/plum_like_replay_leadtime/report.json')
        ..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/plum_like_replay_leadtime.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
