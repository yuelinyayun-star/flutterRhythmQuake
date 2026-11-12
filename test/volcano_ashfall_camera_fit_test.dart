import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sources/jma_ashfall_forecast_service.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/volcano_ashfall_layer.dart';
import 'package:flutterrhythmquake/widgets/map/volcano_info_focus.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(1584, 850), const Size(430, 900)]) {
    testWidgets(
      'original VFVO55 six window geometries fit without imposing an earthquake anchor $size',
      (tester) async {
        final file = File(
          'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml',
        );
        final hash = sha256.convert(file.readAsBytesSync());
        final xml = file.readAsStringSync(encoding: utf8);
        final windows = JmaAshfallForecastService().parseDetailForTesting(xml);
        expect(windows, hasLength(6));
        final coordinate = RegExp(
          r'<Coordinate\b[^>]*>(.*?)</Coordinate>',
          dotAll: true,
        ).firstMatch(xml)!.group(1)!.replaceAll(RegExp(r'\s+'), '');
        final components = RegExp(
          r'([+]\d{2})(\d{2}\.\d+)([+]\d{3})(\d{2}\.\d+)',
        ).firstMatch(coordinate)!;
        final latitude =
            double.parse(components.group(1)!) +
            double.parse(components.group(2)!) / 60;
        final longitude =
            double.parse(components.group(3)!) +
            double.parse(components.group(4)!) / 60;
        // Only source-derived geometry is needed. No simulated volcano bulletin,
        // updated timestamps or fabricated forecast polygons are introduced.
        final volcano = VolcanoEventData.fromMap({
          'latitude': latitude,
          'longitude': longitude,
          'ashfallWindows': [for (final window in windows) window.toMap()],
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = MapController();
        final state = MapStateProvider();
        final boundaryKey = GlobalKey();
        late BuildContext mapContext;
        final current = ValueNotifier(windows.first);
        final output = Directory(
          'tmp/jma_info_center_20261030/other-filled-runtime',
        )..createSync(recursive: true);
        final results = <Map<String, dynamic>>[];
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  mapContext = context;
                  return RepaintBoundary(
                    key: boundaryKey,
                    child: FlutterMap(
                      mapController: controller,
                      options: MapOptions(
                        initialCenter: LatLng(latitude, longitude),
                        initialZoom: 3,
                      ),
                      children: [
                        ValueListenableBuilder(
                          valueListenable: current,
                          builder: (_, window, _) => PolygonLayer(
                            polygons: VolcanoAshfallLayer.polygonsForWindow(
                              window,
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
          state.setController(controller, const TestVSync());
          for (var index = 0; index < windows.length; index++) {
            // Move the test reference clock, keeping every source time unchanged.
            final now =
                (index == 0
                        ? windows.first.startTime!
                        : windows[index - 1].endTime!)
                    .add(const Duration(seconds: 1));
            final selected = volcano.mapAshfallWindow(now: now)!;
            expect(selected.toMap(), windows[index].toMap());
            current.value = selected;
            final points = volcanoInfoFocusPoints(volcano, now: now);
            final allVertices = [
              for (final item in selected.items)
                for (final polygon in item.polygons)
                  for (final point in polygon)
                    LatLng(point.latitude, point.longitude),
            ];
            expect(points, containsAll(allVertices));
            final padding = cencIrViewportPadding(mapContext);
            state.smartMoveToPoints(
              points,
              padding: .8,
              minZoom: 3,
              maxZoom: 8,
              viewportPadding: padding,
              force: true,
              minInterval: Duration.zero,
            );
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1350)),
            );
            await tester.pump(const Duration(milliseconds: 30));
            final visible = (padding ?? EdgeInsets.zero).deflateRect(
              Offset.zero & size,
            );
            for (final point in points) {
              expect(
                visible
                    .inflate(1)
                    .contains(controller.camera.latLngToScreenOffset(point)),
                isTrue,
                reason: 'window=$index point=$point viewport=$visible',
              );
            }
            final layer = tester.widget<PolygonLayer>(
              find.byType(PolygonLayer),
            );
            expect(
              layer.polygons.length,
              VolcanoAshfallLayer.polygonsForWindow(selected).length,
            );
            expect(layer.polygons, isNotEmpty);
            results.add({
              'window': index + 1,
              'sourceStart': selected.startTime.toString(),
              'sourceEnd': selected.endTime.toString(),
              'polygons': layer.polygons.length,
              'vertices': allVertices.length,
              'zoom': controller.camera.zoom,
              'allVerticesVisible': true,
              'forcedEpicenterAnchor': false,
            });
            if (index == 0 || index == windows.length - 1) {
              await tester.runAsync(() async {
                final image =
                    await (boundaryKey.currentContext!.findRenderObject()
                            as RenderRepaintBoundary)
                        .toImage();
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                File(
                  '${output.path}/volcano-window${index + 1}-${size.width.toInt()}.png',
                ).writeAsBytesSync(png!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
          expect(
            volcanoInfoFocusPoints(
              volcano,
              now: windows.last.endTime!.add(const Duration(seconds: 1)),
            ),
            [LatLng(latitude, longitude)],
          );
          expect(sha256.convert(file.readAsBytesSync()), hash);
          File(
            '${output.path}/volcano-${size.width.toInt()}.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
            encoding: utf8,
          );
          debugPrint(
            'VOLCANO_RAW_WINDOWS_VERIFIED size=$size windows=${results.length} expiredPolygonsExcluded=true sourceSHA256=$hash',
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          current.dispose();
          state.dispose();
          controller.dispose();
        }
      },
    );
  }
}
