import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/jian_sources.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/whews_catalog.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'all catalog agencies have mapped transports; captures stay unchanged',
    () {
      final rawText = File('test/fixtures/jian/all.json').readAsStringSync();
      final captured = jsonDecode(rawText) as Map;
      final mapped = jianEarthquakeSources.values.toSet();
      expect(unifiedCatalogSources.length, 31);
      expect(whewsCatalogSources.keys.where(mapped.contains), hasLength(16));
      for (final source in unifiedCatalogSources.keys) {
        expect(
          whewsCatalogSources.containsKey(source) || mapped.contains(source),
          isTrue,
          reason: source,
        );
      }
      for (final entry in jianEarthquakeSources.entries) {
        if (!unifiedCatalogSources.containsKey(entry.value)) continue;
        final raw = Map<String, dynamic>.from(
          (captured['source：${entry.key}'] as Map)['Data'] as Map,
        );
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertJian(entry.key, raw)!;
        expect(event.source, entry.value);
        expect(event.eventId, raw['id']);
        expect(jsonEncode(raw), before);
      }
      expect(File('test/fixtures/jian/all.json').readAsStringSync(), rawText);
    },
  );

  test(
    'GeoNet FAN and WHEWS share agency, raw ID, filters and list bucket',
    () {
      final frames =
          jsonDecode(
                File(
                  'test/fixtures/whews_catalog_official_examples.json',
                ).readAsStringSync(),
              )
              as List;
      final raw = Map<String, dynamic>.from(
        (frames.singleWhere((f) => f['source'] == 'geonet') as Map)['Data']
            as Map,
      );
      final before = jsonEncode(raw);
      final fan = QuakeEventAdapter.convert('geonet', raw, 1)!;
      final whews = QuakeEventAdapter.convertWhews('geonet', raw)!;
      expect(fan.source, whews.source);
      expect(fan.source, 'whews_geonet');
      expect(fan.apiTypeLabel, 'FAN');
      expect(fan.origin, 1);
      expect(fan.eventId, raw['id']);
      expect(fan.sourcePayload, raw);
      expect(catalogReportKey(fan), catalogReportKey(whews));
      expect(jsonEncode(raw), before);
    },
  );

  test('INGV scientific ID comparison retains original captured ID', () {
    final captured =
        jsonDecode(File('test/fixtures/jian/all.json').readAsStringSync())
            as Map;
    final raw = Map<String, dynamic>.from(
      (captured['source：ingv'] as Map)['Data'] as Map,
    );
    final event = QuakeEventAdapter.convertJian('ingv', raw)!;
    expect(event.eventId, '4.7176982e+07');
    expect(catalogEventId(event.source, event.eventId), '47176982');
    expect(
      catalogEventId('whews_nrcan', '20260914.0835001'),
      '20260914.0835001',
    );
  });

  test(
    'FAN GeoNet snapshot stays silent and live dispatch uses shared agency',
    () async {
      final received = <UnifiedQuakeData>[];
      final service = FanService();
      final sub = service.onUnifiedEvent.listen(received.add);
      final frames =
          jsonDecode(
                File(
                  'test/fixtures/whews_catalog_official_examples.json',
                ).readAsStringSync(),
              )
              as List;
      final raw =
          (frames.singleWhere((f) => f['source'] == 'geonet') as Map)['Data'];
      for (final type in ['initial', 'update']) {
        service.handleMessageForTesting(
          jsonEncode({'type': type, 'source': 'geonet', 'Data': raw}),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(type == 'initial' ? 0 : 1));
      }
      expect(received.single.source, 'whews_geonet');
      expect(received.single.isSnapshot, isFalse);
      await sub.cancel();
      service.dispose();
    },
  );

  for (final source in unifiedCatalogSources.keys) {
    test(
      '$source: late arrival, cross-ID/API, history, replay and genuine update',
      () async {
        final provider = QuakeProvider();
        addTearDown(provider.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
        final manager = EqlistManager();
        final first = unitScenario(source);
        final second = first.copyWith(
          eventId: 'unit-alternative-api-id',
          origin: 4,
          apiTypeLabel: 'Jian Project',
          titleText: 'Alternative agency title',
          hypocenter: 'Alternative place translation',
          maxIntensity: '6.0',
        );
        var notifications = 0;
        provider.onUnifiedEventNotified = (_, _) => notifications++;
        expect(QuakeTime.catalogInformationRemainingSeconds(first, 300), 300);
        provider.handleUnifiedEventForTest(first);
        final arrival = provider.unifiedEvents.single.arrivedAt;
        expect(
          processor.process(first).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(second);
        expect(
          processor.process(second).type,
          BackgroundEventResultType.dropped,
        );
        expect(provider.unifiedEvents, hasLength(1));
        expect(provider.unifiedEvents.single.arrivedAt, arrival);
        expect(notifications, 1);
        expect(provider.historyBySource[source], hasLength(1));
        for (final event in [first, second]) {
          manager.upsertBucketItem(
            source,
            provider.unifiedToQuakeMessageForTest(event),
          );
        }
        expect(manager.getAllBuckets()[source], hasLength(1));
        final replay = second.copyWith(isHistory: true);
        provider.handleUnifiedEventForTest(replay);
        expect(notifications, 1);
        expect(provider.historyBySource[source], hasLength(1));
        final restarted = BackgroundEventProcessor(
          sourceInfoMagFilters: {},
          seenUnifiedInfoEvents: processor.seenUnifiedInfoEvents,
        );
        expect(
          restarted.process(second).type,
          BackgroundEventResultType.dropped,
        );
        // Same agency ID with revised parameters remains a genuine update.
        final revised = first.copyWith(
          magnitude: 4.5,
          reportTime: first.reportTime!.add(const Duration(seconds: 1)),
        );
        expect(
          processor.process(revised).type,
          BackgroundEventResultType.update,
        );
        provider.handleUnifiedEventForTest(revised);
        expect(provider.unifiedEvents.single.magnitude, 4.5);
        expect(provider.historyBySource[source], hasLength(1));
        manager.upsertBucketItem(
          source,
          provider.unifiedToQuakeMessageForTest(revised),
        );
        expect(manager.getAllBuckets()[source], hasLength(1));
      },
    );
  }

  test(
    'different agencies, nearby events, missing values and real status changes stay distinct',
    () {
      final event = unitScenario('whews_tmd');
      final key = catalogReportKey(event);
      expect(key, isNotNull);
      for (final other in [
        event.copyWith(source: 'whews_bmkg'),
        event.copyWith(
          originTime: event.originTime!.add(const Duration(seconds: 1)),
        ),
        event.copyWith(lat: 18.46001),
        event.copyWith(magnitude: 4.2),
        event.copyWith(isCanceled: true),
        event.copyWith(maxIntensity: '7'),
        event.copyWith(reportNumText: 'reviewed'),
      ]) {
        expect(catalogReportKey(other), isNot(key));
      }
      expect(catalogReportKey(event.copyWith(depth: -1)), isNull);
      expect(catalogReportKey(event.copyWith(lat: double.nan)), isNull);
      expect(catalogReportKey(event.copyWith(isEew: true)), isNull);
    },
  );

  test(
    'foreground restart remembers an alternate transport ID without re-alerting',
    () async {
      final first = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final event = unitScenario('whews_tmd');
      first.handleUnifiedEventForTest(event);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      first.dispose();
      final restarted = QuakeProvider();
      addTearDown(restarted.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      restarted.handleUnifiedEventForTest(
        event.copyWith(eventId: 'unit-alt', origin: 4),
      );
      expect(restarted.unifiedEvents, isEmpty);
    },
  );
}

// Synthetic lifecycle test only, not a modified or claimed live capture.
UnifiedQuakeData unitScenario(String source) {
  final time = DateTime.now().toUtc().subtract(const Duration(minutes: 9));
  return UnifiedQuakeData(
    source: source,
    origin: 3,
    eventId: 'unit-primary-api-id',
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
