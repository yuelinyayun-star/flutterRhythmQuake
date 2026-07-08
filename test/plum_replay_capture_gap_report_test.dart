import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_replay_capture_gap_report.dart';

void main() {
  test('PLUM replay capture gap report isolates incomplete captures', () {
    final report = buildPlumReplayCaptureGapReportJson(
      nowJst: DateTime(2026, 6, 29, 7, 51),
    );

    expect(report['schemaVersion'], 'plum_replay_capture_gap_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['repairsCaptures'], isFalse);
    expect(policy['excludesCaptures'], isFalse);
    expect(policy['recordsExclusionDecisions'], isTrue);
    expect(policy['changesReplayMetrics'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 7);
    expect(summary['completeCaseCount'], 6);
    expect(summary['totalGapCaseCount'], 1);
    expect(summary['gapCaseCount'], 0);
    expect(summary['excludedGapCaseCount'], 1);
    expect(summary['failedGifCount'], 0);
    expect(summary['excludedFailedGifCount'], 16);
    expect(summary['totalFailedGifCount'], 16);

    final gapCases = (report['gapCases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(gapCases, isEmpty);
    final excludedGapCases = (report['excludedGapCases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(excludedGapCases, hasLength(1));
    final yamanashiM33 = excludedGapCases.single;
    expect(
      yamanashiM33['caseId'],
      '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
    );
    expect(yamanashiM33['expectedGifCount'], 302);
    expect(yamanashiM33['downloadedGifCount'], 286);
    expect(yamanashiM33['failedGifCount'], 16);
    expect(yamanashiM33['originTimeJst'], '2026-06-26T23:17:46');
    expect(yamanashiM33['repairWindowStatus'], 'expired_over_3h');
    expect(
      yamanashiM33['recommendedAction'],
      'excluded_from_complete_replay_metrics',
    );
    expect((yamanashiM33['failedRecords'] as List), hasLength(16));
    final exclusionDecision = (yamanashiM33['exclusionDecision'] as Map)
        .cast<String, Object?>();
    expect(exclusionDecision['exclusionApproved'], isTrue);
    expect(
      exclusionDecision['decisionStatus'],
      'capture_gap_exclusion_approved',
    );
    expect((exclusionDecision['excludedFiles'] as List), hasLength(16));

    final completeCaseIds = (report['completeCases'] as List)
        .map((entry) => (entry as Map)['caseId'])
        .toSet();
    expect(
      completeCaseIds,
      contains('20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21'),
    );

    final markdown = plumReplayCaptureGapMarkdown(report);
    expect(markdown, contains('PLUM Replay Capture Gap Report'));
    expect(markdown, contains('Unresolved gap cases: `0`'));
    expect(markdown, contains('Excluded gap cases: `1`'));
    expect(markdown, contains('capture_gap_exclusion_approved'));

    final output = File('.dart_tool/plum_replay_capture_gap/report.json')
      ..parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    final markdownFile = File(
      'docs/baselines/plum_replay_capture_gap.generated.md',
    )..parent.createSync(recursive: true);
    markdownFile.writeAsStringSync(markdown);
  });
}
