import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fnet_cmt_service.dart';
import 'package:flutterrhythmquake/widgets/map/fssn_cmt_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/cmt_badge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final listBytes = File(
    'test/fixtures/fnet/20260922-list-eucjp.html',
  ).readAsBytesSync();
  final detailBytes = File(
    'test/fixtures/fnet/20260922063300-detail-eucjp.html',
  ).readAsBytesSync();
  const id = 'fnet_cmt_20260922063300';

  for (final failure in ['http', 'transport', 'incomplete']) {
    test(
      'latest detail recovers from $failure and caches the real mechanism',
      () async {
        var detailRequests = 0;
        var failing = true;
        final snapshots = <List<Map<String, dynamic>>>[];
        final service = FnetCmtService.forTest(
          clientFactory: () => MockClient((r) async {
            if (r.url.path.endsWith('joho.php')) return http.Response('', 200);
            if (r.url.path.endsWith('sret.php')) {
              return http.Response.bytes(listBytes, 200);
            }
            if (r.url.queryParameters['_id'] != '20260922063300') {
              return http.Response('', 503);
            }
            expect(r.url.queryParameters['LANG'], 'ja');
            detailRequests++;
            if (failing) {
              if (failure == 'transport') {
                throw http.ClientException('test transport fault');
              }
              if (failure == 'incomplete') {
                // Explicit protocol fault, not a replacement earthquake observation.
                return http.Response(
                  '<td class="nodeci region">region only</td>',
                  200,
                );
              }
              return http.Response('', 503);
            }
            return http.Response.bytes(detailBytes, 200);
          }),
        );
        addTearDown(service.stop);
        service.onListUpdated = snapshots.add;
        await service.fetch();
        expect(
          detailRequests,
          3,
          reason: 'initial request plus two bounded retries',
        );
        final missing = snapshots.last.singleWhere((e) => e['eventId'] == id);
        expect(missing['nodalPlane1'], isNull);
        failing = false;
        await service.fetch();
        expect(
          detailRequests,
          4,
          reason: 'incomplete details must not poison the cache',
        );
        final complete = snapshots.last.singleWhere((e) => e['eventId'] == id);
        expect(complete['location'], '茨城県南部');
        expect(complete['nodalPlane1'], '279/26/143');
        expect(complete['nodalPlane2'], '44/75/69');
        expect(complete['centroidDepth'], 53);
        final event = QuakeEventAdapter.convert('fnetCmt', complete, 0)!;
        expect(
          CmtBeachball.hasRenderableMechanism(
            nodalPlane: event.nodalPlane1,
            nodalPlane2: event.nodalPlane2,
          ),
          isTrue,
        );
        await service.fetch();
        expect(detailRequests, 4, reason: 'successful details are reused');
        expect(snapshots.last.singleWhere((e) => e['eventId'] == id), complete);
      },
    );
  }

  test(
    'transient latest detail failure is retried before publishing the list',
    () async {
      var requests = 0;
      List<Map<String, dynamic>>? received;
      final service = FnetCmtService.forTest(
        clientFactory: () => MockClient((r) async {
          if (r.url.path.endsWith('joho.php')) return http.Response('', 200);
          if (r.url.path.endsWith('sret.php')) {
            return http.Response.bytes(listBytes, 200);
          }
          if (r.url.queryParameters['_id'] != '20260922063300') {
            return http.Response('', 503);
          }
          return ++requests == 1
              ? http.Response('', 503)
              : http.Response.bytes(detailBytes, 200);
        }),
      );
      addTearDown(service.stop);
      service.onListUpdated = (items) => received = items;
      await service.fetch();
      expect(requests, 2);
      expect(received!.first['nodalPlane1'], '279/26/143');
    },
  );

  for (final size in [const Size(1584, 850), const Size(390, 844)]) {
    testWidgets('official F-net detail renders a ball on $size', (
      tester,
    ) async {
      late Map<String, dynamic> item;
      final service = FnetCmtService.forTest(
        clientFactory: () => MockClient((r) async {
          if (r.url.path.endsWith('joho.php')) return http.Response('', 200);
          if (r.url.path.endsWith('sret.php')) {
            return http.Response.bytes(listBytes, 200);
          }
          if (r.url.queryParameters['_id'] == '20260922063300') {
            return http.Response.bytes(detailBytes, 200);
          }
          return http.Response('', 503);
        }),
      );
      addTearDown(service.stop);
      service.onListUpdated = (items) =>
          item = items.singleWhere((e) => e['eventId'] == id);
      await service.fetch();
      final event = QuakeEventAdapter.convert('fnetCmt', item, 0)!;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: CmtBadge(event: event, size: 72, color: Colors.grey),
          ),
        ),
      );
      expect(find.byType(CmtBeachball), findsOneWidget);
      expect(find.text('--'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
