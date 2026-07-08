import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_evidence_robustness_report.dart';

void main() {
  test(
    'PLUM evidence robustness report remains non-suppressive diagnostic',
    () {
      final temp = Directory.systemTemp.createTempSync('plum_robustness_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final model = File('${temp.path}/model.json')
        ..writeAsStringSync(
          jsonEncode({
            'modelId': 'static_intensity_attenuation_v1',
            'logDistanceCoefficient': 0.1,
            'linearDistanceCoefficient': 0.0,
            'nearDistanceKm': 20.0,
            'huberDelta': 1.0,
            'residualScale': 0.5,
            'centroidPenaltyPerKm': 0.0,
            'depthClassesKm': [10.0],
          }),
        );
      final validation = File('${temp.path}/validation.json')
        ..writeAsStringSync(jsonEncode(_dataset()));

      final report = buildPlumEvidenceRobustnessReportJson(
        validationDatasetPath: validation.path,
        modelPath: model.path,
      );

      expect(report['schemaVersion'], 'plum_evidence_robustness_report_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['split'], 'validation');
      expect(policy['frozenTestEvaluated'], isFalse);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['rawPredictedIntensityMutated'], isFalse);

      final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
      expect(thresholds.keys, containsAll(['shindo4', 'shindo5-']));

      final shindo4 = (thresholds['shindo4'] as Map).cast<String, Object?>();
      final features = (shindo4['features'] as Map).cast<String, Object?>();
      expect(
        features.keys,
        containsAll([
          'maskRate',
          'retainedCount',
          'plumEvidenceCount',
          'nearestEvidenceDistance',
          'branchAgreement',
          'robustnessScore',
        ]),
      );

      final markdown = plumEvidenceRobustnessMarkdown(report);
      expect(markdown, contains('PLUM Evidence Robustness Diagnostic'));
      expect(markdown, contains('does not suppress, cap, replace, or hide'));
      expect(markdown, contains('Production remains blocked'));
    },
  );
}

Map<String, Object?> _dataset() => {
  'schemaVersion': 1,
  'split': 'validation',
  'events': [
    {
      'eventId': 'validation_robustness_event',
      'split': 'validation',
      'truth': {
        'originTime': '2026-06-28T00:00:00Z',
        'latitude': 35.0,
        'longitude': 139.0,
        'depthKm': 10.0,
        'magnitude': 4.5,
      },
      'stations': [
        _station('strong_a', 35.00, 139.00, 4.3),
        _station('strong_b', 35.03, 139.03, 3.8),
        _station('weak_a', 35.12, 139.12, 2.0),
        _station('anchor_a', 35.30, 139.30, 1.0),
        _station('anchor_b', 34.90, 138.90, 1.0),
      ],
      'variants': [
        {
          'variantId': 'validation_robustness_event_mask_20pct',
          'requestedMaskRate': 0.2,
          'retainedStationIds': [
            'strong_a',
            'strong_b',
            'anchor_a',
            'anchor_b',
          ],
        },
      ],
    },
  ],
};

Map<String, Object?> _station(
  String id,
  double latitude,
  double longitude,
  double intensity,
) => {
  'stationId': id,
  'latitude': latitude,
  'longitude': longitude,
  'instrumentalIntensity': intensity,
};
