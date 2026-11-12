import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  for (final display0 in [false, true]) {
    testWidgets(
      'information dots restore original symbols and preserve grids display0=$display0',
      (tester) async {
        tester.view.physicalSize = const Size(800, 450);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Deliberate render-level coverage, not observations or detector input.
        final stations = [
          for (final (i, level) in [-1, 0, 5, 6, 8, 12, 16, 20].indexed)
            NiedStation(
              id: i,
              code: 'render-$i',
              name: 'render-$i',
              coordinate: LatLng(35, 138 + i * .3),
              network: 'K-NET',
              prefecture: '',
              expireSeconds: 10,
              level: level,
            ),
        ];
        stations.last.gifLayerQualityFlags[NiedGifLayer.realtimeShindo] = {
          'missing',
        };
        final beforeLevels = stations.map((s) => s.level).toList();
        final beforeActivity = stations
            .map(
              (s) => [
                s.isActive,
                s.activity,
                s.detectState,
                s.recentLevel.toList(),
              ],
            )
            .toList();
        const grid = {
          'cell': NiedDetectionGridCell(
            center: LatLng(35, 139),
            level: 12,
            shindo: 3,
          ),
        };
        final mode = ValueNotifier(false);
        final blink = ValueNotifier(true);
        final controller = MapController();
        final capture = GlobalKey();
        var callbacks = 0;
        addTearDown(mode.dispose);
        addTearDown(blink.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: capture,
              child: ColoredBox(
                color: const Color(0xFF202124),
                child: FlutterMap(
                  mapController: controller,
                  options: const MapOptions(
                    initialCenter: LatLng(35, 139),
                    initialZoom: 7,
                  ),
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: mode,
                      builder: (_, dotsOnly, _) => ValueListenableBuilder<bool>(
                        valueListenable: blink,
                        builder: (_, blinkOn, _) => NiedIntensityLayer(
                          stations: stations,
                          displayShindo0: display0,
                          informationFocusDotsOnly: dotsOnly,
                          blinkOn: blinkOn,
                          detectionGridCells: grid,
                          onGridCellsChanged: (_) => callbacks++,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final root = find.byType(NiedIntensityLayer);
        Finder beneath(Type type) =>
            find.descendant(of: root, matching: find.byType(type));
        List<StationDot> dots() => tester
            .widget<StationDotPainterLayer>(beneath(StationDotPainterLayer))
            .dots;
        List<Polygon> polygons() =>
            tester.widget<PolygonLayer>(beneath(PolygonLayer)).polygons;
        Future<List<int>> pixels([String? name]) async =>
            (await tester.runAsync(() async {
              final image =
                  await (capture.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              try {
                if (name != null) {
                  final output = File(
                    'tmp/nied_information_focus_style_20261103/$name.png',
                  )..parent.createSync(recursive: true);
                  output.writeAsBytesSync(
                    (await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    ))!.buffer.asUint8List(),
                  );
                }
                return (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List().toList();
              } finally {
                image.dispose();
              }
            }))!;
        final originalPixels = await pixels('normal-$display0');
        final originalDots = List<StationDot>.of(dots());
        final originalGrid = polygons().single;
        final iconCount = tester
            .widget<MarkerLayer>(beneath(MarkerLayer))
            .markers
            .length;
        expect(iconCount, display0 ? 4 : 3);
        mode.value = true;
        await tester.pump();
        expect(beneath(MarkerLayer), findsNothing);
        expect(dots(), hasLength(stations.length));
        for (final original in originalDots) {
          final current = dots().singleWhere(
            (d) => d.coordinate == original.coordinate,
          );
          expect(
            (
              current.color,
              current.radius,
              current.fillOpacity,
              current.borderOpacity,
              current.borderWidth,
            ),
            (
              original.color,
              original.radius,
              original.fillOpacity,
              original.borderOpacity,
              original.borderWidth,
            ),
          );
        }
        expect(
          dots()
              .singleWhere((d) => d.coordinate == stations[4].coordinate)
              .color,
          const Color(0xFF8282FF),
        );
        expect(
          dots()
              .singleWhere((d) => d.coordinate == stations[5].coordinate)
              .color,
          const Color(0xFF00DC8C),
        );
        expect(
          dots()
              .singleWhere((d) => d.coordinate == stations[6].coordinate)
              .color,
          const Color(0xFFFFB400),
        );
        expect(polygons().single.points, originalGrid.points);
        expect(polygons().single.borderColor, originalGrid.borderColor);
        expect(
          polygons().single.borderStrokeWidth,
          originalGrid.borderStrokeWidth,
        );
        await pixels('information-dots-$display0');
        blink.value = false;
        await tester.pump();
        expect(polygons().single.borderColor.a, 0);
        expect(beneath(MarkerLayer), findsNothing);
        expect(callbacks, 1);
        blink.value = true;
        mode.value = false;
        await tester.pump();
        expect(
          tester.widget<MarkerLayer>(beneath(MarkerLayer)).markers.length,
          iconCount,
        );
        expect(await pixels(), originalPixels);
        expect(stations.map((s) => s.level).toList(), beforeLevels);
        expect(
          stations
              .map(
                (s) => [
                  s.isActive,
                  s.activity,
                  s.detectState,
                  s.recentLevel.toList(),
                ],
              )
              .toList(),
          beforeActivity,
        );
        expect(callbacks, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
