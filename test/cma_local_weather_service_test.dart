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

  test('refreshes local weather every ten minutes', () {
    expect(CmaLocalWeatherService.refreshInterval, const Duration(minutes: 10));
  });

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
  });

  test('selects the nearest five-digit CMA station', () {
    final selected = cmaNearestStationFromRows(
      _stationRows(),
      latitude: 29.84,
      longitude: 106.08,
    );

    expect(selected, isNotNull);
    expect(selected!.id, '57510');
    expect(selected.name, '铜梁');
  });

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
