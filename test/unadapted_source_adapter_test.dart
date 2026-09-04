import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> geonetPayload({
    String? title,
    String? source,
    String? api,
  }) {
    return {
      'id': 'geonet-1',
      'placeName': '35 km south-west of Tokoroa',
      'magnitude': 1.5,
      'depth': 192,
      'latitude': -38.3,
      'longitude': 175.8,
      'shockTime': '2026-08-17 09:53:29',
      'createTime': '2026-08-17 09:53:40',
      if (source != null) 'source': source,
      if (api != null) 'api': api,
      if (title != null) 'title': title,
    };
  }

  test('unadapted FAN payloads use title field and transport API badge', () {
    final event = QuakeEventAdapter.convertUnadapted(
      apiName: 'geonet',
      origin: 1,
      data: geonetPayload(title: '新西兰 GeoNet 地震信息'),
    );

    expect(event.source, 'unadapted_geonet');
    expect(event.titleText, '新西兰 GeoNet 地震信息');
    expect(event.apiTypeLabel, 'FAN');
    expect(event.hypocenter, '35 km south-west of Tokoroa');
    expect(event.magnitude, 1.5);
    expect(event.titleText, isNot(contains('中国地震台网')));
    expect(event.apiTypeLabel, isNot('geonet'));
  });

  test(
    'unadapted payloads keep transport API badge when catalog is present',
    () {
      final event = QuakeEventAdapter.convertUnadapted(
        apiName: 'FAN',
        origin: 1,
        data: geonetPayload(source: 'geonet', title: '新西兰 GeoNet 地震信息'),
      );

      expect(event.apiTypeLabel, 'FAN');
      expect(event.titleText, '新西兰 GeoNet 地震信息');
      expect(event.apiTypeLabel, isNot('geonet'));
    },
  );

  test(
    'unadapted FAN payloads leave title empty when title field is missing',
    () {
      final event = QuakeEventAdapter.convertUnadapted(
        apiName: 'geonet',
        origin: 1,
        data: geonetPayload(),
      );

      expect(event.titleText, isEmpty);
      expect(event.apiTypeLabel, 'FAN');
      expect(event.titleText, isNot('geonet'));
    },
  );

  test(
    'unknown convert() sources no longer become CENC or FAN title defaults',
    () {
      final event = QuakeEventAdapter.convert('customfeed', geonetPayload(), 1);

      expect(event, isNotNull);
      expect(event!.source, 'unadapted_customfeed');
      expect(event.titleText, isEmpty);
      expect(event.apiTypeLabel, 'FAN');
      expect(event.titleText, isNot(contains('中国地震台网')));
      expect(event.apiTypeLabel, isNot('geonet'));
    },
  );

  test(
    'FAN GeoNet payload uses its dedicated adapter and UTC+8 wall clock',
    () {
      final event = QuakeEventAdapter.convert('geonet', geonetPayload(), 1);

      expect(event, isNotNull);
      expect(event!.source, 'geonet');
      expect(event.titleText, '新西兰地球科学局地震信息');
      expect(event.apiTypeLabel, 'FAN');
      expect(event.timeZone, 8);
      expect(event.originTime, DateTime(2026, 8, 17, 9, 53, 29));
      expect(event.hypocenter, '35 km south-west of Tokoroa');
      expect(event.lat, -38.3);
      expect(event.lng, 175.8);
      expect(event.depth, 192);
      expect(event.magnitude, 1.5);
    },
  );

  test('FAN GeoNet null magnitude and depth remain unknown', () {
    final event = QuakeEventAdapter.convert('geonet', {
      ...geonetPayload(),
      'magnitude': null,
      'depth': null,
    }, 1);

    expect(event, isNotNull);
    expect(event!.magnitude, -1);
    expect(event.depth, -1);
    expect(event.depthText, isEmpty);
    expect(event.maxIntensity, '-');
  });

  test(
    'FAN and WHEWS GeoNet keep their transport API labels after mapping',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      final fan = QuakeEventAdapter.convert('geonet', geonetPayload(), 1)!;
      final whews = QuakeEventAdapter.convertWhews('geonet', geonetPayload())!;

      expect(provider.unifiedToQuakeMessageForTest(fan).apiTypeLabel, 'FAN');
      expect(
        provider.unifiedToQuakeMessageForTest(whews).apiTypeLabel,
        'WHEWS',
      );
    },
  );

  test('FAN GeoNet enters foreground and background magnitude filtering', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = QuakeEventAdapter.convert('geonet', geonetPayload(), 1)!;

    expect(provider.unifiedSourceTypeForTest(event), QuakeSourceType.geonet);
    expect(provider.passesInfoMagnitudeFilterForTest(event, 2.0), isFalse);
    expect(provider.passesInfoMagnitudeFilterForTest(event, 1.0), isTrue);

    final background = BackgroundEventProcessor(
      sourceInfoMagFilters: const {'source_mag_filter_geonet': 2.0},
    );
    expect(background.process(event).type, BackgroundEventResultType.dropped);
  });

  test('unknown WHEWS sources use title field and WHEWS badge', () {
    final event = QuakeEventAdapter.convertWhews('newagency', {
      ...geonetPayload(title: 'New Agency 地震信息'),
      'updateTime': '2026-08-17 09:53:40',
    });

    expect(event, isNotNull);
    expect(event!.source, 'whews_newagency');
    expect(event.titleText, 'New Agency 地震信息');
    expect(event.apiTypeLabel, 'WHEWS');
    expect(event.apiTypeLabel, isNot('newagency'));
    expect(event.titleText, isNot(contains('中国地震台网')));
  });

  test(
    'unadapted sources are rejected by default in background processing',
    () {
      final now = DateTime.now();
      final event = QuakeEventAdapter.convertWhews('newagency', {
        ...geonetPayload(title: 'New Agency 地震信息'),
        'shockTime': now.toString(),
        'createTime': now.toString(),
        'updateTime': now.add(const Duration(seconds: 1)).toString(),
      })!;

      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      expect(processor.process(event).type, BackgroundEventResultType.dropped);

      final explicitlyEnabled = BackgroundEventProcessor(
        sourceInfoMagFilters: const {'source_mag_filter_unadapted': 0},
      );
      expect(
        explicitlyEnabled.process(event).type,
        BackgroundEventResultType.newEvent,
      );
    },
  );

  test(
    'unadapted WHEWS title follows the same title field as adapted generic',
    () {
      const payloadTitle = 'Agency Title From Payload';
      final payload = {
        ...geonetPayload(title: payloadTitle),
        'updateTime': '2026-08-17 09:53:40',
      };

      final unadapted = QuakeEventAdapter.convertWhews('newagency', payload);
      final adapted = QuakeEventAdapter.convertWhews('geonet', payload);

      expect(unadapted!.titleText, payloadTitle);
      expect(adapted!.titleText, payloadTitle);
    },
  );

  test('unadapted direct HTTP uses title field as API badge', () {
    final event = QuakeEventAdapter.convertUnadapted(
      apiName: 'customfeed',
      origin: 99,
      data: geonetPayload(title: 'Custom Agency 地震信息'),
    );

    expect(event.titleText, 'Custom Agency 地震信息');
    expect(event.apiTypeLabel, 'Custom Agency 地震信息');
    expect(event.apiTypeLabel, isNot('FAN'));
  });

  test('unadapted direct HTTP leaves API badge empty without title', () {
    final event = QuakeEventAdapter.convertUnadapted(
      apiName: 'customfeed',
      origin: 99,
      data: geonetPayload(),
    );

    expect(event.titleText, isEmpty);
    expect(event.apiTypeLabel, isEmpty);
    expect(event.apiTypeLabel, isNot('customfeed'));
  });

  test(
    'already-adapted WHEWS GeoNet keeps its dedicated title and WHEWS badge',
    () {
      final event = QuakeEventAdapter.convertWhews('geonet', geonetPayload());

      expect(event, isNotNull);
      expect(event!.source, 'whews_geonet');
      expect(event.apiTypeLabel, 'WHEWS');
      expect(event.titleText, '新西兰地球科学局地震信息');
    },
  );

  test('adapted CENC FAN events still use the CENC title and FAN badge', () {
    final event = QuakeEventAdapter.convert('cencEqlist', {
      'eventId': 'cenc-1',
      'placeName': '四川甘孜州',
      'magnitude': 4.2,
      'depth': 10,
      'latitude': 30.1,
      'longitude': 101.2,
      'shockTime': '2026-08-17 09:00:00',
      'createTime': '2026-08-17 09:01:00',
      'type': '正式测定',
    }, 1);

    expect(event, isNotNull);
    expect(event!.source, 'cencEqlist');
    expect(event.titleText, '中国地震台网地震信息');
    expect(event.apiTypeLabel, 'FAN');
  });

  test('adapted sources keep dedicated titles and aggregator badges', () {
    const adapted = <(String, int, String, String)>[
      ('cencEqlist', 1, '中国地震台网地震信息', 'FAN'),
      ('usgsEqlist', 1, 'USGS 地震情报', 'FAN'),
      ('hko', 1, '香港天文台地震情报', 'FAN'),
      ('emsc', 1, 'EMSC 地震情报', 'FAN'),
      ('guangxi', 1, '广西地震局地震信息', 'FAN'),
      ('shanxi', 1, '山西地震局地震信息', 'FAN'),
      ('fssnEqlist', 1, 'FSSN 地震情报', 'FAN'),
      ('cwaEqlist', 1, '中央氣象署 地震報告', 'FAN'),
      ('ceaEew', 1, '中国地震预警网地震预警', 'FAN'),
    ];
    final payload = {
      'eventId': 'adapted-1',
      'placeName': '测试地点',
      'location': '测试地点',
      'magnitude': 4.2,
      'depth': 10,
      'latitude': 30.1,
      'longitude': 101.2,
      'shockTime': '2026-08-17 09:00:00',
      'originTime': '2026-08-17 09:00:00',
      'createTime': '2026-08-17 09:01:00',
    };

    for (final (source, origin, title, badge) in adapted) {
      final event = QuakeEventAdapter.convert(source, payload, origin);
      expect(event, isNotNull, reason: source);
      expect(event!.source, source, reason: source);
      expect(event.titleText, title, reason: source);
      expect(event.apiTypeLabel, badge, reason: source);
    }

    final whewsCenc = QuakeEventAdapter.convertWhews('cenc', payload);
    expect(whewsCenc, isNotNull);
    expect(whewsCenc!.source, 'cencEqlist');
    expect(whewsCenc.titleText, '中国地震台网地震信息');
    expect(whewsCenc.apiTypeLabel, 'WHEWS');

    final whewsGuangxi = QuakeEventAdapter.convertWhews('guangxi', payload);
    expect(whewsGuangxi, isNotNull);
    expect(whewsGuangxi!.source, 'guangxi');
    expect(whewsGuangxi.titleText, '广西地震局地震信息');
    expect(whewsGuangxi.apiTypeLabel, 'WHEWS');

    final whewsGeonet = QuakeEventAdapter.convertWhews('geonet', payload);
    expect(whewsGeonet, isNotNull);
    expect(whewsGeonet!.source, 'whews_geonet');
    expect(whewsGeonet.titleText, '新西兰地球科学局地震信息');
    expect(whewsGeonet.apiTypeLabel, 'WHEWS');
  });

  test('provider maps unadapted unified events away from CENC', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = QuakeEventAdapter.convertUnadapted(
      apiName: 'geonet',
      origin: 1,
      data: geonetPayload(title: '新西兰 GeoNet 地震信息'),
    );

    expect(provider.unifiedSourceTypeForTest(event), QuakeSourceType.unadapted);
    final mapped = provider.unifiedToQuakeMessageForTest(event);
    expect(mapped.source, QuakeSourceType.unadapted);
    expect(mapped.infoTypeName, '新西兰 GeoNet 地震信息');
    expect(mapped.infoTypeName, isNot(contains('中国地震台网')));
  });

  test('provider still maps adapted CENC events as CENC', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = QuakeEventAdapter.convert('cencEqlist', {
      'eventId': 'cenc-1',
      'placeName': '四川甘孜州',
      'magnitude': 4.2,
      'depth': 10,
      'latitude': 30.1,
      'longitude': 101.2,
      'shockTime': '2026-08-17 09:00:00',
      'createTime': '2026-08-17 09:01:00',
      'type': '正式测定',
    }, 1)!;

    expect(provider.unifiedSourceTypeForTest(event), QuakeSourceType.cenc);
    final mapped = provider.unifiedToQuakeMessageForTest(event);
    expect(mapped.source, QuakeSourceType.cenc);
  });
}
