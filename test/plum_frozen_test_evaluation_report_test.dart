import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_frozen_test_acceptance_criteria_report.dart';
import '../tools/build_plum_frozen_test_evaluation_report.dart';

void main() {
  test(
    'PLUM frozen-test evaluation runs once without production promotion',
    () {
      final criteria = buildPlumFrozenTestAcceptanceCriteriaReportJson();
      File('.dart_tool/plum_frozen_test_acceptance_criteria/report.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(criteria)}\n',
        );

      final report = buildPlumFrozenTestEvaluationReportJson();

      expect(report['schemaVersion'], 'plum_frozen_test_evaluation_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'test');
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['selectedForProduction'], isFalse);

      final selected = (report['selectedOperatingPoint'] as Map)
          .cast<String, Object?>();
      expect(selected['candidateId'], 'plum_like_r30_d0_50');

      final summary = (report['combinedSummary'] as Map)
          .cast<String, Object?>();
      expect((summary['caseCount'] as int), greaterThan(0));

      final outcome = (report['outcome'] as Map).cast<String, Object?>();
      expect(outcome['advanceToProduction'], isFalse);
      expect(outcome['frozenEvaluationStatus'], anyOf('pass', 'warn', 'fail'));

      final markdown = plumFrozenTestEvaluationMarkdown(report);
      expect(markdown, contains('PLUM Frozen-Test Evaluation'));
      expect(markdown, contains('Frozen test evaluated: `true`'));
      expect(markdown, contains('Production ready: `false`'));

      File('.dart_tool/plum_frozen_test_evaluation/report.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      File('docs/baselines/plum_frozen_test_evaluation.generated.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
