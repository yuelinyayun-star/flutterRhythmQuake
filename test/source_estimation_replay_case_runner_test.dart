import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'run a source-estimation replay case from dart-define',
    () async {
      const casePath = String.fromEnvironment('SOURCE_ESTIMATION_CASE');
      if (casePath.isEmpty) {
        markTestSkipped('Set SOURCE_ESTIMATION_CASE to a replay fixture path.');
        return;
      }

      final replayCase = SourceEstimationReplayCase.fromManifest(
        File(casePath),
        workspaceRoot: Directory.current,
      );
      if (!replayCase.captureDirectory.existsSync()) {
        fail('Missing local capture: ${replayCase.captureDirectory.path}');
      }

      final sourceReport = await SourceEstimationBenchmarkRunner(
        replayCase,
      ).run();
      sourceReport.writeJson(
        File(
          '.dart_tool/source_estimation_benchmark/'
          '${replayCase.caseId}.reference.json',
        ),
      );

      final detectionReport = await EventDetectionBenchmarkRunner(
        replayCase,
      ).run();
      detectionReport.writeJson(
        File(
          '.dart_tool/event_detection_benchmark/'
          '${replayCase.caseId}.reference.json',
        ),
      );

      expect(sourceReport.requestedFrameCount, greaterThan(0));
      expect(sourceReport.decodedFrameCount, sourceReport.requestedFrameCount);
      expect(
        detectionReport.requestedFrameCount,
        sourceReport.requestedFrameCount,
      );
      expect(
        detectionReport.decodedFrameCount,
        detectionReport.requestedFrameCount,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
