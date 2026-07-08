import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

void main() {
  test('P2PQuake DetailScale station points are merged by JMA area', () {
    final data =
        json.decode(r'''
{
  "_id": "6a1c291de88ee598246bed72",
  "code": 551,
  "earthquake": {
    "hypocenter": {
      "depth": 20,
      "latitude": 33.8,
      "longitude": 135.8,
      "magnitude": 2.9,
      "name": "和歌山県南部"
    },
    "maxScale": 20,
    "time": "2026/05/31 21:24:00"
  },
  "issue": {
    "correct": "None",
    "source": "気象庁",
    "time": "2026/05/31 21:27:09",
    "type": "DetailScale"
  },
  "points": [
    {
      "addr": "熊野市紀和町板屋",
      "isArea": false,
      "pref": "三重県",
      "scale": 20
    },
    {
      "addr": "紀宝町 神内",
      "isArea": false,
      "pref": "三重県",
      "scale": 10
    }
  ]
}
''')
            as Map<String, dynamic>;

    final event = QuakeEventAdapter.convert('jmaEqlist', data, 2);
    expect(event, isNotNull);

    final areas = json.decode(event!.warnArea) as List<dynamic>;
    expect(areas, hasLength(1));
    expect(areas.single['name'], '三重県南部');
    expect(areas.single['intensity'], '2');
  });

  test('JMA shindo display follows kanameishi symbol format', () {
    final jmaEew = QuakeEventAdapter.convert('jmaEew', {
      'EventID': 'jma-eew',
      'Serial': 1,
      'MaxIntensity': '5弱',
      'Hypocenter': 'test',
    }, 0);
    expect(jmaEew?.maxIntensity, '5-');

    final cwaEew = QuakeEventAdapter.convert('cwaEew', {
      'EventID': 'cwa-eew',
      'ReportNum': 1,
      'MaxIntensity': '5強',
      'HypoCenter': 'test',
    }, 0);
    expect(cwaEew?.maxIntensity, '5+');

    final fanCwaEew = QuakeEventAdapter.convert('cwaEew', {
      'eventId': 'fan-cwa-eew',
      'updates': 1,
      'maxIntensity': '6弱',
      'location': 'test',
    }, 1);
    expect(fanCwaEew?.useShindo, isTrue);
    expect(fanCwaEew?.maxIntensity, '6-');

    final wolfxJma = QuakeEventAdapter.convert('jmaEqlist', {
      'EventID': 'wolfx-jma',
      'Title': '地震情報',
      'shindo': '6弱',
      'location': 'test',
    }, 0);
    expect(wolfxJma?.maxIntensity, '6-');

    final p2p = QuakeEventAdapter.convert('jmaEqlist', {
      '_id': 'p2p',
      'earthquake': {
        'hypocenter': {'name': 'test', 'magnitude': 5.0, 'depth': 10},
        'maxScale': 55,
        'time': '2026/06/18 12:00:00',
      },
      'issue': {'type': 'DetailScale', 'time': '2026/06/18 12:01:00'},
    }, 2);
    expect(p2p?.maxIntensity, '6-');

    final cwaList = QuakeEventAdapter.convert('cwaEqlist', {
      'eventId': 'cwa-list',
      'jmaShindo': '6強',
      'location': 'test',
    }, 1);
    expect(cwaList?.maxIntensity, '6+');
  });

  test('P2PQuake Destination keeps merged max shindo and title labels', () {
    final destination = QuakeEventAdapter.convert('jmaEqlist', {
      '_id': 'p2p-destination',
      'earthquake': {
        'hypocenter': {
          'name': '千葉県北東部',
          'magnitude': 6.0,
          'depth': 50,
          'latitude': 35.8,
          'longitude': 140.6,
        },
        'maxScale': 40,
        'time': '2026/06/26 12:46:35',
      },
      'issue': {'type': 'Destination', 'time': '2026/06/26 12:46:43'},
    }, 2);

    expect(destination, isNotNull);
    expect(destination!.titleText, '震源に関する情報');
    expect(destination.maxIntensity, '4');
    expect(destination.className, isNot('dark-gray'));

    final scaleAndDestination = QuakeEventAdapter.convert('jmaEqlist', {
      '_id': 'p2p-scale-destination',
      'earthquake': {
        'hypocenter': {
          'name': '千葉県北東部',
          'magnitude': 6.0,
          'depth': 50,
          'latitude': 35.8,
          'longitude': 140.6,
        },
        'maxScale': 40,
        'time': '2026/06/26 12:46:35',
      },
      'issue': {'type': 'ScaleAndDestination', 'time': '2026/06/26 12:50:00'},
    }, 2);

    expect(scaleAndDestination, isNotNull);
    expect(scaleAndDestination!.titleText, '震度・震源に関する情報');
    expect(scaleAndDestination.maxIntensity, '4');
  });
}
