import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';
import 'package:flutterrhythmquake/widgets/ui/china_weather_hourly_panel.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_home_details.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_weather_panel.dart';

void main() {
  final outlook = parseChinaWeatherOutlook(
    File(
      'test/fixtures/china_weather_hourly/yiwu_outlook.js',
    ).readAsStringSync(),
  );
  final current = parseChinaWeatherCurrent(
    File(
      'test/fixtures/china_weather_hourly/yiwu_current.js',
    ).readAsStringSync(),
    '101210904',
  );
  final now = outlook.days.first.date.add(const Duration(hours: 4));
  final state = ChinaWeatherHourlyState(
    areaId: '101210904',
    areaName: '义乌',
    outlook: outlook,
    current: current,
  );
  testWidgets('restored panel offset does not become index expansion state', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Future<void> show({required bool loaded}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: SingleChildScrollView(
              key: const PageStorageKey('mobile-weather-content'),
              controller: scroll,
              child: loaded
                  ? Column(
                      children: [
                        ChinaWeatherHourlyPanel(
                          state: ChinaWeatherHourlyState(
                            hours: parseChinaWeatherHours(
                              File(
                                'test/fixtures/china_weather_hourly/yiwu_outlook.js',
                              ).readAsStringSync(),
                            ),
                          ),
                          now: now,
                          showChart: true,
                          showSource: false,
                        ),
                        MobileWeatherHomeDetails(state: state, now: now),
                      ],
                    )
                  : const SizedBox(height: 3000),
            ),
          ),
        ),
      ),
    );
    await show(loaded: false);
    scroll.jumpTo(420);
    await tester.pumpAndSettle();
    await show(loaded: true);
    expect(tester.takeException(), isNull);
    ScrollPosition horizontalPosition(String key) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(PageStorageKey(key)),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(horizontalPosition('weather-home-daily-scroll').pixels, 0);
    expect(horizontalPosition('weather-hourly-chart-scroll').pixels, 0);
    horizontalPosition('weather-home-daily-scroll').jumpTo(188);
    horizontalPosition('weather-hourly-chart-scroll').jumpTo(270);
    await tester.pumpAndSettle();
    expect(scroll.offset, 420);
    await tester.ensureVisible(
      find.byKey(const PageStorageKey('weather-index-ct')),
    );
    await tester.tap(find.byKey(const PageStorageKey('weather-index-ct')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final verticalOffset = scroll.offset;
    await tester.pumpWidget(const SizedBox());
    await show(loaded: true);
    expect(tester.takeException(), isNull);
    expect(scroll.offset, verticalOffset);
    expect(horizontalPosition('weather-home-daily-scroll').pixels, 188);
    expect(horizontalPosition('weather-hourly-chart-scroll').pixels, 270);
    expect(
      find.text(outlook.indices.firstWhere((i) => i.code == 'ct').description),
      findsOneWidget,
    );
    expect(
      find.text(outlook.indices.firstWhere((i) => i.code == 'fs').description),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final (width, scale) in [(320.0, 1.0), (390.0, 1.0), (320.0, 1.5)]) {
    testWidgets('home sections fit width $width and text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    children: [
                      MobileWeatherConditions(state: state, now: now),
                      MobileWeatherAdvice(state: state, now: now),
                      MobileWeatherHomeDetails(state: state, now: now),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('22～31℃'), findsOneWidget);
      expect(find.text('每日预报'), findsOneWidget);
      expect(find.text('日出 05:40'), findsOneWidget);
      expect(find.text('日落 18:15'), findsOneWidget);
      expect(find.text('气象实况'), findsOneWidget);
      expect(find.text('空气质量'), findsOneWidget);
      expect(find.text('生活指数'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const PageStorageKey('weather-index-ct')),
      );
      await tester.tap(find.byKey(const PageStorageKey('weather-index-ct')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          outlook.indices.firstWhere((i) => i.code == 'ct').description,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing data does not fabricate a quality grade or sunrise', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MobileWeatherHomeDetails(state: ChinaWeatherHourlyState()),
          ),
        ),
      ),
    );
    expect(find.text('AQI —'), findsOneWidget);
    expect(find.text('日出 —'), findsOneWidget);
    expect(find.text('暂无当日生活指数'), findsOneWidget);
    expect(find.textContaining('PM2.5'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
