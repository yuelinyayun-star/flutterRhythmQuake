import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/mobile_weather_layers.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/weather_map_source_requests.dart';
import 'package:flutterrhythmquake/services/native_weather_map_policy.dart';
import 'package:flutterrhythmquake/services/background_source_reload_plan.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_map.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await loadUnifiedUiFonts();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  test(
    'mobile weather switches and station mode cannot change global or seismic layers',
    () {
      final map = MapStateProvider();
      map.setOverlayEnabled('radarChinaLayer', true);
      map.setOverlayEnabled('cnFault', true);
      map.setWeatherStationMode('wind');
      final original = Map<String, bool>.from(map.overlayEnabledMap);
      map.restoreMobileWeatherLayers({
        'radarChinaLayer': false,
        'jmaRadarLayer': true,
      }, stationMode: 'temperature');
      map.configureMobileViewport(
        enabled: true,
        viewport: MapViewport.weather,
        visible: true,
      );
      expect(map.isOverlayEnabled('radarChinaLayer'), isFalse);
      expect(map.isOverlayEnabled('jmaRadarLayer'), isTrue);
      expect(map.isOverlayEnabled('cnFault'), isTrue);
      expect(map.weatherStationMode, 'temperature');
      map.setMobileWeatherLayer('cnFault', false);
      expect(map.isOverlayEnabled('cnFault'), isTrue);
      map.configureMobileViewport(
        enabled: true,
        viewport: MapViewport.seismic,
        visible: true,
      );
      expect(map.isOverlayEnabled('radarChinaLayer'), isTrue);
      expect(map.isOverlayEnabled('jmaRadarLayer'), isFalse);
      expect(map.weatherStationMode, 'wind');
      expect(map.overlayEnabledMap, original);
      map.configureMobileViewport(
        enabled: false,
        viewport: MapViewport.weather,
        visible: true,
      );
      expect(map.isOverlayEnabled('radarChinaLayer'), isTrue);
      expect(map.weatherStationMode, 'wind');
      map.dispose();
    },
  );

  test(
    'native source union preserves global demand and ignores non-weather keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'map_overlay_radarChinaLayer': true,
        'map_overlay_satelliteCloudLayer': true,
        mobileWeatherPreferenceKey: jsonEncode({
          'radarChinaLayer': false,
          'jmaRadarLayer': true,
          'typhoonLayer': true,
          'fdsnEarthScope': true,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      expect(requiredWeatherMapSources(prefs), {
        'radarChinaLayer',
        'satelliteCloudLayer',
        'jmaRadarLayer',
        'typhoonLayer',
      });
      expect(NativeWeatherMapPolicy.requiredSources(1, 0x80000004), 5);
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
      final plan = BackgroundSourceReloadPlan({}, {
        mobileWeatherPreferenceKey: '{}',
        mobileWeatherStationModeKey: 'wind',
      });
      expect(plan.requiresFullReload, isFalse);
      expect(plan.stations, isEmpty);
    },
  );

  test(
    'malformed mobile UI settings cannot disable existing weather feeds',
    () async {
      SharedPreferences.setMockInitialValues({
        'map_overlay_jmaRadarLayer': true,
        mobileWeatherPreferenceKey: 'invalid-json',
      });
      expect(requiredWeatherMapSources(await SharedPreferences.getInstance()), {
        'jmaRadarLayer',
      });
    },
  );

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(430, 932), 1.5),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'weather map controls fit $size/$scale, solo and overlay without changing global settings',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'map_overlay_radarChinaLayer': true,
          'weather_station_mode': 'wind',
        });
        final map = MapStateProvider()
          ..setOverlayEnabled('radarChinaLayer', true);
        map.configureMobileViewport(
          enabled: true,
          viewport: MapViewport.weather,
          visible: true,
        );
        final provider = QuakeProvider(startCatalogServices: false);
        final times = ValueNotifier<Map<String, DateTime?>>(const {
          'radarChinaLayer': null,
          'precipitationChinaLayer': null,
        });
        var back = 0, locate = 0, mapTaps = 0;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: map),
              ChangeNotifierProvider.value(value: provider),
            ],
            child: MaterialApp(
              theme: unifiedUiTestTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTap: () => mapTaps++,
                        child: const ColoredBox(color: Color(0xFF253242)),
                      ),
                      MobileWeatherMap(
                        onBack: () => back++,
                        onLocate: () => locate++,
                        station: const Text('原有气象站组件'),
                        frameTimes: times,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final original = Map<String, bool>.from(map.overlayEnabledMap);
        // Map center remains hit-testable, independently of the floating controls.
        await tester.tapAt(Offset(100, size.height / 2));
        expect(mapTaps, 1);
        await tester.tap(
          find.byKey(
            const ValueKey('weather-map-quick-precipitationChinaLayer'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          map.mobileWeatherLayerEnabled('precipitationChinaLayer'),
          isTrue,
        );
        expect(map.mobileWeatherLayerEnabled('radarChinaLayer'), isFalse);
        expect(map.overlayEnabledMap, original);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('map_overlay_radarChinaLayer'), isTrue);
        expect(prefs.getString('weather_station_mode'), 'wind');
        expect(
          readMobileWeatherLayerValues(
            prefs.getString(mobileWeatherPreferenceKey),
          )['precipitationChinaLayer'],
          isTrue,
        );
        expect(find.text('尚未收到当前图层数据'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('weather-map-layers')));
        await tester.pumpAndSettle();
        final radar = find.byKey(
          const ValueKey('weather-layer-radarChinaLayer'),
        );
        await tester.tap(radar);
        await tester.pumpAndSettle();
        expect(map.mobileWeatherLayerEnabled('radarChinaLayer'), isTrue);
        expect(
          map.mobileWeatherLayerEnabled('precipitationChinaLayer'),
          isTrue,
        );
        expect(map.overlayEnabledMap, original);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('weather-map-information')));
        await tester.pumpAndSettle();
        expect(find.text('原有气象站组件'), findsOneWidget);
        expect(find.text('全国气象预警 · 0条'), findsOneWidget);
        expect(find.textContaining('暂未收到'), findsWidgets);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('回到所在地'));
        expect(locate, 1);
        await tester.tap(find.byKey(const ValueKey('weather-map-back')));
        expect(back, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        times.dispose();
        provider.dispose();
        map.dispose();
      },
    );
  }
}
