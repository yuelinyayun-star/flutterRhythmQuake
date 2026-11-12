import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/notification_settings_provider.dart';
import 'package:flutterrhythmquake/providers/background_settings_provider.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/screens/main_screen.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';
import 'package:flutterrhythmquake/widgets/ui/desktop_weather_home.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_map.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual MainScreen top entry to desktop home/map and back retains controller, camera and seismic flags',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final dir = Directory('tmp/desktop_weather_20261106/widget-cache')
        ..createSync(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.absolute.path,
          );
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      final map = MapStateProvider()..setTileKey(MapConfig.vectorBasemapKey);
      final notification = NotificationSettingsProvider();
      final background = BackgroundSettingsProvider();
      final pageBackground = PageBackgroundProvider();
      await tester.runAsync(() async {
        await provider.eewHistoryReadyForTest;
        await loadUnifiedUiFonts();
        await VectorBasemapService.instance.load();
        await AppPageBackground.cachedBytes();
      });
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      var disposed = false;
      Future<void> cleanup() async {
        if (disposed) return;
        disposed = true;
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        map.dispose();
        notification.dispose();
        background.dispose();
        pageBackground.dispose();
      }

      addTearDown(cleanup);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: map),
            ChangeNotifierProvider.value(value: notification),
            ChangeNotifierProvider.value(value: background),
            ChangeNotifierProvider.value(value: pageBackground),
          ],
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: const MainScreen(),
          ),
        ),
      );
      await settle();
      expect(tester.takeException(), isNull);
      final mapElement = tester.element(find.byType(QuakeMapView));
      final mapWidget = tester.widget<QuakeMapView>(find.byType(QuakeMapView));
      final controller = mapWidget.mapController;
      controller.move(const LatLng(36, 140), 7);
      map.pauseAutoZoom(resumeAfter: const Duration(hours: 1));
      final global = Map.of(map.overlayEnabledMap);
      await tester.tap(find.byKey(const ValueKey('desktop-weather-entry')));
      await settle();
      expect(find.byType(DesktopWeatherHome), findsOneWidget);
      expect(
        tester.element(find.byType(QuakeMapView, skipOffstage: false)),
        same(mapElement),
      );
      expect(TickerMode.valuesOf(mapElement).enabled, isFalse);
      expect(map.isSeismicViewportVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('weather-home-open-map')));
      await settle();
      expect(find.byType(MobileWeatherMap), findsOneWidget);
      expect(
        tester.widget<QuakeMapView>(find.byType(QuakeMapView)).weatherOnly,
        isTrue,
      );
      expect(
        tester.widget<QuakeMapView>(find.byType(QuakeMapView)).mapController,
        same(controller),
      );
      controller.move(const LatLng(29, 120), 9);
      await tester.tap(find.byKey(const ValueKey('weather-map-back')));
      await settle();
      expect(find.byType(DesktopWeatherHome), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-weather-back')));
      await settle();
      expect(
        find.byKey(const ValueKey('desktop-weather-entry')),
        findsOneWidget,
      );
      expect(tester.element(find.byType(QuakeMapView)), same(mapElement));
      expect(controller.camera.center.latitude, closeTo(36, 1e-8));
      expect(controller.camera.center.longitude, closeTo(140, 1e-8));
      expect(controller.camera.zoom, closeTo(7, 1e-8));
      expect(map.cameraMode, MapCameraMode.manualLocked);
      expect(map.overlayEnabledMap, global);
      expect(tester.takeException(), isNull);
      await cleanup();
    },
  );
}
