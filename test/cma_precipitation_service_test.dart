import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fan_radar_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

class _LiveHttpOverrides extends HttpOverrides {}

final listBytes = File(
  'test/fixtures/cma_precipitation/rain_list.jsonp',
).readAsBytesSync();
final imageBytes = File(
  'test/fixtures/cma_precipitation/prec_2026092122.png',
).readAsBytesSync();
final text = utf8.decode(listBytes);
List<dynamic> entries() =>
    (jsonDecode(text.substring(text.indexOf('(') + 1, text.lastIndexOf(')')))
            as Map)['datas']
        as List;
bool isList(http.Request r) => r.url.path.endsWith('rainList.json');
http.Response listResponse([List<dynamic>? items]) => items == null
    ? http.Response.bytes(listBytes, 200)
    : http.Response('getPreObs1h(${jsonEncode({'datas': items})})', 200);
http.Response picture() => http.Response.bytes(imageBytes, 200);
FanRadarService rainService(http.Client client) {
  final service = FanRadarService.forTesting(
    client: client,
    product: CmaImageProduct.precipitation,
  );
  addTearDown(() {
    service.stop(clear: true);
    client.close();
  });
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('CMA_PRECIPITATION_LIVE')) {
    test('live China Weather precipitation loads and decodes', () async {
      final service = rainService(
        IOClient(_LiveHttpOverrides().createHttpClient(null)),
      );
      await service.start(startupAttempts: 1);
      expect(service.latestFrame, isNotNull);
      final frame = service.latestFrame!;
      // ignore: avoid_print
      print(
        'Live precipitation: ${frame.time} ${frame.width}x${frame.height}, ${frame.imageBytes.length} bytes',
      );
    });
  }

  test(
    'original hourly list and PNG use rain bounds and Android handoff',
    () async {
      final requests = <http.Request>[];
      final service = rainService(
        MockClient((r) async {
          requests.add(r);
          return isList(r) ? listResponse() : picture();
        }),
      );
      await service.start(startupAttempts: 1);
      expect(requests, hasLength(2));
      expect(requests.first.url.queryParameters['callback'], 'getPreObs1h');
      expect(
        requests.last.url.path,
        '/radar_channel/prec1h/prec_2026092122.png',
      );
      expect(
        requests.every(
          (r) => r.url.scheme == 'https' && r.url.host == 'd1.weather.com.cn',
        ),
        isTrue,
      );
      expect(
        requests.every(
          (r) => r.headers['referer'] == 'https://www.weather.com.cn/',
        ),
        isTrue,
      );
      final frame = service.latestFrame!;
      expect(frame.time, DateTime.utc(2026, 9, 21, 14));
      expect(frame.width, 3600);
      expect(frame.height, 2733);
      expect(frame.southWest.latitude, 18);
      expect(frame.southWest.longitude, 73);
      expect(frame.northEast.latitude, 55);
      expect(frame.northEast.longitude, 136);
      expect(frame.imageBytes, imageBytes);
      final payload = ForegroundStationPayload.cmaPrecipitation(frame);
      expect(payload['kind'], 'cmaPrecipitation');
      final restored = ForegroundStationPayload.decodeFanRadar(payload)!;
      expect(restored.imageBytes, imageBytes);
      expect(restored.time, frame.time);
      expect(restored.northEast, frame.northEast);
    },
  );

  test(
    'latest hourly frame is selected without depending on list order',
    () async {
      final service = rainService(
        MockClient(
          (r) async =>
              isList(r) ? listResponse(entries().reversed.toList()) : picture(),
        ),
      );
      await service.start(startupAttempts: 1);
      expect(service.latestFrame!.time, DateTime.utc(2026, 9, 21, 14));
    },
  );

  test('same and older hourly lists do not fetch duplicate PNGs', () async {
    var lists = 0;
    var pictures = 0;
    final service = rainService(
      MockClient((r) async {
        if (isList(r)) {
          return ++lists < 3
              ? listResponse()
              : listResponse(entries().take(24).toList());
        }
        pictures++;
        return picture();
      }),
    );
    await service.start(startupAttempts: 1);
    await service.fetchNow();
    await service.fetchNow();
    expect(pictures, 1);
  });

  test(
    'wrong callback and HTML never replace a valid precipitation frame',
    () async {
      var initial = true;
      final service = rainService(
        MockClient((r) async {
          if (!isList(r)) return picture();
          if (initial) {
            initial = false;
            return listResponse();
          }
          return http.Response('readRadarList({"datas":[]})', 200);
        }),
      );
      await service.start(startupAttempts: 1);
      final frame = service.latestFrame;
      await service.fetchNow();
      expect(identical(frame, service.latestFrame), isTrue);
    },
  );

  test(
    'independent products and layer toggles do not change existing rain/radar',
    () {
      expect(
        identical(FanRadarService(), FanRadarService.precipitation()),
        isFalse,
      );
      expect(
        FanRadarService.precipitation().product,
        CmaImageProduct.precipitation,
      );
      final map = MapStateProvider();
      addTearDown(map.dispose);
      expect(map.isOverlayEnabled('precipitationChinaLayer'), isFalse);
      map.setOverlayEnabled('precipitationChinaLayer', true);
      expect(map.isOverlayEnabled('precipitationChinaLayer'), isTrue);
      expect(map.isOverlayEnabled('rainLayer'), isFalse);
      expect(map.isOverlayEnabled('radarChinaLayer'), isFalse);
    },
  );
}
