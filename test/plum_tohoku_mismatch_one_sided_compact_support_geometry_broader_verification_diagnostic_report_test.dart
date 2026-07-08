import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report.dart';

void main() {
  test(
    'PLUM Tohoku mismatch/one_sided/compact support-geometry broader verification diagnostic is structured and non-production',
    () {
      final report =
          buildPlumTohokuMismatchOneSidedCompactSupportGeometryBroaderVerificationDiagnosticJson();

      expect(
        report['schemaVersion'],
        'plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_v1',
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
      expect(report['sliceCategorySummary'], isA<Map>());

      final markdown =
          plumTohokuMismatchOneSidedCompactSupportGeometryBroaderVerificationDiagnosticMarkdown(
            report,
          );
      expect(
        markdown,
        contains(
          '# PLUM Tohoku mismatch/one_sided/compact Support-Geometry Broader Verification Diagnostic',
        ),
      );
      expect(markdown, contains('## Slice Category Summary'));
      expect(markdown, contains('## Slice Summary'));
      expect(markdown, contains('## `all_remainder`'));
      expect(markdown, contains('leave_event_out::'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
