import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/ka_kma_marker_style.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  for (final ratio in [1.0, 1.25]) {
    for (final zoomSized in [false, true]) {
      testWidgets(
        'circles match original direct-render pixels DPR $ratio sized $zoomSized',
        (tester) async {
          tester.view.devicePixelRatio = ratio;
          tester.view.physicalSize = Size(640 * ratio, 400 * ratio);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final controller = MapController();
          final key = GlobalKey();
          final reference = ValueNotifier(false);
          final data = ValueNotifier([
            for (var i = 0; i < 150; i++)
              StationDot(
                coordinate: LatLng(32 + (i % 15) * .59, 133 + (i ~/ 15) * .81),
                color: [
                  Colors.blue,
                  Colors.green,
                  Colors.yellow,
                  Colors.red,
                ][i % 4],
                radius: .9 + i % 5,
                fillOpacity: i % 3 == 0 ? .08 : .36,
                borderOpacity: i % 3 == 1 ? .22 : .9,
                borderWidth: .35 + (i % 3) * .25,
              ),
            const StationDot(
              coordinate: LatLng(35, 139),
              color: Colors.cyan,
              radius: 9,
              fillOpacity: .3,
              borderOpacity: .8,
              borderWidth: 2,
            ),
            const StationDot(
              coordinate: LatLng(35, 139),
              color: Colors.purple,
              radius: 3,
              fillOpacity: .8,
              borderOpacity: .3,
              borderWidth: 1,
            ),
          ]);
          addTearDown(controller.dispose);
          addTearDown(reference.dispose);
          addTearDown(data.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: key,
                child: FlutterMap(
                  mapController: controller,
                  options: const MapOptions(
                    initialCenter: LatLng(35, 139),
                    initialZoom: 5,
                  ),
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: reference,
                      builder: (_, ref, _) =>
                          ValueListenableBuilder<List<StationDot>>(
                            valueListenable: data,
                            builder: (_, dots, _) => ref
                                ? _ReferenceLayer(dots, zoomSized)
                                : StationDotPainterLayer(
                                    dots: dots,
                                    sizeWithCameraZoom: zoomSized,
                                  ),
                          ),
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
                    .toImage(pixelRatio: ratio);
            try {
              return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }))!;
          for (final (center, zoom, rotation) in [
            (const LatLng(35, 139), 5.0, 0.0),
            (const LatLng(35.023, 139.17), 5.0, 0.0),
            (const LatLng(35.15, 139.3), 5.0, 0.0),
            (const LatLng(35.15, 139.3), 5.45, 0.0),
            (const LatLng(35.15, 139.3), 5.45, 35.0),
            (const LatLng(35.15, 139.3), 5.45, 80.0),
            (const LatLng(35, 139 + 360), 5.0, 0.0),
            (const LatLng(-30, -100), 5.0, 0.0),
            (const LatLng(35, 139), 5.0, 0.0),
          ]) {
            reference.value = false;
            controller.moveAndRotate(center, zoom, rotation);
            await tester.pump();
            final actual = await pixels();
            reference.value = true;
            await tester.pump();
            final original = await pixels();
            var changed = 0, maximum = 0;
            for (var i = 0; i < actual.length; i++) {
              final delta = (actual[i] - original[i]).abs();
              if (delta != 0) changed++;
              if (delta > maximum) maximum = delta;
            }
            expect(
              changed,
              0,
              reason: '$center zoom=$zoom rotation=$rotation maxDelta=$maximum',
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}

class _ReferenceLayer extends StatelessWidget {
  const _ReferenceLayer(this.dots, this.sized);
  final List<StationDot> dots;
  final bool sized;
  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        size: camera.size,
        painter: _ReferencePainter(camera, dots, sized),
      ),
    );
  }
}

/// Independent original direct-circle rendering, including original culling,
/// order, world copies and alpha. No cached implementation calls.
class _ReferencePainter extends CustomPainter {
  _ReferencePainter(this.camera, this.dots, this.sized);
  final MapCamera camera;
  final List<StationDot> dots;
  final bool sized;
  @override
  void paint(Canvas canvas, Size size) {
    final world = camera.getWorldWidthAtZoom(),
        visible = camera.pixelBounds.inflate(12);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;
    for (final dot in dots) {
      final p = camera.projectAtZoom(dot.coordinate);
      final radius = sized
          ? KaKmaMarkerStyle.dotSizeForZoom(camera.zoom) / 2
          : dot.radius;
      final width = sized
          ? KaKmaMarkerStyle.borderWidthForZoom(camera.zoom)
          : dot.borderWidth;
      bool intersects(Offset p) =>
          visible.overlaps(Rect.fromCircle(center: p, radius: radius));
      if (!intersects(p) &&
          !(world != 0 &&
              (intersects(p - Offset(world, 0)) ||
                  intersects(p + Offset(world, 0))))) {
        continue;
      }
      void draw(Offset p) {
        if (!intersects(p)) return;
        final local = p - camera.pixelOrigin;
        if (dot.fillOpacity.clamp(0.0, 1.0) > 0) {
          fill.color = dot.color.withValues(
            alpha: dot.fillOpacity.clamp(0.0, 1.0),
          );
          canvas.drawCircle(local, radius, fill);
        }
        if (dot.borderOpacity.clamp(0.0, 1.0) > 0 && width > 0) {
          stroke
            ..color = dot.color.withValues(
              alpha: dot.borderOpacity.clamp(0.0, 1.0),
            )
            ..strokeWidth = width;
          canvas.drawCircle(local, radius, stroke);
        }
      }

      draw(p);
      if (world == 0) continue;
      for (double shift = -world; ; shift -= world) {
        final next = p + Offset(shift, 0);
        if (!intersects(next)) break;
        draw(next);
      }
      for (double shift = world; ; shift += world) {
        final next = p + Offset(shift, 0);
        if (!intersects(next)) break;
        draw(next);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReferencePainter old) => true;
}
