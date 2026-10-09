import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/catalog_event_identity.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final wolfxText = File(
    'test/fixtures/cenc_history_20261009/wolfx.original.json',
  ).readAsStringSync();
  final jianText = File(
    'test/fixtures/cenc_history_20261009/jian.original.json',
  ).readAsStringSync();
  final wolfx = QuakeEventAdapter.convertWolfxCencEqlist(
    Map<String, dynamic>.from(jsonDecode(wolfxText) as Map),
  ).first;
  final jianEvent = QuakeEventAdapter.convertJian(
    'cenc',
    Map<String, dynamic>.from(jsonDecode(jianText) as Map),
    isHistory: true,
  )!;
  late QuakeMessage jian;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EqlistManager().updateCencList(const []);
    final provider = QuakeProvider();
    jian = provider.unifiedToQuakeMessageForTest(jianEvent);
    provider.dispose();
  });

  test(
    'captured CENC native and Jian manual IDs match without changing raw data',
    () {
      expect(wolfx.eventId, 'CD.20261009122537.626');
      expect(jian.eventId, 'CD.20261009122537.626_M');
      expect(wolfx.originTime.second, 53);
      expect(jian.originTime.second, 0);
      expect(sameCatalogHistoryEvent('cencEqlist', wolfx, jian), isTrue);
      expect(catalogEventId('cencEqlist', jian.eventId), wolfx.eventId);
      expect(catalogEventId('usgsCmt', jian.eventId), jian.eventId);
      expect(catalogEventId('cencEqlist', 'unrecognized_M'), 'unrecognized_M');
      expect(
        File(
          'test/fixtures/cenc_history_20261009/wolfx.original.json',
        ).readAsStringSync(),
        wolfxText,
      );
      expect(
        File(
          'test/fixtures/cenc_history_20261009/jian.original.json',
        ).readAsStringSync(),
        jianText,
      );
    },
  );

  for (final preciseFirst in [true, false]) {
    test(
      'history replay retains full original seconds, preciseFirst=$preciseFirst',
      () {
        final manager = EqlistManager();
        for (final row in preciseFirst ? [wolfx, jian] : [jian, wolfx]) {
          manager.upsertBucketItem('cencEqlist', row, replayOnly: true);
        }
        expect(manager.cencList, hasLength(1));
        expect(manager.cencList.single.eventId, wolfx.eventId);
        expect(manager.cencList.single.originTime, wolfx.originTime);
        expect(manager.cencList.single.maxIntensity, wolfx.maxIntensity);
        manager.upsertBucketItem('cencEqlist', jian, replayOnly: true);
        expect(manager.cencList.single.eventId, wolfx.eventId);
      },
    );
  }

  test(
    'existing duplicate rows are collapsed when a minute-precision replay arrives',
    () {
      final manager = EqlistManager();
      final captured =
          (jsonDecode(
                    File(
                      'test/fixtures/cenc_history_20261009/app_history.original.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .take(2)
              .map(
                (row) =>
                    QuakeMessage.fromMap(Map<String, dynamic>.from(row as Map)),
              )
              .toList();
      manager.updateCencList(captured);
      manager.upsertBucketItem('cencEqlist', jian, replayOnly: true);
      expect(manager.cencList, hasLength(1));
      expect(manager.cencList.single.eventId, wolfx.eventId);
      expect(manager.cencList.single.originTime.second, 53);
    },
  );

  test('other original CENC bulletins remain separate', () {
    final rows = QuakeEventAdapter.convertWolfxCencEqlist(
      Map<String, dynamic>.from(jsonDecode(wolfxText) as Map),
    );
    for (final row in rows.skip(1)) {
      expect(
        sameCatalogHistoryEvent('cencEqlist', row, jian),
        isFalse,
        reason: row.eventId,
      );
    }
    expect(sameCatalogHistoryEvent('cencCmt', wolfx, jian), isFalse);
  });

  test(
    'real list replay and manual unified card retain the precise source row',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      var notifications = 0;
      provider.onUnifiedEventNotified = (_, _) => notifications++;
      EqlistManager().updateCencList([wolfx]);
      provider.handleUnifiedEventForTest(jianEvent);
      expect(provider.historyBySource['cencEqlist'], hasLength(1));
      expect(
        provider.historyList.where((e) => e.source == QuakeSourceType.cenc),
        hasLength(1),
      );
      provider.selectHistoryMapProducts(
        provider.historyBySource['cencEqlist']!.single,
      );
      expect(provider.historyInfoDisplayEvent!.originTime, wolfx.originTime);
      expect(provider.historyInfoDisplayEvent!.eventId, wolfx.eventId);
      expect(provider.historyInfoDisplayEvent!.apiTypeLabel, 'Wolfx');
      expect(provider.unifiedEvents, isEmpty);
      expect(notifications, 0);
    },
  );
}
