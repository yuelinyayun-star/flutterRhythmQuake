import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/unified_event_wave_layers.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'package:latlong2/latlong.dart';

Map readJson(String path) =>
    jsonDecode(File(path).readAsStringSync(encoding: utf8)) as Map;

Future<void> expectWaveClass(
  WidgetTester tester,
  UnifiedQuakeData event,
  String expected,
) async {
  final before = jsonEncode(event.toMap());
  final mapped = QuakeMessage(
    source: switch (event.source) {
      'cwaEew' => QuakeSourceType.cwa_eew,
      'jmaEew' => QuakeSourceType.wolfx,
      'ceaEew' => QuakeSourceType.cea,
      'kmaEew' => QuakeSourceType.kma_eew_fan,
      'sa' => QuakeSourceType.sa,
      _ => QuakeSourceType.cenc,
    },
    eventId: event.eventId,
    location: event.hypocenter,
    latitude: event.lat ?? 23,
    longitude: event.lng ?? 121,
    magnitude: event.magnitude,
    depth: event.depth,
    originTime: event.originTime ?? DateTime.utc(2000),
    isCanceled: event.isCanceled,
    isAssumption: event.isAssumption,
    isWarn: event.isWarn,
  );
  final requestedClasses = <String>[];
  const suppliedColor = Color(0xFF4FF77F);
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(mapped.latitude, mapped.longitude),
          initialZoom: 7,
        ),
        children: [
          UnifiedEventWaveLayers(
            events: [event],
            mapEvents: [mapped],
            waveColor: (name) {
              requestedClasses.add(name);
              return suppliedColor;
            },
            blinkOn: false,
          ),
        ],
      ),
    ),
  );
  expect(requestedClasses, isNotEmpty);
  expect(requestedClasses, everyElement(expected));
  final layer = tester.widget<QuakeWaveLayer>(find.byType(QuakeWaveLayer));
  expect(layer.event, same(mapped));
  expect(layer.showWaves, event.isEew);
  expect(layer.blinkOn, !event.isEew);
  expect(layer.sWaveColor, suppliedColor);
  expect(layer.colorMode, SWaveColorMode.intensity);
  final painter =
      tester
              .widget<CustomPaint>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint && widget.painter is WavePainter,
                ),
              )
              .painter!
          as WavePainter;
  expect(painter.sWaveColor, suppliedColor);
  expect(painter.event, same(mapped));
  expect(jsonEncode(event.toMap()), before);
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TravelTimeService().ensureLoaded());
  final jian = readJson('test/fixtures/jian/all.json');
  final cwaRaw = Map<String, dynamic>.from(
    readJson(
          'test/fixtures/source_estimation/cwa_1150075_prediction_reference.json',
        )['sourcePayload']
        as Map,
  );
  final cwa = QuakeEventAdapter.convertJian('cwa-eew', cwaRaw)!;
  final whews =
      jsonDecode(
            File(
              'test/fixtures/catalog_20260917/whews_all.json',
            ).readAsStringSync(encoding: utf8),
          )
          as List;

  testWidgets('original CWA report connects its existing estimate to waves', (
    tester,
  ) async {
    final before = jsonEncode(cwaRaw);
    expect(estimatedEewIntensityValue(cwa), '3');
    await expectWaveClass(tester, cwa, 'green');
    expect(cwa.maxIntensity, '-');
    expect(cwa.sourcePayload, cwaRaw);
    expect(jsonEncode(cwaRaw), before);
  });

  testWidgets('original Jian CEA, CEA-PR and SA estimates reach the painter', (
    tester,
  ) async {
    for (final (type, value, color) in [
      ('cea', '6', 'yellow'),
      ('cea-pr', '4', 'blue'),
      ('sa', '5', 'green'),
    ]) {
      final raw = Map<String, dynamic>.from(
        (jian['source：$type'] as Map)['Data'] as Map,
      );
      final before = jsonEncode(raw);
      final event = QuakeEventAdapter.convertJian(type, raw)!;
      expect(estimatedEewIntensityValue(event), value, reason: type);
      await expectWaveClass(tester, event, color);
      expect(event.maxIntensity, '-');
      expect(jsonEncode(raw), before);
    }
  });

  testWidgets('WHEWS missing-value protocol paths reuse existing estimates', (
    tester,
  ) async {
    // Synthetic protocol boundaries, not edited upstream captures.
    for (final type in ['cea', 'cea_pr', 'sa_eew', 'kma_eew']) {
      final raw = <String, dynamic>{
        'id': 'protocol-boundary-case',
        'updates': 1,
        'shockTime': '2000-01-01 00:00:00',
        'magnitude': 4.7,
        'depth': 10,
        'latitude': 30.0,
        'longitude': 100.0,
        'placeName': 'Protocol boundary case',
      };
      final before = jsonEncode(raw);
      final event = QuakeEventAdapter.convertWhews(type, raw)!;
      expect(estimatedEewIntensityValue(event), '6', reason: type);
      await expectWaveClass(tester, event, 'yellow');
      expect(jsonEncode(raw), before);
    }
  });

  testWidgets(
    'original reported intensities and PLUM keep their wave classes',
    (tester) async {
      final events = <UnifiedQuakeData>[
        for (final frame in whews.whereType<Map>())
          if (const {
            'sa_eew',
            'kma_eew',
            'jma_eew',
            'cwa_eew',
          }.contains(frame['source']))
            QuakeEventAdapter.convertWhews(
              frame['source'] as String,
              Map<String, dynamic>.from(frame['Data'] as Map),
            )!,
        QuakeEventAdapter.convertWhews(
          'jma_eew',
          Map<String, dynamic>.from(
            readJson('test/fixtures/jma_plum_20261106/whews_report_01.json'),
          ),
        )!,
      ];
      expect(events.length, greaterThanOrEqualTo(5));
      for (final event in events) {
        expect(estimatedEewIntensityValue(event), isNull);
        await expectWaveClass(tester, event, event.className);
      }
    },
  );

  testWidgets('CWA APIs and deferred replay retain every shindo palette class', (
    tester,
  ) async {
    // Presentation-state boundaries; original capture and parser remain intact.
    for (final (api, origin) in [
      ('FAN', 1),
      ('Jian Project', 4),
      ('WHEWS', 3),
    ]) {
      await expectWaveClass(
        tester,
        cwa.copyWith(apiTypeLabel: api, origin: origin),
        'green',
      );
      for (final (value, color) in [
        ('0', 'dark-gray'),
        ('1', 'gray'),
        ('2', 'blue'),
        ('3', 'green'),
        ('4', 'yellow'),
        ('5-', 'orange'),
        ('5+', 'dark-orange'),
        ('6-', 'red'),
        ('6+', 'dark-red'),
        ('7', 'purple'),
      ]) {
        await expectWaveClass(
          tester,
          cwa.copyWith(
            apiTypeLabel: 'Replay',
            origin: origin,
            replaySessionId: 'presentation-state-case',
            clearSourcePayload: true,
            displayEstimateResolved: true,
            displayEstimatedIntensity: value,
          ),
          color,
        );
      }
    }
  });

  testWidgets(
    'excluded statuses and ordinary information keep original colors',
    (tester) async {
      // Presentation-state boundaries do not redefine upstream reports.
      for (final event in [
        cwa.copyWith(isCanceled: true),
        cwa.copyWith(isAssumption: true),
        cwa.copyWith(isEew: false, source: 'cwaEqlist'),
        cwa.copyWith(apiTypeLabel: 'Wolfx', origin: 0),
      ]) {
        expect(estimatedEewIntensityValue(event), isNull);
        await expectWaveClass(tester, event, event.className);
      }
    },
  );
}
