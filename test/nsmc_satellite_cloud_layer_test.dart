import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/nsmc_satellite_cloud_layer.dart';
import 'package:flutterrhythmquake/services/sources/nsmc_satellite_cloud_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final sourcePath = Platform.environment['NSMC_CLOUD_TEST_IMAGE'];
  testWidgets(
    'official cloud image renders across dateline on desktop and phone',
    (tester) async {
      final frame = NsmcSatelliteCloudFrame(
        time: DateTime.utc(2026, 9, 22, 8),
        imageBytes: nsmcSatelliteToMercator(
          File(sourcePath!).readAsBytesSync(),
        ),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(1200, 700), const Size(420, 800)]) {
        tester.view.physicalSize = size;
        for (final longitude in [179.0, -179.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: const ValueKey('cloud-preview'),
                child: FlutterMap(
                  key: ValueKey('$size-$longitude'),
                  options: MapOptions(
                    initialCenter: LatLng(25, longitude),
                    initialZoom: 2.5,
                    backgroundColor: const Color(0xFF202124),
                  ),
                  children: [NsmcSatelliteCloudLayer(frame: frame)],
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await precacheImage(
              MemoryImage(frame.imageBytes),
              tester.element(find.byType(FlutterMap)),
            );
          });
          await tester.pumpAndSettle();
          expect(find.byType(Image), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('cloud-preview')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File(
              'build/satellite-cloud-qa/wrapped-${size.width.toInt()}-$longitude.png',
            );
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: sourcePath == null,
  );
  for (final longitude in [140.0, 179.0, -179.0, 220.0, -220.0]) {
    for (final zoom in [0.0, 2.5, 5.0]) {
      for (final rotation in [0.0, 35.0]) {
        test('continuous coverage at $longitude / $zoom / $rotation', () {
          final camera = MapCamera(
            crs: const Epsg3857(),
            center: LatLng(30, longitude),
            zoom: zoom,
            rotation: rotation,
            nonRotatedSize: const Size(1600, 900),
          );
          final copies = nsmcSatelliteWorldRects(camera);
          expect(copies, isNotEmpty);
          expect(copies.first.left, lessThanOrEqualTo(camera.pixelBounds.left));
          expect(
            copies.last.right,
            greaterThanOrEqualTo(camera.pixelBounds.right),
          );
          for (var i = 0; i < copies.length; i++) {
            expect(
              copies[i].width,
              closeTo(camera.getWorldWidthAtZoom(), 1e-8),
            );
            if (i > 0) {
              expect(copies[i].left, closeTo(copies[i - 1].right, 1e-8));
            }
          }
        });
      }
    }
  }
}
