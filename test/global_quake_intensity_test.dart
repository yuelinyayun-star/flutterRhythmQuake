import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/services/sources/global_quake_intensity.dart';

void main() {
  test('MMI thresholds match GlobalQuake 0.11', () {
    expect(GlobalQuakeIntensity.mmiLevelFromPga(0.49), 0);
    expect(GlobalQuakeIntensity.mmiLevelFromPga(0.5), 1);
    expect(GlobalQuakeIntensity.mmiLevelFromPga(1.0), 2);
    expect(GlobalQuakeIntensity.mmiLevelFromPga(2.1), 3);
    expect(GlobalQuakeIntensity.mmiLevelFromPga(5.0), 4);
    expect(GlobalQuakeIntensity.mmiLevelFromPga(3000.0), 12);
    expect(GlobalQuakeIntensity.mmiLevelFromPga(double.nan), 0);
  });

  test('depth correction and PGA attenuation match the official formula', () {
    expect(
      GlobalQuakeIntensity.depthCorrection(10),
      closeTo(0.026328938722349537, 1e-12),
    );
    expect(
      GlobalQuakeIntensity.pgaFunction(
        magnitude: 4.5,
        distanceKm: 10,
        depth: 10,
      ),
      closeTo(19.646, 1e-3),
    );
  });

  test('Jan Mayen raw GlobalQuake maxPGA is MMI III, not project CSIS VI', () {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/eew_camera_20261101/gq_jan_mayen_report4.original.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final payload = raw['sourcePayload'] as Map<String, dynamic>;
    final packet = payload['packet'] as Map<String, dynamic>;
    final fields = packet['fields'] as Map<String, dynamic>;
    final data = fields['data'] as Map<String, dynamic>;
    final dataFields = data['fields'] as Map<String, dynamic>;
    final maxPga = (dataFields['maxPGA'] as num).toDouble();

    expect(maxPga, closeTo(2.91273804916355, 1e-12));
    expect(GlobalQuakeIntensity.mmiLevelFromPga(maxPga), 3);
    expect(
      IntensityCalculator.calcCsisLevel(
        (dataFields['magnitude'] as num).toDouble(),
        (dataFields['depth'] as num).toDouble(),
        0,
      ),
      6,
    );
  });

  test('deep-source land comparison exposes the old CSIS drift', () {
    const magnitude = 4.5;
    final expectedMmi = <int>[5, 4, 2, 1, 0];
    final depths = <double>[10, 40, 100, 300, 600];
    for (var i = 0; i < depths.length; i++) {
      final pga = GlobalQuakeIntensity.pgaFunction(
        magnitude: magnitude,
        distanceKm: depths[i],
        depth: depths[i],
      );
      expect(GlobalQuakeIntensity.mmiLevelFromPga(pga), expectedMmi[i]);
    }
  });
}
