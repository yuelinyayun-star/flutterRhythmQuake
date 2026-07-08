import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'split assignment readiness script regenerates report before testing',
    () {
      final script = File(
        'tools/validate_source_estimation_split_assignment_readiness.ps1',
      ).readAsStringSync();

      expect(script, contains("\$ErrorActionPreference = 'Stop'"));
      expect(
        script,
        contains(
          'build_source_estimation_split_assignment_readiness_report.dart',
        ),
      );
      expect(
        script,
        contains(
          'source_estimation_split_assignment_readiness_report_test.dart',
        ),
      );
      expect(
        script.indexOf(
          'build_source_estimation_split_assignment_readiness_report.dart',
        ),
        lessThan(
          script.indexOf(
            'source_estimation_split_assignment_readiness_report_test.dart',
          ),
        ),
      );
    },
  );

  test('split assignment readiness keeps reference cases out of frozen split', () {
    final reportFile = File(
      '.dart_tool/source_estimation_split_assignment_readiness/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing split assignment readiness report. Run '
        '`dart run tools/build_source_estimation_split_assignment_readiness_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_split_assignment_readiness_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(
      report['warnings'],
      contains('recent_jma_final_catalog_links_pending:9'),
    );
    expect(
      report['warnings'],
      isNot(
        contains(
          startsWith('split_assignment_ready_cases_require_manual_split:'),
        ),
      ),
    );
    expect(
      report['warnings'],
      isNot(
        contains(
          startsWith(
            'manual_split_recommendation_before_requirements_complete:',
          ),
        ),
      ),
    );

    final summary = report['summary'] as Map<String, Object?>;
    expect(summary['caseCount'], 19);
    expect(summary['readyForFrozenSplitCount'], 7);
    expect(summary['readyForManualSplitAssignmentCount'], 0);
    expect(summary['blockedByManualSplitAssignmentCount'], 11);
    final nextActionCounts = (summary['nextActionCounts'] as Map)
        .cast<String, Object?>();
    expect(nextActionCounts['assign_event_level_split'], isNull);
    expect(
      nextActionCounts['keep_candidate_region_false_recovery_diagnostic_only'],
      1,
    );
    expect(nextActionCounts['review_source_trigger_threshold_effect'], isNull);
    expect(nextActionCounts['split_assignment_complete'], 7);
    expect(nextActionCounts['review_jma_catalog_link'], 3);
    expect(nextActionCounts['keep_plum_like_diagnostic_only'], 6);
    expect(nextActionCounts['review_hinet_preliminary_truth_quality'], 1);
    final recommendationCounts =
        (summary['manualSplitRecommendationCounts'] as Map)
            .cast<String, Object?>();
    expect(recommendationCounts['validation'], 7);
    expect(recommendationCounts['none'], 12);
    final tierCounts = (summary['datasetUseTierCounts'] as Map)
        .cast<String, Object?>();
    expect(tierCounts['strict_ready'], 7);
    expect(tierCounts['diagnostic_ready'], 8);
    expect(tierCounts['metadata_only_or_incomplete'], 4);

    final cases = {
      for (final rawCase in report['cases'] as List)
        (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
    };
    expect(cases.keys, contains('20260625_iwate_offshore_m32_jma'));
    expect(cases.keys, contains('20260622_kushiro_offshore_m30_jma'));
    expect(cases.keys, contains('20260622_fukushima_offshore_m22_eq4'));
    expect(cases.keys, contains('20260620_iwate_offshore_m34_ref'));
    expect(cases.keys, contains('noto_m27_20260621_jma_eq5'));
    expect(cases.keys, contains('20260622_iwate_east_offshore_m30_hinet'));
    expect(
      cases.keys,
      contains('20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21'),
    );
    expect(
      cases.keys,
      contains('20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8'),
    );
    expect(
      cases.keys,
      contains('20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p'),
    );
    expect(cases.keys, contains('20260627_fukushima_aizu_m36_jma_equake17'));
    expect(
      cases.keys,
      contains('20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p'),
    );
    expect(cases.keys, contains('20260628_iwate_offshore_m41_jma'));
    expect(cases.keys, contains('20260622_tomakomai_south_offshore_m35_hinet'));
    expect(
      cases.keys,
      contains('20260623_tokachi_southeast_offshore_m34_hinet'),
    );

    final iwate = cases['20260625_iwate_offshore_m32_jma']!;
    expect(iwate['datasetUseTier'], 'diagnostic_ready');
    expect(iwate['readyForFrozenSplit'], isFalse);
    expect(iwate['catalogOrReviewStatus'], contains('jma_final_catalog'));
    expect(iwate['splitStatus'], 'unassigned_reference');

    final kushiro = cases['20260622_kushiro_offshore_m30_jma']!;
    expect(kushiro['datasetUseTier'], 'diagnostic_ready');
    expect(kushiro['readyForFrozenSplit'], isFalse);
    expect(kushiro['catalogOrReviewStatus'], contains('jma_final_catalog'));

    final fukushimaSmall = cases['20260622_fukushima_offshore_m22_eq4']!;
    expect(fukushimaSmall['datasetUseTier'], 'strict_ready');
    expect(fukushimaSmall['catalogOrReviewStatus'], 'complete');
    expect(fukushimaSmall['captureStatus'], 'complete');
    expect(fukushimaSmall['splitStatus'], 'validation_reference');
    expect(fukushimaSmall['readyForFrozenSplit'], isTrue);
    expect(fukushimaSmall['readyForManualSplitAssignment'], isFalse);
    expect(fukushimaSmall['nextAction'], 'split_assignment_complete');
    final fukushimaRecommendation =
        (fukushimaSmall['manualSplitRecommendation'] as Map)
            .cast<String, Object?>();
    expect(fukushimaRecommendation['suggestedSplit'], 'validation');
    expect(
      fukushimaRecommendation['reason'],
      'small_offshore_reference_only_validation_candidate',
    );
    expect(
      fukushimaRecommendation['constraints'],
      contains('do_not_treat_as_catalog_truth'),
    );

    final iwateM34 = cases['20260620_iwate_offshore_m34_ref']!;
    expect(iwateM34['datasetUseTier'], 'metadata_only_or_incomplete');
    expect(
      iwateM34['datasetUseTierReason'],
      'local_capture_missing_or_has_failed_frames',
    );
    expect(iwateM34['captureStatus'], 'pending');
    expect(iwateM34['readyForManualSplitAssignment'], isFalse);
    expect(iwateM34['nextAction'], 'review_hinet_preliminary_truth_quality');
    expect(iwateM34['manualSplitRecommendation'], isNull);

    for (final caseId in const [
      '20260622_iwate_east_offshore_m30_hinet',
      '20260622_tomakomai_south_offshore_m35_hinet',
      '20260623_tokachi_southeast_offshore_m34_hinet',
      '20260622_iwate_offshore_m30_eq10',
      '20260622_wakayama_south_m25_hinet',
    ]) {
      final accepted = cases[caseId]!;
      expect(accepted['datasetUseTier'], 'strict_ready');
      expect(accepted['catalogOrReviewStatus'], 'complete');
      expect(accepted['captureStatus'], 'complete');
      expect(accepted['splitStatus'], 'validation_reference');
      expect(accepted['readyForFrozenSplit'], isTrue);
      expect(accepted['readyForManualSplitAssignment'], isFalse);
      expect(accepted['nextAction'], 'split_assignment_complete');
      final acceptedConditions = (accepted['conditions'] as List)
          .map((raw) => (raw as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(
        acceptedConditions,
        contains(
          predicate<Map<String, Object?>>(
            (condition) =>
                condition['name'].toString().startsWith('review_hinet') &&
                condition['status'] == 'complete' &&
                condition['reason'] ==
                    'hinet_constrained_reference_review_accepted',
          ),
        ),
        reason: caseId,
      );
    }

    final fukushimaM32 = cases['20260621_fukushima_offshore_m32_eq6']!;
    expect(fukushimaM32['datasetUseTier'], 'diagnostic_ready');
    expect(fukushimaM32['catalogOrReviewStatus'], 'complete');
    expect(fukushimaM32['captureStatus'], 'not_required');
    expect(fukushimaM32['splitStatus'], 'unassigned_reference');
    expect(fukushimaM32['readyForFrozenSplit'], isFalse);
    expect(fukushimaM32['readyForManualSplitAssignment'], isFalse);
    expect(
      fukushimaM32['nextAction'],
      'keep_candidate_region_false_recovery_diagnostic_only',
    );
    final fukushimaM32Conditions = (fukushimaM32['conditions'] as List)
        .map((raw) => (raw as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      fukushimaM32Conditions,
      contains(
        predicate<Map<String, Object?>>(
          (condition) =>
              condition['name'].toString().startsWith('review_hinet') &&
              condition['status'] == 'complete' &&
              condition['reason'] ==
                  'hinet_constrained_reference_review_accepted',
        ),
      ),
    );

    final noto = cases['noto_m27_20260621_jma_eq5']!;
    expect(noto['datasetUseTier'], 'strict_ready');
    expect(noto['captureStatus'], 'complete');
    expect(noto['splitStatus'], 'validation_reference');
    expect(noto['readyForFrozenSplit'], isTrue);
    expect(noto['readyForManualSplitAssignment'], isFalse);
    expect(noto['nextAction'], 'split_assignment_complete');
    final notoRecommendation = (noto['manualSplitRecommendation'] as Map)
        .cast<String, Object?>();
    expect(notoRecommendation['suggestedSplit'], 'validation');
    expect(
      notoRecommendation['constraints'],
      containsAll([
        'keep_include_in_detection_metrics_false',
        'do_not_treat_as_catalog_truth',
        'do_not_use_for_final_test_claims',
        'physical_fusion_diagnostic_only',
        'preserve_historical_fetch_warning',
      ]),
    );
    final notoConditions = (noto['conditions'] as List)
        .map((raw) => (raw as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      notoConditions,
      contains(
        predicate<Map<String, Object?>>(
          (condition) =>
              condition['name'] == 'review_source_trigger_threshold_effect' &&
              condition['status'] == 'complete' &&
              condition['reason'] == 'source_trigger_threshold_review_cleared',
        ),
      ),
    );

    for (final entry in cases.values) {
      final conditions = (entry['conditions'] as List)
          .map((raw) => (raw as Map).cast<String, Object?>())
          .toList(growable: false);
      final expectedSplitStatus =
          entry['caseId'] == '20260622_fukushima_offshore_m22_eq4' ||
              entry['caseId'] == '20260622_iwate_east_offshore_m30_hinet' ||
              entry['caseId'] == '20260622_iwate_offshore_m30_eq10' ||
              entry['caseId'] ==
                  '20260622_tomakomai_south_offshore_m35_hinet' ||
              entry['caseId'] == '20260622_wakayama_south_m25_hinet' ||
              entry['caseId'] ==
                  '20260623_tokachi_southeast_offshore_m34_hinet' ||
              entry['caseId'] == 'noto_m27_20260621_jma_eq5'
          ? 'complete'
          : 'pending';
      if (entry['caseId'] == '20260621_fukushima_offshore_m32_eq6') {
        expect(
          conditions,
          isNot(
            contains(
              predicate<Map<String, Object?>>(
                (condition) => condition['name'] == 'assign_event_level_split',
              ),
            ),
          ),
          reason: entry['caseId'] as String,
        );
        continue;
      }
      expect(
        conditions,
        contains(
          predicate<Map<String, Object?>>(
            (condition) =>
                condition['name'] == 'assign_event_level_split' &&
                condition['status'] == expectedSplitStatus,
          ),
        ),
        reason: entry['caseId'] as String,
      );
    }
  });
}
