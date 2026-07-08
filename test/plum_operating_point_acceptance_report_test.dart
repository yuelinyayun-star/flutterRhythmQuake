import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_operating_point_acceptance_report.dart';

void main() {
  test('PLUM operating-point acceptance stays diagnostic-only', () {
    final temp = Directory.systemTemp.createTempSync('plum_acceptance_test_');
    addTearDown(() => temp.deleteSync(recursive: true));

    final combined = File('${temp.path}/combined.json')
      ..writeAsStringSync(
        jsonEncode({
          'status': 'pass',
          'methods': {
            'max_jma_style_plum_like': {
              'thresholds': {
                'shindo4': _threshold(precision: 0.50, recall: 0.83, f1: 0.62),
                'shindo5-': _threshold(precision: 0.44, recall: 0.68, f1: 0.53),
              },
            },
            'max_jma_style_plum_like_r20_d0_50': {
              'thresholds': {
                'shindo4': _threshold(precision: 0.56, recall: 0.72, f1: 0.63),
                'shindo5-': _threshold(precision: 0.59, recall: 0.46, f1: 0.51),
              },
            },
            'max_jma_style_plum_like_r30_d0_50': {
              'thresholds': {
                'shindo4': _threshold(precision: 0.56, recall: 0.73, f1: 0.64),
                'shindo5-': _threshold(precision: 0.59, recall: 0.47, f1: 0.52),
              },
            },
          },
        }),
      );
    final replayJson = {
      'status': 'pass',
      'summary': {'caseCount': 7, 'decodedFrameCount': 1201},
      'tuningGridComparison': {
        'r30_d0.25_baseline': {
          'shindo4': _replay(recall: 0.84, falseAlarms: 27),
          'shindo5-': _replay(recall: 0.50, falseAlarms: 19),
        },
        'r20_d0.50': {
          'shindo4': _replay(recall: 0.56, falseAlarms: 14),
          'shindo5-': _replay(recall: 0.25, falseAlarms: 5),
        },
        'r30_d0.50': {
          'shindo4': _replay(recall: 0.63, falseAlarms: 17),
          'shindo5-': _replay(recall: 0.25, falseAlarms: 5),
        },
      },
    };
    final replay = File('${temp.path}/replay.json')
      ..writeAsStringSync(jsonEncode(replayJson));

    final report = buildPlumOperatingPointAcceptanceReportJson(
      combinedReportPath: combined.path,
      replayReportPath: replay.path,
    );

    expect(report['schemaVersion'], 'plum_operating_point_acceptance_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['recommendedDiagnosticCandidate'], 'plum_like_r30_d0_50');

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['selectedForProduction'], isFalse);

    final candidates = (report['candidates'] as List)
        .map((raw) => (raw as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(candidates.first['acceptanceStatus'], 'warn');
    expect(candidates.last['acceptanceStatus'], 'pass');

    final markdown = plumOperatingPointAcceptanceMarkdown(report);
    expect(markdown, contains('PLUM Operating-Point Acceptance Diagnostic'));
    expect(markdown, contains('diagnostic-only'));

    replayJson['summary'] = {'caseCount': 6, 'decodedFrameCount': 906};
    replay.writeAsStringSync(jsonEncode(replayJson));
    final lowCoverage = buildPlumOperatingPointAcceptanceReportJson(
      combinedReportPath: combined.path,
      replayReportPath: replay.path,
    );
    expect(lowCoverage['recommendedDiagnosticCandidate'], isNull);
    final lowCoverageCandidates = (lowCoverage['candidates'] as List)
        .map((raw) => (raw as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      lowCoverageCandidates
          .where((entry) => entry['candidateId'] != 'plum_like')
          .map((entry) => (entry['checks'] as Map)['replayCoverage']),
      everyElement(false),
    );
  });
}

Map<String, Object?> _threshold({
  required double precision,
  required double recall,
  required double f1,
}) => {'precision': precision, 'recall': recall, 'f1': f1};

Map<String, Object?> _replay({
  required double recall,
  required int falseAlarms,
}) => {
  'stationRecall': recall,
  'falseAlarmStationCount': falseAlarms,
  'stationFalseAlarmRatio': 0.0,
};
