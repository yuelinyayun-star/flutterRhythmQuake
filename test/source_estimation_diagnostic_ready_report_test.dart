import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_diagnostic_ready_report.dart';

void main() {
  test('diagnostic-ready validator builds report before testing', () {
    final script = File(
      'tools/validate_source_estimation_diagnostic_ready.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('build_source_estimation_diagnostic_ready_report.dart'),
    );
    expect(
      script,
      contains('source_estimation_diagnostic_ready_report_test.dart'),
    );
    expect(
      script.indexOf('build_source_estimation_diagnostic_ready_report.dart'),
      lessThan(
        script.indexOf('source_estimation_diagnostic_ready_report_test.dart'),
      ),
    );
  });

  test('diagnostic-ready report separates algorithm work from metrics', () {
    final report = buildSourceEstimationDiagnosticReadyReportJson();

    expect(report['schemaVersion'], 'source_estimation_diagnostic_ready_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(
      report['warnings'],
      contains(
        'optional_json_file_missing:'
        '.dart_tool/source_estimation_early_frame_report/matrix/'
        '20260621_iwate_offshore_m33_eq8.json',
      ),
    );

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['strictMetricEligible'], isFalse);
    expect(policy['productionCoordinateSwitchAllowed'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['diagnosticReadyCount'], 12);
    expect(summary['strictMetricEligibleCount'], 0);
    expect(summary['productionCoordinateSwitchAllowedCount'], 0);
    expect(summary['withEarlyFrameReportCount'], 9);
    expect(summary['withPromotionReportCount'], 9);
    expect(summary['withTimelineReportCount'], 6);
    expect(summary['candidateFrameCount'], 22);
    expect(summary['offlineMissedPositiveFrameCount'], 13);
    expect(summary['offlineFalseAcceptFrameCount'], 0);
    expect(summary['delayedRecoveredMissedPositiveFrameCount'], 3);
    expect((summary['diagnosticRoleCounts'] as Map).cast<String, Object?>(), {
      'false_recovery_guard': 1,
      'local_support_positive_guard': 1,
      'no_candidate_control': 8,
      'residual_candidate_region_guard': 2,
    });
    expect((summary['actionCounts'] as Map).cast<String, Object?>(), {
      'inspect_candidate_rejection_residuals': 2,
      'keep_as_no_candidate_control': 8,
      'keep_as_positive_residual_guard': 1,
      'study_delayed_confirmation_recovery': 1,
    });

    final cases = {
      for (final rawCase in report['cases'] as List)
        (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
    };
    expect(cases.length, 12);
    expect(cases.keys, contains('20260621_fukushima_offshore_m32_eq6'));
    expect(cases.keys, contains('20260622_kushiro_offshore_m30_jma'));
    expect(cases.keys, contains('20260622_tomakomai_south_offshore_m35_hinet'));
    expect(cases.keys, contains('20260625_iwate_offshore_m32_jma'));
    expect(
      cases.keys,
      contains('20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21'),
    );
    expect(cases.keys, contains('20260627_fukushima_aizu_m36_jma_equake17'));

    final fukushima = cases['20260621_fukushima_offshore_m32_eq6']!;
    expect(fukushima['diagnosticRole'], 'false_recovery_guard');
    expect(
      fukushima['recommendedNextDiagnosticAction'],
      'inspect_candidate_rejection_residuals',
    );
    final fukushimaPromotion = (fukushima['promotion'] as Map)
        .cast<String, Object?>();
    expect(fukushimaPromotion['acceptedCandidateFrames'], 0);
    expect(fukushimaPromotion['offlineMissedPositiveFrames'], 7);

    final kushiro = cases['20260622_kushiro_offshore_m30_jma']!;
    expect(kushiro['diagnosticRole'], 'residual_candidate_region_guard');
    expect(
      kushiro['recommendedNextDiagnosticAction'],
      'study_delayed_confirmation_recovery',
    );
    final kushiroPromotion = (kushiro['promotion'] as Map)
        .cast<String, Object?>();
    expect(kushiroPromotion['acceptedCandidateFrames'], 5);
    expect(kushiroPromotion['delayedRecoveredMissedPositiveFrames'], 3);
    final kushiroTimeline = (kushiro['timeline'] as Map)
        .cast<String, Object?>();
    expect(kushiroTimeline['confirmedImmediateCount'], 4);
    expect(kushiroTimeline['confirmedDelayedCount'], 1);
    expect(kushiroTimeline['coordinateSwitchAllowedCount'], 0);

    final tomakomai = cases['20260622_tomakomai_south_offshore_m35_hinet']!;
    expect(
      tomakomai['recommendedNextDiagnosticAction'],
      'keep_as_positive_residual_guard',
    );
    final tomakomaiPromotion = (tomakomai['promotion'] as Map)
        .cast<String, Object?>();
    expect(tomakomaiPromotion['acceptedCandidateFrames'], 3);
    expect(tomakomaiPromotion['offlineFalseAcceptFrames'], 0);

    final iwate = cases['20260625_iwate_offshore_m32_jma']!;
    expect(iwate['diagnosticRole'], 'local_support_positive_guard');
    expect(
      iwate['recommendedNextDiagnosticAction'],
      'inspect_candidate_rejection_residuals',
    );
    final iwateTimeline = (iwate['timeline'] as Map).cast<String, Object?>();
    expect(iwateTimeline['localSupportConfirmedCount'], 1);
    expect(iwateTimeline['localSupportConfirmedDelayedCount'], 1);

    for (final entry in cases.values) {
      expect(entry['datasetUseTier'], 'diagnostic_ready');
      expect(entry['readyForFrozenSplit'], isFalse);
      expect(entry['productionCoordinateSwitchAllowed'], isFalse);
    }

    final reportFile = File(
      '.dart_tool/source_estimation_diagnostic_ready/report.json',
    );
    if (reportFile.existsSync()) {
      final generated =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(generated['schemaVersion'], report['schemaVersion']);
    }
  });
}
