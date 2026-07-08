import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_plum_region_site_calibration_report.dart';

void main() {
  test('PLUM region/site calibration report is non-suppressive diagnostic', () {
    final temp = Directory.systemTemp.createTempSync('plum_region_site_');
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

    final report = buildPlumRegionSiteCalibrationReportJson(
      validationDatasetPath: validation.path,
      modelPath: model.path,
    );

    expect(report['schemaVersion'], 'plum_region_site_calibration_report_v1');
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['split'], 'validation');
    expect(policy['frozenTestEvaluated'], isFalse);
    expect(policy['productionReady'], isFalse);
    expect(policy['productionUiConnected'], isFalse);
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['rawPredictedIntensityMutated'], isFalse);

    final bandDefs = (report['bandDefinitions'] as Map).cast<String, Object?>();
    expect(bandDefs['minSampleForBandAssignment'], 20);

    final bucketDefs =
        (report['bucketDefinitions'] as Map).cast<String, Object?>();
    expect(bucketDefs['regionSource'], 'estimated_source_latitude');
    expect(bucketDefs['siteSource'], 'station_latitude');
    expect(bucketDefs['regionBands'], isA<List>());
    expect(bucketDefs['siteBands'], isA<List>());

    final thresholds = (report['thresholds'] as Map).cast<String, Object?>();
    expect(thresholds.keys, containsAll(['shindo4', 'shindo5-']));

    for (final label in const ['shindo4', 'shindo5-']) {
      final threshold = (thresholds[label] as Map).cast<String, Object?>();
      expect(threshold['baseline'], isA<Map>());
      expect(threshold['jointBuckets'], isA<List>());
      expect(threshold['marginalRegion'], isA<List>());
      expect(threshold['marginalSite'], isA<List>());
      expect(threshold['bandSummary'], isA<Map>());

      final bandSummary =
          (threshold['bandSummary'] as Map).cast<String, Object?>();
      expect(
        bandSummary.keys,
        containsAll(['high', 'medium', 'low', 'insufficient']),
      );

      for (final raw in threshold['marginalRegion'] as List) {
        final bucket = (raw as Map).cast<String, Object?>();
        expect(bucket['region'], isA<String>());
        expect(bucket['predictedPositive'], isA<int>());
        expect(bucket['precision'], isA<double>());
      }
      for (final raw in threshold['marginalSite'] as List) {
        final bucket = (raw as Map).cast<String, Object?>();
        expect(bucket['site'], isA<String>());
        expect(bucket['predictedPositive'], isA<int>());
        expect(bucket['precision'], isA<double>());
      }
      for (final raw in threshold['jointBuckets'] as List) {
        final bucket = (raw as Map).cast<String, Object?>();
        expect(bucket['region'], isA<String>());
        expect(bucket['site'], isA<String>());
        expect(bucket['band'], isA<String>());
        expect(
          bucket['band'],
          isIn(['high', 'medium', 'low', 'insufficient']),
        );
      }
    }

    final markdown = plumRegionSiteCalibrationMarkdown(report);
    expect(markdown, contains('PLUM Region/Site Calibration Diagnostic'));
    expect(markdown, contains('Raw predicted intensity mutated: `false`'));
    expect(markdown, contains('Marginal Region Precision'));
    expect(markdown, contains('Marginal Site Precision'));
    expect(markdown, contains('Joint Calibration Table'));
    expect(markdown, contains('Band Summary'));
    expect(markdown, contains('do not replace, cap, or hide predicted intensity'));
  });
}

Map<String, Object?> _dataset() => {
  'schemaVersion': 1,
  'split': 'validation',
  'events': [
    {
      'eventId': 'region_site_calibration_event',
      'split': 'validation',
      'truth': {
        'originTime': '2026-06-28T00:00:00Z',
        'latitude': 35.0,
        'longitude': 139.0,
        'depthKm': 10.0,
        'magnitude': 4.5,
      },
      'stations': [
        // site = kanto_chubu (34.5 <= lat < 37.5)
        _station('strong_a', 35.00, 139.00, 4.3),
        _station('strong_b', 35.02, 139.02, 4.0),
        _station('weak_a', 35.10, 139.10, 2.0),
        // site = tohoku (37.5 <= lat < 41)
        _station('tohoku_a', 38.00, 139.50, 1.0),
        // site = west_south (lat < 34.5)
        _station('west_a', 34.00, 138.50, 1.0),
      ],
      'variants': [
        {
          'variantId': 'region_site_calibration_event_mask_20pct',
          'requestedMaskRate': 0.2,
          'retainedStationIds': [
            'strong_a',
            'strong_b',
            'tohoku_a',
            'west_a',
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
