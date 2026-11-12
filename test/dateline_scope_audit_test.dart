// B1 regressions using the unchanged captured product. The event-coordinate
// guard remains strict; continuous range geometry has an independent path.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/utils/world_wrap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'package:latlong2/latlong.dart';

import 'information_camera_group_test.dart' show frameFor;

void main() {
  for (final size in [const Size(1584, 850), const Size(430, 900)]) {
    testWidgets(
      'B1 continuous range is visible and fitted while event guards stay strict $size',
      (tester) async {
        const base = 'test/fixtures/usgs_shakemap/aka2026tvzrwv';
        final originals = [
          File('$base.detail.original.geojson'),
          File('$base.cont_mmi.original.json'),
        ];
        final hashes = {
          for (final file in originals)
            file.path: sha256.convert(file.readAsBytesSync()).toString(),
        };
        final frame = frameFor('aka2026tvzrwv');
        expect(frame.contours, isEmpty);
        expect(frame.product.east, 181.883);
        final points = shakeMapFocusPoints(frame);
        final map = MapController();
        final state = MapStateProvider();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (value) {
                context = value;
                return FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: LatLng(
                      frame.event.latitude,
                      frame.event.longitude,
                    ),
                    // Diagnostic viewport only: original data and production rules are
                    // unchanged. A wide view makes all original points truly visible.
                    initialZoom: 3,
                  ),
                  children: const [],
                );
              },
            ),
          ),
        );
        state.setController(map, const TestVSync());
        try {
          final padding = usgsProductViewportPadding(context);
          final viewport = padding.deflateRect(Offset.zero & size);
          final rows = <Map<String, Object?>>[];
          for (final point in points) {
            final displayed = WorldWrap.latLngClosestToCamera(
              point,
              map.camera,
            );
            final pixel = map.camera.latLngToScreenOffset(displayed);
            final onScreen = viewport.contains(pixel);
            final accepted = state.isPointInEventViewport(
              point,
              padding: padding,
            );
            final geometryAccepted = state.areGeometryPointsInEventViewport([
              point,
            ], padding: padding);
            expect(geometryAccepted, isTrue);
            expect(onScreen, isTrue);
            if (point.longitude > 180) {
              expect(
                QuakeCalculator.isUsableMapCoordinate(
                  point.latitude,
                  point.longitude,
                ),
                isFalse,
              );
              expect(
                accepted,
                isFalse,
                reason: 'Event admission must still reject out-of-range fields',
              );
            } else {
              expect(accepted, isTrue);
            }
            rows.add({
              'latitude': point.latitude,
              'originalLongitude': point.longitude,
              'displayLongitude': displayed.longitude,
              'screenX': pixel.dx,
              'screenY': pixel.dy,
              'insideViewport': onScreen,
              'visibilityApi': accepted,
              'geometryVisibilityApi': geometryAccepted,
            });
          }
          expect(
            rows.where((row) => row['visibilityApi'] == false),
            hasLength(1),
          );
          expect(
            state.areGeometryPointsInEventViewport(points, padding: padding),
            isTrue,
          );
          focusUsgsShakeMap(context: context, mapState: state, frame: frame);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1350)),
          );
          await tester.pump(const Duration(milliseconds: 40));
          final fitted = [
            for (final point in points)
              {
                'latitude': point.latitude,
                'originalLongitude': point.longitude,
                'screenX': map.camera
                    .latLngToScreenOffset(
                      WorldWrap.latLngClosestToCamera(point, map.camera),
                    )
                    .dx,
                'screenY': map.camera
                    .latLngToScreenOffset(
                      WorldWrap.latLngClosestToCamera(point, map.camera),
                    )
                    .dy,
                'insideViewport': viewport
                    .inflate(1)
                    .contains(
                      map.camera.latLngToScreenOffset(
                        WorldWrap.latLngClosestToCamera(point, map.camera),
                      ),
                    ),
              },
          ];
          expect(
            fitted.where((row) => row['insideViewport'] == false),
            isEmpty,
          );
          final centerError =
              (map.camera.latLngToScreenOffset(points.first) - viewport.center)
                  .distance;
          expect(centerError, lessThan(1));
          final directory = Directory('tmp/dateline_fix_20261102');
          directory.createSync(recursive: true);
          File(
            '${directory.path}/visibility-${size.width.toInt()}.json',
          ).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert({
              'eventId': frame.event.eventId,
              'width': size.width,
              'height': size.height,
              'points': rows,
              'fittedZoom': map.camera.zoom,
              'fittedPoints': fitted,
              'anchorErrorPixels': centerError,
              'viewport': {
                'left': viewport.left,
                'top': viewport.top,
                'right': viewport.right,
                'bottom': viewport.bottom,
              },
              'originalHashes': hashes,
            }),
            encoding: utf8,
          );
          debugPrint('B1_VISIBILITY_AUDIT ${jsonEncode(rows)}');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          map.dispose();
          for (final file in originals) {
            expect(
              sha256.convert(file.readAsBytesSync()).toString(),
              hashes[file.path],
            );
          }
        }
      },
    );
  }
}
