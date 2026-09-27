import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/ui/local_eew_sidebar_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final body = File(
    'test/fixtures/chinaeew_icl/98943021.json',
  ).readAsStringSync();
  final data = jsonDecode(body) as Map<String, dynamic>;
  final report = Map<String, dynamic>.from((data['data'] as List).last);
  final event = QuakeEventAdapter.convertChinaEewIcl(report)!;

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
    expect(find.text('本地预估烈度'), findsOneWidget);
    expect(find.text('距震中'), findsOneWidget);
    expect(find.byKey(const ValueKey('local-eew-countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
