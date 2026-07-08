import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact mode signal separation diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMismatchOneSidedCompactModeSignalSeparationDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_v1',
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

      expect(report['modeFeatureMeans'], isA<Map>());
      expect(report['featureFamilies'], isA<Map>());
      expect(report['rankedSeparators'], isA<List>());

      final markdown =
          plumTohokuMismatchOneSidedCompactModeSignalSeparationDiagnosticMarkdown(
            report,
          );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku mismatch/one_sided/compact Mode Signal Separation Diagnostic',
        ),
      );
      expect(markdown, contains('## Ranked Separators'));
      expect(markdown, contains('## `localMismatchBand`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
