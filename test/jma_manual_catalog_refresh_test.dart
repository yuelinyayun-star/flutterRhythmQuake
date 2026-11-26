import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/jma_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/wolfx_jma_detail_decoder.dart';
import 'package:flutterrhythmquake/services/sources/wolfx_jma_detail_feed.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/unified_ui_fonts.dart';

final out = Directory('tmp/jma_manual_catalog_refresh');

dynamic read(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync(encoding: utf8));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    out.createSync(recursive: true);
    SharedPreferences.setMockInitialValues({
      'api_source_nied_monitor_enabled': false,
      'api_source_nied_lpgm_enabled': false,
      'api_source_kma_pews_enabled': false,
      'api_source_palert_enabled': false,
      'api_source_wolfx_seisjs_enabled': false,
      'api_source_snet_enabled': false,
      'trem_station_enabled': false,
    });
    SoundEffectService().enabled = false;
    TtsService().enabled = false;
    QuakeMapView.niedMonitorEnabledNotifier.value = false;
    QuakeMapView.niedLpgmEnabledNotifier.value = false;
    QuakeMapView.kmaPewsEnabledNotifier.value = false;
    QuakeMapView.pAlertEnabledNotifier.value = false;
    QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
    QuakeMapView.snetEnabledNotifier.value = false;
    QuakeMapView.tremStationEnabledNotifier.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => out.absolute.path,
        );
  });

  testWidgets('JMA map button keeps reported fill after catalog refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const id = '20261119200801';
    const fixtures = 'wolfx_jma_detail_20261119';
    final summary = QuakeEventAdapter.convertWolfxJmaEqlist(
      read('$fixtures/jma_eqlist.original.json') as Map<String, dynamic>,
    );
    final summaryRow = summary.singleWhere((row) => row.eventId == id);
    expect(summaryRow.informationMap, isNull);
    final detailBytes = File(
      'test/fixtures/$fixtures/jma_earthquake_detail.original.json',
    ).readAsBytesSync();
    final detail = decodeWolfxJmaDetail(detailBytes);
    final report = QuakeEventAdapter.convertWolfxJmaDetail(
      (detail['reports'] as List).cast<Map<String, dynamic>>().singleWhere(
        (row) => row['eventId'] == id,
      ),
      isSnapshot: true,
    )!;
    expect(report.warnArea, isNotEmpty);

    final manager = EqlistManager();
    manager.updateJmaList(summary);
    addTearDown(() => manager.updateJmaList(const []));
    final detailResponse = Completer<http.Response>();
    var detailRequests = 0;
    final client = MockClient((request) {
      expect(request.url.host, 'api.wolfx.jp');
      expect(request.url.path, '/jma_earthquake_detail.json');
      detailRequests++;
      return detailResponse.future;
    });
    addTearDown(client.close);
    final provider = QuakeProvider(
      startCatalogServices: false,
      nativeUnifiedEvents: true,
      manualWolfxDetails: WolfxJmaDetailFeed(client: client),
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

    List<Object?> polygons() => tester
        .widgetList<PolygonLayer>(
          find.descendant(
            of: find.byType(InformationEventFillLayer),
            matching: find.byType(PolygonLayer),
          ),
        )
        .expand((layer) => layer.polygons)
        .map((polygon) => (polygon.points, polygon.borderColor))
        .toList();
    await settleFill();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    Future<void> openReport({bool waitForFill = true}) async {
      await mouse.moveTo(
        tester.getCenter(find.text(summaryRow.location).first),
      );
      await tester.pump();
      await tester.tap(find.text('地图显示'));
      await tester.pump();
      if (waitForFill) await settleFill();
      expect(state.selectedHistoryEvent?.eventId, id);
    }

    await openReport(waitForFill: false);
    expect(provider.selectedInformationMapEvent?.warnArea, isEmpty);
    expect(detailRequests, 1);
    await tester.tap(find.text('取消显示'));
    await tester.pump();
    detailResponse.complete(http.Response.bytes(detailBytes, 200));
    await settleFill();
    expect(provider.selectedInformationMapEvent, isNull);
    expect(polygons(), isEmpty);
    expect(provider.unifiedEvents, isEmpty);

    await openReport();
    expect(detailRequests, 1);
    expect(provider.selectedInformationMapEvent?.warnArea, report.warnArea);
    final fetchedPolygons = polygons();
    expect(fetchedPolygons, isNotEmpty);
    expect(provider.unifiedEvents, isEmpty);
    await tester.tap(find.text('取消显示'));
    await tester.pump();

    provider.handleUnifiedEventForTest(report, suppressEffects: true);
    await tester.runAsync(manager.waitForBucketBindings);
    await tester.pump();
    await openReport();
    final reportedPolygons = polygons();
    expect(reportedPolygons, isNotEmpty);
    expect(reportedPolygons, fetchedPolygons);
    await tester.tap(find.text('取消显示'));
    await settleFill();

    manager.updateJmaList(summary);
    await settleFill();
    expect(provider.unifiedEvents, isEmpty);
    expect(
      manager.jmaList
          .singleWhere((row) => row.eventId == '20261119174748')
          .informationMap,
      isNull,
    );
    await openReport();
    expect(provider.selectedInformationMapEvent?.warnArea, report.warnArea);
    expect(polygons(), reportedPolygons);
    expect(tester.takeException(), isNull);

    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    state.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  test(
    'JMA manual selection uses P2P only after Wolfx is unavailable',
    () async {
      const fixtures = 'event_render_20261104';
      final summary = QuakeEventAdapter.convertWolfxJmaEqlist(
        read('$fixtures/wolfx-jma.original.json') as Map<String, dynamic>,
      ).singleWhere((row) => row.eventId == '20261104053431');
      final p2pBytes = File(
        'test/fixtures/$fixtures/p2p.original.json',
      ).readAsBytesSync();
      final report = (jsonDecode(utf8.decode(p2pBytes)) as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (row) => row['earthquake']['time'] == '2026/11/04 05:34:00',
          );
      final expected = QuakeEventAdapter.convert(
        'jmaEqlist',
        report,
        2,
      )!.warnArea;
      expect(expected, isNotEmpty);
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return request.url.host == 'api.wolfx.jp'
            ? http.Response('', 503)
            : http.Response.bytes(p2pBytes, 200);
      });
      addTearDown(client.close);
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
        manualWolfxDetails: WolfxJmaDetailFeed(client: client),
        manualJmaCatalog: JmaEqlistService.forTesting(client),
      );
      addTearDown(provider.dispose);
      await provider.eewHistoryReadyForTest;
      final loaded = Completer<String>();
      provider.addListener(() {
        final warnArea = provider.selectedInformationMapEvent?.warnArea;
        if (warnArea?.isNotEmpty == true && !loaded.isCompleted) {
          loaded.complete(warnArea);
        }
      });
      provider.selectHistoryMapProducts(summary);
      expect(await loaded.future.timeout(const Duration(seconds: 3)), expected);
      expect(hosts, ['api.wolfx.jp', 'api.p2pquake.net']);
      expect(provider.unifiedEvents, isEmpty);
    },
  );
}
