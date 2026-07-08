import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact support-geometry transfer diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMismatchOneSidedCompactSupportGeometryTransferDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_v1',
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
      expect(inputs['scoreVariant'], 'supportGeometry-only');

      expect(report['sliceReports'], isA<List>());

      final markdown =
          plumTohokuMismatchOneSidedCompactSupportGeometryTransferDiagnosticMarkdown(
            report,
          );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku mismatch/one_sided/compact Support-Geometry Transfer Diagnostic',
        ),
      );
      expect(markdown, contains('## Slice Summary'));
      expect(markdown, contains('## `all_remainder`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
