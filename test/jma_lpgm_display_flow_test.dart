import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_region_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_region_value_badge_layer.dart';
import 'package:flutterrhythmquake/widgets/map/vector_basemap_layer.dart';
import 'package:latlong2/latlong.dart';

import 'support/unified_ui_fonts.dart';

const _fixtures = 'test/fixtures/jma_lpgm_20261108';
final _observedAt = DateTime.parse('2026-11-08T01:13:01+09:00');

JmaLpgmBulletin originalBulletin() {
  final parser = JmaLpgmService();
  try {
    return parser.parseDetailForTesting(
      File(
        '$_fixtures/20261107161354_0_VXSE62_010000.xml',
      ).readAsStringSync(encoding: utf8),
    )!;
  } finally {
    parser.dispose();
  }
}

UnifiedQuakeData originalInformation() {
  final rows =
      jsonDecode(
            File(
              '$_fixtures/p2p_551_live_all_reports.original.json',
            ).readAsStringSync(encoding: utf8),
          )
          as List;
  final raw = Map<String, dynamic>.from(
    rows.firstWhere((r) => r['issue']['type'] == 'DetailScale') as Map,
  );
  return QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
}

UnifiedQuakeData longPeriodEvent(JmaLpgmBulletin b) => UnifiedQuakeData(
  source: 'jmaLpgm',
  origin: 7,
  eventId: b.eventId,
  isEew: false,
  timeZone: 9,
  titleText: jmaLpgmObservationTitle,
  reportNumText: '第${b.serial}报',
  useShindo: false,
  maxIntensity: '${b.maxLgInt}',
  className: 'yellow',
  hypocenter: b.hypocenter,
  originTime: b.originTime,
  reportTime: b.reportTime,
  magnitude: b.magnitude!,
  depth: b.depthKm!,
  lat: b.latitude,
  lng: b.longitude,
  isJmaLpgm: true,
  jmaLpgmBulletin: b,
);

