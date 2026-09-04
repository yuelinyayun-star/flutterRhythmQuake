import 'dart:convert';

import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WHEWS JMA information preserves official area intensities', () {
    final raw = <String, dynamic>{
      'id': '20260809140518',
      'updates': 2,
      'shockTime': '2026-08-09 14:05:00',
      'createTime': '2026-08-09 14:08:00',
      'latitude': 34.68,
      'longitude': 135.82,
      'depth': 10,
      'magnitude': 3.2,
      'placeName': '奈良県',
      'maxIntensity': '調査中',
      'infoTypeName': '訂正',
      'title': '震源・震度に関する情報',
      'intensities': [
        {
          'pref': '三重県',
          'maxIntensity': '2',
          'areas': [
            {
              'area': '三重県南部',
              'maxIntensity': '2',
              'cities': [
                {
                  'name': '熊野市',
                  'maxIntensity': '2',
                  'stations': [
                    {'name': '熊野市紀和町板屋', 'intensity': '2'},
                  ],
                },
              ],
            },
          ],
        },
        {
          'pref': '奈良県',
          'maxIntensity': '5弱',
          'areas': [
            {
              'area': '奈良県',
              'maxIntensity': '不明',
              'cities': [
                {
                  'name': '奈良市',
                  'stations': [
                    {'name': '奈良市二条大路南', 'intensity': '5弱'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    final event = QuakeEventAdapter.convertWhews('jma', raw);

    expect(event, isNotNull);
    expect(event!.source, 'jmaEqlist');
    expect(event.apiTypeLabel, 'WHEWS');
    expect(event.titleText, '震源・震度に関する情報');
    expect(event.reportNumText, '訂正');
    expect(event.maxIntensity, '5-');
    expect(event.className, 'orange');
    expect(event.originTime, DateTime(2026, 8, 9, 14, 5));
    expect(event.reportTime, DateTime(2026, 8, 9, 14, 8));

    final areas = json.decode(event.warnArea) as List<dynamic>;
    expect(areas, hasLength(2));
    expect(areas, contains(containsPair('name', '三重県南部')));
    expect(
      areas,
      contains(
        allOf(
          containsPair('name', '奈良県'),
          containsPair('intensity', '5-'),
          containsPair('className', 'orange'),
        ),
      ),
    );
    expect(raw['maxIntensity'], '調査中');
    expect(
      ((raw['intensities'] as List)[1] as Map)['areas'][0]['maxIntensity'],
      '不明',
    );
  });

  test('WHEWS JMA investigating hypocenter reuses unified P2P UI text', () {
    final event = QuakeEventAdapter.convertWhews('jma', {
      'id': '20260809140518',
      'updates': 1,
      'shockTime': '2026-08-09 14:05:00',
      'createTime': '2026-08-09 14:05:30',
      'latitude': 0,
      'longitude': 0,
      'depth': '不明',
      'magnitude': null,
      'placeName': '調査中',
      'maxIntensity': '3',
      'infoTypeName': '発表',
      'title': '震源・震度に関する情報',
      'intensities': const [],
    });

    expect(event, isNotNull);
    expect(event!.hypocenter, isEmpty);
    expect(event.magnitude, -1);
    expect(event.depth, -1);
    expect(event.depthText, isEmpty);
    expect(event.lat, isNull);
    expect(event.lng, isNull);
    expect(event.reportNumText, isEmpty);

    final presentation = UnifiedEventPresentation.fromEvent(event);
    expect(presentation.primaryText, '震源 調査中');
    expect(presentation.secondaryText, '規模 調査中');
    expect(presentation.intensityValue, '3');
  });

  test('WHEWS JMA cancellation clears intensity areas', () {
    final event = QuakeEventAdapter.convertWhews('jma', {
      'id': '20260809140518',
      'updates': 3,
      'shockTime': '2026-08-09 14:05:00',
      'createTime': '2026-08-09 14:10:00',
      'latitude': 34.68,
      'longitude': 135.82,
      'depth': 10,
      'magnitude': 3.2,
      'placeName': '奈良県',
      'maxIntensity': '3',
      'infoTypeName': '取消',
      'title': '震源・震度に関する情報',
      'intensities': [
        {
          'pref': '奈良県',
          'areas': [
            {'area': '奈良県', 'maxIntensity': '3'},
          ],
        },
      ],
    });

    expect(event, isNotNull);
    expect(event!.isCanceled, isTrue);
    expect(event.reportNumText, '取消');
    expect(event.className, 'dark-gray');
    expect(event.warnArea, isEmpty);
  });

  test(
    'WHEWS JMA volcano event preserves volcano fields without quake values',
    () {
      final raw = <String, dynamic>{
        'id': 'VFVO52_20260724174700_506',
        'updates': 2,
        'kindCode': 'VFVO52',
        'kindName': '喷发相关火山观测报',
        'infoKind': '噴火に関する火山観測報',
        'infoTypeName': '訂正',
        'title': '火山名　桜島　噴火に関する火山観測報',
        'reportTime': '2026-08-07 12:01:00',
        'targetTime': '2026-08-07 11:59:00',
        'volcanoName': '桜島',
        'volcanoCode': '506',
        'latitude': 31.5925,
        'longitude': 130.6567,
        'craterName': '南岳山頂火口',
        'headline': '噴火が発生しました。',
        'plumeDirection': '直上',
        'plumeHeight': 1000,
        'winds': [
          {'heightFt': 5000, 'degree': 20, 'speedKt': 11},
        ],
        'publishingOffice': '鹿児島地方気象台',
      };

      final event = QuakeEventAdapter.convertWhews('va', raw);

      expect(event, isNotNull);
      expect(event!.source, 'whews_va');
      expect(event.origin, WhewsService.adapterOrigin);
      expect(event.timeZone, 9);
      expect(event.isVolcanoEvent, isTrue);
      expect(event.magnitude, -1);
      expect(event.depth, -1);
      expect(event.maxIntensity, isEmpty);
      expect(event.volcanoEvent!.volcanoCode, '506');
      expect(event.volcanoEvent!.displayLocation, '桜島 南岳山頂火口');
      expect(event.volcanoEvent!.winds.single.speedKt, 11);
      expect(event.lat, 31.5925);
      expect(event.lng, 130.6567);
      expect(raw['kindCode'], 'VFVO52');

      final presentation = UnifiedEventPresentation.fromEvent(event);
      expect(presentation.primaryText, '桜島 南岳山頂火口');
      expect(presentation.secondaryText, '噴火が発生しました。');
      expect(presentation.intensityLabel, '火山');
    },
  );

  test('WHEWS JMA EEW uses the existing JMA source slot and WHEWS label', () {
    final event = QuakeEventAdapter.convertWhews('jma_eew', {
      'id': 'JMA-1',
      'updates': 4,
      'shockTime': '2026-08-06 12:00:00',
      'createTime': '2026-08-06 12:00:05',
      'latitude': 35.0,
      'longitude': 140.0,
      'depth': 20,
      'magnitude': 5.2,
      'placeName': '千葉県',
      'epiIntensity': '5 弱',
      'infoTypeName': '警報',
      'final': false,
      'cancel': false,
    });

    expect(event, isNotNull);
    expect(event!.source, 'jmaEew');
    expect(event.origin, 3);
    expect(event.apiTypeLabel, 'WHEWS');
    expect(event.eventId, 'JMA-1');
    expect(event.reportNumText, contains('4'));
    expect(event.isEew, isTrue);
  });

  test('WHEWS information uses the same CENC slot for merging', () {
    final event = QuakeEventAdapter.convertWhews('cenc', {
      'id': 'CENC-1',
      'shockTime': '2026-08-06 12:00:00',
      'updateTime': '2026-08-06 12:00:03',
      'latitude': 30.0,
      'longitude': 100.0,
      'depth': 10,
      'magnitude': 4.5,
      'placeName': '四川省',
      'maxIntensity': '3.2',
      'type': 'reviewed',
    });

    expect(event, isNotNull);
    expect(event!.source, 'cencEqlist');
    expect(event.origin, 3);
    expect(event.apiTypeLabel, 'WHEWS');
    expect(event.reportNumText, '正式测定');
  });

  test(
    'WHEWS generic information preserves an unsupported source identity',
    () {
      final event = QuakeEventAdapter.convertWhews('bmkg', {
        'id': 'BMKG-1',
        'shockTime': '2026-08-06 12:00:00',
        'updateTime': '2026-08-06 12:00:01',
        'latitude': -6.2,
        'longitude': 106.8,
        'magnitude': 4.1,
        'placeName': 'Java',
      });

      expect(event, isA<UnifiedQuakeData>());
      expect(event!.source, 'whews_bmkg');
      expect(event.apiTypeLabel, 'WHEWS');
      expect(event.eventId, 'BMKG-1');
    },
  );

  test(
    'WHEWS generic information sources retain separate source identities',
    () {
      const expectedTypes = <String, QuakeSourceType>{
        'bmkg': QuakeSourceType.bmkg,
        'geonet': QuakeSourceType.geonet,
        'tmd': QuakeSourceType.tmd,
        'ingv': QuakeSourceType.ingv,
        'nrcan': QuakeSourceType.nrcan,
        'mmd': QuakeSourceType.mmd,
        'phivolcs': QuakeSourceType.phivolcs,
        'sgc': QuakeSourceType.sgc,
        'ga': QuakeSourceType.ga,
        'cenais': QuakeSourceType.cenais,
      };
      const expectedTitles = <String, String>{
        'bmkg': '印度尼西亚气象气候与地球物理局',
        'geonet': '新西兰地球科学局',
        'tmd': '泰国气象局',
        'ingv': '意大利国家地球物理与火山学研究所',
        'nrcan': '加拿大自然资源部',
        'mmd': '马来西亚气象局',
        'phivolcs': '菲律宾火山与地震研究所',
        'sgc': '哥伦比亚地质局',
        'ga': '澳大利亚地质局',
        'cenais': '古巴国家地震研究中心',
      };
      final expectedIntensity = IntensityCalculator.calcCsisLevel(
        4.1,
        10.0,
        0,
      ).toStringAsFixed(1);
      for (final source in expectedTypes.keys) {
        final event = QuakeEventAdapter.convertWhews(source, {
          'id': '${source.toUpperCase()}-1',
          'shockTime': '2026-08-06 12:00:00',
          'updateTime': '2026-08-06 12:00:01',
          'latitude': 10.0,
          'longitude': 120.0,
          'depth': 10.0,
          'magnitude': 4.1,
          'placeName': 'Test location',
        });

        expect(event, isNotNull, reason: source);
        expect(event!.source, 'whews_$source');
        expect(event.apiTypeLabel, 'WHEWS');
        expect(event.timeZone, 8, reason: source);
        expect(event.titleText, contains(expectedTitles[source]!));
        expect(event.maxIntensity, expectedIntensity, reason: source);
        expect(event.className, isNot('gray'), reason: source);
      }
      expect(
        QuakeProvider.infoMagFilterSources,
        containsAll(expectedTypes.values),
      );
    },
  );

  test('WHEWS SGC GA and CENAIS use the documented generic frame fields', () {
    final sgc = QuakeEventAdapter.convertWhews('sgc', {
      'id': 'SGC2026pvumwd',
      'infoTypeName': 'manual/MLr_1',
      'magnitude': 3.6,
      'placeName': '哥伦比亚',
      'shockTime': '2026-08-13 19:22:00',
      'updateTime': '2026-08-13 19:22:00',
      'longitude': -76.53783333333334,
      'latitude': 4.855166666666666,
      'depth': 94,
    });
    expect(sgc, isNotNull);
    expect(sgc!.source, 'whews_sgc');
    expect(sgc.titleText, contains('哥伦比亚地质局'));
    expect(sgc.reportNumText, '正式');
    expect(sgc.magnitude, 3.6);
    expect(sgc.originTime, DateTime(2026, 8, 13, 19, 22));
    expect(sgc.reportTime, DateTime(2026, 8, 13, 19, 22));

    final ga = QuakeEventAdapter.convertWhews('ga', {
      'id': 'ga2026pylrk1',
      'infoTypeName': 'manual/Mw',
      'magnitude': 5.2,
      'placeName': '菲律宾棉兰老岛',
      'shockTime': '2026-08-13 17:22:59',
      'updateTime': '2026-08-13 17:22:59',
      'longitude': 125.920822143555,
      'latitude': 6.24310779571533,
      'depth': 85.9,
    });
    expect(ga, isNotNull);
    expect(ga!.source, 'whews_ga');
    expect(ga.titleText, contains('澳大利亚地质局'));
    expect(ga.reportNumText, '正式');

    final gaAuto = QuakeEventAdapter.convertWhews('ga', {
      'id': 'ga2026auto',
      'infoTypeName': 'automatic/Mw',
      'magnitude': 4.0,
      'placeName': 'Test',
      'shockTime': '2026-08-13 17:22:59',
      'updateTime': '2026-08-13 17:22:59',
      'longitude': 120.0,
      'latitude': 10.0,
      'depth': 10.0,
    });
    expect(gaAuto, isNotNull);
    expect(gaAuto!.reportNumText, '自动');

    final cenais = QuakeEventAdapter.convertWhews('cenais', {
      'id': 'cenais_20260813043125',
      'magnitude': 2.9,
      'placeName': '海地地区',
      'shockTime': '2026-08-13 12:31:25',
      'updateTime': '2026-08-13 12:31:25',
      'longitude': -72.77,
      'latitude': 19.801,
      'depth': 40,
    });
    expect(cenais, isNotNull);
    expect(cenais!.source, 'whews_cenais');
    expect(cenais.titleText, contains('古巴国家地震研究中心'));
    expect(cenais.reportNumText, isEmpty);

    final presentation = UnifiedEventPresentation.fromEvent(sgc);
    expect(presentation.title, '哥伦比亚地质局地震信息 正式');
    expect(presentation.secondaryText, contains('M3.6'));
    expect(presentation.title, isNot(contains('manual/')));
    expect(presentation.timeText, '2026-08-13 19:22:00 (UTC+8)');
  });

  test('WHEWS KMA information preserves Roman MMI and UTC+8 update time', () {
    final raw = <String, dynamic>{
      'id': 'kma_20260723034704',
      'shockTime': '2026-07-23 02:47:04',
      'updateTime': '2026-07-23 02:48:05',
      'latitude': 36.1,
      'longitude': 128.2,
      'depth': 12,
      'magnitude': 4.2,
      'placeName': '경상북도',
      'maxIntensity': 'Ⅳ',
    };

    final event = QuakeEventAdapter.convertWhews('kma', raw);

    expect(event, isNotNull);
    expect(event!.source, 'kmaEqlist');
    expect(event.timeZone, 8);
    expect(event.maxIntensity, 'Ⅳ');
    expect(event.className, 'blue');
    expect(event.originTime, DateTime(2026, 7, 23, 2, 47, 4));
    expect(event.reportTime, DateTime(2026, 7, 23, 2, 48, 5));
    expect(raw['maxIntensity'], 'Ⅳ');
  });

  test('WHEWS KMA EEW uses KST shockTime when originTime is epoch', () {
    final raw = <String, dynamic>{
      'id': 'KMA-EEW-1',
      'updates': 2,
      'originTime': 1784269800000,
      'shockTime': '2026-07-26 15:30:00',
      'updateTime': '2026-07-26 15:30:04',
      'latitude': 36.1,
      'longitude': 128.2,
      'depth': 10,
      'magnitude': 5.1,
      'placeName': '경상북도',
      'maxMmi': 5,
      'maxMmiLabel': 'Ⅴ',
    };

    final event = QuakeEventAdapter.convertWhews('kma_eew', raw);

    expect(event, isNotNull);
    expect(event!.source, 'kmaEew');
    expect(event.timeZone, 9);
    expect(event.originTime, DateTime(2026, 7, 26, 15, 30));
    expect(event.reportTime, DateTime(2026, 7, 26, 15, 30, 4));
    expect(event.maxIntensity, 'Ⅴ');
    expect(raw['originTime'], 1784269800000);
  });

  test('WHEWS JMA cancel report retains time for expiry checks', () {
    final event = QuakeEventAdapter.convertWhews('jma_eew', {
      'id': 'JMA-CANCEL-OLD',
      'updates': 5,
      'shockTime': '2026-07-01 12:00:00',
      'createTime': '2026-07-01 12:00:10',
      'magnitude': 5.0,
      'cancel': true,
    });

    expect(event, isNotNull);
    expect(event!.isCanceled, isTrue);
    expect(event.originTime, DateTime(2026, 7, 1, 12));
    expect(event.reportTime, DateTime(2026, 7, 1, 12, 0, 10));
  });

  test('WHEWS CWA information uses the official updateTime', () {
    final event = QuakeEventAdapter.convertWhews('cwa', {
      'id': 'CWA-1',
      'shockTime': '2026-08-07 12:00:00',
      'updateTime': '2026-08-07 12:01:23',
      'latitude': 23.5,
      'longitude': 121.0,
      'depth': 15,
      'magnitude': 4.8,
      'placeName': '花蓮縣近海',
      'maxIntensity': '3',
    });

    expect(event, isNotNull);
    expect(event!.reportTime, DateTime(2026, 8, 7, 12, 1, 23));
  });

  test('WHEWS estimates missing information intensity like FAN and HTTP', () {
    final expected = IntensityCalculator.calcCsisLevel(
      8,
      10,
      0,
    ).toStringAsFixed(1);
    for (final source in const ['usgs', 'emsc', 'cenc']) {
      final event = QuakeEventAdapter.convertWhews(source, {
        'id': '$source-no-intensity',
        'shockTime': '2026-08-07 12:00:00',
        'updateTime': '2026-08-07 12:00:10',
        'latitude': 30.0,
        'longitude': 100.0,
        'depth': 10,
        'magnitude': 8.0,
        'placeName': 'Test location',
      });

      expect(event, isNotNull, reason: source);
      expect(event!.maxIntensity, expected, reason: source);
      expect(event.className, isNot('gray'), reason: source);
    }
  });
}
