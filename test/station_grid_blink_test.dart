import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/widgets/map/cwa_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/kma_intensity_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  Widget map(Widget layer) => MaterialApp(
    home: FlutterMap(
      options: const MapOptions(initialCenter: LatLng(35, 139), initialZoom: 5),
      children: [layer],
    ),
  );

  testWidgets('non-alert KMA values do not draw any blinking grids', (
    tester,
  ) async {
    for (final intensity in [0, 1, 5]) {
      final station = KmaStation(
        id: 1,
        coordinate: const LatLng(35, 139),
        intensity: intensity,
      );
      for (final blinkOn in [false, true]) {
        await tester.pumpWidget(
          map(KmaIntensityLayer(stations: [station], blinkOn: blinkOn)),
        );
        expect(find.byType(PolygonLayer), findsNothing);
      }
      station.dispose();
    }
  });

  testWidgets('activated KMA grids retain both blink phases', (tester) async {
    final station = KmaStation(
      id: 1,
      coordinate: const LatLng(35, 139),
      intensity: 3,
    )..isActive = true;
    await tester.pumpWidget(
      map(KmaIntensityLayer(stations: [station], blinkOn: true)),
    );
    expect(
      tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons
          .single
          .borderColor
          .a,
      closeTo(0.8, 0.001),
    );
    await tester.pumpWidget(
      map(KmaIntensityLayer(stations: [station], blinkOn: false)),
    );
    expect(
      tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons
          .single
          .borderColor
          .a,
      0,
    );
    station.dispose();
  });

  CwaStation station({bool hasAlert = false, double intensity = 0}) =>
      CwaStation(
        id: '1',
        code: 1,
        net: 'test',
        coordinate: const LatLng(35, 139),
        work: true,
        intensity: intensity,
        alertIntensity: 2,
        hasAlert: hasAlert,
      );

  testWidgets('non-alert TREM values do not draw any blinking grids', (
    tester,
  ) async {
    for (final intensity in [0.0, 1.0, 5.0]) {
      final data = station(intensity: intensity);
      for (final blinkOn in [false, true]) {
        await tester.pumpWidget(
          map(CwaStationLayer(stations: [data], blinkOn: blinkOn)),
        );
        expect(find.byType(PolygonLayer), findsNothing);
      }
    }
  });

  testWidgets('alerted TREM grids retain both blink phases', (tester) async {
    final data = station(hasAlert: true);
    await tester.pumpWidget(
      map(CwaStationLayer(stations: [data], blinkOn: true)),
    );
    expect(
      tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons
          .single
          .borderColor
          .a,
      closeTo(0.8, 0.001),
    );
    await tester.pumpWidget(
      map(CwaStationLayer(stations: [data], blinkOn: false)),
    );
    expect(
      tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons
          .single
          .borderColor
          .a,
      0,
    );
  });
}
