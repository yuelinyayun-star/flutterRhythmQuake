import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/jma_info_focus.dart';

void main() {
  final history =
      jsonDecode(
            File(
              'test/fixtures/jma_voice/p2p_history_20260921.json',
            ).readAsStringSync(encoding: utf8),
          )
          as List;
  final raw = history.cast<Map<String, dynamic>>().singleWhere(
    (item) =>
        item['issue']['type'] == 'DetailScale' &&
        item['earthquake']['time'] == '2026/09/21 22:38:00',
  );

  for (final size in [const Size(1584, 850), const Size(1200, 800)]) {
    testWidgets('Hyuganada original regions fit desktop viewport $size', (
      tester,
    ) async {
      final original = jsonEncode(raw);
      final event = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
      final points = jmaInfoFocusPoints(
        warnAreaJson: event.warnArea,
        epicenterLatitude: event.lat,
        epicenterLongitude: event.lng,
      );
      expect(raw['points'], hasLength(191));
      final bounds = LatLngBounds.fromPoints(points);
      debugPrint('HYUGANADA bounds=$bounds');

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final map = MapStateProvider();
      final controller = MapController();
      addTearDown(map.dispose);
      late EdgeInsets padding;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              padding = cencIrViewportPadding(context)!;
              return FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: points.first,
                  initialZoom: 7,
                ),
                children: const [],
              );
            },
          ),
        ),
      );
      map.setController(controller, const TestVSync());
      Future<void> finishMove() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1600)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Reproduce the previous JMA path without changing the source report.
      map.smartMoveToPoints(
        points,
        padding: 0.8,
        minZoom: 3,
        maxZoom: 8,
        screenOffset: Offset(
          (padding.left - padding.right) / 2,
          (padding.top - padding.bottom) / 2,
        ),
        force: true,
      );
      await finishMove();
      final oldZoom = controller.camera.zoom;
      expect(oldZoom, 5);

      map.smartMoveToPoints(
        points,
        padding: 0.8,
        minZoom: 3,
        maxZoom: 8,
        viewportPadding: padding,
        force: true,
      );
      await finishMove();
      final zoom = controller.camera.zoom;
      expect(zoom, greaterThan(oldZoom + 1));
      final visible = padding.deflateRect(Offset.zero & size).inflate(1);
      for (final point in points) {
        expect(
          visible.contains(controller.camera.latLngToScreenOffset(point)),
          isTrue,
        );
      }
      debugPrint('HYUGANADA_CAMERA $size oldZoom=$oldZoom fittedZoom=$zoom');
      expect(jsonEncode(raw), original);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
