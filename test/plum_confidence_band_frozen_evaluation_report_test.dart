import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_confidence_band_frozen_evaluation_report.dart';

void main() {
  test(
    'PLUM confidence-band frozen evaluation is one-shot and non-suppressive',
    () {
      final report = buildPlumConfidenceBandFrozenEvaluationJson();

      expect(report['schemaVersion'],
          'plum_confidence_band_frozen_evaluation_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'test');
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['oneShot'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['rawPredictedIntensityMutated'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);

      final validationRef =
          (report['validationReference'] as Map).cast<String, Object?>();
      expect(validationRef['bandPrecision'], isA<Map>());
      expect(validationRef['bandPredictedPositive'], isA<Map>());
      expect(validationRef['highMediumShare'], isA<double>());

      final frozenCoverage =
          (report['frozenCoverage'] as Map).cast<String, Object?>();
      expect(frozenCoverage['stationForecastCount'], greaterThan(0));
      expect(frozenCoverage['totalPredictedPositive'], greaterThan(0));

      final frozenBands =
          (report['frozenBands'] as Map).cast<String, Object?>();
      expect(
        frozenBands.keys,
        containsAll(['high', 'medium', 'low', 'insufficient']),
      );

      final checks = (report['criteriaChecks'] as Map).cast<String, Object?>();
      expect(
        checks.keys,
        containsAll([
          'F1_band_monotonicity',
          'F2_high_precision_hold',
          'F3_no_collapse_high',
          'F3_no_collapse_medium',
          'F3_no_collapse_low',
          'F4_coverage_hold',
        ]),
      );

      final outcome = (report['outcome'] as Map).cast<String, Object?>();
      expect(outcome['frozenEvaluationStatus'], anyOf('pass', 'fail'));
      expect(outcome['advanceToProductionUi'], isFalse);

      final markdown = plumConfidenceBandFrozenEvaluationMarkdown(report);
      expect(markdown, contains('PLUM Confidence-Band Frozen Evaluation'));
      expect(markdown, contains('One-shot: `true`'));
      expect(markdown, contains('Raw predicted intensity mutated: `false`'));
      expect(markdown, contains('F1-F4 are pre-registered'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
