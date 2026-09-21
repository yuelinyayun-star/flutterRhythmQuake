import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/world_wrap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:latlong2/latlong.dart';

// Geometric camera test positions, not earthquake observations.
const west = LatLng(-30, -70);
const east = LatLng(-5, 150);
const screenOffset = Offset(106, 26);
const viewportPadding = EdgeInsets.fromLTRB(490, 84, 278, 32);

Future<void> advanceCamera(WidgetTester tester, int milliseconds) async {
  await tester.runAsync(
    () => Future<void>.delayed(Duration(milliseconds: milliseconds)),
  );
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> mountMap(
  WidgetTester tester,
  MapController controller,
  MapStateProvider provider,
  LatLng initial,
) async {
  tester.view.physicalSize = const Size(1584, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        mapController: controller,
        options: MapOptions(initialCenter: initial, initialZoom: 7),
        children: const [],
      ),
    ),
  );
  provider.setController(controller, const TestVSync());
}

void expectFramed(MapController controller, LatLng target, Offset offset) {
  final camera = controller.camera;
  final wrapped = WorldWrap.latLngClosestToCamera(target, camera);
  final actual =
      camera.projectAtZoom(wrapped) - camera.projectAtZoom(camera.center);
  expect(actual.dx, closeTo(offset.dx, 0.01));
  expect(actual.dy, closeTo(offset.dy, 0.01));
  expect(camera.zoom, closeTo(7, 1e-9));
}

void main() {
  for (final positions in [
    (west, east),
    (east, west),
    (const LatLng(10, 170), const LatLng(10, -179.8)),
    (const LatLng(10, -170), const LatLng(10, 179.8)),
  ]) {
    for (final offset in [screenOffset, Offset.zero]) {
      testWidgets('cross-date-line focus ${positions.$1} to ${positions.$2}, '
          'offset=$offset', (tester) async {
        final controller = MapController();
        final provider = MapStateProvider();
        await mountMap(tester, controller, provider, positions.$1);
        provider.smartMoveToCenter(
          positions.$2,
          zoom: 7,
          screenOffset: offset,
          force: true,
        );
        // Selection must use the final target even before the flight arrives.
        expect(
          provider.isPointInEventViewport(
            positions.$2,
            padding: viewportPadding,
          ),
          isTrue,
        );
        await advanceCamera(tester, 1300);
        expectFramed(controller, positions.$2, offset);
      });
    }
  }

  testWidgets('far carousel keeps the selected target through world wrap', (
    tester,
  ) async {
    final controller = MapController();
    final provider = MapStateProvider();
    await mountMap(tester, controller, provider, west);
    final selector = DesktopEventCameraFocus();
    const candidates = [
      DesktopCameraCandidate(key: 'west', index: 0, location: west),
      DesktopCameraCandidate(key: 'east', index: 1, location: east),
    ];
    void refresh(int index) {
      final target = selector.select(
        candidates: candidates,
        requestedIndex: index,
        isVisible: (point) =>
            provider.isPointInEventViewport(point, padding: viewportPadding),
      )!;
      expect(target.index, index);
      provider.smartMoveToCenter(
        target.location,
        zoom: 7,
        screenOffset: screenOffset,
        sourceTag: 'policy-${target.key}',
        force: true,
      );
    }

    for (final index in [1, 0, 1]) {
      refresh(index);
      await advanceCamera(tester, 750);
      refresh(index);
      await advanceCamera(tester, 550);
      expectFramed(controller, candidates[index].location, screenOffset);
    }
  });

  testWidgets('repeated identical request does not restart an in-flight move', (
    tester,
  ) async {
    final controller = MapController();
    final provider = MapStateProvider();
    await mountMap(tester, controller, provider, const LatLng(10, 10));
    const target = LatLng(40, 110);
    provider.animatedMove(target, 7);
    await advanceCamera(tester, 600);
    provider.animatedMove(target, 7);
    await advanceCamera(tester, 700);
    expectFramed(controller, target, Offset.zero);
  });

  testWidgets('a different target still replaces an in-flight move', (
    tester,
  ) async {
    final controller = MapController();
    final provider = MapStateProvider();
    await mountMap(tester, controller, provider, west);
    provider.animatedMoveWithScreenOffset(east, 7, screenOffset);
    await advanceCamera(tester, 600);
    provider.animatedMoveWithScreenOffset(west, 7, screenOffset);
    await advanceCamera(tester, 1300);
    expectFramed(controller, west, screenOffset);
  });

  testWidgets('unprojection preserves longitude world copies at each zoom', (
    tester,
  ) async {
    final controller = MapController();
    final provider = MapStateProvider();
    await mountMap(tester, controller, provider, west);
    final camera = controller.camera;
    for (final zoom in [3.0, 7.0, 12.0]) {
      for (final longitude in [-540.5, -210.0, -180.0, 180.0, 290.0, 540.5]) {
        final point = LatLng(-30, longitude);
        final result = WorldWrap.unprojectUnwrapped(
          camera,
          camera.projectAtZoom(point, zoom),
          zoom: zoom,
        );
        expect(result.latitude, closeTo(point.latitude, 1e-9));
        expect(result.longitude, closeTo(longitude, 1e-9));
      }
    }
  });
}
