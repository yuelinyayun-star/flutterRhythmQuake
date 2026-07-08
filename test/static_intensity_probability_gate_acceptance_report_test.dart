import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_static_intensity_probability_gate_acceptance_report.dart';
import '../tools/build_static_intensity_probability_gate_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'probability gate acceptance report blocks automatic frozen test',
    () {
      final gateReport = buildStaticIntensityProbabilityGateJson();
      final gateOutput = File(
        '.dart_tool/static_intensity_probability_gate/report.json',
      )..parent.createSync(recursive: true);
      gateOutput.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(gateReport)}\n',
      );

      final report = buildStaticIntensityProbabilityGateAcceptanceJson();

      expect(
        report['schemaVersion'],
        'static_intensity_probability_gate_acceptance_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['rawIntensityFieldMutated'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['readyForFrozenTest'], isFalse);
      expect(summary['requiresManualDecision'], isTrue);
      expect(summary['warningRelevantThresholds'], contains('shindo4'));

      final thresholds = (report['thresholds'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      final shindo5 = thresholds.singleWhere(
        (entry) => entry['label'] == 'shindo5-',
      );
      expect(shindo5['status'], 'pass');

      final markdown = staticIntensityProbabilityGateAcceptanceMarkdown(report);
      expect(markdown, contains('Ready for frozen test: `false`'));
      expect(markdown, contains('Requires manual decision: `true`'));

      final output = File(
        '.dart_tool/static_intensity_probability_gate_acceptance/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdownFile = File(
        'docs/baselines/static_intensity_probability_gate_acceptance.generated.md',
      )..parent.createSync(recursive: true);
      markdownFile.writeAsStringSync(markdown);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
