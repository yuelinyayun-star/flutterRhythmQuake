import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_focus.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'usgs_dyfi_test.dart' show originalDetail, emptyDyfiDetail, dyfiEvent;

UsgsDyfiFrame originalFrame(String id) {
  final detail = id == 'us6000u1em' ? emptyDyfiDetail() : originalDetail(id);
  return UsgsDyfiFrame(
    event: dyfiEvent(detail),
    product: UsgsDyfiProduct.fromDetail(detail)!,
    cells: UsgsDyfiCell.parse(
      jsonDecode(
        File(
          'test/fixtures/usgs_dyfi/$id.dyfi_geo_10km.original.geojson',
        ).readAsStringSync(encoding: utf8),
      ),
    ),
  );
}

double smallestCellSide(MapCamera camera, UsgsDyfiFrame frame) {
  var result = double.infinity;
  for (final cell in frame.cells!) {
    final points = cell.rings.first.map(camera.projectAtZoom).toList();
    final width =
        points.map((p) => p.dx).reduce(max) -
        points.map((p) => p.dx).reduce(min);
    final height =
        points.map((p) => p.dy).reduce(max) -
        points.map((p) => p.dy).reduce(min);
    result = min(result, min(width, height));
  }
  return result;
}

void main() {
  for (final id in ['ci41345415', 'us6000u0xi', 'us6000u1em']) {
    for (final size in [
      const Size(1584, 850),
      const Size(1200, 800),
      const Size(430, 900),
    ]) {
      testWidgets(
        '$id DYFI stays at usable viewport center with legible grids $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final file = File(
            'test/fixtures/usgs_dyfi/$id.dyfi_geo_10km.original.geojson',
          );
          final originalHash = sha256.convert(file.readAsBytesSync());
          final frame = originalFrame(id);
          final map = MapController(), state = MapStateProvider();
          addTearDown(state.dispose);
          late BuildContext mapContext;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  mapContext = context;
                  return FlutterMap(
                    mapController: map,
                    options: const MapOptions(
                      initialCenter: LatLng(29.36, 120.17),
                      initialZoom: 3,
                    ),
                    children: [
                      UsgsDyfiGridLayer(frame: frame, interactive: false),
                    ],
                  );
                },
              ),
            ),
          );
          state.setController(map, const TestVSync());
          final minimumZoom = dyfiMinimumZoom(map.camera, frame);
          focusUsgsDyfi(context: mapContext, mapState: state, frame: frame);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1300)),
          );
          await tester.pump(const Duration(milliseconds: 30));
          final viewport = usgsProductViewportPadding(
            mapContext,
          ).deflateRect(Offset.zero & size);
          final anchor = LatLng(frame.event.latitude, frame.event.longitude);
          expect(
            (map.camera.latLngToScreenOffset(anchor) - viewport.center)
                .distance,
            lessThan(1),
          );
          expect(map.camera.zoom, greaterThanOrEqualTo(minimumZoom - 1e-6));
          if (frame.cells!.isNotEmpty) {
            expect(
              smallestCellSide(map.camera, frame),
              greaterThanOrEqualTo(dyfiMinimumCellPixels - 1e-5),
            );
          }
          // Manual navigation remains free to zoom out beyond the automatic limit.
          state.pauseAutoZoom();
          map.move(map.camera.center, minimumZoom - 1);
          final heldCamera = map.camera;
          focusUsgsDyfi(context: mapContext, mapState: state, frame: frame);
          await tester.pump(const Duration(seconds: 2));
          expect(map.camera.center, heldCamera.center);
          expect(map.camera.zoom, heldCamera.zoom);
          state.resumeAutoZoom();
          expect(sha256.convert(file.readAsBytesSync()), originalHash);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          map.dispose();
        },
      );
    }
  }

  for (final id in ['ci41345415', 'us6000u0xi']) {
    testWidgets(
      '$id thumbnail centers on original epicenter without an epicenter marker',
      (tester) async {
        await tester.runAsync(UsgsDyfiMiniMap.prepareOutlines);
        final frame = originalFrame(id);
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 180,
                height: 140,
                child: UsgsDyfiMiniMap(frame: frame),
              ),
            ),
          ),
        );
        await tester.pump();
        final camera = MapCamera.of(
          tester.element(find.byType(UsgsDyfiGridLayer)),
        );
        final anchor = LatLng(frame.event.latitude, frame.event.longitude);
        expect(
          (camera.latLngToScreenOffset(anchor) - const Offset(90, 70)).distance,
          lessThan(1),
        );
        expect(
          smallestCellSide(camera, frame),
          greaterThanOrEqualTo(dyfiMinimumCellPixels - 1e-5),
        );
        if (id == 'us6000u0xi') {
          // Its original grid includes reports 108 km from the epicenter.
          // The legibility limit must take precedence over fitting them all.
          expect(camera.zoom, closeTo(dyfiMinimumZoom(camera, frame), 1e-6));
        }
        expect(find.byType(HistoryMarkerLayer), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
