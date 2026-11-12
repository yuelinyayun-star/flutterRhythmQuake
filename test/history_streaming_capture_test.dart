import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/history_replay_directory_io.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/foreground_station_bridge_coalescer.dart';
import 'package:flutterrhythmquake/services/history_storage_io.dart';
import 'package:flutterrhythmquake/services/native_replay_history_files_io.dart';
import 'package:flutterrhythmquake/services/replay_history_files.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'windows_history_storage_test.dart' as fixture;

class _SlowManifest extends DirectoryHistoryStorage {
  _SlowManifest(super.root);
  Completer<void>? entered, release;
  Completer<void>? flushEntered, flushRelease;
  @override
  Future<void> flushPending() async {
    final gate = flushRelease;
    if (gate != null) {
      flushRelease = null;
      flushEntered?.complete();
      await gate.future;
    }
    await super.flushPending();
  }

  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) async {
    entered?.complete();
    entered = null;
    await release?.future;
    return super.writeWithSnapshot(key, value, snapshot);
  }
}

Future<List<Map<String, dynamic>>> _recordBridgeScenario({
  required String name,
  required int? backgroundAt,
  required String root,
}) async {
  final previous = SharedPreferencesStorePlatform.instance;
  final worker = await WindowsPreferencesWorker.start('$root/bridge-$name');
  SharedPreferencesStorePlatform.instance = worker;
  final soundWasEnabled = SoundEffectService().enabled;
  final ttsWasEnabled = TtsService().enabled;
  SoundEffectService().enabled = false;
  TtsService().enabled = false;
  final input = fixture.fixtureGroup();
  final capture = StationHistoryCapture.instance;
  capture.setEnabled('nied', true);
  final frames = [
    for (var i = 0; i < 4; i++)
      StationHistoryFrame(
        receivedAt: input.stationFrames.single.receivedAt.add(
          Duration(seconds: i + 1),
        ),
        snapshot: {...input.stationFrames.single.snapshot, 'sequence': i},
        originalJson: input.stationFrames.single.originalJson,
      ),
  ];
  late final ForegroundStationBridgeCoalescer coalescer;
  coalescer = ForegroundStationBridgeCoalescer(
    paused: backgroundAt == 0,
    window: const Duration(days: 1),
    emit: (payload) {
      final frame = StationHistoryFrame.fromMap(payload['frame'] as Map);
      capture.publish(
        frame.kind,
        () => frame.snapshot,
        originalJson: frame.originalJson,
        receivedAt: frame.receivedAt,
      );
    },
  );
  final provider = QuakeProvider(
    startCatalogServices: false,
    eewClock: () => QuakeTime.unifiedInstantUtc(
      input.latest,
      value: input.latest.reportTime,
    ),
  );
  try {
    await provider.eewHistoryReadyForTest;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    // Production sendUnifiedEvent sets this before forwarding a real-time EEW.
    coalescer.setRecording(true);
    for (final report in input.reports) {
      provider.handleUnifiedEventForTest(report, suppressEffects: true);
    }
    for (var i = 0; i < frames.length; i++) {
      if (backgroundAt == i && i != 0) coalescer.setPaused(true);
      coalescer.submit({
        'kind': frames[i].kind,
        'source': 'real-history-fixture',
        'frame': frames[i].toMap(),
      });
    }
    final loaded = await provider.loadHistoryStationFrames(
      provider.eewHistory.single,
    );
    return [
      for (final entry in StationReplayFrames.describe(loaded.stationFrames))
        (await entry.loadAsync()).toMap(),
    ];
  } finally {
    coalescer.dispose();
    provider.dispose();
    capture.clearLatest('nied');
    await provider.eewHistoryIdleForTest;
    await Future<void>.delayed(Duration.zero);
    SharedPreferencesStorePlatform.instance = previous;
    await worker.close();
    SoundEffectService().enabled = soundWasEnabled;
    TtsService().enabled = ttsWasEnabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late SharedPreferences prefs;
  late DirectoryHistoryStorage storage;
  late EewHistoryStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    temporary = await Directory.systemTemp.createTemp('rq-stream-history-');
    storage = DirectoryHistoryStorage('${temporary.path}/history');
    store = EewHistoryStore(
      preferenceKey: 'unified_eew_history',
      storage: storage,
    );
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  test(
    'receipt releases originals before any manifest save and reads them exactly',
    () async {
      final input = fixture.fixtureGroup();
      var group = store.acceptReports(input.copyWith(stationFrames: const []));
      for (final frame in input.stationFrames) {
        group = store.acceptFrame(group, frame);
      }
      expect(group.stationFrames, isEmpty);
      expect(group.reports.every((r) => r.sourcePayload == null), isTrue);
      expect(group.savedReportCount, input.savedReportCount);
      // No save() / timer / all-history commit has happened yet.
      await store.flushFiles();
      final files = ReplayHistoryFiles('${temporary.path}/history');
      expect(
        await File(files.recordPath(store.recordKey(group))).exists(),
        isFalse,
      );
      expect(
        await File(
          group.storedReports!.payloads.values.first.filePath!,
        ).exists(),
        isTrue,
      );
      final loaded = await store.loadStationFrames(group);
      expect(
        (await StationReplayFrames.describe(
          loaded.stationFrames,
        ).single.loadAsync()).toMap(),
        input.stationFrames.single.toMap(),
      );
      expect(
        (await store.loadReports(group)).reports.map((r) => r.toMap()),
        input.reports.map((r) => r.toMap()),
      );
      await store.save(prefs, [group]);
      final cold = EewHistoryStore(
        preferenceKey: 'unified_eew_history',
        storage: DirectoryHistoryStorage('${temporary.path}/history'),
      );
      try {
        final restored = (await cold.restoreForStartup(
          prefs,
          lazyReports: true,
        )).single;
        expect(restored.stationFrames, isEmpty);
        expect(
          restored.storedStations!.frameKeys,
          group.storedStations!.frameKeys,
        );
        final package = HistoryReplayPackage.fromGroup(
          await cold.loadStationFrames(restored),
        );
        await exportReplayDirectory(package, '${temporary.path}/roundtrip.zip');
        final imported = await importReplayFile(
          '${temporary.path}/roundtrip.zip',
        );
        try {
          final original =
              await imported.storedReports!.payloads.values.first.load!();
          expect(original.toMap(), input.reports.first.toMap());
          expect(
            (await StationReplayFrames.describe(
              imported.stationFrames,
            ).single.loadAsync()).toMap(),
            input.stationFrames.single.toMap(),
          );
        } finally {
          await imported.releaseFiles?.call();
        }
      } finally {
        await cold.close();
      }
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'shared frames write once and one event deletion preserves the other',
    () async {
      final input = fixture.fixtureGroup();
      var one = store.acceptReports(input.copyWith(stationFrames: const []));
      var two = store.acceptReports(
        input.copyWith(
          eventId: 'storage-sharing-test',
          stationFrames: const [],
        ),
      );
      final frame = input.stationFrames.single;
      one = store.acceptFrame(one, frame);
      two = store.acceptFrame(two, frame);
      one = store.acceptFrame(one, frame);
      expect(one.storedStations!.frameKeys, hasLength(1));
      expect(two.storedStations!.frameKeys, one.storedStations!.frameKeys);
      await store.flushFiles();
      expect(
        await Directory('${temporary.path}/history/frames').list().length,
        1,
      );
      await store.save(prefs, [one, two]);
      await store.save(prefs, [two]);
      expect(
        await File(
          storage.framePath(two.storedStations!.frameKeys.single),
        ).exists(),
        isTrue,
      );
      expect(one.stationFrames, isEmpty);
      expect(two.stationFrames, isEmpty);
    },
  );

  test(
    'new report arriving during slow manifest commit remains a file reference',
    () async {
      await store.close();
      final slow = _SlowManifest('${temporary.path}/history');
      store = EewHistoryStore(
        preferenceKey: 'unified_eew_history',
        storage: slow,
      );
      final input = fixture.fixtureGroup();
      var group = store.acceptReports(
        input.copyWith(reports: [input.reports.last], stationFrames: const []),
      );
      slow.entered = Completer<void>();
      final entered = slow.entered!.future;
      slow.release = Completer<void>();
      final save = store.save(prefs, [group]);
      await entered;
      group = store.acceptReports(group.addReport(input.reports.first));
      group = store.acceptFrame(group, input.stationFrames.single);
      expect(group.stationFrames, isEmpty);
      expect(group.reports.every((r) => r.sourcePayload == null), isTrue);
      slow.release!.complete();
      await save;
      group = store.releaseSavedFrames(group, deferReports: true);
      expect(group.storedStations!.frameKeys, hasLength(1));
      await store.save(prefs, [group]);
      expect(
        (await store.loadReports(group)).reports.map((r) => r.toMap()),
        group.reports.map(
          (r) => input.reports
              .singleWhere(
                (v) => historyReportSignature(v) == historyReportSignature(r),
              )
              .toMap(),
        ),
      );
    },
  );

  test(
    'an event received while an older save drains IO is not removed by retention',
    () async {
      await store.close();
      final slow = _SlowManifest('${temporary.path}/history');
      store = EewHistoryStore(
        preferenceKey: 'unified_eew_history',
        storage: slow,
      );
      slow.flushEntered = Completer<void>();
      final blocked = slow.flushEntered!.future;
      final release = Completer<void>();
      slow.flushRelease = release;
      final olderSave = store.save(prefs, []);
      await blocked;
      final input = fixture.fixtureGroup();
      var group = store.acceptReports(input.copyWith(stationFrames: const []));
      group = store.acceptFrame(group, input.stationFrames.single);
      release.complete();
      await olderSave;
      await store.flushFiles();
      expect(
        await File(
          storage.framePath(group.storedStations!.frameKeys.single),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          group.storedReports!.payloads.values.first.filePath!,
        ).exists(),
        isTrue,
      );
      await store.save(prefs, [group]);
      expect(
        (await store.loadReports(group)).latest.toMap(),
        input.latest.toMap(),
      );
    },
  );

  test(
    'native writer failures are visible, retain the item and can retry',
    () async {
      if (!NativeReplayHistoryFiles.supported) return;
      final input = fixture.fixtureGroup();
      final frame = input.stationFrames.single;
      final key =
          'unified_eew_history_station_${frame.kind}_${frame.receivedAt.microsecondsSinceEpoch}';
      final obstruction = Directory('${storage.framePath(key)}.pending');
      await obstruction.create(recursive: true);
      final group = store.acceptFrame(
        input.copyWith(stationFrames: const []),
        frame,
      );
      await expectLater(store.flushFiles(), throwsStateError);
      expect(group.stationFrames, isEmpty);
      await obstruction.delete();
      storage.retryPending();
      await store.flushFiles();
      final bytes = await File(storage.framePath(key)).readAsBytes();
      expect(jsonDecode(utf8.decode(gzip.decode(bytes))), frame.toMap());
    },
  );

  test(
    'actual provider receipt keeps active originals and history file references',
    () async {
      final previous = SharedPreferencesStorePlatform.instance;
      final worker = await WindowsPreferencesWorker.start(
        '${temporary.path}/provider',
      );
      SharedPreferencesStorePlatform.instance = worker;
      SoundEffectService().enabled = false;
      TtsService().enabled = false;
      final input = fixture.fixtureGroup();
      final capture = StationHistoryCapture.instance;
      final provider = QuakeProvider(
        startCatalogServices: false,
        eewClock: () => QuakeTime.unifiedInstantUtc(
          input.latest,
          value: input.latest.reportTime,
        ),
      );
      try {
        await provider.eewHistoryReadyForTest;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        for (final report in input.reports) {
          provider.handleUnifiedEventForTest(report, suppressEffects: true);
        }
        final frame = input.stationFrames.single;
        capture.publish(
          frame.kind,
          () => frame.snapshot,
          originalJson: frame.originalJson,
          receivedAt: frame.receivedAt,
        );
        expect(
          provider.unifiedEvents.single.sourcePayload,
          input.reports.last.sourcePayload,
        );
        expect(
          provider.eewHistory.single.reports.every(
            (r) => r.sourcePayload == null,
          ),
          isTrue,
        );
        expect(provider.eewHistory.single.stationFrames, isEmpty);
        expect(
          provider.eewHistory.single.storedStations!.frameKeys,
          hasLength(1),
        );
        final loaded = await provider.loadHistoryStationFrames(
          provider.eewHistory.single,
        );
        expect(
          (await StationReplayFrames.describe(
            loaded.stationFrames,
          ).single.loadAsync()).toMap(),
          frame.toMap(),
        );
        expect(
          (await provider.loadHistoryReports(
            provider.eewHistory.single,
          )).latest.sourcePayload,
          input.reports.last.sourcePayload,
        );
        expect(
          QuakeProvider.runtimePerformanceSnapshot['pendingHistoryWrites'],
          lessThanOrEqualTo(1),
        );
      } finally {
        provider.dispose();
        capture.clearLatest(input.stationFrames.single.kind);
        // dispose has an asynchronous final index commit, then closes its owner.
        await provider.eewHistoryIdleForTest;
        await Future<void>.delayed(Duration.zero);
        SharedPreferencesStorePlatform.instance = previous;
        await worker.close();
        SoundEffectService().enabled = true;
        TtsService().enabled = true;
      }
    },
  );

  test(
    'real EEW frames survive foreground and both background transitions',
    () async {
      final foreground = await _recordBridgeScenario(
        name: 'foreground',
        backgroundAt: null,
        root: temporary.path,
      );
      final backgroundBefore = await _recordBridgeScenario(
        name: 'background-before',
        backgroundAt: 0,
        root: temporary.path,
      );
      final backgroundDuring = await _recordBridgeScenario(
        name: 'background-during',
        backgroundAt: 2,
        root: temporary.path,
      );
      expect(foreground, hasLength(4));
      expect(backgroundBefore, foreground);
      expect(backgroundDuring, foreground);
      expect(
        foreground.map((frame) => frame['receivedAt']).toList(),
        List.of(
          foreground.map((frame) => frame['receivedAt']),
        ).toSet().toList(),
      );
    },
  );

  final sourceDirectory = Platform.environment['RQ_STREAM_ORIGINAL_FRAMES'];
  test(
    'all retained original frames stay file-backed through sustained capture',
    () async {
      final input = fixture.fixtureGroup();
      var group = store.acceptReports(input.copyWith(stationFrames: const []));
      final samples = <Map<String, dynamic>>[];
      var count = 0;
      final watch = Stopwatch()..start();
      final acceptMicros = <int>[];
      final sourceHashes = <String, String>{};
      await for (final entity in Directory(
        sourceDirectory!,
      ).list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json.gz')) continue;
        final raw = gzip.decode(await entity.readAsBytes());
        final frame = StationHistoryFrame.fromMap(
          jsonDecode(utf8.decode(raw)) as Map,
        );
        final acceptWatch = Stopwatch()..start();
        group = store.acceptFrame(group, frame);
        acceptMicros.add(acceptWatch.elapsedMicroseconds);
        // Keep only hashes for the subsequent complete round-trip comparison.
        sourceHashes[group.storedStations!.frameKeys.last] = sha256
            .convert(JsonUtf8Encoder().convert(frame.toMap()))
            .toString();
        count++;
        expect(group.stationFrames, isEmpty);
        if (count % 500 == 0) {
          await store.flushFiles();
          samples.add({
            'frames': count,
            'rss': ProcessInfo.currentRss,
            'writer': store.pendingFileWrites,
          });
        }
      }
      await store.save(prefs, [group]);
      final writeMs = watch.elapsedMilliseconds;
      final loaded = await store.loadStationFrames(group);
      for (final entry in StationReplayFrames.describe(loaded.stationFrames)) {
        expect(
          sha256
              .convert(
                JsonUtf8Encoder().convert((await entry.loadAsync()).toMap()),
              )
              .toString(),
          sourceHashes[entry.identity],
        );
      }
      final output = {
        'frames': count,
        'residentHistoryFrames': group.stationFrames.length,
        'elapsedMs': watch.elapsedMilliseconds,
        'writeMs': writeMs,
        'readAndVerifyMs': watch.elapsedMilliseconds - writeMs,
        'acceptLatencyUs': () {
          acceptMicros.sort();
          return {
            'median': acceptMicros[acceptMicros.length ~/ 2],
            'p95': acceptMicros[(acceptMicros.length * 0.95).floor()],
            'max': acceptMicros.last,
          };
        }(),
        'rss': ProcessInfo.currentRss,
        'writer': store.pendingFileWrites,
        'samples': samples,
      };
      File(
        'tmp/replay_stream_original_frames_20261110.json',
      ).writeAsStringSync(jsonEncode(output), encoding: utf8);
      expect(count, greaterThan(3500));
      expect(store.pendingFileWrites['pending'], 0);
    },
    skip: sourceDirectory == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
