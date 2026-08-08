import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

void main() {
  const genericSources = <String, String>{
    'emsc': 'EMSC 地震情报',
    'bcsf': 'BCSF 地震情报',
    'gfz': 'GFZ 地震信息',
    'usp': 'USP 地震信息',
    'ningxia': '宁夏地震局地震信息',
    'guangxi': '广西地震局地震信息',
    'shanxi': '山西地震局地震信息',
    'beijing': '北京地震局地震信息',
    'yunnan': '云南地震局地震信息',
  };

  test(
    'generic information sources never append a measurement-type suffix',
    () {
      for (final entry in genericSources.entries) {
        final event = QuakeEventAdapter.convert(entry.key, {
          ..._eventPayload,
          'reviewType': 'automatic',
          'type': 'reviewed',
          'verify': 'automatic',
        }, 1);

        expect(event, isNotNull, reason: entry.key);
        expect(event!.titleText, entry.value, reason: entry.key);
      }
    },
  );

  test('HKO keeps its own verify mapping only', () {
    final verified = QuakeEventAdapter.convert('hko', {
      ..._eventPayload,
      'verify': 'Y',
      'reviewType': 'automatic',
    }, 1);
    final unverified = QuakeEventAdapter.convert('hko', {
      ..._eventPayload,
      'verify': 'N',
      'reviewType': 'reviewed',
    }, 1);

    expect(verified?.titleText, '香港天文台地震情报已核实');
    expect(unverified?.titleText, '香港天文台地震情报待核实');
  });

  test(
    'CWA official directory events never append a measurement-type suffix',
    () {
      final event = QuakeEventAdapter.convert('cwaEqlist', {
        ..._eventPayload,
        'jmaShindo': '3',
        'reviewType': 'automatic',
      }, 0);

      expect(event?.titleText, '中央氣象署 地震報告');
    },
  );
}

const _eventPayload = <String, dynamic>{
  'eventId': 'generic-info-test',
  'location': '测试区域',
  'originTime': '2026-08-05 10:00:00',
  'magnitude': 5.0,
  'depth': 10.0,
  'latitude': 30.0,
  'longitude': 120.0,
};
