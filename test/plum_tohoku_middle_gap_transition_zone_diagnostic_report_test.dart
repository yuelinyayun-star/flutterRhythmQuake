import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_middle_gap_transition_zone_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku middle-gap transition-zone diagnostic is structured and non-production',
    () {
      final report = buildPlumTohokuMiddleGapTransitionZoneDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_middle_gap_transition_zone_diagnostic_v1',
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

      final zoneDefinitions =
          (report['zoneDefinitions'] as Map).cast<String, Object?>();
      expect(zoneDefinitions.keys, containsAll(<String>[
        'middle_transition_zone',
        'extreme_false_zone',
        'extreme_true_zone',
        'other_mismatch_zone',
      ]));

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));
      for (final label in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[label]! as Map).cast<String, Object?>();
        expect(threshold['validation'], isA<Map>());
        expect(threshold['test'], isA<Map>());
        expect(threshold['zoneComparisons'], isA<List>());
        expect(threshold['signatureAssessment'], isA<Map>());
      }

      final markdown =
          plumTohokuMiddleGapTransitionZoneDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Middle-Gap Transition-Zone Diagnostic'),
      );
      expect(markdown, contains('### Zone Comparison'));
      expect(markdown, contains('### Signature Assessment'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
