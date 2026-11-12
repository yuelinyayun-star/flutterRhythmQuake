import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_animation_clock.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_tsunami_regions.dart';
import 'package:flutterrhythmquake/services/tsunami_region_service.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_layer.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_region_layer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

const _jsonUrl =
    'http://www.tsunami.gov/events/PAAQ/2025/09/18/t2ssp5/1/WEAK51/PAAQ.json';
const _kmzUrl =
    'https://www.tsunami.gov/events/PAAQ/2025/09/18/t2ssp5/1/WEAK51/PAAQevent.kmz';
// Presentation model of the original NTWC advisory; source times are retained.
const _advisory = TsunamiMessage(
  source: TsunamiSource.ntwc,
  eventId: 't2ssp5',
  reportNumber: 1,
  grade: TsunamiGrade.watch,
  reportTime: '2025-09-18T19:07:03Z',
  sourcePayload: {'jsonUrl': _jsonUrl},
);

void main() {
  final supported = NativeTsunamiRegions.supported;
  late List<Map<String, dynamic>> originalRegions;
  setUpAll(() async {
    if (!supported) return;
    final result = await NativeTsunamiRegions.prepare(
      {
        'op': 'geometry',
        'format': 'kmz',
        'message': {'source': 'ntwc', 'grade': 'watch'},
      },
      document: await File(
        'test/fixtures/tsunami_regions/noaa_ntwc_20250918.original.kmz',
      ).readAsBytes(),
    );
    originalRegions = [
      for (final row in result['regions'] as List)
        Map<String, dynamic>.from(row as Map),
    ];
  });

  test(
    'official NOAA URL loads original KMZ without changing the report',
    () async {
      var requests = 0;
      final original = _advisory.toMap();
      final client = MockClient((request) async {
        requests++;
        expect(request.url.toString(), _kmzUrl);
        return http.Response.bytes(
          await File(
            'test/fixtures/tsunami_regions/noaa_ntwc_20250918.original.kmz',
          ).readAsBytes(),
          200,
        );
      });
      addTearDown(client.close);
      final regions = await TsunamiRegionService(
        client: client,
      ).load(_advisory);
      expect(requests, 1);
      expect(regions.single['name'], 'AK791');
      expect(regions.single['className'], 'orange');
      expect(regions.single['strokeArgb'], 0x50FFA014);
      expect((regions.single['lines'] as List).length, greaterThan(10));
      expect(_advisory.toMap(), original);
    },
    skip: !supported,
  );

  test('cancelled advisory never fetches or keeps warning geometry', () async {
    final client = MockClient(
      (_) async => throw StateError('Unexpected fetch'),
    );
    addTearDown(client.close);
    final regions = await TsunamiRegionService(client: client).load(
      _advisory.copyWith(
        grade: TsunamiGrade.none,
        bulletinLevel: 'Cancellation',
      ),
    );
    expect(regions, isEmpty);
  }, skip: !supported);

  test(
    'CWA named coastlines load locally with raw area colors and no HTTP',
    () async {
      final client = MockClient(
        (_) async => throw StateError('Unexpected fetch'),
      );
      addTearDown(client.close);
      // Protocol-only report fields, not a historical or live warning fixture.
      final message = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.cwa,
        {
          'level': 'Warning',
          'warningAreas': [
            {'areaName': '北部沿海地區', 'areaColor': '紅色'},
            {'areaName': '東南沿海地區', 'areaColor': '橙色'},
            {'areaName': '海峽沿海地區', 'areaColor': '黃色'},
            {'areaName': '東部沿海地區', 'areaColor': '綠色'},
            {'areaName': '宜蘭縣', 'areaColor': '紅色'},
          ],
        },
      );
      final original = message.toMap();
      final service = TsunamiRegionService(client: client);
      final regions = await service.load(message);
      expect(regions.map((r) => r['name']), ['北部沿海地區', '東南沿海地區', '海峽沿海地區']);
      expect(regions.map((r) => r['strokeArgb']), [
        0xffff0000,
        0xffffa500,
        0xffffff00,
      ]);
      expect((regions.first['lines'] as List).first.first, [121.966, 24.9831]);
      expect(message.toMap(), original);
      expect(
        await service.load(
          message.copyWith(
            grade: TsunamiGrade.none,
            bulletinLevel: 'Cancellation',
          ),
        ),
        isEmpty,
      );
    },
    skip: !supported,
  );

  test(
    'original INCOIS 2012 public bulletin KMZ reaches the map codec',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/SHP/dss120411083800/B2/dss120411083800_B2_pub.kmz',
        );
        return http.Response.bytes(
          await File(
            'test/fixtures/tsunami_regions/incois_20120411_B2.original.kmz',
          ).readAsBytes(),
          200,
        );
      });
      addTearDown(client.close);
      // Metadata from the actual historical public bulletin; its KMZ is untouched.
      final regions = await TsunamiRegionService(client: client).load(
        const TsunamiMessage(
          source: TsunamiSource.incois,
          eventId: 'dss120411083800',
          reportNumber: 2,
          grade: TsunamiGrade.warning,
          sourcePayload: {
            'detailUrl':
                'https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/Web/dss120411083800_Bulletin2_box_pub_A.html',
          },
        ),
      );
      expect(regions, hasLength(55));
      expect(regions.where((r) => r['className'] == 'red'), hasLength(3));
      expect(regions.where((r) => r['className'] == 'orange'), hasLength(14));
      expect(regions.where((r) => r['className'] == 'yellow'), hasLength(38));
    },
    skip: !supported,
  );

  test(
    'CWA event CAP geometry takes priority over named base-map coastlines',
    () async {
      // Protocol-only CAP verifies document precedence and exact ID binding.
      const cap =
          '<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">'
          '<identifier>protocol-cwa</identifier><msgType>Alert</msgType><info>'
          '<severity>Severe</severity><area><areaDesc>protocol-CAP-zone</areaDesc>'
          '<polygon>24,121 25,122 26,121 24,121</polygon></area></info></alert>';
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(
          request.url.toString(),
          'https://alerts.ncdr.nat.gov.tw/protocol.xml',
        );
        return http.Response(cap, 200);
      });
      addTearDown(client.close);
      final message = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.cwa,
        {
          'id': 'protocol-cwa',
          'level': 'Warning',
          'capUrl': 'https://alerts.ncdr.nat.gov.tw/protocol.xml',
          'warningAreas': [
            {'areaName': '北部沿海地區', 'areaColor': '橙色'},
          ],
        },
      );
      final regions = await TsunamiRegionService(client: client).load(message);
      expect(calls, 1);
      expect(regions.single['name'], 'protocol-CAP-zone');
      expect((regions.single['lines'] as List).first.first, [121, 24]);
    },
    skip: !supported,
  );

  test(
    'CWA cancelled CAP cannot reactivate named base-map coastlines',
    () async {
      // Protocol-only inconsistent metadata verifies authoritative cancellation.
      final client = MockClient(
        (_) async => http.Response(
          '<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">'
          '<identifier>protocol-cwa</identifier><msgType>Cancel</msgType></alert>',
          200,
        ),
      );
      addTearDown(client.close);
      final message = TsunamiMessage.parseInternationalTsunami(
        TsunamiSource.cwa,
        {
          'id': 'protocol-cwa',
          'level': 'Warning',
          'capUrl': 'https://alerts.ncdr.nat.gov.tw/protocol.xml',
          'warningAreas': [
            {'areaName': '北部沿海地區', 'areaColor': '橙色'},
          ],
        },
      );
      expect(await TsunamiRegionService(client: client).load(message), isEmpty);
    },
    skip: !supported,
  );

  test('original PTWC Hawaii warning reaches all coastal map zones', () async {
    const base =
        'https://www.tsunami.gov/events/PHEB/2025/07/29/25210002/4/WEHW40/';
    final raw =
        jsonDecode(
              await File(
                'test/fixtures/tsunami_regions/ptwc_hawaii_20250730.original.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final client = MockClient((request) async {
      expect(request.url.toString(), '${base}PHEBevent.kmz');
      return http.Response.bytes(
        await File(
          'test/fixtures/tsunami_regions/ptwc_hawaii_20250730.original.kmz',
        ).readAsBytes(),
        200,
      );
    });
    addTearDown(client.close);
    // Normalized metadata from the original bulletin; no historical time rewrite.
    final message = TsunamiMessage(
      source: TsunamiSource.ptwc,
      grade: TsunamiGrade.warning,
      eventId: raw['twcEventID'] as String,
      reportTime: raw['bulletinIssueTime'] as String,
      originTime: raw['originTime'] as String,
      sourcePayload: const {'jsonUrl': '${base}PHEB.json'},
    );
    final regions = await TsunamiRegionService(client: client).load(message);
    expect(regions, hasLength(39));
    expect(regions.where((r) => r['strokeArgb'] == 0x66ff0000), hasLength(35));
    expect(regions.where((r) => r['strokeArgb'] == 0x50ffa014), hasLength(4));
    expect(message.reportTime, '2025-07-30T01:51:32Z');
  }, skip: !supported);

  test('HTTP failure produces no invented warning region', () async {
    final client = MockClient((_) async => http.Response('Not found', 404));
    addTearDown(client.close);
    expect(await TsunamiRegionService(client: client).load(_advisory), isEmpty);
  }, skip: !supported);

  testWidgets('official colors reuse JMA stroke and blink clock', (
    tester,
  ) async {
    final clock = EventAnimationClock.instance;
    final leasesBefore = clock.activeLeaseCount;
    await tester.pumpWidget(_map(_advisory, _Prepared(originalRegions)));
    await tester.pump();
    final polylineLayer = tester.widget<PolylineLayer>(
      find.byType(PolylineLayer),
    );
    expect(polylineLayer.polylines.length, greaterThan(10));
    for (final line in polylineLayer.polylines) {
      expect(line.color, const Color(0x50FFA014));
      expect(line.strokeWidth, 5);
      expect(line.points.length, greaterThanOrEqualTo(2));
    }
    expect(find.byType(MarkerLayer), findsNothing);
    expect(clock.activeLeaseCount, leasesBefore + 1);
    final opacity = find
        .ancestor(
          of: find.byType(PolylineLayer),
          matching: find.byType(Opacity),
        )
        .first;
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.widget<Opacity>(opacity).opacity,
      clock.blink2Fps.value % 6 != 0 ? 1 : 0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(clock.activeLeaseCount, leasesBefore);
  }, skip: !supported);

  for (final sample in [
    (
      'BOLETIN_ALERTA_001_20260717_090502',
      'cat_20260717_alert.original.xml',
      0xffd71717,
    ),
    (
      'BOLETIN_SEGUIMIENTO_003_20260717_110847',
      'cat_20260717_followup.original.xml',
      0xffec8210,
    ),
  ]) {
    test(
      'original CAT ${sample.$1} loads its own WKT warning polygon',
      () async {
        final client = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://diredimoat.semar.gob.mx/cat/rss/${sample.$1}.xml',
          );
          return http.Response.bytes(
            await File(
              'test/fixtures/tsunami_regions/${sample.$2}',
            ).readAsBytes(),
            200,
          );
        });
        addTearDown(client.close);
        final regions = await TsunamiRegionService(client: client).load(
          TsunamiMessage(
            source: TsunamiSource.cat,
            grade: TsunamiGrade.warning,
            id: sample.$1,
            sourcePayload: {
              'id': sample.$1,
              'capUrl':
                  'https://diredimoat.semar.gob.mx/cat/rss/ultimo_boletin.xml',
            },
          ),
        );
        expect(regions, hasLength(1));
        expect(regions.single['strokeArgb'], sample.$3);
        final point =
            ((regions.single['lines'] as List).first as List).first as List;
        expect(point[0] as num, lessThan(-90));
        expect(point[1] as num, greaterThan(10));
      },
      skip: !supported,
    );
  }

  testWidgets('late geometry cannot resurrect a cancelled report', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final service = _Deferred(pending);
    await tester.pumpWidget(_map(_advisory, service));
    expect(find.byType(TsunamiLayer), findsNothing);
    await tester.pumpWidget(
      _map(
        _advisory.copyWith(
          grade: TsunamiGrade.none,
          bulletinLevel: 'Cancellation',
        ),
        _Prepared([]),
      ),
    );
    pending.complete(originalRegions);
    await tester.pump();
    expect(find.byType(PolylineLayer), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !supported);

  testWidgets('expired official warning has no outline or animation lease', (
    tester,
  ) async {
    final before = EventAnimationClock.instance.activeLeaseCount;
    await tester.pumpWidget(
      _map(
        const TsunamiMessage(
          source: TsunamiSource.cwa,
          grade: TsunamiGrade.warning,
          expires: '2020-01-01T00:00:00Z',
        ),
        _Prepared(originalRegions),
      ),
    );
    await tester.pump();
    expect(find.byType(PolylineLayer), findsNothing);
    expect(EventAnimationClock.instance.activeLeaseCount, before);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !supported);
}

Widget _map(TsunamiMessage message, TsunamiRegionService service) =>
    MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(52, 179),
          initialZoom: 5,
        ),
        children: [TsunamiRegionLayer(tsunami: message, service: service)],
      ),
    );

class _Prepared extends TsunamiRegionService {
  _Prepared(this.regions);
  final List<Map<String, dynamic>> regions;
  @override
  Future<List<Map<String, dynamic>>> load(TsunamiMessage message) async =>
      regions;
}

class _Deferred extends TsunamiRegionService {
  _Deferred(this.pending);
  final Completer<List<Map<String, dynamic>>> pending;
  @override
  Future<List<Map<String, dynamic>>> load(TsunamiMessage message) =>
      pending.future;
}
