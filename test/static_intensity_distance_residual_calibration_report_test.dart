import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_static_intensity_distance_residual_calibration_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'distance residual calibration report stays diagnostic-only',
    () {
      final report = buildStaticIntensityDistanceResidualCalibrationJson();

      expect(
        report['schemaVersion'],
        'static_intensity_distance_residual_calibration_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['calibrationType'], 'station_distance_residual_correction');

      final summary = (report['summary'] as Map).cast<String, Object?>();
      final baseline = (summary['baseline'] as Map).cast<String, Object?>();
      final farDistance = (summary['farDistanceCorrected'] as Map)
          .cast<String, Object?>();
      expect(farDistance['caseCount'], baseline['caseCount']);
      expect(
        farDistance['stationForecastCount'],
        baseline['stationForecastCount'],
      );

      final distanceBuckets = (report['distanceBuckets'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(
        distanceBuckets.map((entry) => entry['bucket']),
        containsAll(['0_50km', '50_100km', '100_200km', 'gt_200km']),
      );
      final farBucket = distanceBuckets.singleWhere(
        (entry) => entry['bucket'] == 'gt_200km',
      );
      expect((farBucket['correction'] as num).toDouble(), lessThan(0));
      expect(farBucket['targetedCorrection'], farBucket['correction']);

      final markdown = staticIntensityDistanceResidualCalibrationMarkdown(
        report,
      );
      expect(markdown, contains('validation-only'));
      expect(markdown, contains('gt_200km'));
      expect(markdown, contains('must not be applied to runtime'));

      final output = File(
        '.dart_tool/static_intensity_distance_residual_calibration/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/static_intensity_distance_residual_calibration.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
