import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';
import 'package:flutterrhythmquake/widgets/ui/china_weather_hourly_panel.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_sections.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_panel.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_home_details.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hours = parseChinaWeatherHours(
    File('test/fixtures/china_weather_hourly/beijing.js').readAsStringSync(),
  );
  final currentWeather = parseChinaWeatherCurrent(
    File(
      'test/fixtures/china_weather_hourly/yiwu_current.js',
    ).readAsStringSync(),
    '101210904',
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final (name, path) in [
      ('WeatherTest', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'D:/flutter_windows_3.41.1-stable/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        await (FontLoader(name)..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())),
            ))
            .load();
      }
    }
  });

  testWidgets('condition updates clear old weather and distinguish loading', (
    tester,
  ) async {
    Future<void> show(ChinaWeatherHourlyState state) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileWeatherConditions(state: state)),
      ),
    );
    await show(ChinaWeatherHourlyState(current: currentWeather));
    expect(find.text(currentWeather.weather), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    await show(const ChinaWeatherHourlyState(currentLoading: true));
    expect(find.text(currentWeather.weather), findsNothing);
    expect(find.text('正在获取天气状况…'), findsOneWidget);
    await show(const ChinaWeatherHourlyState());
    expect(find.text('天气状况暂不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-current-weather')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile weather credits appear only once after the station', (
    tester,
  ) async {
    final provider = QuakeProvider();
    final source = File(
      'test/fixtures/china_weather_hourly/yiwu_outlook.js',
    ).readAsStringSync();
    final outlook = parseChinaWeatherOutlook(source);
    final now = outlook.days.first.date.add(const Duration(hours: 4));
    final state = ChinaWeatherHourlyState(
      current: currentWeather,
      outlook: outlook,
      hours: parseChinaWeatherHours(source),
      areaName: '义乌',
      areaId: '101210904',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: MobileWeatherPanel(
              onLayers: () {},
              onLocate: () {},
              conditions: MobileWeatherConditions(state: state, now: now),
              forecast: ChinaWeatherHourlyPanel(
                state: state,
                now: now,
                showChart: true,
                showSource: false,
              ),
              details: MobileWeatherHomeDetails(state: state, now: now),
              station: const Text('气象站内容'),
              sourceText: '数据来源：中国天气网、中国气象局、FAN Studio',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('中国天气网'), findsOneWidget);
    expect(find.textContaining('中国气象局'), findsOneWidget);
    expect(find.textContaining('FAN Studio'), findsOneWidget);
    expect(find.textContaining('CMA'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mobile-weather-source'))).dy,
      greaterThan(tester.getBottomLeft(find.text('气象站内容')).dy),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('mobile-weather-source')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-weather-source')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChinaWeatherHourlyPanel(state: state, now: now),
        ),
      ),
    );
    expect(find.text('中国天气网 · 义乌'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  for (final (size, textScale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(430, 932), 1.5),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'weather panel fits $size / $textScale and leaves map interactive',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = QuakeProvider();
        var taps = 0;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'WeatherTest'),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: const ValueKey('weather-preview'),
                    child: MobileSectionHost(
                      seismic: GestureDetector(
                        onTap: () => taps++,
                        child: const ColoredBox(color: Color(0xFF607C73)),
                      ),
                      settingsBuilder: (_) => const Text('Settings'),
                      weather: MobileWeatherPanel(
                        onLayers: () {},
                        onLocate: () {},
                        conditions: MobileWeatherConditions(
                          state: ChinaWeatherHourlyState(
                            current: currentWeather,
                          ),
                        ),
                        forecast: ChinaWeatherHourlyPanel(
                          showChart: true,
                          state: ChinaWeatherHourlyState(
                            areaId: '101010100',
                            areaName: '北京',
                            hours: hours,
                          ),
                          now: hours.first.time,
                        ),
                        station: const Text(
                          '气象站内容',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('mobile-section-weather')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(currentWeather.weather), findsWidgets);
        expect(
          find.byKey(const ValueKey('mobile-current-weather')),
          findsOneWidget,
        );
        await tester.tapAt(const Offset(140, 120));
        expect(taps, 1);
        final grip = find.byKey(const ValueKey('mobile-weather-grip'));
        final frame = find.byKey(const ValueKey('mobile-weather-panel'));
        final initial = tester.getSize(frame).height;
        await tester.drag(grip, const Offset(0, -400));
        await tester.pump();
        expect(tester.getSize(frame).height, greaterThan(initial));
        expect(tester.getTopLeft(frame).dy, greaterThanOrEqualTo(74));
        final scroll = find.byKey(
          const PageStorageKey('mobile-weather-content'),
        );
        await tester.drag(scroll, const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(find.text('气象站内容').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size.width == 390) {
          await tester.drag(scroll, const Offset(0, 1000));
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('weather-preview')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('tmp/mobile_ui_review/mobile-weather.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      },
    );
  }

  testWidgets(
    'weather shortcut reuses live settings and persists original keys',
    (tester) async {
      final map = MapStateProvider();
      final provider = QuakeProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: map),
            ChangeNotifierProvider.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SettingsPage(weatherOnly: true)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('实况云图'), findsOneWidget);
      expect(find.text('JMA 火山'), findsNothing);
      expect(find.text('中国等高线'), findsNothing);
      expect(find.text('中国断层'), findsNothing);
      expect(find.text('日本断层'), findsNothing);
      expect(find.text('应用设置'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, false);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(map.isOverlayEnabled('cloudLayer'), true);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'map_overlay_cloudLayer',
        ),
        true,
      );
      map.setOverlayEnabled('cloudLayer', false);
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      map.dispose();
      provider.dispose();
    },
  );
}
