import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capturedText = File(
    'test/fixtures/early_est_history_20261009.original.json',
  ).readAsStringSync(encoding: utf8);
  final records = (jsonDecode(capturedText) as List)
      .map((item) => QuakeMessage.fromMap(Map<String, dynamic>.from(item)))
      .toList();
  final jian = records.singleWhere((e) => e.apiTypeLabel == 'Jian Project');
  final whews = records.singleWhere((e) => e.apiTypeLabel == 'WHEWS');
  final manager = EqlistManager();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager.getAllBuckets()['earlyEst']?.clear();
  });

  test('captured IDs prove identity across the revised hypocenter', () {
    expect(jian.eventId, 'EARLY_event_1791522664003');
    expect(whews.eventId, '1791522664003');
    expect(jian.longitude, 126.08);
    expect(whews.longitude, 126.05);
    expect(jian.magnitude, 4.9);
    expect(whews.magnitude, 5.0);
    expect(sameCatalogHistoryEvent('earlyEst', jian, whews), isTrue);
    expect(sameCatalogHistoryEvent('earlyEst', whews, jian), isTrue);
    expect(catalogEventId('earlyEst', jian.eventId), whews.eventId);
    expect(catalogEventId('whews_ingv', jian.eventId), jian.eventId);
    expect(
      catalogEventId('earlyEst', 'EARLY_event_other'),
      'EARLY_event_other',
    );
    expect(
      File(
        'test/fixtures/early_est_history_20261009.original.json',
      ).readAsStringSync(encoding: utf8),
      capturedText,
    );
  });

  for (final reverse in [false, true]) {
    test('report 9 survives either arrival order (reverse=$reverse)', () {
      for (final event in reverse ? [whews, jian] : [jian, whews]) {
        manager.upsertBucketItem('earlyEst', event, replayOnly: true);
      }
      expect(manager.getAllBuckets()['earlyEst'], [whews]);
      manager.upsertBucketItem('earlyEst', jian);
      expect(manager.getAllBuckets()['earlyEst'], [whews]);
    });

    test('legacy duplicates collapse on an old replay (reverse=$reverse)', () {
      manager.upsertBucketItem('earlyEst', whews);
      final list = manager.getAllBuckets()['earlyEst']!;
      list
        ..clear()
        ..addAll(reverse ? [whews, jian] : [jian, whews]);
      manager.upsertBucketItem('earlyEst', jian, replayOnly: true);
      expect(list, [whews]);
    });

    test('canonical identity stays stable across API revisions ($reverse)', () {
      final seen = <String, DateTime>{};
      for (final record in reverse ? [whews, jian] : [jian, whews]) {
        final event = unifiedHistory(record);
        expect(catalogCanonicalEventId(event, seen), '1791522664003');
        for (final key in catalogReportKeys(event, seen)) {
          seen[key] = DateTime.now();
        }
      }
    });
  }

  test(
    'a restored pre-fix identity is normalized without changing its cache',
    () {
      final oldIdentity = {
        'source': 'earlyEst',
        'id': jian.eventId,
        'api': '4|Jian Project',
        'observation': 'earlyEst|1791522669|0.780|126.080|71.0',
        'identity': jian.eventId,
      };
      final key =
          'catalog|agency-identity-v1|earlyEst|${jsonEncode(oldIdentity)}';
      final seen = {key: DateTime.now()};
      expect(
        catalogCanonicalEventId(unifiedHistory(jian), seen),
        whews.eventId,
      );
      expect(
        catalogCanonicalEventId(unifiedHistory(whews), seen),
        whews.eventId,
      );
      expect(seen.keys.single, key);
    },
  );

  test('unrelated unchanged captured Early-est ID stays distinct', () {
    final captured =
        jsonDecode(
              File(
                'test/fixtures/jian/all.json',
              ).readAsStringSync(encoding: utf8),
            )
            as Map;
    final otherId = captured['source：early-est']['Data']['id'] as String;
    expect(catalogEventId('earlyEst', otherId), isNot(whews.eventId));
  });

  test(
    'provider history rejects the previous report after the higher report',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      provider.handleUnifiedEventForTest(unifiedHistory(jian));
      provider.handleUnifiedEventForTest(unifiedHistory(whews));
      provider.handleUnifiedEventForTest(unifiedHistory(jian));
      final row = provider.historyBySource['earlyEst']!.single;
      expect(row.eventId, whews.eventId);
      expect(row.reportNumText, '第9報');
      expect(row.longitude, whews.longitude);
      expect(row.magnitude, whews.magnitude);
      expect(
        provider.unifiedEvents.where((e) => e.source == 'earlyEst'),
        isEmpty,
      );
      final captured =
          jsonDecode(
                File(
                  'test/fixtures/jian/all.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map;
      final other = QuakeEventAdapter.convertJian(
        'early-est',
        Map<String, dynamic>.from(captured['source：early-est']['Data'] as Map),
        isHistory: true,
      )!;
      provider.handleUnifiedEventForTest(other);
      expect(provider.historyBySource['earlyEst'], hasLength(2));
      expect(
        provider.historyBySource['earlyEst']!.map((e) => e.eventId),
        containsAll([whews.eventId, other.eventId]),
      );
    },
  );
}

// Map actual captured APP rows to the shared event type without retimestamping
// or treating these records as raw upstream packets.
UnifiedQuakeData unifiedHistory(QuakeMessage row) => UnifiedQuakeData(
  source: 'earlyEst',
  origin: row.apiTypeLabel == 'WHEWS' ? 3 : 4,
  eventId: row.eventId,
  isEew: false,
  timeZone: row.timeZone ?? 8,
  titleText: row.infoTypeName ?? '',
  reportNumText: row.reportNumText ?? '',
  hasReportSequence: true,
  useShindo: false,
  maxIntensity: row.maxIntensity?.toString() ?? '',
  className: '',
  hypocenter: row.location,
  originTime: row.originTime,
  reportTime: row.reportTime,
  magnitude: row.magnitude,
  depth: row.depth,
  lat: row.latitude,
  lng: row.longitude,
  apiTypeLabel: row.apiTypeLabel ?? '',
  isHistory: true,
);
