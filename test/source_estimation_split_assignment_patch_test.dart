import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_split_assignment_patch.dart'
    as split_patch_tool;

void main() {
  test(
    'split assignment patch script regenerates dry-run report before test',
    () {
      final script = File(
        'tools/validate_source_estimation_split_assignment_patch.ps1',
      ).readAsStringSync();

      expect(script, contains("\$ErrorActionPreference = 'Stop'"));
      expect(
        script,
        contains('build_source_estimation_split_assignment_patch.dart'),
      );
      expect(
        script,
        contains('source_estimation_split_assignment_patch_test.dart'),
      );
      expect(
        script.indexOf('build_source_estimation_split_assignment_patch.dart'),
        lessThan(
          script.indexOf('source_estimation_split_assignment_patch_test.dart'),
        ),
      );
    },
  );

  test('split assignment patch is idempotent after applying recommendation', () {
    final reportFile = File(
      '.dart_tool/source_estimation_split_assignment_patch/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing split assignment patch report. Run '
        '`dart run tools/build_source_estimation_split_assignment_patch.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_split_assignment_patch_v1',
    );
    expect(report['status'], 'pass');
    expect(report['applyRequested'], isFalse);
    expect(report['errors'], isEmpty);
    expect(report['warnings'], isEmpty);

    final summary = report['summary'] as Map<String, Object?>;
    expect(summary['proposalCount'], 7);
    expect(summary['readyToApplyCount'], 0);
    expect(summary['alreadyAppliedCount'], 7);
    expect(summary['blockedCount'], 0);

    final proposals = (report['proposals'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(proposals, hasLength(7));
    final byCaseId = {
      for (final proposal in proposals) proposal['caseId'] as String: proposal,
    };

    final fukushima = byCaseId['20260622_fukushima_offshore_m22_eq4']!;
    expect(
      fukushima['fixtureFileName'],
      'fukushima_offshore_m22_20260622_eq4.json',
    );
    expect(fukushima['status'], 'already_applied');
    expect(fukushima['suggestedSplit'], 'validation');
    expect(fukushima['proposedFixtureSplitStatus'], 'validation_reference');
    expect(fukushima['existingSplit'], 'validation');
    expect(fukushima['violations'], isEmpty);
    expect(fukushima['actions'], isEmpty);
    expect(
      fukushima['constraints'],
      containsAll([
        'keep_include_in_detection_metrics_false',
        'do_not_treat_as_catalog_truth',
        'do_not_use_for_final_test_claims',
      ]),
    );

    final noto = byCaseId['noto_m27_20260621_jma_eq5']!;
    expect(noto['fixtureFileName'], 'noto_m27_20260621_jma_eq5.json');
    expect(noto['status'], 'already_applied');
    expect(noto['suggestedSplit'], 'validation');
    expect(noto['proposedFixtureSplitStatus'], 'validation_reference');
    expect(noto['existingSplit'], 'validation');
    expect(noto['violations'], isEmpty);
    expect(noto['actions'], isEmpty);
    expect(
      noto['constraints'],
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
      final hinet = byCaseId[caseId]!;
      expect(hinet['status'], 'already_applied', reason: caseId);
      expect(hinet['suggestedSplit'], 'validation', reason: caseId);
      expect(
        hinet['proposedFixtureSplitStatus'],
        'validation_reference',
        reason: caseId,
      );
      expect(hinet['existingSplit'], 'validation', reason: caseId);
      expect(hinet['violations'], isEmpty, reason: caseId);
      expect(hinet['actions'], isEmpty, reason: caseId);
      expect(
        hinet['constraints'],
        containsAll([
          'hinet_constrained_reference_only',
          'do_not_treat_as_catalog_truth',
          'do_not_use_for_final_test_claims',
        ]),
        reason: caseId,
      );
    }
  });

  test(
    'split assignment patch apply updates only the requested temp files',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'source_split_assignment_patch_',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final fixtureDir = Directory('${temp.path}/fixtures')..createSync();
      final splitFile = File('${fixtureDir.path}/dataset_splits.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            'datasetId': 'source_estimation_p1_test',
            'frozenAt': '2026-06-20',
            'splitPolicy': 'event-level split',
            'splits': {'train': <String>[], 'validation': <String>[], 'test': <String>[]},
          })}\n',
        );
      final fixtureFile =
          File(
            '${fixtureDir.path}/fukushima_offshore_m22_20260622_eq4.json',
          )..writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'caseId': '20260622_fukushima_offshore_m22_eq4', 'caseType': 'event', 'splitStatus': 'unassigned_reference'})}\n',
          );
      final planFile = File('${temp.path}/plan.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 'source_estimation_split_assignment_plan_v1',
            'cases': [
              {
                'caseId': '20260622_fukushima_offshore_m22_eq4',
                'currentStatus': 'unassigned_reference',
                'plannedUse': 'small_offshore_reference_pool',
                'requiredBeforeFrozenSplit': ['assign_event_level_split'],
                'manualSplitRecommendation': {
                  'suggestedSplit': 'validation',
                  'reason': 'small_offshore_reference_only_validation_candidate',
                  'constraints': ['keep_include_in_detection_metrics_false', 'do_not_treat_as_catalog_truth', 'do_not_use_for_final_test_claims'],
                },
              },
            ],
          })}\n',
        );
      final outputFile = File('${temp.path}/report.json');
      final markdownFile = File('${temp.path}/report.md');

      split_patch_tool.main([
        '--split',
        splitFile.path,
        '--plan',
        planFile.path,
        '--fixture-directory',
        fixtureDir.path,
        '--output',
        outputFile.path,
        '--markdown',
        markdownFile.path,
        '--apply',
      ]);

      final report =
          jsonDecode(outputFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['applyRequested'], isTrue);
      final proposal = ((report['proposals'] as List).single as Map)
          .cast<String, Object?>();
      expect(proposal['status'], 'ready_to_apply');

      final updatedSplit =
          jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
      final splits = (updatedSplit['splits'] as Map).cast<String, Object?>();
      expect(
        splits['validation'],
        contains('fukushima_offshore_m22_20260622_eq4.json'),
      );
      expect(splits['train'], isEmpty);
      expect(splits['test'], isEmpty);

      final updatedFixture =
          jsonDecode(fixtureFile.readAsStringSync()) as Map<String, Object?>;
      expect(updatedFixture['splitStatus'], 'validation_reference');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
