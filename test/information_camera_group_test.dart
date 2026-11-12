import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/information_camera_group.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'package:latlong2/latlong.dart';

import 'usgs_shakemap_test.dart' show readJson, eventFor;

UsgsShakeMapFrame frameFor(String id) {
  final detail = readJson('$id.detail.original.geojson');
  return UsgsShakeMapFrame(
    event: eventFor(detail),
    product: UsgsShakeMapProduct.fromDetail(detail)!,
    contours: UsgsMmiContour.parse(
      jsonDecode(
        File(
          'test/fixtures/usgs_shakemap/$id.cont_mmi.original.json',
        ).readAsStringSync(encoding: utf8),
      ),
    ),
  );
}

List<DesktopCameraCandidate> candidatesFor(UsgsShakeMapFrame frame) => [
  DesktopCameraCandidate(
    key: 'usgsShakeMap:${frame.event.eventId}',
    index: 0,
    location: LatLng(frame.event.latitude, frame.event.longitude),
    fitPoints: shakeMapFocusPoints(frame),
    isMapProduct: true,
  ),
  // Separate source identities exercise the same original event geometry.
  DesktopCameraCandidate(
    key: 'usgsEqlist:${frame.event.eventId}',
    index: 1,
    location: LatLng(frame.event.latitude, frame.event.longitude),
  ),
];

void main() {
  test('nearby product and report cache one extent across carousel turns', () {
    final candidates = candidatesFor(frameFor('ci41345415'));
    final groups = InformationCameraGroups();
    var builds = 0;
    for (var i = 0; i < 20; i++) {
      groups.update('same geometry', () {
        builds++;
        return candidates;
      });
      final group = groups.sharedGroup(candidates[i % 2].key)!;
      expect(group.members.length, 2);
      expect(group.owner, same(candidates.first));
      expect(group.points, containsAll(candidates.first.fitPoints));
      expect(groups.needsFit(group, (1584, 850)), i == 0);
    }
    expect(builds, 1);
    final group = groups.sharedGroup(candidates.last.key)!;
    expect(groups.needsFit(group, (390, 844)), isTrue);
    expect(groups.needsFit(group, (390, 844)), isFalse);
    groups.leave();
    expect(groups.needsFit(group, (390, 844)), isTrue);
    groups.clear();
    expect(groups.sharedGroup(candidates.first.key), isNull);
  });

  test('unrelated distant updates do not invalidate the current extent', () {
    final nearby = candidatesFor(frameFor('ci41345415'));
    final distant = candidatesFor(frameFor('us6000u0xi'));
    final groups = InformationCameraGroups();
    groups.update(1, () => nearby);
    expect(groups.needsFit(groups.sharedGroup(nearby.first.key)!, 1), isTrue);
    groups.update(2, () => [...distant.reversed, ...nearby.reversed]);
    final sameArea = groups.sharedGroup(nearby.last.key)!;
    expect(sameArea.members, hasLength(2));
    expect(groups.needsFit(sameArea, 1), isFalse);
    final farArea = groups.sharedGroup(distant.last.key)!;
    expect(farArea.key, isNot(sameArea.key));
    expect(groups.needsFit(farArea, 1), isTrue);
    expect(groups.needsFit(sameArea, 1), isTrue);
  });

  test(
    'distance groups cannot chain beyond the existing 2500 km threshold',
    () {
      // Controlled camera geometry, not a simulated earthquake bulletin.
      final candidates = [
        for (var i = 0; i < 3; i++)
          DesktopCameraCandidate(
            key: '$i',
            index: i,
            location: LatLng(0, i * 20),
          ),
      ];
      final groups = InformationCameraGroups()..update(1, () => candidates);
      expect(informationCameraSplitDistanceKm, 2500);
      expect(groups.sharedGroup('0')?.members.map((e) => e.key), ['0', '1']);
      expect(groups.sharedGroup('2'), isNull);
      groups.update(2, () => candidates.reversed.toList());
      expect(groups.sharedGroup('0')?.members.map((e) => e.key), ['0', '1']);
      expect(groups.sharedGroup('2'), isNull);
    },
  );

  for (final size in [const Size(1584, 850), const Size(390, 844)]) {
    testWidgets(
      'real ShakeMap and source report keep the fitted camera $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final frame = frameFor('ci41345415');
        final candidates = candidatesFor(frame);
        final groups = InformationCameraGroups()..update(1, () => candidates);
        final controller = MapController();
        final state = MapStateProvider();
        addTearDown(state.dispose);
        late BuildContext mapContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                mapContext = context;
                return FlutterMap(
                  mapController: controller,
                  options: const MapOptions(
                    initialCenter: LatLng(29.36, 120.17),
                  ),
                  children: const [],
                );
              },
            ),
          ),
        );
        state.setController(controller, const TestVSync());
        void focus(String key) => groups.focus(
          context: mapContext,
          mapState: state,
          group: groups.sharedGroup(key)!,
        );
        focus(candidates.first.key);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1300)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        final center = controller.camera.center, zoom = controller.camera.zoom;
        final padding = usgsProductViewportPadding(mapContext);
        final expectedAnchor = Offset(
          padding.left + (size.width - padding.horizontal) / 2,
          padding.top + (size.height - padding.vertical) / 2,
        );
        expect(
          (controller.camera.latLngToScreenOffset(candidates.first.location) -
                  expectedAnchor)
              .distance,
          lessThan(1),
        );
        var moves = 0;
        final subscription = controller.mapEventStream.listen((_) => moves++);
        for (var i = 0; i < 8; i++) {
          focus(candidates[i % 2].key);
          await tester.pump(const Duration(seconds: 1));
          expect(controller.camera.center, center);
          expect(controller.camera.zoom, zoom);
        }
        expect(moves, 0);
        await tester.runAsync(subscription.cancel);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
