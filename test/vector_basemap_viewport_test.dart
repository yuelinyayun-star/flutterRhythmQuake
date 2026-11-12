import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/vector_basemap_layer.dart';
import 'package:flutterrhythmquake/services/native_map_coordinates.dart';

void main() {
  for (final size in [const Size(430, 850), const Size(1280, 720)]) {
    testWidgets(
      'viewport projection equals complete original map pixels $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = VectorBasemapService(
          loadAsset: (p) => File(p).readAsString(),
        );
        final data = (await tester.runAsync(service.load))!;
        final controller = MapController();
        final full = ValueNotifier(false);
        addTearDown(controller.dispose);
        addTearDown(full.dispose);
        addTearDown(() => ProjectedPointsTransform.batch = null);
        final key = GlobalKey();
        final original = ColoredBox(
          color: VectorBasemapLayer.oceanColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final dataset in data) ...[
                PolygonLayer<Object>(
                  polygons: [
                    for (final p in dataset.polygons)
                      Polygon<Object>(
                        points: p.rings.first,
                        holePointsList: p.rings.length > 1
                            ? p.rings.sublist(1)
                            : null,
                        color: VectorBasemapLayer.landColor,
                        borderStrokeWidth: 0,
                      ),
                  ],
                  polygonCulling: true,
                  drawInSingleWorld: true,
                  polygonLabels: false,
                  simplificationTolerance: .5,
                ),
                PolylineLayer<Object>(
                  polylines: [
                    for (final p in dataset.borders)
                      Polyline<Object>(
                        points: p,
                        color: VectorBasemapLayer.borderColor,
                        strokeWidth: 1,
                      ),
                  ],
                  cullingMargin: 10,
                  drawInSingleWorld: true,
                  simplificationTolerance: .5,
                ),
              ],
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: FlutterMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(32, 120),
                  initialZoom: 7,
                  minZoom: 1,
                  maxZoom: 18,
                ),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: full,
                    builder: (_, value, child) =>
                        value ? original : VectorBasemapLayer(service: service),
                  ),
                ],
              ),
            ),
          ),
        );
        Future<List<int>> pixels() async => (await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        }))!;
        for (final (center, zoom, rotation) in [
          (const LatLng(32, 120), 7.0, 0.0),
          (const LatLng(37, 137), 5.0, 0.0),
          (const LatLng(25.75, 123.5), 10.0, 0.0),
          (const LatLng(13, 115), 5.0, 0.0),
          (const LatLng(0, 180), 3.0, 0.0),
          (const LatLng(0, -180), 3.0, 35.0),
          (const LatLng(65, -175), 4.0, 0.0),
          (const LatLng(48, 10), 5.0, 45.0),
          (const LatLng(-34, 18), 5.0, 0.0),
          (const LatLng(82, 0), 3.0, 0.0),
          (const LatLng(0, 0), 1.0, 0.0),
        ]) {
        configureNativeMapCoordinates();
        full.value = false;
        controller.moveAndRotate(center, zoom, rotation);
        await tester.pump();
        await tester.runAsync(() async {});
          await tester.pumpAndSettle();
          final optimized = await pixels();
          ProjectedPointsTransform.batch = null;
          full.value = true;
          await tester.pumpAndSettle();
          final reference = await pixels();
          var mismatches = 0;
          for (var i = 0; i < reference.length; i++) {
            if (reference[i] != optimized[i]) mismatches++;
          }
          expect(
            mismatches,
            0,
            reason: '$center zoom=$zoom rotation=$rotation',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
