import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart'
    show NiedIntensityNumberMarker;
import 'package:flutterrhythmquake/widgets/map/vector_basemap_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'package:flutterrhythmquake/widgets/ui/event_render_page.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'support/unified_ui_fonts.dart';

const fixture = 'test/fixtures/jma_lpgm_20261108';
final output = Directory(
  'tmp/jma_lpgm_combined_nied_numeric_icons_font_verified_20261108',
);

Future<void> _writeScreenshot(
  WidgetTester tester,
  Finder finder,
  String fileName,
) async {
  await tester.runAsync(() async {
    final object = tester.renderObject(finder) as RenderRepaintBoundary;
    final image = await object.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      output.createSync(recursive: true);
      File(
        '${output.path}/$fileName',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real VXSE53 + VXSE62: combined event renders JMA intensity polygon, '
    'four LPGM stations and two intensity badges (16:9 and split)',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'weather_alarm_local_only': false,
        'map_view_lat': 35.0,
        'map_view_lng': 137.2,
      });
      tester.view.physicalSize = const Size(1880, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vxse53 = XmlDocument.parse(
        File('$fixture/20261107161257_0_VXSE53_010000.xml').readAsStringSync(),
      );
      String xmlText(String name) => vxse53.descendants
          .whereType<XmlElement>()
          .firstWhere((element) => element.name.local == name)
          .innerText
          .trim();
      final officialId = xmlText('EventID');
      final officialMax = xmlText('MaxInt');
      final officialMagnitude = double.parse(xmlText('Magnitude'));
      final officialOrigin = DateTime.parse(xmlText('OriginTime'));
      final officialReport = DateTime.parse(xmlText('ReportDateTime'));
      final serial = xmlText('Serial');
      expect(officialId, '20261108010441');
      expect(serial, '2');
      expect(officialMax, '5+');
      expect(officialMagnitude, 5.7);

      final parser = JmaLpgmService();
      final bulletin = parser.parseDetailForTesting(
        File('$fixture/20261107161354_0_VXSE62_010000.xml').readAsStringSync(),
      )!;
      parser.dispose();
      expect(bulletin.eventId, officialId);
      expect(bulletin.maxLgInt, 1);
      expect(bulletin.regions, hasLength(3));
      expect(bulletin.stations, hasLength(4));

      final originalRecords =
          (jsonDecode(
                    File(
                      '$fixture/p2p_551_live_all_reports.original.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      final raw = originalRecords.firstWhere(
        (r) => (r['issue'] as Map)['type'] == 'DetailScale',
      );
      final p2pEvent = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
      expect(p2pEvent.eventId, '2026-11-08 01:04:00');
      expect(p2pEvent.magnitude, officialMagnitude);
      expect(p2pEvent.depth, 40);
      expect(p2pEvent.lat, 34.9);
      expect(p2pEvent.lng, 137.7);
      expect(p2pEvent.warnArea, isNotEmpty);

      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      addTearDown(provider.dispose);
      await tester.runAsync(() async {
        await provider.eewHistoryReadyForTest;
      });
      // Keep the exact, nonstandard P2P event ID to exercise actual
      // cross-API association with the official VXSE62 EventID.
      provider.acceptJmaLpgm(
        JmaLpgmBulletin.fromMap({
          ...bulletin.toMap(),
          'reportTime': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final p2pJoined = provider.associatedJmaInformationFor(p2pEvent);
      expect(p2pJoined.jmaLpgmBulletin?.eventId, officialId);
      expect(p2pJoined.jmaLpgmBulletin?.stations, hasLength(4));

      // This is a test display projection from REAL data, not a VXSE53 JSON
      // API payload: VXSE53 official event/maximum/time + same-event
      // P2P detailScale's actual district-level observed intensity regions.
      final officialMain = p2pEvent.copyWith(
        eventId: officialId,
        maxIntensity: officialMax,
        titleText: '震源・震度に関する情報',
        reportNumText: '第2报',
        magnitude: officialMagnitude,
        originTime: officialOrigin,
        reportTime: officialReport,
      );
      final combined = provider.associatedJmaInformationFor(officialMain);
      expect(combined.jmaLpgmBulletin?.eventId, officialId);
      expect(combined.maxIntensity, '5+');
      expect(combined.jmaLpgmBulletin?.maxLgInt, 1);
      expect(combined.source, 'jmaEqlist');
      expect(combined.isJmaLpgm, isFalse);

      await tester.runAsync(() async {
        await loadUnifiedUiFonts();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await AppPageBackground.cachedBytes();
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<PageBackgroundProvider>(
          create: (_) => PageBackgroundProvider(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: unifiedUiTestTheme(),
            home: EventRenderPage(event: combined),
          ),
        ),
      );
      await tester.pump();
      await _settle(tester);

      expect(find.byType(InformationEventFillLayer), findsOneWidget);
      expect(find.byType(IntensityFillLayer), findsOneWidget);
      expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(JmaLpgmStationLayer),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('render_header_intensity_text')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('render_header_lpgm_text')),
        findsOneWidget,
      );
      final intensityText = tester
          .widget<Text>(
            find.byKey(const ValueKey('render_header_intensity_text')),
          )
          .data;
      final lpgmText = tester
          .widget<Text>(find.byKey(const ValueKey('render_header_lpgm_text')))
          .data;
      expect(intensityText, '最大震度 5+');
      expect(lpgmText, '长周期 1');

      final stationKeys = [
        for (final station in bulletin.stations)
          ValueKey('jma_lpgm_station_${station.code}'),
      ];
      for (final stationKey in stationKeys) {
        expect(
          find.byKey(stationKey),
          findsOneWidget,
          reason: 'missing $stationKey',
        );
      }
      final polygons = tester
          .widgetList<PolygonLayer>(
            find.descendant(
              of: find.byType(IntensityFillLayer),
              matching: find.byType(PolygonLayer),
            ),
          )
          .expand((layer) => layer.polygons)
          .toList();
      expect(polygons, isNotEmpty);
      final locations = await JmaLpgmStationLocations.load();
      expect(
        JmaLpgmStationLocations.located(bulletin, locations),
        hasLength(4),
      );
      debugPrint(
        'COMBINED_REAL_RENDER event=$officialId '
        'ordinaryMax=$intensityText lpgm=$lpgmText '
        'jmaPolygons=${polygons.length} stations=4 '
        'p2pWireId=${raw['id']}',
      );
      await _writeScreenshot(
        tester,
        find.byKey(const ValueKey('render_canvas_repaint')),
        'combined_vxse53_vxse62_full_1600x900.png',
      );
      // Actual Flutter map only, without covering information sidebar.
      await _writeScreenshot(
        tester,
        find.byKey(const ValueKey('render_map_repaint')),
        'map_only_existing_event_render_page.png',
      );

      await tester.tap(find.byKey(const ValueKey('render_layout_split')));
      await tester.pump();
      await _settle(tester);
      expect(find.byType(IntensityFillLayer), findsOneWidget);
      expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
      await _writeScreenshot(
        tester,
        find.byKey(const ValueKey('render_canvas_repaint')),
        'combined_vxse53_vxse62_split_1600x900.png',
      );

      // Render genuine vector-basemap + observed intensity + LPGM station
      // layers in a dedicated full-screen map at two real zoom levels.
      for (final zoom in [6.3, 8.2, 9.2]) {
        final mapBoundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: unifiedUiTestTheme(),
            home: Scaffold(
              backgroundColor: VectorBasemapLayer.oceanColor,
              body: Center(
                child: SizedBox(
                  width: 1600,
                  height: 900,
                  child: RepaintBoundary(
                    key: mapBoundary,
                    child: FlutterMap(
                      key: ValueKey('lpgm_only_map_' + zoom.toString()),
                      options: MapOptions(
                        initialCenter: const LatLng(35.14, 137.40),
                        initialZoom: zoom,
                        minZoom: 2.5,
                        maxZoom: 12,
                        backgroundColor: VectorBasemapLayer.oceanColor,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        const VectorBasemapLayer(),
                        InformationEventFillLayer(event: combined),
                        const VectorBasemapLabels(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await _settle(tester);

        expect(find.byType(IntensityFillLayer), findsOneWidget);
        expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
        final mapPolygons = tester
            .widgetList<PolygonLayer>(
              find.descendant(
                of: find.byType(IntensityFillLayer),
                matching: find.byType(PolygonLayer),
              ),
            )
            .expand((layer) => layer.polygons)
            .toList();
        expect(mapPolygons, isNotEmpty);
        final stationMarkerLayer = tester.widget<MarkerLayer>(
          find.descendant(
            of: find.byType(JmaLpgmStationLayer),
            matching: find.byType(MarkerLayer),
          ),
        );
        expect(stationMarkerLayer.markers, hasLength(4));
        expect(
          find.descendant(
            of: find.byType(JmaLpgmStationLayer),
            matching: find.byType(NiedIntensityNumberMarker),
          ),
          findsNWidgets(4),
        );
        for (final marker in stationMarkerLayer.markers) {
          expect(marker.width, NiedIntensityNumberMarker.markerSize);
          expect(marker.height, NiedIntensityNumberMarker.markerSize);
        }

        expect(
          find.descendant(
            of: find.byType(JmaLpgmStationLayer),
            matching: find.byType(Tooltip),
          ),
          findsNothing,
        );
        debugPrint(
          'LPGM_MAP_ONLY zoom=' +
              zoom.toString() +
              ' polygons=' +
              mapPolygons.length.toString() +
              ' stationMarkers=' +
              stationMarkerLayer.markers.length.toString(),
        );
        await _writeScreenshot(
          tester,
          find.byKey(mapBoundary),
          zoom == 6.3
              ? 'map_only_vxse53_vxse62_overview_1600x900.png'
              : zoom == 8.2
              ? 'map_only_vxse53_vxse62_station_focus_1600x900.png'
              : 'map_only_vxse53_vxse62_station_closeup_1600x900.png',
        );
      }

      // The P2P-native identity variant must also render the LPGM badge
      // without rewriting its own API eventId to the official XML ID.
      expect(p2pJoined.eventId, p2pEvent.eventId);
    },
  );

  testWidgets('unified JMA alert card visibly adds EEW-style LPGM footer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'weather_alarm_local_only': false,
      'map_view_lat': 35.0,
      'map_view_lng': 137.2,
    });
    tester.view.physicalSize = const Size(900, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadUnifiedUiFonts);
    final parser = JmaLpgmService();
    final bulletin = parser.parseDetailForTesting(
      File('$fixture/20261107161354_0_VXSE62_010000.xml').readAsStringSync(),
    )!;
    parser.dispose();
    final originalRecords =
        (jsonDecode(
                  File(
                    '$fixture/p2p_551_live_all_reports.original.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map<String, dynamic>>();
    final original = QuakeEventAdapter.convert(
      'jmaEqlist',
      originalRecords.first,
      2,
    )!;
    final combined = original.copyWith(jmaLpgmBulletin: bulletin);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: unifiedUiTestTheme(),
        home: Scaffold(
          backgroundColor: const Color(0xff070a12),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: UnifiedAlertCard(event: combined),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('jma-eew-long-period-footer')),
      findsOneWidget,
    );
    expect(find.text('长周期 1'), findsOneWidget);
    await _writeScreenshot(
      tester,
      find.byKey(key),
      'unified_jma_lpgm_alert_card.png',
    );
  });
}
