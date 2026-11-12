import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/world_wrap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/information_camera_group.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'information_camera_group_test.dart' show frameFor, candidatesFor;

// Frozen pre-fix implementation, solely for diagnosing the new rotation
// coverage. Original geometry is neither rewritten nor fed back as a bulletin.
MapCamera frozenFit(
  MapCamera camera,
  List<LatLng> points,
  LatLng anchor,
  EdgeInsets padding,
) {
  Offset rotate(Offset p, double angle) => Offset(
    p.dx * math.cos(angle) - p.dy * math.sin(angle),
    p.dx * math.sin(angle) + p.dy * math.cos(angle),
  );
  final origin = camera.projectAtZoom(anchor);
  var halfWidth = 0.0, halfHeight = 0.0;
  for (final point in points) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) {
      continue;
    }
    final wrapped = WorldWrap.latLngClosestToCamera(point, camera);
    final p = rotate(
      camera.projectAtZoom(wrapped) - origin,
      -camera.rotationRad,
    );
    halfWidth = math.max(halfWidth, p.dx.abs());
    halfHeight = math.max(halfHeight, p.dy.abs());
  }
  final width = camera.nonRotatedSize.width - padding.horizontal;
  final height = camera.nonRotatedSize.height - padding.vertical;
  final scale = math.min(
    halfWidth == 0 ? double.infinity : width / (2 * halfWidth),
    halfHeight == 0 ? double.infinity : height / (2 * halfHeight),
  );
  final zoom = (scale.isFinite ? camera.getScaleZoom(scale) : 10.0)
      .clamp(2.0, 10.0)
      .toDouble();
  final offset = rotate(
    Offset(
      (padding.right - padding.left) / 2,
      (padding.bottom - padding.top) / 2,
    ),
    camera.rotationRad,
  );
  return camera.withPosition(
    center: WorldWrap.unprojectUnwrapped(
      camera,
      camera.projectAtZoom(anchor, zoom) + offset,
      zoom: zoom,
    ),
    zoom: zoom,
  );
}

void main() {
  for (final size in [const Size(1584, 850), const Size(430, 900)]) {
    // Production QuakeMapView explicitly starts at zero and disables rotation.
    // The forced 20-degree diagnostic is retained separately in tmp, not used
    // to redefine the supported APP contract.
    for (final rotation in [0.0]) {
      testWidgets(
        'original cross-line group retains viewport $size rotation=$rotation',
        (tester) async {
          expect(NativeCameraFocus.supported, isTrue);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final frame = frameFor('aka2026tvzrwv');
          final candidates = candidatesFor(frame);
          final groups = InformationCameraGroups()..update(1, () => candidates);
          final map = MapController(), state = MapStateProvider();
          late BuildContext context;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (value) {
                  context = value;
                  return FlutterMap(
                    mapController: map,
                    options: MapOptions(
                      initialCenter: candidates.first.location,
                      initialZoom: 3,
                      initialRotation: rotation,
                    ),
                    children: const [],
                  );
                },
              ),
            ),
          );
          state.setController(map, const TestVSync());
          var moves = 0;
          final sub = map.mapEventStream.listen((_) {
            moves++;
          });
          try {
            void focus(String key) => groups.focus(
              context: context,
              mapState: state,
              group: groups.sharedGroup(key)!,
            );
            final oldPadding = usgsProductViewportPadding(context);
            final oldCamera = frozenFit(
              map.camera,
              shakeMapFocusPoints(frame),
              candidates.first.location,
              oldPadding,
            );
            final oldError =
                (oldCamera.latLngToScreenOffset(candidates.first.location) -
                        oldPadding.deflateRect(Offset.zero & size).center)
                    .distance;
            focus(candidates.first.key);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1350)),
            );
            await tester.pump(const Duration(milliseconds: 40));
            final padding = usgsProductViewportPadding(context);
            final viewport = padding.deflateRect(Offset.zero & size);
            final points = shakeMapFocusPoints(frame);
            final currentError =
                (map.camera.latLngToScreenOffset(candidates.first.location) -
                        viewport.center)
                    .distance;
            final diagnostic = {
              'width': size.width,
              'rotation': rotation,
              'oldErrorPixels': oldError,
              'currentErrorPixels': currentError,
            };
            debugPrint('ROTATION_COMPARE ${jsonEncode(diagnostic)}');
            File(
              'tmp/dateline_fix_20261102/rotation-${size.width.toInt()}-$rotation.json',
            ).writeAsStringSync(jsonEncode(diagnostic), encoding: utf8);
            for (final point in points) {
              expect(
                viewport
                    .inflate(1)
                    .contains(
                      map.camera.latLngToScreenOffset(
                        WorldWrap.latLngClosestToCamera(point, map.camera),
                      ),
                    ),
                isTrue,
              );
            }
            expect(
              (map.camera.latLngToScreenOffset(candidates.first.location) -
                      viewport.center)
                  .distance,
              lessThan(1),
            );
            final center = map.camera.center, zoom = map.camera.zoom;
            moves = 0;
            for (var i = 0; i < 8; i++) {
              focus(candidates[i % 2].key);
              await tester.pump(const Duration(milliseconds: 40));
            }
            // Controlled UI card identity, retaining the same unmodified original
            // geometry. This is not an invented upstream bulletin or new quake.
            final extra = DesktopCameraCandidate(
              key: 'contained-card',
              index: 2,
              location: candidates.last.location,
            );
            groups.update(2, () => [...candidates, extra]);
            final calls = NativeCameraFocus.calls;
            focus(extra.key);
            expect(
              NativeCameraFocus.calls - calls,
              2,
              reason:
                  'Contained update should validate visibility and retain, without refitting',
            );
            await tester.pump(const Duration(seconds: 2));
            expect(moves, 0);
            expect(map.camera.center, center);
            expect(map.camera.zoom, zoom);
            expect(NativeCameraFocus.outputs, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.runAsync(sub.cancel);
            await tester.pumpWidget(const SizedBox());
            state.dispose();
            map.dispose();
          }
        },
      );
    }
  }
}
