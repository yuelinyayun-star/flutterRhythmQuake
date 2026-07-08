import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_frozen_regression_diagnostic_report.dart';

void main() {
  test(
    'PLUM frozen regression diagnostic compares validation and test buckets',
    () {
      final temp = Directory.systemTemp.createTempSync('plum_regression_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final model = File('${temp.path}/model.json')
        ..writeAsStringSync(
          jsonEncode({
            'modelId': 'static_intensity_attenuation_v1',
            'logDistanceCoefficient': 1.0,
            'linearDistanceCoefficient': 0.0,
            'nearDistanceKm': 20.0,
            'huberDelta': 1.0,
            'residualScale': 0.5,
            'centroidPenaltyPerKm': 0.0,
            'depthClassesKm': [10.0],
          }),
        );
      final validation = File('${temp.path}/validation.json')
        ..writeAsStringSync(jsonEncode(_dataset(split: 'validation')));
      final test = File('${temp.path}/test.json')
        ..writeAsStringSync(jsonEncode(_dataset(split: 'test')));

      final report = buildPlumFrozenRegressionDiagnosticReportJson(
        validationDatasetPath: validation.path,
        testDatasetPath: test.path,
        modelPath: model.path,
      );

      expect(report['schemaVersion'], 'plum_frozen_regression_diagnostic_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['frozenTestEvaluated'], isTrue);
      expect(policy['productionReady'], isFalse);
      expect(policy['productionUiConnected'], isFalse);
      expect(policy['diagnosticOnly'], isTrue);

      final comparisons = (report['comparisons'] as Map)
          .cast<String, Object?>();
      expect(comparisons.keys, containsAll(['maskRate', 'stationDistance']));

      final markdown = plumFrozenRegressionDiagnosticMarkdown(report);
      expect(markdown, contains('PLUM Frozen Regression Diagnostic'));
      expect(markdown, contains('Worst Shindo4 F1 Drops'));
    },
  );
}

Map<String, Object?> _dataset({required String split}) => {
  'schemaVersion': 1,
  'split': split,
  'events': [
    {
      'eventId': '${split}_event',
      'split': split,
      'truth': {
        'originTime': '2026-06-28T00:00:00Z',
        'latitude': 35.0,
        'longitude': 139.0,
        'depthKm': 10.0,
        'magnitude': 4.8,
      },
      'stations': [
        _station('a', 35.00, 139.00, 4.0, 0.0),
        _station('b', 35.05, 139.05, 3.6, 7.0),
        _station('c', 35.10, 139.10, 2.0, 14.0),
        _station('d', 35.15, 139.15, 1.0, 21.0),
      ],
      'variants': [
        {
          'variantId': '${split}_event_mask_50pct',
          'requestedMaskRate': 0.5,
          'retainedStationIds': ['a', 'b', 'c', 'd'],
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
