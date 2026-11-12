import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/cwa_eqlist_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/utils/cwa_location.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const root = 'test/fixtures/cwa_catalog_20261028';
dynamic original(String name) =>
    jsonDecode(File('$root/$name').readAsStringSync(encoding: utf8));

final trem = (original('trem_list.original.json') as List)
    .cast<Map<String, dynamic>>();
final jian = (original('jian_cwalist.original.json')['Data'] as List)
    .cast<Map<String, dynamic>>();
final whews =
    original('whews_cwa.original.json')['Data'] as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('original captures retain their recorded SHA256 hashes', () {
    final manifest = original('manifest.json')['files'] as Map;
    for (final entry in manifest.entries) {
      expect(
        sha256.convert(File('$root/${entry.key}').readAsBytesSync()).toString(),
        entry.value,
      );
    }
  });

  test(
    'all Jian CWA report titles use the epicentral area and preserve raw data',
    () {
      final before = jsonEncode(jian);
      final events = [
        for (final raw in jian) QuakeEventAdapter.convertJian('cwa', raw)!,
      ];
      expect(events, hasLength(50));
      expect(events.take(5).map((e) => e.hypocenter), [
        '臺灣東部海域',
        '花蓮縣近海',
        '花蓮縣卓溪鄉',
        '花蓮縣萬榮鄉',
        '高雄市桃源區',
      ]);
      for (var i = 0; i < events.length; i++) {
        expect(events[i].hypocenter, isNot(contains('公里')));
        expect(events[i].hypocenter, isNot(contains('位於')));
        expect(events[i].sourcePayload, jian[i]);
      }
      expect(jsonEncode(jian), before);
      final detail =
          original('trem_detail.original.json') as Map<String, dynamic>;
      final current = QuakeEventAdapter.convert('cwaEqlist', detail, 0)!;
      expect(current.hypocenter, '臺灣東部海域');
      expect(current.sourcePayload, detail);
      final w = QuakeEventAdapter.convertWhews('cwa', whews)!;
      expect(w.hypocenter, '宜蘭縣南澳鄉');
      expect(w.sourcePayload, whews);
      // Shared wire-field compatibility only: this is the unchanged WHEWS
      // capture through FAN's parser, not a claimed FAN live observation.
      final compatibleFan = FanService.decodeEventPayload(
        whews,
        sourceHint: 'cwa',
      )!;
      expect(compatibleFan.hypocenter, w.hypocenter);
      expect(compatibleFan.sourcePayload, whews);
      final fan =
          original('fan_documented.original.json')['Data']
              as Map<String, dynamic>;
      final event = FanService.decodeEventPayload(fan, sourceHint: 'cwa')!;
      expect(event.hypocenter, '屏東縣近海');
      expect(event.sourcePayload, fan);
    },
  );

  test(
    'TREM HTTP list, detail and existing catalog presentation keep their titles',
    () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          File(
            '$root/${request.url.hasQuery ? 'trem_list' : 'trem_detail'}.original.json',
          ).readAsBytesSync(),
          200,
        ),
      );
      addTearDown(client.close);
      final service = CwaEqlistService.forTesting(client);
      await service.fetchForTesting();
      expect(service.latestList, hasLength(25));
      expect(service.latestList.first.location, '臺灣東部海域');
      expect(service.latestList[1].location, '花蓮縣近海');
      expect(service.latestList[2].location, '花蓮縣卓溪鄉');
      final oldRow = service.latestList.first.copyWith(
        location: jian.first['placeName'] as String,
      );
      expect(
        QuakeEventAdapter.catalogInfo(oldRow, 'cwaEqlist').hypocenter,
        '臺灣東部海域',
      );
      expect(oldRow.location, jian.first['placeName']);
      service.stop();
    },
  );

  test(
    'all 22 overlapping Jian/TREM events share IDs, including three revised hypocenters',
    () {
      var matches = 0;
      var revisions = 0;
      for (final t in trem) {
        final rows = jian.where((j) => j['originTime'] == t['time']);
        if (rows.isEmpty) continue;
        matches++;
        final j = rows.single;
        final a = QuakeEventAdapter.convert('cwaEqlist', t, 0)!;
        final b = QuakeEventAdapter.convertJian('cwa', j)!;
        expect(
          catalogEventId(a.source, a.eventId),
          catalogEventId(b.source, b.eventId),
        );
        if (a.depth != b.depth ||
            a.lat != b.lat ||
            a.lng != b.lng ||
            a.magnitude != b.magnitude) {
          revisions++;
        }
        expect(a.sourcePayload, t);
        expect(b.sourcePayload, j);
      }
      expect(matches, 22);
      expect(revisions, 3);
      final w = QuakeEventAdapter.convertWhews('cwa', whews)!;
      final t = QuakeEventAdapter.convert('cwaEqlist', trem[9], 0)!;
      expect(
        catalogEventId(w.source, w.eventId),
        catalogEventId(t.source, t.eventId),
      );
      expect(
        catalogEventId('cwaEqlist', trem[0]['id'] as String),
        isNot(catalogEventId('cwaEqlist', trem[1]['id'] as String)),
      );
      expect(catalogEventId('cwaEew', '115000'), '115000');
      expect(cwaDisplayLocation('臺灣東部海域'), '臺灣東部海域');
    },
  );

  for (final native in [false, if (NativeUnifiedEventOwner.supported) true]) {
    for (final reversed in [false, true]) {
      test(
        'one CWA history row per event with all real sources, native=$native reverse=$reversed',
        () async {
          final mapper = QuakeProvider(
            startCatalogServices: false,
            nativeUnifiedEvents: false,
          );
          await mapper.eewHistoryReadyForTest;
          final manager = EqlistManager();
          final owner = native
              ? NativeUnifiedEventOwner(onBatch: (_, _) {})
              : null;
          try {
            manager.onBucketUpsertAsync = null;
            manager.onBucketUpsert = owner == null
                ? null
                : (bucket, current, incoming, replayOnly) => owner.upsertBucket(
                    bucket,
                    current,
                    incoming,
                    replayOnly: replayOnly,
                  );
            manager.updateCwaList([]);
            final events = <UnifiedQuakeData>[
              for (final t in trem)
                QuakeEventAdapter.convert('cwaEqlist', t, 0)!,
              for (final j in jian)
                QuakeEventAdapter.convertJian('cwa', j, isHistory: true)!,
              QuakeEventAdapter.convertWhews('cwa', whews)!,
              // Compatibility of the FAN input schema, using original bytes'
              // decoded body. No made-up FAN event or edited earthquake fields.
              FanService.decodeEventPayload(whews, sourceHint: 'cwa')!,
            ];
            final delivery = reversed ? events.reversed.toList() : events;
            for (final event in [...delivery, ...delivery.reversed]) {
              manager.upsertBucketItem(
                'cwaEqlist',
                mapper.unifiedToQuakeMessageForTest(event),
                replayOnly: true,
              );
              final ids = manager.cwaList
                  .map((r) => catalogEventId('cwaEqlist', r.eventId))
                  .toList();
              expect(ids.toSet().length, ids.length, reason: event.eventId);
              expect(
                manager.cwaList.every((r) => !r.location.contains('公里')),
                isTrue,
              );
            }
            expect(manager.cwaList, hasLength(50));
            expect(manager.cwaList.first.location, '臺灣東部海域');
            // Production HTTP/FAN snapshot entry points must merge as well;
            // a 25-row TREM refresh cannot erase the other 25 retained rows.
            manager.mergeCwaList([
              for (final t in trem)
                mapper.unifiedToQuakeMessageForTest(
                  QuakeEventAdapter.convert('cwaEqlist', t, 0)!,
                ),
            ], externalUpdate: false);
            expect(manager.cwaList, hasLength(50));
            final refreshedIds = manager.cwaList.map(
              (r) => catalogEventId('cwaEqlist', r.eventId),
            );
            expect(refreshedIds.toSet(), hasLength(50));
            // Already persisted duplicates must collapse even if the incoming
            // history row has no publication time and is rejected as older.
            final a = mapper.unifiedToQuakeMessageForTest(events.first);
            final b = mapper.unifiedToQuakeMessageForTest(events[25]);
            manager.updateCwaList([a, b]);
            manager.upsertBucketItem('cwaEqlist', b, replayOnly: true);
            expect(manager.cwaList, hasLength(1));
            expect(manager.cwaList.single.eventId, a.eventId);
          } finally {
            manager.onBucketUpsert = null;
            manager.updateCwaList([]);
            owner?.dispose();
            mapper.dispose();
          }
        },
      );
    }
    test(
      'CWA unified source identity agrees across transports, native=$native',
      () async {
        final provider = QuakeProvider(
          startCatalogServices: false,
          nativeUnifiedEvents: native,
        );
        addTearDown(provider.dispose);
        await provider.eewHistoryReadyForTest;
        for (final t in trem) {
          final match = jian.where((j) => j['originTime'] == t['time']);
          if (match.isEmpty) continue;
          final a = QuakeEventAdapter.convert('cwaEqlist', t, 0)!;
          final b = QuakeEventAdapter.convertJian('cwa', match.single)!;
          expect(
            provider.unifiedEventKeyForTest(a),
            provider.unifiedEventKeyForTest(b),
          );
        }
        final seen = <String, DateTime>{};
        final w = QuakeEventAdapter.convertWhews('cwa', whews)!;
        final t = QuakeEventAdapter.convert('cwaEqlist', trem[9], 0)!;
        for (final key in catalogReportKeys(w, seen).toList()) {
          seen[key] = DateTime.now();
        }
        expect(
          catalogCanonicalEventId(w, seen),
          catalogCanonicalEventId(t, seen),
        );
      },
    );
  }

  if (NativeUnifiedEventOwner.supported) {
    test(
      'production Rust worker merges original CWA reports asynchronously',
      () async {
        final mapper = QuakeProvider(
          startCatalogServices: false,
          nativeUnifiedEvents: false,
        );
        await mapper.eewHistoryReadyForTest;
        final owner = NativeUnifiedEventOwner(
          onBatch: (_, _) {},
          manualClock: false,
        );
        try {
          final events = [
            QuakeEventAdapter.convert('cwaEqlist', trem.first, 0)!,
            QuakeEventAdapter.convertJian('cwa', jian.first)!,
          ];
          var rows = <QuakeMessage>[];
          for (final event in [...events, ...events.reversed]) {
            final result = await owner.upsertBucketAsync(
              'cwaEqlist',
              rows,
              mapper.unifiedToQuakeMessageForTest(event),
              replayOnly: true,
            );
            rows = result.rows;
            expect(rows, hasLength(1));
            expect(rows.single.location, '臺灣東部海域');
            expect(rows.single.depth, 33.5);
          }
        } finally {
          owner.dispose();
          mapper.dispose();
        }
      },
    );
  }
}
