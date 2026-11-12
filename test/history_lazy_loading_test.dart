import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/history_storage.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'history_panel_layout_test.dart' show HistoryProvider;
import 'history_replay_timeline_test.dart' show captured, saved;

class CountedStorage implements HistoryStorage, HistorySnapshotStorage {
  CountedStorage(this.delegate);
  final HistoryStorage delegate;
  int bodyReads = 0, snapshotReads = 0;
  Completer<void>? gate;
  @override
  bool get separate => delegate.separate;
  @override
  Future<Object?> read(String key) async {
    if (key.contains('_event_')) {
      bodyReads++;
      await gate?.future;
    }
    return delegate.read(key);
  }

  @override
  Future<Map<String, dynamic>?> readSnapshot(String key) {
    snapshotReads++;
    return (delegate as HistorySnapshotStorage).readSnapshot(key);
  }

  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) => (delegate as HistorySnapshotStorage).writeWithSnapshot(
    key,
    value,
    snapshot,
  );
  @override
  Future<bool> write(String key, Object value) => delegate.write(key, value);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
}

// Keep the old backend's snapshot/migration regression tests independent of the
// new directory backend, which is exercised in history_directory_replay_test.
class LegacyWorkerHistory implements HistoryStorage, HistorySnapshotStorage {
  LegacyWorkerHistory(this.worker);
  final WindowsPreferencesWorker worker;
  @override
  bool get separate => true;
  @override
  Future<Object?> read(String key) => worker.readHistory(key);
  @override
  Future<bool> write(String key, Object value) =>
      worker.writeHistory(key, value);
  @override
  Future<bool> remove(String key) => worker.removeHistory(key);
  @override
  Future<Map<String, dynamic>?> readSnapshot(String key) =>
      worker.readHistorySnapshot(key);
  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) => worker.writeHistoryWithSnapshot(key, value, snapshot);
}

