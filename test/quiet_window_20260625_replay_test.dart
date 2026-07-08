import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '20260625 quiet live replay stays idle for detection and source estimation',
    () async {
      final workspaceRoot = Directory.current;
      final manifest = File(
        'test/fixtures/source_estimation/'
        'quiet_20260625_233535_jst_live.json',
      );
      final replayCase = SourceEstimationReplayCase.fromManifest(
        manifest,
        workspaceRoot: workspaceRoot,
      );
      if (!replayCase.captureDirectory.existsSync()) {
        markTestSkipped(
          'Missing replay capture: ${replayCase.captureDirectory.path}',
        );
        return;
      }

      final report = await SourceEstimationBenchmarkRunner(replayCase).run();
      report.writeJson(
        File(
          '.dart_tool/source_estimation_benchmark/${replayCase.caseId}.json',
        ),
      );

      expect(report.requestedFrameCount, 300);
      expect(report.decodedFrameCount, 300);
      expect(report.detectionSummary.hasCandidate, isFalse);
      expect(report.detectionSummary.hasConfirmed, isFalse);
      expect(report.detectionSummary.falseCandidateFrameCount, 0);
      expect(report.detectionSummary.falseConfirmedFrameCount, 0);
      for (final summary in report.summaries.values) {
        expect(summary.estimateCount, 0, reason: summary.methodId);
        expect(summary.falseEstimateFrameCount, 0, reason: summary.methodId);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
