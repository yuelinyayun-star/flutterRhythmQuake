import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';

const directory = 'test/fixtures/usgs_shakemap';
Map<String, dynamic> readJson(String file) =>
    jsonDecode(File('$directory/$file').readAsStringSync());

// Views of actual captured superseded products. Product fields, coordinates,
// origin and publication timestamps are retained without alteration.
Map<String, dynamic> detailVersion(String version) {
  final detail = readJson('us6000u0xi.versions.original.geojson');
  final product = (detail['properties']['products']['shakemap'] as List)
      .firstWhere((p) => p['properties']['version'] == version);
  return {
    ...detail,
    'properties': {
      ...detail['properties'],
      'products': {
        'shakemap': [product],
      },
    },
  };
}

QuakeMessage eventFor(Map<String, dynamic> detail) {
  final p = detail['properties'];
  final coords = detail['geometry']['coordinates'];
  final product = UsgsShakeMapProduct.fromDetail(detail)!;
  return QuakeMessage(
    source: QuakeSourceType.usgs,
    eventId: detail['id'],
    location: p['place'],
    magnitude: (p['mag'] as num).toDouble(),
    latitude: (coords[1] as num).toDouble(),
    longitude: (coords[0] as num).toDouble(),
    depth: (coords[2] as num).toDouble(),
    originTime: DateTime.fromMillisecondsSinceEpoch(
      p['time'],
      isUtc: true,
    ).toLocal(),
    timeZone: DateTime.now().timeZoneOffset.inHours,
    isHistory: true,
    usgsDetailUrl:
        'https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=${detail['id']}&format=geojson',
    usgsProductTypes: ',origin,shakemap,',
    usgsUpdated: product.updated.millisecondsSinceEpoch,
  );
}

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

http.Response contourResponse(Uri url) {
  final detail = readJson('us6000u0xi.versions.original.geojson');
  final products = detail['properties']['products']['shakemap'] as List;
  for (final product in products) {
    final contents = product['contents'] as Map;
    const key = 'download/cont_mmi.json';
    if (contents[key]?['url'] != url.toString()) continue;
    final version = product['properties']['version'];
    final suffix = version == '3' ? '' : '.v$version';
    return http.Response.bytes(
      File(
        '$directory/us6000u0xi$suffix.cont_mmi.original.json',
      ).readAsBytesSync(),
      200,
    );
  }
  return http.Response('', 404);
}

