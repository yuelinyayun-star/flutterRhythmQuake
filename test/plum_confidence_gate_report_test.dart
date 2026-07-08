import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_confidence_gate_report.dart';

void main() {
  test('PLUM confidence gate remains threshold-only diagnostic', () {
    final temp = Directory.systemTemp.createTempSync('plum_confidence_');
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

    final report = buildPlumConfidenceGateReportJson(
      validationDatasetPath: validation.path,
      modelPath: model.path,
    );

    expect(report['schemaVersion'], 'plum_confidence_gate_report_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['split'], 'validation');
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['rawIntensityFieldMutated'], isFalse);

    final evaluations = (report['evaluations'] as List)
        .cast<Map>()
        .map((entry) => entry.cast<String, Object?>())
        .toList();
    expect(
      evaluations.map((entry) => entry['gateId']),
      containsAll([
        'baseline_raw_threshold',
        'jma_or_plum_r20_d0_50',
        'two_of_jma_r20_d0_50_r30_d0_75',
      ]),
    );

    final markdown = plumConfidenceGateMarkdown(report);
    expect(markdown, contains('PLUM Confidence Gate Diagnostic'));
    expect(markdown, contains('Raw intensity field mutated: `false`'));
    expect(markdown, contains('Production remains blocked'));
  });
}

Map<String, Object?> _dataset() => {
  'schemaVersion': 1,
  'split': 'validation',
  'events': [
    {
      'eventId': 'validation_confidence_event',
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
        _station('strong_b', 35.02, 139.02, 4.0),
        _station('weak_a', 35.10, 139.10, 2.0),
        _station('anchor_a', 35.30, 139.30, 1.0),
        _station('anchor_b', 34.90, 138.90, 1.0),
      ],
      'variants': [
        {
          'variantId': 'validation_confidence_event_mask_20pct',
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
