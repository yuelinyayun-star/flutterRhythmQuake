import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_event_concentration_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku event-concentration diagnostic is structured and non-production',
    () {
      final report = buildPlumTohokuEventConcentrationDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_event_concentration_diagnostic_v1',
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
      expect(focus['baselineThresholdCrossingRequired'], isTrue);
      expect(focus['plumMarginGateApplied'], isFalse);

      final dominantEvent = (report['dominantEvent'] as Map)
          .cast<String, Object?>();
      expect(dominantEvent['eventId'], isNot('none'));
      expect(dominantEvent['testFocusShare'], isA<num>());

      final sliceSummaries = (report['sliceSummaries'] as Map)
          .cast<String, Object?>();
      expect(sliceSummaries['validation'], isA<Map>());
      expect(sliceSummaries['testFull'], isA<Map>());
      expect(sliceSummaries['dominantTestEventOnly'], isA<Map>());
      expect(sliceSummaries['testWithoutDominantEvent'], isA<Map>());

      expect(report['sourceTriggerFamilySlices'], isA<List>());
      expect(report['sourceWinnerFamilySlices'], isA<List>());
      expect(report['sourceWinnerTransitionSlices'], isA<List>());
      expect(report['eventConcentrationTable'], isA<List>());

      final markdown = plumTohokuEventConcentrationDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Event-Concentration Diagnostic'),
      );
      expect(markdown, contains('## Dominant Event'));
      expect(markdown, contains('## Source Winner Family Slices'));
      expect(markdown, contains('## Test Event Concentration'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
