import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_layer.dart';
import 'information_camera_group_test.dart' show frameFor;

final legendTitle = find.textContaining('USGS ShakeMap · MMI');

void main() {
  for (final id in ['ci41345415', 'us6000u0xi', 'aka2026tvzrwv']) {
    testWidgets('$id legend follows camera, rotation and world copy', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(TopoJsonLoader.loadCnEew);
      final cenc = CencIrData.fromNowQuakeJson(
        jsonDecode(
              File(
                'test/fixtures/cenc_ir_zaduo_20261024163952.original.json',
              ).readAsStringSync(encoding: utf8),
            )
            as Map<String, dynamic>,
      );
      final frame = frameFor(id);
      final before = jsonEncode(frame.event.toMap());
      final map = MapController();
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: LatLng(cenc.epiLat, cenc.epiLon),
              initialZoom: 6,
            ),
            children: [
              UsgsShakeMapLayer(frame: frame, showLegend: false),
              CencIrLayer(data: cenc),
              UsgsShakeMapLegend(frame: frame),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CencIrLayer), findsOneWidget);
      expect(legendTitle, findsNothing);
      for (final shift in [0.0, 360.0, -360.0]) {
        map.move(
          LatLng(frame.event.latitude, frame.event.longitude + shift),
          6,
        );
        map.rotate(25);
        await tester.pumpAndSettle();
        expect(legendTitle, findsOneWidget);
      }
      map.move(LatLng(cenc.epiLat, cenc.epiLon), 6);
      await tester.pumpAndSettle();
      expect(legendTitle, findsNothing);
      expect(tester.takeException(), isNull);
      expect(jsonEncode(frame.event.toMap()), before);
      await tester.pumpWidget(const SizedBox.shrink());
      map.dispose();
    });
  }

  testWidgets('visible contour shows legend with offscreen epicenter', (
    tester,
  ) async {
    final frame = frameFor('us6000u0xi');
    final epicenter = LatLng(frame.event.latitude, frame.event.longitude);
    double distance(LatLng p) =>
        (p.latitude - epicenter.latitude).abs() +
        (p.longitude - epicenter.longitude).abs();
    final points = [
      for (final c in frame.contours)
        for (final line in c.lines) ...line,
    ]..sort((a, b) => distance(b).compareTo(distance(a)));
    final map = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: map,
          options: MapOptions(initialCenter: points.first, initialZoom: 12),
          children: [UsgsShakeMapLegend(frame: frame)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = Offset.zero & map.camera.nonRotatedSize;
    expect(
      viewport.contains(map.camera.latLngToScreenOffset(epicenter)),
      isFalse,
    );
    expect(UsgsMmiContourPainter.hasVisibleContour(frame, map.camera), isTrue);
    expect(legendTitle, findsOneWidget);
    // The grid rectangle alone does not mean a contour is visible.
    map.move(LatLng(frame.product.north, frame.product.east), 16);
    await tester.pumpAndSettle();
    expect(UsgsMmiContourPainter.hasVisibleContour(frame, map.camera), isFalse);
    expect(legendTitle, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    map.dispose();
  });

  testWidgets('loading status follows selected event geography', (
    tester,
  ) async {
    final frame = frameFor('ci41345415');
    final map = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: LatLng(frame.event.latitude, frame.event.longitude),
            initialZoom: 6,
          ),
          children: [
            UsgsShakeMapLegend(
              status: '正在加载 USGS ShakeMap',
              statusEvent: frame.event,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在加载 USGS ShakeMap'), findsOneWidget);
    map.move(const LatLng(32.54, 93.97), 6);
    await tester.pumpAndSettle();
    expect(find.text('正在加载 USGS ShakeMap'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    map.dispose();
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('fill cannot tint legend or block map tap at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final frame = frameFor('ci41345415');
      final map = MapController();
      final key = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: LatLng(
                  frame.event.latitude,
                  frame.event.longitude,
                ),
                initialZoom: 6,
                onTap: (_, _) => taps++,
              ),
              children: [
                UsgsShakeMapLayer(frame: frame, showLegend: false),
                // UI-only paint-order probe; never a source observation.
                const IgnorePointer(child: ColoredBox(color: Colors.blue)),
                UsgsShakeMapLegend(frame: frame),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(legendTitle, findsOneWidget);
      final rect = tester.getRect(legendTitle);
      final image = (await tester.runAsync(
        () async =>
            (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
                .toImage(),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      var white = 0;
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
        for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
          final i = (y * image.width + x) * 4;
          if (bytes.getUint8(i) > 220 &&
              bytes.getUint8(i + 1) > 220 &&
              bytes.getUint8(i + 2) > 220) {
            white++;
          }
        }
      }
      expect(white, greaterThan(20));
      image.dispose();
      await tester.tapAt(rect.center);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      map.dispose();
    });
  }
}
