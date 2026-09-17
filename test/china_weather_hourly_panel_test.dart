import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';
import 'package:flutterrhythmquake/widgets/ui/china_weather_hourly_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hours = parseChinaWeatherHours(
    File('test/fixtures/china_weather_hourly/beijing.js').readAsStringSync(),
  );
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final bytes = await font.readAsBytes();
      await (FontLoader(
        'WeatherTest',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final icons = File(
      'D:/flutter_windows_3.41.1-stable/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });
  for (final scale in [.55, .75, 1.0]) {
    testWidgets('official hourly columns fit desktop sidebar at $scale', (
      tester,
    ) async {
      const boundaryKey = ValueKey('hourly-preview');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'WeatherTest'),
          home: Scaffold(
            backgroundColor: const Color(0xff777f80),
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: Container(
                  width: 234,
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xbb171d20),
                  child: ChinaWeatherHourlyPanel(
                    state: ChinaWeatherHourlyState(
                      areaId: '101010100',
                      areaName: '北京',
                      hours: hours,
                    ),
                    scale: scale,
                    now: hours.first.time,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('逐小时预报'), findsOneWidget);
      expect(find.text('中国天气网 · 北京'), findsOneWidget);
      final list = find.byKey(const PageStorageKey('weather-hourly-list'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      await tester.tap(find.byTooltip('后一页预报'));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      await tester.tap(find.byTooltip('前一页预报'));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      expect(tester.takeException(), isNull);
      if (scale == 1.0) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('tmp/mobile_ui_review/desktop-hourly-weather.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  testWidgets('long weather name fits at enlarged text size', (tester) async {
    final hour = ChinaWeatherHour(hours.first.time, {
      ...hours.first.raw,
      'ja': '05',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'WeatherTest'),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SizedBox(
              width: 202,
              child: ChinaWeatherHourlyPanel(
                state: ChinaWeatherHourlyState(hours: [hour]),
                now: hour.time,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('雷阵雨伴有冰雹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hourly curve hides scrollbar and remains swipeable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ChinaWeatherHourlyPanel(
              state: ChinaWeatherHourlyState(hours: hours),
              now: hours.first.time,
              showChart: true,
            ),
          ),
        ),
      ),
    );
    final chart = find.byKey(
      const PageStorageKey('weather-hourly-chart-scroll'),
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: chart, matching: find.byType(Scrollable)),
        )
        .position;
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    await tester.drag(chart, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
      expect(find.byTooltip('后一页预报'), findsNothing);
      expect(find.byTooltip('前一页预报'), findsNothing);
      final afterDrag = position.pixels;
      await tester.drag(chart, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, lessThan(afterDrag));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired forecast is not shown as current and large text fits', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SizedBox(
              width: 202,
              child: ChinaWeatherHourlyPanel(
                state: ChinaWeatherHourlyState(hours: hours),
                now: hours.last.time.add(const Duration(hours: 1)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const PageStorageKey('weather-hourly-list')),
      findsNothing,
    );
    expect(find.text('暂无有效逐小时预报'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
