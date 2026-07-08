import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'candidate promotion matrix keeps residual gate conservative',
    () {
      final reportFile = File(
        '.dart_tool/source_candidate_promotion_report/matrix.json',
      );
      if (!reportFile.existsSync()) {
        markTestSkipped(
          'Missing promotion matrix report. Run '
          '`powershell -NoProfile -ExecutionPolicy Bypass -File '
          'tools\\validate_source_candidate_promotion_matrix.ps1`.',
        );
        return;
      }

      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['schemaVersion'], 'source_candidate_promotion_report_v1');
      final validation = report['validation'] as Map<String, Object?>;
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);
      final gate = report['productionGate'] as Map<String, Object?>;
      expect(gate['usesTruthLabels'], isFalse);
      final delayed = gate['delayedConfirmationDiagnostic'] as Map;
      expect(delayed['productionCoordinateSwitch'], isFalse);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };
      expect(cases.keys, containsAll(_expectedCoreCases));
      expect(
        cases.values.every((entry) => entry['offlineFalseAcceptFrames'] == 0),
        isTrue,
        reason: 'residual promotion must not create offline false accepts',
      );
      expect(
        cases.values.every((entry) => entry['delayedFalseRecoveryFrames'] == 0),
        isTrue,
        reason: 'delayed residual confirmation must not recover false cases',
      );

      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['acceptedCandidateFrames'],
        0,
      );
      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['rejectedCandidateFrames'],
        8,
      );

      expect(
        cases['20260625_iwate_offshore_m32_jma']!['acceptedCandidateFrames'],
        0,
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['rejectedCandidateFrames'],
        3,
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['offlineMissedPositiveFrames'],
        3,
      );

      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['acceptedCandidateFrames'],
        5,
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['delayedRecoveredMissedPositiveFrames'],
        3,
      );

      expect(
        cases['20260622_tomakomai_south_offshore_m35_hinet']!['acceptedCandidateFrames'],
        3,
      );
      expect(
        cases['20260622_tomakomai_south_offshore_m35_hinet']!['rejectedCandidateFrames'],
        0,
      );
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
