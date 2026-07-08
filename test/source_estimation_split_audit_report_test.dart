import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split audit validation script regenerates report before testing', () {
    final script = File(
      'tools/validate_source_estimation_split_audit.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('build_source_estimation_split_audit_report.dart'));
    expect(
      script,
      contains('test\\source_estimation_split_audit_report_test.dart'),
    );
    expect(
      script.indexOf('build_source_estimation_split_audit_report.dart'),
      lessThan(
        script.indexOf('source_estimation_split_audit_report_test.dart'),
      ),
    );
  });

  test('source-estimation split audit keeps frozen metrics isolated', () {
    final reportFile = File(
      '.dart_tool/source_estimation_split_audit/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing split audit report. Run '
        '`dart run tools/build_source_estimation_split_audit_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'source_estimation_split_audit_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final summary = report['summary'] as Map<String, Object?>;
    expect(summary['caseCount'], 25);
    expect(summary['detectionMetricCaseCount'], 2);
    expect(summary['unassignedReferenceEventCount'], 12);
    expect(summary['explicitUnassignedReferenceEventCount'], 12);
    expect(summary['unspecifiedUnassignedEventCount'], 0);
    expect(summary['quietWindowTargetCount'], 2);
    expect(summary['quietWindowRemainingCount'], 0);
    expect(summary['quietWindowPlannedCaptureCount'], 0);
    expect(summary['splitAssignmentPlanCaseCount'], 19);
    expect(summary['plannedUnassignedReferenceEventCount'], 12);
    expect(summary['unplannedUnassignedReferenceEventCount'], 0);

    final quietPlan = report['quietWindowCapturePlan'] as Map<String, Object?>;
    expect(
      quietPlan['path'],
      'docs/data/source_estimation_quiet_window_capture_plan.json',
    );
    expect(
      quietPlan['schemaVersion'],
      'source_estimation_quiet_window_capture_plan_v1',
    );
    expect(quietPlan['currentIndependentQuietWindowCount'], 2);
    expect(quietPlan['remainingIndependentQuietWindowCount'], 0);
    expect(quietPlan['plannedCaptureCount'], 0);
    expect(quietPlan['layerCount'], 8);
    expect(quietPlan['hasRequiredLayers'], isTrue);
    expect(quietPlan['missingRequiredLayers'], isEmpty);
    expect(quietPlan['requiredLayerFamilies'], [
      'jma',
      'acmap',
      'vcmap',
      'dcmap',
    ]);
    expect(quietPlan['layers'], [
      'acmap_b',
      'acmap_s',
      'dcmap_b',
      'dcmap_s',
      'jma_b',
      'jma_s',
      'vcmap_b',
      'vcmap_s',
    ]);

    final assignmentPlan =
        report['splitAssignmentPlan'] as Map<String, Object?>;
    expect(
      assignmentPlan['path'],
      'docs/data/source_estimation_split_assignment_plan.json',
    );
    expect(
      assignmentPlan['schemaVersion'],
      'source_estimation_split_assignment_plan_v1',
    );
    expect(assignmentPlan['caseCount'], 19);
    expect(assignmentPlan['plannedUnassignedReferenceEventCount'], 12);
    expect(assignmentPlan['unplannedUnassignedReferenceEventCount'], 0);

    final bySplit = summary['bySplit'] as Map<String, Object?>;
    expect(bySplit['train'], 2);
    expect(bySplit['validation'], 9);
    expect(bySplit['test'], 1);
    expect(bySplit['unassigned'], 13);

    final byCaseType = summary['byCaseType'] as Map<String, Object?>;
    expect(byCaseType['event'], 23);
    expect(byCaseType['noise'], 2);

    expect(report['warnings'], contains('unassigned_reference_event_count:12'));
    expect(
      report['warnings'],
      isNot(contains('independent_quiet_window_count_below_2:1')),
    );
    expect(
      report['warnings'],
      isNot(contains('quiet_window_capture_plan_missing')),
    );
    expect(
      report['warnings'],
      isNot(
        contains(
          'quiet_window_capture_plan_missing_required_layers:jma_s,jma_b',
        ),
      ),
    );
    expect(
      report['warnings'],
      isNot(contains('quiet_window_capture_plan_insufficient:0<1')),
    );
    expect(
      report['warnings'],
      isNot(contains('split_assignment_plan_missing')),
    );
    expect(
      report['warnings'],
      isNot(contains('unassigned_reference_without_assignment_plan:13')),
    );
    expect(
      report['warnings'],
      isNot(contains('unassigned_reference_without_assignment_plan:3')),
    );
    expect(
      report['warnings'],
      isNot(contains('unassigned_event_without_split_status:11')),
    );

    final cases = (report['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      cases.where(
        (entry) =>
            entry['split'] == 'unassigned' &&
            entry['includeInDetectionMetrics'] == true,
      ),
      isEmpty,
    );
    expect(
      cases.where(
        (entry) =>
            entry['caseType'] == 'noise' &&
            entry['includeInDetectionMetrics'] == true,
      ),
      isEmpty,
    );
  });

  test('capture scripts default to synchronized physical-layer windows', () {
    final liveScript = File(
      'tools/capture_nied_gif_live.ps1',
    ).readAsStringSync();
    final windowScript = File(
      'tools/capture_nied_gif_window.ps1',
    ).readAsStringSync();
    final quietPlan =
        jsonDecode(
              File(
                'docs/data/source_estimation_quiet_window_capture_plan.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    for (final layer in const [
      'jma_s',
      'jma_b',
      'acmap_s',
      'acmap_b',
      'vcmap_s',
      'vcmap_b',
      'dcmap_s',
      'dcmap_b',
    ]) {
      expect(liveScript, contains('"$layer"'));
      expect(windowScript, contains(layer));
      expect(quietPlan['recommendedCommandTemplate'], contains(layer));
    }
  });
}
