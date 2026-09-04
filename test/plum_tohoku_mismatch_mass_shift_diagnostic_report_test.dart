import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_mass_shift_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch mass-shift diagnostic is structured and non-production',
    () {
      final report = buildPlumTohokuMismatchMassShiftDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_mass_shift_diagnostic_v1',
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

      final definitions = (report['decompositionDefinitions'] as Map)
          .cast<String, Object?>();
      expect(
        definitions.keys,
        containsAll(<String>[
          'localConsistencyBand',
          'geometrySpread',
          'actualGapBand',
          'evidenceGapBand',
        ]),
      );

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));
      for (final label in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[label]! as Map).cast<String, Object?>();
        expect(threshold['validation'], isA<Map>());
        expect(threshold['test'], isA<Map>());
        expect(threshold['transfers'], isA<Map>());
      }

      final markdown = plumTohokuMismatchMassShiftDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Mismatch Regime Mass-Shift Diagnostic'),
      );
      expect(markdown, contains('### Local-Consistency Mass Shift'));
      expect(markdown, contains('### Mismatch Geometry/Spread Mass Shift'));
      expect(markdown, contains('### Mismatch Actual-Gap Mass Shift'));
      expect(markdown, contains('### Mismatch Evidence-Gap Mass Shift'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
