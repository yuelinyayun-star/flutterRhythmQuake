import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/cma_local_weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const station = CmaWeatherStation(
    id: '57510',
    name: '铜梁',
    latitude: 29.86,
    longitude: 106.06,
  );

  test('refreshes local weather every five minutes', () {
    expect(CmaLocalWeatherService.refreshInterval, const Duration(minutes: 5));
  });

  test(
    'hosted snapshot survives page changes without local requests',
    () async {
      var requests = 0;
      final service = CmaLocalWeatherService(
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      addTearDown(service.dispose);
      final state = CmaLocalWeatherState(
        status: CmaLocalWeatherStatus.ready,
        station: station,
        observation: cmaObservationFromJson(_observationPayload(), station),
      );
      service.ingestExternalState(state);
      for (var i = 0; i < 3; i++) {
        service.pause(clearState: false);
        expect(service.stateNotifier.value, same(state));
      }
      await service.refreshNow();
      expect(requests, 0);
      final update = CmaLocalWeatherState(
        status: CmaLocalWeatherStatus.ready,
        station: station,
        observation: cmaObservationFromJson(_observationPayload(), station),
      );
      service.ingestExternalState(update);
      expect(service.stateNotifier.value, same(update));
      service.pause();
      expect(service.stateNotifier.value.status, CmaLocalWeatherStatus.idle);
      expect(service.stateNotifier.value.observation, isNull);
    },
  );

  test('parses the official CMA current weather payload', () {
    final observation = cmaObservationFromJson(_observationPayload(), station);

    expect(observation, isNotNull);
    expect(observation!.station.id, '57510');
    expect(observation.station.name, '铜梁');
    expect(observation.locationPath, '中国, 重庆, 铜梁');
    expect(observation.temperature, 28.9);
    expect(observation.feelsLike, 32.9);
    expect(observation.pressure, 968.0);
    expect(observation.humidity, 71.0);
    expect(observation.windDirection, '西南风');
    expect(observation.windDirectionDegree, 240.0);
    expect(observation.windSpeed, 1.5);
    expect(observation.windScale, '微风');
    expect(observation.precipitation, 0.0);
    expect(observation.observedAt, DateTime(2026, 7, 19, 0, 20));
    expect(observation.alarms, hasLength(1));
    expect(observation.alarms.single.displayText, '高温橙色预警');
    expect(observation.alarms.single.severity, 'ORANGE');
  });

  test('builds alert card payload from highest-severity CMA station alarm', () {
    final observation = cmaObservationFromJson(_observationPayload(), station);
    expect(observation, isNotNull);

    final alarm = cmaBestWeatherAlarmForDisplay(observation);
    expect(alarm, isNotNull);
    expect(alarm!.headline, contains('高温'));
    expect(alarm.levelLabel, '橙色');
    expect(alarm.disasterType, '高温');
    expect(alarm.description, '中国, 重庆, 铜梁');
  });

  test('parses CMA station alarms from a list or a single object', () {
    final listed = cmaAlarmsFromRaw([
      {
        'id': '44050041600000_20260814101359',
        'title': '汕头市气象台发布暴雨黄色预警[III级/较重]',
        'signaltype': '暴雨',
        'signallevel': '黄色',
        'effective': '2026/08/14 10:10',
        'severity': 'YELLOW',
        'type': 'p0002003',
      },
      {
        'id': '44050041600000_20260814105100',
        'title': '汕头市气象台发布雷雨大风黄色预警[III级/较重]',
        'signaltype': '雷雨大风',
        'signallevel': '黄色',
        'effective': '2026/08/14 10:45',
        'severity': 'ORANGE',
        'type': 'p0015003',
      },
    ]);
    expect(listed, hasLength(2));
    expect(listed.first.displayText, '雷雨大风黄色预警');
    expect(listed.first.severityRank, 3);
    expect(listed.last.displayText, '暴雨黄色预警');

    final single = cmaAlarmsFromRaw({
      'id': '35010041600000_20260814104000',
      'title': '福州市气象台发布高温橙色预警信号',
      'signaltype': '高温',
      'signallevel': '橙色',
      'effective': '2026/08/14 10:40',
      'severity': 'ORANGE',
    });
    expect(single, hasLength(1));
    expect(single.single.displayText, '高温橙色预警');
    expect(single.single.effective, DateTime(2026, 8, 14, 10, 40));
  });

  test(
    'selects the nearest CMA station including alphanumeric regional IDs',
    () {
      final selected = cmaNearestStationFromRows(
        _stationRows(),
        latitude: 29.84,
        longitude: 106.08,
      );

      expect(selected, isNotNull);
      expect(selected!.id, '57510');
      expect(selected.name, '铜梁');

      final regionalSelected = cmaNearestStationFromRows(
        _stationRows(),
        latitude: 30.55,
        longitude: 119.97,
      );
      expect(regionalSelected, isNotNull);
      expect(regionalSelected!.id, 'K5079');
      expect(regionalSelected.name, '德清');
    },
  );

  test('reuses the cached station for the same saved location', () async {
    SharedPreferences.setMockInitialValues({});
    var directoryRequests = 0;
    var observationRequests = 0;
    final firstService = CmaLocalWeatherService(
      client: MockClient((request) async {
        if (request.url.path == '/api/map/weather/1') {
          directoryRequests++;
          return _jsonResponse({
            'msg': 'success',
            'code': 0,
            'data': {'city': _stationRows()},
          });
        }
        if (request.url.path == '/api/now/57510') {
          observationRequests++;
          return _jsonResponse(_observationPayload());
        }
        return http.Response('not found', 404);
      }),
    );

    await firstService.startForLocation(29.84, 106.08);
    expect(
      firstService.stateNotifier.value.status,
      CmaLocalWeatherStatus.ready,
    );
    expect(firstService.stateNotifier.value.station?.id, '57510');
    expect(directoryRequests, 1);
    expect(observationRequests, 1);
    firstService.dispose();

    final secondService = CmaLocalWeatherService(
      client: MockClient((request) async {
        if (request.url.path == '/api/map/weather/1') {
          fail('station directory should not be requested for cached location');
        }
        if (request.url.path == '/api/now/57510') {
          observationRequests++;
          return _jsonResponse(_observationPayload());
        }
        return http.Response('not found', 404);
      }),
    );

    await secondService.startForLocation(29.85, 106.08);
    expect(
      secondService.stateNotifier.value.status,
      CmaLocalWeatherStatus.ready,
    );
    expect(secondService.stateNotifier.value.station?.id, '57510');
    expect(directoryRequests, 1);
    expect(observationRequests, 2);
    secondService.dispose();
  });
}

