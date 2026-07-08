import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_frozen_test_acceptance_criteria_report.dart';

void main() {
  test('PLUM frozen-test criteria freeze candidate without evaluation', () {
    final temp = Directory.systemTemp.createTempSync('plum_frozen_criteria_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final operatingPointReport = File('${temp.path}/operating_point.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'plum_operating_point_acceptance_v1',
          'status': 'pass',
          'policy': {
            'frozenTestEvaluated': false,
            'productionReady': false,
            'productionUiConnected': false,
            'selectedForProduction': false,
          },
          'recommendedDiagnosticCandidate': 'plum_like_r30_d0_50',
          'candidates': [
            {
              'candidateId': 'plum_like_r30_d0_50',
              'maxMethodId': 'max_jma_style_plum_like_r30_d0_50',
              'replayKey': 'r30_d0.50',
              'acceptanceStatus': 'pass',
              'replayShindo5Minus': {'recall': 0.25},
            },
          ],
        }),
      );

    final report = buildPlumFrozenTestAcceptanceCriteriaReportJson(
      operatingPointReportPath: operatingPointReport.path,
    );

    expect(report['schemaVersion'], 'plum_frozen_test_acceptance_criteria_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['selectedForProduction'], isFalse);
    expect(policy['sourceEstimationCoordinateSwitchAllowed'], isFalse);

    final selected = (report['selectedOperatingPoint'] as Map)
        .cast<String, Object?>();
    expect(selected['candidateId'], 'plum_like_r30_d0_50');
    expect(selected['radiusKm'], 30.0);
    expect(selected['dampingPer10Km'], 0.50);
    expect(selected['surfaceInputOnly'], isTrue);

    final decision = (report['decision'] as Map).cast<String, Object?>();
    expect(decision['readyToRunFrozenEvaluation'], isTrue);
    expect(decision['advanceToProduction'], isFalse);

    final markdown = plumFrozenTestAcceptanceCriteriaMarkdown(report);
    expect(markdown, contains('PLUM Frozen-Test Acceptance Criteria'));
    expect(markdown, contains('Frozen test evaluated: `false`'));
    expect(markdown, contains('Ready to run frozen evaluation: `true`'));
  });
}
