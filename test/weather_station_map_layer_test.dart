import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/cma_local_weather_service.dart';
import 'package:flutterrhythmquake/widgets/map/weather_station_map_layer.dart';
import 'package:latlong2/latlong.dart';

// CMA nationwide station directory row for 59951.
const _wanning = CmaStationSummary(
  id: '59951',
  name: '万宁',
  latitude: 18.8,
  longitude: 110.33,
  temperature: 29,
  weather: '中雨',
  windDirection: '北风',
  windScale: '3~4级',
);

CmaLocalWeatherObservation _wanningObservation() {
  final raw = File(
    'test/fixtures/cma_weather_stations/59951.original.json',
  ).readAsStringSync();
  return cmaObservationFromJson(
    jsonDecode(raw) as Map<String, dynamic>,
    CmaWeatherStation(
      id: _wanning.id,
      name: _wanning.name,
      latitude: _wanning.latitude,
      longitude: _wanning.longitude,
    ),
  )!;
}

void main() {
  test(
    'parses CmaStationSummary rows correctly and determines rain severity',
    () {
      final rows = [
        ['54511', '北京', '中国', 2, 39.9, 116.4, 29.3, '晴', 0, '西南风', '2级'],
        ['58457', '杭州', '中国', 2, 30.2, 120.1, 25.6, '中雨', 8, '东北风', '3~4级'],
        ['59287', '广州', '中国', 2, 23.1, 113.2, 27.0, '暴雨', 10, '南风', '5级'],
        ['57510', '铜梁', '中国', 3, 29.8, 106.0, 31.0, '多云', 1, '微风', '1级'],
        ['K1418', '余杭', '中国', 3, 30.4, 120.3, 24.5, '大暴雨', 11, '东风', '6级'],
      ];

      final summaries = cmaStationSummariesFromRows(rows);
      expect(summaries, hasLength(5));

      final beijing = summaries[0];
      expect(beijing.name, '北京');
      expect(beijing.temperature, 29.3);
      expect(beijing.isRaining, isFalse);
      expect(beijing.rainSeverity, 0);

      final hangzhou = summaries[1];
      expect(hangzhou.name, '杭州');
      expect(hangzhou.isRaining, isTrue);
      expect(hangzhou.rainSeverity, 2);
      expect(hangzhou.rainWithAmountText, '中雨');

      final guangzhou = summaries[2];
      expect(guangzhou.name, '广州');
      expect(guangzhou.isRaining, isTrue);
      expect(guangzhou.rainSeverity, 4);
      expect(guangzhou.rainWithAmountText, '暴雨');

      final yuhang = summaries[4];
      expect(yuhang.id, 'K1418');
      expect(yuhang.name, '余杭');
      expect(yuhang.isRaining, isTrue);
      expect(yuhang.rainSeverity, 5);
      expect(yuhang.rainWithAmountText, '大暴雨');
    },
  );

  test('WeatherStationDisplayMode parses keys and provides display labels', () {
    expect(
      WeatherStationDisplayMode.fromKey('auto'),
      WeatherStationDisplayMode.auto,
    );
    expect(
      WeatherStationDisplayMode.fromKey('rain'),
      WeatherStationDisplayMode.rain,
    );
    expect(
      WeatherStationDisplayMode.fromKey('temperature'),
      WeatherStationDisplayMode.temperature,
    );
    expect(
      WeatherStationDisplayMode.fromKey('wind'),
      WeatherStationDisplayMode.wind,
    );

    expect(WeatherStationDisplayMode.auto.label, '综合(降雨优先)');
    expect(WeatherStationDisplayMode.rain.label, '降水雨量');
    expect(WeatherStationDisplayMode.temperature.label, '气温实况');
    expect(WeatherStationDisplayMode.wind.label, '风向风力');
  });

  test('each mode labels only the selected CMA reading', () {
    final observation = _wanningObservation();
    final expected = {
      WeatherStationDisplayMode.auto: '1.9mm',
      WeatherStationDisplayMode.rain: '1.9mm',
      WeatherStationDisplayMode.temperature: '20.4℃',
      WeatherStationDisplayMode.wind: '3.4m/s',
    };
    for (final entry in expected.entries) {
      expect(
        weatherStationValueLabel(_wanning, observation, entry.key),
        entry.value,
      );
    }
    expect(
      weatherStationValueLabel(_wanning, null, WeatherStationDisplayMode.rain),
      isNull,
    );
    expect(
      weatherStationValueLabel(_wanning, null, WeatherStationDisplayMode.wind),
      '3~4级',
    );
    expect(
      weatherStationValueLabel(
        _wanning,
        null,
        WeatherStationDisplayMode.temperature,
      ),
      '29.0℃',
    );
  });

  testWidgets('the numeric label starts at the province close-up', (
    tester,
  ) async {
    final observations = CmaLocalWeatherService.stationObservationMapNotifier;
    final original = observations.value;
    observations.value = {_wanning.id: _wanningObservation()};
    addTearDown(() => observations.value = original);

    final center = LatLng(_wanning.latitude, _wanning.longitude);
    final controller = MapController();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: RepaintBoundary(
              key: boundary,
              child: FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 5,
                  backgroundColor: Colors.black,
                ),
                children: const [
                  WeatherStationMapLayer(
                    stations: [_wanning],
                    mode: WeatherStationDisplayMode.temperature,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final labelPixelCounts = <int>[];
    const labelZoom = WeatherStationMapLayer.labelMinZoom;
    for (final zoom in [5.0, 7.0, labelZoom - .01, labelZoom, 10.0, 7.0]) {
      controller.move(center, zoom);
      await tester.pump();
      final counts = await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var count = 0;
          for (var y = 88; y < 111; y++) {
            for (var x = 107; x < 174; x++) {
              final i = (y * image.width + x) * 4;
              if (pixels.getUint8(i) > 220 &&
                  pixels.getUint8(i + 1) > 220 &&
                  pixels.getUint8(i + 2) > 220) {
                count++;
              }
            }
          }
          final markerOffset = (100 * image.width + 100) * 4;
          return (label: count, marker: pixels.getUint8(markerOffset));
        } finally {
          image.dispose();
        }
      });
      expect(counts!.marker, greaterThan(0), reason: 'marker missing at $zoom');
      if (zoom < labelZoom) {
        expect(counts.label, 0, reason: 'unexpected label at $zoom');
      } else {
        expect(counts.label, greaterThan(0), reason: 'label missing at $zoom');
        labelPixelCounts.add(counts.label);
      }
    }
    for (final count in labelPixelCounts.skip(1)) {
      expect(
        count,
        closeTo(labelPixelCounts.first, labelPixelCounts.first * .2),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('the station sprite follows mode and observation changes', (
    tester,
  ) async {
    final observations = CmaLocalWeatherService.stationObservationMapNotifier;
    final original = observations.value;
    observations.value = const {};
    addTearDown(() => observations.value = original);

    final mode = ValueNotifier(WeatherStationDisplayMode.rain);
    addTearDown(mode.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            height: 200,
            child: RepaintBoundary(
              key: boundary,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(_wanning.latitude, _wanning.longitude),
                  initialZoom: WeatherStationMapLayer.labelMinZoom,
                  backgroundColor: Colors.black,
                ),
                children: [
                  ValueListenableBuilder(
                    valueListenable: mode,
                    builder: (context, value, _) => WeatherStationMapLayer(
                      stations: const [_wanning],
                      mode: value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Future<List<int>> labelPixels() async {
      await tester.pump();
      return (await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return [
            for (var y = 88; y < 111; y++)
              for (var x = 127; x < 198; x++)
                pixels.getUint32((y * image.width + x) * 4),
          ];
        } finally {
          image.dispose();
        }
      }))!;
    }

    final empty = await labelPixels();
    expect(empty.toSet(), hasLength(1));
    observations.value = {_wanning.id: _wanningObservation()};
    final rain = await labelPixels();
    expect(rain, isNot(orderedEquals(empty)));
    mode.value = WeatherStationDisplayMode.temperature;
    final temperature = await labelPixels();
    expect(temperature, isNot(orderedEquals(rain)));
    mode.value = WeatherStationDisplayMode.wind;
    expect(await labelPixels(), isNot(orderedEquals(temperature)));
    mode.value = WeatherStationDisplayMode.rain;
    expect(await labelPixels(), orderedEquals(rain));
    observations.value = const {};
    expect(await labelPixels(), orderedEquals(empty));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
