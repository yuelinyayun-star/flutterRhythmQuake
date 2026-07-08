import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_metric_readiness_triage_report.dart';

void main() {
  test('metric-readiness triage validator runs blocker prerequisite', () {
    final script = File(
      'tools/validate_source_metric_readiness_triage.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('validate_source_estimation_split_blocker_queue.ps1'),
    );
    expect(
      script,
      contains('build_source_metric_readiness_triage_report.dart'),
    );
    expect(script, contains('source_metric_readiness_triage_report_test.dart'));
  });

  test(
    'metric-readiness triage does not promote diagnostic cases',
    () {
      final report = buildSourceMetricReadinessTriageReportJson();

      expect(report['schemaVersion'], 'source_metric_readiness_triage_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['assignsSplits'], isFalse);
      expect(policy['changesMetricEligibility'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['caseCount'], 19);
      expect(summary['metricBearingReadyCount'], 0);
      expect(summary['referenceValidationOnlyCount'], 7);
      expect(summary['diagnosticReadyBlockedCount'], 8);
      expect(summary['metadataOnlyOrIncompleteCount'], 4);
      expect(summary['blockedCaseCount'], 12);
      expect(summary['completedSplitAssignmentCount'], 7);
      expect(summary['readyForManualSplitAssignmentCount'], 0);
      expect(summary['candidateRegionDiagnosticBlockedCount'], 3);
      expect(summary['referenceLabelAvailableCount'], 19);
      expect(summary['jmaReferenceLabelAvailableCount'], 10);
      final nextActionCounts = (summary['nextActionCounts'] as Map)
          .cast<String, Object?>();
      expect(nextActionCounts['assign_event_level_split'], isNull);
      expect(
        nextActionCounts['keep_candidate_region_false_recovery_diagnostic_only'],
        1,
      );
      expect(nextActionCounts['split_assignment_complete'], 7);
      expect(nextActionCounts['review_hinet_preliminary_truth_quality'], 1);
      expect(nextActionCounts['keep_plum_like_diagnostic_only'], 6);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };
      expect(
        cases['20260622_fukushima_offshore_m22_eq4']!['triageTier'],
        'reference_validation_only',
      );
      expect(
        cases['noto_m27_20260621_jma_eq5']!['triageTier'],
        'reference_validation_only',
      );
      for (final caseId in const [
        '20260622_iwate_east_offshore_m30_hinet',
        '20260622_iwate_offshore_m30_eq10',
        '20260622_tomakomai_south_offshore_m35_hinet',
        '20260622_wakayama_south_m25_hinet',
        '20260623_tokachi_southeast_offshore_m34_hinet',
      ]) {
        expect(cases[caseId]!['triageTier'], 'reference_validation_only');
        expect(cases[caseId]!['readyForManualSplitAssignment'], isFalse);
        expect(
          cases[caseId]!['metricBlockingReason'],
          'reference_only_validation_not_for_final_metric_claims',
        );
        expect(cases[caseId]!['metricBearingReady'], isFalse);
      }
      expect(
        cases['20260622_fukushima_offshore_m22_eq4']!['metricBlockingReason'],
        'reference_only_validation_not_for_final_metric_claims',
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['triageTier'],
        'diagnostic_ready_blocked',
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['referenceLabelStatus'],
        'jma_reference_label_available',
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['referenceLabelSource'],
        'jma_source_and_intensity_label_not_final_catalog',
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['metricBlockingReason'],
        'jma_reference_label_available_final_catalog_link_pending',
      );
      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['metricBlockingReason'],
        'keep_candidate_region_false_recovery_diagnostic_only',
      );
      for (final caseId in const [
        '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        '20260627_fukushima_aizu_m36_jma_equake17',
      ]) {
        expect(cases[caseId]!['triageTier'], 'diagnostic_ready_blocked');
        expect(
          cases[caseId]!['metricBlockingReason'],
          'keep_plum_like_diagnostic_only',
        );
        expect(cases[caseId]!['metricBearingReady'], isFalse);
        expect(cases[caseId]!['readyForManualSplitAssignment'], isFalse);
      }
      expect(
        cases['20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8']!['triageTier'],
        'metadata_only_or_incomplete',
      );
      expect(
        cases['20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8']!['metricBlockingReason'],
        'local_capture_missing_or_has_failed_frames',
      );
      expect(
        cases['20260620_iwate_offshore_m34_ref']!['triageTier'],
        'metadata_only_or_incomplete',
      );
      for (final caseId in const ['20260621_fukushima_offshore_m32_eq6']) {
        expect(cases[caseId]!['triageTier'], 'diagnostic_ready_blocked');
        expect(cases[caseId]!['readyForManualSplitAssignment'], isFalse);
        expect(
          cases[caseId]!['metricBlockingReason'],
          'keep_candidate_region_false_recovery_diagnostic_only',
        );
        expect(cases[caseId]!['metricBearingReady'], isFalse);
      }

      final reportFile = File(
        '.dart_tool/source_metric_readiness_triage/report.json',
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
