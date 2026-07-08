import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Iwate east offshore reference replay emits diagnostic reports',
    () async {
      final replayCase = SourceEstimationReplayCase.fromManifest(
        File(
          'test/fixtures/source_estimation/'
          'iwate_east_offshore_m30_20260622_hinet.json',
        ),
        workspaceRoot: Directory.current,
      );
      if (!replayCase.captureDirectory.existsSync()) {
        markTestSkipped(
          'Missing local capture: ${replayCase.captureDirectory.path}',
        );
        return;
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

      expect(sourceReport.requestedFrameCount, 151);
      expect(sourceReport.decodedFrameCount, 151);
      expect(
        sourceReport.summaries.keys,
        contains(SourceEstimationBenchmarkRunner.kotoho7RawIdDiagnosticMethod),
      );
      expect(
        sourceReport.frames.any(
          (frame) => frame.methods.containsKey(
            SourceEstimationBenchmarkRunner.kotoho7RawIdDiagnosticMethod,
          ),
        ),
        isTrue,
      );
      expect(detectionReport.requestedFrameCount, 151);
      expect(detectionReport.decodedFrameCount, 151);
      expect(replayCase.eventLabels.catalogTruthVerified, isFalse);
      expect(replayCase.eventLabels.includeInDetectionMetrics, isFalse);
      expect(
        detectionReport.stationTriggerSummary.maxTriggeredStationCount,
        greaterThan(0),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
