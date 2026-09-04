import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_validation_event_family_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku validation event-family diagnostic is structured and validation-only',
    () {
      final report = buildPlumTohokuValidationEventFamilyDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_validation_event_family_diagnostic_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['rawPredictedIntensityMutated'], isFalse);
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['validationOnly'], isTrue);
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

      final definitions = (report['familyDefinitions'] as Map)
          .cast<String, Object?>();
      expect(
        definitions.keys,
        containsAll(<String>[
          'localConsistencyBand',
          'geometryBand',
          'spreadBand',
        ]),
      );

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));
      for (final label in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[label]! as Map).cast<String, Object?>();
        expect(threshold['summary'], isA<Map>());
        expect(threshold['familyAggregates'], isA<List>());
        expect(threshold['eventSignatures'], isA<List>());
      }

      final markdown = plumTohokuValidationEventFamilyDiagnosticMarkdown(
        report,
      );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku Validation Event/Propagation-Family Diagnostic',
        ),
      );
      expect(markdown, contains('### Validation Focus Summary'));
      expect(markdown, contains('### Family Aggregates'));
      expect(markdown, contains('### Event Signatures'));
      expect(markdown, contains('Validation only: `true`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
