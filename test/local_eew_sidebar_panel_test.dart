import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/models/sasmex_map_geometry.dart';
import 'package:flutterrhythmquake/widgets/ui/local_eew_sidebar_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final body = File(
    'test/fixtures/chinaeew_icl/98943021.json',
  ).readAsStringSync();
  final data = jsonDecode(body) as Map<String, dynamic>;
  final report = Map<String, dynamic>.from((data['data'] as List).last);
  final event = QuakeEventAdapter.convertChinaEewIcl(report)!;

  test('SASMEX original event countdown matches its S wave without depth', () {
    final frame =
        jsonDecode(
              File(
                'test/fixtures/sasmex_firestore_20261006.relay.json',
              ).readAsStringSync(encoding: utf8),
            )
            as Map<String, dynamic>;
    final sasmex = SasmexService.parseRelayFrame(frame)!;
    final before = jsonEncode(sasmex.sourcePayload);
    const userLat = 29.36;
    const userLng = 120.17;
    final distance = QuakeCalculator.haversineDistance(
      sasmex.lat!,
      sasmex.lng!,
      userLat,
      userLng,
    );
    final estimate = calculateLocalEewEstimate(
      sasmex,
      userLat: userLat,
      userLng: userLng,
      elapsedSeconds: 20.2,
    );
    expect(estimate.secondsToSWave, (distance / 5 - 20.2).round());
    expect(estimate.intensity, isNull);
    expect(sasmex.depth, -1);
    expect(sasmex.magnitude, -1);
    expect(jsonEncode(sasmex.sourcePayload), before);
    final atEpicenter = calculateLocalEewEstimate(
      sasmex,
      userLat: sasmex.lat,
      userLng: sasmex.lng,
      elapsedSeconds: 20,
    );
    expect(atEpicenter.secondsToSWave, 0);
    final animation = SasmexMapAnimation(
      const LatLng(16.29569, -97.90988),
      20,
      false,
    );
    expect(
      SasmexMapAnimation.sArrivalSeconds(animation.sRadiusMeters / 1000),
      20,
    );
    expect(
      calculateLocalEewEstimate(
        sasmex,
        userLat: null,
        userLng: null,
        elapsedSeconds: 20,
      ).secondsToSWave,
      isNull,
    );
    expect(
      calculateLocalEewEstimate(
        sasmex.copyWith(isCanceled: true),
        userLat: userLat,
        userLng: userLng,
        elapsedSeconds: 20,
      ).secondsToSWave,
      isNull,
    );
  });

  test(
    'GlobalQuake 4162 km event has an available far-field S-wave arrival',
    () async {
      await TravelTimeService().ensureLoaded();
      const userLat = 29.36;
      const userLng = 120.17;
      final farField = event.copyWith(
        source: 'globalQuakeEew',
        lat: -8.0,
        lng: 120.17,
        magnitude: 5.1,
        depth: 10,
        originTime: DateTime.utc(2026, 10, 18, 8, 0, 7),
      );
      final estimated = calculateLocalEewEstimate(
        farField,
        userLat: userLat,
        userLng: userLng,
        elapsedSeconds: 235,
      );
      expect(estimated.distanceKm, inInclusiveRange(4000, 4300));
      expect(estimated.secondsToSWave, isNotNull);
      expect(estimated.secondsToSWave, greaterThan(480));
      expect(estimated.secondsToSWave, lessThan(650));
    },
  );
  test('local estimate uses the captured report and local position', () async {
    await TravelTimeService().ensureLoaded();
    final county = Map<String, dynamic>.from(
      (report['counties'] as List).first,
    );
    final rawBefore = jsonEncode(report);
    final estimate = calculateLocalEewEstimate(
      event,
      userLat: (county['latitude'] as num).toDouble(),
      userLng: (county['longitude'] as num).toDouble(),
      elapsedSeconds: 0,
    );

    expect(estimate.distanceKm, greaterThan(0));
    expect(double.parse(estimate.intensity!), inInclusiveRange(0, 12));
    expect(estimate.secondsToSWave, greaterThan(0));
    expect(jsonEncode(report), rawBefore);

    final shindoFlagged = calculateLocalEewEstimate(
      event.copyWith(useShindo: true),
      userLat: (county['latitude'] as num).toDouble(),
      userLng: (county['longitude'] as num).toDouble(),
      elapsedSeconds: 0,
    );
    expect(shindoFlagged.intensity, estimate.intensity);

    final afterArrival = calculateLocalEewEstimate(
      event,
      userLat: (county['latitude'] as num).toDouble(),
      userLng: (county['longitude'] as num).toDouble(),
      elapsedSeconds: estimate.secondsToSWave! + 10,
    );
    expect(afterArrival.secondsToSWave, 0);
  });

  test('missing position or source parameters do not invent an estimate', () {
    final noPosition = calculateLocalEewEstimate(
      event,
      userLat: null,
      userLng: null,
      elapsedSeconds: 0,
    );
    expect(noPosition.distanceKm, isNull);
    expect(noPosition.intensity, isNull);
    expect(noPosition.secondsToSWave, isNull);

    final missingDepth = calculateLocalEewEstimate(
      event.copyWith(depth: -1),
      userLat: event.lat,
      userLng: event.lng,
      elapsedSeconds: 0,
    );
    expect(missingDepth.distanceKm, 0);
    expect(missingDepth.intensity, isNull);
    expect(missingDepth.secondsToSWave, isNull);
  });

  testWidgets('GlobalQuake captured replay renders numeric S countdown in UI', (
    tester,
  ) async {
    await TravelTimeService().ensureLoaded();
    LocationService().setCurrentLatLng(29.36, 120.17);
    final eventFromCapture = UnifiedQuakeData(
      source: 'globalQuakeEew',
      origin: 3,
      eventId: '3ef60ee6-b157-4deb-bd6a-c8b426937d49',
      isEew: true,
      timeZone: 8,
      titleText: 'GlobalQuake 地震预警',
      reportNumText: '第1报',
      useShindo: false,
      maxIntensity: '7',
      className: 'orange',
      hypocenter: '印尼弗洛勒斯岛地区附近',
      originTime: DateTime(2026, 10, 18, 16, 0, 6, 55),
      reportTime: DateTime(2026, 10, 18, 16, 2, 56, 425),
      magnitude: 5.227834224700928,
      depth: 10,
      lat: -8.098663330078125,
      lng: 120.38573455810547,
      replaySessionId: 'captured-replay-test',
      replayClockOffset: DateTime.now().toUtc().difference(
        DateTime.utc(2026, 10, 18, 8, 2, 58),
      ),
    );
    expect(
      selectLocalEewSidebarEvent(
        [eventFromCapture],
        0,
        domesticEnabled: true,
        foreignEnabled: true,
      ),
      same(eventFromCapture),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 440,
            child: LocalEewSidebarPanel(
              event: eventFromCapture,
              scale: (v) => v,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final countdown = tester.widget<Text>(
      find.byKey(const ValueKey('local-eew-countdown')),
    );
    expect(
      countdown.data,
      isNot('--'),
      reason: 'Widget should render a numeric countdown for captured replay',
    );
    expect(int.tryParse(countdown.data!), isNotNull);
    expect(find.text('S 波走时不可用'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'sidebar loads travel tables itself and updates unavailable placeholder',
    (tester) async {
      TravelTimeService().resetForTesting();
      LocationService().setCurrentLatLng(29.36, 120.17);
      final source = UnifiedQuakeData(
        source: 'globalQuakeEew',
        origin: 3,
        eventId: 'replay-load-check',
        isEew: true,
        timeZone: 8,
        titleText: 'GlobalQuake 地震预警',
        reportNumText: '第14报',
        useShindo: false,
        maxIntensity: '7',
        className: 'orange',
        hypocenter: '印尼弗洛勒斯岛地区附近',
        originTime: DateTime(2026, 10, 18, 16, 0, 7),
        magnitude: 5.1,
        depth: 10,
        lat: -8.073859214782715,
        lng: 120.3382339477539,
        replaySessionId: 'local-load',
        replayClockOffset: DateTime.now().toUtc().difference(
          DateTime.utc(2026, 10, 18, 8, 4, 2),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 450,
              child: LocalEewSidebarPanel(event: source, scale: (v) => v),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && !TravelTimeService().isLoaded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(TravelTimeService().isLoaded, isTrue);
      final label = tester.widget<Text>(
        find.byKey(const ValueKey('local-eew-countdown')),
      );
      expect(int.tryParse(label.data ?? ''), isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('EEW source switch keeps the captured ICL event eligible', () {
    expect(isDomesticLocalEew(event), isTrue);
    expect(
      selectLocalEewSidebarEvent(
        [event],
        0,
        domesticEnabled: true,
        foreignEnabled: false,
      ),
      same(event),
    );
    expect(
      selectLocalEewSidebarEvent(
        [event],
        0,
        domesticEnabled: false,
        foreignEnabled: true,
      ),
      isNull,
    );
    expect(
      selectLocalEewSidebarEvent(
        [event.copyWith(isCanceled: true)],
        0,
        domesticEnabled: true,
        foreignEnabled: true,
      ),
      isNull,
    );
  });

  testWidgets('local page fits a narrow sidebar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 145,
              height: 170,
              child: LocalEewSidebarPanel(event: event, scale: (v) => v),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('本地烈度预估 · S 波倒计时'), findsOneWidget);
    expect(find.textContaining('仅供参考'), findsOneWidget);
    expect(find.textContaining('以实际感受为准'), findsNothing);
    final place = tester.widget<Text>(
      find.byKey(const ValueKey('local-eew-place')),
    );
    expect(place.style?.fontSize, 10);
    expect(place.style?.fontWeight, FontWeight.w600);
    expect(place.style?.color, Colors.white.withValues(alpha: 0.9));
    expect(find.text('本地预估烈度'), findsOneWidget);
    expect(find.text('距震中'), findsOneWidget);
    expect(find.byKey(const ValueKey('local-eew-countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
