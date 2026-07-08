import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_middle_transition_runtime_signal_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku middle-transition runtime-signal diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMiddleTransitionRuntimeSignalDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_middle_transition_runtime_signal_diagnostic_v1',
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

      final label = (report['labelDefinition'] as Map).cast<String, Object?>();
      expect(label['positiveLabel'], 'middle_transition_zone');

      final means =
          (report['testOutcomeFeatureMeans'] as Map).cast<String, Object?>();
      expect(
        means.keys,
        containsAll(<String>['middleTransitionZone', 'otherFocusSamples']),
      );

      final families = (report['featureFamilies'] as Map).cast<String, Object?>();
      expect(families.keys, containsAll(<String>[
        'topContributionShareBand',
        'contributionHhiBand',
        'marginStdDevBand',
        'topContributionShareBand|geometrySpread',
      ]));

      final markdown =
          plumTohokuMiddleTransitionRuntimeSignalDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Middle-Transition Runtime-Signal Diagnostic'),
      );
      expect(markdown, contains('## Test Outcome Feature Means'));
      expect(markdown, contains('## Ranked Runtime-Signal Candidates'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

