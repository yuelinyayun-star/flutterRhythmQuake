import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final wolfxFile = File(
    'test/fixtures/cenc_history_20261014/wolfx.original.json',
  );
  final jianFile = File(
    'test/fixtures/cenc_history_20261014/jian.original.json',
  );
  final wolfxText = wolfxFile.readAsStringSync();
  final jianText = jianFile.readAsStringSync();
  final wolfxRaw = Map<String, dynamic>.from(jsonDecode(wolfxText) as Map);
  final precise = QuakeEventAdapter.convertWolfxCencEqlist(wolfxRaw).first;
  final preciseUnified = QuakeEventAdapter.convert(
    'cencEqlist',
    Map<String, dynamic>.from(wolfxRaw['No1'] as Map),
    0,
  )!;
  final jianRows = (jsonDecode(jianText) as Map)['Data'] as List;
  final minuteUnified = QuakeEventAdapter.convertJian(
    'cenc',
    Map<String, dynamic>.from(jianRows.first as Map),
    isHistory: true,
  )!;
  late QuakeMessage minute;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EqlistManager().updateCencList(const []);
    final provider = QuakeProvider();
    minute = provider.unifiedToQuakeMessageForTest(minuteUnified);
    provider.dispose();
  });

  test('captured Panjin bulletins retain distinct raw IDs and timestamps', () {
    expect(precise.eventId, 'AU.20261014140625.8');
    expect(minute.eventId, 'CD.20261014141149.480_M');
    expect(precise.originTime.second, 25);
    expect(minute.originTime.second, 0);
    expect(precise.location, '辽宁盘锦市双台子区');
    expect(sameCatalogHistoryEvent('cencEqlist', precise, minute), isTrue);
    expect(compareCencHistoryOriginPrecision(precise, minute), -1);
    expect(compareCencHistoryOriginPrecision(minute, precise), 1);
    expect(wolfxFile.readAsStringSync(), wolfxText);
    expect(jianFile.readAsStringSync(), jianText);
  });

  for (final preciseFirst in [true, false]) {
    test('one precise list row in either arrival order: $preciseFirst', () {
      final manager = EqlistManager();
      for (final event
          in preciseFirst ? [precise, minute] : [minute, precise]) {
        manager.upsertBucketItem('cencEqlist', event, replayOnly: true);
      }
      expect(manager.cencList, hasLength(1));
      expect(manager.cencList.single.eventId, precise.eventId);
      expect(manager.cencList.single.originTime, precise.originTime);
      expect(manager.cencList.single.maxIntensity, precise.maxIntensity);
      manager.upsertBucketItem('cencEqlist', minute, replayOnly: true);
      expect(manager.cencList.single.eventId, precise.eventId);
    });

    test('shared unified identity respects raw precision: $preciseFirst', () {
      final seen = <String, DateTime>{};
      final first = preciseFirst ? preciseUnified : minuteUnified;
      final second = preciseFirst ? minuteUnified : preciseUnified;
      final identity = catalogCanonicalEventId(first, seen);
      for (final key in catalogReportKeys(first, seen).toList()) {
        seen[key] = DateTime.utc(2026, 10, 14, 7);
      }
      expect(catalogCanonicalEventId(second, seen), identity);
      expect(
        compareCencUnifiedOriginPrecision(preciseUnified, minuteUnified),
        -1,
      );
      expect(
        compareCencUnifiedOriginPrecision(minuteUnified, preciseUnified),
        1,
      );
    });
  }

  test(
    'existing duplicates collapse and manual unified UI uses precise row',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final manager = EqlistManager()..updateCencList([minute, precise]);
      provider.handleUnifiedEventForTest(minuteUnified);
      expect(manager.cencList, hasLength(1));
      provider.selectHistoryMapProducts(manager.cencList.single);
      expect(provider.historyInfoDisplayEvent!.originTime, precise.originTime);
      expect(provider.historyInfoDisplayEvent!.eventId, precise.eventId);
      expect(provider.historyInfoDisplayEvent!.apiTypeLabel, 'Wolfx');
      expect(provider.unifiedEvents, isEmpty);
    },
  );

  test('other captured bulletins and independent products remain separate', () {
    for (final row in QuakeEventAdapter.convertWolfxCencEqlist(
      wolfxRaw,
    ).skip(1)) {
      expect(sameCatalogHistoryEvent('cencEqlist', row, minute), isFalse);
    }
    for (final raw in jianRows.skip(1)) {
      final event = QuakeEventAdapter.convertJian(
        'cenc',
        Map<String, dynamic>.from(raw as Map),
        isHistory: true,
      )!;
      expect(compareCencUnifiedOriginPrecision(preciseUnified, event), isNull);
    }
    expect(sameCatalogHistoryEvent('cencCmt', precise, minute), isFalse);
    expect(wolfxFile.readAsStringSync(), wolfxText);
    expect(jianFile.readAsStringSync(), jianText);
  });
}
