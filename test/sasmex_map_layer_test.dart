import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_animation_clock.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/sasmex_map_geometry.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/widgets/map/sasmex_map_layer.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'package:latlong2/latlong.dart';

// Actual historical Firestore document, not a manufactured realtime message.
UnifiedQuakeData originalOctober6Event() {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/sasmex_firestore_20261006.original.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map<String, dynamic>;
  final epoch = (raw['unix'] as int) * 1000;
  return SasmexService.parseRelayFrame({
    'type': 'snapshot',
    'Data': {
      ...raw,
      'id': '$epoch',
      'eventId': '$epoch',
      'epochMs': epoch,
      'lat': raw['epicenter']['latitude'],
      'lng': raw['epicenter']['longitude'],
    },
  })!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final event = originalOctober6Event();
  final sourceTime = QuakeTime.unifiedInstantUtc(event);

  test(
    'real coordinates select Oaxaca without injecting a state or coordinates',
    () async {
      final catalog = await SasmexMapCatalog.load();
      expect(catalog.states.length, 32);
      expect(catalog.stateFor(event)!.name, 'Oaxaca');
      expect(event.sourcePayload!['region'], 'Santa María Huazolotitlán, Oax.');
      expect(event.lat, 16.29569);
      expect(event.lng, -97.90988);
    },
  );

  test('website rings use source time without magnitude/depth defaults', () {
    final animation = SasmexMapAnimation.at(
      event,
      sourceTime.add(const Duration(seconds: 20)),
    )!;
    expect(animation.pRadiusMeters, 216000);
    expect(animation.sRadiusMeters, 100000);
    expect(event.originTime, DateTime.utc(2026, 10, 6, 4, 9, 46));
    expect(event.magnitude, -1);
    expect(event.depth, -1);
    expect(event.sourcePayload!.containsKey('severity'), false);
    expect(SasmexMapAnimation.cameraRadiusKm(20, severe: false), 216);
  });

  test('old delivery and future timestamps cannot restart propagation', () {
    expect(
      SasmexMapAnimation.at(event, sourceTime.add(const Duration(minutes: 3))),
      isNull,
    );
    expect(SasmexMapAnimation.at(event, DateTime.utc(2026, 10, 8)), isNull);
    expect(
      SasmexMapAnimation.at(
        event,
        sourceTime.subtract(const Duration(seconds: 1)),
      ),
      isNull,
    );
    expect(SasmexMapAnimation.cameraRadiusKm(300, severe: true), 0);
    expect(SasmexMapAnimation.cameraRadiusKm(299, severe: true), 2000);
  });

  testWidgets(
    'state layer and our existing wave painter share the unchanged source without station markers',
    (tester) async {
      final leases = EventAnimationClock.instance.activeLeaseCount;
      var displayTime = sourceTime.add(const Duration(seconds: 20));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(20.3092, -105.6313),
                initialZoom: 8,
              ),
              children: [
                SasmexMapLayer(
                  events: [event],
                  displayClock: () => displayTime,
                ),
                IgnorePointer(
                  child: QuakeWaveLayer(
                    event: SasmexService.parseRelayEvent(event.sourcePayload!)!,
                    showWaves: true,
                    showEpicenterLabel: false,
                    sWaveColor: const Color(0xFFFFFF1F),
                    displayClock: () => displayTime,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() async => SasmexMapCatalog.load());
      await tester.pump();
      final polygons = tester.widget<PolygonLayer>(find.byType(PolygonLayer));
      expect(polygons.polygons.length, greaterThan(0));
      final fillColors = polygons.polygons
          .map((polygon) => polygon.color)
          .toList();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<PolygonLayer>(find.byType(PolygonLayer))
            .polygons
            .map((polygon) => polygon.color)
            .toList(),
        fillColors,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<PolygonLayer>(find.byType(PolygonLayer))
            .polygons
            .map((polygon) => polygon.color)
            .toList(),
        fillColors,
      );
      expect(find.byType(PolylineLayer), findsNothing);
      final drawing = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is WavePainter,
        ),
      );
      final painter = drawing.painter! as WavePainter;
      expect(painter.showWaves, true);
      expect(painter.pWaveColor, isNull); // Existing default white.
      expect(
        painter.sWaveColor,
        const Color(0xFFFFFF1F),
      ); // Existing unified yellow.
      expect(painter.event.originTime, DateTime.utc(2026, 10, 6, 4, 9, 46));
      expect(find.byType(MarkerLayer), findsNothing);
      displayTime = sourceTime.add(const Duration(minutes: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PolygonLayer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(EventAnimationClock.instance.activeLeaseCount, leases);
    },
  );
}
