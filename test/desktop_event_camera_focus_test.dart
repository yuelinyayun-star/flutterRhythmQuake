import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/eew_wave_camera_follow_gate.dart';
import 'package:latlong2/latlong.dart';

CencIrData readReport(String file) => CencIrData.fromNowQuakeJson(
  jsonDecode(File('test/fixtures/$file').readAsStringSync())
      as Map<String, dynamic>,
);

final mojiang = readReport('cenc_ir_mojiang_20260914170727.json');
final qiaojiaRaw = jsonDecode(
  File('test/fixtures/cenc_ir_qiaojia_20260908013139.json').readAsStringSync(),
) as Map<String, dynamic>;
final qiaojia = CencIrData.fromNowQuakeJson(qiaojiaRaw);
final report = DesktopCameraCandidate(
  key: 'report:${mojiang.reportId}',
  index: 0,
  location: LatLng(mojiang.epiLat, mojiang.epiLon),
  stationPoints: cencIrFocusPoints(
    data: mojiang,
    eventId: mojiang.reportId,
    epicenterLatitude: mojiang.epiLat,
    epicenterLongitude: mojiang.epiLon,
  ),
);
// Exercise source identities independently, using the same original epicenter.
final bulletin = DesktopCameraCandidate(
  key: 'bulletin:${mojiang.reportId}',
  index: 1,
  location: report.location,
);
final other = DesktopCameraCandidate(
  key: 'report:${qiaojia.reportId}',
  index: 2,
  location: LatLng(qiaojia.epiLat, qiaojia.epiLon),
);

void main() {
  test(
    'detailed report wins even if the bulletin arrives before the first fit',
    () {
      final focus = DesktopEventCameraFocus();
      final candidates = [report, bulletin];
      final selected = focus.select(
        candidates: candidates,
        requestedIndex: 1,
        isVisible: (_) => false,
      );
      expect(selected, same(report));
      expect(candidates, [same(report), same(bulletin)]);
    },
  );

  test('nearby carousel and source updates retain the detailed owner', () {
    final focus = DesktopEventCameraFocus();
    focus.select(
      candidates: [report],
      requestedIndex: 0,
      isVisible: (_) => true,
    );
    for (final index in [1, 0, 1, 1, 0]) {
      expect(
        focus.select(
          candidates: [report, bulletin],
          requestedIndex: index,
          isVisible: (_) => true,
        ),
        same(report),
      );
    }
    expect(
      focus.select(
        candidates: [bulletin],
        requestedIndex: 1,
        isVisible: (_) => true,
      ),
      same(bulletin),
    );
    expect(
      focus.select(candidates: [], requestedIndex: 0, isVisible: (_) => true),
      isNull,
    );
  });

  test('a station detail arriving later replaces a point-only owner', () {
    final focus = DesktopEventCameraFocus();
    focus.select(
      candidates: [bulletin],
      requestedIndex: 1,
      isVisible: (_) => true,
    );
    expect(
      focus.select(
        candidates: [report, bulletin],
        requestedIndex: 1,
        isVisible: (_) => true,
      ),
      same(report),
    );
  });

  test(
    'nearby EEW source remains separate but does not replace camera owner',
    () {
      final focus = DesktopEventCameraFocus();
      final second = DesktopCameraCandidate(
        key: 'second-source:${mojiang.reportId}',
        index: 0,
        location: bulletin.location,
      );
      focus.select(
        candidates: [bulletin],
        requestedIndex: 1,
        isVisible: (_) => true,
      );
      final selected = focus.select(
        candidates: [second, bulletin],
        requestedIndex: 0,
        isVisible: (_) => true,
      );
      expect(selected, same(bulletin));
      expect(
        eewCameraFocusEvents(
          events: [second, bulletin],
          splitDistant: true,
          currentEvent: selected,
        ),
        [same(bulletin)],
      );
    },
  );

  for (final size in [const Size(1584, 850), const Size(1200, 800)]) {
    testWidgets('pending fit and distant carousel use individual views $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = MapStateProvider();
      final controller = MapController();
      final focus = DesktopEventCameraFocus();
      addTearDown(provider.dispose);
      late EdgeInsets padding;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              padding = cencIrViewportPadding(context)!;
              return FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: other.location,
                  initialZoom: 8,
                ),
                children: const [],
              );
            },
          ),
        ),
      );
      provider.setController(controller, const TestVSync());
      bool visible(LatLng point) =>
          provider.isPointInEventViewport(point, padding: padding);
      final candidates = [report, bulletin, other];
      DesktopCameraCandidate select(int index) => focus.select(
        candidates: candidates,
        requestedIndex: index,
        isVisible: visible,
      )!;
      Future<void> finishMove() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1300)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }

      void frameReport() => provider.smartMoveToPoints(
        report.stationPoints,
        viewportPadding: padding,
        focusAnchor: report.location,
        maxZoom: 12,
        force: true,
        minInterval: Duration.zero,
      );

      expect(select(0), same(report));
      frameReport();
      // The map is still over Qiaojia, but visibility must use its Mojiang target.
      expect(
        controller.camera.center.latitude,
        closeTo(other.location.latitude, 0.1),
      );
      expect(visible(report.location), isTrue);
      expect(visible(other.location), isFalse);
      expect(select(1), same(report));
      await finishMove();
      final fittedZoom = controller.camera.zoom;
      final fittedCenter = controller.camera.center;
      expect(fittedZoom, greaterThan(8));
      for (final index in [1, 0, 1]) {
        expect(select(index), same(report));
        frameReport();
      }
      await finishMove();
      expect(controller.camera.zoom, fittedZoom);
      expect(controller.camera.center, fittedCenter);

      final distance = QuakeCalculator.haversineDistance(
        mojiang.epiLat,
        mojiang.epiLon,
        qiaojia.epiLat,
        qiaojia.epiLon,
      );
      expect(distance, lessThan(2500));
      expect(select(2), same(other));
      final event = QuakeMessage(
        source: QuakeSourceType.cencIr,
        eventId: qiaojia.reportId,
        location: qiaojia.locName,
          magnitude: (qiaojiaRaw['magnitude'] as num).toDouble(),
        latitude: qiaojia.epiLat,
        longitude: qiaojia.epiLon,
        depth: qiaojia.focDepth,
        originTime: qiaojia.oriTime,
      );
      // Test only the camera; no derived or substitute event observations.
      provider.smartMoveToEvents(
        [event],
        padding: 1,
        force: true,
        minInterval: Duration.zero,
        screenOffset: Offset(
          (padding.left - padding.right) / 2,
          (padding.top - padding.bottom) / 2,
        ),
      );
      expect(visible(other.location), isTrue);
      expect(visible(report.location), isFalse);
      await finishMove();
      expect(controller.camera.zoom, 7);
      expect(select(0), same(report));
      frameReport();
      await finishMove();
      expect(controller.camera.zoom, closeTo(fittedZoom, 1e-8));
      debugPrint(
        'DESKTOP_CAMERA $size distanceKm=$distance reportZoom=$fittedZoom '
        'nearbyUpdates=stable outsideEvent=individual returnReport=restored',
      );
    });
  }
}
