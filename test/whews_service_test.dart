import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/weather_alarm.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';

void main() {
  test(
    'initial aggregate array only establishes the dedupe baseline',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);
      final initial = {
        'source': 'cenc',
        'md5': 'initial-md5',
        'Data': {
          'id': 'CENC-INITIAL',
          'shockTime': '2026-08-06 12:00:00',
          'updateTime': '2026-08-06 12:00:03',
          'latitude': 30.0,
          'longitude': 100.0,
          'depth': 10,
          'magnitude': 4.5,
          'placeName': '四川省',
        },
      };

      service.handleMessageForTesting([initial]);
      service.handleMessageForTesting(initial);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      service.handleMessageForTesting({
        ...initial,
        'md5': 'new-md5',
        'Data': {...initial['Data']! as Map<String, dynamic>, 'updates': 2},
      });
      service.handleMessageForTesting({
        ...initial,
        'md5': 'new-md5',
        'Data': {...initial['Data']! as Map<String, dynamic>, 'updates': 2},
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.source, 'cencEqlist');

      await subscription.cancel();
      service.dispose();
    },
  );

  test(
    'frames without md5 use documented identity aliases for dedupe',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);
      final first = {
        'source': 'JMA-EEW',
        'Data': {
          'EventID': 'JMA-NO-MD5',
          'Serial': 3,
          'ReportTime': '2026-08-07 12:00:03',
          'shockTime': '2026-08-07 12:00:00',
          'latitude': 35.0,
          'longitude': 140.0,
          'depth': 10,
          'magnitude': 4.5,
          'placeName': '千葉県',
          'epiIntensity': '4',
        },
      };

      service.handleMessageForTesting(first);
      service.handleMessageForTesting({...first, 'source': 'jma_eew'});
      service.handleMessageForTesting({
        ...first,
        'source': 'jma_eew',
        'Data': {
          ...first['Data']! as Map<String, dynamic>,
          'Serial': 4,
          'ReportTime': '2026-08-07 12:00:04',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events.map((event) => event.reportNumText), ['第1報', '第1報']);

      await subscription.cancel();
      service.dispose();
    },
  );

  test(
    'weather and tsunami frames use the existing dedicated event streams',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      WeatherAlarm? alarm;
      TsunamiMessage? tsunami;
      service.onWeatherAlarm = (value) => alarm = value;
      final tsunamiSubscription = service.onTsunamiEvent.listen((value) {
        tsunami = value;
      });

      service.handleMessageForTesting({
        'source': 'weatheralarm',
        'md5': 'weather-md5',
        'Data': {
          'id': 'weather-1',
          'headline': '广东省发布暴雨橙色预警信号',
          'effective': '2026/08/06 12:00',
          'description': '请注意防范',
          'type': 'p0002002',
        },
      });
      service.handleMessageForTesting({
        'source': 'tsunami',
        'md5': 'tsunami-md5',
        'Data': {
          'id': 'tsunami-1',
          'warningInfo': {'title': '海啸信息', 'level': '信息'},
          'timeInfo': {'updateDate': '2026-08-06 12:01:00'},
          'shockInfo': {
            'shockTime': '2026-08-06 12:00',
            'latitude': 24.0,
            'longitude': 122.0,
            'magnitude': 6.0,
            'depth': 30,
            'placeName': '台湾附近海域',
          },
          'forecasts': [],
          'waterLevelMonitoring': [],
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(alarm?.id, 'weather-1');
      expect(tsunami?.id, 'tsunami-1');

      await tsunamiSubscription.cancel();
      service.dispose();
    },
  );

  test('JMA tsunami frames use the existing JMA tsunami pipeline', () async {
    final service = WhewsService(apiToken: 'test-token');
    final tsunamis = <TsunamiMessage>[];
    final unifiedEvents = <UnifiedQuakeData>[];
    final tsunamiSubscription = service.onTsunamiEvent.listen(tsunamis.add);
    final unifiedSubscription = service.onUnifiedEvent.listen(
      unifiedEvents.add,
    );

    service.handleMessageForTesting({
      'source': 'jma_tsunami',
      'md5': 'jma-tsunami-active',
      'Data': {
        'id': '20260101120000-test',
        'updates': 1,
        'createTime': '2026-01-01 12:00:00',
        'infoTypeName': '発表',
        'title': '津波警報・注意報・予報',
        'headline': '有明・八代海に津波注意報が発表されています。',
        'cancel': false,
        'areas': [
          {
            'code': '712',
            'name': '有明・八代海',
            'kind': '津波注意報',
            'kindCode': '62',
            'arrivalTime': '2026-01-01 12:30:00',
            'condition': '津波到達中と推測',
            'maxHeight': '1',
            'maxHeightDesc': '１ｍ',
            'stations': [
              {
                'code': '71201',
                'name': '大牟田市三池',
                'highTide': '2026-01-01 13:04:00',
                'arrivalTime': '2026-01-01 12:30:00',
                'condition': '',
              },
            ],
          },
        ],
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(tsunamis, hasLength(1));
    expect(unifiedEvents, isEmpty);
    final tsunami = tsunamis.single;
    expect(tsunami.source, TsunamiSource.jma);
    expect(tsunami.id, '20260101120000-test');
    expect(tsunami.timeZone, 9);
    expect(tsunami.reportTime, '2026-01-01 12:00:00');
    expect(tsunami.grade, TsunamiGrade.watch);
    expect(tsunami.areas, hasLength(1));
    expect(tsunami.areas.single.name, '有明・八代海');
    expect(tsunami.areas.single.height, 1);
    expect(tsunami.areas.single.description, '１ｍ');
    expect(tsunami.areas.single.arrivalTime, '2026-01-01 12:30:00');
    expect(tsunami.areas.single.condition, '津波到達中と推測');
    expect(tsunami.observations, isEmpty);

    await tsunamiSubscription.cancel();
    await unifiedSubscription.cancel();
    service.dispose();
  });

  test('JMA tsunami cancellation clears the active warning', () async {
    final service = WhewsService(apiToken: 'test-token');
    final tsunamis = <TsunamiMessage>[];
    final subscription = service.onTsunamiEvent.listen(tsunamis.add);

    service.handleMessageForTesting({
      'source': 'jma_tsunami',
      'md5': 'jma-tsunami-cancel',
      'Data': {
        'id': '20260101120000-test',
        'updates': 2,
        'createTime': '2026-01-01 12:15:00',
        'title': '津波警報・注意報・予報',
        'headline': '津波注意報を解除しました。',
        'cancel': true,
        'areas': [],
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(tsunamis, hasLength(1));
    expect(tsunamis.single.source, TsunamiSource.jma);
    expect(tsunamis.single.grade, TsunamiGrade.none);
    expect(tsunamis.single.isActive, isFalse);
    expect(tsunamis.single.areas, isEmpty);
    expect(
      '${tsunamis.single.title}${tsunamis.single.titleText}',
      contains('解除'),
    );

    await subscription.cancel();
    service.dispose();
  });

  test('duplicate JMA tsunami frames emit once', () async {
    final service = WhewsService(apiToken: 'test-token');
    final tsunamis = <TsunamiMessage>[];
    final subscription = service.onTsunamiEvent.listen(tsunamis.add);
    final frame = {
      'source': 'jma_tsunami',
      'md5': 'jma-tsunami-duplicate',
      'Data': {
        'id': 'jma-tsunami-duplicate',
        'updates': 1,
        'createTime': '2026-01-01 12:00:00',
        'title': '津波警報・注意報・予報',
        'headline': '津波注意報発表中',
        'cancel': false,
        'areas': [
          {'name': '有明・八代海', 'kind': '津波注意報'},
        ],
      },
    };

    service.handleMessageForTesting(frame);
    service.handleMessageForTesting(frame);
    await Future<void>.delayed(Duration.zero);

    expect(tsunamis, hasLength(1));

    await subscription.cancel();
    service.dispose();
  });

  test('initial JMA tsunami aggregate only establishes baseline', () async {
    final service = WhewsService(apiToken: 'test-token');
    final tsunamis = <TsunamiMessage>[];
    final subscription = service.onTsunamiEvent.listen(tsunamis.add);
    final frame = {
      'source': 'jma_tsunami',
      'md5': 'jma-tsunami-initial',
      'Data': {
        'id': 'jma-tsunami-initial',
        'updates': 1,
        'createTime': '2026-01-01 12:00:00',
        'title': '津波警報・注意報・予報',
        'cancel': false,
        'areas': [
          {'name': '有明・八代海', 'kind': '津波注意報'},
        ],
      },
    };

    service.handleMessageForTesting([frame]);
    service.handleMessageForTesting(frame);
    await Future<void>.delayed(Duration.zero);

    expect(tsunamis, isEmpty);

    await subscription.cancel();
    service.dispose();
  });
}
