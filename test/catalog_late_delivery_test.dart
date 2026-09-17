import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final examples =
      (jsonDecode(
                File(
                  'test/fixtures/whews_catalog_official_examples.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  final frame = examples.singleWhere((e) => e['source'] == 'tmd');
  final raw = Map<String, dynamic>.from(frame['Data'] as Map);
  final documented = QuakeEventAdapter.convertWhews('tmd', raw)!;
  final origin = QuakeTime.wallClockToUtc(
    documented.originTime!,
    const Duration(hours: 8),
  );
  final arrival = origin.add(const Duration(minutes: 9));

  int remaining(UnifiedQuakeData event, DateTime time, {DateTime? first}) =>
      QuakeTime.catalogInformationRemainingSeconds(
        event,
        300,
        firstArrivedAt: first,
        now: time,
        sourceNow: time,
      )!;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test('unchanged documented TMD payload admits nine-minute late delivery', () {
    final before = jsonEncode(raw);
    expect(remaining(documented, arrival), 300);
    expect(
      remaining(
        documented,
        arrival.add(const Duration(minutes: 4)),
        first: arrival,
      ),
      60,
    );
    expect(
      remaining(
        documented,
        arrival.add(const Duration(minutes: 5)),
        first: arrival,
      ),
      0,
    );
    expect(jsonEncode(raw), before);
    expect(documented.originTime, DateTime.parse(raw['shockTime'] as String));
    expect(documented.reportTime, DateTime.parse(raw['updateTime'] as String));
  });

  test(
    'admission boundary and missing timestamps never become fresh alerts',
    () {
      expect(
        remaining(
          documented,
          origin.add(const Duration(minutes: 29, seconds: 59)),
        ),
        300,
      );
      expect(remaining(documented, origin.add(const Duration(minutes: 30))), 0);
      expect(remaining(documented, origin.add(const Duration(days: 1))), 0);
      final missing = QuakeEventAdapter.convertWhews('tmd', const {
        'id': 'unit-missing-time',
      })!;
      expect(remaining(missing, arrival), 0);
    },
  );

  test('snapshots keep original expiry and explicit history never alerts', () {
    expect(
      remaining(documented.copyWith(isSnapshot: true), arrival),
      lessThanOrEqualTo(0),
    );
    expect(
      remaining(
        documented.copyWith(isSnapshot: true),
        origin.add(const Duration(minutes: 2)),
      ),
      180,
    );
    expect(remaining(documented.copyWith(isHistory: true), origin), 0);
  });

  test('acceptance before boundary finishes its original display window', () {
    final lateArrival = origin.add(const Duration(minutes: 29));
    expect(
      remaining(
        documented,
        origin.add(const Duration(minutes: 32)),
        first: lateArrival,
      ),
      120,
    );
  });

  test(
    'WHEWS marks only catalog snapshot delivery and does not mutate frames',
    () async {
      final received = <UnifiedQuakeData>[];
      final snapshotService = WhewsService(apiToken: 'test-only');
      final liveService = WhewsService(apiToken: 'test-only');
      final subscriptions = [
        snapshotService.onUnifiedEvent.listen(received.add),
        liveService.onUnifiedEvent.listen(received.add),
      ];
      final before = jsonEncode(frame);
      snapshotService.handleMessageForTesting([frame]);
      liveService.handleMessageForTesting(frame);
      await Future<void>.delayed(Duration.zero);
      expect(received.map((e) => e.isSnapshot), [true, false]);
      expect(jsonEncode(frame), before);
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      snapshotService.dispose();
      liveService.dispose();
    },
  );

  test('foreground and Android accept late TMD above M2 only once', () async {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.setSourceInfoMagFilter(QuakeSourceType.tmd, 2);
    final processor = BackgroundEventProcessor(
      sourceInfoMagFilters: {'source_mag_filter_tmd': 2},
    );
    final event = lateDeliveryScenario();
    var notifications = 0;
    provider.onUnifiedEventNotified = (_, _) => notifications++;
    provider.handleUnifiedEventForTest(event);
    final accepted = provider.unifiedEvents.single;
    expect(accepted.originTime, event.originTime);
    expect(accepted.reportTime, event.reportTime);
    expect(accepted.arrivedAt, isNotNull);
    final mobile = processor.process(event);
    expect(mobile.type, BackgroundEventResultType.newEvent);
    expect(mobile.event!.originTime, event.originTime);
    provider.handleUnifiedEventForTest(event);
    expect(provider.unifiedEvents.single.arrivedAt, accepted.arrivedAt);
    expect(notifications, 1);
    expect(processor.process(event).type, BackgroundEventResultType.dropped);
    provider.dismissUnifiedEventForTest(event);
    provider.handleUnifiedEventForTest(event);
    expect(provider.unifiedEvents, isEmpty);
    expect(notifications, 1);
    final restarted = BackgroundEventProcessor(
      sourceInfoMagFilters: {},
      seenUnifiedInfoEvents: processor.seenUnifiedInfoEvents,
    );
    expect(restarted.process(event).type, BackgroundEventResultType.dropped);
  });

  test(
    'late live revisions retain first arrival across Android serialization',
    () {
      final processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final event = lateDeliveryScenario();
      final first = processor.process(event).event!;
      final corrected = processor.process(event.copyWith(magnitude: 4.2));
      expect(corrected.type, BackgroundEventResultType.update);
      expect(corrected.event!.arrivedAt, first.arrivedAt);
      final restored = UnifiedQuakeData.fromMap(corrected.event!.toMap());
      expect(restored.arrivedAt, first.arrivedAt);
      expect(restored.originTime, event.originTime);
    },
  );

  test('threshold and disabled-source choices remain authoritative', () {
    final event = lateDeliveryScenario();
    for (final threshold in [-1.0, 5.0]) {
      expect(
        BackgroundEventProcessor(
          sourceInfoMagFilters: {'source_mag_filter_tmd': threshold},
        ).process(event).type,
        BackgroundEventResultType.dropped,
      );
    }
  });

  testWidgets(
    'late card lasts five minutes and replay cannot extend or revive it',
    (tester) async {
      final provider = QuakeProvider();
      await tester.pump(const Duration(milliseconds: 50));
      final event = lateDeliveryScenario();
      provider.handleUnifiedEventForTest(event);
      expect(provider.unifiedEvents, hasLength(1));
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(provider.unifiedEvents, hasLength(1));
      provider.handleUnifiedEventForTest(event);
      await tester.pump(const Duration(seconds: 2));
      expect(provider.unifiedEvents, isEmpty);
      provider.handleUnifiedEventForTest(event);
      expect(provider.unifiedEvents, isEmpty);
      provider.dispose();
    },
  );

  test('foreground restart restores catalog replay protection', () async {
    final first = QuakeProvider();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final event = lateDeliveryScenario();
    first.handleUnifiedEventForTest(event);
    expect(first.unifiedEvents, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    first.dispose();
    final restarted = QuakeProvider();
    addTearDown(restarted.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    restarted.handleUnifiedEventForTest(event);
    expect(restarted.unifiedEvents, isEmpty);
    expect(
      restarted.historyBySource['whews_tmd']!.any(
        (e) => e.eventId == event.eventId,
      ),
      isTrue,
    );
  });
}

// Explicit unit-test scenario matching the reported delay, not a captured frame.
UnifiedQuakeData lateDeliveryScenario() {
  final origin = DateTime.now().toUtc().subtract(const Duration(minutes: 9));
  return UnifiedQuakeData(
    source: 'whews_tmd',
    origin: 3,
    eventId: 'unit-late-tmd',
    isEew: false,
    timeZone: 0,
    titleText: '泰国气象局地震信息',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '6',
    className: 'yellow',
    hypocenter: '越南',
    originTime: origin,
    reportTime: origin,
    magnitude: 4.1,
    depth: 10,
    apiTypeLabel: 'WHEWS',
  );
}
