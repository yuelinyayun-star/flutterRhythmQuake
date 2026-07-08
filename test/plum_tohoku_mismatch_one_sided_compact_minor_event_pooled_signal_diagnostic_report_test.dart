import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact minor-event pooled signal diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMismatchOneSidedCompactMinorEventPooledSignalDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_v1',
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

      expect(report['minorSliceEvents'], isA<List>());
      expect(report['variantComparison'], isA<Map>());
      expect(report['modeFeatureMeans'], isA<Map>());
      expect(report['featureFamilies'], isA<Map>());
      expect(report['rankedSeparators'], isA<List>());
      expect(report['sampleLedger'], isA<List>());

      final markdown =
          plumTohokuMismatchOneSidedCompactMinorEventPooledSignalDiagnosticMarkdown(
            report,
          );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku mismatch/one_sided/compact Minor-Event Pooled Signal Diagnostic',
        ),
      );
      expect(markdown, contains('## Variant Summary'));
      expect(markdown, contains('## Ranked Separators'));
      expect(markdown, contains('## Sample Ledger'));
      expect(markdown, contains('## `localMismatchBand`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
