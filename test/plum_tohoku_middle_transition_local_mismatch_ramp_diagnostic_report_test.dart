import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku middle-transition local-mismatch-ramp diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMiddleTransitionLocalMismatchRampDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_v1',
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

      final scoreDef =
          (report['scoreDefinition'] as Map).cast<String, Object?>();
      expect(scoreDef['localMismatchRamp'], isA<String>());
      expect(scoreDef['adjustedScore'], isA<String>());

      final transfer =
          (report['validationAnchoredBandTransfer'] as Map).cast<String, Object?>();
      expect(transfer['base'], isA<Map>());
      expect(transfer['adjusted'], isA<Map>());

      final monotonicity =
          (report['monotonicitySummary'] as Map).cast<String, Object?>();
      expect(monotonicity['base'], isA<Map>());
      expect(monotonicity['adjusted'], isA<Map>());
      expect(report['comparisonSummary'], isA<Map>());

      final markdown =
          plumTohokuMiddleTransitionLocalMismatchRampDiagnosticMarkdown(report);
      expect(
        markdown,
        contains(
          '# PLUM Tohoku Middle-Transition Local-Mismatch-Ramp Diagnostic',
        ),
      );
      expect(markdown, contains('## Comparison Summary'));
      expect(markdown, contains('## `base` Validation-Anchored Band Transfer'));
      expect(
        markdown,
        contains('## `adjusted` Validation-Anchored Band Transfer'),
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

