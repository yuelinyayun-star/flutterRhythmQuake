import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_evidence_shape_report.dart';

void main() {
  test('PLUM evidence shape report remains validation-only diagnostic', () {
    final temp = Directory.systemTemp.createTempSync('plum_shape_');
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

    final report = buildPlumEvidenceShapeReportJson(
      validationDatasetPath: validation.path,
      modelPath: model.path,
      shapeConfigs: const [
        EvidenceShapeConfig(
          id: 'test_shape_min2',
          threshold: 3.5,
          minimumStrongEvidenceCount: 2,
          supportRadiusKm: 30,
          evidenceMargin: 0.5,
          minimumEvidenceSpreadKm: 0,
        ),
      ],
    );

    expect(report['schemaVersion'], 'plum_evidence_shape_report_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['split'], 'validation');
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['rawProductionIntensityMutated'], isFalse);

    final evaluations = (report['evaluations'] as List)
        .cast<Map>()
        .map((entry) => entry.cast<String, Object?>())
        .toList();
    expect(
      evaluations.map((entry) => entry['configId']),
      containsAll(['baseline_no_shape_gate', 'test_shape_min2']),
    );
    final shaped = evaluations.firstWhere(
      (entry) => entry['configId'] == 'test_shape_min2',
    );
    final shape = (shaped['shape'] as Map).cast<String, Object?>();
    expect(shape['suppressedCount'], greaterThan(0));

    final markdown = plumEvidenceShapeMarkdown(report);
    expect(markdown, contains('PLUM Evidence Shape Diagnostic'));
    expect(markdown, contains('Production remains blocked'));
    expect(markdown, contains('Raw production intensity mutated: `false`'));
  });
}

Map<String, Object?> _dataset() => {
  'schemaVersion': 1,
  'split': 'validation',
  'events': [
    {
      'eventId': 'validation_shape_event',
      'split': 'validation',
      'truth': {
        'originTime': '2026-06-28T00:00:00Z',
        'latitude': 35.0,
        'longitude': 139.0,
        'depthKm': 10.0,
        'magnitude': 1.0,
      },
      'stations': [
        _station('isolated_strong', 35.00, 139.00, 5.0),
        _station('target_weak', 35.03, 139.03, 2.0),
        _station('weak_a', 35.08, 139.08, 2.0),
        _station('anchor_a', 35.30, 139.30, 1.0),
        _station('anchor_b', 34.90, 138.90, 1.0),
      ],
      'variants': [
        {
          'variantId': 'validation_shape_event_mask_20pct',
          'requestedMaskRate': 0.2,
          'retainedStationIds': [
            'isolated_strong',
            'weak_a',
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
