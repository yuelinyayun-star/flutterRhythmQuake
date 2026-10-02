import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/eew_history_retention.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_replay_test.dart' as recorded;

// Storage identities and ordering only; the captured earthquake body is unchanged.
List<EewEventGroup> storageGroups() {
  final captured = recorded.recordedEew();
  final cwa = HistoryReplayPackage.decode(
    File(
      'test/fixtures/history_replay/cwa_1150074.rqreplay',
    ).readAsStringSync(),
  ).reports.first;
  return [
    for (var i = 0; i < 40; i++)
      EewEventGroup(
        eventId: 'storage-slot-$i',
        firstArrivedAt: DateTime.utc(2026, 9, 17).add(Duration(seconds: i)),
        reports: [i.isEven ? captured : cwa],
      ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default keeps 15 events for each source, not 15 total', () {
    final kept = const EewHistoryRetention().apply(storageGroups().reversed);
    expect(kept.length, 30);
    expect(kept.where((g) => g.latest.source == 'jmaEew').length, 15);
    expect(kept.where((g) => g.latest.source == 'cwaEew').length, 15);
    expect(kept.first.eventId, 'storage-slot-39');
    expect(kept.any((g) => g.eventId == 'storage-slot-0'), isFalse);
  });

  test('custom limit and permanent storage preserve per-event reports', () {
    final groups = storageGroups();
    expect(const EewHistoryRetention(maxPerSource: 3).apply(groups).length, 6);
    final retained = const EewHistoryRetention(keepForever: true).apply(groups);
    expect(retained.length, groups.length);
    expect(
      retained.last.reports.single.sourcePayload,
      groups.first.latest.sourcePayload,
    );
  });

  test('legacy migration, incremental update, pruning and restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final groups = storageGroups();
    await prefs.setString(
      'unified_eew_history',
      jsonEncode(groups.map((g) => g.toMap()).toList()),
    );
    final store = EewHistoryStore(preferenceKey: 'unified_eew_history');
    final restored = store.restore(prefs);
    expect(restored.length, 40);
    final kept = const EewHistoryRetention().apply(restored);
    await store.save(prefs, kept);
    expect(prefs.getString('unified_eew_history'), isNull);
    expect(prefs.getStringList(store.indexKey)!.length, 30);
    final record = store.recordKey(kept.first);
    final text = '${prefs.getString(record)} ';
    await prefs.setString(record, text);
    await store.save(prefs, kept);
    expect(
      prefs.getString(record),
      text,
      reason: 'Unchanged event is not re-encoded',
    );
    final restarted = EewHistoryStore(preferenceKey: 'unified_eew_history');
    expect(
      restarted.restore(prefs).map((g) => g.toMap()),
      kept.map((g) => g.toMap()),
    );
    await store.save(prefs, kept.skip(1).toList());
    expect(prefs.containsKey(record), isFalse);
    expect(restarted.restore(prefs).length, 29);
  });

  test(
    'same upstream event ID in two sources has independent storage keys',
    () {
      final store = EewHistoryStore(preferenceKey: 'history');
      final groups = storageGroups();
      final a = groups.first;
      final b = groups[1].copyWith(eventId: a.eventId);
      expect(store.recordKey(a), isNot(store.recordKey(b)));
    },
  );

  test('unreadable legacy history is preserved during migration', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('history', '{bad json');
    final store = EewHistoryStore(preferenceKey: 'history');
    expect(store.restore(prefs), isEmpty);
    await store.save(prefs, []);
    expect(prefs.getString('history'), '{bad json');
  });

  test(
    'disposing before restore completes does not overwrite existing history',
    () async {
      final text = jsonEncode(storageGroups().map((g) => g.toMap()).toList());
      SharedPreferences.setMockInitialValues({'unified_eew_history': text});
      final provider = QuakeProvider();
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('unified_eew_history'), text);
      expect(prefs.containsKey('unified_eew_history_index_v2'), isFalse);
    },
  );

  test(
    'provider restores per-source limits and persists changed settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'unified_eew_history': jsonEncode(
          storageGroups().map((g) => g.toMap()).toList(),
        ),
        EewHistoryRetention.keepForeverKey: true,
      });
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.eewHistory.length, 40);
      await provider.setEewHistoryRetention(
        const EewHistoryRetention(maxPerSource: 4),
      );
      expect(provider.eewHistory.length, 8);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(EewHistoryRetention.maxPerSourceKey), 4);
      expect(prefs.getBool(EewHistoryRetention.keepForeverKey), isFalse);
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final restarted = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(restarted.eewHistory.length, 8);
      expect(restarted.eewHistoryRetention.maxPerSource, 4);
      restarted.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );
}
