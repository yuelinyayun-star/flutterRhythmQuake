import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

import '../tools/build_jma_style_intensity_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JMA-style predictor follows PGV intensity formula', () {
    const predictor = JmaStyleIntensityPredictor();
    final pgv600 = predictor.pgv600FromJmaMagnitude(
      magnitude: 5.0,
      depthKm: 20.0,
      distanceKm: 40.0,
    );
    final surfacePgv = predictor.surfacePgvFromPgv600(
      pgv600: pgv600,
      amplification: 1.5,
    );
    final intensity = predictor.instrumentalIntensityFromSurfacePgv(surfacePgv);

    expect(pgv600, greaterThan(0));
    expect(surfacePgv, closeTo(pgv600 * 1.5 * 0.90, 1e-9));
    expect(intensity.isFinite, isTrue);
  });

  test(
    'JMA-style report remains diagnostic-only',
    () {
      final report = buildJmaStyleIntensityReportJson();

      expect(report['schemaVersion'], 'jma_style_intensity_report_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['plumIncluded'], isFalse);
      expect(policy['sourceSemantics'], contains('oracle catalog source'));

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect((summary['caseCount'] as int), greaterThan(0));
      expect((summary['stationForecastCount'] as int), greaterThan(0));
      expect(summary['stationIntensityMae'], isA<double>());

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(
        thresholds.keys,
        containsAll(['shindo1', 'shindo2', 'shindo3', 'shindo4', 'shindo5-']),
      );

      final markdown = jmaStyleIntensityReportMarkdown(report);
      expect(markdown, contains('JMA-style traditional'));
      expect(markdown, contains('oracle-source diagnostic'));
      expect(markdown, contains('PLUM included: `false`'));

      final output = File('.dart_tool/jma_style_intensity/report.json')
        ..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/jma_style_intensity.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
