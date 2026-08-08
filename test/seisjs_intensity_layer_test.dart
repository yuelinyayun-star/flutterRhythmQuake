import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/widgets/map/seisjs_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test(
    'SeisJS parses realtime intensity separately from maximum intensity',
    () {
      final intensity = seisJsRealtimeIntensityFromJson({
        'Intensity': 8.4,
        'Max_Intensity': 11.0,
      });

      expect(intensity, 8.4);
    },
  );

  test('SeisJS map rounds realtime intensity and uses CSIS color', () {
    expect(seisJsMapIntensityLevel(8.4), 8);
    expect(seisJsMapIntensityLevel(11.6), 12);
    expect(
      seisJsMapIntensityColor(8.4),
      Color(IntensityCalculator.getCsisColor(8)),
    );
  });

  test(
    'SeisJS dashboard selects the station with current maximum intensity',
    () {
      final historicalMaximum = SeisJsStation(
        id: 'history',
        region: 'history',
        coordinate: const LatLng(0, 0),
        intensity: 2,
        maxIntensity: 10,
      );
      final currentMaximum = SeisJsStation(
        id: 'current',
        region: 'current',
        coordinate: const LatLng(0, 0),
        intensity: 5,
        maxIntensity: 6,
      );

      expect(
        selectSeisJsCurrentMaxStation([historicalMaximum, currentMaximum])?.id,
        'current',
      );
    },
  );
}
