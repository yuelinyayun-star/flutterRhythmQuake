import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/cwa_intensity_prediction.dart';
import 'package:flutterrhythmquake/core/cwa_report_intensities.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/information_fill_geometry.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_region_fill_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original CWA county polygons use native bounds once and EEW cannot reuse them',
    () async {
      final file = File(
        'test/fixtures/source_estimation/cwa_report_115068_original.json',
      );
      final hash = sha256.convert(file.readAsBytesSync());
      final raw =
          jsonDecode(file.readAsStringSync(encoding: utf8))
              as Map<String, dynamic>;
      final event = QuakeEventAdapter.convert('cwaEqlist', raw, 0)!;
      final ranks = CwaReportIntensities.fromWarnArea(event.warnArea);
      final topo = (await TopoJsonLoader.loadTwEew())!;
      final painted = topo.regions
          .where(
            (r) =>
                (ranks[CwaIntensityPrediction.canonicalCounty(r.name)] ?? 0) >=
                1,
          )
          .toList();
      expect(painted, isNotEmpty);
      final geometry = InformationFillGeometry(painted);
      final calls = NativeCameraFocus.supported ? NativeCameraFocus.calls : 0;
      InformationFillGeometry(painted);
      if (NativeCameraFocus.supported) expect(NativeCameraFocus.calls, calls);
      final bounds = geometry.forEvent(
        event,
        namedRegions: false,
        representative: false,
      );
      expect(bounds, hasLength(4));
      final rectangle = LatLngBounds.fromPoints(bounds);
      for (final region in painted) {
        for (final polygon in region.polygons) {
          for (final p in polygon) {
            expect(
              p.latitude,
              inInclusiveRange(rectangle.south, rectangle.north),
            );
            expect(
              p.longitude,
              inInclusiveRange(rectangle.west, rectangle.east),
            );
          }
        }
      }
      expect(
        NativeCameraFocus.prepare({
          'op': 'informationFillBounds',
          'isEew': true,
          'regions': geometry.regions,
          'warnArea': event.warnArea,
          'namedRegions': false,
        }),
        isEmpty,
      );
      expect(
        geometry.forEvent(event, namedRegions: false, representative: false),
        bounds,
      );
      if (NativeCameraFocus.supported) expect(NativeCameraFocus.outputs, 0);
      expect(sha256.convert(file.readAsBytesSync()), hash);
    },
  );

  testWidgets(
    'LPGM geometry callback matches painted polygons without changing its palette',
    (tester) async {
      final topo = await tester.runAsync(TopoJsonLoader.loadJpEew);
      final region = topo!.regions.firstWhere(
        (r) => r.code.isNotEmpty && r.polygons.any((p) => p.length >= 3),
      );
      // Controlled renderer contract, not an earthquake observation or live alert.
      final bulletin = JmaLpgmBulletin.fromMap({
        'eventId': 'geometry-contract',
        'regions': [
          {'name': region.name, 'code': region.code, 'maxLgInt': 2},
        ],
      });
      var callbacks = 0;
      List<TopoJsonRegion>? reported;
      Widget host(Object geometryKey) => MaterialApp(
        home: FlutterMap(
          options: const MapOptions(initialCenter: LatLng(36, 138)),
          children: [
            JmaLpgmRegionFillLayer(
              bulletin: bulletin,
              informationGeometryKey: geometryKey,
              onInformationGeometry: (regions) {
                callbacks++;
                reported = regions;
              },
            ),
          ],
        ),
      );
      await tester.pumpWidget(host('first'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      final polygons = tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons;
      expect(reported!.map((r) => r.code), contains(region.code));
      expect(
        polygons.length,
        region.polygons.where((p) => p.length >= 3).length,
      );
      expect(polygons.first.color, jmaLpgmClassColor(2).withValues(alpha: .55));
      expect(callbacks, 1);
      await tester.pump();
      expect(callbacks, 1);
      await tester.pumpWidget(host('updated-consumer'));
      await tester.pump();
      expect(callbacks, 2);
      expect(
        identical(
          polygons,
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
        ),
        isTrue,
        reason:
            'publish revised geometry ownership without rebuilding polygons',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
