import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

const dyfiFixtures = 'test/fixtures/usgs_dyfi';
Map<String, dynamic> originalDetail(String id) => jsonDecode(
  File(
    'test/fixtures/usgs_shakemap/$id.detail.original.geojson',
  ).readAsStringSync(encoding: utf8),
);
Map<String, dynamic> emptyDyfiDetail() => jsonDecode(
  File(
    '$dyfiFixtures/us6000u1em.detail.original.geojson',
  ).readAsStringSync(encoding: utf8),
);
Map<String, dynamic> dyfiDetail([int responses = 191]) {
  if (responses == 191) return originalDetail('ci41345415');
  final captured = jsonDecode(
    File(
      '$dyfiFixtures/ci41345415.versions.original.geojson',
    ).readAsStringSync(encoding: utf8),
  );
  // Select an actually published native product; do not change its contents,
  // timestamps, coordinates or counts to simulate a newer event.
  final product = (captured['properties']['products']['dyfi'] as List)
      .firstWhere((p) => p['properties']['numResp'] == '$responses');
  return {
    ...captured,
    'properties': {
      ...captured['properties'],
      'products': {
        'dyfi': [product],
      },
    },
  };
}

QuakeMessage dyfiEvent(Map<String, dynamic> detail) {
  final p = detail['properties'], xyz = detail['geometry']['coordinates'];
  final product = UsgsDyfiProduct.fromDetail(detail);
  final mag = (p['mag'] as num).toDouble(), depth = (xyz[2] as num).toDouble();
  return QuakeMessage(
    source: QuakeSourceType.usgs,
    eventId: detail['id'],
    location: getFEName((xyz[1] as num).toDouble(), (xyz[0] as num).toDouble()),
    magnitude: mag,
    depth: depth,
    latitude: (xyz[1] as num).toDouble(),
    longitude: (xyz[0] as num).toDouble(),
    originTime: DateTime.fromMillisecondsSinceEpoch(
      p['time'],
      isUtc: true,
    ).toLocal(),
    timeZone: DateTime.now().timeZoneOffset.inHours,
    isHistory: true,
    maxIntensity: IntensityCalculator.calcCsisLevel(mag, depth, 0),
    usgsDetailUrl:
        'https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=${detail['id']}&format=geojson',
    usgsProductTypes: p['types'],
    // Native product publication revisions drive the sequence under replay.
    usgsUpdated: product?.updated.millisecondsSinceEpoch ?? p['updated'],
  );
}

