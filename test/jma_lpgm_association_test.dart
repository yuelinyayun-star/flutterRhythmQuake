import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixtures = 'test/fixtures/jma_lpgm_20261108';
final idPattern = RegExp(r'<EventID>([^<]+)</EventID>');

UnifiedQuakeData jmaInfo(String source, String id) => UnifiedQuakeData(
  source: source,
  origin: 1,
  eventId: id,
  isEew: false,
  timeZone: 9,
  titleText: '震源・震度に関する情報',
  reportNumText: '第2报',
  useShindo: true,
  maxIntensity: '5+',
  className: 'red',
  hypocenter: '静岡県西部',
  depth: 40,
  depthText: '40km',
  magnitude: 5.7,
  originTime: DateTime(2026, 11, 8, 1, 4),
  reportTime: DateTime(2026, 11, 8, 1, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cross API identifiers require independent physical agreement', () {
    final parser = JmaLpgmService();
    addTearDown(parser.dispose);
    final realXml = File(
      '$fixtures/20261107161354_0_VXSE62_010000.xml',
    ).readAsStringSync();
    final bulletin = parser.parseDetailForTesting(realXml)!;
    final provider = QuakeProvider(
      startCatalogServices: false,
      nativeUnifiedEvents: true,
    );
    addTearDown(provider.dispose);
    provider.acceptJmaLpgm(
      JmaLpgmBulletin.fromMap({
        ...bulletin.toMap(),
        'reportTime': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    // P2P raw id, adapted earthquake.time, JMA HTTP time-key and
    // Wolfx md5 all differ from the official JMA EventID.
    final candidates = [
      '2026-11-08 01:04:00',
      '2026/11/08 01:04:00',
      '6aea60b5e88ee598246bf46c',
      'md5-from-other-transport',
      '20261108010400',
    ];
    for (final id in candidates) {
      final item = jmaInfo('p2pJmaEqlist', id).copyWith(lat: 34.9, lng: 137.7);
      final result = provider.associatedJmaInformationFor(item);
      expect(result.jmaLpgmBulletin?.eventId, bulletin.eventId, reason: id);
      expect(result.source, 'p2pJmaEqlist');
      expect(result.maxIntensity, item.maxIntensity);
    }
    final base = jmaInfo(
      'jmaEqlist',
      'timestamp-generated-by-api',
    ).copyWith(lat: 34.9, lng: 137.7);
    for (final invalid in [
      base.copyWith(lat: 35.3),
      base.copyWith(lng: 138.2),
      base.copyWith(magnitude: 6.5),
      base.copyWith(depth: 80),
      base.copyWith(magnitude: -1),
      base.copyWith(lat: null).copyWith(lat: 0),
      base.copyWith(originTime: DateTime(2026, 11, 8, 1, 6)),
    ]) {
      expect(
        provider.associatedJmaInformationFor(invalid).jmaLpgmBulletin,
        isNull,
        reason: invalid.eventId,
      );
    }
    // Even if the physical solutions coincide, two different official
    // 14-digit IDs are never merged by the fallback.
    expect(
      provider
          .associatedJmaInformationFor(base.copyWith(eventId: '20261108010442'))
          .jmaLpgmBulletin,
      isNull,
    );
  });

  test(
    'nonofficial long-period IDs link by evidence but ambiguous links fail',
    () {
      final parser = JmaLpgmService();
      addTearDown(parser.dispose);
      final xml = File(
        '$fixtures/20261107161354_0_VXSE62_010000.xml',
      ).readAsStringSync();
      final bulletin = parser.parseDetailForTesting(xml)!;
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      addTearDown(provider.dispose);
      final now = DateTime.now().toUtc().toIso8601String();
      final nonofficial = JmaLpgmBulletin.fromMap({
        ...bulletin.toMap(),
        'eventId': 'api-provider-unique-lpgm-id',
        'reportTime': now,
      });
      provider.acceptJmaLpgm(nonofficial);
      final normal = jmaInfo(
        'jmaEqlist',
        bulletin.eventId,
      ).copyWith(lat: 34.9, lng: 137.7);
      expect(
        provider.associatedJmaInformationFor(normal).jmaLpgmBulletin?.eventId,
        nonofficial.eventId,
      );
      provider.acceptJmaLpgm(
        JmaLpgmBulletin.fromMap({
          ...nonofficial.toMap(),
          'eventId': 'another-api-lpgm-id',
        }),
      );
      // No arbitrary selection where two different report IDs plausibly match.
      expect(
        provider.associatedJmaInformationFor(normal).jmaLpgmBulletin,
        isNull,
      );
    },
  );

  test(
    'real VXSE53 and VXSE62 are associated without changing primary quake fields',
    () {
      final ordinaryXml = File(
        '$fixtures/20261107161257_0_VXSE53_010000.xml',
      ).readAsStringSync();
      final lpgmXml = File(
        '$fixtures/20261107161354_0_VXSE62_010000.xml',
      ).readAsStringSync();
      final id = idPattern.firstMatch(ordinaryXml)!.group(1)!;
      final parser = JmaLpgmService();
      addTearDown(parser.dispose);
      final official = parser.parseDetailForTesting(lpgmXml)!;
      expect(id, official.eventId);
      expect(official.regions, hasLength(3));
      expect(official.stations, hasLength(4));
      final now = DateTime.now().toUtc();
      final active = JmaLpgmBulletin.fromMap({
        ...official.toMap(),
        'reportTime': now.toIso8601String(),
      });
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      addTearDown(provider.dispose);
      final normal = jmaInfo('jmaEqlist', id);
      expect(
        identical(provider.associatedJmaInformationFor(normal), normal),
        isTrue,
      );
      provider.acceptJmaLpgm(active);
      for (final source in ['jmaEqlist', 'p2pJmaEqlist']) {
        final original = jmaInfo(source, id);
        final joined = provider.associatedJmaInformationFor(original);
        expect(joined.isJmaLpgm, isFalse);
        expect(joined.source, source);
        expect(joined.titleText, original.titleText);
        expect(joined.maxIntensity, '5+');
        expect(joined.reportNumText, '第2报');
        expect(joined.jmaLpgmBulletin?.maxLgInt, 1);
        expect(joined.jmaLpgmBulletin?.stations, hasLength(4));
        expect(joined.jmaLpgmBulletin?.regions, hasLength(3));
      }
      for (final invalid in [
        jmaInfo('jmaEqlist', '20261108010442'),
        jmaInfo('cwaEqlist', id),
        jmaInfo('jmaEqlist', '20261108010400'),
        jmaInfo('jmaEqlist', id).copyWith(isEew: true),
      ]) {
        expect(
          provider.associatedJmaInformationFor(invalid).jmaLpgmBulletin,
          isNull,
        );
      }
      final updated = JmaLpgmBulletin.fromMap({
        ...active.toMap(),
        'serial': 2,
        'maxLgInt': 2,
        'reportTime': now.add(const Duration(seconds: 1)).toIso8601String(),
      });
      provider.acceptJmaLpgm(updated);
      expect(
        provider.associatedJmaInformationFor(normal).jmaLpgmBulletin?.serial,
        2,
      );
      provider.acceptJmaLpgm(active);
      expect(
        provider.associatedJmaInformationFor(normal).jmaLpgmBulletin?.serial,
        2,
      );
      provider.clearJmaLpgm(id);
      // UI expiry does not discard retained data needed for historical rendering.
      expect(
        provider.associatedJmaInformationFor(normal).jmaLpgmBulletin?.serial,
        2,
      );
      provider.acceptJmaLpgm(
        JmaLpgmBulletin.fromMap({...updated.toMap(), 'infoType': '取消'}),
      );
      expect(
        provider.associatedJmaInformationFor(normal).jmaLpgmBulletin,
        isNull,
      );
    },
  );
}
