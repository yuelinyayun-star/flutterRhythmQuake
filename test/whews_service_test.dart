import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/weather_alarm.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/services/sources/jma_ashfall_forecast_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';

String _chinaTime(DateTime utc) {
  final value = utc.toUtc().add(const Duration(hours: 8));
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

void main() {
  test(
    'initial aggregate array enters the same event pipeline and dedupes',
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

      expect(events, hasLength(1));

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

      expect(events, hasLength(2));
      expect(events.last.source, 'cencEqlist');

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
    'JMA aggregate frame uses the dedicated JMA information adapter',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);

      service.handleMessageForTesting({
        'source': 'jma',
        'md5': 'jma-info-service-route',
        'Data': {
          'id': '20260809140518',
          'updates': 2,
          'shockTime': '2026-08-09 14:05:00',
          'createTime': '2026-08-09 14:05:18',
          'placeName': '調査中',
          'magnitude': -1,
          'depth': '不明',
          'latitude': 0,
          'longitude': 0,
          'maxIntensity': '4',
          'infoTypeName': '発表',
          'title': '震源・震度に関する情報',
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.source, 'jmaEqlist');
      expect(events.single.origin, WhewsService.adapterOrigin);
      expect(events.single.titleText, '震源・震度に関する情報');
      expect(events.single.reportNumText, isEmpty);
      expect(events.single.hypocenter, isEmpty);
      expect(events.single.lat, isNull);
      expect(events.single.lng, isNull);

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
          'effective': _chinaTime(DateTime.now().toUtc()),
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
      expect(alarm?.source, WeatherAlarmSource.whews);
      expect(tsunami?.id, 'tsunami-1');

      await tsunamiSubscription.cancel();
      service.dispose();
    },
  );

  test('expired WHEWS weather alarm is not emitted', () async {
    final service = WhewsService(apiToken: 'test-token');
    WeatherAlarm? alarm;
    service.onWeatherAlarm = (value) => alarm = value;

    service.handleMessageForTesting({
      'source': 'weatheralarm',
      'md5': 'expired-weather-md5',
      'Data': {
        'id': 'expired-weather',
        'headline': '过期预警',
        'effective': _chinaTime(
          DateTime.now().toUtc().subtract(const Duration(days: 2)),
        ),
        'description': '过期内容',
        'type': 'p0002002',
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(alarm, isNull);
    service.dispose();
  });

  test('explicit disconnect starts a new frame dedupe session', () async {
    final service = WhewsService(apiToken: 'test-token');
    final events = <UnifiedQuakeData>[];
    final subscription = service.onUnifiedEvent.listen(events.add);
    final frame = {
      'source': 'cenc',
      'md5': 'reconnect-frame',
      'Data': {
        'id': 'reconnect-event',
        'shockTime': _chinaTime(DateTime.now().toUtc()),
        'updateTime': _chinaTime(DateTime.now().toUtc()),
        'latitude': 30.0,
        'longitude': 100.0,
        'depth': 10,
        'magnitude': 4.5,
        'placeName': '四川省',
      },
    };

    service.handleMessageForTesting(frame);
    service.disconnect();
    service.handleMessageForTesting(frame);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    await subscription.cancel();
    service.dispose();
  });

  test(
    'aggregate status prefers a live WHEWS socket over a handshaking peer',
    () {
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.connected,
          WhewsSocketState.connected,
        ]),
        SourceStatus.connected,
      );
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.connected,
          WhewsSocketState.error,
        ]),
        SourceStatus.connecting,
      );
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.connected,
          WhewsSocketState.disconnected,
        ]),
        SourceStatus.connecting,
      );
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.connected,
          WhewsSocketState.unauthorized,
        ]),
        SourceStatus.connecting,
      );
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.connected,
          WhewsSocketState.connecting,
        ]),
        SourceStatus.connected,
      );
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.connecting,
          WhewsSocketState.connecting,
        ]),
        SourceStatus.connecting,
      );
      expect(
        whewsAggregateStatus(const [
          WhewsSocketState.error,
          WhewsSocketState.unauthorized,
        ]),
        SourceStatus.error,
      );
    },
  );

  test('ashfall enrichment cannot emit after disconnect', () async {
    final ashfall = _DelayedAshfallService();
    final service = WhewsService(
      apiToken: 'test-token',
      ashfallForecastService: ashfall,
    );
    final events = <UnifiedQuakeData>[];
    final subscription = service.onUnifiedEvent.listen(events.add);

    service.handleMessageForTesting({
      'source': 'va',
      'md5': 'ashfall-disconnect',
      'Data': {
        'id': 'VFVO53_20260810120000_506',
        'updates': 1,
        'kindCode': 'VFVO53',
        'kindName': '定时降灰预报',
        'reportTime': _chinaTime(DateTime.now().toUtc()),
        'targetTime': _chinaTime(DateTime.now().toUtc()),
        'volcanoName': '桜島',
        'volcanoCode': '506',
        'latitude': 31.5925,
        'longitude': 130.6567,
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));

    service.disconnect();
    ashfall.complete(const [VolcanoAshfallWindow(label: '1時間後', items: [])]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    await subscription.cancel();
    service.dispose();
  });

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

  test('initial JMA tsunami aggregate enters the dedicated pipeline', () async {
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

    expect(tsunamis, hasLength(1));

    await subscription.cancel();
    service.dispose();
  });

  test(
    'initial aggregate emits only the latest report for each tsunami source',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      final tsunamis = <TsunamiMessage>[];
      final subscription = service.onTsunamiEvent.listen(tsunamis.add);

      service.handleMessageForTesting([
        {
          'source': 'jma_tsunami',
          'md5': 'jma-tsunami-old-warning',
          'Data': {
            'id': 'jma-warning',
            'createTime': '2026-08-10 12:00:00',
            'title': '津波警報・注意報・予報',
            'cancel': false,
            'areas': [
              {'name': '有明・八代海', 'kind': '津波注意報'},
            ],
          },
        },
        {
          'source': 'jma_tsunami',
          'md5': 'jma-tsunami-new-cancel',
          'Data': {
            'id': 'jma-cancel',
            'createTime': '2026-08-10 12:30:00',
            'headline': '津波注意報を解除しました。',
            'cancel': true,
            'areas': [],
          },
        },
        {
          'source': 'tsunami',
          'md5': 'nmefc-information',
          'Data': {
            'id': 'nmefc-information',
            'warningInfo': {'title': '海啸信息', 'level': '信息'},
            'timeInfo': {'updateDate': '2026-08-10 11:50:00'},
            'forecasts': [],
            'waterLevelMonitoring': [],
          },
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(tsunamis, hasLength(2));
      expect(
        tsunamis.where((item) => item.source == TsunamiSource.jma).single.id,
        'jma-cancel',
      );
      expect(tsunamis.every((item) => item.isInitialSnapshot), isTrue);

      await subscription.cancel();
      service.dispose();
    },
  );

  test(
    'PTWC NTWC and INCOIS frames use the dedicated tsunami pipeline',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      final tsunamis = <TsunamiMessage>[];
      final subscription = service.onTsunamiEvent.listen(tsunamis.add);

      for (final entry in [
        (source: 'ptwc', id: 'PHEB-1-26224050', expected: TsunamiSource.ptwc),
        (source: 'ntwc', id: 'PAAQ-1-tjk09g', expected: TsunamiSource.ntwc),
        (
          source: 'incois',
          id: 'incois2026ptdz_B1',
          expected: TsunamiSource.incois,
        ),
      ]) {
        service.handleMessageForTesting({
          'source': entry.source,
          'md5': '${entry.source}-md5',
          'Data': {
            'id': entry.id,
            'level': 'Warning',
            'headline': 'Tsunami Warning',
            'issueTime': '2026-08-10 20:58:30',
            'shockTime': '2026-08-10 20:34:28',
            'latitude': 5.0,
            'longitude': -76.3,
            'placeName': 'Test',
          },
        });
      }
      await Future<void>.delayed(Duration.zero);

      expect(tsunamis, hasLength(3));
      expect(tsunamis.map((item) => item.source).toSet(), {
        TsunamiSource.ptwc,
        TsunamiSource.ntwc,
        TsunamiSource.incois,
      });

      await subscription.cancel();
      service.dispose();
    },
  );

  test(
    'initial aggregate keeps the latest frame for each tsunami source',
    () async {
      final service = WhewsService(apiToken: 'test-token');
      final tsunamis = <TsunamiMessage>[];
      final subscription = service.onTsunamiEvent.listen(tsunamis.add);

      service.handleMessageForTesting([
        {
          'source': 'ptwc',
          'md5': 'ptwc-old',
          'Data': {
            'id': 'ptwc-old',
            'level': 'Watch',
            'issueTime': '2026-08-10 12:00:00',
          },
        },
        {
          'source': 'ptwc',
          'md5': 'ptwc-new',
          'Data': {
            'id': 'ptwc-new',
            'level': 'Warning',
            'issueTime': '2026-08-10 12:30:00',
          },
        },
        {
          'source': 'cenc',
          'md5': 'cenc-info',
          'Data': {
            'id': 'cenc-1',
            'shockTime': '2026-08-10 12:00:00',
            'updateTime': '2026-08-10 12:00:01',
            'latitude': 30.0,
            'longitude': 100.0,
            'magnitude': 4.0,
            'placeName': 'Test',
          },
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(tsunamis, hasLength(1));
      expect(tsunamis.single.source, TsunamiSource.ptwc);
      expect(tsunamis.single.id, 'ptwc-new');
      expect(tsunamis.single.isInitialSnapshot, isTrue);

      await subscription.cancel();
      service.dispose();
    },
  );
}

class _DelayedAshfallService extends JmaAshfallForecastService {
  final Completer<List<VolcanoAshfallWindow>> _completer = Completer();

  @override
  Future<List<VolcanoAshfallWindow>> fetchFor(VolcanoEventData volcano) =>
      _completer.future;

  void complete(List<VolcanoAshfallWindow> windows) {
    _completer.complete(windows);
  }
}
