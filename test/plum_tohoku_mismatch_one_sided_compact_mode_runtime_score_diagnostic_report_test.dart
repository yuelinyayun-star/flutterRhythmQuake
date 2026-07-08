import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact mode runtime-score diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMismatchOneSidedCompactModeRuntimeScoreDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['rawPredictedIntensityMutated'], isFalse);
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['parametersTuned'], isFalse);
      expect(policy['suppressionApplied'], isFalse);

      final inputs = (report['inputs'] as Map).cast<String, Object?>();
      expect(inputs['family'], 'mismatch/one_sided/compact');

      expect(report['scoreAnchors'], isA<Map>());
      expect(report['modeScoreMeans'], isA<Map>());
      expect(report['validationAnchoredBandTransfer'], isA<Map>());
      expect(report['remainderQuartiles'], isA<List>());
      expect(report['remainderMonotonicity'], isA<Map>());

      final markdown =
          plumTohokuMismatchOneSidedCompactModeRuntimeScoreDiagnosticMarkdown(
            report,
          );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Diagnostic',
        ),
      );
      expect(markdown, contains('## Validation-Anchored Band Transfer'));
      expect(markdown, contains('## Remainder Quartiles'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
