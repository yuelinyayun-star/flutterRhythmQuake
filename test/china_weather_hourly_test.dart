import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/china_weather_hourly_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final source = File(
    'test/fixtures/china_weather_hourly/beijing.js',
  ).readAsStringSync();
  final location = File(
    'test/fixtures/china_weather_hourly/beijing_location.jsonp',
  ).readAsStringSync();
  final hours = parseChinaWeatherHours(source);
  final currentSource = File(
    'test/fixtures/china_weather_hourly/beijing_current.js',
  ).readAsStringSync();
  final now = hours.first.time.subtract(const Duration(minutes: 5));
  http.Response reply(String text) =>
      http.Response.bytes(utf8.encode(text), 200);

  test(
    'current weather preserves the official raw payload and checks area',
    () {
      final current = parseChinaWeatherCurrent(currentSource, '101010100');
      expect(current.raw, chinaWeatherJsonVariable(currentSource, 'dataSK'));
      expect(current.weather, isNotEmpty);
      expect(() => current.raw['weather'] = 'changed', throwsUnsupportedError);
      expect(
        () => parseChinaWeatherCurrent(currentSource, '101210904'),
        throwsFormatException,
      );
      expect(
        () => parseChinaWeatherCurrent(source, '101010100'),
        throwsFormatException,
      );
    },
  );

  test('official payload preserves raw values and hourly Beijing timestamps', () {
    final rows = chinaWeatherJsonVariable(source, 'fc1h_24')['jh'] as List;
    expect(hours, hasLength(rows.length));
    expect(hours.length, 48);
    for (var i = 0; i < hours.length; i++) {
      expect(hours[i].raw, rows[i]);
      final wall = hours[i].time.add(chinaWeatherOffset);
      final stamp =
          '${wall.year}${wall.month.toString().padLeft(2, '0')}'
          '${wall.day.toString().padLeft(2, '0')}${wall.hour.toString().padLeft(2, '0')}'
          '${wall.minute.toString().padLeft(2, '0')}';
      expect(stamp, rows[i]['jf']);
      expect(hours[i].time.isUtc, isTrue);
    }
    expect(() => hours.first.raw['jb'] = '0', throwsUnsupportedError);
  });

  test('JSON scanner handles quoted braces and never executes script', () {
    expect(
      chinaWeatherJsonVariable(
        r'var x={"s":"a\"}b","list":[{}]};throw 1;',
        'x',
      )['s'],
      'a"}b',
    );
    expect(
      () => chinaWeatherJsonVariable('var x=runCode();', 'x'),
      throwsFormatException,
    );
    expect(
      () => parseChinaWeatherHours('<html>denied</html>'),
      throwsFormatException,
    );
  });

  test(
    'rejects gaps, duplicate times and invalid dates without interpolation',
    () {
      final rows = chinaWeatherJsonVariable(source, 'fc1h_24')['jh'] as List;
      String wrap(List rows) => 'var fc1h_24=${jsonEncode({'jh': rows})};';
      expect(
        () => parseChinaWeatherHours(wrap([rows[0], rows[2]])),
        throwsFormatException,
      );
      expect(
        () => parseChinaWeatherHours(wrap([rows[0], rows[0]])),
        throwsFormatException,
      );
      expect(
        () => parseChinaWeatherHours(
          wrap([
            {'jf': '202602300000'},
          ]),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'resolves forecast area separately and caches repeated location requests',
    () async {
      final requests = <http.Request>[];
      final service = ChinaWeatherHourlyService(
        now: () => now,
        client: MockClient((request) async {
          requests.add(request);
          return reply(
            request.url.host == 'd4.weather.com.cn'
                ? location
                : request.url.path.startsWith('/sk_2d/')
                ? currentSource
                : source,
          );
        }),
      );
      addTearDown(service.dispose);
      await service.startForLocation(39.9, 116.4);
      expect(service.state.value.areaId, '101010100');
      expect(service.state.value.areaName, '北京');
      expect(service.state.value.hours, hasLength(48));
      expect(requests[1].url.path, '/wap_40d/101010100.html');
      expect(requests.last.url.path, '/sk_2d/101010100.html');
      expect(
        service.state.value.current?.raw,
        chinaWeatherJsonVariable(currentSource, 'dataSK'),
      );
      expect(
        jsonDecode(requests.first.url.queryParameters['params']!)['lat'],
        39.9,
      );
      await service.startForLocation(39.9, 116.4);
      expect(requests.length, 3);
      service.pause();
      await service.refresh();
      expect(requests.length, 3);
    },
  );

  test(
    'failure is explicit, existing forecast is retained and no false zero values appear',
    () async {
      var fail = false;
      final service = ChinaWeatherHourlyService(
        now: () => now,
        client: MockClient((request) async {
          if (fail) return http.Response('unavailable', 503);
          return reply(
            request.url.host == 'd4.weather.com.cn' ? location : source,
          );
        }),
      );
      addTearDown(service.dispose);
      await service.startForLocation(39.9, 116.4);
      final previous = service.state.value.hours;
      fail = true;
      await service.refresh();
      expect(service.state.value.failed, isTrue);
      expect(service.state.value.hours, same(previous));
      service.pause(clear: true);
      expect(service.state.value.hours, isEmpty);
    },
  );

  test(
    'current weather failure does not replace it with hourly forecast',
    () async {
      var failCurrent = false;
      final service = ChinaWeatherHourlyService(
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.startsWith('/sk_2d/')) {
            return failCurrent ? http.Response('', 503) : reply(currentSource);
          }
          return reply(r.url.host == 'd4.weather.com.cn' ? location : source);
        }),
      );
      addTearDown(service.dispose);
      await service.startForLocation(39.9, 116.4);
      expect(service.state.value.current, isNotNull);
      failCurrent = true;
      await service.refresh();
      expect(service.state.value.current, isNull);
      expect(service.state.value.hours, hasLength(48));
      expect(service.state.value.failed, isFalse);
    },
  );

  test(
    'paused current weather response cannot restore cleared location',
    () async {
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      final service = ChinaWeatherHourlyService(
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.startsWith('/sk_2d/')) {
            requested.complete();
            return pending.future;
          }
          return reply(r.url.host == 'd4.weather.com.cn' ? location : source);
        }),
      );
      addTearDown(service.dispose);
      final loading = service.startForLocation(39.9, 116.4);
      await requested.future;
      service.pause(clear: true);
      pending.complete(reply(currentSource));
      await loading;
      expect(service.state.value.current, isNull);
      expect(service.state.value.hours, isEmpty);
    },
  );

  test(
    'pausing during a request prevents publication and further requests',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final service = ChinaWeatherHourlyService(
        now: () => now,
        client: MockClient((request) async {
          calls++;
          return pending.future;
        }),
      );
      addTearDown(service.dispose);
      final loading = service.startForLocation(39.9, 116.4);
      await Future<void>.delayed(Duration.zero);
      service.pause(clear: true);
      pending.complete(reply(location));
      await loading;
      expect(service.state.value.areaId, isEmpty);
      expect(service.state.value.hours, isEmpty);
      expect(calls, 1);
    },
  );

  test('expired payload is not published', () async {
    final service = ChinaWeatherHourlyService(
      now: () => hours.last.time.add(const Duration(hours: 1)),
      client: MockClient(
        (r) async =>
            reply(r.url.host == 'd4.weather.com.cn' ? location : source),
      ),
    );
    addTearDown(service.dispose);
    await service.startForLocation(39.9, 116.4);
    expect(service.state.value.failed, isTrue);
    expect(service.state.value.hours, isEmpty);
  });

  test(
    'old request cannot restore data after location changes or pause',
    () async {
      final pending = Completer<http.Response>();
      var count = 0;
      final service = ChinaWeatherHourlyService(
        now: () => now,
        client: MockClient((request) async {
          count++;
          if (count == 1) return pending.future;
          return http.Response('lookup failed', 503);
        }),
      );
      addTearDown(service.dispose);
      final first = service.startForLocation(39.9, 116.4);
      await Future<void>.delayed(Duration.zero);
      await service.startForLocation(30.2, 120.1);
      pending.complete(reply(location));
      await first;
      expect(service.state.value.areaId, isEmpty);
      expect(service.state.value.failed, isTrue);
      expect(count, 2);
      service.pause(clear: true);
      await service.refresh();
      expect(count, 2);
    },
  );
}
