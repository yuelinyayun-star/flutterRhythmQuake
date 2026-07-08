import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_upstream_source_family_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku upstream source-family diagnostic is structured and non-production',
    () {
      final report = buildPlumTohokuUpstreamSourceFamilyDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_upstream_source_family_diagnostic_v1',
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

      final definitions =
          (report['familyDefinitions'] as Map).cast<String, Object?>();
      expect(definitions['sourceTriggerFamily'], isA<Map>());
      expect(definitions['sourceWinnerFamily'], isA<Map>());
      expect(definitions['eventFamily'], isA<Map>());

      final splitSummaries =
          (report['splitSummaries'] as Map).cast<String, Object?>();
      expect(splitSummaries['validation'], isA<Map>());
      expect(splitSummaries['test'], isA<Map>());

      expect(report['sourceTriggerFamilyTransfer'], isA<List>());
      expect(report['sourceWinnerFamilyTransfer'], isA<List>());
      expect(report['sourceWinnerTransitionTransfer'], isA<List>());
      expect(report['sourceWinnerEventFamilyTransfer'], isA<List>());
      expect(report['dominantTestEvents'], isA<List>());

      final markdown =
          plumTohokuUpstreamSourceFamilyDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Upstream Source-Family Diagnostic'),
      );
      expect(markdown, contains('## Source Trigger Family Transfer'));
      expect(markdown, contains('## Source Winner x Transition Transfer'));
      expect(markdown, contains('## Dominant Test Events'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
