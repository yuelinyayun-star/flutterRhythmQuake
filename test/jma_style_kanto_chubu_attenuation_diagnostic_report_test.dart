import 'package:flutter_test/flutter_test.dart';

import '../tools/build_jma_style_kanto_chubu_attenuation_diagnostic_report.dart';

void main() {
  test(
    'JMA-style kanto_chubu attenuation diagnostic is structured and non-production',
    () {
      final report = buildJmaStyleKantoChubuAttenuationDiagnosticJson();

      expect(
        report['schemaVersion'],
        'jma_style_kanto_chubu_attenuation_diagnostic_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['targetRegion'], 'kanto_chubu');
      expect(policy['rawPredictedIntensityMutated'], isFalse);
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['parametersTuned'], isFalse);

      final coverage = (report['coverage'] as Map).cast<String, Object?>();
      expect(coverage['validationStationForecasts'], greaterThan(0));
      expect(coverage['testStationForecasts'], greaterThan(0));

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));

      for (final thresholdLabel in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[thresholdLabel]! as Map)
            .cast<String, Object?>();
        expect(threshold['estimatedSourcePrecisionDelta'], isA<double>());
        expect(threshold['oracleSourcePrecisionDelta'], isA<double>());

        final splits = (threshold['splits']! as Map).cast<String, Object?>();
        expect(splits.keys, containsAll(<String>['validation', 'test']));
        for (final splitName in <String>['validation', 'test']) {
          final split = (splits[splitName]! as Map).cast<String, Object?>();
          for (final branch in <String>[
            'estimatedSourceJma',
            'oracleSourceJma',
          ]) {
            final metrics = (split[branch]! as Map).cast<String, Object?>();
            expect(metrics['precision'], isA<double>());
            expect(metrics['recall'], isA<double>());
            expect(metrics['f1'], isA<double>());
            expect(metrics['meanError'], isA<double>());
            expect(metrics['mae'], isA<double>());
          }
          for (final bucketField in <String>[
            'sourceErrorBuckets',
            'distanceBuckets',
            'depthBuckets',
            'magnitudeBuckets',
            'amplificationBuckets',
          ]) {
            expect(split[bucketField], isA<Map>());
          }
        }
      }

      final markdown = jmaStyleKantoChubuAttenuationDiagnosticMarkdown(report);
      expect(
        markdown,
        contains('# JMA-Style Kanto/Chubu Attenuation Diagnostic'),
      );
      expect(markdown, contains('Estimated vs Oracle Source'));
      expect(markdown, contains('Source Error Buckets'));
      expect(markdown, contains('Amplification Buckets'));
      expect(markdown, contains('Raw predicted intensity mutated: `false`'));
      expect(markdown, contains('Production UI connected: `false`'));
      expect(markdown, contains('Diagnostic only: `true`'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
