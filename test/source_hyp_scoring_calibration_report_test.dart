import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hyp_scoring_calibration_report.dart';

void main() {
  test('HYP scoring calibration markdown documents diagnostic policy', () {
    final report = {
      'schemaVersion': 'source_hyp_scoring_calibration_report_v1',
      'status': 'pass',
      'policy': {
        'diagnosticOnly': true,
        'productionCoordinateSwitchAllowed': false,
        'referenceAlgorithmInput': 'nied_kmoni_gif_reverse_decoded',
        'calibrates': 'hyp_candidate_search_scoring_not_support_gate',
        'historicalGifRedownload': false,
      },
      'variants': [
        {
          'variantId': 'baseline',
          'description': 'Current HYP diagnostic scoring.',
          'summary': {
            'caseCount': 2,
            'supportedCount': 1,
            'depthSupportedCount': 1,
            'improvedCount': 1,
            'regressedCount': 0,
            'medianHypErrorKm': 8.0,
            'medianSupportedHypErrorKm': 3.0,
            'medianDeltaKm': -4.0,
            'pOnlyFinalRowCount': 1,
          },
          'rows': [
            {
              'caseId': 'supported_case',
              'hybridFinalErrorKm': 12.0,
              'hypFinalErrorKm': 3.0,
              'hypMinusHybridFinalErrorKm': -9.0,
              'hypSupported': true,
              'hypDepthSupported': true,
              'hypPhasePCount': 4,
              'hypPhaseSCount': 5,
              'hypPhaseOtherCount': 0,
              'hypPhaseMeanResidualSeconds': 0.8,
              'hypPairMeanResidualSeconds': 0.9,
              'hypUnarrivedPenalty': 2.0,
              'hypDepthKm': 40.0,
            },
          ],
        },
      ],
      'findings': [
        'candidate_search_calibration_only',
        'keep_hyp_diagnostic_until_variant_beats_hybrid_reliably',
      ],
    };

    final markdown = sourceHypScoringCalibrationMarkdown(report);

    expect(markdown, contains('# HYP scoring calibration report'));
    expect(markdown, contains('Historical GIF redownload: `false`'));
    expect(markdown, contains('baseline'));
    expect(markdown, contains('supported_case'));
    expect(markdown, contains('candidate_search_calibration_only'));
  });

  test(
    'optionally generates local HYP scoring calibration report',
    () async {
      const generate = bool.fromEnvironment('SOURCE_HYP_SCORING_GENERATE');
      if (!generate) return;

      final report = await buildSourceHypScoringCalibrationReportJson();
      final output = File(
        '.dart_tool/source_hyp_scoring_calibration_report/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdown = File(
        'docs/baselines/source_hyp_scoring_calibration_report.generated.md',
      )..parent.createSync(recursive: true);
      markdown.writeAsStringSync(sourceHypScoringCalibrationMarkdown(report));

      expect(report['status'], 'pass');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
