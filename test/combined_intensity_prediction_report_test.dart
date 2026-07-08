import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_combined_intensity_prediction_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'combined intensity report remains validation-only diagnostic',
    () {
      final report = buildCombinedIntensityPredictionReportJson();

      expect(
        report['schemaVersion'],
        'combined_intensity_prediction_report_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['sourceSemantics'], contains('PLUM-like branch'));

      final methods = (report['methods'] as Map).cast<String, Object?>();
      expect(
        methods.keys,
        containsAll([
          'p3_static_raw',
          'jma_style_p3_source',
          'plum_like',
          'plum_like_r20_d0_50',
          'plum_like_r30_d0_50',
          'max_jma_style_plum_like',
          'max_jma_style_plum_like_r20_d0_50',
          'max_jma_style_plum_like_r30_d0_50',
        ]),
      );

      final candidates = (report['plumOperatingPointCandidates'] as Map)
          .cast<String, Object?>();
      expect(
        candidates.keys,
        containsAll([
          'plum_like',
          'plum_like_r20_d0_50',
          'plum_like_r30_d0_50',
        ]),
      );
      expect(
        (candidates['plum_like_r30_d0_50'] as Map)['diagnosticOnly'],
        isTrue,
      );
      expect(
        (candidates['plum_like_r30_d0_50'] as Map)['selectedForProduction'],
        isFalse,
      );

      final combined = (methods['max_jma_style_plum_like'] as Map)
          .cast<String, Object?>();
      final summary = (combined['summary'] as Map).cast<String, Object?>();
      expect((summary['caseCount'] as int), greaterThan(0));
      expect((summary['stationForecastCount'] as int), greaterThan(0));

      final thresholds = (combined['thresholds'] as Map)
          .cast<String, Object?>();
      expect(thresholds.keys, containsAll(['shindo3', 'shindo4', 'shindo5-']));

      final gate = (report['probabilityGate'] as Map).cast<String, Object?>();
      expect(gate.keys, containsAll(['shindo3', 'shindo4', 'shindo5-']));

      final markdown = combinedIntensityPredictionMarkdown(report);
      expect(markdown, contains('Combined Intensity Prediction Diagnostic'));
      expect(markdown, contains('max(JMA-style, PLUM-like)'));
      expect(markdown, contains('Production UI connected: `false`'));

      final output = File(
        '.dart_tool/combined_intensity_prediction/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/combined_intensity_prediction.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
