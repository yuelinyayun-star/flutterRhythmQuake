import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fan_radar_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

class _LiveHttpOverrides extends HttpOverrides {}

final listBytes = File(
  'test/fixtures/cma_radar/radar_list_20260921.jsonp',
).readAsBytesSync();
final imageBytes = File(
  'test/fixtures/cma_radar/ACHN_QREF_20260921_221200.png',
).readAsBytesSync();
final listText = utf8.decode(listBytes);
List<dynamic> entries() =>
    (jsonDecode(
              listText.substring(
                listText.indexOf('(') + 1,
                listText.lastIndexOf(')'),
              ),
            )
            as Map)['datas']
        as List;
http.Response listResponse([List<dynamic>? frames]) => frames == null
    ? http.Response.bytes(listBytes, 200)
    : http.Response('readRadarList(${jsonEncode({'datas': frames})})', 200);
bool isList(http.Request request) =>
    request.url.path.endsWith('radar_list.json');
http.Response pngResponse() => http.Response.bytes(
  imageBytes,
  200,
  headers: {'content-type': 'image/png'},
);

FanRadarService serviceFor(http.Client client) {
  final service = FanRadarService.forTesting(
    client: client,
    now: () => DateTime.utc(2026, 9, 21, 14, 32),
  );
  addTearDown(() {
    service.stop(clear: true);
    client.close();
  });
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (const bool.fromEnvironment('CMA_RADAR_LIVE')) {
    test(
      'live CMA request parses and decodes the current radar image',
      () async {
        // Only this opt-in probe uses a real socket; normal tests stay offline.
        final socketClient = _LiveHttpOverrides().createHttpClient(null);
        final service = serviceFor(IOClient(socketClient));
        await service.start(startupAttempts: 1);
        final frame = service.latestFrame;
        expect(frame, isNotNull);
        expect(frame!.imageBytes.length, greaterThan(33));
        // ignore: avoid_print
        print(
          'Live CMA: ${frame.time.toIso8601String()} '
          '${frame.width}x${frame.height}, ${frame.imageBytes.length} bytes',
        );
      },
    );
  }

  test(
    'captured CMA list and original PNG replace FAN without altering pixels',
    () async {
      final requests = <http.Request>[];
      final service = serviceFor(
        MockClient((request) async {
          requests.add(request);
          return isList(request) ? listResponse() : pngResponse();
        }),
      );
      await service.start(startupAttempts: 1);
      final frame = service.latestFrame!;
      expect(requests, hasLength(2));
      expect(
        requests.every(
          (r) => r.url.host == 'd1.weather.com.cn' && r.url.scheme == 'https',
        ),
        isTrue,
      );
      expect(requests.first.url.queryParameters['callback'], 'readRadarList');
      expect(
        requests.first.url.queryParameters['_'],
        '${DateTime.utc(2026, 9, 21, 14, 32).millisecondsSinceEpoch}',
      );
      expect(
        requests.every(
          (r) => r.headers['referer'] == 'https://www.weather.com.cn/',
        ),
        isTrue,
      );
      expect(
        requests.last.url.path,
        '/radar_channel/radar/pic/ACHN_QREF_20260921_221200.png',
      );
      expect(frame.time, DateTime.utc(2026, 9, 21, 14, 12));
      expect(frame.width, 2882);
      expect(frame.height, 2161);
      expect(frame.southWest.latitude, 12.316339);
      expect(frame.northEast.longitude, 140.209411);
      expect(frame.imageBytes, imageBytes);
      final restored = ForegroundStationPayload.decodeFanRadar(
        ForegroundStationPayload.fanRadar(frame),
      )!;
      expect(restored.imageBytes, imageBytes);
      expect(restored.time, frame.time);
      expect(restored.southWest, frame.southWest);
    },
  );

  test(
    'selection follows latest dt even when original entries arrive reversed',
    () async {
      final service = serviceFor(
        MockClient(
          (r) async => isList(r)
              ? listResponse(entries().reversed.toList())
              : pngResponse(),
        ),
      );
      await service.start(startupAttempts: 1);
      expect(service.latestFrame!.time, DateTime.utc(2026, 9, 21, 14, 12));
    },
  );

  test(
    'same frame and older list do not download or publish images again',
    () async {
      var lists = 0;
      var images = 0;
      final frames = <FanRadarFrame?>[];
      final service = serviceFor(
        MockClient((r) async {
          if (isList(r)) {
            lists++;
            return lists < 3
                ? listResponse()
                : listResponse(entries().take(23).toList());
          }
          images++;
          return pngResponse();
        }),
      );
      final subscription = service.frameStream.listen(frames.add);
      addTearDown(subscription.cancel);
      await service.start(startupAttempts: 1);
      await service.fetchNow();
      await service.fetchNow();
      await Future<void>.delayed(Duration.zero);
      expect(lists, 3);
      expect(images, 1);
      expect(frames, hasLength(1));
    },
  );

  test('bad list response preserves the last valid image', () async {
    var first = true;
    final service = serviceFor(
      MockClient((r) async {
        if (!isList(r)) return pngResponse();
        if (first) {
          first = false;
          return listResponse();
        }
        return http.Response('<html>unavailable</html>', 200);
      }),
    );
    await service.start(startupAttempts: 1);
    final original = service.latestFrame;
    await service.fetchNow();
    expect(identical(service.latestFrame, original), isTrue);
  });

  for (final failure in ['html', 'truncated', 'http']) {
    test(
      'rejects $failure images and retries the same original frame later',
      () async {
        var failed = true;
        final service = serviceFor(
          MockClient((r) async {
            if (isList(r)) return listResponse();
            if (!failed) return pngResponse();
            return switch (failure) {
              'html' => http.Response('<html>data contact</html>', 200),
              'truncated' => http.Response.bytes(
                imageBytes.sublist(0, 33),
                200,
              ),
              _ => http.Response('', 503),
            };
          }),
        );
        await service.start(startupAttempts: 1);
        expect(service.latestFrame, isNull);
        failed = false;
        await service.fetchNow();
        expect(service.latestFrame!.imageBytes, imageBytes);
      },
    );
  }

  for (final list in [
    'readRadarList({"datas":[]})',
    'otherCallback({"datas":[]})',
    'readRadarList({"datas":[{"dt":"20260921141200","fn":"https://example.com/image.png"}]})',
    'readRadarList({"datas":[{"dt":"20260230000000","fn":"ACHN_QREF_20260230_000000.png"}]})',
  ]) {
    test('invalid list cannot trigger an image request: $list', () async {
      var requests = 0;
      final service = serviceFor(
        MockClient((r) async {
          requests++;
          return http.Response(list, 200);
        }),
      );
      await service.start(startupAttempts: 1);
      expect(requests, 1);
      expect(service.latestFrame, isNull);
    });
  }

  test('stop during image download discards the result', () async {
    final download = Completer<http.Response>();
    final requested = Completer<void>();
    final service = serviceFor(
      MockClient((r) async {
        if (isList(r)) return listResponse();
        requested.complete();
        return download.future;
      }),
    );
    final pending = service.start(startupAttempts: 1);
    await requested.future;
    service.stop(clear: true);
    download.complete(pngResponse());
    await pending;
    expect(service.latestFrame, isNull);
    expect(service.isRunning, isFalse);
  });

  test(
    'restart during an old request still fetches for the new session',
    () async {
      final download = Completer<http.Response>();
      final requested = Completer<void>();
      var pictures = 0;
      final service = serviceFor(
        MockClient((r) async {
          if (isList(r)) return listResponse();
          pictures++;
          if (pictures > 1) return pngResponse();
          requested.complete();
          return download.future;
        }),
      );
      final pending = service.start(startupAttempts: 1);
      await requested.future;
      service.stop(clear: true);
      await service.start(startupAttempts: 1);
      download.complete(http.Response('old session', 503));
      await pending;
      expect(pictures, 2);
      expect(service.latestFrame!.imageBytes, imageBytes);
    },
  );

  test(
    'restart replays cache for Android subscribers without re-downloading',
    () async {
      var pictures = 0;
      final service = serviceFor(
        MockClient((r) async {
          if (isList(r)) return listResponse();
          pictures++;
          return pngResponse();
        }),
      );
      await service.start(startupAttempts: 1);
      service.stop();
      final next = service.frameStream.first;
      await service.start(startupAttempts: 1);
      expect((await next)!.imageBytes, imageBytes);
      expect(pictures, 1);
      service.stop(clear: true);
      await service.start(startupAttempts: 1);
      expect(pictures, 2);
    },
  );
}
