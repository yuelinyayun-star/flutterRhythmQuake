import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/location_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(MapStateProvider, MapController)> mount(WidgetTester tester) async {
    final controller = MapController();
    final state = MapStateProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(35, 135),
            initialZoom: 6,
          ),
          children: const [],
        ),
      ),
    );
    state.setController(controller, const TestVSync());
    state.configureMobileViewport(
      enabled: true,
      viewport: MapViewport.seismic,
      visible: true,
    );
    return (state, controller);
  }

  void switchTo(
    MapStateProvider state,
    MapViewport view, {
    bool visible = true,
  }) => state.configureMobileViewport(
    enabled: true,
    viewport: view,
    visible: visible,
  );

  void expectCamera(MapController controller, LatLng center, double zoom) {
    expect(controller.camera.center.latitude, closeTo(center.latitude, 1e-8));
    expect(controller.camera.center.longitude, closeTo(center.longitude, 1e-8));
    expect(controller.camera.zoom, closeTo(zoom, 1e-8));
  }

  testWidgets(
    'tabs restore independent centers and zooms without replacing map',
    (tester) async {
      final (state, controller) = await mount(tester);
      controller.move(const LatLng(36, 140), 7);
      switchTo(state, MapViewport.weather);
      controller.move(const LatLng(29, 120), 9);
      switchTo(state, MapViewport.seismic);
      expectCamera(controller, const LatLng(36, 140), 7);
      switchTo(state, MapViewport.weather);
      expectCamera(controller, const LatLng(29, 120), 9);
      expect(identical(state.mapController, controller), true);
      state.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'seismic animation is cancelled on switch and cannot leak into weather',
    (tester) async {
      final (state, controller) = await mount(tester);
      state.animatedMove(const LatLng(42, 143), 8);
      await tester.pump(const Duration(milliseconds: 80));
      final saved = controller.camera.center;
      final zoom = controller.camera.zoom;
      switchTo(state, MapViewport.weather);
      controller.move(const LatLng(29, 120), 9);
      await tester.pump(const Duration(seconds: 2));
      expectCamera(controller, const LatLng(29, 120), 9);
      state.animatedMoveNoAnimate(const LatLng(40, 140), 7);
      state.smartMoveToCenter(
        const LatLng(40, 140),
        zoom: 7,
        force: true,
        respectAutoZoom: false,
      );
      await tester.pump(const Duration(seconds: 2));
      expectCamera(controller, const LatLng(29, 120), 9);
      switchTo(state, MapViewport.seismic);
      expectCamera(controller, saved, zoom);
      state.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'weather locate and gestures preserve seismic lock and preference',
    (tester) async {
      final (state, controller) = await mount(tester);
      LocationService().setCurrentLatLng(29.356, 120.1692);
      await state.setPreferredViewMode('system_default');
      state.pauseAutoZoom(resumeAfter: const Duration(seconds: 30));
      switchTo(state, MapViewport.weather);
      expect(state.moveWeatherToLocationView(animate: false), true);
      expectCamera(controller, const LatLng(29.356, 120.1692), 4);
      state.pauseAutoZoomForGesture();
      state.resumeAutoZoom();
      await tester.pump(const Duration(seconds: 8));
      expect(state.cameraMode, MapCameraMode.manualLocked);
      expect(state.isGestureAutoFollowPaused, false);
      expect(state.preferredViewMode, 'system_default');
      expect(
        (await SharedPreferences.getInstance()).getString(
          MapStateProvider.preferredViewModeKey,
        ),
        'system_default',
      );
      switchTo(state, MapViewport.seismic);
      expectCamera(controller, const LatLng(35, 135), 6);
      expect(state.canAutoFollow, false);
      await tester.pump(const Duration(seconds: 22));
      expect(state.canAutoFollow, true);
      state.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'settings hides camera without losing the last weather viewport',
    (tester) async {
      final (state, controller) = await mount(tester);
      switchTo(state, MapViewport.weather);
      controller.move(const LatLng(29, 120), 9);
      switchTo(state, MapViewport.weather, visible: false);
      state.smartMoveToCenter(
        const LatLng(40, 140),
        zoom: 7,
        force: true,
        respectAutoZoom: false,
      );
      state.moveWeatherToLocationView();
      await tester.pump(const Duration(seconds: 2));
      expectCamera(controller, const LatLng(29, 120), 9);
      switchTo(state, MapViewport.weather);
      expectCamera(controller, const LatLng(29, 120), 9);
      switchTo(state, MapViewport.weather, visible: false);
      switchTo(state, MapViewport.seismic);
      expectCamera(controller, const LatLng(35, 135), 6);
      state.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('settings default-view choice targets seismic not weather', (
    tester,
  ) async {
    final (state, controller) = await mount(tester);
    switchTo(state, MapViewport.weather);
    controller.move(const LatLng(29, 120), 9);
    switchTo(state, MapViewport.weather, visible: false);
    state.moveToSystemDefaultView(animate: false);
    expectCamera(controller, const LatLng(29, 120), 9);
    switchTo(state, MapViewport.weather);
    expectCamera(controller, const LatLng(29, 120), 9);
    switchTo(state, MapViewport.seismic);
    expectCamera(controller, MapStateProvider.fallbackCenter, 4);
    await tester.pump();
    state.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'desktop restores seismic camera and retains original control behavior',
    (tester) async {
      final (state, controller) = await mount(tester);
      switchTo(state, MapViewport.weather);
      controller.move(const LatLng(29, 120), 9);
      state.configureMobileViewport(
        enabled: false,
        viewport: MapViewport.weather,
        visible: false,
      );
      expectCamera(controller, const LatLng(35, 135), 6);
      state.animatedMoveNoAnimate(const LatLng(40, 140), 7);
      expectCamera(controller, const LatLng(40, 140), 7);
      state.pauseAutoZoomForGesture();
      expect(state.isGestureAutoFollowPaused, true);
      await tester.pump(MapStateProvider.gestureAutoFollowResumeDelay);
      expect(state.canAutoFollow, true);
      state.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
