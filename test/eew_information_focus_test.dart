import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Feed original accepted snapshots to the real map independently of live
// expiry. Only the existing transient replay clock changes; raw bodies stay
// unchanged. The two historical reports are separate earthquakes.
class _MapReports extends QuakeProvider {
  _MapReports()
    : super(startCatalogServices: false, nativeUnifiedEvents: false);
  final reports = <UnifiedQuakeData>[];
  UnifiedQuakeData? focus;
  CencIrData? details;
  @override
  CencIrData? get cencIrData => details;
  @override
  CencIrData? get realtimeCencIrData => details;
  @override
  List<UnifiedQuakeData> get unifiedEvents => List.unmodifiable(reports);
  @override
  List<QuakeMessage> get unifiedMapEvents => [
    for (final e in reports) unifiedToQuakeMessageForTest(e),
  ];
  @override
  UnifiedQuakeData? get currentUnifiedEvent => reports.firstOrNull;
  @override
  void setMobileCameraInfoFocus(UnifiedQuakeData? event) {
    focus = event;
    super.setMobileCameraInfoFocus(event);
  }

  void show(UnifiedQuakeData event) {
    reports.add(event.copyWith(arrivedAt: DateTime.now()));
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'EEW yields to visible information and returns after the hold',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'weather_alarm_local_only': false,
        'api_source_nied_monitor_enabled': false,
        'api_source_nied_lpgm_enabled': false,
        'api_source_kma_pews_enabled': false,
        'api_source_palert_enabled': false,
        'api_source_wolfx_seisjs_enabled': false,
        'api_source_snet_enabled': false,
        'trem_station_enabled': false,
      });
      final cache = Directory('tmp/eew_info_focus_20261029/widget-cache')
        ..createSync(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => cache.absolute.path,
          );
      QuakeMapView.niedMonitorEnabledNotifier.value = false;
      QuakeMapView.niedLpgmEnabledNotifier.value = false;
      QuakeMapView.kmaPewsEnabledNotifier.value = false;
      QuakeMapView.pAlertEnabledNotifier.value = false;
      QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
      QuakeMapView.snetEnabledNotifier.value = false;
      QuakeMapView.tremStationEnabledNotifier.value = false;
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/catalog_20260917/jian_all.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map;
      final eew = QuakeEventAdapter.convertJian(
        'jma-eew',
        Map<String, dynamic>.from(raw['source：jma-eew']['Data'] as Map),
      )!;
      final info = QuakeEventAdapter.convertJian(
        'jma',
        Map<String, dynamic>.from(raw['source：jma']['Data'] as Map),
      )!;
      final before = jsonEncode([eew.sourcePayload, info.sourcePayload]);
      final replayEew = eew.copyWith(
        replaySessionId: 'original-camera-regression',
        replayClockOffset: DateTime.now().toUtc().difference(
          QuakeTime.unifiedInstantUtc(eew),
        ),
      );
      tester.view.physicalSize = const Size(1584, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = _MapReports();
      final map = MapStateProvider();
      final controller = MapController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
        map.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: map),
          ],
          child: MaterialApp(
            home: Scaffold(body: QuakeMapView(mapController: controller)),
          ),
        ),
      );
      map.setController(controller, const TestVSync());
      await tester.pump(const Duration(milliseconds: 50));
      provider.show(replayEew);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1400)),
      );
      await tester.pump();
      final context = tester.element(find.byType(QuakeMapView));
      expect(
        tester
            .widget<NiedIntensityLayer>(find.byType(NiedIntensityLayer))
            .informationFocusDotsOnly,
        false,
      );
      expect(
        map.isPointInEventViewport(
          LatLng(info.lat!, info.lng!),
          padding: cencIrViewportPadding(context)!,
        ),
        true,
      );
      provider.show(info);
      await tester.pump();
      await tester.pump();
      // The NIED style follows the fill layer's post-frame geometry publication.
      await tester.pump();
      await tester.pump();
      expect(provider.focus?.isEew, false);
      expect(provider.focus?.eventId, info.eventId);
      expect(
        tester
            .widget<NiedIntensityLayer>(find.byType(NiedIntensityLayer))
            .informationFocusDotsOnly,
        true,
      );
      expect(
        tester
            .widgetList<IntensityFillLayer>(find.byType(IntensityFillLayer))
            .where((layer) => layer.source == 'jp')
            .single
            .hypoLng,
        info.lng,
      );
      await tester.pump(const Duration(milliseconds: 6600));
      await tester.pump();
      expect(provider.focus?.isEew, true);
      expect(
        tester
            .widget<NiedIntensityLayer>(find.byType(NiedIntensityLayer))
            .informationFocusDotsOnly,
        false,
      );
      expect(
        tester
            .widgetList<IntensityFillLayer>(find.byType(IntensityFillLayer))
            .where((layer) => layer.source == 'jp')
            .single
            .hypoLng,
        eew.lng,
      );
      final irRaw =
          jsonDecode(
                File(
                  'test/fixtures/cenc_ir_mojiang_20260914170727.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      final irData = CencIrData.fromNowQuakeJson(irRaw);
      final irEvent = NowQuakeCencIntensityService.unifiedInfoFromJson(irRaw)!;
      provider.details = irData;
      provider.show(irEvent);
      await tester.pump();
      await tester.pump();
      expect(provider.focus?.eventId, irEvent.eventId);
      expect(
        tester
            .widgetList<IntensityFillLayer>(find.byType(IntensityFillLayer))
            .where((layer) => layer.source == 'cn')
            .single
            .hypoLat,
        irData.epiLat,
      );
      Future<void> expectCencCentered(String entry) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1400)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        final size = tester.view.physicalSize;
        final padding =
            cencIrViewportPadding(context) ?? const EdgeInsets.all(50);
        final center = padding.deflateRect(Offset.zero & size).center;
        final pixel = controller.camera.latLngToScreenOffset(
          LatLng(irData.epiLat, irData.epiLon),
        );
        debugPrint(
          'CENC_ENTRY $entry size=$size errorPx=${(pixel - center).distance}',
        );
        expect((pixel - center).distance, lessThan(1), reason: entry);
      }

      await expectCencCentered('EEW temporary information');
      expect(
        tester
            .widget<NiedIntensityLayer>(find.byType(NiedIntensityLayer))
            .informationFocusDotsOnly,
        false,
      );
      provider.reports.clear();
      provider.show(irEvent);
      await tester.pump();
      await tester.pump();
      await expectCencCentered('desktop information');

      map.selectHistoryEvent(provider.unifiedToQuakeMessageForTest(irEvent));
      await tester.pump();
      await tester.pump();
      await expectCencCentered('desktop history');
      expect(map.isHistoryEventSelected, true);
      map.clearSelectedHistoryEvent();

      tester.view.physicalSize = const Size(430, 900);
      await tester.pump();
      map.pauseAutoZoom();
      map.resumeAutoZoom();
      await tester.pump();
      await tester.pump();
      await expectCencCentered('phone information');
      expect(jsonEncode([eew.sourcePayload, info.sourcePayload]), before);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
