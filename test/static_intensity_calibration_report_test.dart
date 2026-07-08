import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_static_intensity_calibration_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'static intensity calibration report remains diagnostic-only',
    () {
      final report = buildStaticIntensityCalibrationJson();

      expect(report['schemaVersion'], 'static_intensity_calibration_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(
        policy['calibrationType'],
        'global_additive_intensity_offset_scan',
      );

      final baseline = (report['baselineOffset'] as Map)
          .cast<String, Object?>();
      final recommended = (report['recommendedDiagnosticOffset'] as Map)
          .cast<String, Object?>();
      expect(baseline['offset'], 0.0);
      expect(recommended['offset'], isA<double>());
      expect(recommended['caseCount'], baseline['caseCount']);
      expect(
        recommended['stationForecastCount'],
        baseline['stationForecastCount'],
      );

      final offsets = (report['offsets'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(offsets.length, greaterThanOrEqualTo(10));
      expect(
        offsets.map((entry) => entry['offset']),
        containsAll([-1.0, -0.5, 0.0, 0.5]),
      );

      for (final row in offsets) {
        final thresholds = (row['thresholds'] as Map).cast<String, Object?>();
        expect(
          thresholds.keys,
          containsAll(['shindo1', 'shindo2', 'shindo3', 'shindo4', 'shindo5-']),
        );
      }

      final markdown = staticIntensityCalibrationMarkdown(report);
      expect(markdown, contains('validation-only'));
      expect(markdown, contains('not realtime lead-time validation'));
      expect(markdown, contains('must not be consumed by production'));

      final output = File('.dart_tool/static_intensity_calibration/report.json')
        ..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/static_intensity_calibration.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
