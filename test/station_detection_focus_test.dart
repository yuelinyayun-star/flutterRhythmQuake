import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/station_detection_focus.dart';
import 'package:latlong2/latlong.dart';

// Controlled geographic bounds for camera tests, not live detection reports.
final taiwan = [const LatLng(23.5, 120.5), const LatLng(25.5, 121.5)];
final japan = [const LatLng(35.5, 139.5), const LatLng(43.5, 144.5)];
final korea = [const LatLng(35.5, 126.5), const LatLng(37.5, 129.5)];

void main() {
  test('a later NIED detection joins P-Alert instead of replacing it', () {
    final first = StationDetectionFocus({'palert': taiwan});
    final both = StationDetectionFocus({'palert': taiwan, 'nied': japan});
    expect(first.isCombined, isFalse);
    expect(both.isCombined, isTrue);
    expect(both.points, containsAll([...taiwan, ...japan]));
    expect(both.signature, isNot(first.signature));
  });

  test('KMA participates in every two-network combination and all three', () {
    for (final networks in [
      {'palert': taiwan, 'kma': korea},
      {'nied': japan, 'kma': korea},
      {'palert': taiwan, 'nied': japan, 'kma': korea},
    ]) {
      final focus = StationDetectionFocus(networks);
      expect(focus.sources.length, networks.length);
      expect(focus.points, containsAll(networks.values.expand((p) => p)));
    }
  });

  test('arrival order and duplicate centers cannot change framing', () {
    final a = StationDetectionFocus({
      'palert': taiwan,
      'nied': japan,
      'kma': korea,
    });
    final b = StationDetectionFocus({
      'kma': korea.reversed.toList(),
      'nied': japan,
      'palert': [...taiwan, ...taiwan],
    });
    expect(a.signature, b.signature);
    expect(a.points, b.points);
  });

  test(
    'expiry removes only that network and preserves remaining detections',
    () {
      final both = StationDetectionFocus({'palert': taiwan, 'nied': japan});
      final remaining = StationDetectionFocus({'palert': [], 'nied': japan});
      expect(remaining.points, japan);
      expect(remaining.sources, ['nied']);
      expect(remaining.isCombined, isFalse);
      expect(remaining.minZoom, 4.5);
      expect(remaining.signature, isNot(both.signature));
      expect(StationDetectionFocus({'palert': [], 'nied': []}).points, isEmpty);
    },
  );

  test('TREM shares the same extent without duplicating Taiwan centers', () {
    final focus = StationDetectionFocus({
      'palert': taiwan,
      'trem': taiwan,
      'kma': korea,
    });
    expect(focus.sources, ['kma', 'palert', 'trem']);
    expect(focus.points.length, taiwan.length + korea.length);
  });

  test('changed grid extent changes signature even with the same sources', () {
    final first = StationDetectionFocus({
      'palert': taiwan,
      'nied': [japan.first],
    });
    final next = StationDetectionFocus({'palert': taiwan, 'nied': japan});
    expect(first.signature, isNot(next.signature));
  });

  for (final size in [
    const Size(1584, 850),
    const Size(1000, 600),
    const Size(430, 900),
    const Size(360, 640),
  ]) {
    testWidgets('combined detections fit the available viewport $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MapController();
      final provider = MapStateProvider();
      addTearDown(provider.dispose);
      late EdgeInsets padding;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              padding =
                  cencIrViewportPadding(context) ?? const EdgeInsets.all(50);
              return FlutterMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(24, 121),
                  initialZoom: 7,
                ),
                children: const [],
              );
            },
          ),
        ),
      );
      provider.setController(controller, const TestVSync());
      for (final networks in [
        {'palert': taiwan, 'nied': japan},
        {'palert': taiwan, 'nied': japan, 'kma': korea},
        {'palert': taiwan, 'nied': <LatLng>[], 'kma': korea},
      ]) {
        final focus = StationDetectionFocus(networks);
        provider.smartMoveToPoints(
          focus.points,
          minZoom: focus.minZoom,
          maxZoom: 8.5,
          viewportPadding: padding,
          sourceTag: focus.sourceTag,
          force: true,
          minInterval: Duration.zero,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1300)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        final visible = padding.deflateRect(Offset.zero & size).inflate(1);
        for (final point in focus.points) {
          final pixel =
              controller.camera.projectAtZoom(point) -
              controller.camera.pixelOrigin;
          expect(visible.contains(pixel), isTrue, reason: '$point at $size');
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
