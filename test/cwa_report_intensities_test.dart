import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/cwa_intensity_prediction.dart';
import 'package:flutterrhythmquake/core/cwa_report_intensities.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/cwa_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/ka_shindo_marker_style.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

const fixtureRoot = 'test/fixtures/source_estimation';
http.Response jsonResponse(Object? value) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), 200);
Object? fixture(String name) =>
    jsonDecode(File('$fixtureRoot/$name').readAsStringSync(encoding: utf8));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TopoJsonLoader.loadTwEew());
  final detail =
      fixture('cwa_report_115068_original.json') as Map<String, dynamic>;
  final summaries = fixture('cwa_report_list_20261006_original.json') as List;
  final summary = summaries.first as Map<String, dynamic>;
  final documented =
      (fixture('whews_cwa_report_documented_example.json') as Map)['Data']
          as Map<String, dynamic>;
  const expected = {'高雄市': 3, '屏東縣': 2, '嘉義縣': 1, '彰化縣': 1, '臺中市': 1, '臺南市': 1};

  test(
    'unchanged original detail aggregates six observed counties, not EEW estimates',
    () {
      final before = jsonEncode(detail);
      expect(CwaReportIntensities.countyRanks(detail), expected);
      final event = QuakeEventAdapter.convert('cwaEqlist', detail, 0)!;
      expect(event.maxIntensity, '3');
      expect(event.originTime, DateTime(2026, 10, 6, 16, 41, 8));
      expect(CwaReportIntensities.fromWarnArea(event.warnArea), expected);
      expect(event.sourcePayload, detail);
      expect(UnifiedQuakeData.fromMap(event.toMap()).warnArea, event.warnArea);
      expect(jsonEncode(detail), before);
      final listEvent = QuakeEventAdapter.convert('cwaEqlist', summary, 0)!;
      expect(listEvent.maxIntensity, '3');
      expect(listEvent.warnArea, isEmpty);
      expect(CwaReportIntensities.isObservedRevision(listEvent, event), isTrue);
    },
  );

  test(
    'WHEWS documented report table reaches the adapter without rewriting raw data',
    () {
      final before = jsonEncode(documented);
      final event = QuakeEventAdapter.convertWhews('cwa', documented)!;
      expect(CwaReportIntensities.fromWarnArea(event.warnArea), {'花蓮縣': 2});
      expect(event.sourcePayload, documented);
      expect(jsonEncode(documented), before);
      // Protocol compatibility, not a claimed FAN socket capture.
      final fan = FanService.decodeEventPayload(documented, sourceHint: 'cwa')!;
      expect(CwaReportIntensities.fromWarnArea(fan.warnArea), {'花蓮縣': 2});
      expect(fan.sourcePayload, documented);
    },
  );

  test(
    'existing Jian and WHEWS original summaries do not manufacture county grades',
    () {
      final jianRaw =
          (jsonDecode(
                    File(
                      'test/fixtures/jian/all.json',
                    ).readAsStringSync(encoding: utf8),
                  )
                  as Map)['source：cwa']['Data']
              as Map;
      final whewsRaw =
          (jsonDecode(
                        File(
                          'test/fixtures/catalog_20260917/whews_all.json',
                        ).readAsStringSync(encoding: utf8),
                      )
                      as List)
                  .whereType<Map>()
                  .firstWhere((f) => f['source'] == 'cwa')['Data']
              as Map;
      for (final event in [
        QuakeEventAdapter.convertJian(
          'cwa',
          Map<String, dynamic>.from(jianRaw),
        )!,
        QuakeEventAdapter.convertWhews(
          'cwa',
          Map<String, dynamic>.from(whewsRaw),
        )!,
      ]) {
        expect(event.maxIntensity, isNot('-'));
        expect(event.warnArea, isEmpty);
      }
    },
  );

  test('ordinal and displayed weak/strong grades use different encodings', () {
    for (var rank = 0; rank <= 9; rank++) {
      expect(CwaReportIntensities.encodedRank(rank), rank);
      expect(
        CwaIntensityPrediction.parseRank(CwaIntensityPrediction.labels[rank]),
        rank,
      );
    }
    expect(CwaReportIntensities.encodedRank(6), 6);
    expect(CwaIntensityPrediction.parseRank('6'), 7);
    for (final invalid in [-1, 10, 3.5, 'NaN', null]) {
      expect(CwaReportIntensities.encodedRank(invalid), isNull);
    }
  });

  test(
    'schema-only edge cases take county maximum and never paint unrelated regions',
    () {
      // Deliberate parser contract cases, not observational fixtures.
      final raw = {
        'maxIntensity': '7',
        'intensities': [
          {
            'pref': '台东县',
            'maxIntensity': '1',
            'areas': [
              {
                'stations': [
                  {'intensity': '6-'},
                  {'intensity': '5+'},
                  {'intensity': '-'},
                ],
              },
            ],
          },
          {'pref': '台东县', 'maxIntensity': '6+'},
          {'pref': 'unknown', 'maxIntensity': '7'},
        ],
      };
      expect(CwaReportIntensities.countyRanks(raw), {'臺東縣': 8});
      expect(
        CwaReportIntensities.fromWarnArea(CwaReportIntensities.toWarnArea(raw)),
        {'臺東縣': 8},
      );
      expect(
        CwaReportIntensities.fromWarnArea('[{"name":"臺東縣","intensity":"7"}]'),
        isEmpty,
      );
      expect(CwaReportIntensities.fromWarnArea('{}'), isEmpty);
      expect(CwaReportIntensities.fromWarnArea('invalid'), isEmpty);
    },
  );

  test(
    'detail service keeps original report, caches it and updates lists before the detail completes',
    () async {
      var detailRequests = 0;
      final pending = Completer<http.Response>();
      final client = MockClient((uri) async {
        if (uri.url.hasQuery) return jsonResponse(summaries);
        detailRequests++;
        expect(uri.url.path, '/api/v2/eq/report/${detail['id']}');
        return pending.future;
      });
      final service = CwaEqlistService.forTesting(client);
      addTearDown(client.close);
      final received = <Map<String, dynamic>>[];
      var lists = 0;
      service.onListUpdated = (_) => lists++;
      service.onCurrentUpdated = received.add;
      final first = service.fetchForTesting();
      await Future<void>.delayed(Duration.zero);
      expect(lists, 1);
      expect(received, isEmpty);
      await service.fetchForTesting();
      pending.complete(jsonResponse(detail));
      await first;
      await service.fetchForTesting();
      expect(detailRequests, 1);
      expect(received, [detail, detail]);
      service.stop();
    },
  );

  test(
    'failed details retry and a mismatched report cannot fill the summary',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        if (request.url.hasQuery) return jsonResponse(summaries);
        requests++;
        return requests == 1
            ? http.Response('{}', 503)
            : jsonResponse(summaries.last);
      });
      final service = CwaEqlistService.forTesting(client);
      addTearDown(client.close);
      final received = <Map<String, dynamic>>[];
      service.onCurrentUpdated = received.add;
      await service.fetchForTesting();
      await service.fetchForTesting();
      expect(requests, 2);
      expect(received, [summary, summary]);
      service.stop();
    },
  );

  test(
    'stop prevents a pending detail callback from reviving the source',
    () async {
      final pending = Completer<http.Response>();
      final client = MockClient(
        (request) async =>
            request.url.hasQuery ? jsonResponse(summaries) : pending.future,
      );
      final service = CwaEqlistService.forTesting(client);
      addTearDown(client.close);
      final received = <Map<String, dynamic>>[];
      service.onCurrentUpdated = received.add;
      final fetch = service.fetchForTesting();
      await Future<void>.delayed(Duration.zero);
      service.stop();
      pending.complete(jsonResponse(detail));
      await fetch;
      expect(received, isEmpty);
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets(
      'observed map fills only reported counties, preserves palette and caches polygons at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final event = QuakeEventAdapter.convert('cwaEqlist', detail, 0)!;
        final boundaryKey = GlobalKey();
        Future<void> show(String warnArea) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(23.5, 121),
                      initialZoom: 6,
                    ),
                    children: [
                      IntensityFillLayer(
                        source: 'tw',
                        mode: IntensityFillMode.cwaObserved,
                        magnitude: event.magnitude,
                        depth: event.depth,
                        hypoLat: event.lat!,
                        hypoLng: event.lng!,
                        warnAreaJson: warnArea,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() => TopoJsonLoader.loadTwEew());
          await tester.pumpAndSettle();
        }

        await show(event.warnArea);
        final polygons = tester
            .widget<PolygonLayer>(find.byType(PolygonLayer))
            .polygons;
        final topology = await tester.runAsync(
          () => TopoJsonLoader.loadTwEew(),
        );
        final regions = topology!.regions.where(
          (r) => expected.containsKey(
            CwaIntensityPrediction.canonicalCounty(r.name),
          ),
        );
        expect(
          polygons.length,
          regions.fold<int>(
            0,
            (n, r) => n + r.polygons.where((p) => p.length >= 3).length,
          ),
        );
        for (final region in regions) {
          final rank =
              expected[CwaIntensityPrediction.canonicalCounty(region.name)]!;
          final color = KaShindoMarkerStyle.colorForLevel(
            CwaIntensityPrediction.markerLevels[rank],
          ).withValues(alpha: .4);
          for (final points in region.polygons.where((p) => p.length >= 3)) {
            expect(
              polygons.singleWhere((p) => identical(p.points, points)).color,
              color,
            );
          }
        }
        final controller = MapController.of(
          tester.element(find.byType(IntensityFillLayer)),
        );
        controller.move(const LatLng(23.6, 120.9), 6.2);
        await tester.pump();
        expect(
          identical(
            tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
            polygons,
          ),
          isTrue,
        );
        if (const bool.fromEnvironment('CAPTURE_CWA_PREVIEW')) {
          await tester.runAsync(() async {
            final image =
                await (boundaryKey.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/test-previews/cwa_observed_${size.width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        await show('');
        expect(find.byType(PolygonLayer), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
