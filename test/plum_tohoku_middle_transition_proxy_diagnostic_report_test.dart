import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_middle_transition_proxy_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku middle-transition proxy diagnostic is structured and non-production',
    () {
      final report = buildPlumTohokuMiddleTransitionProxyDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_middle_transition_proxy_diagnostic_v1',
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

      final families = (report['featureFamilies'] as Map).cast<String, Object?>();
      expect(families.keys, containsAll(<String>[
        'branchAgreement',
        'robustnessScore',
        'geometrySpread',
        'branchAgreement|geometrySpread',
      ]));

      final ranked = report['rankedCandidates'];
      expect(ranked, isA<List>());

      final markdown =
          plumTohokuMiddleTransitionProxyDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Middle-Transition Proxy Diagnostic'),
      );
      expect(markdown, contains('## Ranked Proxy Candidates'));
      expect(markdown, contains('## `branchAgreement`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

