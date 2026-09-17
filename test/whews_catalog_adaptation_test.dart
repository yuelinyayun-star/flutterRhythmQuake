import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/whews_catalog.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/utils/catalog_location.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  for (final frame in examples) {
    final source = frame['source'] as String;
    test(
      'official $source frame is parsed unchanged with UTC+8 and Chinese voice',
      () {
        final raw = Map<String, dynamic>.from(frame['Data'] as Map);
        final original = jsonEncode(raw);
        final event = QuakeEventAdapter.convertWhews(source, raw)!;
        final type = whewsCatalogSources[event.source]!;
        expect(jsonEncode(raw), original);
        expect(event.isEew, isFalse);
        expect(event.origin, WhewsService.adapterOrigin);
        expect(event.apiTypeLabel, 'WHEWS');
        expect(event.timeZone, 8);
        expect(event.eventId, raw['id'].toString());
        expect(event.lat, raw['latitude']);
        expect(event.lng, raw['longitude']);
        expect(event.magnitude, raw['magnitude']);
        expect(event.depth, raw['depth']);
        final shock = DateTime.parse(raw['shockTime'] as String);
        expect(event.originTime, shock);
        expect(
          QuakeTime.wallClockToUtc(event.originTime!, const Duration(hours: 8)),
          DateTime.utc(
            shock.year,
            shock.month,
            shock.day,
            shock.hour,
            shock.minute,
            shock.second,
          ).subtract(const Duration(hours: 8)),
        );
        expect(event.reportTime, DateTime.parse(raw['updateTime'] as String));
        expect(event.hypocenter, matches(RegExp(r'[\u4e00-\u9fff]')));
        final voice = AlertVoiceHelper.generateUnifiedEventText(
          event,
          phase: 'first',
        );
        expect(voice, contains(type.displayName));
        expect(voice, contains(event.hypocenter));
        expect(voice, isNot(contains('whews_')));
        expect(event.reportNumText, isNot(anyOf('ML', 'L', 'Mw')));
        expect(QuakeProvider.infoMagFilterSources, contains(type));
      },
    );
  }

  // Explicit lifecycle scenarios, not altered captures or live observations.
  for (final entry in whewsCatalogSources.entries) {
    test(
      '${entry.key} foreground/background filters, expiry and replay agree',
      () async {
        final provider = QuakeProvider();
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          provider.dispose();
        });
        final event = scenario(entry.key);
        var notifications = 0;
        provider.onUnifiedEventNotified = (_, _) => notifications++;
        expect(provider.unifiedSourceTypeForTest(event), entry.value);
        final processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
        provider.handleUnifiedEventForTest(event);
        expect(provider.unifiedEvents.single.source, entry.key);
        expect(
          processor.process(event).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(event);
        expect(provider.unifiedEvents, hasLength(1));
        expect(
          processor.process(event).type,
          BackgroundEventResultType.dropped,
        );
        expect(notifications, 1);
        final correction = event.copyWith(magnitude: 4.1);
        final acceptedCorrection = processor.process(correction);
        expect(acceptedCorrection.type, BackgroundEventResultType.update);
        provider.handleUnifiedEventForTest(acceptedCorrection.event!);
        expect(provider.unifiedEvents.single.magnitude, 4.1);
        expect(notifications, 1);
        expect(
          processor.process(correction).type,
          BackgroundEventResultType.dropped,
        );

        final disabled = BackgroundEventProcessor(
          sourceInfoMagFilters: {'source_mag_filter_${entry.value.name}': -1},
        );
        provider.setSourceInfoMagFilter(entry.value, -1);
        final next = scenario(entry.key, id: 'disabled-scenario');
        provider.handleUnifiedEventForTest(next);
        expect(provider.unifiedEvents.single.eventId, event.eventId);
        expect(disabled.process(next).type, BackgroundEventResultType.dropped);
        expect(
          provider.historyList.where((e) => e.source == entry.value),
          isEmpty,
        );

        provider.setSourceInfoMagFilter(entry.value, 5);
        final filtered = scenario(entry.key, id: 'below-threshold-scenario');
        provider.handleUnifiedEventForTest(filtered);
        expect(provider.unifiedEvents.single.eventId, event.eventId);
        expect(
          BackgroundEventProcessor(
            sourceInfoMagFilters: {'source_mag_filter_${entry.value.name}': 5},
          ).process(filtered).type,
          BackgroundEventResultType.dropped,
        );

        provider.setSourceInfoMagFilter(entry.value, 0);
        final expired = scenario(
          entry.key,
          id: 'expired-scenario',
          age: const Duration(days: 10),
        );
        provider.handleUnifiedEventForTest(expired);
        expect(provider.unifiedEvents.single.eventId, event.eventId);
        expect(
          processor.process(expired).type,
          BackgroundEventResultType.dropped,
        );
        expect(
          provider.historyBySource[entry.key]!.any(
            (e) => e.eventId == expired.eventId,
          ),
          isTrue,
        );
        expect(provider.unifiedToQuakeMessageForTest(event).maxIntensity, 4);
        expect(notifications, 1);
      },
    );
  }

  test('null coordinates stay unmapped; Chinese locations are preserved', () {
    expect(catalogDisplayLocation('Near Zurich', null, 8.54), 'Near Zurich');
    expect(catalogDisplayLocation('Near Zurich', 0, 0), 'Near Zurich');
    expect(
      catalogDisplayLocation('Near Zurich', double.nan, 8.54),
      'Near Zurich',
    );
    expect(catalogDisplayLocation('四川省成都市', 30.6, 104.1), '四川省成都市');
    final event = QuakeEventAdapter.convertWhews('bgs', {
      'id': 'missing-coordinates-scenario',
      'latitude': 999,
      'longitude': 1,
      'placeName': 'NORWICH, NORFOLK',
      'shockTime': '',
      'updateTime': '',
    })!;
    expect(event.lat, isNull);
    expect(event.lng, isNull);
    expect(event.originTime, isNull);
    expect(event.reportTime, isNull);
    expect(
      BackgroundEventProcessor(sourceInfoMagFilters: {}).process(event).type,
      BackgroundEventResultType.dropped,
    );
  });

  test(
    'empty compatibility fields do not mask documented time, id or name',
    () {
      final event = QuakeEventAdapter.convertWhews('bgs', {
        'id': 'bgs_20260723101500',
        'eventId': '',
        'originTime': '',
        'reportTime': '',
        'location': '',
        'placeName': 'NORWICH, NORFOLK',
        'shockTime': '2026-07-23 18:15:00',
        'updateTime': '2026-07-23 18:15:00',
        'longitude': 1.29,
        'latitude': 52.63,
        'magnitude': 2.4,
        'depth': 8,
        'maxIntensity': 'Ⅳ',
      })!;
      expect(event.eventId, 'bgs_20260723101500');
      expect(event.originTime, DateTime(2026, 7, 23, 18, 15));
      expect(event.reportTime, event.originTime);
      expect(event.hypocenter, isNotEmpty);
      expect(event.maxIntensity, '4');
    },
  );

  test(
    'each official source survives aggregate dispatch and exact replay is ignored',
    () async {
      final received = <UnifiedQuakeData>[];
      final service = WhewsService(apiToken: 'test-only');
      addTearDown(service.dispose);
      final subscription = service.onUnifiedEvent.listen(received.add);
      addTearDown(subscription.cancel);
      service.handleMessageForTesting(examples);
      service.handleMessageForTesting(examples);
      await Future<void>.delayed(Duration.zero);
      expect(received.length, examples.length);
      expect(received.map((e) => e.source).toSet().length, examples.length);
    },
  );

  test('catalog bucket revisions cannot roll back a newer history item', () {
    final manager = EqlistManager();
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final newer = scenario('whews_bgs', id: 'history-order-scenario');
    final older = newer.copyWith(
      reportTime: newer.reportTime!.subtract(const Duration(seconds: 1)),
      magnitude: 2,
    );
    manager.upsertBucketItem(
      newer.source,
      provider.unifiedToQuakeMessageForTest(newer),
    );
    manager.upsertBucketItem(
      older.source,
      provider.unifiedToQuakeMessageForTest(older),
    );
    expect(
      manager
          .getAllBuckets()[newer.source]!
          .firstWhere((e) => e.eventId == newer.eventId)
          .magnitude,
      4,
    );
  });

  test(
    'unrecognized sources remain opt-in rather than impersonating an agency',
    () {
      final event = QuakeEventAdapter.convertWhews('unregistered_test_source', {
        'id': 'unregistered-scenario',
        'title': 'Test institution',
      })!;
      expect(
        BackgroundEventProcessor(sourceInfoMagFilters: {}).process(event).type,
        BackgroundEventResultType.dropped,
      );
    },
  );
}

UnifiedQuakeData scenario(
  String source, {
  String id = 'lifecycle-scenario',
  Duration age = Duration.zero,
}) {
  final utc = DateTime.now().toUtc().add(const Duration(hours: 8));
  final wallClock = DateTime(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
  return UnifiedQuakeData(
    source: source,
    origin: WhewsService.adapterOrigin,
    eventId: id,
    isEew: false,
    timeZone: 8,
    titleText: '生命周期测试情报',
    reportNumText: '',
    useShindo: false,
    maxIntensity: 'IV',
    className: 'green',
    hypocenter: '测试地点',
    originTime: wallClock.subtract(age),
    reportTime: wallClock,
    magnitude: 4,
    depth: 10,
    depthText: '10km',
    lat: 52.63,
    lng: 1.29,
    apiTypeLabel: 'WHEWS',
  );
}
