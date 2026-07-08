import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_specificity_frozen_diagnostic_report.dart';

void main() {
  test(
    'PLUM specificity frozen diagnostic is structured and non-production',
    () {
      final report = buildPlumSpecificityFrozenDiagnosticJson();

      expect(report['schemaVersion'], 'plum_specificity_frozen_diagnostic_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['rawPredictedIntensityMutated'], isFalse);
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['parametersTuned'], isFalse);
      expect(policy['plumRadiusKm'], 30.0);
      expect(policy['plumDampingPer10Km'], 0.50);

      final coverage = (report['coverage'] as Map).cast<String, Object?>();
      expect(coverage['validationStationForecasts'], greaterThan(0));
      expect(coverage['testStationForecasts'], greaterThan(0));

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));

      for (final thresholdLabel in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[thresholdLabel]! as Map)
            .cast<String, Object?>();
        expect(threshold['precisionDelta'], isA<double>());
        expect(threshold['specificityDelta'], isA<double>());
        expect(threshold['falsePositiveDelta'], isA<int>());

        final splits = (threshold['splits']! as Map).cast<String, Object?>();
        expect(splits.keys, containsAll(<String>['validation', 'test']));
        for (final splitName in <String>['validation', 'test']) {
          final split = (splits[splitName]! as Map).cast<String, Object?>();
          final overall = (split['overall']! as Map).cast<String, Object?>();
          expect(overall['precision'], isA<double>());
          expect(overall['recall'], isA<double>());
          expect(overall['specificity'], isA<double>());
          expect(overall['falsePositiveRate'], isA<double>());
          expect(overall['plumOnlyFalsePositive'], isA<int>());

          for (final bucketField in <String>[
            'regionBuckets',
            'distanceBuckets',
            'maskRateBuckets',
            'evidenceCountBuckets',
            'nearestEvidenceDistanceBuckets',
            'strongestEvidenceIntensityBuckets',
            'predictionMarginBuckets',
          ]) {
            expect(split[bucketField], isA<Map>());
          }
        }
      }

      final markdown = plumSpecificityFrozenDiagnosticMarkdown(report);
      expect(markdown, contains('# PLUM Specificity Frozen Diagnostic'));
      expect(markdown, contains('PLUM-only FP'));
      expect(markdown, contains('Evidence Count Buckets'));
      expect(markdown, contains('Prediction Margin Buckets'));
      expect(markdown, contains('Production UI connected: `false`'));
      expect(markdown, contains('Parameters tuned: `false`'));
      expect(markdown, contains('Raw predicted intensity mutated: `false`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
