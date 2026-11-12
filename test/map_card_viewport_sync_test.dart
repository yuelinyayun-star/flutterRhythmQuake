import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/mock_input_service.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_state.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Isolated UI boundary cases only; no API connection or production data.
UnifiedQuakeData item(int i, {required bool eew}) => UnifiedQuakeData(
  source: 'audit-${eew ? 'eew' : 'info'}-$i',
  origin: 0,
  eventId: 'AUDIT-$i',
  isEew: eew,
  timeZone: 0,
  titleText: eew ? 'Audit EEW' : 'Audit information',
  reportNumText: '1',
  useShindo: false,
  maxIntensity: '3',
  className: 'orange',
  hypocenter: 'AUDIT-$i',
  originTime: DateTime.now().toUtc(),
  reportTime: DateTime.now().toUtc(),
  magnitude: 5,
  depth: 10,
  depthText: '10km',
  lat: 35,
  lng: 140,
);

Future<QuakeProvider> mount(WidgetTester tester, {bool phone = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final provider = QuakeProvider(startCatalogServices: false)
    ..configureMobileEewCarousel(phone);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<QuakeProvider>(create: (_) => provider),
        ChangeNotifierProvider<MapStateProvider>(
          create: (_) => MapStateProvider()..setShowEstimatedEpicenter(true),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AlertModule())),
      ),
    ),
  );
  await tester.pump();
  return provider;
}

