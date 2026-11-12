import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/core/utils/cenc_ir_region_intensities.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_layer.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:latlong2/latlong.dart';

CencIrData read(String name) => CencIrData.fromNowQuakeJson(
  jsonDecode(File('test/fixtures/$name').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final zaduo = read('cenc_ir_zaduo_20261024163952.original.json');
  final mojiang = read('cenc_ir_mojiang_20260914170727.json');

  test(
    'original stations fill their own regions with observed maxima',
    () async {
      final geography = (await TopoJsonLoader.loadCnEew())!;
      final original = jsonEncode(zaduo.toMap());
      final values = CencIrRegionIntensities.fromStations(
        geography,
        zaduo.instrumentIntensities,
      );
      debugPrint('ZADUO_OBSERVED_REGIONS $values');
      expect(values['嘉黎县'], 8.7);
      expect(values['比如县'], 4.1);
      expect(values['治多县'], 1.0);
      expect(values, hasLength(13));
      expect(values.containsKey('东城区'), isFalse);
      expect(values.containsKey('拉萨市'), isFalse);
      // Every regional maximum remains one of the source observations.
      for (final value in values.values) {
        expect(
          zaduo.instrumentIntensities.map((s) => s.intensity),
          contains(value),
        );
      }
      expect(jsonEncode(zaduo.toMap()), original);
      final extent = CencIrRegionIntensities.filledBounds(
        geography,
        zaduo.instrumentIntensities,
      );
      expect(extent, hasLength(4));
      expect(
        identical(
          extent,
          CencIrRegionIntensities.filledBounds(
            geography,
            zaduo.instrumentIntensities,
          ),
        ),
        isTrue,
      );
      final focus = cencIrFocusPoints(
        data: zaduo,
        eventId: zaduo.reportId,
        epicenterLatitude: zaduo.epiLat,
        epicenterLongitude: zaduo.epiLon,
        geography: geography,
      );
      expect(focus, containsAll(extent));
      expect(focus.length, 26);
      expect(
        CencIrRegionIntensities.fromStations(geography, const []),
        isEmpty,
      );
    },
  );

  testWidgets(
    'live sibling paint reuses observed fill, camera still repaints it',
    (tester) async {
      await tester.runAsync(TopoJsonLoader.loadCnEew);
      final controller = MapController();
      final pulse = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(32.54, 93.97),
              initialZoom: 6,
            ),
            children: [
              CencIrLayer(data: zaduo),
              CustomPaint(painter: _LiveSiblingPainter(pulse)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.ancestor(
          of: find.byType(PolygonLayer),
          matching: find.byType(RepaintBoundary),
        ).first,
      );
      boundary.debugResetMetrics();
      for (var i = 1; i <= 5; i++) {
        pulse.value = i;
        await tester.pump();
      }
      expect(boundary.debugSymmetricPaintCount, 0);
      expect(boundary.debugAsymmetricPaintCount, greaterThanOrEqualTo(5));
      boundary.debugResetMetrics();
      controller.move(const LatLng(32.6, 94), 6.2);
      await tester.pump();
      expect(
        boundary.debugSymmetricPaintCount + boundary.debugAsymmetricPaintCount,
        greaterThan(0),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      pulse.dispose();
    },
  );

  testWidgets(
    'observed fill updates, caches on pan, and keeps station painter',
    (tester) async {
      final geography = (await tester.runAsync(TopoJsonLoader.loadCnEew))!;
      final controller = MapController();
      Future<void> show(CencIrData? data) async {
        await tester.pumpWidget(
          MaterialApp(
            home: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(32.54, 93.97),
                initialZoom: 6,
              ),
              children: [CencIrLayer(data: data)],
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(zaduo);
      final polygons = tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons;
      final jiali = geography.getRegion('嘉黎县')!;
      final color = Color(
        IntensityCalculator.getCsisColor(9),
      ).withValues(alpha: .55);
      for (final points in jiali.polygons.where((p) => p.length >= 3)) {
        expect(
          polygons.singleWhere((p) => identical(p.points, points)).color,
          color,
        );
      }
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<CencIrPainter>()
            .single
            .data,
        same(zaduo),
      );
      controller.move(const LatLng(32.6, 94), 6.2);
      await tester.pump();
      expect(
        identical(
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
          polygons,
        ),
        isTrue,
      );

      await show(mojiang);
      final updated = tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons;
      expect(identical(updated, polygons), isFalse);
      expect(
        updated.any(
          (p) => jiali.polygons.any((ring) => identical(p.points, ring)),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await show(null);
      expect(find.byType(PolygonLayer), findsNothing);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<CencIrPainter>(),
        isEmpty,
      );
    },
  );
}

class _LiveSiblingPainter extends CustomPainter {
  _LiveSiblingPainter(this.pulse) : super(repaint: pulse);
  final ValueNotifier<int> pulse;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(
    Offset(10.0 + pulse.value, 10),
    3,
    Paint()..color = Colors.white,
  );

  @override
  bool shouldRepaint(covariant _LiveSiblingPainter oldDelegate) => false;
}
