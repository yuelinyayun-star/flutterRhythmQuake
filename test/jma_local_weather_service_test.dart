import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/weather_alarm.dart';
import 'package:flutterrhythmquake/services/sources/jma_local_weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const station = JmaAmedasStation(
    id: '44132',
    name: '東京',
    latitude: 35.69,
    longitude: 139.76,
  );

  test('refreshes local weather every ten minutes', () {
    expect(JmaLocalWeatherService.refreshInterval, const Duration(minutes: 10));
  });

  test('parses JST latest_time with an explicit offset', () {
    final parsed = jmaParseLatestTime('2026-08-14T23:50:00+09:00');
    expect(parsed, DateTime(2026, 8, 14, 23, 50));
    expect(jmaPointBlockKey(parsed!), '20260814_21');
    expect(jmaMapTimestamp(parsed), '20260814235000');
  });

  test('treats naive latest_time as a JST wall clock', () {
    expect(
      jmaParseLatestTime('2026-08-14T23:50:00'),
      DateTime(2026, 8, 14, 23, 50),
    );
  });

  test('parses the official AMeDAS point payload', () {
    final observation = jmaObservationFromPointJson(
      _pointPayload(),
      station,
      locationPath: '東京',
      forecastSummary: '曇り、所により雨',
      alarms: jmaWarningsFromOfficeJson(_warningPayload()),
    );

    expect(observation, isNotNull);
    expect(observation!.station.id, '44132');
    expect(observation.station.name, '東京');
    expect(observation.temperature, 24.8);
    expect(observation.pressure, 1007.5);
    expect(observation.humidity, 95.0);
    expect(observation.windDirection, '北东');
    expect(observation.windDirectionDegree, 45.0);
    expect(observation.windSpeed, 1.7);
    expect(observation.precipitation, 0.0);
    expect(observation.precipitation10m, 0.0);
    expect(observation.observedAt, DateTime(2026, 8, 15, 0, 30));
    expect(observation.forecastSummary, '曇り、所により雨');
    expect(observation.alarms, hasLength(2));
    expect(observation.alarms.first.label, '大雨警報');
    expect(observation.alarms.first.severityRank, 3);
    expect(observation.alarms.last.label, '雷注意報');
  });

  test('builds alert card payload from the highest JMA warning', () {
    final observation = jmaObservationFromPointJson(
      _pointPayload(),
      station,
      locationPath: '東京',
      alarms: jmaWarningsFromOfficeJson(_warningPayload()),
    );
    expect(observation, isNotNull);

    final alarm = jmaBestWeatherAlarmForDisplay(observation);
    expect(alarm, isNotNull);
    expect(alarm!.source, WeatherAlarmSource.jmaLocal);
    expect(alarm.headline, '東京 大雨警報');
    expect(alarm.type, '1103');
    expect(alarm.levelLabel, '警報');
    expect(alarm.disasterType, '大雨');
  });

  test('selects the nearest AMeDAS station', () {
    final selected = jmaNearestAmedasStation(
      _amedasTable(),
      latitude: 35.68,
      longitude: 139.76,
    );

    expect(selected, isNotNull);
    expect(selected!.id, '44132');
    expect(selected.name, '東京');
  });

  test('maps Tokyo coordinates to the Tokyo forecast office', () {
    expect(jmaOfficeCodeFromLatLng(35.69, 139.69), '130000');
  });

  test('extracts the overview forecast summary', () {
    expect(
      jmaForecastSummaryFromOverview({
        'text': '【気象概況】\n東京地方は曇り、所により雨。\n明日は晴れ。',
      }),
      '東京地方は曇り、所により雨。',
    );
  });

  test('reuses the cached station for the same saved location', () async {
    SharedPreferences.setMockInitialValues({});
    var tableRequests = 0;
    var observationRequests = 0;
    final firstService = JmaLocalWeatherService(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/amedas/const/amedastable.json')) {
          tableRequests++;
          return _jsonResponse(_amedasTable());
        }
        if (path.endsWith('/amedas/data/latest_time.txt')) {
          return http.Response(
            '2026-08-14T23:50:00+09:00',
            200,
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          );
        }
        if (path.contains('/amedas/data/point/44132/')) {
          observationRequests++;
          return _jsonResponse(_pointPayload());
        }
        if (path.endsWith('/warning/data/warning/130000.json')) {
          return _jsonResponse(_warningPayload());
        }
        if (path.endsWith('/forecast/data/overview_forecast/130000.json')) {
          return _jsonResponse({'text': '【気象概況】\n東京地方は曇り、所により雨。'});
        }
        return http.Response('not found', 404);
      }),
    );

    await firstService.startForLocation(35.68, 139.76);
    expect(
      firstService.stateNotifier.value.status,
      JmaLocalWeatherStatus.ready,
    );
    expect(firstService.stateNotifier.value.station?.id, '44132');
    expect(firstService.stateNotifier.value.observation?.temperature, 24.8);
    expect(tableRequests, 1);
    expect(observationRequests, 1);
    firstService.dispose();

    final secondService = JmaLocalWeatherService(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/amedas/const/amedastable.json')) {
          fail('station table should not be requested for cached location');
        }
        if (path.endsWith('/amedas/data/latest_time.txt')) {
          return http.Response(
            '2026-08-14T23:50:00+09:00',
            200,
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          );
        }
        if (path.contains('/amedas/data/point/44132/')) {
          observationRequests++;
          return _jsonResponse(_pointPayload());
        }
        if (path.endsWith('/warning/data/warning/130000.json')) {
          return _jsonResponse(_warningPayload());
        }
        if (path.endsWith('/forecast/data/overview_forecast/130000.json')) {
          return _jsonResponse({'text': '【気象概況】\n東京地方は曇り、所により雨。'});
        }
        return http.Response('not found', 404);
      }),
    );

    await secondService.startForLocation(35.69, 139.76);
    expect(
      secondService.stateNotifier.value.status,
      JmaLocalWeatherStatus.ready,
    );
    expect(secondService.stateNotifier.value.station?.id, '44132');
    expect(tableRequests, 1);
    expect(observationRequests, 2);
    secondService.dispose();
  });
}

Map<String, dynamic> _amedasTable() => {
  '44132': {
    'kjName': '東京',
    'lat': [35, 41.4],
    'lon': [139, 45.6],
    'alt': 25,
  },
  '44136': {
    'kjName': '江戸川臨海',
    'lat': [35, 38.2],
    'lon': [139, 51.8],
    'alt': 5,
  },
};

Map<String, dynamic> _pointPayload() => {
  '20260815000000': {
    'temp': [24.7, 0],
    'pressure': [1007.6, 0],
    'humidity': [96, 0],
    'precipitation1h': [0.0, 0],
    'precipitation10m': [0.0, 0],
    'windDirection': [4, 0],
    'wind': [1.9, 0],
  },
  '20260815003000': {
    'temp': [24.8, 0],
    'pressure': [1007.5, 0],
    'humidity': [95, 0],
    'precipitation1h': [0.0, 0],
    'precipitation10m': [0.0, 0],
    'windDirection': [3, 0],
    'wind': [1.7, 0],
  },
};

Map<String, dynamic> _warningPayload() => {
  'areaTypes': [
    {
      'areas': [
        {
          'warnings': [
            {'code': '03', 'status': '発表'},
            {'code': '14', 'status': '発表'},
            {'code': '10', 'status': '解除'},
            {'code': '15', 'status': 'なし'},
          ],
        },
      ],
    },
  ],
};

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
