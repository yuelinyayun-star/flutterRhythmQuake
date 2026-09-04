import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_subregime_audit_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact sub-regime audit is structured and non-production',
    () {
      final report = buildPlumTohokuMismatchOneSidedCompactSubregimeAuditJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_subregime_audit_v1',
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

      final inputs = (report['inputs'] as Map).cast<String, Object?>();
      expect(inputs['family'], 'mismatch/one_sided/compact');

      expect(report['transitionRows'], isA<List>());
      expect(report['localMismatchRows'], isA<List>());
      expect(report['gapCellRows'], isA<List>());
      expect(report['jointSubRegimeRows'], isA<List>());
      expect(report['remainderEventRows'], isA<List>());

      final markdown = plumTohokuMismatchOneSidedCompactSubregimeAuditMarkdown(
        report,
      );
      expect(
        markdown,
        contains('# PLUM Tohoku mismatch/one_sided/compact Sub-Regime Audit'),
      );
      expect(markdown, contains('## Transition Rows'));
      expect(markdown, contains('## Local Mismatch Rows'));
      expect(markdown, contains('## Joint Sub-Regime Rows'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
