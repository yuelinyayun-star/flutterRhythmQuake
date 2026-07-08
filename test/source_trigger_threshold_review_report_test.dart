import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'source-trigger threshold review regenerates quiet benchmarks first',
    () {
      final script = File(
        'tools/validate_source_trigger_threshold_review.ps1',
      ).readAsStringSync();

      expect(script, contains("\$ErrorActionPreference = 'Stop'"));
      expect(script, contains('source_estimation_batch_test.dart'));
      expect(script, contains('quiet_window_20260625_replay_test.dart'));
      expect(
        script,
        contains('build_source_trigger_threshold_review_report.dart'),
      );
      expect(
        script,
        contains('source_trigger_threshold_review_report_test.dart'),
      );
      expect(
        script.indexOf('source_estimation_batch_test.dart'),
        lessThan(
          script.indexOf('build_source_trigger_threshold_review_report'),
        ),
      );
    },
  );

  test(
    'Noto source-trigger review clears threshold after quiet windows pass',
    () {
      final reportFile = File(
        '.dart_tool/source_trigger_threshold_review/report.json',
      );
      if (!reportFile.existsSync()) {
        markTestSkipped(
          'Missing source-trigger threshold review report. Run '
          '`powershell -NoProfile -ExecutionPolicy Bypass -File '
          'tools\\validate_source_trigger_threshold_review.ps1`.',
        );
        return;
      }

      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['schemaVersion'], 'source_trigger_threshold_review_v2');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);
      expect(
        report['warnings'],
        contains('capture_received_at_unavailable_historical_fetch'),
      );

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['reviewCaseCount'], 1);
      expect(summary['captureProvenanceLocallyCompleteCount'], 1);
      expect(summary['historicalFetchCaptureCount'], 1);
      expect(summary['sourceTriggerMissedEventCount'], 0);
      expect(summary['quietWindowCount'], 2);
      expect(summary['quietWindowPassedCount'], 2);
      expect(summary['quietWindowDecodedFrameCount'], 341);
      expect(summary['quietWindowCandidateFrameCount'], 0);
      expect(summary['quietWindowConfirmedFrameCount'], 0);
      expect(summary['quietWindowFalseEstimateFrameCount'], 0);
      expect(summary['thresholdReviewClearedCount'], 1);
      expect(summary['noiseWindowValidationRequiredCount'], 0);
      expect(summary['physicalFusionProductionEnabledCount'], 0);

      final quietValidation = (report['quietWindowValidation'] as Map)
          .cast<String, Object?>();
      expect(quietValidation['passed'], isTrue);
      final quietWindows = (quietValidation['quietWindows'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(
        quietWindows.map((entry) => entry['caseId']),
        containsAll([
          '20260614_quiet_175544',
          'quiet_20260625_233535_jst_live',
        ]),
      );
      for (final quiet in quietWindows) {
        expect(quiet['candidateFrameCount'], 0);
        expect(quiet['confirmedFrameCount'], 0);
        expect(quiet['falseEstimateFrameCount'], 0);
        expect(quiet['passed'], isTrue);
      }

      final item = (report['case'] as Map).cast<String, Object?>();
      expect(item['caseId'], 'noto_m27_20260621_jma_eq5');
      expect(item['splitStatus'], 'validation_reference');
      expect(item['nextAction'], 'split_assignment_complete');
      expect(
        item['pendingConditions'],
        isNot(contains('review_source_trigger_threshold_effect')),
      );
      expect(
        item['pendingConditions'],
        isNot(contains('confirm_capture_provenance')),
      );
      expect(item['captureDirectorySource'], 'legacy_capture_directory');
      expect(
        item['captureDirectory'],
        'tmp/captures/noto_m27_20260621_210754_multilayer',
      );
      expect(item['captureDirectoryExists'], isTrue);
      expect(item['captureManifestExists'], isTrue);
      expect(item['captureProvenanceLocallyComplete'], isTrue);
      expect(item['receivedAtStatus'], 'unavailable_historical_fetch');
      expect(item['expectedGifCount'], 1208);
      expect(item['downloadedGifCount'], 1208);
      expect(item['failedGifCount'], 0);
      expect(item['manifestRecordCount'], 1208);
      expect(item['frameCount'], 151);
      expect(item['decodedFrameCount'], 151);
      expect(item['sourceTriggerMissedEvent'], isFalse);
      expect(item['triggeredFrameCount'], 32);
      expect(item['jmaOnlyFirstDelaySeconds'], 6.0);
      expect(item['jmaOnlyFirstErrorKm'], lessThan(10.0));
      expect(item['physicalFirstErrorDeltaKm'], greaterThan(0));
      expect(item['physicalFusionProductionEnabled'], isFalse);
      expect(item['noiseWindowValidationRequired'], isFalse);
      expect(item['thresholdReviewCleared'], isTrue);
      expect(
        item['limitations'],
        contains('source_trigger_threshold_requires_noise_window_validation'),
      );
    },
  );
}
