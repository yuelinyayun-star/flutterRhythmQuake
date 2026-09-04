import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_middle_transition_runtime_score_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku middle-transition runtime-score diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMiddleTransitionRuntimeScoreDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_middle_transition_runtime_score_diagnostic_v1',
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

      final focus = (report['focusFilter'] as Map).cast<String, Object?>();
      expect(focus['estimatedSourceRegion'], 'tohoku');
      expect(focus['minimumEvidenceCount'], 8);
      expect(focus['maximumNearestEvidenceDistanceKm'], 10.0);
      expect(focus['minimumPredictionMarginShindo'], 1.0);
      expect(focus['baselineThresholdCrossingRequired'], isTrue);

      final scoreDef = (report['scoreDefinition'] as Map)
          .cast<String, Object?>();
      expect(scoreDef['weights'], isA<Map>());

      final means = (report['testOutcomeScoreMeans'] as Map)
          .cast<String, Object?>();
      expect(
        means.keys,
        containsAll(<String>['middleTransitionZone', 'otherFocusSamples']),
      );

      final transfer = (report['validationAnchoredBandTransfer'] as Map)
          .cast<String, Object?>();
      expect(transfer['validation'], isA<List>());
      expect(transfer['test'], isA<List>());
      expect(report['testDeciles'], isA<List>());
      expect(report['monotonicitySummary'], isA<Map>());

      final markdown = plumTohokuMiddleTransitionRuntimeScoreDiagnosticMarkdown(
        report,
      );
      expect(
        markdown,
        contains('# PLUM Tohoku Middle-Transition Runtime-Score Diagnostic'),
      );
      expect(markdown, contains('## Validation-Anchored Band Transfer'));
      expect(markdown, contains('## Test Deciles'));
      expect(markdown, contains('## Monotonicity'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
