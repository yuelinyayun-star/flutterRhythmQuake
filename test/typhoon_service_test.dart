import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/typhoon_data.dart';
import 'package:flutterrhythmquake/services/sources/typhoon_service.dart';

const cacheKey = 'typhoon_zj_active_cache_v1';
final capturedAt = DateTime.utc(2026, 9, 21, 14);
final activityBytes = File(
  'test/fixtures/typhoon/zj_activity_20260921.json',
).readAsBytesSync();
final detailBytes = File(
  'test/fixtures/typhoon/zj_202625_20260921.json',
).readAsBytesSync();
Map<String, dynamic> detail() =>
    jsonDecode(utf8.decode(detailBytes)) as Map<String, dynamic>;
http.Response activityResponse() => http.Response.bytes(activityBytes, 200);
http.Response detailResponse() => http.Response.bytes(detailBytes, 200);
bool isActivity(http.Request request) =>
    request.url.path.endsWith('TyhoonActivity');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'uses Zhejiang activity and detail endpoints with original captured data',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return isActivity(request) ? activityResponse() : detailResponse();
      });
      addTearDown(client.close);
      final service = TyphoonService(client: client, now: () => capturedAt);
      final items = await service.fetchActiveNow();
      expect(requests.map((r) => r.url.host).toSet(), {
        'typhoon.slt.zj.gov.cn',
      });
      expect(requests.map((r) => r.url.path), [
        '/Api/TyhoonActivity',
        '/Api/TyphoonInfo/202625',
      ]);
      expect(
        requests.every(
          (r) =>
              r.url.queryParameters['time'] ==
              '${capturedAt.millisecondsSinceEpoch}',
        ),
        isTrue,
      );
      expect(items.single.tfid, '202625');
      expect(items.single.isActive, isTrue);
      expect(items.single.points.length, (detail()['points'] as List).length);
      expect(
        items.single.latestPoint!.forecast.map((f) => f.agency),
        containsAll(['中国', '中国台湾', '日本', '中国香港', '美国']),
      );
    },
  );

  test('fetchById uses detail route, and empty ID does not request', () async {
    final requests = <Uri>[];
    final service = TyphoonService(
      client: MockClient((r) async {
        requests.add(r.url);
        return detailResponse();
      }),
    );
    expect(await service.fetchById(' '), isEmpty);
    expect((await service.fetchById(' 202625 ')).single.tfid, '202625');
    expect(requests.single.path, '/Api/TyphoonInfo/202625');
  });

  test(
    'unchanged snapshots emit once and cache the original detail object',
    () async {
      final service = TyphoonService(
        client: MockClient(
          (r) async => isActivity(r) ? activityResponse() : detailResponse(),
        ),
        now: () => capturedAt,
      );
      final updates = <List<TyphoonData>>[];
      service.onActiveTyphoonsChanged = updates.add;
      await service.fetchNow();
      await service.fetchNow();
      expect(updates.length, 1);
      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(prefs.getString(cacheKey)!);
      expect(cached['details'], [detail()]);
    },
  );

  test(
    'detail failure retains only a still-active ID; empty list removes it',
    () async {
      var phase = 0;
      var detailCalls = 0;
      final service = TyphoonService(
        client: MockClient((r) async {
          if (isActivity(r)) {
            return phase == 2 ? http.Response('[]', 200) : activityResponse();
          }
          detailCalls++;
          return phase == 0 ? detailResponse() : http.Response('', 503);
        }),
      );
      final updates = <List<TyphoonData>>[];
      service.onActiveTyphoonsChanged = updates.add;
      await service.fetchNow();
      phase = 1;
      await service.fetchNow();
      expect(updates.length, 1);
      expect(
        (await SharedPreferences.getInstance()).containsKey(cacheKey),
        isFalse,
      );
      phase = 2;
      await service.fetchNow();
      expect(updates.last, isEmpty);
      expect(detailCalls, 2);
    },
  );

  // Controlled transport/protocol failures, not observed meteorological data.
  for (final failure in [
    http.Response('', 503),
    http.Response('{"msg":"unavailable"}', 200),
    http.Response('[{}]', 200),
    http.Response('<html>error</html>', 200),
  ]) {
    test(
      'failed activity does not clear known data: ${failure.statusCode}/${failure.body}',
      () async {
        var failing = false;
        final service = TyphoonService(
          client: MockClient((r) async {
            if (isActivity(r)) return failing ? failure : activityResponse();
            return detailResponse();
          }),
        );
        final updates = <List<TyphoonData>>[];
        service.onActiveTyphoonsChanged = updates.add;
        await service.fetchNow();
        failing = true;
        await service.fetchNow();
        expect(updates.length, 1);
        expect(updates.single.single.tfid, '202625');
      },
    );
  }

  test('invalid detail does not become a successful empty snapshot', () async {
    final service = TyphoonService(
      client: MockClient(
        (r) async =>
            isActivity(r) ? activityResponse() : http.Response('{}', 200),
      ),
    );
    await expectLater(service.fetchActiveNow(), throwsFormatException);
  });

  test('stopped request cannot emit or save cache', () async {
    final pending = Completer<http.Response>();
    final entered = Completer<void>();
    final service = TyphoonService(
      client: MockClient((r) async {
        if (isActivity(r)) return activityResponse();
        entered.complete();
        return pending.future;
      }),
    );
    final updates = <List<TyphoonData>>[];
    service.onActiveTyphoonsChanged = updates.add;
    final fetch = service.fetchNow();
    await entered.future;
    service.stop(clearState: true);
    pending.complete(detailResponse());
    await fetch;
    expect(updates, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).containsKey(cacheKey),
      isFalse,
    );
  });

  test(
    'new generation can fetch while an old request is still pending',
    () async {
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      var first = true;
      final service = TyphoonService(
        client: MockClient((r) async {
          if (isActivity(r)) return activityResponse();
          if (first) {
            first = false;
            entered.complete();
            return pending.future;
          }
          return detailResponse();
        }),
      );
      final updates = <List<TyphoonData>>[];
      service.onActiveTyphoonsChanged = updates.add;
      final old = service.fetchNow();
      await entered.future;
      service.stop(clearState: true);
      await service.fetchNow();
      pending.complete(detailResponse());
      await old;
      expect(updates.length, 1);
    },
  );

  for (final age in [
    Duration.zero,
    const Duration(hours: 2),
    const Duration(minutes: -1),
  ]) {
    test('cache freshness gate: $age', () async {
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode({
          'savedAt': capturedAt.subtract(age).millisecondsSinceEpoch,
          'details': [detail()],
        }),
      });
      final entered = Completer<void>();
      final pending = Completer<http.Response>();
      final service = TyphoonService(
        now: () => capturedAt,
        client: MockClient((r) {
          entered.complete();
          return pending.future;
        }),
      );
      final updates = <List<TyphoonData>>[];
      service.onActiveTyphoonsChanged = updates.add;
      service.start();
      await entered.future;
      expect(updates.length, age == Duration.zero ? 1 : 0);
      service.stop();
      pending.complete(http.Response('[]', 200));
      await Future<void>.delayed(Duration.zero);
    });
  }

  test('legacy FAN cache is never loaded', () async {
    SharedPreferences.setMockInitialValues({
      'typhoon_active_cache_body': utf8.decode(detailBytes),
      'typhoon_active_cache_saved_at': capturedAt.millisecondsSinceEpoch,
    });
    final entered = Completer<void>();
    final service = TyphoonService(
      now: () => capturedAt,
      client: MockClient((r) async {
        entered.complete();
        return http.Response('', 503);
      }),
    );
    addTearDown(service.stop);
    final updates = <List<TyphoonData>>[];
    service.onActiveTyphoonsChanged = updates.add;
    service.start();
    await entered.future;
    expect(updates, isEmpty);
  });

  testWidgets('polls every five minutes; errors retry after thirty seconds', (
    tester,
  ) async {
    var calls = 0;
    var failing = false;
    final service = TyphoonService(
      client: MockClient((r) async {
        calls++;
        return failing ? http.Response('', 503) : http.Response('[]', 200);
      }),
    );
    addTearDown(service.stop);
    service.start();
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(calls, 1);
    expect(service.isRunning, isTrue);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(calls, 1);
    failing = true;
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 29));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 3);
    service.stop();
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 3);
  });

  test(
    'background serialization preserves all parsed fields and signature',
    () {
      final original = TyphoonData.fromMap(detail())!;
      final restored = TyphoonData.fromMap(
        jsonDecode(jsonEncode(original.toMap())),
      )!;
      expect(restored.signature, original.signature);
      expect(restored.latestPoint!.radius7, original.latestPoint!.radius7);
    },
  );

  // Deliberately constructed model edge cases; captured fixtures above stay intact.
  test('wind radius zero keeps its quadrant; malformed radii are rejected', () {
    expect(TyphoonPoint.fromJson({'radius7': '100|0|300|400'})!.radius7, [
      100,
      0,
      300,
      400,
    ]);
    for (final value in [
      '100|bad|300|400',
      '100|NaN|300|400',
      '100|-1|300|400',
      '100|300|400',
    ]) {
      expect(TyphoonPoint.fromJson({'radius7': value})!.radius7, isEmpty);
    }
  });

  test('nonfinite and out-of-range coordinates cannot reach the map', () {
    for (final lat in ['NaN', 'Infinity', '91', '-91']) {
      expect(
        TyphoonPoint.fromJson({'lat': lat, 'lng': '120'})!.hasLocation,
        isFalse,
      );
    }
  });

  test('forecast-only and wind-only changes affect signature', () {
    TyphoonData sample({String radius = '1|2|3|4', int wind = 20}) =>
        TyphoonData.fromMap({
          'tfid': 'test',
          'points': [
            {
              'radius7': radius,
              'forecast': [
                {
                  'tm': 'test',
                  'forecastpoints': [
                    {'speed': wind},
                  ],
                },
              ],
            },
          ],
        })!;
    expect(sample(radius: '1|2|3|5').signature, isNot(sample().signature));
    expect(sample(wind: 21).signature, isNot(sample().signature));
  });
}
