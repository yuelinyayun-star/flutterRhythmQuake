import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });

  tearDown(() => SoundEffectService().enabled = true);

  test('disabled volcano push blocks direct and background-accepted events', () async {
    final provider = QuakeProvider(jmaVolcanoPushEnabled: false);
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final effects = <UnifiedQuakeData>[];
    provider.onUnifiedEventNotified = (event, _) => effects.add(event);
    final event = _whewsVolcanoPush();
    provider.handleUnifiedEventForTest(event);
    provider.handleUnifiedEventForTest(event, alreadyAccepted: true);
    expect(provider.unifiedEvents, isEmpty);
    expect(provider.currentUnifiedEvent, isNull);
    expect(effects, isEmpty);
  });

  test('disabling removes volcano cards without changing selected earthquake', () async {
    final provider = QuakeProvider(jmaVolcanoPushEnabled: true);
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final quake = _whewsInfo(
      eventId: 'quake-remains-visible', reportTime: _sourceLocalNow(8),
    );
    provider.handleUnifiedEventForTest(quake);
    provider.handleUnifiedEventForTest(_whewsVolcanoPush());
    expect(provider.unifiedEvents, hasLength(2));
    provider.setCurrentUnifiedIndex(provider.unifiedEvents.indexWhere(
      (event) => event.eventId == quake.eventId,
    ));
    await provider.setJmaVolcanoPushEnabled(false);
    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.currentUnifiedEvent!.eventId, quake.eventId);
    expect(provider.currentUnifiedIndex, 0);
    expect((await SharedPreferences.getInstance()).getBool(
      QuakeProvider.jmaVolcanoPushEnabledPreferenceKey,
    ), isFalse);
    await provider.setJmaVolcanoPushEnabled(true);
    expect(provider.unifiedEvents, hasLength(1));
    provider.handleUnifiedEventForTest(
      _whewsVolcanoPush().copyWith(eventId: 'next-volcano-report'),
    );
    expect(provider.unifiedEvents.any((event) => event.isVolcanoEvent), isTrue);
  });

  test('disabling the only volcano clears current focus and carousel', () async {
    final provider = QuakeProvider(jmaVolcanoPushEnabled: true);
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.handleUnifiedEventForTest(_whewsVolcanoPush());
    expect(provider.currentUnifiedEvent!.isVolcanoEvent, isTrue);
    var expired = 0;
    provider.onAllEventsExpired = () => expired++;
    await provider.setJmaVolcanoPushEnabled(false);
    expect(provider.unifiedEventCount, 0);
    expect(provider.currentUnifiedIndex, 0);
    expect(provider.currentUnifiedEvent, isNull);
    expect(expired, 1);
  });

  test('saved volcano switch restores without altering the overlay preference', () async {
    SharedPreferences.setMockInitialValues({
      QuakeProvider.jmaVolcanoPushEnabledPreferenceKey: false,
      'map_overlay_volcanoLayer': true,
    });
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(provider.jmaVolcanoPushEnabled, isFalse);
    provider.handleUnifiedEventForTest(_whewsVolcanoPush());
    expect(provider.unifiedEvents, isEmpty);
    expect((await SharedPreferences.getInstance()).getBool(
      'map_overlay_volcanoLayer',
    ), isTrue);
  });

  test('background volcano filtering updates without replacing the processor', () {
    final processor = BackgroundEventProcessor(
      sourceInfoMagFilters: const {}, jmaVolcanoPushEnabled: false,
    );
    final volcano = _whewsVolcanoPush();
    expect(processor.process(volcano).type, BackgroundEventResultType.dropped);
    expect(processor.process(_whewsInfo(
      eventId: 'background-quake', reportTime: _sourceLocalNow(8),
    )).type, BackgroundEventResultType.newEvent);
    processor.jmaVolcanoPushEnabled = true;
    expect(processor.process(volcano).type, BackgroundEventResultType.newEvent);
    processor.jmaVolcanoPushEnabled = false;
    expect(processor.process(volcano.copyWith(
      eventId: 'later-volcano-report',
    )).type, BackgroundEventResultType.dropped);
  });

  test('expired WHEWS information never enters the current UI', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });

    provider.handleUnifiedEventForTest(
      _whewsInfo(
        eventId: '20260722-old-emsc',
        reportTime: _sourceLocalNow(8).subtract(const Duration(days: 15)),
      ),
    );

    expect(provider.unifiedEvents, isEmpty);
    await Future<void>.delayed(Duration.zero);
  });

  test('background notifications reject the same expired WHEWS event', () {
    final processor = BackgroundEventProcessor(sourceInfoMagFilters: const {});
    final result = processor.process(
      _whewsInfo(
        eventId: '20260722-old-emsc',
        reportTime: _sourceLocalNow(8).subtract(const Duration(days: 15)),
      ),
    );

    expect(result.type, BackgroundEventResultType.dropped);
  });

  test('recent EMSC revision cannot revive an old WHEWS earthquake', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final now = _sourceLocalNow(8);
    final event = QuakeEventAdapter.convertWhews('emsc', {
      'id': 'old-emsc-with-fresh-revision',
      'magnitude': 5.1,
      'placeName': '中国四川',
      'shockTime': now.subtract(const Duration(hours: 10)).toIso8601String(),
      'updateTime': now.toIso8601String(),
      'longitude': 104.2,
      'latitude': 30.8,
      'depth': 10,
    });
    final processor = BackgroundEventProcessor(sourceInfoMagFilters: const {});

    expect(event, isNotNull);
    expect(event!.apiTypeLabel, 'WHEWS');
    provider.handleUnifiedEventForTest(event);

    expect(provider.unifiedEvents, isEmpty);
    expect(processor.process(event).type, BackgroundEventResultType.dropped);
    await Future<void>.delayed(Duration.zero);
  });

  test('old WHEWS JMA cancel report is rejected before UI entry', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final event = QuakeEventAdapter.convertWhews('jma_eew', {
      'id': 'JMA-CANCEL-OLD',
      'updates': 5,
      'shockTime': '2026-07-01 12:00:00',
      'createTime': '2026-07-01 12:00:10',
      'magnitude': 5.0,
      'cancel': true,
    });

    expect(event, isNotNull);
    provider.handleUnifiedEventForTest(event!);

    expect(provider.unifiedEvents, isEmpty);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'fresh WHEWS information still enters UI and background processing',
    () async {
      final event = _whewsInfo(
        eventId: 'fresh-emsc',
        reportTime: _sourceLocalNow(8),
      );
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );

      provider.handleUnifiedEventForTest(event);

      expect(provider.unifiedEvents, hasLength(1));
      expect(processor.process(event).type, BackgroundEventResultType.newEvent);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'fresh WHEWS volcano information enters unified UI without quake values',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final event = QuakeEventAdapter.convertWhews('va', {
        'id': 'VFVO52_20260807120000_506',
        'kindCode': 'VFVO52',
        'kindName': '喷发相关火山观测报',
        'infoTypeName': '發表',
        'reportTime': _sourceLocalNow(9).toIso8601String(),
        'targetTime': _sourceLocalNow(
          9,
        ).subtract(const Duration(minutes: 1)).toIso8601String(),
        'volcanoName': '桜島',
        'volcanoCode': '506',
        'latitude': 31.5925,
        'longitude': 130.6567,
        'craterName': '南岳山頂火口',
        'headline': '噴火が発生しました。',
      });

      expect(event, isNotNull);
      expect(event!.isVolcanoEvent, isTrue);
      expect(event.magnitude, -1);
      expect(event.depth, -1);

      provider.handleUnifiedEventForTest(event);

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.isVolcanoEvent, isTrue);
      expect(provider.unifiedDismissSecondsForTest(event), 900);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'same-report WHEWS ashfall enrichment updates UI without repeat effects',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final effects = <UnifiedQuakeData>[];
      provider.onUnifiedEventNotified = (event, _) => effects.add(event);
      final reportTime = _sourceLocalNow(9);
      final first = QuakeEventAdapter.convertWhews('va', {
        'id': 'VFVO53_20260807120000_506',
        'updates': 1,
        'kindCode': 'VFVO53',
        'kindName': '降灰预报',
        'infoTypeName': '發表',
        'reportTime': reportTime.toIso8601String(),
        'targetTime': reportTime.toIso8601String(),
        'volcanoName': '桜島',
        'volcanoCode': '506',
        'latitude': 31.5925,
        'longitude': 130.6567,
      });

      expect(first, isNotNull);
      final enriched = first!.copyWith(
        volcanoEvent: first.volcanoEvent!.copyWith(
          ashfallWindows: [
            VolcanoAshfallWindow(
              label: '予報　３時間後',
              startTime: reportTime,
              endTime: reportTime.add(const Duration(hours: 3)),
              items: const [
                VolcanoAshfallItem(
                  phenomenon: '降灰',
                  phenomenonCode: '70',
                  areaNames: ['鹿児島県屋久島町'],
                  areaCodes: ['4650500'],
                  plumeDirection: '西',
                  distanceKm: 100,
                  polygons: [
                    [
                      VolcanoAshfallCoordinate(
                        latitude: 30.1,
                        longitude: 129.2,
                      ),
                      VolcanoAshfallCoordinate(
                        latitude: 30.3,
                        longitude: 129.4,
                      ),
                      VolcanoAshfallCoordinate(
                        latitude: 30.2,
                        longitude: 129.6,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      provider.handleUnifiedEventForTest(first);
      provider.handleUnifiedEventForTest(enriched);

      expect(provider.unifiedEvents, hasLength(1));
      expect(
        provider.unifiedEvents.single.volcanoEvent!.ashfallWindows,
        hasLength(1),
      );
      expect(effects, hasLength(1));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'changed WHEWS revision updates once and exact replay is dropped',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final effects = <UnifiedQuakeData>[];
      provider.onUnifiedEventNotified = (event, _) => effects.add(event);
      final now = _sourceLocalNow(8);
      final first = _whewsInfo(eventId: 'whews-update-1', reportTime: now);
      final update = _whewsInfo(
        eventId: 'whews-update-1',
        reportTime: now.add(const Duration(seconds: 2)),
        magnitude: 4.6,
      );

      provider.handleUnifiedEventForTest(first);
      provider.handleUnifiedEventForTest(update);
      provider.handleUnifiedEventForTest(update);

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.magnitude, 4.6);
      expect(effects, hasLength(2));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('dismissed WHEWS event stays closed after a later revision', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final now = _sourceLocalNow(8);
    final first = _whewsInfo(eventId: 'whews-dismissed-1', reportTime: now);
    final revision = _whewsInfo(
      eventId: 'whews-dismissed-1',
      reportTime: now.add(const Duration(seconds: 3)),
      magnitude: 4.7,
    );

    provider.handleUnifiedEventForTest(first);
    provider.dismissUnifiedEventForTest(first);
    provider.handleUnifiedEventForTest(revision);

    expect(provider.unifiedEvents, isEmpty);
    await Future<void>.delayed(Duration.zero);
  });

  test('a new fingerprint cannot revive an expired WHEWS event', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final expired = _sourceLocalNow(8).subtract(const Duration(hours: 1));

    provider.handleUnifiedEventForTest(
      _whewsInfo(eventId: 'whews-expired-revision', reportTime: expired),
    );
    provider.handleUnifiedEventForTest(
      _whewsInfo(
        eventId: 'whews-expired-revision',
        reportTime: expired.add(const Duration(seconds: 10)),
        magnitude: 4.6,
      ),
    );

    expect(provider.unifiedEvents, isEmpty);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'foreground and background merge FAN and WHEWS identical bodies',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final effects = <UnifiedQuakeData>[];
      provider.onUnifiedEventNotified = (event, _) => effects.add(event);
      final fan = _kmaInfo(origin: 1, apiTypeLabel: 'FAN');
      final whews = fan.copyWith(
        origin: WhewsService.adapterOrigin,
        apiTypeLabel: 'WHEWS',
      );
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );

      provider.handleUnifiedEventForTest(fan);
      provider.handleUnifiedEventForTest(whews);

      expect(provider.unifiedEvents, hasLength(1));
      expect(effects, hasLength(1));
      expect(processor.process(fan).type, BackgroundEventResultType.newEvent);
      expect(processor.process(whews).type, BackgroundEventResultType.dropped);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('FAN and WHEWS same event retain complementary information fields', () {
    final provider = QuakeProvider();
    addTearDown(() => provider.dispose());
    final fan = _kmaInfo(origin: 1, apiTypeLabel: 'FAN');
    final now = fan.reportTime!.add(const Duration(seconds: 1));
    final whews = UnifiedQuakeData(
      source: 'kmaEqlist',
      origin: WhewsService.adapterOrigin,
      eventId: fan.eventId,
      isEew: false,
      timeZone: 8,
      titleText: fan.titleText,
      reportNumText: '',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '',
      originTime: fan.originTime,
      reportTime: now,
      magnitude: -1,
      depth: -1,
      depthText: '',
      lat: null,
      lng: null,
      apiTypeLabel: 'WHEWS',
    );

    provider.handleUnifiedEventForTest(fan);
    provider.handleUnifiedEventForTest(whews);

    expect(provider.unifiedEvents, hasLength(1));
    final merged = provider.unifiedEvents.single;
    expect(merged.apiTypeLabel, 'WHEWS');
    expect(merged.magnitude, fan.magnitude);
    expect(merged.depth, fan.depth);
    expect(merged.hypocenter, fan.hypocenter);
    expect(merged.lat, fan.lat);
    expect(merged.lng, fan.lng);
  });

  test(
    'WHEWS and FAN different IDs for one JMA warning merge by source event',
    () {
      final provider = QuakeProvider();
      addTearDown(() => provider.dispose());
      final originTime = _sourceLocalNow(
        9,
      ).subtract(const Duration(seconds: 5));
      final fan = QuakeEventAdapter.convert('jmaEew', {
        'eventId': 'FAN-JMA-DIFFERENT-ID',
        'updates': 1,
        'infoTypeName': '警報',
        'originTime': originTime.toIso8601String(),
        'location': '熊本県熊本地方',
        'magnitude': 5.2,
        'depth': 10,
        'latitude': 32.60,
        'longitude': 130.70,
        'jmaShindo': '5強',
        'isWarn': true,
      }, 1);
      final whews = QuakeEventAdapter.convertWhews('jma_eew', {
        'id': 'WHEWS-JMA-DIFFERENT-ID',
        'updates': 2,
        'infoTypeName': '警報',
        'shockTime': originTime.toIso8601String(),
        'createTime': _sourceLocalNow(9).toIso8601String(),
        'placeName': '熊本県熊本地方',
        'magnitude': 5.4,
        'depth': 12,
        'latitude': 32.61,
        'longitude': 130.71,
        'epiIntensity': '6弱',
        'isWarn': true,
      });
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );

      expect(fan, isNotNull);
      expect(whews, isNotNull);
      final fanEvent = fan!;
      final whewsEvent = whews!;
      expect(whewsEvent.origin, WhewsService.adapterOrigin);
      expect(whewsEvent.apiTypeLabel, 'WHEWS');

      provider.handleUnifiedEventForTest(fanEvent);
      provider.handleUnifiedEventForTest(whewsEvent);
      provider.handleUnifiedEventForTest(fanEvent);

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.apiTypeLabel, 'WHEWS');
      expect(provider.unifiedEvents.single.reportNumText, '第2報');
      expect(provider.eewHistory, hasLength(1));
      expect(provider.eewHistory.single.reportCount, 2);

      expect(
        processor.process(fanEvent).type,
        BackgroundEventResultType.newEvent,
      );
      expect(
        processor.process(whewsEvent).type,
        BackgroundEventResultType.update,
      );
      expect(
        processor.process(fanEvent).type,
        BackgroundEventResultType.dropped,
      );
    },
  );

  test('background accepts one changed WHEWS revision only', () {
    final processor = BackgroundEventProcessor(sourceInfoMagFilters: const {});
    final now = _sourceLocalNow(8);
    final first = _whewsInfo(eventId: 'background-update-1', reportTime: now);
    final update = _whewsInfo(
      eventId: 'background-update-1',
      reportTime: now.add(const Duration(seconds: 2)),
      magnitude: 4.6,
    );

    expect(processor.process(first).type, BackgroundEventResultType.newEvent);
    expect(processor.process(update).type, BackgroundEventResultType.update);
    expect(processor.process(update).type, BackgroundEventResultType.dropped);
  });

  test(
    'same-second WHEWS body correction is accepted without repeat effects',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final effects = <UnifiedQuakeData>[];
      provider.onUnifiedEventNotified = (event, _) => effects.add(event);
      final now = _sourceLocalNow(8);
      final first = _whewsInfo(eventId: 'same-second-1', reportTime: now);
      final correction = _whewsInfo(
        eventId: 'same-second-1',
        reportTime: now,
        magnitude: 4.6,
      );
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );

      provider.handleUnifiedEventForTest(first);
      provider.handleUnifiedEventForTest(correction);

      expect(provider.unifiedEvents.single.magnitude, 4.6);
      expect(effects, hasLength(1));
      expect(processor.process(first).type, BackgroundEventResultType.newEvent);
      expect(
        processor.process(correction).type,
        BackgroundEventResultType.update,
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'out-of-order WHEWS revision cannot overwrite newer information',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final now = _sourceLocalNow(8);
      final newer = _whewsInfo(
        eventId: 'out-of-order-1',
        reportTime: now,
        magnitude: 4.7,
      );
      final older = _whewsInfo(
        eventId: 'out-of-order-1',
        reportTime: now.subtract(const Duration(seconds: 2)),
        magnitude: 4.6,
      );
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );

      provider.handleUnifiedEventForTest(newer);
      provider.handleUnifiedEventForTest(older);

      expect(provider.unifiedEvents.single.magnitude, 4.7);
      expect(processor.process(newer).type, BackgroundEventResultType.newEvent);
      expect(processor.process(older).type, BackgroundEventResultType.dropped);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('WHEWS CENC content revision inside 30 seconds updates once', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final effects = <UnifiedQuakeData>[];
    provider.onUnifiedEventNotified = (event, _) => effects.add(event);
    final now = _sourceLocalNow(8);
    final first = _whewsCencInfo(
      reportTime: now,
      magnitude: 4.5,
      reviewLabel: '自动测定',
    );
    final revision = _whewsCencInfo(
      reportTime: now.add(const Duration(seconds: 10)),
      magnitude: 4.6,
      reviewLabel: '正式测定',
    );
    final processor = BackgroundEventProcessor(sourceInfoMagFilters: const {});

    provider.handleUnifiedEventForTest(first);
    provider.handleUnifiedEventForTest(revision);

    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.unifiedEvents.single.magnitude, 4.6);
    expect(provider.unifiedEvents.single.reportNumText, '正式测定');
    expect(effects, hasLength(2));
    expect(processor.process(first).type, BackgroundEventResultType.newEvent);
    expect(processor.process(revision).type, BackgroundEventResultType.update);
    expect(processor.process(revision).type, BackgroundEventResultType.dropped);
    await Future<void>.delayed(Duration.zero);
  });

  test('WHEWS ShakeAlert same-report body revision updates in place', () async {
    final provider = QuakeProvider();
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider.dispose();
    });
    final processor = BackgroundEventProcessor(sourceInfoMagFilters: const {});
    final reportTime = _sourceLocalNow(8);
    final originTime = reportTime.subtract(const Duration(seconds: 5));
    final first = QuakeEventAdapter.convertWhews('sa_eew', {
      'id': 'whews-sa-same-report',
      'shockTime': originTime.toIso8601String(),
      'createTime': reportTime.toIso8601String(),
      'placeName': 'California',
      'latitude': 35.0,
      'longitude': -118.0,
      'depth': 10,
      'magnitude': 4.5,
      'maxMmi': 5.0,
    });
    final revision = QuakeEventAdapter.convertWhews('sa_eew', {
      'id': 'whews-sa-same-report',
      'shockTime': originTime.toIso8601String(),
      'createTime': reportTime
          .add(const Duration(seconds: 2))
          .toIso8601String(),
      'placeName': 'California',
      'latitude': 35.02,
      'longitude': -118.01,
      'depth': 12,
      'magnitude': 4.8,
      'maxMmi': 6.0,
    });

    expect(first, isNotNull);
    expect(revision, isNotNull);
    expect(first!.reportNumText, '第1報');
    expect(first.reportTime, reportTime);

    provider.handleUnifiedEventForTest(first);
    provider.handleUnifiedEventForTest(revision!);
    provider.handleUnifiedEventForTest(revision);

    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.unifiedEvents.single.magnitude, 4.8);
    expect(provider.eewHistory, hasLength(1));
    expect(provider.eewHistory.single.reportCount, 1);
    expect(processor.process(first).type, BackgroundEventResultType.newEvent);
    expect(processor.process(revision).type, BackgroundEventResultType.update);
    expect(processor.process(revision).type, BackgroundEventResultType.dropped);
  });
}

