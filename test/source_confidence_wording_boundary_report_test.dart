import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_confidence_wording_boundary_report.dart';

void main() {
  test('confidence wording boundary validator runs matrix prerequisite', () {
    final script = File(
      'tools/validate_source_confidence_wording_boundary.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_residual_decision_matrix.ps1'));
    expect(
      script,
      contains('build_source_confidence_wording_boundary_report.dart'),
    );
    expect(
      script,
      contains('source_confidence_wording_boundary_report_test.dart'),
    );
  });

  test(
    'confidence wording boundary keeps candidate-region diagnostic-only',
    () {
      final report = buildSourceConfidenceWordingBoundaryReportJson();

      expect(report['schemaVersion'], 'source_confidence_wording_boundary_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);
      expect(policy['officialAlertWordingAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['boundaryCount'], 6);
      expect(summary['passedBoundaryCount'], 6);
      expect(summary['sourceCardVisibleBoundaryCount'], 4);
      expect(summary['diagnosticReportBoundaryCount'], 5);
      expect(summary['officialAlertWordingAllowedCount'], 0);
      expect(summary['productionCoordinateSwitchAllowedCount'], 0);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final boundaries = {
        for (final rawBoundary in report['boundaries'] as List)
          (rawBoundary as Map)['signal'] as String: rawBoundary
              .cast<String, Object?>(),
      };
      expect(
        boundaries.keys,
        containsAll({
          'production_estimate_quality',
          'candidate_region_pending',
          'candidate_region_residual_confirmed',
          'candidate_region_local_support_confirmed',
          'candidate_region_rejected_or_expired',
          'event_level_metrics_and_split',
        }),
      );

      for (final entry in boundaries.values) {
        final surfaces = (entry['surfaces'] as Map).cast<String, Object?>();
        expect(surfaces['officialAlertWording'], 'hide');
        expect(surfaces['productionCoordinateSwitch'], 'forbid');
        expect(entry['forbiddenCopy'], isNotEmpty);
      }

      expect(
        (boundaries['candidate_region_pending']!['surfaces'] as Map)
            .cast<String, Object?>()['sourceEstimationUnifiedCard'],
        'show_as_uncertainty_only',
      );
      expect(
        (boundaries['candidate_region_residual_confirmed']!['surfaces'] as Map)
            .cast<String, Object?>()['sourceEstimationUnifiedCard'],
        'show_as_diagnostic_confirmation',
      );
      expect(
        (boundaries['candidate_region_local_support_confirmed']!['surfaces']
                as Map)
            .cast<String, Object?>()['sourceEstimationUnifiedCard'],
        'show_as_diagnostic_confirmation',
      );
      expect(
        (boundaries['candidate_region_rejected_or_expired']!['surfaces'] as Map)
            .cast<String, Object?>()['sourceEstimationUnifiedCard'],
        'hide_or_show_debug_only',
      );
      expect(
        (boundaries['event_level_metrics_and_split']!['surfaces'] as Map)
            .cast<String, Object?>()['sourceEstimationUnifiedCard'],
        'not_ready',
      );

      final reportFile = File(
        '.dart_tool/source_confidence_wording_boundary/report.json',
      );
      if (reportFile.existsSync()) {
        final generated =
            jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
        expect(generated['schemaVersion'], report['schemaVersion']);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
