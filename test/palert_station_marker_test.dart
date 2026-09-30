import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/widgets/map/ka_shindo_marker_style.dart';
import 'package:flutterrhythmquake/widgets/map/palert_station_layer.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

// Controlled threshold inputs, not live observations or an earthquake replay.
PAlertStation station(
  double? pga, {
  double? pgv,
  int? heldLevel,
  Duration age = Duration.zero,
}) {
  final time = DateTime.now().toUtc().subtract(age);
  return PAlertStation(
    id: 'TEST',
    network: 'P-Alert',
    name: 'TEST',
    area: '',
    coordinate: const LatLng(23.5, 121),
    pgaGal: pga,
    pgvCms: pgv,
    cwaIntensityIndex: PAlertService.cwaIntensityIndexFromPgaPgv(
      pgaGal: pga,
      pgvCms: pgv,
    ),
    heldLevel: heldLevel,
    dataTime: time,
    receivedAt: time,
  );
}

void main() {
  for (final size in [const Size(1280, 720), const Size(390, 844)]) {
    testWidgets('P-Alert continuous marker gate at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> render(
        List<PAlertStation> stations, {
        bool showZero = true,
        double zoom = 6,
      }) async {
        final controller = MapController();
        final mapState = MapStateProvider()..setController(controller, tester);
        addTearDown(mapState.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<MapStateProvider>.value(
              value: mapState,
              child: FlutterMap(
                key: ObjectKey(controller),
                mapController: controller,
                options: MapOptions(
                  initialCenter: const LatLng(23.5, 121),
                  initialZoom: zoom,
                ),
                children: [
                  PAlertStationLayer(
                    stations: stations,
                    displayShindo0: showZero,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }

      const floor = 0.44;
      await render([station(floor - 1e-8)]);
      expect(find.byType(MarkerLayer), findsNothing);
      await render([station(floor)]);
      expect(find.text('0'), findsOneWidget);
      await render([station(floor + 1e-8)]);
      expect(find.text('0'), findsOneWidget);

      // KA level 6 is the first numeric zero marker.
      await render([
        station(0.02),
        station(0.1),
        station(0.2),
        station(0.33),
        station(0.44),
      ]);
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        hasLength(1),
      );
      expect(find.text('0'), findsOneWidget);

      await render([station(0.44)], showZero: false);
      expect(find.byType(MarkerLayer), findsNothing);
      await render([station(0.8 - 1e-8)], showZero: false);
      expect(find.byType(MarkerLayer), findsNothing);
      await render([station(0.8 - 1e-8)]);
      expect(find.text('0'), findsOneWidget);
      await render([station(0.8)], showZero: false);
      expect(find.text('1'), findsOneWidget);

      await render([station(0.44)], zoom: 3.99);
      expect(find.byType(MarkerLayer), findsNothing);
      await render([station(0.44)], zoom: 4);
      expect(find.text('0'), findsOneWidget);
      await render([station(0.44, age: const Duration(seconds: 13))]);
      expect(find.byType(MarkerLayer), findsNothing);

      for (final pga in <double?>[null, 0, -1, double.nan, double.infinity]) {
        await render([station(pga)]);
        expect(find.byType(MarkerLayer), findsNothing);
      }
      await render([station(1000)]);
      expect(find.text('4'), findsOneWidget);

      // Strong PGA uses the current PGV-derived KA label/color.
      await render([station(1000, pgv: 5)]);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('7'), findsNothing);
      final marker = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .single;
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byWidget(marker.child),
          matching: find.byType(Container),
        ),
      );
      expect(
        containers.any(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).color ==
                  KaShindoMarkerStyle.colorForLevel(15),
        ),
        isTrue,
      );

      for (final (pgv, label) in <(double, String)>[
        (15, '5-'),
        (30, '5+'),
        (50, '6-'),
        (80, '6+'),
        (140, '7'),
      ]) {
        await render([station(80, pgv: pgv)]);
        expect(find.text(label), findsOneWidget);
      }

      await render([station(0.44, heldLevel: 15)]);
      expect(find.text('4'), findsOneWidget);
      await render([station(0.1, heldLevel: 15)]);
      expect(find.text('4'), findsOneWidget);
    });
  }
}
