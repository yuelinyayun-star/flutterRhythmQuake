import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_static_intensity_stratified_calibration_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'static intensity stratified calibration report stays diagnostic-only',
    () {
      final report = buildStaticIntensityStratifiedCalibrationJson();

      expect(
        report['schemaVersion'],
        'static_intensity_stratified_calibration_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(
        policy['calibrationType'],
        'predicted_max_class_and_location_uncertainty_stratified_offset_scan',
      );

      final summary = (report['summary'] as Map).cast<String, Object?>();
      final baseline = (summary['baseline'] as Map).cast<String, Object?>();
      final stratified = (summary['stratified'] as Map).cast<String, Object?>();
      expect((summary['totalStrata'] as int), greaterThan(0));
      expect((summary['changedStrata'] as int), greaterThanOrEqualTo(0));
      expect(stratified['caseCount'], baseline['caseCount']);
      expect(
        stratified['stationForecastCount'],
        baseline['stationForecastCount'],
      );

      final strata = (report['strata'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(strata, isNotEmpty);
      expect(
        strata.first.keys,
        containsAll(['key', 'selectedOffset', 'baseline', 'selected']),
      );

      final distanceDiagnostics = (report['stationDistanceDiagnostics'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(distanceDiagnostics, isNotEmpty);
      expect(
        distanceDiagnostics.map((entry) => entry['bucket']),
        containsAll(['0_50km', '50_100km', '100_200km', 'gt_200km']),
      );

      final markdown = staticIntensityStratifiedCalibrationMarkdown(report);
      expect(markdown, contains('validation-only stratified offset scan'));
      expect(markdown, contains('High-Shindo Thresholds'));
      expect(markdown, contains('no production coordinate'));

      final output = File(
        '.dart_tool/static_intensity_stratified_calibration/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/static_intensity_stratified_calibration.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
