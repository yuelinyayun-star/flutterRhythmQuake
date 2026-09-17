import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/models/jian_sources.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/whews_catalog.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/utils/catalog_location.dart';
import 'package:flutterrhythmquake/utils/fe_english_names.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final whewsText = File(
    'test/fixtures/catalog_20260917/whews_all.json',
  ).readAsStringSync();
  final jianText = File(
    'test/fixtures/catalog_20260917/jian_all.json',
  ).readAsStringSync();
  final whews = jsonDecode(whewsText) as List;
  final jian = jsonDecode(jianText) as Map;
  Map<String, dynamic> wRaw(String source) => Map<String, dynamic>.from(
    (whews.singleWhere((e) => e['source'] == source) as Map)['Data'] as Map,
  );
  Map<String, dynamic> jRaw(String source) =>
      Map<String, dynamic>.from((jian['source：$source'] as Map)['Data'] as Map);
  UnifiedQuakeData w(String source) =>
      QuakeEventAdapter.convertWhews(source, wRaw(source))!;
  UnifiedQuakeData j(String source) =>
      QuakeEventAdapter.convertJian(source, jRaw(source))!;
  Map<String, DateTime> remember(UnifiedQuakeData event) => {
    for (final key in catalogReportKeys(event)) key: DateTime.now().toUtc(),
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'unaltered GA wire frames deduplicate in both orders and retain precision',
    () {
      final first = w('ga');
      final second = j('ga');
      expect(first.depth, 33.9);
      expect(second.depth, 34);
      expect(first.lat, -14.3846092224121);
      expect(second.lat, -14.385);
      expect(first.sourcePayload, wRaw('ga'));
      expect(second.sourcePayload, jRaw('ga'));
      expect(catalogReportKey(first), isNot(catalogReportKey(second)));
      expect(hasSeenCatalogReport(second, remember(first)), isTrue);
      expect(hasSeenCatalogReport(first, remember(second)), isTrue);
      expect(
      catalogCanonicalEventId(first, {}),
      catalogCanonicalEventId(second, remember(first)),
      );
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      for (final pair in [
        [first, second],
        [second, first],
      ]) {
        final a = provider.unifiedToQuakeMessageForTest(pair[0]);
        final b = provider.unifiedToQuakeMessageForTest(pair[1]);
        expect(sameCatalogHistoryEvent('whews_ga', a, b), isTrue);
        EqlistManager().upsertBucketItem('whews_ga', a);
        EqlistManager().upsertBucketItem('whews_ga', b);
        expect(EqlistManager().getAllBuckets()['whews_ga'], hasLength(1));
        expect(EqlistManager().getAllBuckets()['whews_ga']!.single.depth, 33.9);
      }
      expect(
        File(
          'test/fixtures/catalog_20260917/whews_all.json',
        ).readAsStringSync(),
        whewsText,
      );
      expect(
        File('test/fixtures/catalog_20260917/jian_all.json').readAsStringSync(),
        jianText,
      );
    },
  );

  test(
    'GA tolerance never applies to other agencies, seconds or changed alert states',
    () {
      final first = w('ga');
      final second = j('ga');
      final seen = remember(first);
      for (final different in [
        second.copyWith(source: 'whews_mmd'),
        second.copyWith(
          originTime: second.originTime!.add(const Duration(seconds: 1)),
        ),
        second.copyWith(lat: -14.386),
        second.copyWith(depth: 35),
        second.copyWith(magnitude: 5.4),
        second.copyWith(maxIntensity: '7'),
        second.copyWith(isCanceled: true),
        second.copyWith(isWarn: true),
        second.copyWith(isFinal: true),
        second.copyWith(reportNumText: '自动'),
      ]) {
        expect(hasSeenCatalogReport(different, seen), isFalse);
      }
      // A same-transport revision must not be rounded away.
      seen.addAll(remember(second));
      expect(hasSeenCatalogReport(first.copyWith(depth: 33.8), seen), isFalse);
      expect(
        hasSeenCatalogReport(second.copyWith(reportNumText: '自动'), seen),
        isFalse,
      );
    },
  );

  test(
    'captured MMD PHIVOLCS SSN already match exactly; other shared IDs agree',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      for (final source in ['mmd', 'phivolcs', 'ssn', 'nrcan', 'sed', 'noa']) {
        final first = w(source);
        final second = j(source);
        expect(
          sameCatalogHistoryEvent(
            first.source,
            provider.unifiedToQuakeMessageForTest(first),
            provider.unifiedToQuakeMessageForTest(second),
          ),
          isTrue,
          reason: source,
        );
      }
      expect(catalogEventId('whews_gsras', 'gsras_20263842'), '20263842');
      expect(catalogEventId('whews_ga', 'gsras_20263842'), 'gsras_20263842');
    },
  );

  test(
    'actual GSRAS zero coordinates produce Chinese text, not a invented epicenter',
    () {
      final event = w('gsras');
      expect(wRaw('gsras')['placeName'], 'Tonga Islands');
      expect(wRaw('gsras')['latitude'], 0);
      expect(event.lat, isNull);
      expect(event.lng, isNull);
      expect(event.hypocenter, '汤加群岛');
      expect(event.sourcePayload, wRaw('gsras'));
      final voice = AlertVoiceHelper.generateUnifiedEventText(
        event,
        phase: 'first',
      );
      expect(voice, contains('汤加群岛'));
      expect(voice, isNot(contains('Tonga')));
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      expect(provider.unifiedToQuakeMessageForTest(event).location, '汤加群岛');
    },
  );

  test(
    'all 757 FE labels translate without inventing coordinates or unknown names',
    () {
      expect(feEnglishNames, hasLength(757));
      for (final name in feEnglishNames) {
        expect(
          translateFERegionName(name),
          matches(RegExp(r'[\u4e00-\u9fff]')),
          reason: name,
        );
      }
      expect(catalogDisplayLocation(' tonga   islands ', null, null), '汤加群岛');
      expect(catalogDisplayLocation('KURIL ISLANDS', 0, 0), '千岛群岛');
      expect(
        catalogDisplayLocation('Not a known region', null, null),
        'Not a known region',
      );
      expect(catalogDisplayLocation('四川省成都市', null, null), '四川省成都市');
      expect(translateFERegionName('CENTRAL ALASKA'), '阿拉斯加州中部');
      expect(
        translateFERegionName('GALAPAGOS TRIPLE JUNCTION REGION'),
        '加拉帕戈斯三角洲地区',
      );
    },
  );

  test(
    'every captured international adapter emits Chinese and preserves original maps',
    () {
      for (final frame in whews.whereType<Map>()) {
        final source = frame['source'] as String;
        if (!whewsCatalogSources.containsKey('whews_$source')) continue;
        final raw = wRaw(source);
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertWhews(source, raw)!;
        expect(
          event.hypocenter,
          matches(RegExp(r'[\u4e00-\u9fff]')),
          reason: source,
        );
        expect(jsonEncode(raw), before);
      }
      for (final entry in jianEarthquakeSources.entries) {
        if (!unifiedCatalogSources.containsKey(entry.value)) continue;
        final raw = jRaw(entry.key);
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertJian(entry.key, raw)!;
        expect(
          event.hypocenter,
          matches(RegExp(r'[\u4e00-\u9fff]')),
          reason: entry.key,
        );
        expect(jsonEncode(raw), before);
      }
    },
  );

  // Synthetic lifecycle scenarios only. Captured timestamps above stay intact.
  for (final reverse in [false, true]) {
    test(
      'GA foreground/background/restart no re-alert, reverse=$reverse',
      () async {
        final provider = QuakeProvider();
        addTearDown(provider.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final now = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
        final first = UnifiedQuakeData(
          source: 'whews_ga',
          origin: 3,
          eventId: 'ga2026test',
          isEew: false,
          timeZone: 0,
          titleText: 'Unit catalog',
          reportNumText: '正式',
          useShindo: false,
          maxIntensity: '6',
          className: 'yellow',
          hypocenter: '测试区域',
          originTime: now,
          reportTime: now,
          magnitude: 5.3,
          depth: 33.9,
          lat: 10.12349,
          lng: 20.98761,
          apiTypeLabel: 'WHEWS',
        );
        final second = first.copyWith(
          origin: 4,
          eventId: 'ga_2026-09-17_06:42:42_10.123_20.988',
          apiTypeLabel: 'Jian Project',
          lat: 10.123,
          lng: 20.988,
          depth: 34,
          reportNumText: '',
        );
        final pair = reverse ? [second, first] : [first, second];
        final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
        var notifications = 0;
        provider.onUnifiedEventNotified = (_, _) => notifications++;
        provider.handleUnifiedEventForTest(pair[0]);
        final arrived = provider.unifiedEvents.single.arrivedAt;
        expect(
          background.process(pair[0]).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(pair[1]);
        expect(
          background.process(pair[1]).type,
          BackgroundEventResultType.dropped,
        );
        expect(notifications, 1);
        expect(provider.unifiedEvents, hasLength(1));
        expect(provider.unifiedEvents.single.arrivedAt, arrived);
        final restarted = BackgroundEventProcessor(
          sourceInfoMagFilters: {},
          seenUnifiedInfoEvents: background.seenUnifiedInfoEvents,
        );
        expect(
          restarted.process(pair[1]).type,
          BackgroundEventResultType.dropped,
        );
        final revision = pair[1].copyWith(
          magnitude: 5.5,
          reportTime: now.add(const Duration(seconds: 1)),
        );
        expect(
          background.process(revision).type,
          BackgroundEventResultType.update,
        );
        provider.handleUnifiedEventForTest(revision);
        expect(provider.unifiedEvents.single.magnitude, 5.5);
        expect(provider.unifiedEvents.single.eventId, revision.eventId);
        expect(provider.unifiedEvents.single.arrivedAt, arrived);
      },
    );
  }
}
