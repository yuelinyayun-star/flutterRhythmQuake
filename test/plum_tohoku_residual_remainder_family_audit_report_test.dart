import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_residual_remainder_family_audit_report.dart';

void main() {
  test(
    'PLUM Tohoku residual remainder family audit is structured and non-production',
    () {
      final report = buildPlumTohokuResidualRemainderFamilyAuditJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_residual_remainder_family_audit_v1',
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

      final dominantEvent = (report['dominantEvent'] as Map).cast<String, Object?>();
      expect(dominantEvent['eventId'], isNot('none'));
      expect(dominantEvent['removedFromTest'], isTrue);

      final coverage = (report['coverage'] as Map).cast<String, Object?>();
      expect(coverage['remainderFocusSamples'], isA<int>());
      expect(coverage['remainderFalsePositives'], isA<int>());
      expect(coverage['remainderPlumOnlyFalsePositives'], isA<int>());

      expect(report['validationFamilyRows'], isA<List>());
      expect(report['remainderFamilyRows'], isA<List>());
      expect(report['remainderFalsePositiveFamilyRows'], isA<List>());
      expect(report['remainderPlumOnlyFalsePositiveFamilyRows'], isA<List>());
      expect(report['remainderPlumHigherFalsePositiveFamilyRows'], isA<List>());
      expect(report['dominanceSummary'], isA<Map>());
      expect(report['remainderEventRows'], isA<List>());

      final markdown =
          plumTohokuResidualRemainderFamilyAuditMarkdown(report);
      expect(
        markdown,
        contains('# PLUM Tohoku Residual Remainder Family Audit'),
      );
      expect(markdown, contains('## Dominance Summary'));
      expect(markdown, contains('## Remainder PLUM-Only False-Positive Families'));
      expect(markdown, contains('## Remainder Events'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
