import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_confidence_gate_acceptance_report.dart';

void main() {
  test('PLUM confidence acceptance triage requires manual replay decision', () {
    final temp = Directory.systemTemp.createTempSync('plum_conf_accept_');
    addTearDown(() => temp.deleteSync(recursive: true));

    final confidence = File('${temp.path}/confidence.json')
      ..writeAsStringSync(jsonEncode(_confidenceReport()));
    final replay = File('${temp.path}/replay.json')
      ..writeAsStringSync(jsonEncode(_replayReport()));

    final report = buildPlumConfidenceGateAcceptanceReportJson(
      confidenceReportPath: confidence.path,
      replayReportPath: replay.path,
    );

    expect(report['schemaVersion'], 'plum_confidence_gate_acceptance_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['rawIntensityFieldMutated'], isFalse);

    final decision = (report['decision'] as Map).cast<String, Object?>();
    expect(decision['status'], 'warn');
    expect(decision['readyForFrozenCriteria'], isFalse);
    expect(decision['requiresManualDecision'], isTrue);

    final markdown = plumConfidenceGateAcceptanceMarkdown(report);
    expect(markdown, contains('PLUM Confidence Gate Acceptance Triage'));
    expect(markdown, contains('Ready for frozen criteria: `false`'));
    expect(markdown, contains('Do not open frozen test'));

    final replayJson = _replayReport();
    replayJson['summary'] = {'caseCount': 6, 'decodedFrameCount': 906};
    replay.writeAsStringSync(jsonEncode(replayJson));
    final lowCoverage = buildPlumConfidenceGateAcceptanceReportJson(
      confidenceReportPath: confidence.path,
      replayReportPath: replay.path,
    );
    final lowCoverageDecision = (lowCoverage['decision'] as Map)
        .cast<String, Object?>();
    expect(lowCoverageDecision['status'], 'fail');
    expect(
      lowCoverageDecision['notes'],
      contains('replay_coverage_below_minimum'),
    );
  });
}

Map<String, Object?> _confidenceReport() => {
  'schemaVersion': 'plum_confidence_gate_report_v1',
  'policy': {'frozenTestEvaluated': false, 'rawIntensityFieldMutated': false},
  'recommendedForReplayValidation': 'plum_r20_d0_50_only',
  'evaluations': [
    {
      'gateId': 'baseline_raw_threshold',
      'thresholds': {
        'shindo4': {'precision': 0.55, 'recall': 0.72, 'f1': 0.63},
      },
    },
    {
      'gateId': 'plum_r20_d0_50_only',
      'thresholds': {
        'shindo4': {'precision': 0.69, 'recall': 0.61, 'f1': 0.65},
      },
    },
  ],
};

Map<String, Object?> _replayReport() => {
  'schemaVersion': 'plum_like_replay_leadtime_report_v1',
  'policy': {'frozenTestEvaluated': false},
  'summary': {'caseCount': 7, 'decodedFrameCount': 1201},
  'tuningGridComparison': {
    'r30_d0.50': {
      'shindo4': {'stationRecall': 0.625, 'falseAlarmStationCount': 17},
    },
    'r20_d0.50': {
      'shindo4': {'stationRecall': 0.563, 'falseAlarmStationCount': 14},
    },
  },
};
