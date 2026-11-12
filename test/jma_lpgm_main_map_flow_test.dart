import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_region_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/jma_lpgm_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jma_lpgm_display_flow_test.dart'
    show originalBulletin, originalInformation, longPeriodEvent;
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual main map switches native-linked LPGM fill and restores', (
    tester,
  ) async {
    final out = Directory('tmp/jma_lpgm_display_20261110')
      ..createSync(recursive: true);
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
    QuakeMapView.niedMonitorEnabledNotifier.value = false;
    QuakeMapView.niedLpgmEnabledNotifier.value = false;
    QuakeMapView.kmaPewsEnabledNotifier.value = false;
    QuakeMapView.pAlertEnabledNotifier.value = false;
    QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
    QuakeMapView.snetEnabledNotifier.value = false;
    QuakeMapView.tremStationEnabledNotifier.value = false;
    SoundEffectService().enabled = false;
    TtsService().enabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => out.absolute.path,
        );
    final ntp = NtpService();
    final oldClock = (ntp.deviceOffset, ntp.lastSyncedAt, ntp.isSynced);
    final b = originalBulletin();
    // Set the external source clock; never rewrite the archived report.
    final observationTime = b.reportTime!.add(const Duration(seconds: 1));
    ntp.restoreClockSample(
      observationTime.difference(DateTime.now()).inMilliseconds,
      DateTime.now(),
      true,
    );
    final provider = QuakeProvider(
      startCatalogServices: false,
      nativeUnifiedEvents: true,
    );
    final state = MapStateProvider()..setTileKey('kaVector');
    final controller = MapController();
    final boundary = GlobalKey();
    tester.view.physicalSize = const Size(1584, 900);
    tester.view.devicePixelRatio = 1;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 70)),
        );
        await tester.pump(const Duration(milliseconds: 70));
      }
    }

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${out.path}/main-$name.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    try {
      await tester.runAsync(() async {
        await provider.eewHistoryReadyForTest;
        await loadUnifiedUiFonts();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: state),
          ],
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: QuakeMapView(mapController: controller),
              ),
            ),
          ),
        ),
      );
      state.setController(controller, const TestVSync());
      final normal = originalInformation();
      provider.handleUnifiedEventForTest(normal, suppressEffects: true);
      await settle();
      expect(provider.unifiedEvents, hasLength(1));
      expect(find.byType(IntensityFillLayer), findsOneWidget);
      provider.handleUnifiedEventForTest(
        longPeriodEvent(b),
        suppressEffects: true,
      );
      await settle();
      expect(provider.unifiedEvents, hasLength(1));
      final active = provider.unifiedEvents.single;
      expect(provider.showJmaLpgmRegionsFor(active), true);
      expect(provider.associatedJmaInformationFor(active).jmaLpgmBulletin, b);
      expect(find.byType(JmaLpgmRegionFillLayer), findsOneWidget);
      expect(find.byType(IntensityFillLayer), findsNothing);
      expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
      expect(
        tester
            .widget<MarkerLayer>(
              find.descendant(
                of: find.byType(JmaLpgmStationLayer),
                matching: find.byType(MarkerLayer),
              ),
            )
            .markers,
        hasLength(4),
      );
      await capture('combined');
      await tester.pump(const Duration(seconds: 16));
      await settle();
      expect(provider.showJmaLpgmRegionsFor(active), false);
      expect(find.byType(JmaLpgmRegionFillLayer), findsNothing);
      expect(find.byType(IntensityFillLayer), findsOneWidget);
      expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
      await capture('restored');
      provider.dismissUnifiedEventForTest(active);
      await settle();
      expect(provider.unifiedEvents.single.isJmaLpgm, true);
      expect(find.byType(JmaLpgmRegionFillLayer), findsOneWidget);
      expect(find.byType(JmaLpgmStationLayer), findsOneWidget);
      await capture('standalone');
      provider.clearJmaLpgm(b.eventId);
      await settle();
      expect(provider.unifiedEvents, isEmpty);
      expect(find.byType(JmaLpgmRegionFillLayer), findsNothing);
      expect(find.byType(JmaLpgmStationLayer), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      state.dispose();
      ntp.restoreClockSample(oldClock.$1, oldClock.$2, oldClock.$3);
      SoundEffectService().enabled = true;
      TtsService().enabled = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
