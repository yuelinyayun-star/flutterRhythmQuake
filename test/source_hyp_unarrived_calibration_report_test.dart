import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hyp_unarrived_calibration_report.dart';

void main() {
  test('unarrived calibration recommends safe support threshold', () {
    final temp = Directory.systemTemp.createTempSync(
      'source_hyp_unarrived_calibration_test_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final input = File('${temp.path}${Platform.pathSeparator}hyp_vs_hybrid.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 'source_hyp_vs_hybrid_report_v1',
          'rows': [_row('good_low', hybridError: 12, hypError: 4, p: 4, s: 5, residual: 0.8, pair: 0.9, unarrived: 2), _row('good_mid', hybridError: 10, hypError: 5, p: 5, s: 7, residual: 1.1, pair: 1.0, unarrived: 40), _row('bad_high', hybridError: 8, hypError: 95, p: 8, s: 2, residual: 1.0, pair: 0.8, unarrived: 120), _row('no_s', hybridError: 20, hypError: 100, p: 8, s: 0, residual: 1.0, pair: 0.8, unarrived: 1)],
        })}\n',
      );

    final report = buildSourceHypUnarrivedCalibrationReportJson(
      inputFile: input,
    );

    expect(
      report['schemaVersion'],
      'source_hyp_unarrived_calibration_report_v1',
    );
    expect(report['status'], 'pass');
    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['productionCoordinateSwitchAllowed'], isFalse);
    expect(policy['doesNotChangeCandidateSearch'], isTrue);

    final recommendation = (report['recommendation'] as Map)
        .cast<String, Object?>();
    expect(recommendation['threshold'], 40.0);
    expect(recommendation['supportedCount'], 2);
    expect(recommendation['reason'], 'max_supported_without_large_regression');

    final thresholds = {
      for (final raw in report['thresholds'] as List)
        (raw as Map)['threshold'] as double: raw.cast<String, Object?>(),
    };
    expect(thresholds[0.0]!['verdict'], 'too_strict');
    expect(thresholds[40.0]!['verdict'], 'safe');
    expect(thresholds[120.0]!['verdict'], 'unsafe');
    expect(thresholds[120.0]!['regressedCaseIds'], contains('bad_high'));

    final findings = (report['findings'] as List).cast<String>();
    expect(findings, contains('recommended_threshold_40'));
    expect(
      findings,
      contains('high_thresholds_admit_regressed_hyp_candidates'),
    );
    expect(findings, contains('low_thresholds_are_too_strict'));
    expect(findings, contains('calibration_is_gate_only_not_search_weight'));

    final markdown = sourceHypUnarrivedCalibrationMarkdown(report);
    expect(markdown, contains('# HYP unarrived-penalty calibration report'));
    expect(markdown, contains('Recommended max unarrived penalty'));
  });
}

Map<String, Object?> _row(
  String caseId, {
  required double hybridError,
  required double hypError,
  required int p,
  required int s,
  required double residual,
  required double pair,
  required double unarrived,
}) {
  return {
    'caseId': caseId,
    'hybridFinalErrorKm': hybridError,
    'hypFinalErrorKm': hypError,
    'hypPhasePCount': p,
    'hypPhaseSCount': s,
    'hypPhaseMeanResidualSeconds': residual,
    'hypPairMeanResidualSeconds': pair,
    'hypUnarrivedPenalty': unarrived,
  };
}
