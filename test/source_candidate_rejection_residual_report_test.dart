import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_candidate_rejection_residual_report.dart';

void main() {
  test('candidate rejection residual validator builds dependencies first', () {
    final script = File(
      'tools/validate_source_candidate_rejection_residual_report.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_candidate_promotion_matrix.ps1'));
    expect(script, contains('validate_source_candidate_region_timeline.ps1'));
    expect(script, contains('validate_source_estimation_diagnostic_ready.ps1'));
    expect(
      script,
      contains('build_source_candidate_rejection_residual_report.dart'),
    );
    expect(
      script,
      contains('source_candidate_rejection_residual_report_test.dart'),
    );
  });

  test(
    'candidate rejection residual report explains four core cases',
    () {
      final report = buildSourceCandidateRejectionResidualReportJson();

      expect(
        report['schemaVersion'],
        'source_candidate_rejection_residual_report_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['strictMetricEligible'], isFalse);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['coreCaseCount'], 4);
      expect(summary['inspectCandidateRejectionCaseCount'], 2);
      expect(summary['candidateFrameCount'], 22);
      expect(summary['inspectRejectedOfflineImprovedFrameCount'], 10);
      expect(summary['coreRejectedOfflineImprovedFrameCount'], 13);
      expect(summary['offlineFalseAcceptFrameCount'], 0);
      expect(summary['productionCoordinateSwitchAllowedCount'], 0);
      expect(summary['residualDelayedRecoveredFrameCount'], 3);
      expect(summary['localSupportConfirmedDelayedCaseCount'], 1);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };
      expect(cases.keys, containsAll(_expectedCoreCases));

      final fukushima = cases['20260621_fukushima_offshore_m32_eq6']!;
      expect(
        fukushima['caseDiagnosis'],
        'residual_gate_rejects_offline_positive_candidates',
      );
      expect(fukushima['rejectedOfflineImprovedFrameCount'], 7);
      expect((fukushima['promotion'] as Map)['acceptedCandidateFrames'], 0);
      expect((fukushima['timeline'] as Map)['confirmedDelayedCount'], 0);

      final kushiro = cases['20260622_kushiro_offshore_m30_jma']!;
      expect(
        kushiro['caseDiagnosis'],
        'residual_delayed_recovery_positive_guard',
      );
      expect(kushiro['rejectedOfflineImprovedFrameCount'], 3);
      expect(
        (kushiro['promotion'] as Map)['delayedRecoveredMissedPositiveFrames'],
        3,
      );

      final tomakomai = cases['20260622_tomakomai_south_offshore_m35_hinet']!;
      expect(tomakomai['caseDiagnosis'], 'residual_immediate_positive_guard');
      expect(tomakomai['rejectedOfflineImprovedFrameCount'], 0);
      expect((tomakomai['promotion'] as Map)['acceptedCandidateFrames'], 3);

      final iwate = cases['20260625_iwate_offshore_m32_jma']!;
      expect(
        iwate['caseDiagnosis'],
        'local_support_recovers_residual_rejection',
      );
      expect(iwate['rejectedOfflineImprovedFrameCount'], 3);
      expect(
        (iwate['timeline'] as Map)['localSupportConfirmedDelayedCount'],
        1,
      );
      expect((iwate['timeline'] as Map)['coordinateSwitchAllowedCount'], 0);

      final iwateFrames = (iwate['timelineDiagnostics'] as List)
          .cast<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false);
      expect(
        iwateFrames.any(
          (frame) =>
              frame['localSupportConfirmed'] == true &&
              frame['geometry'] == 'surrounded',
        ),
        isTrue,
      );

      final reportFile = File(
        '.dart_tool/source_candidate_rejection_residual_report/report.json',
      );
      if (reportFile.existsSync()) {
        final generated =
            jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
        expect(generated['schemaVersion'], report['schemaVersion']);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

const _expectedCoreCases = {
  '20260621_fukushima_offshore_m32_eq6',
  '20260622_kushiro_offshore_m30_jma',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260625_iwate_offshore_m32_jma',
};
