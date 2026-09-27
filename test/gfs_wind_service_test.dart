import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/gfs_wind_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uses and caches Jian U/V grid only when Open-Meteo fails', () async {
    final requests = <Uri>[];
    var primaryAvailable = false;
    final u = List<int>.generate(
      360 * 181,
      (index) => index % 360 == 359 ? 4 : 2,
    );
    final v = List<int>.filled(360 * 181, 1);
    final jianBody = jsonEncode({
      'status': 'success',
      'time': '2026-09-23 16:00:00',
      'source': 'gfs',
      'level': '10m',
      'nx': 360,
      'ny': 181,
      'data': [
        {
          'header': {
            'parameterNumber': 2,
            'nx': 360,
            'ny': 181,
            'lo1': 0,
            'la1': 90,
            'dx': 1,
            'dy': 1,
          },
          'data': u,
        },
        {
          'header': {
            'parameterNumber': 3,
            'nx': 360,
            'ny': 181,
            'lo1': 0,
            'la1': 90,
            'dx': 1,
            'dy': 1,
          },
          'data': v,
        },
      ],
    });
    final service = GfsWindService(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.host == 'api.sismotide.top') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(jianBody, 200);
        }
        if (!primaryAvailable) return http.Response('', 503);
        return http.Response(
          jsonEncode(
            List.generate(
              63,
              (_) => {
                'current': {
                  'time': '2026-09-23T09:00',
                  'wind_speed_10m': 5,
                  'wind_direction_10m': 90,
                },
              },
            ),
          ),
          200,
        );
      }),
    );
    addTearDown(service.close);

    final first = service.fetch(south: 30, north: 31, west: 359, east: 360);
    final concurrent = service.fetch(
      south: 31,
      north: 32,
      west: 140,
      east: 141,
    );
    final fallback = await first;
    await concurrent;
    expect(fallback.time, DateTime.utc(2026, 9, 23, 8));
    expect(fallback.sample(30.5, 359.5)!.east, closeTo(3, 0.001));
    expect(fallback.sample(30.5, 359.5)!.north, closeTo(1, 0.001));
    await service.fetch(south: 32, north: 33, west: 135, east: 136);
    expect(requests.where((uri) => uri.path == '/get/wind.php'), hasLength(1));

    primaryAvailable = true;
    final recovered = await service.fetch(
      south: 30,
      north: 31,
      west: 130,
      east: 131,
    );
    expect(recovered.sample(30.5, 130.5)!.east, closeTo(-5, 0.001));
    expect(requests.where((uri) => uri.path == '/get/wind.php'), hasLength(1));
  });

  test('rejects incomplete Jian components after primary failure', () async {
    final service = GfsWindService(
      client: MockClient(
        (request) async => request.url.host == 'api.sismotide.top'
            ? http.Response('{"status":"success","data":[]}', 200)
            : http.Response('', 503),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.fetch(south: 30, north: 31, west: 130, east: 131),
      throwsFormatException,
    );
  });

  test(
    'parses current GFS wind and converts from-direction to flow vector',
    () async {
      Uri? requested;
      final service = GfsWindService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode(
              List.generate(
                63,
                (_) => {
                  'current': {
                    'time': '2026-09-23T06:45',
                    'wind_speed_10m': 10,
                    'wind_direction_10m': 90,
                  },
                },
              ),
            ),
            200,
          );
        }),
      );

      final grid = await service.fetch(
        south: 30,
        north: 40,
        west: 130,
        east: 140,
      );
      expect(requested!.host, 'api.open-meteo.com');
      expect(requested!.path, '/v1/gfs');
      expect(requested!.queryParameters['wind_speed_unit'], 'ms');
      expect(requested!.queryParameters['models'], 'gfs_global');
      expect(requested!.queryParameters['latitude']!.split(','), hasLength(63));
      expect(grid.time, DateTime.utc(2026, 9, 23, 6, 45));
      expect(grid.sample(35, 135)!.east, closeTo(-10, 0.001));
      expect(grid.sample(35, 135)!.north, closeTo(0, 0.001));
      expect(grid.covers(south: 31, north: 39, west: 131, east: 139), isTrue);
      expect(grid.sample(41, 135), isNull);
      service.close();
    },
  );

  test('interpolates across the date line using the same wind grid', () {
    final grid = GfsWindGrid(
      south: 0,
      north: 10,
      west: 170,
      east: 190,
      rows: 2,
      columns: 2,
      time: DateTime.utc(2026),
      vectors: const [
        GfsWindVector(0, 0),
        GfsWindVector(10, 0),
        GfsWindVector(0, 10),
        GfsWindVector(10, 10),
      ],
    );
    expect(grid.sample(5, -180)!.east, closeTo(5, 0.001));
    expect(grid.sample(5, -180)!.north, closeTo(5, 0.001));
    expect(grid.covers(south: 1, north: 9, west: 175, east: 185), isTrue);
  });

  test('a global grid covers either wrapped view of the date line', () {
    final grid = GfsWindGrid(
      south: -80,
      north: 80,
      west: -180,
      east: 180,
      rows: 2,
      columns: 2,
      time: DateTime.utc(2026),
      vectors: const [
        GfsWindVector(1, 0),
        GfsWindVector(1, 0),
        GfsWindVector(1, 0),
        GfsWindVector(1, 0),
      ],
    );
    expect(grid.covers(south: -50, north: 50, west: 170, east: 190), isTrue);
    expect(grid.covers(south: -50, north: 50, west: -190, east: -170), isTrue);
  });

  test('rejects an incomplete location response', () async {
    final service = GfsWindService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'current': {}},
          ]),
          200,
        ),
      ),
    );
    await expectLater(
      service.fetch(south: 30, north: 40, west: 130, east: 140),
      throwsFormatException,
    );
    service.close();
  });
}
