import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'event-detection suite reports candidate and confirmation metrics',
    () async {
      final suite = SourceEstimationBenchmarkSuite.fromManifest(
        File('test/fixtures/source_estimation/detection_suite.json'),
      );
      final outputDirectory = Directory(
        '.dart_tool/event_detection_benchmark/cases',
      );
      final report = await EventDetectionBatchRunner(
        suite: suite,
        workspaceRoot: Directory.current,
      ).run(perCaseOutputDirectory: outputDirectory);
      report.writeJson(
        File('.dart_tool/event_detection_benchmark/${suite.suiteId}.json'),
      );
      final generatedMarkdown = File(
        '.dart_tool/event_detection_benchmark/${suite.suiteId}.md',
      );
      report.writeMarkdown(generatedMarkdown);
      const updateBaseline = bool.fromEnvironment(
        'EVENT_DETECTION_UPDATE_BASELINE',
      );
      if (updateBaseline) {
        report.writeMarkdown(
          File('docs/baselines/event_detection_p0.generated.md'),
        );
      }

      expect(report.cases, hasLength(5));
      expect(report.summary.detectorId, 'legacy_shake_detection_adapter');
      expect(report.summary.catalogEventCaseCount, 4);
      expect(report.summary.excludedEventCaseCount, 2);
      expect(report.summary.eventCaseCount, 2);
      expect(report.summary.eventCasesWithCandidate, 2);
      expect(report.summary.eventCasesConfirmed, 1);
      expect(report.summary.detectionMissedCandidateCount, 0);
      expect(report.summary.detectionMissedEventCount, 1);
      expect(report.summary.noiseCaseCount, 1);
      expect(report.summary.noiseFrameCount, 41);
      expect(report.summary.noiseCandidateFrameCount, 0);
      expect(report.summary.noiseConfirmedFrameCount, 0);
      expect(report.summary.falseCandidateFrameRate, 0);
      expect(report.summary.falseConfirmedFrameRate, 0);
      expect(report.summary.medianCandidateDelaySeconds, 6);
      expect(report.summary.medianConfirmationDelaySeconds, 7);
      expect(
        report.shadowSummary.detectorId,
        'spatiotemporal_event_detector_v0',
      );
      expect(report.shadowSummary.catalogEventCaseCount, 4);
      expect(report.shadowSummary.excludedEventCaseCount, 2);
      expect(report.shadowSummary.eventCaseCount, 2);
      expect(report.shadowSummary.eventCasesWithCandidate, 2);
      expect(report.shadowSummary.eventCasesConfirmed, 2);
      expect(report.shadowSummary.detectionMissedCandidateCount, 0);
      expect(report.shadowSummary.detectionMissedEventCount, 0);
      expect(report.shadowSummary.noiseCandidateFrameCount, 0);
      expect(report.shadowSummary.noiseConfirmedFrameCount, 0);
      expect(report.shadowSummary.medianCandidateDelaySeconds, 8.5);
      expect(report.shadowSummary.medianConfirmationDelaySeconds, 9);
      expect(
        report.temporalBridgeSummary.detectorId,
        'spatiotemporal_event_detector_temporal_bridge_v0',
      );
      expect(report.temporalBridgeSummary.eventCasesWithCandidate, 2);
      expect(report.temporalBridgeSummary.eventCasesConfirmed, 2);
      expect(report.temporalBridgeSummary.detectionMissedCandidateCount, 0);
      expect(report.temporalBridgeSummary.detectionMissedEventCount, 0);
      expect(report.temporalBridgeSummary.noiseCandidateFrameCount, 0);
      expect(report.temporalBridgeSummary.noiseConfirmedFrameCount, 0);
      expect(report.temporalBridgeSummary.medianCandidateDelaySeconds, 7.5);
      expect(report.temporalBridgeSummary.medianConfirmationDelaySeconds, 9);
      expect(generatedMarkdown.readAsStringSync(), contains(suite.suiteId));

      final cases = {
        for (final report in report.cases) report.replayCase.caseId: report,
      };
      for (final caseReport in report.cases) {
        final triggers = caseReport.stationTriggerSummary;
        expect(
          triggers.uniqueTriggeredStationCount,
          greaterThanOrEqualTo(triggers.maxTriggeredStationCount),
        );
        expect(
          triggers.uniqueActivityAtLeast1StationCount,
          greaterThanOrEqualTo(triggers.uniqueActivityAtLeast2StationCount),
        );
        expect(
          triggers.uniqueActivityAtLeast2StationCount,
          greaterThanOrEqualTo(triggers.uniqueActivityAtLeast3StationCount),
        );
      }
      expect(cases['20260610_nara_m36']!.detectionSummary.hasConfirmed, isTrue);
      expect(
        cases['20260610_nara_m36']!.detectionSummary.maxActiveStationCount,
        282,
      );
      expect(cases['20260610_nara_m36']!.detectionSummary.maxShindo, 2);
      expect(
        cases['20260610_nara_m36']!.detectionSummary.maxStationDetectLevel,
        10,
      );
      expect(
        cases['20260610_nara_m36']!.detectionSummary.maxStationActivity,
        36,
      );
      expect(
        cases['20260610_nara_m36']!.shadowDetectionSummary.hasConfirmed,
        isTrue,
      );
      expect(
        cases['20260610_nara_m36']!
            .shadowDetectionSummary
            .firstConfirmedDelaySeconds,
        4,
      );
      expect(
        cases['20260610_nara_m36']!
            .networkAssociationSummary
            .temporalBridgeSweep
            .first
            .firstCandidateClusterDistanceToTruthKm,
        lessThan(20),
      );
      expect(
        cases['20260610_nara_m36']!.networkAssociationSummary.localObservability
            .firstWhere((entry) => entry.radiusKm == 50)
            .maxConnectedStationCount,
        24,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!.detectionSummary.hasCandidate,
        isFalse,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .detectionSummary
            .maxActiveStationCount,
        0,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .detectionSummary
            .maxStationDetectLevel,
        8,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!.detectionSummary.maxStationActivity,
        9.5,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!.shadowDetectionSummary.hasCandidate,
        isFalse,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .networkAssociationSummary
            .maxTriggeredStationCount,
        16,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .networkAssociationSummary
            .maxLargestComponentSize,
        3,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .networkAssociationSummary
            .localObservability
            .firstWhere((entry) => entry.radiusKm == 160)
            .maxConnectedStationCount,
        1,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .replayCase
            .eventLabels
            .includeInDetectionMetrics,
        isFalse,
      );
      final satsumaWideBridge = cases['20260620_satsuma_m26_d179']!
          .networkAssociationSummary
          .temporalBridgeSweep
          .firstWhere(
            (entry) =>
                entry.bridgeDistanceKm == 160 && entry.maxGapSeconds == 12,
          );
      expect(satsumaWideBridge.confirmedFrameCount, 33);
      expect(
        satsumaWideBridge.firstCandidateClusterDistanceToTruthKm,
        greaterThan(1000),
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .temporalBridgeDetectionSummary
            .firstCandidateDelaySeconds,
        38,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .temporalBridgeDetectionSummary
            .hasConfirmed,
        isFalse,
      );
      expect(
        cases['20260620_satsuma_m26_d179']!
            .networkAssociationSummary
            .radiusSweep
            .firstWhere((entry) => entry.radiusKm == 160)
            .confirmedFrameCount,
        3,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!.detectionSummary.hasCandidate,
        isFalse,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!
            .detectionSummary
            .maxActiveStationCount,
        0,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!
            .detectionSummary
            .maxStationDetectLevel,
        8,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!.detectionSummary.maxStationActivity,
        12.5,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!.shadowDetectionSummary.hasCandidate,
        isTrue,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!.shadowDetectionSummary.hasConfirmed,
        isFalse,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!
            .shadowDetectionSummary
            .firstCandidateDelaySeconds,
        45,
      );
      final kyotoWideBridge = cases['20260620_kyoto_s_m18_d12']!
          .networkAssociationSummary
          .temporalBridgeSweep
          .firstWhere(
            (entry) =>
                entry.bridgeDistanceKm == 160 && entry.maxGapSeconds == 12,
          );
      expect(kyotoWideBridge.firstCandidateDelaySeconds, 11);
      expect(
        kyotoWideBridge.firstCandidateClusterDistanceToTruthKm,
        greaterThan(1000),
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!
            .networkAssociationSummary
            .localObservability
            .firstWhere((entry) => entry.radiusKm == 160)
            .maxConnectedStationCount,
        2,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!.networkAssociationSummary.radiusSweep
            .firstWhere((entry) => entry.radiusKm == 160)
            .confirmedFrameCount,
        0,
      );
      expect(
        cases['20260620_kyoto_s_m18_d12']!.networkAssociationSummary.radiusSweep
            .firstWhere((entry) => entry.radiusKm == 240)
            .confirmedFrameCount,
        41,
      );
      final ibaraki = cases['20260620_ibaraki_offshore_m19_ref']!;
      expect(ibaraki.requestedFrameCount, 151);
      expect(ibaraki.decodedFrameCount, 151);
      expect(ibaraki.shadowDetectionSummary.hasConfirmed, isTrue);
      expect(ibaraki.shadowDetectionSummary.firstCandidateDelaySeconds, 14);
      expect(ibaraki.shadowDetectionSummary.firstConfirmedDelaySeconds, 14);
      expect(ibaraki.networkAssociationSummary.maxTriggeredStationCount, 18);
      expect(ibaraki.networkAssociationSummary.maxLargestComponentSize, 10);
      expect(ibaraki.replayCase.eventLabels.observableEvent, isTrue);
      expect(ibaraki.replayCase.eventLabels.detectableEvent, isTrue);
      expect(
        ibaraki.networkAssociationSummary.localObservability
            .firstWhere((entry) => entry.radiusKm == 100)
            .maxConnectedStationCount,
        8,
      );
      expect(
        ibaraki.networkAssociationSummary.localObservability
            .firstWhere((entry) => entry.radiusKm == 100)
            .confirmedEvidenceFrameCount,
        20,
      );
      final ibarakiConservativeBridge = ibaraki
          .networkAssociationSummary
          .temporalBridgeSweep
          .firstWhere(
            (entry) =>
                entry.bridgeDistanceKm == 120 && entry.maxGapSeconds == 4,
          );
      expect(ibarakiConservativeBridge.confirmedFrameCount, 41);
      expect(
        ibarakiConservativeBridge.firstCandidateClusterDistanceToTruthKm,
        lessThan(60),
      );
      expect(
        ibarakiConservativeBridge.firstCandidateStationIds,
        containsAll(['IBR003', 'IBR006', 'TCGH16']),
      );
      expect(
        cases['20260614_quiet_175544']!
            .detectionSummary
            .falseConfirmedFrameCount,
        0,
      );
      expect(
        cases['20260614_quiet_175544']!.detectionSummary.maxActiveStationCount,
        0,
      );
      expect(
        cases['20260614_quiet_175544']!.detectionSummary.maxStationDetectLevel,
        7,
      );
      expect(
        cases['20260614_quiet_175544']!.detectionSummary.maxStationActivity,
        12.5,
      );
      expect(
        cases['20260614_quiet_175544']!.shadowDetectionSummary.hasCandidate,
        isFalse,
      );
      expect(
        cases['20260614_quiet_175544']!.networkAssociationSummary.radiusSweep
            .firstWhere((entry) => entry.radiusKm == 240)
            .maxLargestComponentSize,
        2,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
