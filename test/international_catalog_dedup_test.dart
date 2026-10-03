import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/whews_catalog.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';

Map<String, DateTime> _remember(
  UnifiedQuakeData event, [
  Map<String, DateTime> previous = const {},
]) => {
  ...previous,
  for (final key in catalogReportKeys(event, previous))
    key: DateTime.now().toUtc(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    await TravelTimeService().ensureLoaded();
  });
  tearDown(() => SoundEffectService().enabled = true);

  test('unaltered GeoNet captures match across FAN WHEWS and Jian', () async {
    final whewsText = File(
      'test/fixtures/catalog_20260917/whews_all.json',
    ).readAsStringSync();
    final jianText = File(
      'test/fixtures/catalog_20260917/jian_all.json',
    ).readAsStringSync();
    final frames = jsonDecode(whewsText) as List;
    final raw = Map<String, dynamic>.from(
      (frames.singleWhere((f) => f['source'] == 'geonet') as Map)['Data']
          as Map,
    );
    final jianRaw = Map<String, dynamic>.from(
      ((jsonDecode(jianText) as Map)['source：geonet'] as Map)['Data'] as Map,
    );
    final before = jsonEncode(raw);
    final jianBefore = jsonEncode(jianRaw);
    final whews = QuakeEventAdapter.convertWhews('geonet', raw)!;
    final jian = QuakeEventAdapter.convertJian('geonet', jianRaw)!;
    final fanService = FanService();
    final received = <UnifiedQuakeData>[];
    final subscription = fanService.onUnifiedEvent.listen(received.add);
    addTearDown(subscription.cancel);
    addTearDown(fanService.dispose);
    fanService.handleMessageForTesting(
      jsonEncode({'type': 'update', 'source': 'geonet', 'Data': raw}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    final fan = received.single;
    expect(fan.apiTypeLabel, 'FAN');
    expect(whews.depth, 26.5);
    expect(jian.depth, 26.48970031738281);
    expect(whews.originTime!.millisecond, 0);
    expect(jian.originTime!.millisecond, 280);
    for (final first in [fan, whews, jian]) {
      final seen = _remember(first);
      for (final other in [fan, whews, jian]) {
        expect(
          catalogCanonicalEventId(other, seen),
          catalogCanonicalEventId(first, seen),
        );
        final provider = QuakeProvider();
        expect(
          sameCatalogHistoryEvent(
            'whews_geonet',
            provider.unifiedToQuakeMessageForTest(first),
            provider.unifiedToQuakeMessageForTest(other),
          ),
          isTrue,
        );
        provider.dispose();
      }
    }
    expect(fan.sourcePayload, raw);
    expect(whews.sourcePayload, raw);
    expect(jian.sourcePayload, jianRaw);
    expect(jsonEncode(raw), before);
    expect(jsonEncode(jianRaw), jianBefore);
    expect(
      File('test/fixtures/catalog_20260917/whews_all.json').readAsStringSync(),
      whewsText,
    );
    expect(
      File('test/fixtures/catalog_20260917/jian_all.json').readAsStringSync(),
      jianText,
    );
  });

  for (final source in [
    ...unifiedCatalogSources.keys,
    'usgsEqlist',
    'kmaEqlist',
    'emsc',
    'hko',
    'bcsf',
    'gfz',
    'usp',
  ]) {
    test(
      '$source: three APIs and repeated revisions alert only once',
      () async {
        final provider = QuakeProvider();
        addTearDown(provider.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
        final first = _unitEvent(source);
        final fan = first.copyWith(
          eventId: 'unit-fan-id',
          origin: 1,
          apiTypeLabel: 'FAN',
          magnitude: 4.2,
          reportTime: first.reportTime!.add(const Duration(seconds: 1)),
        );
        final jian = first.copyWith(
          eventId: 'unit-jian-id',
          origin: 4,
          apiTypeLabel: 'Jian Project',
          magnitude: 4.28,
          depth: 10.02,
          lat: 18.4601,
          lng: 100.9921,
          originTime: first.originTime!.add(const Duration(milliseconds: 280)),
          reportTime: first.reportTime!.add(const Duration(seconds: 2)),
        );
        var notifications = 0;
        provider.onUnifiedEventNotified = (_, _) => notifications++;
        provider.handleUnifiedEventForTest(first);
        final arrived = provider.unifiedEvents.single.arrivedAt;
        expect(
          background.process(first).type,
          BackgroundEventResultType.newEvent,
        );
        for (final revision in [fan, jian]) {
          provider.handleUnifiedEventForTest(revision);
          final result = background.process(revision);
          expect(result.type, BackgroundEventResultType.update);
          expect(result.isUpdate, isTrue);
          expect(provider.unifiedEvents, hasLength(1));
          expect(provider.unifiedEvents.single.arrivedAt, arrived);
          expect(provider.unifiedEvents.single.eventId, revision.eventId);
          expect(provider.unifiedEvents.single.magnitude, revision.magnitude);
          expect(notifications, 1);
        }
        for (var i = 0; i < 4; i++) {
          for (final duplicate in [first, fan, jian]) {
            provider.handleUnifiedEventForTest(duplicate);
            expect(
              background.process(duplicate).type,
              BackgroundEventResultType.dropped,
            );
          }
        }
        expect(notifications, 1);
        expect(provider.unifiedEvents.single.magnitude, jian.magnitude);
        final restarted = BackgroundEventProcessor(
          sourceInfoMagFilters: {},
          seenUnifiedInfoEvents: background.seenUnifiedInfoEvents,
        );
        expect(restarted.process(jian).type, BackgroundEventResultType.dropped);
        final bucket = source == 'emsc' ? 'emscEqlist' : source;
        if (unifiedCatalogSources.containsKey(bucket) ||
            bucket == 'usgsEqlist' ||
            bucket == 'kmaEqlist' ||
            bucket == 'emscEqlist') {
          final manager = EqlistManager();
          manager.getAllBuckets()[bucket]?.clear();
          for (final item in [first, fan, jian]) {
            manager.upsertBucketItem(
              bucket,
              provider.unifiedToQuakeMessageForTest(item),
            );
          }
          expect(manager.getAllBuckets()[bucket], hasLength(1));
        }
      },
    );
  }

  test('other agencies, seconds, location and depth do not share identity', () {
    final first = _unitEvent('emsc');
    final seen = _remember(first);
    for (final different in [
      first.copyWith(source: 'whews_geonet'),
      first.copyWith(
        originTime: first.originTime!.add(const Duration(seconds: 1)),
      ),
      first.copyWith(lat: 18.462),
      first.copyWith(lng: 100.994),
      first.copyWith(depth: 10.2),
    ]) {
      final incoming = different.copyWith(
        eventId: 'unit-other-id',
        origin: 1,
        apiTypeLabel: 'FAN',
      );
      expect(catalogCanonicalEventId(incoming, seen), incoming.eventId);
      expect(hasSeenCatalogReport(incoming, seen), isFalse);
    }
    for (final invalid in [
      first.copyWith(depth: -1),
      first.copyWith(lat: double.nan),
      first.copyWith(lat: 0, lng: 0),
      first.copyWith(isEew: true),
    ]) {
      expect(catalogReportKeys(invalid), isEmpty);
    }
    expect(
      () => catalogReportKeys(first.copyWith(magnitude: double.nan)).toList(),
      returnsNormally,
    );
    expect(internationalCatalogSource('jmaEew'), isNull);
    expect(internationalCatalogSource('cwaEqlist'), isNull);
    expect(internationalCatalogSource('cencEqlist'), isNull);
  });

  test(
    'EMSC and GeoNet both display and notify, never cross-agency dedup',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final first = _unitEvent('emsc');
      final second = first.copyWith(source: 'whews_geonet');
      var notifications = 0;
      provider.onUnifiedEventNotified = (_, _) => notifications++;
      for (final event in [first, second]) {
        provider.handleUnifiedEventForTest(event);
        expect(
          processor.process(event).type,
          BackgroundEventResultType.newEvent,
        );
      }
      expect(provider.unifiedEvents, hasLength(2));
      expect(notifications, 2);
    },
  );

  test(
    'foreground restart suppresses a FAN alias with a new magnitude',
    () async {
      final event = _unitEvent('emsc');
      final first = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.handleUnifiedEventForTest(event);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      first.dispose();
      final restarted = QuakeProvider();
      addTearDown(restarted.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      restarted.handleUnifiedEventForTest(
        event.copyWith(
          eventId: 'unit-fan-alias',
          origin: 1,
          apiTypeLabel: 'FAN',
          magnitude: 4.3,
        ),
      );
      expect(restarted.unifiedEvents, isEmpty);
    },
  );

  for (final reverse in [false, true]) {
    test(
      'FAN/Jian equal publication time updates silently, reverse=$reverse',
      () async {
        final provider = QuakeProvider();
        addTearDown(provider.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
        final fan = _unitEvent(
          'emsc',
        ).copyWith(origin: 1, eventId: 'unit-fan-emsc', apiTypeLabel: 'FAN');
        final jian = fan.copyWith(
          origin: 4,
          eventId: 'unit-jian-emsc',
          apiTypeLabel: 'Jian Project',
          magnitude: 4.3,
        );
        final events = reverse ? [jian, fan] : [fan, jian];
        var notifications = 0;
        provider.onUnifiedEventNotified = (_, _) => notifications++;
        provider.handleUnifiedEventForTest(events.first);
        expect(
          processor.process(events.first).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(events.last);
        expect(
          processor.process(events.last).type,
          BackgroundEventResultType.update,
        );
        expect(provider.unifiedEvents.single.eventId, events.last.eventId);
        expect(provider.unifiedEvents.single.magnitude, events.last.magnitude);
        expect(notifications, 1);
      },
    );
  }
}

// Synthetic lifecycle fixture, separate from the unchanged wire captures above.
UnifiedQuakeData _unitEvent(String source) {
  final now = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
  final time = DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
    now.second,
  );
  return UnifiedQuakeData(
    source: source,
    origin: 3,
    eventId: 'unit-whews-id',
    isEew: false,
    timeZone: 0,
    titleText: 'Unit catalog',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '6',
    className: 'yellow',
    hypocenter: 'Unit location',
    originTime: time,
    reportTime: time,
    magnitude: 4.1,
    depth: 10,
    lat: 18.46,
    lng: 100.992,
    apiTypeLabel: 'WHEWS',
  );
}
