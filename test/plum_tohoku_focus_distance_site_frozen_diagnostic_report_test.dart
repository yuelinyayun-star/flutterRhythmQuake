import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_focus_distance_site_frozen_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku focus distance/site frozen diagnostic is structured and non-production',
    () {
      final report = buildPlumTohokuFocusDistanceSiteFrozenDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_focus_distance_site_frozen_diagnostic_v1',
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

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));

      for (final label in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[label]! as Map).cast<String, Object?>();
        final validation = (threshold['validation']! as Map)
            .cast<String, Object?>();
        final test = (threshold['test']! as Map).cast<String, Object?>();
        expect(validation['focusSampleCount'], isA<int>());
        expect(test['focusSampleCount'], isA<int>());
        expect(validation['baseline'], isA<Map>());
        expect(test['baseline'], isA<Map>());
        expect(validation['marginalDistance'], isA<List>());
        expect(test['marginalDistance'], isA<List>());
        expect(validation['jointBuckets'], isA<List>());
        expect(test['jointBuckets'], isA<List>());
        expect(validation['bandSummary'], isA<Map>());
        expect(test['bandTransferSummary'], isA<Map>());

        final validationBaseline = (validation['baseline']! as Map)
            .cast<String, Object?>();
        final testBaseline = (test['baseline']! as Map).cast<String, Object?>();
        if (label == 'shindo4') {
          expect(
            validationBaseline['precision'] as double,
            greaterThan(testBaseline['precision'] as double),
          );
        }
      }

      final markdown = plumTohokuFocusDistanceSiteFrozenDiagnosticMarkdown(
        report,
      );
      expect(
        markdown,
        contains('# PLUM Tohoku Focus Distance/Site Frozen Diagnostic'),
      );
      expect(markdown, contains('### Focus Baseline'));
      expect(markdown, contains('### Marginal Distance Precision'));
      expect(markdown, contains('### Distance-Site Buckets'));
      expect(markdown, contains('### Band Transfer'));
      expect(markdown, contains('Suppression applied: `false`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
