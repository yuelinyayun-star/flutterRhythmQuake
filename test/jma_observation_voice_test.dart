import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/core/utils/jma_voice_location.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

String voice(UnifiedQuakeData event) =>
    AlertVoiceHelper.generateUnifiedEventText(event, phase: 'first');

// Synthetic inputs below exercise edge cases; the captured P2P test uses raw JSON.
UnifiedQuakeData observation(List<Map<String, dynamic>> areas) =>
    UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: 2,
      eventId: 'voice-observation-unit-test',
      isEew: false,
      timeZone: 9,
      titleText: '震度速報',
      reportNumText: '',
      useShindo: true,
      maxIntensity: '4',
      className: 'orange',
      hypocenter: '',
      warnArea: jsonEncode(areas),
    );

void main() {
  test(
    'raw P2P ScalePrompt announces every area, including more than three',
    () {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/jma_voice/p2p_scale_prompt.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      expect(raw, hasLength(2));
      for (final item in raw.cast<Map<String, dynamic>>()) {
        final before = jsonEncode(item);
        expect(item['issue']['type'], 'ScalePrompt');
        final event = QuakeEventAdapter.convert('jmaEqlist', item, 2)!;
        expect(event.hypocenter, isEmpty);
        final beforeEvent = event.toMap();
        final text = voice(event);
        final names = (item['points'] as List)
            .map((p) => jmaVoiceLocation(p['addr'] as String))
            .toList();
        expect(names.length, greaterThan(3));
        expect(text, '震度速报，观测到震度3的地区：${names.join('、')}。日本气象厅。');
        expect(text, isNot(contains('震源待定')));
        expect(text, isNot(contains('深度')));
        expect(text, isNot(contains('震级')));
        expect(event.toMap(), beforeEvent);
        expect(jsonEncode(item), before);
      }
    },
  );

  test('regions group by descending intensity with no count truncation', () {
    final event = observation([
      {'name': 'ニセコ町', 'intensity': '3'},
      {'name': 'むつ市', 'intensity': '4'},
      {'name': 'つくば市', 'intensity': '4'},
      {'name': '北海道', 'intensity': '3'},
      {'name': '東京都', 'intensity': '3'},
    ]);
    expect(
      voice(event),
      '震度速报，观测到震度4的地区：陆奥市、筑波市。'
      '观测到震度3的地区：新雪谷町、北海道、东京都。日本气象厅。',
    );
  });

  test(
    'all investigating placeholders use observed regions, not an epicentre',
    () {
      final event = observation([
        {'name': 'ニセコ町', 'intensity': '4'},
      ]);
      for (final name in [
        '',
        '-',
        '--',
        '調査中',
        '震源調査中',
        '震源调查中',
        '震源待定',
        '不明',
        '不詳',
        'unknown',
      ]) {
        expect(
          voice(event.copyWith(hypocenter: name)),
          '震度速报，观测到震度4的地区：新雪谷町。日本气象厅。',
        );
      }
    },
  );

  test(
    'duplicate observations retain the reported maximum without mutation',
    () {
      final event = observation([
        {'name': 'ニセコ町', 'intensity': '3'},
        {'name': 'ニセコ町', 'intensity': '5+'},
        {'name': 'むつ市', 'intensity': '6-'},
        {'name': 'つくば市', 'intensity': '5-'},
      ]).copyWith(maxIntensity: '6-');
      final before = event.warnArea;
      expect(
        voice(event),
        '震度速报，观测到震度6弱的地区：陆奥市。'
        '观测到震度5强的地区：新雪谷町。观测到震度5弱的地区：筑波市。日本气象厅。',
      );
      expect(event.warnArea, before);
    },
  );

  test(
    'unknown observation intensity never becomes zero or an assumed value',
    () {
      final event = observation([
        {'name': 'ニセコ町', 'intensity': '不明'},
      ]);
      expect(voice(event), '震度速报，震度尚未明确的报告地区：新雪谷町，最大震度4。日本气象厅。');
    },
  );

  test('invalid or absent area data never leaks JSON or invents locations', () {
    for (final encoded in [
      '',
      '{broken',
      '{}',
      '[null,42,{"intensity":"4"}]',
    ]) {
      final text = voice(observation([]).copyWith(warnArea: encoded));
      expect(text, '震度速报，最大震度4。日本气象厅。');
    }
  });

  test(
    'P2P bulletin types use Chinese titles and map katakana hypocentres',
    () {
      const titles = {
        'ScalePrompt': '震度速报',
        'Destination': '震源信息',
        'ScaleAndDestination': '震源震度信息',
        'DetailScale': '各地震度信息',
        'Foreign': '远地地震信息',
        'Other': '地震信息',
      };
      for (final entry in titles.entries) {
        final event = QuakeEventAdapter.convert('jmaEqlist', {
          'issue': {'type': entry.key, 'time': '2026/09/17 00:10:00'},
          'earthquake': {
            'time': '2026/09/17 00:07:00',
            'maxScale': 40,
            'hypocenter': {
              'name': 'カムチャツカ半島付近',
              'latitude': 50,
              'longitude': 160,
              'magnitude': 6.2,
              'depth': 30,
            },
          },
        }, 2)!;
        expect(voice(event), startsWith('${entry.value}，堪察加半岛附近，震级6.2'));
        expect(voice(event), contains('深度30公里'));
      }
    },
  );

  test('WHEWS structured observations use the same voice path', () {
    final raw = <String, dynamic>{
      'id': 'voice-whews-unit-test',
      'title': '震度速報',
      'location': '調査中',
      'maxIntensity': '4',
      'intensities': [
        {
          'pref': '北海道',
          'areas': [
            {'area': 'ニセコ町', 'maxIntensity': '4'},
          ],
        },
      ],
    };
    final before = jsonEncode(raw);
    final event = QuakeEventAdapter.convertWhews('jma', raw)!;
    expect(voice(event), '震度速报，观测到震度4的地区：新雪谷町。日本气象厅。');
    expect(jsonEncode(raw), before);
  });

  test('Jian structured observations use the same voice path', () {
    final event = QuakeEventAdapter.convertJian('jma', {
      'id': 'voice-jian-unit-test',
      'title': '震度速報',
      'hypocenterUnknown': true,
      'intensity': '4',
      'intensityAreas': [
        {'name': 'ニセコ町', 'intensity': '4'},
      ],
    })!;
    expect(voice(event), '震度速报，观测到震度4的地区：新雪谷町。日本气象厅。');
  });

  test('unknown hypocentre processing never bypasses cancellation', () {
    expect(
      voice(
        observation([
          {'name': 'ニセコ町', 'intensity': '4'},
        ]).copyWith(isCanceled: true),
      ),
      '日本气象厅，地震信息已取消。',
    );
  });

  test('EEW depth is spoken naturally; unknown depth is omitted', () {
    final event = observation([]).copyWith(
      source: 'jmaEew',
      isEew: true,
      hypocenter: 'カムチャツカ半島付近',
      magnitude: 6.2,
    );
    expect(voice(event.copyWith(depth: 0)), contains('深度很浅'));
    expect(voice(event.copyWith(depth: 14.9)), contains('深度14.9公里'));
    for (final depth in [-1.0, double.nan, double.infinity]) {
      expect(voice(event.copyWith(depth: depth)), isNot(contains('深度')));
    }
  });

  test(
    'captured Hyuganada DetailScale speaks regions with a known hypocentre',
    () {
      final history =
          jsonDecode(
                File(
                  'test/fixtures/jma_voice/p2p_history_20260921.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      final raw = history.cast<Map<String, dynamic>>().singleWhere(
        (item) =>
            item['issue']['type'] == 'DetailScale' &&
            item['earthquake']['time'] == '2026/09/21 22:38:00',
      );
      final before = jsonEncode(raw);
      expect(raw['points'], hasLength(191));
      final event = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
      final beforeEvent = event.toMap();
      final text = voice(event);
      expect(text, startsWith('各地震度信息，日向滩，震级4.8，最大震度3，深度30公里。'));
      expect(text, contains('观测到震度3的地区：'));
      for (final name in ['大分県中部', '大分県南部', '宮崎県北部平野部', '宮崎県北部山沿い']) {
        expect(text, contains(jmaVoiceLocation(name)));
      }
      final areas = jsonDecode(event.warnArea) as List;
      expect(areas.length, greaterThan(4));
      for (final area in areas) {
        expect(text, contains(jmaVoiceLocation(area['name'] as String)));
      }
      expect(text, contains('观测到震度2的地区：'));
      expect(text, contains('观测到震度1的地区：'));
      expect(text, endsWith('日本气象厅。'));
      expect(jsonEncode(raw), before);
      expect(event.toMap(), beforeEvent);
      expect(voice(event.copyWith(isCanceled: true)), '日本气象厅，地震信息已取消。');
    },
  );

  test(
    'captured shallow DetailScale omits shallow-depth wording without changing data',
    () {
      final history =
          jsonDecode(
                File(
                  'test/fixtures/jma_voice/p2p_history_20260921.json',
                ).readAsStringSync(encoding: utf8),
              )
              as List;
      final raw = history.cast<Map<String, dynamic>>().firstWhere(
        (item) =>
            item['issue']['type'] == 'DetailScale' &&
            item['earthquake']['hypocenter']['depth'] == 0,
      );
      final event = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
      expect(event.depth, 0);
      expect(voice(event), isNot(contains('深度')));
      expect(voice(event), contains('观测到震度'));
      expect(event.depth, 0);
    },
  );

  test('only observation bulletins suppress shallow depth', () {
    final event = observation([
      {'name': 'ニセコ町', 'intensity': '4'},
    ]).copyWith(hypocenter: '日向灘', magnitude: 4.8, depth: 0);
    for (final title in ['震度速報', '震度速报', '各地の震度に関する情報', '各地の震度情報']) {
      final text = voice(event.copyWith(titleText: title));
      expect(text, isNot(contains('深度很浅')));
      expect(text, contains('观测到震度4的地区：新雪谷町'));
      expect(
        voice(event.copyWith(titleText: title, depth: 30)),
        contains('深度30公里'),
      );
    }
    for (final title in ['震源に関する情報', '震度・震源に関する情報', '遠地地震に関する情報', 'その他の情報']) {
      final text = voice(event.copyWith(titleText: title));
      expect(text, contains('深度很浅'));
      expect(text, isNot(contains('观测到')));
    }
    expect(voice(event.copyWith(source: 'cencEqlist')), contains('深度很浅'));
    expect(
      voice(event.copyWith(source: 'jmaEew', isEew: true)),
      contains('深度很浅'),
    );
  });

  test(
    'known-location observation bulletin with no regions does not invent any',
    () {
      final event = observation([]).copyWith(
        titleText: '各地の震度に関する情報',
        hypocenter: '日向灘',
        magnitude: 4.8,
        depth: 30,
      );
      expect(voice(event), '各地震度信息，日向滩，震级4.8，最大震度4，深度30公里。日本气象厅。');
    },
  );

  test(
    'WHEWS and Jian known-location DetailScale use the shared regional TTS',
    () {
      final whews = QuakeEventAdapter.convertWhews('jma', {
        'id': 'voice-whews-detail-test',
        'title': '各地の震度に関する情報',
        'location': '日向灘',
        'maxIntensity': '4',
        'intensities': [
          {
            'pref': '北海道',
            'areas': [
              {'area': 'ニセコ町', 'maxIntensity': '4'},
            ],
          },
        ],
      })!;
      final jian = QuakeEventAdapter.convertJian('jma', {
        'id': 'voice-jian-detail-test',
        'title': '各地の震度に関する情報',
        'placeName': '日向灘',
        'intensity': '4',
        'intensityAreas': [
          {'name': 'ニセコ町', 'intensity': '4'},
        ],
      })!;
      for (final event in [whews, jian]) {
        expect(event.hypocenter, '日向灘');
        expect(voice(event), contains('观测到震度4的地区：新雪谷町'));
      }
    },
  );
}
