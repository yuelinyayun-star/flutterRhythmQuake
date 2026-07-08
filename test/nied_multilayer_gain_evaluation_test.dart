import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/evaluate_nied_multilayer_gain.dart';

void main() {
  test(
    'evaluates Noto M2.7 JMA-only against fixed physical fusion',
    () {
      const capture = 'tmp/captures/noto_m27_20260621_210754_multilayer';
      if (!Directory(capture).existsSync()) {
        markTestSkipped('Missing local multilayer capture: $capture');
        return;
      }
      const output = '$capture/multilayer_gain_report.json';
      evaluateNiedMultilayerGain(const [
        '--capture',
        capture,
        '--truth',
        'test/fixtures/source_estimation/noto_m27_20260621_jma_eq5.json',
        '--output',
        output,
        '--markdown',
        'docs/baselines/noto_m27_20260621_multilayer_gain.generated.md',
      ]);

      final report =
          jsonDecode(File(output).readAsStringSync()) as Map<String, Object?>;
      expect(report['caseId'], 'noto_m27_20260621_jma_eq5');
      expect(report['frameCount'], 151);
      expect(report['decodedFrameCount'], 151);
      expect(report['sourceTriggerMissedEvent'], isFalse);
      expect(report['triggeredFrameCount'], greaterThan(0));
      final methods = report['methods']! as Map<String, Object?>;
      final jmaOnly = methods['jmaOnly']! as Map<String, Object?>;
      final physical = methods['jmaPhysical']! as Map<String, Object?>;
      expect(jmaOnly['firstEstimateDelaySeconds'], 6.0);
      expect(jmaOnly['firstEstimateErrorKm'], lessThan(10.0));
      expect(
        physical['firstEstimateErrorKm'] as num,
        greaterThan(jmaOnly['firstEstimateErrorKm'] as num),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
