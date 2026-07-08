import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'source-estimation suite produces event and noise baselines',
    () async {
      final suite = SourceEstimationBenchmarkSuite.fromManifest(
        File('test/fixtures/source_estimation/baseline_suite.json'),
      );
      final outputDirectory = Directory(
        '.dart_tool/source_estimation_benchmark/cases',
      );
      final report = await SourceEstimationBatchRunner(
        suite: suite,
        workspaceRoot: Directory.current,
      ).run(perCaseOutputDirectory: outputDirectory);
      report.writeJson(
        File('.dart_tool/source_estimation_benchmark/${suite.suiteId}.json'),
      );
      final generatedMarkdown = File(
        '.dart_tool/source_estimation_benchmark/${suite.suiteId}.md',
      );
      report.writeMarkdown(generatedMarkdown);
      const updateBaseline = bool.fromEnvironment(
        'SOURCE_ESTIMATION_UPDATE_BASELINE',
      );
      if (updateBaseline) {
        report.writeMarkdown(
          File('docs/baselines/source_estimation_p0_suite.generated.md'),
        );
      }

      expect(report.cases, hasLength(3));
      expect(generatedMarkdown.readAsStringSync(), contains(suite.suiteId));
      expect(
        generatedMarkdown.readAsStringSync(),
        contains('weighted_centroid_baseline'),
      );
      expect(
        generatedMarkdown.readAsStringSync(),
        contains('Event Detection Summary'),
      );
      expect(
        report.detectionSummary.detectorId,
        NiedSourceEstimationDriver.sourceEventDetectorId,
      );
      expect(report.detectionSummary.catalogEventCaseCount, 2);
      expect(report.detectionSummary.excludedEventCaseCount, 1);
      expect(report.detectionSummary.eventCaseCount, 1);
      expect(report.detectionSummary.eventCasesWithCandidate, 1);
      expect(report.detectionSummary.eventCasesConfirmed, 1);
      expect(report.detectionSummary.detectionMissedCandidateCount, 0);
      expect(report.detectionSummary.detectionMissedEventCount, 0);
      expect(report.detectionSummary.noiseCaseCount, 1);
      expect(report.detectionSummary.noiseFrameCount, 41);
      expect(report.detectionSummary.noiseCandidateFrameCount, 0);
      expect(report.detectionSummary.noiseConfirmedFrameCount, 0);
      expect(report.detectionSummary.falseCandidateFrameRate, 0);
      expect(report.detectionSummary.falseConfirmedFrameRate, 0);
      expect(report.detectionSummary.medianCandidateDelaySeconds, 3);
      expect(report.detectionSummary.medianConfirmationDelaySeconds, 4);
      for (final method in report.summaries.values) {
        expect(method.eventCaseCount, 2);
        expect(method.eventCasesWithEstimates, 1);
        expect(method.missedEventCaseCount, 1);
        expect(method.confirmedEventCaseCount, 1);
        expect(method.confirmedEventCasesWithEstimates, 1);
        expect(method.sourceMissedConfirmedEventCount, 0);
        expect(method.noiseCaseCount, 1);
        expect(method.noiseFrameCount, 41);
        expect(method.noiseEstimateFrameCount, 0);
        expect(method.falseEstimateFrameRate, 0);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
