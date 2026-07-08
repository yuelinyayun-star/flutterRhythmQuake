import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_candidate_region_four_case_report.dart';

void main() {
  test('four-case validator rebuilds prerequisite guard reports', () {
    final script = File(
      'tools/validate_source_candidate_region_four_case.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('validate_source_residual_delayed_recovery.ps1'),
    );
    expect(script, contains('validate_source_local_support_separation.ps1'));
    expect(
      script,
      contains('build_source_candidate_region_four_case_report.dart'),
    );
    expect(script, contains('source_candidate_region_four_case_report_test'));
  });

  test('four-case report locks the current candidate-region guard roles', () {
    final report = buildSourceCandidateRegionFourCaseReportJson();

    expect(
      report['schemaVersion'],
      'source_candidate_region_four_case_report_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['productionCoordinateSwitchAllowed'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 4);
    expect(summary['falseRecoveryBlockedCount'], 1);
    expect(summary['residualDelayedPositiveCount'], 1);
    expect(summary['residualImmediatePositiveCount'], 1);
    expect(summary['localSupportDelayedPositiveCount'], 1);
    expect(summary['productionCoordinateSwitchAllowedCount'], 0);

    final validation = (report['validation'] as Map).cast<String, Object?>();
    expect(validation['status'], 'pass');
    expect(validation['violations'], isEmpty);

    final cases = {
      for (final rawCase in report['cases'] as List)
        (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
    };

    expect(
      cases['20260621_fukushima_offshore_m32_eq6']!['actualOutcome'],
      'blocked_by_dual_residual_and_local_growth',
    );
    expect(
      cases['20260621_fukushima_offshore_m32_eq6']![
          'localSupportConfirmedCount'],
      0,
    );
    expect(
      cases['20260622_kushiro_offshore_m30_jma']!['actualOutcome'],
      'same_region_residual_delayed_confirmation',
    );
    expect(
      cases['20260622_kushiro_offshore_m30_jma']![
          'delayedRecoveredPositiveFrameCount'],
      3,
    );
    expect(
      cases['20260622_tomakomai_south_offshore_m35_hinet']!['actualOutcome'],
      'dual_residual_immediate_confirmation',
    );
    expect(
      cases['20260622_tomakomai_south_offshore_m35_hinet']![
          'acceptedPositiveFrameCount'],
      3,
    );
    expect(
      cases['20260625_iwate_offshore_m32_jma']!['actualOutcome'],
      'local_support_delayed_confirmation',
    );
    expect(
      cases['20260625_iwate_offshore_m32_jma']![
          'localSupportConfirmedCount'],
      1,
    );

    final reportFile = File(
      '.dart_tool/source_candidate_region_four_case/report.json',
    );
    if (reportFile.existsSync()) {
      final generated =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(generated['schemaVersion'], report['schemaVersion']);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