class LazyHistoryProvider extends HistoryProvider {
  LazyHistoryProvider(super.groups, this.store);
  final EewHistoryStore store;
  int loads = 0;
  @override
  Future<EewEventGroup> loadHistoryReports(EewEventGroup group) {
    loads++;
    return store.loadReports(group);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late WindowsPreferencesWorker worker;
  late SharedPreferencesStorePlatform previous;
  late SharedPreferences prefs;
  late CountedStorage storage;
  EewHistoryStore store() =>
      EewHistoryStore(preferenceKey: 'unified_eew_history', storage: storage);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    previous = SharedPreferencesStorePlatform.instance;
    directory = await Directory.systemTemp.createTemp('rq-lazy-history-');
    worker = await WindowsPreferencesWorker.start(directory.path);
    SharedPreferencesStorePlatform.instance = worker;
    storage = CountedStorage(LegacyWorkerHistory(worker));
  });
  tearDown(() async {
    SharedPreferencesStorePlatform.instance = previous;
    await worker.close();
    final resolved = directory.absolute.path;
    expect(
      resolved.startsWith(
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
      ),
      isTrue,
    );
    await directory.delete(recursive: true);
  });

  test(
    'startup reads summaries only; on-demand bodies and exports stay exact',
    () async {
      final original = saved(captured('cwa_1150074'));
      final writer = store();
      await writer.save(prefs, [original]);
      final originalText = await worker.readHistory(writer.recordKey(original));
      final cold = store();
      storage.bodyReads = 0;
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(storage.bodyReads, 0);
      expect(storage.snapshotReads, 1);
      expect(summary.hasDeferredReports, isTrue);
      expect(summary.savedReportCount, original.savedReportCount);
      expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
      expect(() => summary.toMap(), throwsStateError);
      final preview = HistoryReplayPackage.fromGroup(summary);
      expect(preview.times, HistoryReplayPackage.fromGroup(original).times);
      expect(preview.encodeBytes, throwsStateError);
      await cold.save(prefs, [summary]);
      expect(storage.bodyReads, 0);
      expect(
        await worker.readHistory(writer.recordKey(original)),
        originalText,
      );
      final a = cold.loadReports(summary), b = cold.loadReports(summary);
      expect(identical(a, b), isTrue);
      final loaded = await a;
      expect(await b, same(loaded));
      expect(storage.bodyReads, 1);
      expect(loaded.toMap(), original.toMap());
      expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
      expect(
        HistoryReplayPackage.fromGroup(loaded).encode(),
        HistoryReplayPackage.fromGroup(original).encode(),
      );
      await cold.loadReports(summary);
      expect(
        storage.bodyReads,
        2,
      ); // Completed reads do not retain hydrated bodies.
    },
  );

  test(
    'a later original report preserves all earlier deferred bodies on save',
    () async {
      final original = saved(captured('cwa_1150074'));
      final chronological = original.reports.reversed.toList();
      expect(chronological.length, greaterThan(1));
      final first = original.copyWith(reports: [chronological.first]);
      final writer = store();
      await writer.save(prefs, [first]);
      final cold = store();
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      final updated = summary.addReport(chronological[1]);
      await cold.save(prefs, [updated]);
      final restarted = store();
      final latest = (await restarted.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      final loaded = await restarted.loadReports(latest);
      expect(loaded.toMap(), first.addReport(chronological[1]).toMap());
      expect(loaded.savedReportCount, 2);
    },
  );

  testWidgets('directory report rows expand without reading original bodies', (
    tester,
  ) async {
    late EewEventGroup summary;
    late EewHistoryStore files;
    await tester.runAsync(() async {
      files = EewHistoryStore(
        preferenceKey: 'unified_eew_history',
        storage: historyStorage(prefs),
      );
      await files.save(prefs, [saved(captured('cwa_1150074'))]);
      summary = (await files.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
    });
    final provider = LazyHistoryProvider([summary], files);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<QuakeProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 350, child: HistoryPanel())),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    expect(find.text('第4報'), findsOneWidget);
    expect(provider.loads, 0);
    expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'linked replay loads selected originals and stop releases its full package',
    () async {
      final originals = [
        saved(captured('cwa_1150074')),
        saved(captured('cea_202609290220')),
      ];
      await store().save(prefs, originals);
      final cold = store();
      final summaries = await cold.restoreForStartup(prefs, lazyReports: true);
      final output = <UnifiedQuakeData>[];
      final controller = HistoryReplayController(
        onReport: output.add,
        onClear: (_) {},
        historyGroups: () => summaries,
        loadHistoryGroup: cold.loadStationFrames,
      );
      addTearDown(controller.dispose);
      controller.restoreTimelineLinked(true);
      controller.load(
        HistoryReplayPackage.fromGroup(summaries.first),
        storedGroup: summaries.first,
        remember: false,
      );
      await controller.playPrepared();
      expect(controller.active, isTrue);
      expect(controller.linkedEventCount, 2);
      expect(output.every((r) => r.sourcePayload?.isNotEmpty == true), isTrue);
      controller.stop();
      expect(controller.package!.storedReports, isNotNull);
      expect(
        controller.package!.reports.every((r) => r.sourcePayload == null),
        isTrue,
      );
      expect(controller.importedPackages, isEmpty);
    },
  );

  test(
    'a pending local selection follows persisted summaries and deletion',
    () async {
      final original = saved(captured('cwa_1150074'));
      var current = [original];
      final controller = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) {},
        historyGroups: () => current,
      );
      addTearDown(controller.dispose);
      controller.load(
        HistoryReplayPackage.fromGroup(original),
        storedGroup: original,
        remember: false,
      );
      // Stop may precede the asynchronous persistence of a new live report.
      controller.stop();
      expect(controller.package!.reports.first.sourcePayload, isNotNull);
      final writer = store();
      await writer.save(prefs, current);
      final summary = writer.releaseSavedFrames(original, deferReports: true);
      current = [summary];
      controller.refreshStoredSelection();
      expect(controller.package!.storedReports, isNotNull);
      expect(
        controller.package!.reports.every((r) => r.sourcePayload == null),
        isTrue,
      );
      // Stop also looks up the current provider snapshot without a prior refresh.
      controller.load(
        HistoryReplayPackage.fromGroup(original),
        storedGroup: original,
        remember: false,
      );
      controller.stop();
      expect(controller.package!.storedReports, isNotNull);
      current = [];
      controller.refreshStoredSelection();
      expect(controller.package, isNull);
      expect(controller.importedPackages, isEmpty);
    },
  );

  test(
    'stop during an original-body read prevents late replay delivery',
    () async {
      await store().save(prefs, [saved(captured('cwa_1150074'))]);
      final cold = store();
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      final output = <UnifiedQuakeData>[];
      final controller = HistoryReplayController(
        onReport: output.add,
        onClear: (_) {},
        loadHistoryGroup: cold.loadStationFrames,
      );
      addTearDown(controller.dispose);
      controller.load(
        HistoryReplayPackage.fromGroup(summary),
        storedGroup: summary,
        remember: false,
      );
      storage.gate = Completer<void>();
      final pending = controller.playPrepared();
      await Future<void>.delayed(Duration.zero);
      expect(controller.preparing, isTrue);
      controller.stop();
      storage.gate!.complete();
      await pending;
      expect(controller.active, isFalse);
      expect(output, isEmpty);
      expect(
        controller.package!.reports.every((r) => r.sourcePayload == null),
        isTrue,
      );
    },
  );

  testWidgets(
    'expand loads originals, collapse and drawer close discard details',
    (tester) async {
      final original = saved(captured('cwa_1150074'));
      late EewHistoryStore cold;
      late EewEventGroup summary;
      await tester.runAsync(() async {
        await store().save(prefs, [original]);
        cold = store();
        summary = (await cold.restoreForStartup(
          prefs,
          lazyReports: true,
        )).single;
      });
      final provider = LazyHistoryProvider([summary], cold);
      addTearDown(provider.dispose);
      var active = true;
      late StateSetter update;
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Scaffold(
                  body: SizedBox(
                    width: 350,
                    child: HistoryPanel(active: active),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(provider.loads, 0);
      Future<void> expand() async {
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
      }

      await expand();
      expect(provider.loads, 1);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      await expand();
      expect(provider.loads, 2);
      update(() => active = false);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      update(() => active = true);
      await tester.pump();
      await expand();
      expect(provider.loads, 3);
      expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'new raw report stays owned until its exact group is durably saved',
    () async {
      final original = saved(captured('cwa_1150074'));
      final chronological = original.reports.reversed.toList();
      final first = original.copyWith(reports: [chronological.first]);
      final writer = store();
      await writer.save(prefs, [first]);
      final firstSummary = writer.releaseSavedFrames(first, deferReports: true);
      expect(firstSummary.hasDeferredReports, isTrue);
      final newer = firstSummary.addReport(chronological[1]);
      final stillOwned = writer.releaseSavedFrames(newer, deferReports: true);
      expect(
        stillOwned.reports.any(
          (r) => identical(r, chronological[1]) && r.sourcePayload != null,
        ),
        isTrue,
      );
      await writer.save(prefs, [stillOwned]);
      final summary = writer.releaseSavedFrames(stillOwned, deferReports: true);
      expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
      expect(
        (await writer.loadReports(summary)).toMap(),
        first.addReport(chronological[1]).toMap(),
      );
    },
  );

  test(
    'failed snapshot migration keeps the original record and retries atomically',
    () async {
      final original = saved(captured('cwa_1150074'));
      final cold = store();
      final key = cold.recordKey(original);
      final text = jsonEncode(original.toMap());
      await worker.writeHistory(key, text);
      await worker.writeHistory(cold.indexKey, [key]);
      final name = sha256.convert(utf8.encode('flutter.$key')).toString();
      final obstruction = Directory(
        '${directory.path}/eew_history/$name.json.tmp',
      );
      await obstruction.create();
      await expectLater(
        cold.restoreForStartup(prefs, lazyReports: true),
        throwsStateError,
      );
      expect(await worker.readHistory(key), text);
      await obstruction.delete();
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(summary.hasDeferredReports, isTrue);
      expect(await worker.readHistory(key), text);
      expect((await cold.loadReports(summary)).toMap(), original.toMap());
    },
  );

  test(
    'early snapshots rebuild badge metadata once without rewriting originals',
    () async {
      final original = saved(captured('cwa_1150074'));
      final writer = store();
      await writer.save(prefs, [original]);
      final key = writer.recordKey(original);
      final text = await worker.readHistory(key) as String;
      final header = (await worker.readHistorySnapshot(key))!;
      header.remove('presentationVersion');
      for (final report in (header['group'] as Map)['reports'] as List) {
        (report as Map)
          ..remove('displayEstimatedIntensity')
          ..remove('displayEstimateResolved');
      }
      await worker.writeHistoryWithSnapshot(key, text, header);
      storage.bodyReads = 0;
      final upgraded = (await store().restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(storage.bodyReads, 1);
      expect(upgraded.latest.displayEstimateResolved, isTrue);
      expect(
        unifiedEewIntensityValue(upgraded.latest),
        unifiedEewIntensityValue(original.latest),
      );
      expect(await worker.readHistory(key), text);
      storage.bodyReads = 0;
      final restarted = (await store().restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(storage.bodyReads, 0);
      expect(restarted.latest.displayEstimateResolved, isTrue);
      expect((await store().loadReports(restarted)).toMap(), original.toMap());
    },
  );

  final fixture = Platform.environment['RQ_HISTORY_ORIGINAL_RECORDS'];
  test(
    'all original copied histories migrate and hydrate without changing raw records',
    () async {
      final source = Directory(fixture!);
      final target = Directory('${directory.path}/eew_history')..createSync();
      for (final file in source.listSync().whereType<File>()) {
        file.copySync('${target.path}/${file.uri.pathSegments.last}');
      }
      final indexName =
          '${sha256.convert(utf8.encode('flutter.unified_eew_history_index_v2'))}.json';
      final keys =
          (jsonDecode(File('${source.path}/$indexName').readAsStringSync())
                  as Map)['value']
              as List;
      final originalValues = <String, String>{};
      for (final key in keys) {
        originalValues[key as String] = await worker.readHistory(key) as String;
      }
      final cold = store();
      final summaries = await cold.restoreForStartup(prefs, lazyReports: true);
      var gq = 0;
      for (final summary in summaries) {
        expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
        final loaded = await cold.loadReports(summary);
        final expected = EewEventGroup.fromMap(
          jsonDecode(originalValues[cold.recordKey(summary)]!) as Map,
        );
        expect(loaded.toMap(), expected.toMap());
        gq += loaded.reports
            .where(
              (r) => r.source == 'globalQuakeEew' && r.sourcePayload != null,
            )
            .length;
        expect(
          await worker.readHistory(cold.recordKey(summary)),
          originalValues[cold.recordKey(summary)],
        );
      }
      expect(gq, greaterThan(100));
      storage.bodyReads = 0;
      final restarted = await store().restoreForStartup(
        prefs,
        lazyReports: true,
      );
      expect(storage.bodyReads, 0);
      expect(restarted.length, summaries.length);
      // ignore: avoid_print
      print(
        'Original lazy history events=${summaries.length} GQ reports=$gq; all raw records exact',
      );
    },
    skip: fixture == null,
  );
}
