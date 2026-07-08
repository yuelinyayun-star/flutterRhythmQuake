import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_static_intensity_probability_gate_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'static intensity probability gate remains validation-only',
    () {
      final report = buildStaticIntensityProbabilityGateJson();

      expect(report['schemaVersion'], 'static_intensity_probability_gate_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['rawIntensityFieldMutated'], isFalse);
      expect(
        policy['calibrationType'],
        'threshold_probability_gate_validation',
      );

      expect((report['farDistanceCorrection'] as num).toDouble(), lessThan(0));

      final thresholds = (report['thresholds'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(
        thresholds.map((entry) => entry['label']),
        containsAll(['shindo3', 'shindo4', 'shindo5-']),
      );
      for (final threshold in thresholds) {
        expect(
          threshold.keys,
          containsAll([
            'rawThreshold',
            'hardFarCorrection',
            'probabilityGate',
            'selectedGateScore',
          ]),
        );
      }

      final markdown = staticIntensityProbabilityGateMarkdown(report);
      expect(markdown, contains('Raw intensity field mutated: `false`'));
      expect(markdown, contains('Threshold Comparison'));
      expect(markdown, contains('not realtime lead-time validation'));

      final output = File(
        '.dart_tool/static_intensity_probability_gate/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/static_intensity_probability_gate.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
