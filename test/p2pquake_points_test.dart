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
}