void main() {
  test('preferred real product retains MMI and original geographic bounds', () {
    final detail = readJson('us6000u0xi.versions.original.geojson');
    final product = UsgsShakeMapProduct.fromDetail(detail)!;
    expect(product.version, '3');
    expect(product.eventId, 'us6000u0xi');
    expect(product.updated.millisecondsSinceEpoch, 1791457492389);
    expect(product.south, -16.441);
    expect(product.west, 167.25);
    expect(product.maxMmi, 7.654);
    expect(product.contoursUrl?.path, endsWith('/download/cont_mmi.json'));
  });

  test('USGS reference survives foreground serialization and copy', () {
    final event = eventFor(detailVersion('3'));
    final restored = QuakeMessage.fromMap(
      event.copyWith(location: event.location).toMap(),
    );
    expect(restored.usgsUpdated, event.usgsUpdated);
    expect(restored.usgsDetailUrl, event.usgsDetailUrl);
    expect(restored.usgsProductTypes, event.usgsProductTypes);
  });

  test('missing ShakeMap is an absent product, not fabricated intensity', () {
    final summary = readJson('summary.original.geojson');
    expect(UsgsShakeMapProduct.fromDetail(summary['features'][0]), isNull);
  });

  test(
    'startup baseline is silent; actual version update displays once',
    () async {
      var detail = detailVersion('1');
      var contourRequests = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/cont_mmi.json')) {
          contourRequests++;
          return contourResponse(request.url);
        }
        return http.Response(jsonEncode(detail), 200);
      });
      final service = UsgsShakeMapService(client: client);
      addTearDown(service.dispose);
      // FAN may arrive before the official HTTP catalogue. That does not
      // establish an empty baseline or replay all historical maps later.
      final fanMap = eventFor(detail).toMap()
        ..remove('usgsDetailUrl')
        ..remove('usgsProductTypes')
        ..remove('usgsUpdated');
      await service.observe([QuakeMessage.fromMap(fanMap)]);
      final initial = service.observe([eventFor(detail)]);
      await service.observe([
        eventFor(detail),
      ]); // repeated catalogue during initial fetch
      await initial;
      await settle();
      expect(service.frame, isNull);
      expect(contourRequests, 0);
      detail = detailVersion('3');
      await service.observe([eventFor(detail)]);
      await settle();
      expect(service.frame?.product.version, '3');
      final count = contourRequests;
      await service.observe([eventFor(detail)]);
      await settle();
      expect(contourRequests, count);
    },
  );

  test(
    'history selection independently loads an old actual earthquake',
    () async {
      final detail = detailVersion('3');
      final client = MockClient(
        (request) async => request.url.path.endsWith('/cont_mmi.json')
            ? contourResponse(request.url)
            : http.Response(jsonEncode(detail), 200),
      );
      final service = UsgsShakeMapService(client: client);
      addTearDown(service.dispose);
      await service.select(eventFor(detail));
      expect(service.frame?.event.eventId, 'us6000u0xi');
      expect(service.frame?.product.version, '3');
      expect(service.status, isNull);
      await service.select(null);
      expect(service.frame, isNull);
    },
  );

  test(
    'cancelled history selection cannot be restored by a late response',
    () async {
      final detail = detailVersion('3');
      final response = Completer<http.Response>();
      final service = UsgsShakeMapService(
        client: MockClient((_) => response.future),
      );
      addTearDown(service.dispose);
      final pending = service.select(eventFor(detail));
      await service.select(null);
      response.complete(http.Response(jsonEncode(detail), 200));
      await pending;
      expect(service.frame, isNull);
      expect(service.status, isNull);
    },
  );

  test(
    'a failed new contour response is retried and retains the earlier contours',
    () async {
      var detail = detailVersion('1');
      var failContours = false;
      final service = UsgsShakeMapService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cont_mmi.json')) {
            return failContours
                ? http.Response('unavailable', 503)
                : contourResponse(request.url);
          }
          return http.Response(jsonEncode(detail), 200);
        }),
      );
      addTearDown(service.dispose);
      await service.observe([eventFor(detail)]);
      await settle();
      detail = detailVersion('2');
      await service.observe([eventFor(detail)]);
      await settle();
      expect(service.frame?.product.version, '2');
      detail = detailVersion('3');
      failContours = true;
      await service.observe([eventFor(detail)]);
      await settle();
      expect(service.frame?.product.version, '2');
      failContours = false;
      await service.observe([eventFor(detail)]);
      await settle();
      expect(service.frame?.product.version, '3');
    },
  );

  test(
    'network error is distinguished from a product not yet available',
    () async {
      final service = UsgsShakeMapService(
        client: MockClient((_) async => http.Response('', 503)),
      );
      addTearDown(service.dispose);
      await service.select(eventFor(detailVersion('3')));
      expect(service.frame, isNull);
      expect(service.status, contains('加载失败'));
    },
  );

  for (final threshold in [-1.0, 7.0, 6.3, 0.0]) {
    test('real M6.3 auto update obeys source threshold $threshold', () async {
      var detail = detailVersion('1');
      var requests = 0;
      final service = UsgsShakeMapService(
        client: MockClient((request) async {
          requests++;
          return request.url.path.endsWith('/cont_mmi.json')
              ? contourResponse(request.url)
              : http.Response(jsonEncode(detail), 200);
        }),
      );
      addTearDown(service.dispose);
      service.setMagnitudeFilter(threshold);
      await service.observe([eventFor(detail)]);
      detail = detailVersion('3');
      await service.observe([eventFor(detail)]);
      if (threshold == 0 || threshold == 6.3) {
        expect(service.frame?.product.version, '3');
      } else {
        expect(service.frame, isNull);
        expect(requests, 0);
        await service.select(eventFor(detail));
        expect(service.frame, isNull);
        expect(service.status, isNull);
        expect(requests, 0);
      }
    });
  }

  test(
    'raising threshold clears an active map and cancels late contours',
    () async {
      var detail = detailVersion('1');
      final contourResult = Completer<http.Response>();
      Uri? contourUrl;
      final service = UsgsShakeMapService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cont_mmi.json')) {
            if (detail['properties']['products']['shakemap'][0]['properties']['version'] ==
                    '3' &&
                contourUrl == null) {
              contourUrl = request.url;
              return contourResult.future;
            }
            return contourResponse(request.url);
          }
          return http.Response(jsonEncode(detail), 200);
        }),
      );
      addTearDown(service.dispose);
      await service.observe([eventFor(detail)]);
      detail = detailVersion('2');
      await service.observe([eventFor(detail)]);
      expect(service.frame?.product.version, '2');
      detail = detailVersion('3');
      final pending = service.observe([eventFor(detail)]);
      await settle();
      expect(contourUrl, isNotNull);
      service.setMagnitudeFilter(7);
      expect(service.frame, isNull);
      contourResult.complete(contourResponse(contourUrl!));
      await pending;
      expect(service.frame, isNull);
    },
  );

  test('disabled source invalidates a pending manual detail request', () async {
    final detail = detailVersion('3');
    final response = Completer<http.Response>();
    var contourRequests = 0;
    final service = UsgsShakeMapService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/cont_mmi.json')) {
          contourRequests++;
          return contourResponse(request.url);
        }
        return response.future;
      }),
    );
    addTearDown(service.dispose);
    final pending = service.select(eventFor(detail));
    expect(service.status, contains('正在加载'));
    service.setMagnitudeFilter(-1);
    response.complete(http.Response(jsonEncode(detail), 200));
    await pending;
    expect(service.frame, isNull);
    expect(service.status, isNull);
    expect(contourRequests, 0);
  });

  test('official contours retain all values, coordinates and line styles', () {
    final file = File('$directory/us6000u0xi.cont_mmi.original.json');
    final original = file.readAsStringSync(encoding: utf8);
    final raw = jsonDecode(original) as Map<String, dynamic>;
    final contours = UsgsMmiContour.parse(raw);
    expect(contours, hasLength(raw['features'].length));
    for (var i = 0; i < contours.length; i++) {
      final feature = raw['features'][i];
      final contour = contours[i];
      expect(contour.value, feature['properties']['value']);
      expect(contour.weight, feature['properties']['weight']);
      expect(
        contour.colorArgb,
        0xFF000000 |
            int.parse(feature['properties']['color'].substring(1), radix: 16),
      );
      final lines = feature['geometry']['coordinates'];
      expect(contour.lines, hasLength(lines.length));
      for (var j = 0; j < lines.length; j++) {
        expect(contour.lines[j], hasLength(lines[j].length));
        for (var k = 0; k < lines[j].length; k++) {
          expect(contour.lines[j][k].longitude, lines[j][k][0]);
          expect(contour.lines[j][k].latitude, lines[j][k][1]);
        }
      }
    }
    expect(file.readAsStringSync(encoding: utf8), original);
    expect(
      () => UsgsMmiContour.parse(readJson('summary.original.geojson')),
      throwsFormatException,
    );
  });

  test(
    'real empty contours display an honest status without fabricating lines',
    () async {
      final detail = readJson('aka2026tvzrwv.detail.original.geojson');
      final service = UsgsShakeMapService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cont_mmi.json') &&
              request.url !=
                  UsgsShakeMapProduct.fromDetail(detail)!.contoursUrl) {
            return contourResponse(request.url);
          }
          return request.url.path.endsWith('/cont_mmi.json')
              ? http.Response.bytes(
                  File(
                    '$directory/aka2026tvzrwv.cont_mmi.original.json',
                  ).readAsBytesSync(),
                  200,
                )
              : http.Response(
                  jsonEncode(
                    request.url.queryParameters['eventid'] == detail['id']
                        ? detail
                        : detailVersion('1'),
                  ),
                  200,
                );
        }),
      );
      addTearDown(service.dispose);
      await service.select(eventFor(detail));
      expect(service.frame?.contours, isEmpty);
      expect(service.status, contains('无可绘制'));
      await service.select(null);
      await service.observe([eventFor(detailVersion('1'))]);
      await service.observe([eventFor(detail)]);
      expect(service.frame, isNull);
    },
  );
}
