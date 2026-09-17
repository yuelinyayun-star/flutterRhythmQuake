import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';
import 'package:flutterrhythmquake/services/boundary_service.dart';
import 'package:flutterrhythmquake/widgets/map/vector_basemap_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(430, 850), const Size(1280, 720)]) {
    testWidgets('offline vector basemap rendering, caches and camera $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MapController();
      final selected = ValueNotifier(true);
      final rebuild = ValueNotifier(0);
      addTearDown(controller.dispose);
      addTearDown(selected.dispose);
      addTearDown(rebuild.dispose);
      var reads = 0;
      final service = VectorBasemapService(
        loadAsset: (p) async {
          reads++;
          return File(p).readAsStringSync();
        },
      );
      final loadWatch = Stopwatch()..start();
      await tester.runAsync(service.load);
      loadWatch.stop();
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (_, count, child) => FlutterMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(32, 120),
                  initialZoom: 4,
                  minZoom: 3,
                  maxZoom: 18,
                ),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: selected,
                    builder: (_, enabled, child) => enabled
                        ? VectorBasemapLayer(service: service)
                        : const ColoredBox(color: Colors.black),
                  ),
                  const VectorBasemapLabels(),
                  const MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(32, 120),
                        width: 20,
                        height: 20,
                        child: Icon(Icons.location_on, color: Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(find.byType(PolygonLayer), findsNWidgets(3));
      expect(find.byType(PolylineLayer), findsNWidgets(3));
      expect(find.byType(TileLayer), findsNothing);
      final before = tester
          .widgetList<PolygonLayer>(find.byType(PolygonLayer))
          .toList();
      expect(before.map((p) => p.polygons.length), [1561, 400, 421]);
      final shots = [
        ('east-asia', const LatLng(32, 120), 4.0),
        ('japan', const LatLng(37, 137), 5.0),
        ('diaoyu', const LatLng(25.75, 123.5), 10.0),
        ('south-china-sea', const LatLng(13, 115), 5.0),
        ('pacific', const LatLng(0, 180), 3.0),
      ];
      for (final (name, center, zoom) in shots) {
        controller.move(center, zoom);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var landPixels = 0;
          for (var i = 0; i < bytes.lengthInBytes; i += 4) {
            if (bytes.getUint8(i) == 57 &&
                bytes.getUint8(i + 1) == 57 &&
                bytes.getUint8(i + 2) == 57) {
              landPixels++;
            }
          }
          expect(landPixels, greaterThan(25), reason: '$name: blank map');
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final dir = Directory('tmp/vector_basemap_review')
            ..createSync(recursive: true);
          File(
            '${dir.path}/$name-${size.width.toInt()}.png',
          ).writeAsBytesSync(png.buffer.asUint8List());
          image.dispose();
        });
      }
      final frames = <int>[];
      controller.move(const LatLng(36, 136), 5);
      await tester.pumpAndSettle();
      for (var i = 0; i < 30; i++) {
        final watch = Stopwatch()..start();
        controller.move(LatLng(36 + i * .03, 136 + i * .04), 5);
        await tester.pump();
        watch.stop();
        frames.add(watch.elapsedMicroseconds);
      }
      frames.sort();
      // Flutter test-engine timings are diagnostic, not device FPS claims.
      // ignore: avoid_print
      print(
        'Vector $size: load=${loadWatch.elapsedMilliseconds}ms; warm pump median=${frames[15]}us p95=${frames[28]}us',
      );
      rebuild.value++;
      await tester.pump();
      final after = tester
          .widgetList<PolygonLayer>(find.byType(PolygonLayer))
          .toList();
      for (var i = 0; i < 3; i++) {
        expect(identical(before[i], after[i]), isTrue);
      }
      final center = controller.camera.center;
      await tester.drag(find.byType(FlutterMap), const Offset(70, 25));
      await tester.pumpAndSettle();
      expect(controller.camera.center, isNot(center));
      final retained = controller.camera.center;
      selected.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(PolygonLayer), findsNothing);
      selected.value = true;
      await tester.pump();
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(controller.camera.center, retained);
      expect(reads, 3);
      expect(find.byType(PolygonLayer), findsNWidgets(3));
      expect(BoundaryService().isLoaded, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
