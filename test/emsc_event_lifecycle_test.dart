import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tts = TtsService();
  final spoken = <String>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tts.init();
    await tts.stop();
    await tts.configure(
      enabled: true,
      eventEnabled: true,
      updateEnabled: true,
      gptSovitsEnabled: false,
      persist: false,
    );
    spoken.clear();
    tts.windowsSpeechOverrideForTest = (text) async => spoken.add(text);
  });
  tearDown(() async {
    await tts.stop();
    tts.windowsSpeechOverrideForTest = null;
  });

  test(
    'unaltered old WS capture is history-only across EMSC transports',
    () async {
      final rawText = File(
        'test/fixtures/emsc_ws_20261008.original.json',
      ).readAsStringSync(encoding: utf8);
      final raw = jsonDecode(rawText) as Map<String, dynamic>;
      final feature = raw['data'] as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>;
      final coordinates = (feature['geometry'] as Map)['coordinates'] as List;
      // Same field mapping as the official service; retain the unmodified wire data.
      final event = QuakeEventAdapter.convert('emsc', {
        'eventId': props['unid'],
        'latitude': coordinates[1],
        'longitude': coordinates[0],
        'depth': props['depth'],
        'magnitude': props['mag'],
        'originTime': props['time'],
        'createTime': props['lastupdate'],
        'originalData': raw,
      }, 0)!;
      for (final transport in [
        event,
        event.copyWith(
          origin: 1,
          apiTypeLabel: 'FAN',
          useSourceTimeForExpiry: false,
        ),
        event.copyWith(origin: 3, apiTypeLabel: 'WHEWS'),
      ]) {
        for (final alreadyAccepted in [false, true]) {
          final provider = QuakeProvider();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          var notifications = 0;
          provider.onUnifiedEventNotified = (_, _) => notifications++;
          provider.handleUnifiedEventForTest(
            transport,
            alreadyAccepted: alreadyAccepted,
          );
          expect(provider.unifiedEvents, isEmpty);
          expect(notifications, 0);
          provider.dispose();
        }
        expect(
          BackgroundEventProcessor(
            sourceInfoMagFilters: {},
          ).process(transport).type,
          BackgroundEventResultType.dropped,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      expect(spoken, isEmpty);
      expect(event.sourcePayload!['originalData'], raw);
      expect(
        File(
          'test/fixtures/emsc_ws_20261008.original.json',
        ).readAsStringSync(encoding: utf8),
        rawText,
      );
    },
  );

  test(
    'old earthquake with newer revision never replaces current EMSC',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final current = _lifecycleEvent('unit-current');
    final older = current.copyWith(
      eventId: 'unit-older',
      origin: 1,
      apiTypeLabel: 'FAN',
      timeZone: 8,
      originTime: current.originTime!.add(const Duration(hours: 8, minutes: -10)),
      reportTime: current.reportTime!.add(const Duration(hours: 8, seconds: 1)),
      );
      var notifications = 0;
      provider.onUnifiedEventNotified = (_, _) => notifications++;
      provider.handleUnifiedEventForTest(current);
      expect(
        background.process(current).type,
        BackgroundEventResultType.newEvent,
      );
      provider.handleUnifiedEventForTest(older);
      expect(background.process(older).type, BackgroundEventResultType.dropped);
      expect(provider.unifiedEvents.single.eventId, current.eventId);
      expect(notifications, 1);
    },
  );

  test(
    'revision changes the card silently and duplicates do not renew it',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      var notifications = 0;
      provider.onUnifiedEventNotified = (_, _) => notifications++;
      final first = _lifecycleEvent('unit-revision');
      provider.handleUnifiedEventForTest(first);
      final arrival = provider.unifiedEvents.single.arrivedAt;
      final newer = first.copyWith(
        magnitude: 4.3,
        reportTime: first.reportTime!.add(const Duration(seconds: 1)),
      );
      provider.handleUnifiedEventForTest(newer);
      provider.handleUnifiedEventForTest(first);
      provider.handleUnifiedEventForTest(newer);
      expect(provider.unifiedEvents.single.magnitude, 4.3);
      expect(provider.unifiedEvents.single.arrivedAt, arrival);
      expect(notifications, 1);
      provider.dismissUnifiedEventForTest(newer);
      provider.handleUnifiedEventForTest(newer.copyWith(magnitude: 4.4));
      expect(provider.unifiedEvents, isEmpty);
      expect(notifications, 1);
    },
  );

  test('expired card cancels voice before its delayed playback', () async {
    if (!Platform.isWindows) return;
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final event = _lifecycleEvent('unit-about-to-expire').copyWith(
      arrivedAt: DateTime.now().subtract(const Duration(seconds: 299)),
    );
    provider.handleUnifiedEventForTest(event, alreadyAccepted: true);
    expect(provider.unifiedEvents, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    expect(provider.unifiedEvents, isEmpty);
    expect(spoken, isEmpty);
  });

  test('fresh EMSC voice starts while its card is active', () async {
    if (!Platform.isWindows) return;
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final event = _lifecycleEvent('unit-fresh-voice');
    provider.handleUnifiedEventForTest(event);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(provider.unifiedEvents, hasLength(1));
    expect(spoken, hasLength(1));
    expect(spoken.single, contains('欧洲地中海地震中心'));
  });
}

// Synthetic lifecycle scenarios only; the captured upstream JSON above stays intact.
UnifiedQuakeData _lifecycleEvent(String id) {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: 'emsc',
    origin: 0,
    eventId: id,
    isEew: false,
    timeZone: 0,
    titleText: 'EMSC 地震情报',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '4',
    className: 'yellow',
    hypocenter: 'Unit location',
    originTime: now.subtract(const Duration(minutes: 2)),
    reportTime: now,
    magnitude: 4.1,
    depth: 10,
    lat: 18.46,
    lng: 100.992,
    apiTypeLabel: 'EMSC',
    useSourceTimeForExpiry: true,
  );
}