http.Response dyfiGridResponse(Uri url) {
  final file = url.toString().contains('1791532575397')
      ? 'ci41345415.dyfi_geo_10km.original.geojson'
      : url.toString().contains('1791532884156')
      ? 'ci41345415.210.dyfi_geo_10km.original.geojson'
      : url.toString().contains('1791453896368')
      ? 'us6000u0xi.dyfi_geo_10km.original.geojson'
      : null;
  if (file == null) return http.Response('', 404);
  return http.Response.bytes(
    File('$dyfiFixtures/$file').readAsBytesSync(),
    200,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Panama native zero maximum and empty grid load without a failure',
    () async {
      final detail = emptyDyfiDetail();
      final before = jsonEncode(detail);
      final event = dyfiEvent(detail);
      final product = UsgsDyfiProduct.fromDetail(detail)!;
      final gridBytes = File(
        '$dyfiFixtures/us6000u1em.dyfi_geo_10km.original.geojson',
      ).readAsBytesSync();
      final grid = jsonDecode(utf8.decode(gridBytes)) as Map<String, dynamic>;
      final gridBefore = jsonEncode(grid);
      final service = UsgsDyfiService(
        client: MockClient(
          (request) async => request.url == product.gridUrl
              ? http.Response.bytes(gridBytes, 200)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      addTearDown(service.dispose);
      expect(event.eventId, 'us6000u1em');
      expect(event.magnitude, 4.3);
      expect(product.maxCdi, 0);
      expect(product.maxCdiText, '未知');
      expect(product.responses, 1);
      expect(UsgsDyfiCell.parse(grid), isEmpty);
      await service.observe([event]);
      expect(service.errorFor(event), isNull);
      expect(service.frameFor(event)!.cells, isEmpty);
      expect(service.automaticFrame, isNull);
      await service.select(event);
      expect(service.status, isNull);
      expect(service.manualFrame!.product.responses, 1);
      expect(service.manualFrame!.cells, isEmpty);
      expect(jsonEncode(detail), before);
      expect(jsonEncode(grid), gridBefore);
      expect(product.original, detail['properties']['products']['dyfi'][0]);
    },
  );

  test('native product and CDI grids retain all original report values', () {
    final detail = dyfiDetail();
    final before = jsonEncode(detail);
    final product = UsgsDyfiProduct.fromDetail(detail)!;
    final grid =
        jsonDecode(
              File(
                '$dyfiFixtures/ci41345415.dyfi_geo_10km.original.geojson',
              ).readAsStringSync(encoding: utf8),
            )
            as Map<String, dynamic>;
    final gridBefore = jsonEncode(grid);
    final cells = UsgsDyfiCell.parse(grid);
    expect(product.responses, 191);
    expect(product.maxCdi, 3.5);
    expect(product.updated.millisecondsSinceEpoch, 1791532575397);
    expect(product.gridKm, 10);
    expect(product.original, detail['properties']['products']['dyfi'][0]);
    expect(cells, hasLength(15));
    expect(cells.first.cdi, 3.5);
    expect(cells.first.responses, 14);
    expect(cells.first.distance, 14);
    expect(cells.first.rings.first.first.longitude, -118.29626);
    expect(cells.fold<int>(0, (n, c) => n + c.responses), 187);
    // Four questionnaires without plotted coordinates must not become fake cells.
    expect(jsonEncode(grid), gridBefore);
    expect(jsonEncode(detail), before);
  });

  test(
    'startup loads list thumbnails silently; actual revision redisplays once',
    () async {
      var detail = dyfiDetail();
      var grids = 0, details = 0;
      final service = UsgsDyfiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('.geojson')) {
            grids++;
            return dyfiGridResponse(request.url);
          }
          details++;
          return http.Response(jsonEncode(detail), 200);
        }),
      );
      addTearDown(service.dispose);
      await service.observe([dyfiEvent(detail)]);
      expect(service.frameFor(dyfiEvent(detail))?.product.responses, 191);
      expect(service.automaticFrame, isNull);
      expect(service.frame, isNull);
      await service.observe([dyfiEvent(detail)]);
      expect(grids, 1);
      expect(details, 1);
      detail = dyfiDetail(210);
      await service.observe([dyfiEvent(detail)]);
      expect(service.automaticFrame?.product.responses, 210);
      await service.observe([dyfiEvent(detail)]);
      expect(grids, 2);
      expect(details, 2);
    },
  );

  test(
    'late older product cannot replace a newer cached grid or selection',
    () async {
      var detail = dyfiDetail();
      final service = UsgsDyfiService(
        client: MockClient(
          (r) async => r.url.path.endsWith('.geojson')
              ? dyfiGridResponse(r.url)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      addTearDown(service.dispose);
      await service.observe([dyfiEvent(detail)]);
      detail = dyfiDetail(210);
      await service.observe([dyfiEvent(detail)]);
      detail = dyfiDetail();
      await service.select(dyfiEvent(detail));
      expect(service.manualFrame?.product.responses, 210);
      expect(service.automaticFrame?.product.responses, 210);
    },
  );

  test(
    'magnitude filtering also suppresses an in-flight grid response',
    () async {
      final pending = Completer<http.Response>();
      final detail = dyfiDetail();
      final service = UsgsDyfiService(
        client: MockClient(
          (r) async => r.url.path.endsWith('.geojson')
              ? pending.future
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      addTearDown(service.dispose);
      final selection = service.select(dyfiEvent(detail));
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      service.setMagnitudeFilter(4);
      pending.complete(
        dyfiGridResponse(UsgsDyfiProduct.fromDetail(detail)!.gridUrl!),
      );
      await selection;
      expect(service.frame, isNull);
      expect(service.frameFor(dyfiEvent(detail)), isNull);
      service.setMagnitudeFilter(0);
      await service.select(dyfiEvent(detail));
      expect(service.frame?.product.responses, 191);
    },
  );

  test('failed refresh retains the last real grid and can retry', () async {
    var detail = dyfiDetail();
    var fail = false;
    final service = UsgsDyfiService(
      client: MockClient(
        (r) async => fail
            ? http.Response('', 503)
            : r.url.path.endsWith('.geojson')
            ? dyfiGridResponse(r.url)
            : http.Response(jsonEncode(detail), 200),
      ),
    );
    addTearDown(service.dispose);
    await service.observe([dyfiEvent(detail)]);
    detail = dyfiDetail(210);
    fail = true;
    await service.observe([dyfiEvent(detail)]);
    expect(service.frameFor(dyfiEvent(detail))?.product.responses, 191);
    expect(service.errorFor(dyfiEvent(detail)), contains('失败'));
    fail = false;
    await service.observe([dyfiEvent(detail)]);
    expect(service.frameFor(dyfiEvent(detail))?.product.responses, 210);
    expect(service.errorFor(dyfiEvent(detail)), isNull);
  });

  test(
    'ordinary quake selection hides DYFI map but retains its automatic card',
    () async {
      var detail = dyfiDetail();
      final service = UsgsDyfiService(
        client: MockClient(
          (r) async => r.url.path.endsWith('.geojson')
              ? dyfiGridResponse(r.url)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      addTearDown(service.dispose);
      await service.observe([dyfiEvent(detail)]);
      detail = dyfiDetail(210);
      await service.observe([dyfiEvent(detail)]);
      await service.select(dyfiEvent(detail), showProduct: false);
      expect(service.frame, isNull);
      expect(service.automaticFrame?.product.responses, 210);
      await service.select(null);
      expect(service.frame?.product.responses, 210);
    },
  );
}
