import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/jma_satellite_cloud_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Entries observed in JMA's targetTimes_fd.json on 2026-09-22.
const older = {'basetime': '20260922050000', 'validtime': '20260922050000'};
const newer = {'basetime': '20260922051000', 'validtime': '20260922051000'};

http.Response times(List<Object?> entries) =>
    http.Response(jsonEncode(entries), 200);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('selects latest UTC observation regardless of list ordering', () {
    final frame = jmaSatelliteFrameFromTargetTimes([newer, older])!;
    expect(frame.time, DateTime.utc(2026, 9, 22, 5, 10));
    expect(frame.time.isUtc, isTrue);
    expect(
      frame.tileUrlTemplate,
      'https://www.jma.go.jp/bosai/himawari/data/satimg/'
      '20260922051000/fd/20260922051000/B13/TBB/{z}/{x}/{y}.jpg',
    );
    expect(jmaSatelliteFrameFromTargetTimes([older, newer])!.time, frame.time);
    expect(
      JmaSatelliteCloudService.refreshInterval,
      const Duration(minutes: 10),
    );
  });

  test('rejects malformed and overflowed dates, including the base time', () {
    for (final value in [
      null,
      20260922051000,
      '',
      '../20260922051000',
      '20260230000000',
      '20261301000000',
      '20260922250000',
      '20260922056000',
      '20260922051060',
      '202609220510',
    ]) {
      expect(jmaSatelliteTimeFromStamp(value), isNull);
      expect(
        jmaSatelliteFrameFromTargetTime({
          'basetime': value,
          'validtime': newer['validtime'],
        }),
        isNull,
      );
    }
    expect(jmaSatelliteFrameFromTargetTimes({}), isNull);
    expect(jmaSatelliteFrameFromTargetTimes([null, 1, {}]), isNull);
  });

  test('Android payload round trip validates stamps and keeps UTC', () {
    final frame = jmaSatelliteFrameFromTargetTimes([newer])!;
    final payload = ForegroundStationPayload.jmaSatelliteCloud(frame);
    expect(payload['kind'], 'jmaSatelliteCloud');
    final decoded = ForegroundStationPayload.decodeJmaSatelliteCloud(payload)!;
    expect(decoded.time, frame.time);
    expect(decoded.tileUrlTemplate, frame.tileUrlTemplate);
    expect(ForegroundStationPayload.decodeJmaSatelliteCloud({}), isNull);
  });

  test('off means no requests; stop clears the frame', () async {
    var requests = 0;
    final service = JmaSatelliteCloudService.forTest(
      client: MockClient((req) async {
        requests++;
        expect(req.url.toString(), JmaSatelliteCloudService.targetTimesUrl);
        return times([older, newer]);
      }),
    );
    addTearDown(() => service.stop(clear: true));
    await service.fetchNow();
    expect(requests, 0);
    final first = service.frameStream.first;
    service.start();
    expect((await first)!.time, DateTime.utc(2026, 9, 22, 5, 10));
    service.stop(clear: true);
    await service.fetchNow();
    expect(service.latestFrame, isNull);
    expect(service.isRunning, isFalse);
    expect(requests, 1);
  });

  test(
    'duplicate, malformed, older and HTTP error responses retain current frame',
    () async {
      var response = times([newer]);
      final service = JmaSatelliteCloudService.forTest(
        client: MockClient((_) async => response),
      );
      addTearDown(() => service.stop(clear: true));
      final frames = <JmaSatelliteCloudFrame?>[];
      final sub = service.frameStream.listen(frames.add);
      addTearDown(sub.cancel);
      service.start();
      await flush();
      for (final next in [
        times([newer]),
        times([older]),
        times([]),
        http.Response('<html>unavailable</html>', 200),
        http.Response('', 503),
      ]) {
        response = next;
        await service.fetchNow();
      }
      await flush();
      expect(frames, hasLength(1));
      expect(service.latestFrame!.validtime, newer['validtime']);
    },
  );

  test('stop discards in-flight responses', () async {
    final pending = Completer<http.Response>();
    final service = JmaSatelliteCloudService.forTest(
      client: MockClient((_) => pending.future),
    );
    service.start();
    await flush();
    service.stop(clear: true);
    pending.complete(times([newer]));
    await flush();
    expect(service.latestFrame, isNull);
  });

  test(
    'restart during an old request processes the queued new session',
    () async {
      final pending = Completer<http.Response>();
      var requests = 0;
      final service = JmaSatelliteCloudService.forTest(
        client: MockClient((_) {
          requests++;
          return requests == 1 ? pending.future : Future.value(times([newer]));
        }),
      );
      addTearDown(() => service.stop(clear: true));
      service.start();
      await flush();
      service.stop(clear: true);
      final result = service.frameStream.first;
      service.start();
      pending.complete(times([older]));
      expect(
        (await result.timeout(const Duration(seconds: 2)))!.validtime,
        newer['validtime'],
      );
      expect(requests, 2);
    },
  );

  test(
    'restart replays cached frame for a new background subscriber',
    () async {
      final service = JmaSatelliteCloudService.forTest(
        client: MockClient((_) async => times([newer])),
      );
      addTearDown(() => service.stop(clear: true));
      final first = service.frameStream.first;
      service.start();
      await first;
      service.stop();
      final replay = service.frameStream.first;
      service.start();
      expect((await replay)!.validtime, newer['validtime']);
    },
  );
}