void main() {
  final mock = MockInputService();
  setUpAll(() => SourceManager().registerSource(mock));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
    SoundEffectService().enabled = false;
    StationEventTracker.instance.currentNiedEvent.value = null;
    PAlertSourceState.events.value = const [];
  });
  tearDown(() {
    UiRuntimeFlags.desktopUnifiedPageSizeNotifier.value = 4;
    SoundEffectService().enabled = true;
    StationEventTracker.instance.currentNiedEvent.value = null;
    PAlertSourceState.events.value = const [];
  });

  testWidgets(
    'frequent estimate updates do not starve pages of the same station view',
    (tester) async {
      final provider = await mount(tester);
      for (var i = 0; i < 5; i++) {
        provider.handleUnifiedEventForTest(item(i, eew: false));
      }
      final now = DateTime.now().toUtc();
      final sources = [
        for (var i = 0; i < 6; i++)
          SeismicActiveEvent(
            eventId: 'AUDIT-PA-$i',
            sourceId: 'palert',
            startedAt: now,
            updatedAt: now,
            stageName: 'confirmed',
            maxShindo: 3,
            estimate: SourceEstimate(
              latitude: 23.3 + i * .01,
              longitude: 121.1,
              depthKm: 20,
              magnitude: 4.2,
              originTime: now,
              confidence: .5,
              method: 'audit',
              supportingStationCount: 6,
            ),
          ),
      ];
      PAlertSourceState.events.value = sources;
      provider.setCameraSourceFocus([
        for (final event in sources)
          'palert_source_estimation:${event.eventId}',
      ]);
      final seen = <int>{};
      for (var tick = 0; tick < 12; tick++) {
        for (final event in sources) {
          event.updatedAt = now.add(Duration(seconds: tick));
        }
        PAlertSourceState.events.value = List.of(sources);
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          if (find
              .text('${(23.3 + i * .01).toStringAsFixed(3)}°N, 121.100°E')
              .evaluate()
              .isNotEmpty) {
            seen.add(i);
          }
        }
        await tester.pump(const Duration(seconds: 1));
      }
      expect(seen, hasLength(6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Mock stream preserves event admission sequence and stale rejection',
    (tester) async {
      final provider = await mount(tester);
      await tester.runAsync(() => provider.eewHistoryReadyForTest);
      await tester.pump();
      final fresh = item(
        10,
        eew: true,
      ).copyWith(source: 'ceaEew', reportNumText: '第3报');
      expect(mock.injectJson(jsonEncode(fresh.toMap()), format: 'unified'), 1);
      await tester.pump();
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.apiTypeLabel, 'Mock');
      expect(find.text('AUDIT-10'), findsOneWidget);
      mock.injectJson(jsonEncode(fresh.toMap()), format: 'unified');
      mock.injectJson(
        jsonEncode(fresh.copyWith(reportNumText: '第2报', magnitude: 4).toMap()),
        format: 'unified',
      );
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.reportNumText, '第3报');
      expect(provider.unifiedEvents.single.magnitude, 5);
      final stale = item(11, eew: true).copyWith(
        source: 'ceaEew',
        originTime: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      );
      mock.injectJson(jsonEncode(stale.toMap()), format: 'unified');
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(1));
      expect(find.text('AUDIT-11'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same-view six information cards rotate with the shared-view selection',
    (tester) async {
      final provider = await mount(tester);
      for (var i = 0; i < 6; i++) {
        provider.handleUnifiedEventForTest(item(i, eew: false));
      }
      expect(provider.unifiedEvents, hasLength(6));
      final seen = <String>{};
      for (var turn = 0; turn < 8; turn++) {
        // Shared information geometry remains fixed while its selected member changes.
        provider.setMobileCameraInfoFocus(provider.currentUnifiedEvent);
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          if (find.text('AUDIT-$i').evaluate().isNotEmpty) seen.add('AUDIT-$i');
        }
        await tester.pump(const Duration(seconds: 5));
      }
      debugPrint('AUDIT_SHARED_INFO reachable=${seen.length}/6 cards=$seen');
      await tester.pumpWidget(const SizedBox());
      expect(seen, hasLength(6));
    },
  );

  testWidgets('same-view six EEW cards remain reachable with a stable camera', (
    tester,
  ) async {
    final provider = await mount(tester);
    for (var i = 0; i < 6; i++) {
      provider.handleUnifiedEventForTest(item(i, eew: true));
    }
    expect(provider.unifiedEvents, hasLength(6));
    final focus = DesktopEventCameraFocus();
    final seen = <String>{};
    final owners = <String>{};
    for (var turn = 0; turn < 8; turn++) {
      final candidates = [
        for (var i = 0; i < provider.unifiedEvents.length; i++)
          DesktopCameraCandidate.fromEvent(
            provider.unifiedEvents[i],
            index: i,
          )!,
      ];
      final owner = focus.select(
        candidates: candidates,
        requestedIndex: provider.currentUnifiedIndex,
        isVisible: (_) => true,
      )!;
      owners.add(owner.key);
      final card = DesktopEventCameraFocus.cardInViewport(
        owner: owner,
        requested: candidates.firstWhere(
          (e) => e.index == provider.currentUnifiedIndex,
        ),
        isVisible: (_) => true,
      );
      provider.setMobileCameraInfoFocus(provider.unifiedEvents[card.index]);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        if (find.text('AUDIT-$i').evaluate().isNotEmpty) seen.add('AUDIT-$i');
      }
      await tester.pump(const Duration(seconds: 5));
    }
    debugPrint(
      'AUDIT_STABLE_EEW owners=${owners.length} reachable=${seen.length}/6 cards=$seen',
    );
    await tester.pumpWidget(const SizedBox());
    expect(
      seen,
      hasLength(6),
      reason: 'All same-view pages must remain reachable.',
    );
  });

  testWidgets(
    'source focus can show its estimate when five information cards exist',
    (tester) async {
      final provider = await mount(tester);
      for (var i = 0; i < 5; i++) {
        provider.handleUnifiedEventForTest(item(i, eew: false));
      }
      final now = DateTime.now().toUtc();
      StationEventTracker.instance.currentNiedEvent.value = SeismicActiveEvent(
        eventId: 'AUDIT-SOURCE',
        sourceId: 'nied',
        startedAt: now,
        updatedAt: now,
        stageName: 'confirmed',
        maxShindo: 3,
        estimate: SourceEstimate(
          latitude: 35,
          longitude: 140,
          depthKm: 20,
          magnitude: 5,
          originTime: now,
          confidence: 0.5,
          method: 'audit',
          supportingStationCount: 6,
        ),
      );
      // Same submission as _applyCameraPolicy after source focus succeeds.
      provider.setCameraSourceFocus(['nied_source_estimation:AUDIT-SOURCE']);
      await tester.pump();
      final immediatelyVisible = find.text('震源本地推算').evaluate().isNotEmpty;
      var seenSource = immediatelyVisible;
      for (var turn = 0; turn < 6; turn++) {
        await tester.pump();
        seenSource |= find.text('震源本地推算').evaluate().isNotEmpty;
        await tester.pump(const Duration(seconds: 5));
      }
      debugPrint(
        'AUDIT_SOURCE clearOwnerFallback=${provider.mobileCameraDisplayEvent?.eventId} immediatelyVisible=$immediatelyVisible eventuallyVisible=$seenSource',
      );
      await tester.pumpWidget(const SizedBox());
      expect(
        immediatelyVisible,
        isTrue,
        reason: 'The card must follow the current source focus immediately.',
      );
    },
  );

  test(
    'offscreen carousel entries cannot replace the accepted camera card',
    () {
      final owner = DesktopCameraCandidate.fromEvent(
        item(0, eew: true),
        index: 0,
      )!;
      final requested = DesktopCameraCandidate.fromEvent(
        item(1, eew: true).copyWith(lat: -20, lng: -70),
        index: 1,
      )!;
      expect(
        DesktopEventCameraFocus.cardInViewport(
          owner: owner,
          requested: requested,
          isVisible: (point) => point.latitude == owner.location.latitude,
        ),
        same(owner),
      );
    },
  );

  for (final phone in [false, true]) {
    testWidgets(
      'admission updates and temporary focus retain the original lifecycle phone=$phone',
      (tester) async {
        final provider = await mount(tester, phone: phone);
        final a = item(0, eew: true);
        final b = item(1, eew: true);
        provider.handleUnifiedEventForTest(a);
        provider.handleUnifiedEventForTest(b);
        expect(provider.unifiedEvents, hasLength(2));
        provider.setMobileCameraInfoFocus(a);
        final incoming = item(2, eew: false);
        provider.handleUnifiedEventForTest(incoming);
        provider.setMobileCameraInfoFocus(incoming);
        await tester.pump();
        expect(find.text('AUDIT-2'), findsOneWidget);
        expect(provider.unifiedEvents, hasLength(3));
        final update = incoming.copyWith(
          reportNumText: '第2报',
          magnitude: 5.2,
          reportTime: DateTime.now().toUtc().add(const Duration(seconds: 1)),
        );
        provider.handleUnifiedEventForTest(update);
        await tester.pump();
        expect(
          provider.unifiedEvents.where((e) => e.eventId == incoming.eventId),
          hasLength(1),
        );
        expect(provider.mobileCameraDisplayEvent?.magnitude, 5.2);
        // The existing map hold expires and returns to its selected EEW.
        await tester.pump(const Duration(milliseconds: 6500));
        provider.setMobileCameraInfoFocus(b);
        await tester.pump();
        expect(find.text('AUDIT-1'), findsOneWidget);
        expect(provider.unifiedEvents, hasLength(3));
        // Clearing a completed source focus must not change event admission.
        provider.setCameraSourceFocus([
          'nied_source_estimation:finished-source',
        ]);
        provider.handleUnifiedEventForTest(item(3, eew: true));
        await tester.pump();
        expect(provider.cameraSourceDisplayKeys, isEmpty);
        expect(find.text('AUDIT-3'), findsOneWidget);
        provider.dismissUnifiedEventForTest(incoming);
        await tester.pump();
        expect(
          provider.unifiedEvents.any((e) => e.eventId == incoming.eventId),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
