import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact mode runtime-score ablation diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMismatchOneSidedCompactModeRuntimeScoreAblationDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_v1',
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
      expect(inputs['variants'], isA<List>());

      expect(report['variantComparison'], isA<Map>());

      final markdown =
          plumTohokuMismatchOneSidedCompactModeRuntimeScoreAblationDiagnosticMarkdown(
            report,
          );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Ablation Diagnostic',
        ),
      );
      expect(markdown, contains('## Variant Summary'));
      expect(markdown, contains('## `support_geometry_only`'));
      expect(markdown, contains('## `support_geometry_plus_proximity`'));
      expect(markdown, contains('## `full_score`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
