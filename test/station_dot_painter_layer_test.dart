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
}
