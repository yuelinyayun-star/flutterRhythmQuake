import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_propagation_shape_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku propagation-shape diagnostic stays non-production and structured',
    () {
      final report = buildPlumTohokuPropagationShapeDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_propagation_shape_diagnostic_v1',
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
      expect(policy['plumRadiusKm'], 30.0);
      expect(policy['plumDampingPer10Km'], 0.50);

      final focus = (report['focusFilter'] as Map).cast<String, Object?>();
      expect(focus['estimatedSourceRegion'], 'tohoku');
      expect(focus['minimumEvidenceCount'], 8);
      expect(focus['maximumNearestEvidenceDistanceKm'], 10.0);
      expect(focus['minimumPredictionMarginShindo'], 1.0);

      final coverage = (report['coverage'] as Map).cast<String, Object?>();
      expect(coverage['validationStationForecasts'], greaterThan(0));
      expect(coverage['testStationForecasts'], greaterThan(0));

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));

      for (final label in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[label]! as Map).cast<String, Object?>();
        final splits = (threshold['splits']! as Map).cast<String, Object?>();
        expect(splits.keys, containsAll(<String>['validation', 'test']));
        double? validationPrecision;
        double? testPrecision;
        for (final splitName in <String>['validation', 'test']) {
          final split = (splits[splitName]! as Map).cast<String, Object?>();
          expect(split['focusSampleCount'], isA<int>());
          expect(split['truePositiveCount'], isA<int>());
          expect(split['falsePositiveCount'], isA<int>());
          expect(split['precision'], isA<double>());
          expect(split['plumOnlyFalsePositiveCount'], isA<int>());
          if (splitName == 'validation') {
            validationPrecision = split['precision']! as double;
          } else {
            testPrecision = split['precision']! as double;
          }

          final outcomes = (split['outcomes']! as Map).cast<String, Object?>();
          expect(
            outcomes.keys,
            containsAll(<String>['truePositive', 'falsePositive']),
          );
          for (final outcomeName in <String>['truePositive', 'falsePositive']) {
            final outcome = (outcomes[outcomeName]! as Map)
                .cast<String, Object?>();
            final features = (outcome['features']! as Map)
                .cast<String, Object?>();
            expect(outcome['count'], isA<int>());
            expect(features['strongestEvidenceIntensity'], isA<double>());
            expect(features['actualIntensity'], isA<double>());
            expect(features['evidenceTargetGap'], isA<double>());
            expect(features['localBelowThresholdShare10Km'], isA<double>());
            expect(features['localBelowThresholdShare20Km'], isA<double>());
            expect(features['supportingEvidenceCount'], isA<double>());
            expect(
              features['supportingEvidenceQuadrantCoverage'],
              isA<double>(),
            );
            expect(
              features['supportingEvidenceCentroidOffsetKm'],
              isA<double>(),
            );
            expect(features['supportingEvidenceMeanDistanceKm'], isA<double>());
            expect(features['supportingEvidenceMaxSpreadKm'], isA<double>());
          }

          expect(split['falsePositiveExamples'], isA<List>());
        }

        if (label == 'shindo4') {
          expect(
            (splits['test']! as Map)['focusSampleCount'] as int,
            greaterThan(0),
          );
          expect(
            (splits['test']! as Map)['falsePositiveCount'] as int,
            greaterThan(0),
          );
        }
        expect(validationPrecision, isNotNull);
        expect(testPrecision, isNotNull);
        expect(validationPrecision!, greaterThan(testPrecision!));
      }

      final markdown = plumTohokuPropagationShapeDiagnosticMarkdown(report);
      expect(markdown, contains('# PLUM Tohoku Propagation-Shape Diagnostic'));
      expect(markdown, contains('## Focus Filter'));
      expect(markdown, contains('### Feature Aggregates'));
      expect(markdown, contains('### False-Positive Examples'));
      expect(markdown, contains('Suppression applied: `false`'));
      expect(markdown, contains('Raw predicted intensity mutated: `false`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
