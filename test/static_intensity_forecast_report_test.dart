import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_static_intensity_forecast_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'static intensity forecast report remains validation-only',
    () {
      final report = buildStaticIntensityForecastValidationJson();

      expect(
        report['schemaVersion'],
        'static_intensity_forecast_validation_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(
        policy['temporalSemantics'],
        contains('not realtime observed intensity'),
      );

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect((summary['caseCount'] as int), greaterThan(0));
      expect((summary['stationForecastCount'] as int), greaterThan(0));
      expect(summary['maxClassMae'], isA<double>());
      expect(summary['stationIntensityMae'], isA<double>());

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(
        thresholds.keys,
        containsAll(['shindo1', 'shindo2', 'shindo3', 'shindo4', 'shindo5-']),
      );

      final markdown = staticIntensityForecastValidationMarkdown(report);
      expect(markdown, contains('validation-only forecast metric report'));
      expect(markdown, contains('must not be described as realtime'));
      expect(markdown, contains('Frozen test remains unopened'));

      final output = File(
        '.dart_tool/static_intensity_forecast_validation/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/static_intensity_forecast_validation.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
