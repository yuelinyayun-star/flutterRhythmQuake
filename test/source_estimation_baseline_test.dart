import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Nara replay produces the frozen source-estimation baseline',
    () async {
      final workspaceRoot = Directory.current;
      final manifest = File('test/fixtures/source_estimation/nara_m36.json');
      final captureOverride = const String.fromEnvironment(
        'SOURCE_ESTIMATION_CAPTURE_DIR',
      );
      final replayCase = SourceEstimationReplayCase.fromManifest(
        manifest,
        workspaceRoot: workspaceRoot,
        captureDirectoryOverride: captureOverride.isEmpty
            ? null
            : Directory(captureOverride),
      );
      if (!replayCase.captureDirectory.existsSync()) {
        markTestSkipped(
          'Missing replay capture: ${replayCase.captureDirectory.path}. '
          'Set SOURCE_ESTIMATION_CAPTURE_DIR to override it.',
        );
        return;
      }

      final report = await SourceEstimationBenchmarkRunner(replayCase).run();
      final output = File(
        '.dart_tool/source_estimation_benchmark/${replayCase.caseId}.json',
      );
      report.writeJson(output);

      expect(report.requestedFrameCount, 51);
      expect(report.decodedFrameCount, report.requestedFrameCount);
      expect(
        report
            .summaries[SourceEstimationBenchmarkRunner.weightedMethod]!
            .estimateCount,
        greaterThan(0),
      );
      expect(
        report
            .summaries[SourceEstimationBenchmarkRunner.hybridMethod]!
            .estimateCount,
        greaterThan(0),
      );
      expect(
        report
            .summaries[SourceEstimationBenchmarkRunner.scratchMethod]!
            .estimateCount,
        greaterThan(0),
      );
      if (SourceEstimationBenchmarkRunner.kotoho7JsReceiverReplayEnabled) {
        expect(
          report.summaries,
          contains(SourceEstimationBenchmarkRunner.kotoho7JsReceiverMethod),
        );
        expect(
          report
              .summaries[SourceEstimationBenchmarkRunner
                  .kotoho7JsReceiverMethod]!
              .estimateCount,
          greaterThan(0),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
