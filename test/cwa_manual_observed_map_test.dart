import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/cwa_report_intensities.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/cwa_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  testWidgets('CWA map button loads the second report’s observed regions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'api_source_nied_monitor_enabled': false,
      'api_source_nied_lpgm_enabled': false,
      'api_source_kma_pews_enabled': false,
      'api_source_palert_enabled': false,
      'api_source_wolfx_seisjs_enabled': false,
      'api_source_snet_enabled': false,
      'trem_station_enabled': false,
    });
    final out = Directory('tmp/cwa_manual_observed_map')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => out.absolute.path,
        );
    const root = 'test/fixtures/cwa_catalog_20261028';
    final listBytes = File(
      '$root/trem_list_20261123.original.json',
    ).readAsBytesSync();
    final detailBytes = File(
      '$root/trem_second_detail_20261123.original.json',
    ).readAsBytesSync();
    final detail = jsonDecode(utf8.decode(detailBytes)) as Map<String, dynamic>;
    final expected = CwaReportIntensities.toWarnArea(detail);
    final response = Completer<http.Response>();
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return switch (request.url.path) {
        '/api/v2/eq/report' => http.Response.bytes(listBytes, 200),
        '/api/v2/eq/report/115000-2026-1117-222850' => response.future,
        _ => http.Response('', 404),
      };
    });
    addTearDown(client.close);
    final catalog = CwaEqlistService.forTesting(client);
    await tester.runAsync(catalog.fetchForTesting);
    final row = catalog.latestList[1];
    expect(row.eventId, detail['id']);
    expect(row.informationMap?.warnArea, isEmpty);
    expect(paths, [
      '/api/v2/eq/report',
      '/api/v2/eq/report/${catalog.latestList.first.eventId}',
    ]);
    final manager = EqlistManager()..updateCwaList([row]);
    addTearDown(() => manager.updateCwaList(const []));
    final provider = QuakeProvider(
      startCatalogServices: false,
      nativeUnifiedEvents: true,
      manualCwaCatalog: catalog,
    );
    final state = MapStateProvider()..setTileKey(MapConfig.vectorBasemapKey);
    final controller = MapController();
    await tester.runAsync(() => provider.eewHistoryReadyForTest);
    await tester.runAsync(loadUnifiedUiFonts);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: state),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                QuakeMapView(mapController: controller),
                const Positioned(
                  left: 0,
                  top: 100,
                  bottom: 0,
                  child: EqlistPanel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    state.setController(controller, const TestVSync());
    Future<void> settleFill() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 90)),
        );
        await tester.pump(const Duration(milliseconds: 90));
      }
    }

    await settleFill();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text(row.location).first));
    await tester.pump();
    await tester.tap(find.text('地图显示'));
    await tester.pump();

    expect(state.selectedHistoryEvent, same(row));
    expect(paths.last, '/api/v2/eq/report/${row.eventId}');
    final fill = find.descendant(
      of: find.byType(InformationEventFillLayer),
      matching: find.byType(IntensityFillLayer),
    );
    expect(tester.widget<IntensityFillLayer>(fill).mode, IntensityFillMode.cwa);
    response.complete(http.Response.bytes(detailBytes, 200));
    await settleFill();

    final selected = provider.selectedInformationMapEvent!;
    expect(selected.warnArea, expected);
    expect(cwaObservedFillAvailable(selected), isTrue);
    expect(CwaReportIntensities.fromWarnArea(selected.warnArea), {
      '臺東縣': 2,
      '花蓮縣': 2,
    });
    expect(
      tester.widget<IntensityFillLayer>(fill).mode,
      IntensityFillMode.cwaObserved,
    );
    final layer = tester.widget<PolygonLayer>(
      find.descendant(
        of: find.byType(InformationEventFillLayer),
        matching: find.byType(PolygonLayer),
      ),
    );
    expect(layer.polygons, isNotEmpty);
    expect(provider.unifiedEvents, isEmpty);
    expect(manager.cwaList.single.informationMap?.warnArea, isEmpty);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    state.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
