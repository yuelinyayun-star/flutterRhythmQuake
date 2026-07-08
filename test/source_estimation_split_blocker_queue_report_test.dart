import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split blocker queue script regenerates readiness first', () {
    final script = File(
      'tools/validate_source_estimation_split_blocker_queue.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains(r'[switch]$UseExistingReadiness'));
    expect(script, contains(r'if (-not $UseExistingReadiness)'));
    expect(
      script,
      contains('validate_source_estimation_split_assignment_readiness.ps1'),
    );
    expect(
      script,
      contains('build_source_estimation_split_blocker_queue_report.dart'),
    );
    expect(
      script,
      contains('source_estimation_split_blocker_queue_report_test.dart'),
    );
    expect(
      script,
      contains('build_final_catalog_or_hinet_revision_review_packet.dart'),
    );
    expect(
      script,
      contains('final_catalog_or_hinet_revision_review_packet_test.dart'),
    );
    expect(
      script.indexOf('validate_source_estimation_split_assignment_readiness'),
      lessThan(
        script.indexOf('build_source_estimation_split_blocker_queue_report'),
      ),
    );
    expect(
      script.indexOf('build_source_estimation_split_blocker_queue_report'),
      lessThan(
        script.indexOf('build_final_catalog_or_hinet_revision_review_packet'),
      ),
    );
  });

  test('split blocker queue exposes remaining source-estimation blockers', () {
    final reportFile = File(
      '.dart_tool/source_estimation_split_blocker_queue/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing split blocker queue report. Run '
        '`dart run tools/build_source_estimation_split_blocker_queue_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['schemaVersion'], 'source_estimation_split_blocker_queue_v1');
    expect(report['status'], 'pass');
    expect(report['readinessStatus'], 'pass');
    expect(report['errors'], isEmpty);
    expect(
      report['warnings'],
      isNot(contains('manual_ready_cases_still_unassigned')),
    );

    final summary = report['summary'] as Map<String, Object?>;
    expect(summary['blockedCaseCount'], 12);
    expect(summary['completedSplitAssignmentCount'], 7);
    expect(summary['readyForManualSplitAssignmentCount'], 0);
    expect(summary['readyForFrozenSplitButBlockedCount'], 0);
    final nextActionCounts = (summary['nextActionCounts'] as Map)
        .cast<String, Object?>();
    expect(nextActionCounts['review_jma_catalog_link'], 3);
    expect(nextActionCounts['review_hinet_preliminary_truth_quality'], 1);
    expect(nextActionCounts['review_hinet_truth_quality'], isNull);
    expect(nextActionCounts['link_final_catalog_or_hinet_revision'], 1);
    expect(
      nextActionCounts['keep_candidate_region_false_recovery_diagnostic_only'],
      1,
    );
    expect(nextActionCounts['keep_plum_like_diagnostic_only'], 6);
    expect(nextActionCounts['review_source_trigger_threshold_effect'], isNull);
    expect(nextActionCounts['assign_event_level_split'], isNull);

    final blockers = (report['blockers'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      blockers.map((entry) => entry['caseId']),
      isNot(contains('20260622_fukushima_offshore_m22_eq4')),
    );
    expect(
      blockers.map((entry) => entry['nextAction']),
      everyElement(isNot('split_assignment_complete')),
    );
    expect(
      blockers.map((entry) => entry['caseId']),
      isNot(contains('noto_m27_20260621_jma_eq5')),
    );
    final manualReady = blockers
        .where((entry) => entry['readyForManualSplitAssignment'] == true)
        .toList(growable: false);
    expect(manualReady, isEmpty);
    final fukushimaM32 = blockers.singleWhere(
      (entry) => entry['caseId'] == '20260621_fukushima_offshore_m32_eq6',
    );
    expect(
      fukushimaM32['nextAction'],
      'keep_candidate_region_false_recovery_diagnostic_only',
    );
    expect(fukushimaM32['readyForManualSplitAssignment'], isFalse);
    final plumOnly = blockers
        .where(
          (entry) => entry['nextAction'] == 'keep_plum_like_diagnostic_only',
        )
        .toList(growable: false);
    expect(plumOnly, hasLength(6));
    expect(
      plumOnly.map((entry) => entry['caseId']),
      containsAll([
        '20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p',
        '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
        '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        '20260627_fukushima_aizu_m36_jma_equake17',
        '20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p',
        '20260628_iwate_offshore_m41_jma',
      ]),
    );
    expect(
      plumOnly.map((entry) => entry['readyForManualSplitAssignment']),
      everyElement(false),
    );

    final completed = (report['completedSplitAssignments'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(completed, hasLength(7));
    final completedByCaseId = {
      for (final entry in completed) entry['caseId'] as String: entry,
    };
    expect(
      completedByCaseId['20260622_fukushima_offshore_m22_eq4']!['splitStatus'],
      'validation_reference',
    );
    expect(
      completedByCaseId['20260622_fukushima_offshore_m22_eq4']!['manualSplitConstraints'],
      containsAll([
        'keep_include_in_detection_metrics_false',
        'do_not_treat_as_catalog_truth',
        'do_not_use_for_final_test_claims',
      ]),
    );
    expect(
      completedByCaseId['noto_m27_20260621_jma_eq5']!['splitStatus'],
      'validation_reference',
    );
    expect(
      completedByCaseId['noto_m27_20260621_jma_eq5']!['manualSplitConstraints'],
      containsAll([
        'keep_include_in_detection_metrics_false',
        'do_not_treat_as_catalog_truth',
        'do_not_use_for_final_test_claims',
        'physical_fusion_diagnostic_only',
        'preserve_historical_fetch_warning',
      ]),
    );
    for (final caseId in const [
      '20260622_iwate_east_offshore_m30_hinet',
      '20260622_iwate_offshore_m30_eq10',
      '20260622_tomakomai_south_offshore_m35_hinet',
      '20260622_wakayama_south_m25_hinet',
      '20260623_tokachi_southeast_offshore_m34_hinet',
    ]) {
      expect(
        completedByCaseId[caseId]!['splitStatus'],
        'validation_reference',
        reason: caseId,
      );
      expect(
        completedByCaseId[caseId]!['manualSplitConstraints'],
        containsAll([
          'hinet_constrained_reference_only',
          'do_not_treat_as_catalog_truth',
          'do_not_use_for_final_test_claims',
        ]),
        reason: caseId,
      );
    }
  });
}
