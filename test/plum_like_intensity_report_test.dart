import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

import '../tools/build_plum_like_intensity_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PLUM-like predictor propagates nearby observed shaking only', () {
    const predictor = PlumLikeIntensityPredictor(radiusKm: 40);
    const target = StaticIntensityStation(
      stationId: 'target',
      latitude: 35,
      longitude: 140,
      intensity: 0,
    );
    const near = StaticIntensityStation(
      stationId: 'near',
      latitude: 35.1,
      longitude: 140,
      intensity: 3,
    );
    const far = StaticIntensityStation(
      stationId: 'far',
      latitude: 37,
      longitude: 140,
      intensity: 6,
    );

    final prediction = predictor.predict(
      targetStation: target,
      observedStations: const [near, far],
    );

    expect(prediction.intensity, closeTo(3, 1e-9));
    expect(prediction.evidenceCount, 1);
    expect(prediction.strongestEvidenceStationId, 'near');
  });

  test(
    'PLUM-like report remains source-independent diagnostic',
    () {
      final report = buildPlumLikeIntensityReportJson();

      expect(report['schemaVersion'], 'plum_like_intensity_report_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['sourceIndependent'], isTrue);
      expect(policy['usesSourceLatitudeLongitudeDepthMagnitude'], isFalse);

      final selectedConfig = (report['selectedConfig'] as Map)
          .cast<String, Object?>();
      expect(selectedConfig['radiusKm'], isA<double>());
      expect(selectedConfig['minimumEvidenceCount'], isA<int>());

      final summary = (report['selectedSummary'] as Map)
          .cast<String, Object?>();
      expect((summary['caseCount'] as int), greaterThan(0));
      expect((summary['stationForecastCount'] as int), greaterThan(0));
      expect(summary['stationIntensityMae'], isA<double>());

      final thresholds = (report['selectedThresholds'] as Map)
          .cast<String, Object?>();
      expect(
        thresholds.keys,
        containsAll(['shindo1', 'shindo2', 'shindo3', 'shindo4', 'shindo5-']),
      );

      final markdown = plumLikeIntensityReportMarkdown(report);
      expect(markdown, contains('PLUM-Like Intensity Diagnostic'));
      expect(markdown, contains('Source independent: `true`'));
      expect(markdown, contains('synthetic reveal'));

      final output = File('.dart_tool/plum_like_intensity/report.json')
        ..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/plum_like_intensity.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
