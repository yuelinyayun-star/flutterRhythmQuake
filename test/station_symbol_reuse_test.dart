import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/widgets/map/cwa_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/kma_intensity_layer.dart';
import 'package:flutterrhythmquake/widgets/map/palert_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  Widget map(Widget child, {MapController? controller}) => MaterialApp(
    home: FlutterMap(
      mapController: controller,
      options: const MapOptions(initialCenter: LatLng(24, 121), initialZoom: 4),
      children: [child],
    ),
  );
  StationDotPainterLayer dots(WidgetTester tester) =>
      tester.widget(find.byType(StationDotPainterLayer));

  testWidgets('CWA partial changes preserve only unchanged station symbols', (
    tester,
  ) async {
    final cwa = [
      for (var i = 0; i < 2; i++)
        CwaStation(
            id: '$i',
            code: i,
            net: 'test',
            coordinate: LatLng(24 + i * 0.1, 121),
            work: true,
            intensity: 2,
          )
          ..hasAlert = true
          ..preparedGridLevel = 8,
    ];
    await tester.pumpWidget(map(CwaStationLayer(stations: cwa)));
    final before = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(before, hasLength(2));
    cwa[1].preparedGridLevel = 12;
    await tester.pumpWidget(map(CwaStationLayer(stations: cwa)));
    final after = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(after, hasLength(2));
    expect(identical(before[0], after[0]), isTrue);
    expect(identical(before[1], after[1]), isFalse);
    expect(after[1].point, before[1].point);
    cwa.setAll(0, [cwa[1], cwa[0]]);
    await tester.pumpWidget(map(CwaStationLayer(stations: cwa)));
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.first.point,
      cwa.first.coordinate,
    );
    final removed = cwa.removeLast();
    await tester.pumpWidget(map(CwaStationLayer(stations: cwa)));
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(1),
    );
    cwa.add(removed);
    await tester.pumpWidget(map(CwaStationLayer(stations: cwa)));
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last.point,
      removed.coordinate,
    );
  });

  testWidgets(
    'CWA blink reuses symbols and mutable input refreshes in the same pump',
    (tester) async {
      final station = CwaStation(
        id: '1',
        code: 1,
        net: 'test',
        coordinate: const LatLng(24, 121),
        work: true,
        intensity: -3,
      );
      final data = [station];
      await tester.pumpWidget(map(CwaStationLayer(stations: data)));
      final original = dots(tester);
      await tester.pumpWidget(
        map(CwaStationLayer(stations: data, blinkOn: false)),
      );
      expect(identical(dots(tester), original), isTrue);
      station.intensity = 2;
      await tester.pumpWidget(map(CwaStationLayer(stations: data)));
      expect(identical(dots(tester), original), isFalse);
      expect(dots(tester).dots.single.color, isNot(original.dots.single.color));
      station.hasAlert = true;
      station.alertIntensity = 4;
      await tester.pumpWidget(map(CwaStationLayer(stations: data)));
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        1,
      );
      station.preparedGridLevel = -1;
      await tester.pumpWidget(map(CwaStationLayer(stations: data)));
      expect(find.byType(MarkerLayer), findsNothing);
      expect(dots(tester).dots.single.color, const Color(0x804466AA));
      await tester.pumpWidget(map(const CwaStationLayer(stations: [])));
      expect(find.byType(StationDotPainterLayer), findsNothing);
      station.preparedGridLevel = 17;
      await tester.pumpWidget(map(CwaStationLayer(stations: data)));
      expect(find.byType(MarkerLayer), findsOneWidget);
    },
  );

  testWidgets(
    'KMA order, removals, held level, display zero and fractional zoom invalidate',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      final a = KmaStation(
        id: 1,
        coordinate: const LatLng(24, 121),
        intensity: -3,
      );
      final b = KmaStation(
        id: 2,
        coordinate: const LatLng(24.1, 121.1),
        intensity: -2,
      );
      final data = [a, b];
      Future<void> pump({bool blink = true, bool display0 = false}) =>
          tester.pumpWidget(
            map(
              KmaIntensityLayer(
                stations: data,
                blinkOn: blink,
                displayShindo0: display0,
              ),
              controller: controller,
            ),
          );
      await pump();
      await pump(blink: false);
      data.setAll(0, [b, a]);
      await pump();
      expect(dots(tester).dots.first.coordinate, b.coordinate);
      b.holdLevel = 4;
      await pump();
      expect(find.byType(MarkerLayer), findsOneWidget);
      b.holdLevel = 3;
      await pump(display0: true);
      expect(find.byType(MarkerLayer), findsOneWidget);
      await pump();
      expect(find.byType(MarkerLayer), findsNothing);
      final beforeZoom = dots(tester);
      controller.move(const LatLng(24, 121), 4.29);
      await tester.pump();
      expect(identical(beforeZoom, dots(tester)), isFalse);
      expect(
        dots(tester).dots.first.radius,
        isNot(beforeZoom.dots.first.radius),
      );
      data.removeAt(0);
      await pump();
      expect(dots(tester).dots.single.coordinate, a.coordinate);
      data.clear();
      await pump();
      expect(find.byType(StationDotPainterLayer), findsNothing);
    },
  );

  testWidgets(
    'P-Alert expires at the original 12 second boundary and respects prepared recent',
    (tester) async {
      final time = DateTime.utc(2026, 10, 14, 9, 4, 50);
      PAlertStation station({bool? recent}) => PAlertStation(
        id: '1',
        network: 'test',
        name: 'render fixture',
        area: 'test',
        coordinate: const LatLng(24, 121),
        heldLevel: 12,
        receivedAt: time,
        preparedMapRecent: recent,
      );
      final data = [station()];
      Future<void> pump(DateTime now, {bool blink = true}) => tester.pumpWidget(
        map(
          PAlertStationLayer(
            stations: data,
            observationTime: now,
            blinkOn: blink,
          ),
        ),
      );
      await pump(time);
      await pump(time.add(const Duration(seconds: 12)), blink: false);
      expect(find.byType(MarkerLayer), findsOneWidget);
      await pump(time.add(const Duration(seconds: 12, microseconds: 1)));
      expect(find.byType(MarkerLayer), findsNothing);
      expect(dots(tester).dots.length, 1);
      data[0] = station(recent: true);
      await pump(time.add(const Duration(seconds: 60)));
      expect(find.byType(MarkerLayer), findsOneWidget);
      data[0] = station(recent: false);
      await pump(time);
      expect(find.byType(MarkerLayer), findsNothing);
      data.clear();
      await pump(time);
      expect(find.byType(StationDotPainterLayer), findsNothing);
      data.add(station());
      await pump(time);
      expect(find.byType(MarkerLayer), findsOneWidget);
    },
  );
}
