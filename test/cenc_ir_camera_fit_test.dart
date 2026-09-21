import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_layer.dart';
import 'package:latlong2/latlong.dart';

Rect screenBounds(MapCamera camera, List<LatLng> points) {
  final offsets = points.map(
    (point) => camera.projectAtZoom(point) - camera.pixelOrigin,
  );
  return Rect.fromLTRB(
    offsets.map((p) => p.dx).reduce(math.min),
    offsets.map((p) => p.dy).reduce(math.min),
    offsets.map((p) => p.dx).reduce(math.max),
    offsets.map((p) => p.dy).reduce(math.max),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('JetBrainsMono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf'));
    await font.load();
  });
  // Unmodified production responses retained in test/fixtures.
  for (final fixture in [
    'cenc_ir_mojiang_20260914170727.json',
    'cenc_ir_qiaojia_20260908013139.json',
  ]) {
    final data = CencIrData.fromNowQuakeJson(
      jsonDecode(File('test/fixtures/$fixture').readAsStringSync())
          as Map<String, dynamic>,
    );
    final points = cencIrFocusPoints(
      data: data,
      eventId: data.reportId,
      epicenterLatitude: data.epiLat,
      epicenterLongitude: data.epiLon,
    );
    final epicenter = LatLng(data.epiLat, data.epiLon);
    for (final size in [
      const Size(1584, 850),
      const Size(1200, 800),
      const Size(1920, 1080),
      const Size(1000, 600),
      const Size(430, 900),
    ]) {
      testWidgets(
        'raw $fixture fits stations around the centered epicenter $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = MapController();
          final provider = MapStateProvider();
          addTearDown(provider.dispose);
          final boundaryKey = GlobalKey();
          late EdgeInsets padding;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  padding =
                      cencIrViewportPadding(context) ??
                      const EdgeInsets.all(50);
                  return RepaintBoundary(
                    key: boundaryKey,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: controller,
                          options: MapOptions(
                            initialCenter: LatLng(data.epiLat, data.epiLon),
                            initialZoom: 6,
                            backgroundColor: const Color(0xFF202426),
                          ),
                          children: [CencIrLayer(data: data)],
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Padding(
                              padding: padding,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.cyan),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
          provider.setController(controller, const TestVSync());
          Future<void> finishMove() async {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1300)),
            );
            await tester.pump(const Duration(milliseconds: 30));
          }

          Future<void> capture(String name) async {
            if (size.width != 1584) return;
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('tmp/cenc_ir_camera').create(recursive: true);
              await File(
                'tmp/cenc_ir_camera/${data.reportId}_$name.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          provider.smartMoveToPoints(
            points,
            padding: 0.8,
            force: true,
            minInterval: Duration.zero,
          );
          await finishMove();
          final before = screenBounds(controller.camera, points);
          final beforeZoom = controller.camera.zoom;
          await capture('before');
          provider.smartMoveToPoints(
            points,
            viewportPadding: padding,
            focusAnchor: epicenter,
            maxZoom: 12,
            force: true,
            minInterval: Duration.zero,
          );
          await finishMove();
          final bounds = screenBounds(controller.camera, points);
          final visible = padding.deflateRect(Offset.zero & size);
          expect(points.length, greaterThan(1));
          for (final point in points) {
            final offset =
                controller.camera.projectAtZoom(point) -
                controller.camera.pixelOrigin;
            expect(
              visible.inflate(1).contains(offset),
              isTrue,
              reason: '$point',
            );
          }
          final epicenterPixel =
              controller.camera.projectAtZoom(epicenter) -
              controller.camera.pixelOrigin;
          expect((epicenterPixel - visible.center).distance, lessThan(1));
          final horizontalSpan =
              math.max(
                (bounds.left - visible.center.dx).abs(),
                (bounds.right - visible.center.dx).abs(),
              ) *
              2;
          final verticalSpan =
              math.max(
                (bounds.top - visible.center.dy).abs(),
                (bounds.bottom - visible.center.dy).abs(),
              ) *
              2;
          expect(
            math.max(
              horizontalSpan / visible.width,
              verticalSpan / visible.height,
            ),
            closeTo(1, 0.01),
          );
          debugPrint(
            'CENC_IR_CAMERA $size stations=${data.instrumentIntensities.length} '
            'zoom=$beforeZoom -> ${controller.camera.zoom} '
            'stationBounds=$before -> $bounds visible=$visible',
          );
          await capture('after');

          // Existing user gesture pause still takes precedence over auto framing.
          provider.pauseAutoZoom();
          final pausedCenter = controller.camera.center;
          provider.smartMoveToPoints(
            [points.first],
            viewportPadding: padding,
            focusAnchor: epicenter,
            maxZoom: 12,
            force: true,
          );
          await finishMove();
          expect(controller.camera.center, pausedCenter);
          provider.resumeAutoZoom();
          provider.smartMoveToPoints(
            [points.first],
            viewportPadding: padding,
            focusAnchor: epicenter,
            maxZoom: 12,
            force: true,
          );
          await finishMove();
          expect(controller.camera.zoom.isFinite, isTrue);
          expect(controller.camera.zoom, 12);
          final finalEpicenterPixel =
              controller.camera.projectAtZoom(epicenter) -
              controller.camera.pixelOrigin;
          expect((finalEpicenterPixel - visible.center).distance, lessThan(1));
        },
      );
    }
  }

  testWidgets('phone retains its existing framing policy', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(cencIrViewportPadding(context), isNull);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
