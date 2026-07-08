import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Iwate offshore reference replay emits diagnostic benchmark reports',
    () async {
      final replayCase = SourceEstimationReplayCase.fromManifest(
        File('test/fixtures/source_estimation/iwate_offshore_m34_ref.json'),
        workspaceRoot: Directory.current,
      );

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
      expect(detectionReport.requestedFrameCount, 151);
      expect(detectionReport.decodedFrameCount, 151);
      expect(replayCase.eventLabels.includeInDetectionMetrics, isFalse);
      expect(
        detectionReport.networkAssociationSummary.maxTriggeredStationCount,
        greaterThan(0),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
