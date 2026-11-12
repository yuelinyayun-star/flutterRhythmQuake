import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_layer.dart';
import 'usgs_shakemap_test.dart' show eventFor;

void main() {
  for (final id in ['ci41345415', 'us6000u0xi', 'aka2026tvzrwv']) {
    for (final size in [
      const Size(1584, 850),
      const Size(1200, 800),
      const Size(430, 900),
    ]) {
      testWidgets(
        '$id keeps epicenter centered and raw contours clear of panels $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final detailFile = File(
            'test/fixtures/usgs_shakemap/$id.detail.original.geojson',
          );
          final linesFile = File(
            'test/fixtures/usgs_shakemap/$id.cont_mmi.original.json',
          );
          final detailHash = sha256.convert(detailFile.readAsBytesSync());
          final linesHash = sha256.convert(linesFile.readAsBytesSync());
          final detail =
              jsonDecode(detailFile.readAsStringSync()) as Map<String, dynamic>;
          final frame = UsgsShakeMapFrame(
            event: eventFor(detail),
            product: UsgsShakeMapProduct.fromDetail(detail)!,
            contours: UsgsMmiContour.parse(
              jsonDecode(linesFile.readAsStringSync()) as Map<String, dynamic>,
            ),
          );
          final map = MapController(), state = MapStateProvider();
          addTearDown(state.dispose);
          final boundaryKey = GlobalKey();
          late BuildContext mapContext;
          late EdgeInsets padding;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  mapContext = context;
                  padding = usgsProductViewportPadding(context);
                  return RepaintBoundary(
                    key: boundaryKey,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: map,
                          options: const MapOptions(
                            initialCenter: LatLng(29.36, 120.17),
                            initialZoom: 3,
                            backgroundColor: Color(0xff202426),
                          ),
                          children: [
                            UsgsShakeMapLayer(frame: frame),
                            HistoryMarkerLayer(event: frame.event),
                          ],
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
          state.setController(map, const TestVSync());
          final oldCamera = map.camera;
          focusUsgsShakeMap(context: mapContext, mapState: state, frame: frame);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1300)),
          );
          await tester.pump(const Duration(milliseconds: 30));
          final visible = padding.deflateRect(Offset.zero & size);
          final anchor = LatLng(frame.event.latitude, frame.event.longitude);
          expect(
            (map.camera.latLngToScreenOffset(anchor) - visible.center).distance,
            lessThan(1),
          );
          for (final contour in frame.contours) {
            for (final line in contour.lines) {
              for (final pixel in UsgsMmiContourPainter.projectLine(
                line,
                map.camera,
              )) {
                expect(
                  visible.inflate(1).contains(pixel),
                  isTrue,
                  reason: '$id $size $pixel $visible',
                );
              }
            }
          }
          final before = HistoryCrossPainter(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            magnitude: frame.event.magnitude,
            camera: oldCamera,
          );
          final after = HistoryCrossPainter(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            magnitude: frame.event.magnitude,
            camera: map.camera,
          );
          expect(after.shouldRepaint(before), isTrue);
          expect(after.shouldRepaint(after), isFalse);
          expect(tester.takeException(), isNull);
          if (size.width == 1584) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('tmp/usgs_camera').create(recursive: true);
              await File(
                'tmp/usgs_camera/${id}_centered.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          state.pauseAutoZoom();
          final heldCenter = map.camera.center;
          focusUsgsShakeMap(context: mapContext, mapState: state, frame: frame);
          await tester.pump(const Duration(seconds: 2));
          expect(map.camera.center, heldCenter);
          state.resumeAutoZoom();
          expect(sha256.convert(detailFile.readAsBytesSync()), detailHash);
          expect(sha256.convert(linesFile.readAsBytesSync()), linesHash);
          await tester.pumpWidget(const SizedBox.shrink());
          map.dispose();
        },
      );
    }
  }
}
