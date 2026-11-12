import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/mobile_weather_layers.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/location_service.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';
import 'package:flutterrhythmquake/services/weather_playback_controller.dart';
import 'package:flutterrhythmquake/widgets/ui/desktop_weather_home.dart';
import 'package:flutterrhythmquake/widgets/ui/weather_status_entry.dart';
import 'package:flutterrhythmquake/widgets/ui/top_status_bar.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_home_details.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_home.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_map.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await loadUnifiedUiFonts();
    await (FontLoader('JetBrainsMono')..addFont(
          File(
            'assets/fonts/JetBrainsMono-Variable.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  final rawCurrent = File(
    'test/fixtures/china_weather_hourly/yiwu_current.js',
  ).readAsStringSync(encoding: utf8);
  final rawForecast = File(
    'test/fixtures/china_weather_hourly/yiwu_outlook.js',
  ).readAsStringSync(encoding: utf8);
  final current = parseChinaWeatherCurrent(rawCurrent, '101210904');
  final outlook = parseChinaWeatherOutlook(rawForecast);
  final now = outlook.days.first.date.add(const Duration(hours: 4));
  final state = ChinaWeatherHourlyState(
    areaId: '101210904',
    areaName: '义乌',
    current: current,
    hours: parseChinaWeatherHours(rawForecast),
    outlook: outlook,
  );

  Future<void> save(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('desktop-weather-capture')),
      );
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('tmp/desktop_weather_20261106')
          ..createSync(recursive: true);
        File(
          '${dir.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  for (final size in [const Size(800, 650), const Size(1600, 900)]) {
    testWidgets(
      'top bar puts original current weather immediately after location at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LocationService().setCurrentLatLng(29.356, 120.1692);
        var clicked = 0;
        final before = jsonEncode(current.raw);
        await tester.pumpWidget(
          MaterialApp(
            theme: unifiedUiTestTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const ValueKey('desktop-weather-capture'),
                  child: TopStatusBar(
                    weatherEntry: WeatherStatusEntry(
                      state: state,
                      onPressed: () => clicked++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final entry = find.byKey(const ValueKey('desktop-weather-entry'));
        final location = find.textContaining('终端位置:');
        expect(
          tester.getTopLeft(entry).dx,
          greaterThan(tester.getTopRight(location).dx),
        );
        expect(
          tester.getTopLeft(entry).dx - tester.getTopRight(location).dx,
          lessThan(28),
        );
        expect(
          find.text(
            '${current.weather} ${double.parse(current.raw['temp'].toString()).toStringAsFixed(0)}℃',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
        await tester.tap(entry);
        expect(clicked, 1);
        expect(jsonEncode(current.raw), before);
        expect(tester.takeException(), isNull);
        if (size.width == 1600) await save(tester, 'top-weather-entry');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final (size, textScale) in [
    (const Size(1600, 900), 1.0),
    (const Size(900, 700), 1.25),
  ]) {
    testWidgets(
      'desktop home fits real observations and wide/narrow layout $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var back = 0, map = 0, settings = 0;
        final before = jsonEncode([
          current.raw,
          [for (final day in outlook.days) day.raw],
        ]);
        await tester.pumpWidget(
          MaterialApp(
            theme: unifiedUiTestTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('desktop-weather-capture'),
                  child: DesktopWeatherHome(
                    state: state,
                    now: now,
                    station: const Text('气象站实况暂不可用'),
                    advice: MobileWeatherAdvice(state: state, now: now),
                    details: MobileWeatherHomeDetails(
                      state: state,
                      now: now,
                      showTopDivider: false,
                    ),
                    sourceText: '数据来源：中国天气网、中国气象局、FAN Studio',
                    onBack: () => back++,
                    onMap: () => map++,
                    onLocate: () {},
                    onLayers: () => settings++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final image = tester.widget<Image>(
            find.byKey(const ValueKey('weather-background-clear_day')),
          );
          await precacheImage(
            image.image,
            tester.element(find.byType(DesktopWeatherHome)),
          );
        });
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('desktop-weather-columns')),
          size.width >= 1000 ? findsOneWidget : findsNothing,
        );
        expect(find.text(current.cityName), findsOneWidget);
        expect(find.text('逐小时预报'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile-section-weather')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('weather-home-open-map')));
        await tester.tap(find.byKey(const ValueKey('desktop-weather-back')));
        await tester.tap(find.byTooltip('气象图层与预警设置'));
        expect([map, back, settings], [1, 1, 1]);
        await tester.pumpAndSettle();
        if (size.width == 1600) await save(tester, 'desktop-weather-home');
        expect(
          jsonEncode([
            current.raw,
            [for (final day in outlook.days) day.raw],
          ]),
          before,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'desktop workspace retains one map, independent views/layers, seismic camera lock',
    (tester) async {
      final controller = MapController();
      final map = MapStateProvider();
      final mapKey = GlobalKey();
      var active = false, showMap = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return DesktopWeatherWorkspace(
                  active: active,
                  mapVisible: showMap,
                  weather: const ColoredBox(color: Colors.blue),
                  map: FlutterMap(
                    key: mapKey,
                    mapController: controller,
                    options: const MapOptions(
                      initialCenter: LatLng(36, 140),
                      initialZoom: 7,
                    ),
                    children: const [],
                  ),
                );
              },
            ),
          ),
        ),
      );
      map.setController(controller, const TestVSync());
      map.setOverlayEnabled('radarChinaLayer', true);
      final global = Map.of(map.overlayEnabledMap);
      map.pauseAutoZoom(resumeAfter: const Duration(hours: 1));
      final element = mapKey.currentContext;
      for (var i = 0; i < 3; i++) {
        map.configureMobileViewport(
          enabled: true,
          viewport: MapViewport.weather,
          visible: true,
        );
        update(() {
          active = true;
          showMap = false;
        });
        await tester.pump();
        expect(TickerMode.valuesOf(mapKey.currentContext!).enabled, isFalse);
        expect(mapKey.currentContext, same(element));
        map.restoreMobileWeatherLayers({
          'radarChinaLayer': false,
          'nsmcSatelliteCloudLayer': true,
        });
        update(() => showMap = true);
        await tester.pump();
        controller.move(const LatLng(29, 120), 9);
        map.smartMoveToCenter(
          const LatLng(45, 145),
          zoom: 5,
          force: true,
          respectAutoZoom: false,
        );
        expect(controller.camera.center, const LatLng(29, 120));
        expect(map.isOverlayEnabled('radarChinaLayer'), isFalse);
        expect(map.isOverlayEnabled('nsmcSatelliteCloudLayer'), isTrue);
        map.configureMobileViewport(
          enabled: false,
          viewport: MapViewport.seismic,
          visible: true,
        );
        update(() => active = false);
        await tester.pump();
        expect(controller.camera.center, const LatLng(36, 140));
        expect(controller.camera.zoom, 7);
        expect(map.cameraMode, MapCameraMode.manualLocked);
        expect(map.overlayEnabledMap, global);
        expect(mapKey.currentContext, same(element));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      map.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'desktop weather map keeps playback narrow and exposes both return actions',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        mobileWeatherPreferenceKey: jsonEncode({'radarChinaLayer': true}),
      });
      final map = MapStateProvider();
      final provider = QuakeProvider(startCatalogServices: false);
      final playback = WeatherPlaybackController(autoPrepare: false);
      final times = ValueNotifier<Map<String, DateTime?>>(const {});
      var home = 0, close = 0;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: map),
            ChangeNotifierProvider.value(value: provider),
          ],
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: Scaffold(
              body: MobileWeatherMap(
                desktop: true,
                playback: playback,
                onBack: () => home++,
                onClose: () => close++,
                onLocate: () {},
                station: const Text('气象站实况暂不可用'),
                frameTimes: times,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('weather-map-back')));
      await tester.tap(find.byKey(const ValueKey('desktop-weather-map-close')));
      expect([home, close], [1, 1]);
      await tester.tap(find.byKey(const ValueKey('weather-map-layers')));
      await tester.pumpAndSettle();
      expect(find.text('气象地图独立保存，可单独显示或叠加'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(WeatherGlassCard),
              ),
            )
            .width,
        lessThanOrEqualTo(680),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(playback.source, isNull);
      playback.dispose();
      provider.dispose();
      map.dispose();
      times.dispose();
    },
  );
}
