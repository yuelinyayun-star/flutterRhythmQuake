import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'history_replay_timeline_test.dart' as timeline;
import 'history_replay_test.dart' as recorded;

const prefix = 'unified_eew_history';

EewEventGroup fixtureGroup() {
  final replay = HistoryReplayPackage.decode(
    File(
      'test/fixtures/history_replay/cwa_1150074.rqreplay',
    ).readAsStringSync(),
  );
  final observed =
      jsonDecode(
            File(
              'test/fixtures/whews_nied/observations.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return EewEventGroup(
    eventId: replay.reports.first.eventId,
    reports: replay.reports,
    firstArrivedAt: replay.times.first,
    stationFrames: [
      StationHistoryFrame(
        receivedAt: replay.times.first,
        snapshot: {'kind': 'nied', 'stations': []},
        originalJson: observed,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late WindowsPreferencesWorker worker;
  late SharedPreferencesStorePlatform previous;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    previous = SharedPreferencesStorePlatform.instance;
    directory = await Directory.systemTemp.createTemp('rq-history-storage-');
    worker = await WindowsPreferencesWorker.start(directory.path);
    SharedPreferencesStorePlatform.instance = worker;
  });
  tearDown(() async {
    SharedPreferencesStorePlatform.instance = previous;
    await worker.close();
    await directory.delete(recursive: true);
  });

  test(
    'migration preserves original bytes and keeps history out of settings cache',
    () async {
      final original = File(
        'test/fixtures/whews_nied/observations.json',
      ).readAsStringSync();
      final source = jsonEncode({
        'flutter.normal': true,
        'flutter.${prefix}_station_archive_existing': original,
        'external': 'preserve',
      });
      final file = File('${directory.path}/shared_preferences.json');
      await file.writeAsString(source);
      expect(await worker.getAll(), {'flutter.normal': true});
      expect(
        await worker.readHistory('${prefix}_station_archive_existing'),
        original,
      );
      expect(
        await File(
          '${directory.path}/shared_preferences.before_history_split.json',
        ).readAsString(),
        source,
      );
      expect(jsonDecode(await file.readAsString()), {
        'flutter.normal': true,
        'external': 'preserve',
      });
      final before = await file.lastModified();
      await worker.remove('flutter.absent');
      await worker.setValue('Bool', 'flutter.normal', true);
      expect(await file.lastModified(), before);
      await worker.close();
      worker = await WindowsPreferencesWorker.start(directory.path);
      SharedPreferencesStorePlatform.instance = worker;
      expect(
        await worker.readHistory('${prefix}_station_archive_existing'),
        original,
      );
      expect(await worker.getAll(), {'flutter.normal': true});
    },
  );

  test(
    'failed migration leaves original intact and retries without losing records',
    () async {
      const key = 'flutter.${prefix}_station_archive_retry';
      final original = File(
        'test/fixtures/whews_nied/observations.json',
      ).readAsStringSync();
      final text = jsonEncode({key: original, 'flutter.enabled': true});
      final file = File('${directory.path}/shared_preferences.json');
      await file.writeAsString(text);
      final obstruction = Directory(
        '${directory.path}/eew_history/${sha256.convert(utf8.encode(key))}.json.tmp',
      );
      await obstruction.create(recursive: true);
      await expectLater(worker.getAll(), throwsStateError);
      expect(await file.readAsString(), text);
      await obstruction.delete();
      expect(await worker.getAll(), {'flutter.enabled': true});
      expect(
        await worker.readHistory(key.substring('flutter.'.length)),
        original,
      );
      expect(
        await File(
          '${directory.path}/shared_preferences.before_history_split.json',
        ).readAsString(),
        text,
      );
    },
  );

  test(
    'public and personal namespaces retain independent indexes and archives',
    () async {
      final personal = EewHistoryStore(preferenceKey: prefix);
      final public = EewHistoryStore(preferenceKey: '${prefix}_public');
      final original = fixtureGroup();
      await personal.save(prefs, [original]);
      await public.save(prefs, [original]);
      final publicSaved = (await public.restoreForStartup(prefs)).single;
      await personal.restoreForStartup(prefs);
      await personal.save(prefs, []);
      final loaded = await public.loadStationFrames(publicSaved);
      expect(
        loaded.stationFrames.single.toMap(),
        original.stationFrames.single.toMap(),
      );
      expect(await worker.getAll(), isEmpty);
    },
  );

  test(
    'startup leaves archives unopened; replay loads unchanged observations',
    () async {
      final original = fixtureGroup();
      final store = EewHistoryStore(preferenceKey: prefix);
      await store.save(prefs, [original]);
      final cold = EewHistoryStore(preferenceKey: prefix);
      final groups = await cold.restoreForStartup(prefs);
      expect(groups.single.stationFrames, isEmpty);
      expect(groups.single.hasStationHistory, isTrue);
      expect(groups.single.storedStations!.frameKeys, hasLength(1));
      final files = Directory(
        '${directory.path}/eew_history',
      ).listSync().whereType<File>().toList();
      final times = {
        for (final file in files) file.path: file.lastModifiedSync(),
      };
      await cold.save(prefs, groups);
      for (final file in files) {
        expect(file.lastModifiedSync(), times[file.path]);
      }
      final loaded = await cold.loadStationFrames(groups.single);
      expect(
        loaded.stationFrames.map((f) => f.toMap()),
        original.stationFrames.map((f) => f.toMap()),
      );
      expect(loaded.storedStations, isNull);
      expect(groups.single.stationFrames, isEmpty);
      expect(
        () => HistoryReplayPackage.fromGroup(groups.single).encode(),
        throwsStateError,
      );
    },
  );

  test(
    'captured frames are released after save and old references survive later reports',
    () async {
      final store = EewHistoryStore(preferenceKey: prefix);
      final original = fixtureGroup();
      await store.save(prefs, [original]);
      final released = store.releaseSavedFrames(original);
      expect(released.stationFrames, isEmpty);
      expect(released.hasStationHistory, isTrue);
      final withReport = released.addReport(original.latest);
      expect(withReport.storedStations, same(released.storedStations));
      await store.save(prefs, [withReport]);
      final loaded = await store.loadStationFrames(withReport);
      expect(
        loaded.stationFrames.single.toMap(),
        original.stationFrames.single.toMap(),
      );
      await store.save(prefs, []);
      expect(await store.restoreForStartup(prefs), isEmpty);
      expect(
        await worker.readHistory(released.storedStations!.archiveKeys.single),
        isNull,
      );
    },
  );

  test('old standalone frames survive addition of new archived frames', () async {
    final store = EewHistoryStore(preferenceKey: prefix);
    final original = fixtureGroup();
    final frame = original.stationFrames.single;
    final key =
        '${prefix}_station_${frame.kind}_${frame.receivedAt.microsecondsSinceEpoch}';
    await worker.writeHistory(key, jsonEncode(frame.toMap()));
    await worker.writeHistory(
      store.recordKey(original),
      jsonEncode({
        ...original.toMap(includeStationFrames: false),
        'stationFrameKeys': [key],
      }),
    );
    await worker.writeHistory(store.indexKey, [store.recordKey(original)]);
    final restored = (await store.restoreForStartup(prefs)).single;
    final next = StationHistoryFrame(
      receivedAt: frame.receivedAt.add(const Duration(seconds: 1)),
      snapshot: frame.snapshot,
      originalJson: frame.originalJson,
    );
    final updated = restored.copyWith(stationFrames: [next]);
    await store.save(prefs, [updated]);
    final restart = EewHistoryStore(preferenceKey: prefix);
    final saved = (await restart.restoreForStartup(prefs)).single;
    final loaded = await restart.loadStationFrames(saved);
    expect(loaded.stationFrames.map((f) => f.toMap()), [
      frame.toMap(),
      next.toMap(),
    ]);
  });

  test(
    'missing archive is reported on demand, not discarded during startup',
    () async {
      final original = fixtureGroup();
      final store = EewHistoryStore(preferenceKey: prefix);
      await store.save(prefs, [original]);
      final key = store
          .releaseSavedFrames(original)
          .storedStations!
          .archiveKeys
          .single;
      await worker.removeHistory(key);
      final groups = await store.restoreForStartup(prefs);
      expect(groups, hasLength(1));
      await expectLater(
        store.loadStationFrames(groups.single),
        throwsFormatException,
      );
    },
  );

  test('single saved event can be played with timeline enabled', () async {
    final original = fixtureGroup();
    final store = EewHistoryStore(preferenceKey: prefix);
    await store.save(prefs, [original]);
    final stored = (await store.restoreForStartup(prefs)).single;
    final controller = HistoryReplayController(
      onReport: (_) {},
      onClear: (_) {},
      historyGroups: () => [stored],
      loadHistoryGroup: store.loadStationFrames,
    );
    controller.restoreTimelineLinked(true);
    controller.load(
      HistoryReplayPackage.fromGroup(stored),
      remember: false,
      storedGroup: stored,
    );
    await controller.playPrepared();
    expect(controller.active, isTrue);
    expect(controller.totalStationFrames, 1);
    controller.stop();
    expect(controller.package!.stationFrames, isEmpty);
    expect(controller.package!.storedStations, isNotNull);
    controller.restoreTimelineLinked(false);
    await controller.playPrepared();
    expect(controller.active, isTrue);
    expect(controller.totalStationFrames, 1);
    controller.stop();
    controller.dispose();
  });

  test(
    'linked replay loads only overlapping CWA and CEA, not unrelated history',
    () async {
      final store = EewHistoryStore(preferenceKey: prefix);
      final cwa = fixtureGroup();
      final cea = timeline.saved(timeline.captured('cea_202609290220'));
      final unrelated = recorded.group([recorded.recordedEew()]);
      await store.save(prefs, [cwa, cea, unrelated]);
      final groups = await store.restoreForStartup(prefs);
      final loaded = <String>[];
      final controller = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) {},
        historyGroups: () => groups,
        loadHistoryGroup: (group) {
          loaded.add(group.eventId);
          return store.loadStationFrames(group);
        },
      );
      controller.restoreTimelineLinked(true);
      controller.load(
        HistoryReplayPackage.fromGroup(
          await store.loadStationFrames(groups.first),
        ),
        remember: false,
      );
      await controller.playPrepared();
      expect(loaded, [cea.eventId]);
      expect(controller.linkedEventCount, 2);
      expect(controller.totalReports, 5);
      controller.stop();
      controller.dispose();
    },
  );

  test(
    'stop cancels an in-flight linked archive load without starting playback',
    () async {
      final cwa = timeline.captured('cwa_1150074');
      final cea = timeline.saved(timeline.captured('cea_202609290220'));
      final loading = Completer<EewEventGroup>();
      final controller = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) {},
        historyGroups: () => [cea],
        loadHistoryGroup: (_) => loading.future,
      );
      controller.restoreTimelineLinked(true);
      controller.load(cwa, remember: false);
      final playing = controller.playPrepared();
      expect(controller.preparing, isTrue);
      controller.stop();
      loading.complete(cea);
      await playing;
      expect(controller.active, isFalse);
      expect(controller.preparing, isFalse);
      controller.dispose();
    },
  );

  test(
    'shared station chunks survive deleting only one referencing event',
    () async {
      final store = EewHistoryStore(preferenceKey: prefix);
      final cwa = fixtureGroup();
      final cea = timeline
          .saved(timeline.captured('cea_202609290220'))
          .copyWith(stationFrames: cwa.stationFrames);
      await store.save(prefs, [cwa, cea]);
      final groups = await store.restoreForStartup(prefs);
      expect(
        groups.first.storedStations!.archiveKeys,
        groups.last.storedStations!.archiveKeys,
      );
      await store.save(prefs, [groups.last]);
      final loaded = await store.loadStationFrames(groups.last);
      expect(
        loaded.stationFrames.single.toMap(),
        cwa.stationFrames.single.toMap(),
      );
    },
  );
}
