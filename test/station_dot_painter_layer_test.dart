import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const dot = StationDot(
    coordinate: LatLng(35, 139),
    color: Colors.green,
    radius: 3,
    fillOpacity: 0.3,
    borderOpacity: 0.7,
    borderWidth: 1,
  );

  Widget map(List<StationDot> dots, {bool sizeWithCameraZoom = false}) {
    return MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(35, 139),
          initialZoom: 5,
        ),
        children: [
          StationDotPainterLayer(
            dots: dots,
            sizeWithCameraZoom: sizeWithCameraZoom,
          ),
        ],
      ),
    );
  }

  CustomPainter painter(WidgetTester tester) => tester
      .widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString() == '_StationDotPainter',
        ),
      )
      .painter!;

  final stationPaint = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_StationDotPainter',
  );

  testWidgets(
    'identical dot appearance does not repaint a newly allocated list',
    (tester) async {
      await tester.pumpWidget(map([dot]));
      final previous = painter(tester);
      await tester.pumpWidget(
        map([
          const StationDot(
            coordinate: LatLng(35, 139),
            color: Colors.green,
            radius: 3,
            fillOpacity: 0.3,
            borderOpacity: 0.7,
            borderWidth: 1,
          ),
        ]),
      );
      expect(painter(tester).shouldRepaint(previous), isFalse);
    },
  );

  testWidgets('each appearance change still repaints', (tester) async {
    final changes = [
      const StationDot(
        coordinate: LatLng(36, 139),
        color: Colors.green,
        radius: 3,
        fillOpacity: 0.3,
        borderOpacity: 0.7,
        borderWidth: 1,
      ),
      const StationDot(
        coordinate: LatLng(35, 139),
        color: Colors.red,
        radius: 3,
        fillOpacity: 0.3,
        borderOpacity: 0.7,
        borderWidth: 1,
      ),
      const StationDot(
        coordinate: LatLng(35, 139),
        color: Colors.green,
        radius: 4,
        fillOpacity: 0.3,
        borderOpacity: 0.7,
        borderWidth: 1,
      ),
      const StationDot(
        coordinate: LatLng(35, 139),
        color: Colors.green,
        radius: 3,
        fillOpacity: 0.4,
        borderOpacity: 0.7,
        borderWidth: 1,
      ),
      const StationDot(
        coordinate: LatLng(35, 139),
        color: Colors.green,
        radius: 3,
        fillOpacity: 0.3,
        borderOpacity: 0.8,
        borderWidth: 1,
      ),
      const StationDot(
        coordinate: LatLng(35, 139),
        color: Colors.green,
        radius: 3,
        fillOpacity: 0.3,
        borderOpacity: 0.7,
        borderWidth: 2,
      ),
    ];
    for (final changed in changes) {
      await tester.pumpWidget(map([dot]));
      final previous = painter(tester);
      await tester.pumpWidget(map([changed]));
      expect(painter(tester).shouldRepaint(previous), isTrue);
    }
  });

  testWidgets('station count and sizing mode changes still repaint', (
    tester,
  ) async {
    await tester.pumpWidget(map([dot]));
    final previous = painter(tester);
    await tester.pumpWidget(map([dot, dot]));
    expect(painter(tester).shouldRepaint(previous), isTrue);
    await tester.pumpWidget(map([dot], sizeWithCameraZoom: true));
    expect(painter(tester).shouldRepaint(previous), isTrue);
  });

  testWidgets('camera movement still repaints unchanged stations', (
    tester,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(35, 139),
            initialZoom: 5,
          ),
          children: [
            StationDotPainterLayer(dots: [dot]),
          ],
        ),
      ),
    );
    final previous = painter(tester);
    controller.move(const LatLng(36, 139), 6);
    await tester.pump();
    expect(painter(tester).shouldRepaint(previous), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('offscreen updates do not repaint visible original dots', (
    tester,
  ) async {
    const outside = StationDot(
      coordinate: LatLng(-30, -100),
      color: Colors.blue,
      radius: 3,
      fillOpacity: .3,
      borderOpacity: .7,
      borderWidth: 1,
    );
    await tester.pumpWidget(map([dot, outside]));
    final previous = painter(tester);
    await tester.pumpWidget(
      map([
        dot,
        const StationDot(
          coordinate: LatLng(-30, -100),
          color: Colors.yellow,
          radius: 3,
          fillOpacity: .3,
          borderOpacity: .7,
          borderWidth: 1,
        ),
      ]),
    );
    expect(painter(tester).shouldRepaint(previous), isFalse);
    await tester.pumpWidget(map([outside]));
    expect(stationPaint, findsNothing);
  });

  testWidgets('pan and world wrap reveal previously hidden stations', (
    tester,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(-30, -100),
            initialZoom: 5,
          ),
          children: const [
            StationDotPainterLayer(dots: [dot]),
          ],
        ),
      ),
    );
    expect(stationPaint, findsNothing);
    controller.move(const LatLng(35, 139), 5);
    await tester.pump();
    expect(stationPaint, findsOneWidget);
    controller.move(const LatLng(35, 139 + 360), 5);
    await tester.pump();
    expect(stationPaint, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'pan and color updates reuse projections; zoom invalidates them',
    (tester) async {
      const coordinate = LatLng(35.1, 139.1);
      final crs = _CountingCrs(coordinate);
      final controller = MapController();
      final color = ValueNotifier(Colors.green);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: controller,
            options: MapOptions(
              crs: crs,
              initialCenter: const LatLng(35, 139),
              initialZoom: 5,
            ),
            children: [
              ValueListenableBuilder<Color>(
                valueListenable: color,
                builder: (_, value, _) => StationDotPainterLayer(
                  dots: [
                    StationDot(
                      coordinate: coordinate,
                      color: value,
                      radius: 3,
                      fillOpacity: .3,
                      borderOpacity: .7,
                      borderWidth: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      expect(crs.stationProjections, 1);
      controller.move(const LatLng(35.2, 139), 5);
      await tester.pump();
      color.value = Colors.red;
      await tester.pump();
      expect(crs.stationProjections, 1);
      controller.move(const LatLng(35.2, 139), 6);
      await tester.pump();
      expect(crs.stationProjections, 2);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      color.dispose();
    },
  );
}

class _CountingCrs extends Epsg3857 {
  _CountingCrs(this.station);
  final LatLng station;
  final _counts = [0];
  int get stationProjections => _counts[0];
  @override
  Offset latLngToOffset(LatLng latlng, double zoom) {
    if (latlng == station) _counts[0]++;
    return super.latLngToOffset(latlng, zoom);
  }
}
