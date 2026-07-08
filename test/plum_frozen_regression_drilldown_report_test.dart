import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_frozen_regression_drilldown_report.dart';

void main() {
  test('PLUM frozen regression drilldown reports target bucket examples', () {
    final temp = Directory.systemTemp.createTempSync('plum_drilldown_');
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
    final testDataset = File('${temp.path}/test.json')
      ..writeAsStringSync(jsonEncode(_dataset()));

    final report = buildPlumFrozenRegressionDrilldownReportJson(
      testDatasetPath: testDataset.path,
      modelPath: model.path,
    );

    expect(report['schemaVersion'], 'plum_frozen_regression_drilldown_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['frozenTestEvaluated'], isTrue);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['diagnosticOnly'], isTrue);

    final buckets = (report['buckets'] as Map).cast<String, Object?>();
    final kantoBucket =
        (buckets['eventLatitudeBand_kanto_chubu'] as Map)
            .cast<String, Object?>();
    expect(kantoBucket['falsePositiveCount'], greaterThan(0));
    expect(kantoBucket['falseNegativeCount'], greaterThan(0));

    final markdown = plumFrozenRegressionDrilldownMarkdown(report);
    expect(markdown, contains('PLUM Frozen Regression Drilldown'));
    expect(markdown, contains('eventLatitudeBand_kanto_chubu'));
    expect(markdown, contains('Production remains blocked'));
  });
}

Map<String, Object?> _dataset() => {
  'schemaVersion': 1,
  'split': 'test',
  'events': [
    {
      'eventId': 'test_kanto_chubu_event',
      'split': 'test',
      'truth': {
        'originTime': '2026-06-28T00:00:00Z',
        'latitude': 35.0,
        'longitude': 139.0,
        'depthKm': 10.0,
        'magnitude': 1.0,
      },
      'stations': [
        _station('near_high', 35.00, 139.00, 4.2, 0.0),
        _station('mid_low', 35.05, 139.05, 2.0, 40.0),
        _station('far_high', 35.20, 139.20, 4.0, 90.0),
        _station('anchor_low', 35.30, 139.30, 1.0, 120.0),
      ],
      'variants': [
        {
          'variantId': 'test_kanto_chubu_event_mask_80pct',
          'requestedMaskRate': 0.8,
          'retainedStationIds': [
            'near_high',
            'mid_low',
            'far_high',
            'anchor_low',
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
  double surfaceDistanceKm,
) => {
  'stationId': id,
  'latitude': latitude,
  'longitude': longitude,
  'instrumentalIntensity': intensity,
  'surfaceDistanceKm': surfaceDistanceKm,
};