UnifiedQuakeData _whewsInfo({
  required String eventId,
  required DateTime reportTime,
  double magnitude = 4.5,
}) {
  return UnifiedQuakeData(
    source: 'emsc',
    origin: WhewsService.adapterOrigin,
    eventId: eventId,
    isEew: false,
    timeZone: 8,
    titleText: 'EMSC 地震情报',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '-',
    className: 'green',
    hypocenter: '所罗门群岛',
    originTime: reportTime.subtract(const Duration(minutes: 1)),
    reportTime: reportTime,
    magnitude: magnitude,
    depth: 27,
    depthText: '深度: 27km',
    lat: -9.0,
    lng: 159.0,
    apiTypeLabel: 'WHEWS',
  );
}

UnifiedQuakeData _kmaInfo({required int origin, required String apiTypeLabel}) {
  final now = _sourceLocalNow(8);
  return UnifiedQuakeData(
    source: 'kmaEqlist',
    origin: origin,
    eventId: 'KMA-CROSS-API-1',
    isEew: false,
    timeZone: 8,
    titleText: '기상청 지진정보',
    reportNumText: '',
    useShindo: false,
    maxIntensity: 'Ⅳ',
    className: 'blue',
    hypocenter: '경상북도',
    originTime: now.subtract(const Duration(minutes: 1)),
    reportTime: now,
    magnitude: 4.2,
    depth: 12,
    depthText: '深度: 12km',
    lat: 36.1,
    lng: 128.2,
    apiTypeLabel: apiTypeLabel,
  );
}

