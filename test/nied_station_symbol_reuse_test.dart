import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  NiedStation station(int id, int level) => NiedStation(
    id: id,
    code: 'test-$id',
    name: 'render fixture',
    coordinate: LatLng(35 + id * .01, 139),
    network: 'test',
    prefecture: 'test',
    expireSeconds: 10,
    level: level,
  );
  Widget map(
    List<NiedStation> data, {
    bool blink = true,
    bool display0 = false,
  }) => MaterialApp(
    home: FlutterMap(
      options: const MapOptions(initialCenter: LatLng(35, 139), initialZoom: 4),
      children: [
        NiedIntensityLayer(
          stations: data,
          blinkOn: blink,
          displayShindo0: display0,
        ),
      ],
    ),
  );
  StationDotPainterLayer layer(WidgetTester t) =>
      t.widget<StationDotPainterLayer>(find.byType(StationDotPainterLayer));

  testWidgets(
    'grid blink reuses symbols; original mutable station updates appear immediately',
    (tester) async {
      final data = [station(0, 0), station(1, -1)];
      await tester.pumpWidget(map(data));
      final before = layer(tester);
      await tester.pumpWidget(map(data, blink: false));
      expect(identical(before, layer(tester)), isTrue);
      data[0].level = 4;
      await tester.pumpWidget(map(data, blink: false));
      expect(identical(before, layer(tester)), isFalse);
      expect(layer(tester).dots.first.color, const Color(0x4D00B3A2));
      expect(layer(tester).dots.last.color, const Color(0x4D0003CF));
      final updated = layer(tester);
      await tester.pumpWidget(map([station(0, 4), station(1, -1)]));
      expect(identical(updated, layer(tester)), isTrue);
    },
  );

  testWidgets(
    'missing current observation is gray even when KA retains a numeric level; recovery invalidates cache',
    (tester) async {
      final data = [station(0, 4), station(1, 4)];
      await tester.pumpWidget(map(data));
      final normal = layer(tester).dots.first;
      data[0].clearGifObservation(
        NiedGifLayer.realtimeShindo,
        qualityFlag: 'pixel_transparent',
      );
      await tester.pumpWidget(map(data));
      expect(layer(tester).dots.first.color, const Color(0x4D888888));
      expect(layer(tester).dots.first.radius, normal.radius);
      expect(layer(tester).dots.first.fillOpacity, normal.fillOpacity);
      expect(layer(tester).dots.first.borderOpacity, normal.borderOpacity);
      expect(layer(tester).dots.last.color, normal.color);
      data[0].updateGifObservation(const NiedGifObservation(shindo: -1.2));
      await tester.pumpWidget(map(data));
      expect(layer(tester).dots.first.color, normal.color);
      data[0].level = 8;
      await tester.pumpWidget(map(data));
      expect(find.byType(MarkerLayer), findsOneWidget);
      data[0].clearGifObservation(
        NiedGifLayer.realtimeShindo,
        qualityFlag: 'pixel_transparent',
      );
      await tester.pumpWidget(map(data));
      expect(find.byType(MarkerLayer), findsNothing);
      expect(layer(tester).dots.first.color, const Color(0x4D888888));
      expect(data[0].level, 8);
    },
  );

  testWidgets(
    'threshold, order, removals and empty input invalidate symbol snapshot',
    (tester) async {
      final data = [station(0, 6), station(1, -1)];
      await tester.pumpWidget(map(data));
      expect(layer(tester).dots.length, 2);
      await tester.pumpWidget(map(data, display0: true));
      expect(layer(tester).dots.length, 1);
      expect(find.byType(MarkerLayer), findsOneWidget);
      data[0].level = 8;
      await tester.pumpWidget(map(data));
      expect(layer(tester).dots.length, 1);
      data.removeAt(0);
      await tester.pumpWidget(map(data));
      expect(layer(tester).dots.single.coordinate, data.single.coordinate);
      await tester.pumpWidget(map([]));
      expect(find.byType(StationDotPainterLayer), findsNothing);
      await tester.pumpWidget(map([station(2, 0)]));
      expect(layer(tester).dots.single.coordinate, const LatLng(35.02, 139));
    },
  );
}
