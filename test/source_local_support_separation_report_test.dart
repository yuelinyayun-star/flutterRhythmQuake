import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_local_support_separation_report.dart';

void main() {
  test(
    'local-support separation validator rebuilds reference inputs first',
    () {
      final script = File(
        'tools/validate_source_local_support_separation.ps1',
      ).readAsStringSync();

      expect(script, contains("\$ErrorActionPreference = 'Stop'"));
      expect(script, contains('fukushima_offshore_reference_replay_test.dart'));
      expect(script, contains('iwate_offshore_m32_reference_replay_test.dart'));
      expect(
        script,
        contains('validate_source_candidate_rejection_residual_report.ps1'),
      );
      expect(
        script,
        contains('build_source_local_support_separation_report.dart'),
      );
      expect(
        script,
        contains('source_local_support_separation_report_test.dart'),
      );
    },
  );

  test(
    'local-support separation blocks Fukushima and keeps Iwate',
    () {
      final report = buildSourceLocalSupportSeparationReportJson();

      expect(
        report['schemaVersion'],
        'source_local_support_separation_report_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds['minMemberGrowth'], 4);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 2);
      expect(summary['falseRecoveryGuardConfirmedCount'], 0);
      expect(summary['positiveGuardConfirmedCount'], 1);
      expect(summary['productionCoordinateSwitchAllowedCount'], 0);
      expect(summary['nearCompleteBlockedOnlyByGrowthCount'], greaterThan(0));

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };
      final fukushima = cases['20260621_fukushima_offshore_m32_eq6']!;
      expect(fukushima['diagnosis'], 'blocked_false_recovery_by_member_growth');
      expect(fukushima['localSupportConfirmedCount'], 0);
      expect(fukushima['nearCompleteBlockedOnlyByGrowthCount'], greaterThan(0));
      expect(fukushima['maxMemberGrowthWhenBlockedOnlyByGrowth'], lessThan(4));

      final iwate = cases['20260625_iwate_offshore_m32_jma']!;
      expect(iwate['diagnosis'], 'confirmed_positive_by_full_local_support');
      expect(iwate['localSupportConfirmedCount'], 1);
      expect(iwate['minConfirmedMemberGrowth'], greaterThanOrEqualTo(4));

      final iwateFrames = (iwate['frames'] as List)
          .cast<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false);
      final confirmed = iwateFrames.singleWhere(
        (frame) => frame['localSupportConfirmed'] == true,
      );
      expect(confirmed['status'], 'confirmedDelayed');
      expect(confirmed['memberCountGrowth'], 5);
      expect(
        (confirmed['support'] as Map).values.every((value) => value == true),
        isTrue,
      );

      final reportFile = File(
        '.dart_tool/source_local_support_separation_report/report.json',
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
