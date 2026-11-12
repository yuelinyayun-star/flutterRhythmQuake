import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/information_camera_group.dart';

void main() {
  // Two original reports, unmodified; this exercises shared camera geometry,
  // not a synthetic bulletin or an injected live earthquake.
  final candidates = <DesktopCameraCandidate>[];
  for (final fixture in [
    'cenc_ir_mojiang_20260914170727.json',
    'cenc_ir_qiaojia_20260908013139.json',
  ]) {
    final raw =
        jsonDecode(
              File('test/fixtures/$fixture').readAsStringSync(encoding: utf8),
            )
            as Map<String, dynamic>;
    final data = CencIrData.fromNowQuakeJson(raw);
    final event = NowQuakeCencIntensityService.unifiedInfoFromJson(raw)!;
    candidates.add(
      DesktopCameraCandidate.fromEvent(
        event,
        index: candidates.length,
        focusPoints: cencIrFocusPoints(
          data: data,
          eventId: data.reportId,
          epicenterLatitude: data.epiLat,
          epicenterLongitude: data.epiLon,
        ),
      )!,
    );
  }
  for (final size in [const Size(1584, 850), const Size(430, 900)]) {
    testWidgets('CENC shared view retains owner epicenter at center $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MapController();
      final map = MapStateProvider();
      addTearDown(map.dispose);
      final groups = InformationCameraGroups()..update(1, () => candidates);
      final group = groups.sharedGroup(candidates.first.key)!;
      late BuildContext mapContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              mapContext = context;
              return FlutterMap(
                mapController: controller,
                options: MapOptions(initialCenter: group.owner.location),
                children: const [],
              );
            },
          ),
        ),
      );
      map.setController(controller, const TestVSync());
      groups.focus(context: mapContext, mapState: map, group: group);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1400)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      final padding =
          cencIrViewportPadding(mapContext) ?? const EdgeInsets.all(50);
      final visible = padding.deflateRect(Offset.zero & size);
      final pixel = controller.camera.latLngToScreenOffset(
        group.owner.location,
      );
      expect((pixel - visible.center).distance, lessThan(1));
      for (final point in group.points) {
        expect(
          visible
              .inflate(1)
              .contains(controller.camera.latLngToScreenOffset(point)),
          true,
        );
      }
      final center = controller.camera.center, zoom = controller.camera.zoom;
      var moves = 0;
      final subscription = controller.mapEventStream.listen((_) => moves++);
      for (final event in candidates.reversed) {
        groups.focus(
          context: mapContext,
          mapState: map,
          group: groups.sharedGroup(event.key)!,
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(moves, 0);
      expect(controller.camera.center, center);
      expect(controller.camera.zoom, zoom);
      await tester.runAsync(subscription.cancel);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