List<List<Object>> _stationRows() => [
  ['57516', '重庆', '中国', 2, 29.56, 106.55],
  ['57510', '铜梁', '中国', 3, 29.86, 106.06],
  ['57510-ACQ', '铜梁重复站', '中国', 3, 29.86, 106.06],
  ['K5079', '德清', '中国', 3, 30.54, 119.98],
];

Map<String, dynamic> _observationPayload() => {
  'msg': 'success',
  'code': 0,
  'data': {
    'location': {'id': '57510', 'name': '铜梁', 'path': '中国, 重庆, 铜梁'},
    'now': {
      'precipitation': 0.0,
      'temperature': 28.9,
      'pressure': 968.0,
      'humidity': 71.0,
      'windDirection': '西南风',
      'windDirectionDegree': 240.0,
      'windSpeed': 1.5,
      'windScale': '微风',
      'feelst': 32.9,
    },
    'alarm': [
      {
        'id': '50000041600000_20260814093705',
        'title': '重庆市气象台发布高温橙色预警[II级/较重]',
        'signaltype': '高温',
        'signallevel': '橙色',
        'effective': '2026/08/14 09:36',
        'eventType': '11B09',
        'severity': 'ORANGE',
        'type': 'p0003002',
      },
    ],
    'jieQi': '',
    'lastUpdate': '2026/07/19 00:20',
  },
};

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
