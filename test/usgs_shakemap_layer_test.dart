import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_layer.dart';
import 'usgs_shakemap_test.dart' show eventFor;

void main() {
  for (final id in ['ci41345415', 'us6000u0xi', 'aka2026tvzrwv']) {
    testWidgets('$id renders across world copies and the date line', (
      tester,
    ) async {
      final detail =
          jsonDecode(
                File(
                  'test/fixtures/usgs_shakemap/$id.detail.original.geojson',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      final product = UsgsShakeMapProduct.fromDetail(detail)!;
      final frame = UsgsShakeMapFrame(
        event: eventFor(detail),
        product: product,
        contours: UsgsMmiContour.parse(
          jsonDecode(
                File(
                  'test/fixtures/usgs_shakemap/$id.cont_mmi.original.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>,
        ),
      );
      final controller = MapController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(29.36, 120.17),
                initialZoom: 3,
              ),
              children: [UsgsShakeMapLayer(frame: frame)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final longitude in [120.17, -120.0, 179.0, -179.0]) {
        controller.move(LatLng(frame.event.latitude, longitude), 3);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(OverlayImageLayer), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(CustomPaint), findsWidgets);
        for (final contour in frame.contours) {
          for (final line in contour.lines) {
            final projected = UsgsMmiContourPainter.projectLine(
              line,
              controller.camera,
            );
            expect(projected.length, line.length);
            for (var i = 1; i < projected.length; i++) {
              final expected =
                  (line[i].longitude - line[i - 1].longitude).abs() /
                  360 *
                  256 *
                  8;
              expect(
                (projected[i].dx - projected[i - 1].dx).abs(),
                closeTo(expected, 1e-6),
              );
            }
          }
        }
        controller.rotate(25);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        controller.rotate(0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
