import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_sections.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_home.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_home_details.dart';
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
  final currentRaw = File(
    'test/fixtures/china_weather_hourly/yiwu_current.js',
  ).readAsStringSync();
  final forecastRaw = File(
    'test/fixtures/china_weather_hourly/yiwu_outlook.js',
  ).readAsStringSync();
  final current = parseChinaWeatherCurrent(currentRaw, '101210904');
  final outlook = parseChinaWeatherOutlook(forecastRaw);
  final now = outlook.days.first.date.add(const Duration(hours: 4));
  final state = ChinaWeatherHourlyState(
    areaId: '101210904',
    areaName: '义乌',
    current: current,
    hours: parseChinaWeatherHours(forecastRaw),
    outlook: outlook,
  );

  test(
    'backgrounds follow current weather codes, missing and unknown stay neutral',
    () {
      for (final entry in {
        'd00': 'clear_day',
        'n00': 'clear_night',
        'd01': 'cloudy_day',
        'n02': 'cloudy_night',
        'd07': 'rain',
        'n08': 'rain',
        'd04': 'storm',
        'n05': 'storm',
        'd14': 'snow',
        'n17': 'snow',
        'd18': 'fog',
        'd53': 'fog',
      }.entries) {
        expect(mobileWeatherBackground(entry.key), entry.value);
        expect(
          File('assets/images/weather/${entry.value}.png').existsSync(),
          isTrue,
        );
      }
      for (final missing in ['', 'unknown', 'd99']) {
        expect(mobileWeatherBackground(missing), isNull);
      }
    },
  );

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(430, 932), 1.5),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'weather home fits $size at $scale and map reuses mounted instance',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = QuakeProvider();
        var opened = false;
        var located = 0;
        var layers = 0;
        final rawBefore = jsonEncode(current.raw);
        final mapKey = GlobalKey();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              theme: unifiedUiTestTheme(),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, update) => MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(
                      key: const ValueKey('weather-home-render'),
                      child: MobileSectionHost(
                        seismic: SizedBox.expand(
                          key: mapKey,
                          child: const ColoredBox(
                            color: Colors.black,
                            child: Text('map-probe'),
                          ),
                        ),
                        weatherMapVisible: opened,
                        onWeatherMapBack: () => update(() => opened = false),
                        onSectionChanged: (_) => update(() => opened = false),
                        settingsBuilder: (_) => const Text('settings'),
                        weather: MobileWeatherHome(
                          state: state,
                          now: now,
                          mapVisible: opened,
                          onMap: () => update(() => opened = !opened),
                          onLayers: () => layers++,
                          onLocate: () => located++,
                          advice: MobileWeatherAdvice(state: state, now: now),
                          details: MobileWeatherHomeDetails(
                            state: state,
                            now: now,
                          ),
                          station: const Text('气象站实况暂不可用'),
                          sourceText: '数据来源：中国天气网、中国气象局、FAN Studio',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final mapElement = mapKey.currentContext;
        await tester.tap(find.byKey(const ValueKey('mobile-section-weather')));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            tester
                .widget<Image>(
                  find.byKey(const ValueKey('weather-background-clear_day')),
                )
                .image,
            tester.element(find.byType(MobileWeatherHome)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('map-probe'), findsNothing);
        expect(mapKey.currentContext, same(mapElement));
        expect(TickerMode.valuesOf(mapKey.currentContext!).enabled, isFalse);
        expect(
          find.byKey(const ValueKey('weather-background-clear_day')),
          findsOneWidget,
        );
        expect(find.text('30°'), findsWidgets);
        expect(find.text('义乌'), findsOneWidget);
        expect(find.byKey(const ValueKey('mobile-weather-grip')), findsNothing);
        if (size.width == 390) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('weather-home-render')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'tmp/mobile_weather_home_20261105/weather-home.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.tap(
          find.byKey(const ValueKey('mobile-weather-map-entry')),
        );
        await tester.pumpAndSettle();
        expect(opened, isTrue);
        expect(find.byKey(const ValueKey('mobile-section-weather')), findsNothing);
        expect(find.text('map-probe'), findsOneWidget);
        expect(mapKey.currentContext, same(mapElement));
        expect(TickerMode.valuesOf(mapKey.currentContext!).enabled, isTrue);
        await tester.tap(find.byTooltip('气象图层与预警设置'));
        await tester.tap(find.byTooltip('回到所在地'));
        expect(layers, 1);
        expect(located, 1);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(opened, isFalse);
        expect(find.byKey(const ValueKey('mobile-section-weather')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('weather-home-temperature')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('mobile-weather-source')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mobile-weather-source')).hitTestable(),
          findsOneWidget,
        );
        final scrollable = find
            .descendant(
              of: find.byKey(
                const PageStorageKey('mobile-weather-home-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        final previousOffset = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;
        expect(
          find.byKey(const ValueKey('mobile-weather-map-entry')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('mobile-weather-map-entry')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('weather-map-back')));
        await tester.pumpAndSettle();
        expect(
          tester.state<ScrollableState>(scrollable).position.pixels,
          closeTo(previousOffset, 1),
        );
        expect(tester.takeException(), isNull);
        expect(jsonEncode(current.raw), rawBefore);
        expect(
          File(
            'test/fixtures/china_weather_hourly/yiwu_current.js',
          ).readAsStringSync(),
          currentRaw,
        );
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      },
    );
  }

  testWidgets(
    'missing weather does not fabricate a sunny background or temperature',
    (tester) async {
      final provider = QuakeProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: MobileWeatherHome(
                state: const ChinaWeatherHourlyState(),
                station: const Text('等待定位信息'),
                onMap: () {},
                onLayers: () {},
                onLocate: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('—°'), findsOneWidget);
      expect(find.text('天气状况暂不可用'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
