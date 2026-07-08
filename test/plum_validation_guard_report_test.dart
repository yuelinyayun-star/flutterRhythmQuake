import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_validation_guard_report.dart';

void main() {
  test('PLUM validation guard report remains validation-only diagnostic', () {
    final temp = Directory.systemTemp.createTempSync('plum_guard_');
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

    final report = buildPlumValidationGuardReportJson(
      validationDatasetPath: validation.path,
      modelPath: model.path,
      guardConfigs: const [
        LocalContrastGuardConfig(
          id: 'test_local_contrast',
          localRadiusKm: 10,
          weakMaxIntensity: 3.0,
          minimumWeakEvidenceCount: 1,
          capMargin: 0.5,
        ),
      ],
    );

    expect(report['schemaVersion'], 'plum_validation_guard_report_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['split'], 'validation');
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['diagnosticOnly'], isTrue);

    final evaluations = (report['evaluations'] as List)
        .cast<Map>()
        .map((entry) => entry.cast<String, Object?>())
        .toList();
    expect(
      evaluations.map((entry) => entry['configId']),
      containsAll(['baseline_no_guard', 'test_local_contrast']),
    );
    final guarded = evaluations.firstWhere(
      (entry) => entry['configId'] == 'test_local_contrast',
    );
    final guard = (guarded['guard'] as Map).cast<String, Object?>();
    expect(guard['triggeredCount'], greaterThan(0));

    final markdown = plumValidationGuardMarkdown(report);
    expect(markdown, contains('PLUM Validation Guard Diagnostic'));
    expect(markdown, contains('Frozen test evaluated: `false`'));
    expect(markdown, contains('Production remains blocked'));
  });
}

Map<String, Object?> _dataset() => {
  'schemaVersion': 1,
  'split': 'validation',
  'events': [
    {
      'eventId': 'validation_local_contrast_event',
      'split': 'validation',
      'truth': {
        'originTime': '2026-06-28T00:00:00Z',
        'latitude': 35.0,
        'longitude': 139.0,
        'depthKm': 10.0,
        'magnitude': 1.0,
      },
      'stations': [
        _station('strong_observed', 34.92, 138.92, 5.2),
        _station('weak_neighbor', 35.08, 139.08, 2.0),
        _station('target_weak', 35.10, 139.10, 2.0),
        _station('anchor_a', 35.30, 139.30, 1.0),
        _station('anchor_b', 34.90, 138.90, 1.0),
      ],
      'variants': [
        {
          'variantId': 'validation_local_contrast_event_mask_20pct',
          'requestedMaskRate': 0.2,
          'retainedStationIds': [
            'strong_observed',
            'weak_neighbor',
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