UnifiedQuakeData _whewsCencInfo({
  required DateTime reportTime,
  required double magnitude,
  required String reviewLabel,
}) {
  return UnifiedQuakeData(
    source: 'cencEqlist',
    origin: WhewsService.adapterOrigin,
    eventId: 'CENC-WHEWS-REVISION-1',
    isEew: false,
    timeZone: 8,
    titleText: '中国地震台网地震信息',
    reportNumText: reviewLabel,
    useShindo: false,
    maxIntensity: '-',
    className: 'gray',
    hypocenter: '四川省',
    originTime: reportTime.subtract(const Duration(minutes: 1)),
    reportTime: reportTime,
    magnitude: magnitude,
    depth: 10,
    depthText: '深度: 10km',
    lat: 30,
    lng: 100,
    apiTypeLabel: 'WHEWS',
  );
}

UnifiedQuakeData _whewsVolcanoPush() => QuakeEventAdapter.convertWhews('va', {
  'id': 'VFVO52_20260807120000_506',
  'kindCode': 'VFVO52',
  'kindName': '喷发相关火山观测报',
  'infoTypeName': '發表',
  'reportTime': _sourceLocalNow(9).toIso8601String(),
  'targetTime': _sourceLocalNow(9)
      .subtract(const Duration(minutes: 1)).toIso8601String(),
  'volcanoName': '桜島',
  'volcanoCode': '506',
  'latitude': 31.5925,
  'longitude': 130.6567,
  'craterName': '南岳山頂火口',
  'headline': '噴火が発生しました。',
})!;

DateTime _sourceLocalNow(int timeZone) {
  final utc = DateTime.now().toUtc();
  final source = utc.add(Duration(hours: timeZone));
  return DateTime(
    source.year,
    source.month,
    source.day,
    source.hour,
    source.minute,
    source.second,
    source.millisecond,
    0,
  );
}
