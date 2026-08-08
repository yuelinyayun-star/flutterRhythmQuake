import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/eew_wave_camera_follow_gate.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets(
    'EEW wave camera uses the viewport instead of coarse zoom bands',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = MapController();
      final provider = MapStateProvider();

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(35, 135),
                initialZoom: 4,
              ),
              children: const [],
            ),
          ),
        );
        provider.setController(controller, const TestVSync());

        final sourceClockNow = DateTime.now().toUtc().add(
          const Duration(hours: 9),
        );
        final event = QuakeMessage(
          source: QuakeSourceType.wolfx,
          eventId: 'camera-fit-test',
          location: 'test',
          magnitude: 7.0,
          latitude: 35,
          longitude: 135,
          depth: 10,
          originTime: sourceClockNow.subtract(const Duration(seconds: 90)),
        );

        provider.smartMoveToEvents(
          [event],
          waveEvents: [event],
          padding: 0.8,
          minZoom: 4.5,
          maxZoom: 8,
          force: true,
          minInterval: Duration.zero,
          continuousFollow: true,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 900)),
        );
        await tester.pump(const Duration(milliseconds: 40));

        expect(controller.camera.zoom, greaterThan(6.0));
        expect(controller.camera.zoom, lessThanOrEqualTo(8.0));
      } finally {
        provider.dispose();
      }
    },
  );

  testWidgets('EEW camera keeps following an expanding low-magnitude P wave', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MapController();
    final provider = MapStateProvider();

    QuakeMessage eventAt(Duration elapsed) {
      final sourceClockNow = DateTime.now().toUtc().add(
        const Duration(hours: 9),
      );
      return QuakeMessage(
        source: QuakeSourceType.wolfx,
        eventId: 'camera-follow-test',
        location: 'test',
        magnitude: 3.4,
        latitude: 36.4,
        longitude: 139.8,
        depth: 100,
        originTime: sourceClockNow.subtract(elapsed),
      );
    }

    Future<void> moveToWave(Duration elapsed) async {
      final event = eventAt(elapsed);
      provider.smartMoveToEvents(
        [event],
        waveEvents: [event],
        padding: 0.8,
        minZoom: 4.5,
        maxZoom: 8,
        force: true,
        minInterval: Duration.zero,
        continuousFollow: true,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(36.4, 139.8),
              initialZoom: 4,
            ),
            children: const [],
          ),
        ),
      );
      provider.setController(controller, const TestVSync());

      await moveToWave(const Duration(seconds: 75));
      final earlierZoom = controller.camera.zoom;

      await moveToWave(const Duration(seconds: 120));
      final laterZoom = controller.camera.zoom;

      expect(laterZoom, lessThan(earlierZoom - 0.25));
    } finally {
      provider.dispose();
    }
  });

  testWidgets('continuous wave follow has no idle gap before the next target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MapController();
    final provider = MapStateProvider();

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(35, 135),
              initialZoom: 4,
            ),
            children: const [],
          ),
        ),
      );
      provider.setController(controller, const TestVSync());

      provider.animatedMove(const LatLng(36, 136), 7, continuousFollow: true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final zoomAt820ms = controller.camera.zoom;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final zoomAt940ms = controller.camera.zoom;

      expect(zoomAt940ms, greaterThan(zoomAt820ms));
      expect(zoomAt940ms, lessThan(7));
    } finally {
      provider.dispose();
    }
  });

  test('EEW wave camera gate holds at minimum zoom for ten seconds', () {
    final gate = EewWaveCameraFollowGate();
    final start = DateTime(2026, 7, 31, 12, 0, 0);

    expect(gate.syncEvents(['wolfx:wave-1'], start), isFalse);
    gate.noteTargetZoom(targetZoom: 4.5, minimumZoom: 4.5, now: start);
    expect(
      gate.syncEvents([
        'wolfx:wave-1',
      ], start.add(const Duration(seconds: 9, milliseconds: 999))),
      isFalse,
    );
    expect(
      gate.syncEvents(['wolfx:wave-1'], start.add(const Duration(seconds: 10))),
      isTrue,
    );

    expect(
      gate.syncEvents(['wolfx:wave-2'], start.add(const Duration(seconds: 11))),
      isFalse,
    );
  });
}
