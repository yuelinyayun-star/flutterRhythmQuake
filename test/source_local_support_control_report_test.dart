import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_local_support_control_report.dart';

void main() {
  test('local-support control validator depends on separation guard', () {
    final script = File(
      'tools/validate_source_local_support_control.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_local_support_separation.ps1'));
    expect(script, contains('build_source_local_support_control_report.dart'));
    expect(script, contains('source_local_support_control_report_test.dart'));
  });

  test(
    'local-support control report covers validation manifest cases',
    () {
      final report = buildSourceLocalSupportControlReportJson();

      expect(report['schemaVersion'], 'source_local_support_control_report_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 6);
      expect(summary['caseWithCandidateRegionCount'], 4);
      expect(summary['localSupportConfirmedCaseCount'], 1);
      expect(summary['unexpectedLocalSupportConfirmationCount'], 0);
      expect(summary['productionCoordinateSwitchAllowedCount'], 0);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };
      expect(cases.length, 6);
      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['diagnosis'],
        'local_support_control_clear',
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['diagnosis'],
        'residual_guard_no_local_support',
      );
      expect(
        cases['20260622_tomakomai_south_offshore_m35_hinet']!['diagnosis'],
        'residual_guard_no_local_support',
      );
      expect(
        cases['20260623_tokachi_southeast_offshore_m34_hinet']!['diagnosis'],
        'no_candidate_region_control_clear',
      );
      expect(
        cases['20260624_fukushima_aizu_m32_jma_eq5']!['diagnosis'],
        'no_candidate_region_control_clear',
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['diagnosis'],
        'expected_local_support_positive',
      );

      final confirmedFrames = cases.values.expand(
        (entry) => entry['localSupportConfirmedFrames'] as List,
      );
      expect(confirmedFrames.length, 1);

      final reportFile = File(
        '.dart_tool/source_local_support_control_report/report.json',
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
