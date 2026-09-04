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

  test('SeisJS marker size stays square for one- and two-digit labels', () {
    final single = seisJsMarkerSizeForLabel('8', 4);
    expect(single.width, closeTo(16, 0.01));
    expect(single.height, closeTo(16, 0.01));

    final doubleDigit = seisJsMarkerSizeForLabel('10', 4);
    expect(doubleDigit.width, closeTo(16, 0.01));
    expect(doubleDigit.height, closeTo(16, 0.01));

    final maxDoubleDigit = seisJsMarkerSizeForLabel('12', 10);
    expect(maxDoubleDigit.width, closeTo(24, 0.01));
    expect(maxDoubleDigit.height, closeTo(24, 0.01));
    expect(maxDoubleDigit.width / maxDoubleDigit.height, closeTo(1, 0.001));
  });

  test('SeisJS two-digit marker keeps a fixed square box for all zooms', () {
    for (final zoom in [4.0, 7.0, 10.0]) {
      final markerSize = seisJsMarkerSizeForLabel('12', zoom);
      expect(markerSize.width, closeTo(markerSize.height, 0.01));
    }
  });

  test('SeisJS idle dots stay large enough to find on a sparse map', () {
    expect(seisJsIdleDotRadiusForZoom(3), closeTo(5.0, 0.001));
    expect(seisJsIdleDotRadiusForZoom(4), closeTo(5.8, 0.001));
    expect(seisJsIdleDotRadiusForZoom(7), closeTo(8.2, 0.001));
    expect(seisJsIdleDotRadiusForZoom(12), closeTo(9.0, 0.001));
    expect(seisJsOverviewFactorForZoom(3.2), 0);
    expect(seisJsOverviewFactorForZoom(7), closeTo(1, 0.001));
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
