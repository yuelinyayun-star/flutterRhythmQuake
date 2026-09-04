import 'package:flutter_test/flutter_test.dart';

import '../tools/build_raw_intensity_frozen_source_diagnostic_report.dart';

void main() {
  test(
    'raw intensity frozen source diagnostic is non-suppressive and structured',
    () {
      final report = buildRawIntensityFrozenSourceDiagnosticJson();

      expect(
        report['schemaVersion'],
        'raw_intensity_frozen_source_diagnostic_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      // 非抑制型 policy 字段。
      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['rawPredictedIntensityMutated'], isFalse);
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['parametersTuned'], isFalse);
      expect(
        policy['oneShotCompliance'].toString(),
        contains('one-shot spent'),
      );

      // coverage 必须非零。
      final coverage = (report['coverage'] as Map).cast<String, Object?>();
      expect(coverage['validationStationForecasts'], greaterThan(0));
      expect(coverage['testStationForecasts'], greaterThan(0));

      // thresholds 必须含 shindo4 和 shindo5-。
      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(<String>['shindo4', 'shindo5-']));

      for (final thresholdLabel in <String>['shindo4', 'shindo5-']) {
        final threshold = (thresholds[thresholdLabel]! as Map)
            .cast<String, Object?>();
        // 每个 threshold 的 splits 含 validation 和 test。
        final splits = (threshold['splits']! as Map).cast<String, Object?>();
        expect(splits.keys, containsAll(<String>['validation', 'test']));
        for (final splitName in <String>['validation', 'test']) {
          final split = (splits[splitName]! as Map).cast<String, Object?>();
          // 每个 split 含三组件,每组件有 P/R/F1。
          for (final component in <String>[
            'jmaStyle',
            'plumR30D050',
            'baselineMax',
          ]) {
            final metrics = (split[component]! as Map).cast<String, Object?>();
            expect(metrics['precision'], isA<double>());
            expect(metrics['recall'], isA<double>());
            expect(metrics['f1'], isA<double>());
          }
        }

        // precisionDelta 含三组件。
        final precisionDelta = (threshold['precisionDelta']! as Map)
            .cast<String, Object?>();
        for (final component in <String>[
          'jmaStyle',
          'plumR30D050',
          'baselineMax',
        ]) {
          expect(precisionDelta[component], isA<double>());
        }
        // largestDropComponent 是三组件之一。
        expect(
          threshold['largestDropComponent'].toString(),
          anyOf('jmaStyle', 'plumR30D050', 'baselineMax'),
        );

        // regionBuckets/distanceBuckets 含 validation 和 test。
        final regionBuckets = (threshold['regionBuckets']! as Map)
            .cast<String, Object?>();
        expect(regionBuckets.keys, containsAll(<String>['validation', 'test']));
        final distanceBuckets = (threshold['distanceBuckets']! as Map)
            .cast<String, Object?>();
        expect(
          distanceBuckets.keys,
          containsAll(<String>['validation', 'test']),
        );

        // FP 触发源:validation 和 test 都含 jma_only/plum_only/both。
        final fpTriggerSource = (threshold['fpTriggerSource']! as Map)
            .cast<String, Object?>();
        for (final splitName in <String>['validation', 'test']) {
          final fpTrigger = (fpTriggerSource[splitName]! as Map)
              .cast<String, Object?>();
          expect(
            fpTrigger.keys,
            containsAll(<String>['jma_only', 'plum_only', 'both']),
          );
        }
      }

      // markdown 含关键章节标题和非抑制型声明。
      final markdown = rawIntensityFrozenSourceDiagnosticMarkdown(report);
      expect(markdown, contains('# Raw Intensity Frozen Source Diagnostic'));
      expect(markdown, contains('Three-Component P/R/F1'));
      expect(markdown, contains('Precision Delta'));
      expect(markdown, contains('Region Buckets'));
      expect(markdown, contains('Distance Buckets'));
      expect(markdown, contains('FP Trigger Source'));
      expect(markdown, contains('Raw predicted intensity mutated: `false`'));
      expect(markdown, contains('Parameters tuned: `false`'));
      expect(markdown, contains('Diagnostic only: `true`'));
      expect(markdown, contains('One-shot compliance'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
