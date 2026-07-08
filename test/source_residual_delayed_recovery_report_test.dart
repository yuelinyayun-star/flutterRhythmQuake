import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_residual_delayed_recovery_report.dart';

void main() {
  test(
    'residual delayed-recovery validator depends on local support controls',
    () {
      final script = File(
        'tools/validate_source_residual_delayed_recovery.ps1',
      ).readAsStringSync();

      expect(script, contains("\$ErrorActionPreference = 'Stop'"));
      expect(script, contains('validate_source_local_support_control.ps1'));
      expect(
        script,
        contains('build_source_residual_delayed_recovery_report.dart'),
      );
      expect(
        script,
        contains('source_residual_delayed_recovery_report_test.dart'),
      );
    },
  );

  test(
    'residual delayed-recovery separates Kushiro from Fukushima',
    () {
      final report = buildSourceResidualDelayedRecoveryReportJson();

      expect(
        report['schemaVersion'],
        'source_residual_delayed_recovery_report_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 3);
      expect(summary['delayedRecoveredPositiveFrameCount'], 3);
      expect(summary['falseRecoveryGuardDelayedRecoveredFrameCount'], 0);
      expect(summary['positiveGuardDelayedRecoveredFrameCount'], 3);
      expect(summary['immediatePositiveGuardAcceptedFrameCount'], 3);
      expect(summary['productionCoordinateSwitchAllowedCount'], 0);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };
      final fukushima = cases['20260621_fukushima_offshore_m32_eq6']!;
      expect(
        fukushima['caseDiagnosis'],
        'dual_regression_blocks_false_recovery',
      );
      expect(fukushima['delayedRecoveredPositiveFrameCount'], 0);
      expect(fukushima['dualRegressionRejectedPositiveFrameCount'], 7);

      final kushiro = cases['20260622_kushiro_offshore_m30_jma']!;
      expect(
        kushiro['caseDiagnosis'],
        'same_region_residual_recovery_after_initial_no_support',
      );
      expect(kushiro['delayedRecoveredPositiveFrameCount'], 3);
      expect(kushiro['dualRegressionRejectedPositiveFrameCount'], 0);
      expect(kushiro['residualConfirmedDelayedCount'], 1);

      final tomakomai = cases['20260622_tomakomai_south_offshore_m35_hinet']!;
      expect(
        tomakomai['caseDiagnosis'],
        'immediate_acceptance_by_dual_residual_support',
      );
      expect(tomakomai['acceptedPositiveFrameCount'], 3);
      expect(tomakomai['rejectedPositiveFrameCount'], 0);
      expect(tomakomai['confirmedImmediateCount'], 3);
      expect(tomakomai['dualRegressionRejectedPositiveFrameCount'], 0);

      final recovered = (kushiro['delayedRecoveredFrames'] as List)
          .cast<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false);
      expect(recovered.length, 3);
      expect(
        recovered.every(
          (frame) =>
              (frame['recoveryMechanism'] as Map)['status'] ==
              'same_region_residual_confirmation',
        ),
        isTrue,
      );
      expect(
        recovered.every((frame) => frame['dualResidualRegression'] == false),
        isTrue,
      );

      final accepted = (tomakomai['acceptedPositiveFrames'] as List)
          .cast<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false);
      expect(accepted.length, 3);
      expect(
        accepted.every(
          (frame) =>
              frame['rankSupportsCandidate'] == true &&
              frame['attenuationSupportsCandidate'] == true &&
              frame['dualResidualRegression'] == false,
        ),
        isTrue,
      );

      final reportFile = File(
        '.dart_tool/source_residual_delayed_recovery_report/report.json',
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
