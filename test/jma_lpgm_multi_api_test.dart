import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_api_adapter.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';

const root = 'test/fixtures/jma_lpgm_20261108';
final realP2p =
    jsonDecode(
          File(
            '$root/p2p_551_live_all_reports.original.json',
          ).readAsStringSync(),
        )
        as List<dynamic>;
final officialXml = File(
  '$root/20261107161354_0_VXSE62_010000.xml',
).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'actual P2P API: six raw message IDs join one official VXSE62 only with full evidence',
    () {
      final service = JmaLpgmService();
      addTearDown(service.dispose);
      final real = service.parseDetailForTesting(officialXml)!;
      expect(real.eventId, '20261108010441');
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      addTearDown(provider.dispose);
      provider.acceptJmaLpgm(
        JmaLpgmBulletin.fromMap({
          ...real.toMap(),
          'reportTime': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final seenOriginalIds = <String>{};
      var matched = 0;
      var rejectedIncomplete = 0;
      for (final raw in realP2p.cast<Map>()) {
        final record = Map<String, dynamic>.from(raw);
        final wireId = record['id'] as String;
        expect(wireId, hasLength(24));
        expect(seenOriginalIds.add(wireId), true);
        final adapted = QuakeEventAdapter.convert('jmaEqlist', record, 2);
        expect(adapted, isNotNull);
        // P2P uses earthquake.time as its *adapted* ID. The wire ID stays in
        // its original JSON, not in the JMA EventID field.
        expect(adapted!.eventId, '2026-11-08 01:04:00');
        final companion = provider.associatedJmaInformationFor(adapted);
        if (adapted.magnitude > 0 &&
            (adapted.lat ?? 0) > 20 &&
            (adapted.lng ?? 0) > 120) {
          expect(
            companion.jmaLpgmBulletin?.eventId,
            real.eventId,
            reason: wireId,
          );
          matched++;
        } else {
          expect(companion.jmaLpgmBulletin, isNull, reason: wireId);
          rejectedIncomplete++;
        }
      }
      expect(seenOriginalIds, hasLength(6));
      expect(matched, 3);
      expect(rejectedIncomplete, 3);
    },
  );

  test(
    'captured JIAN and WHEWS ordinary JMA IDs are not misclassified as VXSE62',
    () {
      final jianCapture =
          jsonDecode(
                File(
                  'test/fixtures/jian/jmalist_response.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final jian = Map<String, dynamic>.from(
        (jianCapture['Data'] as List).first as Map,
      );
      expect(jian['id'], '20260916172127');
      expect(
        QuakeEventAdapter.convertJian('jma', jian)?.jmaLpgmBulletin,
        isNull,
      );

      final whewsCapture =
          jsonDecode(
                File(
                  'test/fixtures/catalog_20260917/whews_all.json',
                ).readAsStringSync(),
              )
              as List;
      final whews = whewsCapture.cast<Map>().firstWhere(
        (x) => x['source'] == 'jma',
      );
      final payload = Map<String, dynamic>.from(whews['Data'] as Map);
      expect(payload['id'], '20260917061143');
      expect(
        QuakeEventAdapter.convertWhews('jma', payload)?.jmaLpgmBulletin,
        isNull,
      );
    },
  );

  test(
    'JIAN/WHEWS constructed VXSE62 envelopes preserve real original XML fields',
    () {
      // Envelope is synthetic: neither provider's raw VXSE62 JSON was captured.
      // The XML contents/real EventID are the original official JMA report.
      final headers = [
        <String, dynamic>{
          'id': 'transport-jian-id',
          'telegram': 'VXSE62',
          'xmlReport': officialXml,
          'originTime': '2026-11-08 01:04:00',
          'reportTime': DateTime.now().toUtc().toIso8601String(),
        },
        <String, dynamic>{
          'id': 'transport-whews-id',
          'telegramType': 'VXSE62',
          'xmlReport': officialXml,
          'shockTime': '2026-11-08 01:04:00',
          'createTime': DateTime.now().toUtc().toIso8601String(),
        },
      ];
      final jian = QuakeEventAdapter.convertJian('jma', headers[0]);
      final whews = QuakeEventAdapter.convertWhews('jma', headers[1]);
      for (final value in [jian, whews]) {
        expect(value, isNotNull);
        expect(value!.isJmaLpgm, isTrue);
        expect(value.source, 'jmaLpgm');
        expect(value.eventId, '20261108010441');
        expect(value.jmaLpgmBulletin?.stations, hasLength(4));
        expect(value.jmaLpgmBulletin?.regions, hasLength(3));
      }
      expect(
        QuakeEventAdapter.convertJian('jma-eew', {
          ...headers[0],
          'maxLgInt': 4,
        })?.jmaLpgmBulletin,
        isNull,
      );
    },
  );

  test(
    'projected relay JSON uses real field values, never creates missing stations',
    () {
      final official = JmaLpgmService();
      addTearDown(official.dispose);
      final real = official.parseDetailForTesting(officialXml)!;
      final projection = <String, dynamic>{
        'id': 'relay-nonofficial-example',
        'telegramType': 'VXSE62',
        'maxLgInt': real.maxLgInt,
        'magnitude': real.magnitude,
        'latitude': real.latitude,
        'longitude': real.longitude,
        'depth': real.depthKm,
        'originTime': '2026-11-08 01:04:00',
        'createTime': DateTime.now().toUtc().toIso8601String(),
        'regions': real.regions.map((e) => e.toMap()).toList(),
        'stations': real.stations.map((e) => e.toMap()).toList(),
      };
      final parsed = JmaLpgmApiAdapter.parse(projection, 'VXSE62');
      expect(parsed?.eventId, 'relay-nonofficial-example');
      expect(parsed?.originTime?.toUtc(), DateTime.utc(2026, 11, 7, 16, 4));

      expect(parsed?.regions, hasLength(3));
      expect(parsed?.stations, hasLength(4));
      final partial = JmaLpgmApiAdapter.parse({
        ...projection,
        'regions': [],
        'stations': [],
      }, 'VXSE62');
      expect(partial?.regions, isEmpty);
      expect(partial?.stations, isEmpty);
      expect(JmaLpgmApiAdapter.parse(projection, 'VXSE44'), isNull);
      expect(
        JmaLpgmApiAdapter.parse({
          ...projection,
          'maxLgInt': null,
        }, 'VXSE62')?.maxLgInt,
        real.maxLgInt,
      );
      expect(
        JmaLpgmApiAdapter.parse({
          ...projection,
          'maxLgInt': null,
          'regions': <Object>[],
          'stations': <Object>[],
        }, 'VXSE62'),
        isNull,
      );
    },
  );
}
