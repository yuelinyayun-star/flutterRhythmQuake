import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/core/utils/cenc_ir_region_intensities.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_layer.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final out = Directory('tmp/cenc_manual_fill_20261122');

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

  testWidgets('Delingha catalogue map shows only the selected CENC fill', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final row = QuakeEventAdapter.convertWolfxCencEqlist(
      read('delingha_20261121/wolfx-cenc-list.original.json')
          as Map<String, dynamic>,
    ).singleWhere((row) => row.eventId == 'AU.20261121184534.4');
    final report = CencIrData.fromNowQuakeJson(
      read('delingha_20261121/delingha-nowquake-detail.original.json')
          as Map<String, dynamic>,
    );
    final unrelated = CencIrData.fromNowQuakeJson(
      read('cenc_ir_zaduo_20261024163952.original.json')
          as Map<String, dynamic>,
    );
    final provider = QuakeProvider(
      startCatalogServices: false,
      nativeUnifiedEvents: true,
    );
    final previousTileUrl = MapConfig.currentTileUrl;
    addTearDown(() => MapConfig.currentTileUrl = previousTileUrl);
    final state = MapStateProvider()..setTileKey(MapConfig.vectorBasemapKey);
    final controller = MapController();
    final manager = EqlistManager();
    manager.updateCencList([row]);
    addTearDown(() => manager.updateCencList(const []));
    await tester.runAsync(() => provider.eewHistoryReadyForTest);
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
    await settleFill();
    expect(find.text('取消显示'), findsOneWidget);
    expect(state.selectedHistoryEvent?.eventId, row.eventId);
    final information = find.byType(InformationEventFillLayer);
    final observed = find.byType(CencIrLayer);
    final estimatedPolygons = find.descendant(
      of: information,
      matching: find.byType(PolygonLayer),
    );
    expect(estimatedPolygons, findsOneWidget);
    expect(observed, findsNothing);
    expect(row.maxIntensity, 7);

    provider.updateManualCencIrDataForTest(unrelated);
    await settleFill();
    expect(estimatedPolygons, findsOneWidget);
    expect(observed, findsNothing);

    // A matched report with only metadata cannot replace the model fill.
    provider.updateManualCencIrDataForTest(
      CencIrData(
        source: CencIrDataSource.nowQuake,
        reportId: report.reportId,
        uniEventId: report.uniEventId,
        oriTime: report.oriTime,
        gmtCreate: report.gmtCreate,
        locName: report.locName,
        epiLon: report.epiLon,
        epiLat: report.epiLat,
        focDepth: report.focDepth,
        subjectCodes: report.subjectCodes,
        intensityInfoText: report.intensityInfoText,
      ),
    );
    await settleFill();
    expect(observed, findsOneWidget);
    expect(estimatedPolygons, findsOneWidget);
    provider.clearCencIrData();

    provider.updateManualCencIrDataForTest(report);
    await settleFill();
    expect(observed, findsOneWidget);
    expect(tester.widget<CencIrLayer>(observed).data, same(report));
    expect(estimatedPolygons, findsNothing);

    final geography = TopoJsonLoader.cnData!;
    final values = CencIrRegionIntensities.fromStations(
      geography,
      report.instrumentIntensities,
    );
    final expected = [
      for (final region in geography.regions)
        if (values[region.name] case final intensity?
            when CencIrRegionIntensities.isFilled(intensity))
          for (final points in region.polygons)
            if (points.length >= 3)
              (points, IntensityCalculator.getCsisColor(intensity.round())),
    ];
    expect(expected, isNotEmpty);
    final polygons = tester
        .widget<PolygonLayer>(
          find.descendant(of: observed, matching: find.byType(PolygonLayer)),
        )
        .polygons;
    expect(polygons.map((p) => (p.points, p.borderColor.toARGB32())), expected);

    provider.clearCencIrData();
    await settleFill();
    expect(estimatedPolygons, findsOneWidget);
    expect(observed, findsNothing);
    await tester.tap(find.text('取消显示'));
    await settleFill();
    expect(state.selectedHistoryEvent, isNull);
    expect(information, findsNothing);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    state.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
