import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('gesture lock refreshes from the latest gesture', (tester) async {
    final provider = MapStateProvider();

    try {
      provider.pauseAutoZoomForGesture();
      expect(provider.cameraMode, MapCameraMode.manualLocked);
      expect(provider.isGestureAutoFollowPaused, isTrue);

      await tester.pump(const Duration(seconds: 5));
      provider.pauseAutoZoomForGesture();

      await tester.pump(const Duration(seconds: 7));
      expect(provider.cameraMode, MapCameraMode.manualLocked);

      await tester.pump(const Duration(seconds: 1));
      expect(provider.cameraMode, MapCameraMode.autoFollow);
      expect(provider.canAutoFollow, isTrue);
      expect(provider.isGestureAutoFollowPaused, isFalse);
    } finally {
      provider.dispose();
    }
  });

  testWidgets('non-gesture camera lock keeps its existing duration', (
    tester,
  ) async {
    final provider = MapStateProvider();

    try {
      provider.pauseAutoZoom();
      await tester.pump(MapStateProvider.gestureAutoFollowResumeDelay);

      expect(provider.cameraMode, MapCameraMode.manualLocked);
      expect(provider.isGestureAutoFollowPaused, isFalse);
    } finally {
      provider.dispose();
    }
  });

  testWidgets('gesture does not shorten an existing longer camera lock', (
    tester,
  ) async {
    final provider = MapStateProvider();

    try {
      provider.pauseAutoZoom();
      await tester.pump(const Duration(seconds: 5));
      provider.pauseAutoZoomForGesture();

      await tester.pump(MapStateProvider.gestureAutoFollowResumeDelay);
      expect(provider.cameraMode, MapCameraMode.manualLocked);
      expect(provider.canAutoFollow, isFalse);
      expect(provider.isGestureAutoFollowPaused, isFalse);

      await tester.pump(const Duration(seconds: 60));
      expect(provider.cameraMode, MapCameraMode.autoFollow);
      expect(provider.canAutoFollow, isTrue);
    } finally {
      provider.dispose();
    }
  });

  testWidgets('gesture immediately stops a running camera animation', (
    tester,
  ) async {
    final controller = MapController();
    final provider = MapStateProvider();

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(35, 135),
                initialZoom: 4,
              ),
              children: const [],
            ),
          ),
        ),
      );
      provider.setController(controller, const TestVSync());

      provider.animatedMove(const LatLng(40, 140), 7);
      await tester.pump(const Duration(milliseconds: 200));
      provider.pauseAutoZoomForGesture();
      final interruptedCenter = controller.camera.center;
      final interruptedZoom = controller.camera.zoom;

      await tester.pump(const Duration(milliseconds: 800));
      expect(
        controller.camera.center.latitude,
        closeTo(interruptedCenter.latitude, 1e-9),
      );
      expect(
        controller.camera.center.longitude,
        closeTo(interruptedCenter.longitude, 1e-9),
      );
      expect(controller.camera.zoom, closeTo(interruptedZoom, 1e-9));
    } finally {
      provider.dispose();
    }
  });

  testWidgets('screen offset is measured in pixels at destination zoom', (
    tester,
  ) async {
    final controller = MapController();
    final provider = MapStateProvider();
    const focus = LatLng(35, 135);
    const zoom = 7.0;
    const screenOffset = Offset(120, -40);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(35, 135),
                initialZoom: 4,
              ),
              children: const [],
            ),
          ),
        ),
      );
      provider.setController(controller, const TestVSync());

      provider.smartMoveToCenter(
        focus,
        zoom: zoom,
        screenOffset: screenOffset,
        force: true,
        minInterval: Duration.zero,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump(const Duration(milliseconds: 40));

      final camera = controller.camera;
      final focusPoint = camera.projectAtZoom(focus, zoom);
      final centerPoint = camera.projectAtZoom(camera.center, zoom);
      final actualOffset = focusPoint - centerPoint;
      expect(actualOffset.dx, closeTo(screenOffset.dx, 0.01));
      expect(actualOffset.dy, closeTo(screenOffset.dy, 0.01));
    } finally {
      provider.dispose();
    }
  });
}
