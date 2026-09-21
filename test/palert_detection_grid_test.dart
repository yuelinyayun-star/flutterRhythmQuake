import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/palert_detection_grid.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/widgets/map/palert_station_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final now = DateTime.utc(2026, 9, 19, 12);
  PAlertStation station(
    String id,
    double lat,
    double lng,
    int intensity, {
    DateTime? receivedAt,
  }) => PAlertStation(
    id: id,
    network: 'P-Alert',
    name: id,
    area: '',
    coordinate: LatLng(lat, lng),
    cwaIntensityIndex: intensity,
    dataTime: now,
    receivedAt: receivedAt ?? now,
  );

  const first = PAlertDetectionGridCell(center: LatLng(23.5, 121), level: 15);
  const distant = PAlertDetectionGridCell(center: LatLng(25.5, 122), level: 9);

  test(
    'camera consumes all confirmed detection cells without station filtering',
    () {
      final grid = PAlertDetectionGrid()..update([first, distant]);
      expect(grid.centers, [const LatLng(23.5, 121), const LatLng(25.5, 122)]);
      expect(grid.cells.map((cell) => cell.level), [15, 9]);
    },
  );

  test('an empty detector snapshot clears camera points', () {
    final grid = PAlertDetectionGrid()..update([first]);
    grid.update([]);
    expect(grid.cells, isEmpty);
    expect(grid.signature, isEmpty);
  });

  test('confirmed zero-level hold is kept until the detector ends it', () {
    final grid = PAlertDetectionGrid()
      ..update([
        const PAlertDetectionGridCell(center: LatLng(23.5, 121), level: 0),
      ]);
    expect(grid.centers, [const LatLng(23.5, 121)]);
    grid.clear();
    expect(grid.centers, isEmpty);
  });

  test('input ordering does not change the camera signature', () {
    final a = PAlertDetectionGrid()..update([first, distant]);
    final b = PAlertDetectionGrid()..update([distant, first]);
    expect(a.signature, b.signature);
  });

  for (final size in [const Size(1280, 720), const Size(390, 844)]) {
    testWidgets(
      'grid borders match camera centers and blink at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final stations = [station('active', 23.54, 121.04, 4)];
        final grid = PAlertDetectionGrid()..update([first]);
        Future<void> render({bool blink = true, bool hide = false}) async {
          await tester.pumpWidget(
            MaterialApp(
              home: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(23.5, 121),
                  initialZoom: 6,
                ),
                children: [
                  PAlertStationLayer(
                    stations: stations,
                    detectionGridCells: grid.cells,
                    blinkOn: blink,
                    hideGrid: hide,
                  ),
                ],
              ),
            ),
          );
        }

        await render();
        final polygon = tester
            .widget<PolygonLayer>(find.byType(PolygonLayer))
            .polygons
            .single;
        final lat =
            polygon.points.map((p) => p.latitude).reduce((a, b) => a + b) / 4;
        final lng =
            polygon.points.map((p) => p.longitude).reduce((a, b) => a + b) / 4;
        expect(lat, closeTo(grid.centers.single.latitude, 1e-9));
        expect(lng, closeTo(grid.centers.single.longitude, 1e-9));
        expect(polygon.borderColor, const Color(0xFFFF0000));
        expect(polygon.color, Colors.transparent);
        await render(blink: false);
        expect(
          tester
              .widget<PolygonLayer>(find.byType(PolygonLayer))
              .polygons
              .single
              .borderColor
              .a,
          0,
        );
        await render(hide: true);
        expect(find.byType(PolygonLayer), findsNothing);
        grid.clear();
        await render();
        expect(find.byType(PolygonLayer), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
