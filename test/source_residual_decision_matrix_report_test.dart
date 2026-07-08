import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_residual_decision_matrix_report.dart';

void main() {
  test('residual decision matrix validator runs prerequisite reports', () {
    final script = File(
      'tools/validate_source_residual_decision_matrix.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_residual_delayed_recovery.ps1'));
    expect(
      script,
      contains('build_source_residual_decision_matrix_report.dart'),
    );
    expect(
      script,
      contains('source_residual_decision_matrix_report_test.dart'),
    );
  });

  test(
    'residual decision matrix codifies diagnostic-only signatures',
    () {
      final report = buildSourceResidualDecisionMatrixReportJson();

      expect(report['schemaVersion'], 'source_residual_decision_matrix_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['rowCount'], 5);
      expect(summary['passedRowCount'], 5);
      expect(summary['failedRowCount'], 0);
      expect(summary['manifestCaseCount'], 6);
      expect(summary['manifestCandidateRegionCaseCount'], 4);
      expect(summary['delayedRecoveredPositiveFrameCount'], 3);
      expect(summary['localSupportConfirmedCaseCount'], 1);
      expect(summary['unexpectedLocalSupportConfirmationCount'], 0);
      expect(summary['productionCoordinateSwitchAllowedCount'], 0);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final rows = {
        for (final rawRow in report['rows'] as List)
          (rawRow as Map)['signature'] as String: rawRow
              .cast<String, Object?>(),
      };
      expect(
        rows.keys,
        containsAll({
          'immediate_accept',
          'delayed_same_region_recovery',
          'false_recovery_reject',
          'local_support_delayed_confirmation',
          'no_candidate_region_control',
        }),
      );
      expect(rows.values.every((entry) => entry['status'] == 'pass'), isTrue);

      final tomakomaiEvidence = (rows['immediate_accept']!['evidence'] as Map)
          .cast<String, Object?>();
      expect(tomakomaiEvidence['acceptedPositiveFrameCount'], 3);
      expect(tomakomaiEvidence['confirmedImmediateCount'], 3);
      expect(tomakomaiEvidence['rejectedPositiveFrameCount'], 0);

      final kushiroEvidence =
          (rows['delayed_same_region_recovery']!['evidence'] as Map)
              .cast<String, Object?>();
      expect(kushiroEvidence['delayedRecoveredPositiveFrameCount'], 3);
      expect(kushiroEvidence['residualConfirmedDelayedCount'], 1);
      expect(kushiroEvidence['dualRegressionRejectedPositiveFrameCount'], 0);

      final fukushimaEvidence =
          (rows['false_recovery_reject']!['evidence'] as Map)
              .cast<String, Object?>();
      expect(fukushimaEvidence['delayedRecoveredPositiveFrameCount'], 0);
      expect(fukushimaEvidence['dualRegressionRejectedPositiveFrameCount'], 7);

      final iwateEvidence =
          (rows['local_support_delayed_confirmation']!['evidence'] as Map)
              .cast<String, Object?>();
      expect(iwateEvidence['localSupportConfirmedCount'], 1);
      expect(iwateEvidence['confirmedDelayedCount'], 1);
      expect(iwateEvidence['expectedResidualConfirmedDelayedCount'], 0);

      final controlEvidence =
          (rows['no_candidate_region_control']!['evidence'] as Map)
              .cast<String, Object?>();
      expect(controlEvidence['controlCaseCount'], 2);
      expect(controlEvidence['productionCoordinateSwitchAllowedCount'], 0);
      final controlCases = (controlEvidence['cases'] as List).cast<Map>();
      expect(controlCases.every((entry) => entry['frameCount'] == 0), isTrue);

      final reportFile = File(
        '.dart_tool/source_residual_decision_matrix/report.json',
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