Map<String, dynamic> _context(DateTime sourceTime) => {
  'nowUs': sourceTime.microsecondsSinceEpoch,
  'nowIso': sourceTime.toIso8601String(),
  'sourceNowUs': sourceTime.microsecondsSinceEpoch,
  'eewNowUs': sourceTime.microsecondsSinceEpoch,
  'localOffsetMinutes': 0,
  'showStale': false,
  'historyLoaded': true,
  'historyKeepForever': true,
  'historyMaxPerSource': 15,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unaltered VXSE62 and P2P: native merge, restoration, cancel, ownership',
    () {
      final baseline = NativeUnifiedEventOwner.diagnostics;
      var now = _observedAt;
      withClock(Clock(() => now), () {
        late Map<String, dynamic> batch;
        late Map<int, UnifiedQuakeData> pool;
        final owner = NativeUnifiedEventOwner(
          manualClock: true,
          onBatch: (b, p) {
            batch = b;
            pool = Map.of(p);
          },
        );
        try {
          final ordinary = originalInformation();
          final b = originalBulletin();
          expect(b.regions, hasLength(3));
          expect(b.stations, hasLength(4));
          owner.admit(ordinary, _context(now), suppressEffects: true);
          expect(batch['active'], hasLength(1));
          owner.admit(longPeriodEvent(b), _context(now));
          expect(
            batch['active'],
            hasLength(2),
            reason: 'source lifetime retained',
          );
          final display = batch['jmaLpgmDisplay'] as Map;
          expect(display['active'], hasLength(1));
          expect(display['links'], hasLength(1));
          expect(display['links'][0]['showRegions'], true);
          final retained = pool[(display['active'] as List).single]!;
          expect(retained.titleText, ordinary.titleText);
          expect(retained.maxIntensity, ordinary.maxIntensity);
          expect(retained.eventId, ordinary.eventId);
          expect(retained.sourcePayload, ordinary.sourcePayload);
          expect(
            (batch['actions'] as List).any((a) => a[0] == 'effects'),
            true,
            reason: 'hidden companion still dispatches its existing effects',
          );
          now = now.add(const Duration(seconds: 14));
          owner.send({'op': 'jmaLpgmSpeech', 'busy': true});
          now = now.add(const Duration(seconds: 2));
          owner.send({'op': 'tick'});
          expect(
            batch['jmaLpgmDisplay']['links'],
            isNotEmpty,
            reason: jsonEncode(batch),
          );
          expect(batch['jmaLpgmDisplay']['links'][0]['showRegions'], true);
          owner.send({'op': 'jmaLpgmSpeech', 'busy': false});
          expect(batch['jmaLpgmDisplay']['links'][0]['showRegions'], false);
          owner.send({'op': 'jmaLpgmSpeech', 'busy': true});
          expect(batch['jmaLpgmDisplay']['links'][0]['showRegions'], false);
          owner.send({'op': 'clearJmaLpgm', 'eventId': b.eventId});
          expect(batch['active'], hasLength(1));
          expect(batch['jmaLpgmDisplay']['links'], isEmpty);
          expect(pool[(batch['active'] as List).single]!.isJmaLpgm, false);
        } finally {
          owner.dispose();
        }
      });
      expect(NativeUnifiedEventOwner.diagnostics, baseline);
    },
  );

  test(
    'unaltered VXSE62 after ordinary expiry stays standalone then expires',
    () {
      var now = _observedAt;
      withClock(Clock(() => now), () {
        late Map<String, dynamic> batch;
        final owner = NativeUnifiedEventOwner(
          manualClock: true,
          onBatch: (b, _) => batch = b,
        );
        try {
          owner.admit(longPeriodEvent(originalBulletin()), _context(now));
          expect(
            batch['jmaLpgmDisplay']['active'],
            hasLength(1),
            reason: jsonEncode(batch),
          );
          expect(batch['jmaLpgmDisplay']['links'], isEmpty);
          now = now.add(const Duration(seconds: 16));
          owner.send({'op': 'tick'});
          expect(batch['jmaLpgmDisplay']['active'], hasLength(1));
          now = now.add(const Duration(seconds: 45));
          owner.send({'op': 'tick'});
          expect(batch['active'], isEmpty);
          expect(batch['jmaLpgmDisplay']['active'], isEmpty);
          expect(batch['jmaLpgmDisplay']['links'], isEmpty);
        } finally {
          owner.dispose();
        }
      });
    },
  );

  testWidgets(
    'original long-period regions and stations render without region badges',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadUnifiedUiFonts);
      final b = originalBulletin();
      final ordinary = originalInformation().copyWith(jmaLpgmBulletin: b);
      final boundary = GlobalKey();
      for (final mode in ['combined', 'restored', 'standalone']) {
        final event = mode == 'standalone' ? longPeriodEvent(b) : ordinary;
        await tester.pumpWidget(
          MaterialApp(
            theme: unifiedUiTestTheme(),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(35.1, 137.5),
                    initialZoom: 7.3,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    const VectorBasemapLayer(),
                    InformationEventFillLayer(
                      event: event,
                      showLongPeriodRegions: mode == 'combined',
                    ),
                    const VectorBasemapLabels(),
                  ],
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
        final markers = tester.widget<MarkerLayer>(
          find.descendant(
            of: find.byType(JmaLpgmStationLayer),
            matching: find.byType(MarkerLayer),
          ),
        );
        expect(markers.markers, hasLength(4));
        if (mode == 'restored') {
          expect(find.byType(IntensityFillLayer), findsOneWidget);
          expect(find.byType(JmaLpgmRegionFillLayer), findsNothing);
        } else {
          expect(find.byType(IntensityFillLayer), findsNothing);
          final polygons = tester
              .widget<PolygonLayer>(
                find.descendant(
                  of: find.byType(JmaLpgmRegionFillLayer),
                  matching: find.byType(PolygonLayer),
                ),
              )
              .polygons;
          expect(polygons, isNotEmpty);
          expect(polygons.where((p) => p.label != null), isEmpty);
          for (final p in polygons) {
            expect(p.color, jmaLpgmClassColor(1).withValues(alpha: .55));
            expect(p.borderColor, jmaLpgmClassColor(1));
          }
          expect(find.byType(JmaRegionValueBadgeLayer), findsNothing);
        }
        await tester.runAsync(() async {
          final repaint =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await repaint.toImage();
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final out = Directory('tmp/jma_lpgm_display_20261110')
              ..createSync(recursive: true);
            File(
              '${out.path}/$mode.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
