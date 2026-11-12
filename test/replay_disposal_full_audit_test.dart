// Disposal regressions from the original audit: unmodified observations and
// controlled resource boundaries. Baseline defect results are kept separately.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutterrhythmquake/core/event_detection/native_station_trigger_detector.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_scorer.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_observation_history.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/replay_source_estimation.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/sources/native_ka_detector.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'tmp/replay_disposal_fix_20261102/after';
final _replay = ReplaySourceEstimation.instance;
final _hashes = <String, String>{};
final _results = <Map<String, Object?>>[];
final _captures = <String, (EewEventGroup, StationHistoryFrame)>{};
late StationHistoryFrame _secondPAlert;
late StationHistoryFrame _laterPAlert;

Map<String, int> resources() => {
  'palertWorkers': NativeStationRuntime.workers,
  'triggerSessions':
      NativeStationTriggerDetector.globalDiagnostics['triggerSessions']!,
  'kaSessions': NativeKaDetector.diagnostics['kaDetectorSessions']!,
  'observationSessions': NativeObservationHistory.diagnostics['sessions']!,
  'hypSessions': NativeHypScorer.sessions,
};

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Resource audit timed out: ${resources()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Map<String, dynamic> original(String path) {
  final bytes = File(path).readAsBytesSync();
  _hashes[path] = sha256.convert(bytes).toString();
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

void record(String name, Map<String, Object?> details) {
  final row = <String, Object?>{'case': name, ...details};
  _results.add(row);
  debugPrint('REPLAY_LIFECYCLE ${jsonEncode(row)}');
}

HistoryReplayController controller(
  String kind, {
  bool frames = false,
  DateTime Function()? now,
}) {
  final (group, frame) = _captures[kind]!;
  final package = HistoryReplayPackage.fromGroup(
    EewEventGroup(
      eventId: group.eventId,
      reports: group.reports,
      firstArrivedAt: group.firstArrivedAt,
      captureEndedAt: group.captureEndedAt,
      stationFrames: frames ? [frame] : const [],
    ),
  );
  return HistoryReplayController(onReport: (_) {}, onClear: (_) {}, now: now)
    ..load(package);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    expect(
      NativeStationRuntime.supported,
      isTrue,
      reason: 'Actual DLL is required',
    );
    Directory(_out).createSync(recursive: true);
    const palRoot = 'test/fixtures/palert_cwa_1150077_20261017';
    final palGroup = EewEventGroup.fromMap(
      jsonDecode(original('$palRoot/cwa_1150077.original.json')['value']),
    );
    final manifest =
        jsonDecode(File('$palRoot/manifest.json').readAsStringSync()) as List;
    final palFrames = <StationHistoryFrame>[];
    for (final entry in manifest) {
      final doc = original('$palRoot/${entry['file']}');
      palFrames.addAll(
        StationJsonArchive.decode(StationArchiveStorage.decode(doc['value'])),
      );
    }
    palFrames.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    _captures['palert'] = (palGroup, palFrames.first);
    _secondPAlert = palFrames[1];
    _laterPAlert = palFrames.firstWhere(
      (frame) => frame.receivedAt.isAfter(palGroup.firstArrivedAt.toUtc()),
    );
    const niedRoot = 'D:/flutterApp/flutter-nied-regression/20261013-200318';
    final niedSaved =
        jsonDecode(
              original(
                '$niedRoot/eew/1cc3760b8dd1caeb6c2461e91eac3a944e0522d432132ab071f3ee2c28777fb6.json',
              )['value'],
            )
            as Map;
    final niedGroup = EewEventGroup.fromMap(niedSaved);
    final niedKeys = (niedSaved['stationArchiveKeys'] as List).toSet();
    final niedFrames = <StationHistoryFrame>[];
    final files =
        Directory(
            '$niedRoot/station-history',
          ).listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final doc = jsonDecode(file.readAsStringSync()) as Map;
      if (!'${doc['key']}'.contains('station_archive_nied_')) continue;
      if (!niedKeys.contains(
        (doc['key'] as String).replaceFirst('flutter.', ''),
      )) {
        continue;
      }
      final frames = StationJsonArchive.decode(
        StationArchiveStorage.decode(original(file.path)['value']),
      );
      niedFrames.addAll(frames);
    }
    niedFrames.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    expect(niedFrames, isNotEmpty);
    _captures['nied'] = (niedGroup, niedFrames.first);
    for (final entry in _captures.entries) {
      record('${entry.key}-capture', {
        'firstReport': HistoryReplayPackage.fromGroup(
          entry.value.$1,
        ).times.first.toIso8601String(),
        'firstFrame': entry.value.$2.receivedAt.toIso8601String(),
      });
    }
    expect(_captures.keys, containsAll(['nied', 'palert']));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    _replay.stop();
    await until(() => resources().values.every((v) => v == 0));
  });
  tearDown(() async {
    _replay.stop();
    await until(() => resources().values.every((v) => v == 0));
    SoundEffectService().enabled = true;
  });
  tearDownAll(() {
    expect(_results, isNotEmpty);
    for (final entry in _hashes.entries) {
      expect(
        sha256.convert(File(entry.key).readAsBytesSync()).toString(),
        entry.value,
        reason: entry.key,
      );
    }
    File('$_out/results.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'cases': _results,
        'originalHashes': _hashes,
        'finalResources': resources(),
      }),
    );
  });

  test('idle controller dispose does not create inference session', () {
    final c = controller('palert');
    c.dispose();
    expect(_replay.session, isNull);
    expect(resources().values.every((v) => v == 0), isTrue);
    record('idle-dispose', {'resources': resources()});
  });

  test(
    'dispose cancels the station-publish timer without late publication',
    () async {
      final clock = FakeAsync();
      late HistoryReplayController c;
      var before = 0, after = 0;
      clock.run((_) {
        final (group, first) = _captures['palert']!;
        final gate = Completer<StationHistoryFrame>();
        final later = _laterPAlert;
        final frames = StationReplayFrames([
          StationReplayEntry.file(
            first.receivedAt,
            first.kind,
            'original-slow',
            filePath: null,
            load: () => gate.future,
          ),
          StationReplayEntry.file(
            later.receivedAt,
            later.kind,
            'original-following',
            filePath: null,
            load: () async => later,
          ),
        ]);
        final package = HistoryReplayPackage.fromGroup(
          EewEventGroup(
            eventId: group.eventId,
            reports: group.reports,
            firstArrivedAt: group.firstArrivedAt,
            captureEndedAt: group.captureEndedAt,
            stationFrames: frames,
          ),
        );
        c = HistoryReplayController(
          onReport: (_) {},
          onClear: (_) {},
          now: clock.getClock(DateTime.utc(2026, 11, 1)).now,
        )..load(package);
        c.play();
        // Simulate a slow original-file read, then catch up without changing
        // any source timestamp. The next file is already due on this clock.
        clock.elapse(
          later.receivedAt.difference(package.times.first) +
              const Duration(milliseconds: 100),
        );
        gate.complete(first);
        clock.flushMicrotasks();
        clock.elapse(Duration.zero);
        clock.flushMicrotasks();
        before = clock.nonPeriodicTimerCount;
        c.dispose();
        after = clock.nonPeriodicTimerCount;
        expect(before, greaterThan(after));
        expect(
          after,
          0,
          reason: 'Disposal must cancel pending station UI publication',
        );
        _replay.stop();
        expect(
          () => clock.elapse(const Duration(milliseconds: 100)),
          returnsNormally,
        );
        expect(clock.nonPeriodicTimerCount, 0);
        clock.flushMicrotasks();
      });
      await until(() => resources().values.every((v) => v == 0));
      record('dispose-publish-timer', {
        'timersBefore': before,
        'timersAfterDispose': after,
        'timersAfter100ms': clock.nonPeriodicTimerCount,
        'latePublicationError': false,
        'resources': resources(),
      });
    },
  );

  for (final kind in ['palert', 'nied']) {
    test(
      '$kind natural completion stops the original inference session',
      () async {
        final clock = FakeAsync();
        late HistoryReplayController c;
        clock.run((_) {
          c = controller(
            kind,
            now: clock.getClock(DateTime.utc(2026, 11, 1)).now,
          );
          c.play();
        });
        clock.flushMicrotasks();
        try {
          var finished = false;
          final work = _replay.process(_captures[kind]!.$2)
            ..whenComplete(() => finished = true);
          await until(() {
            clock.flushMicrotasks();
            return finished;
          });
          await work;
          expect(resources().values.any((v) => v > 0), isTrue);
          clock.elapse(
            c.package!.playbackDuration + const Duration(seconds: 1),
          );
          clock.flushMicrotasks();
          expect(c.active, isFalse);
          expect(_replay.session, isNull);
          await until(() => resources().values.every((v) => v == 0));
          record('$kind-natural-end', {'resources': resources()});
        } finally {
          c.dispose();
        }
      },
    );
  }

  testWidgets('closing only the replay controls preserves playback by design', (
    tester,
  ) async {
    // UI dismissal owns neither controller nor inference. Actual worker
    // ownership is checked separately through the production controller.
    final c = controller('palert');
    c.play();
    try {
      final session = _replay.session;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HistoryReplayControls(controller: c)),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      expect(c.active, isTrue);
      expect(_replay.session, session);
      expect(NativeStationRuntime.workers, 0);
      record('close-controls-only', {
        'controllerActive': c.active,
        'sessionRetained': _replay.session == session,
        'resources': resources(),
      });
      c.stop();
      await tester.runAsync(
        () => until(() => resources().values.every((v) => v == 0)),
      );
    } finally {
      c.dispose();
    }
  });

  for (final kind in ['palert', 'nied']) {
    for (final action in ['stop', 'dispose']) {
      test('$kind $action during worker startup', () async {
        final c = controller(kind);
        var disposed = false;
        c.play();
        final pending = _replay.process(_captures[kind]!.$2);
        try {
          if (action == 'stop') {
            c.stop();
          } else {
            c.dispose();
            disposed = true;
          }
          await pending;
          await until(() => resources().values.every((v) => v == 0));
          expect(_replay.session, isNull);
          expect(_replay.processedFrames, 0);
          record('$kind-startup-$action', {
            'resources': resources(),
            'processedFrames': _replay.processedFrames,
            'sessionRetained': _replay.session != null,
          });
        } finally {
          if (!disposed) c.dispose();
        }
      });
    }
  }

  test(
    'a real controller station-read error stops its already-started worker',
    () async {
      final (group, first) = _captures['palert']!;
      final second = _secondPAlert;
      final gate = Completer<StationHistoryFrame>();
      var entered = false;
      final frames = StationReplayFrames([
        StationReplayEntry.file(
          first.receivedAt,
          first.kind,
          'original-first',
          filePath: null,
          load: () async => first,
        ),
        StationReplayEntry.file(
          second.receivedAt,
          second.kind,
          'original-second',
          filePath: null,
          load: () {
            entered = true;
            return gate.future;
          },
        ),
      ]);
      final package = HistoryReplayPackage.fromGroup(
        EewEventGroup(
          eventId: group.eventId,
          reports: group.reports,
          firstArrivedAt: group.firstArrivedAt,
          captureEndedAt: group.captureEndedAt,
          stationFrames: frames,
        ),
      );
      final c = HistoryReplayController(onReport: (_) {}, onClear: (_) {})
        ..load(package);
      try {
        c.play();
        await until(() => _replay.processedFrames == 1 && entered);
        expect(NativeStationRuntime.workers, 1);
        gate.completeError(const FileSystemException('controlled read error'));
        await until(() => !c.active && resources().values.every((v) => v == 0));
        expect(c.playbackError, contains('controlled read error'));
        expect(_replay.session, isNull);
        record('controller-station-read-error', {
          'playbackError': c.playbackError,
          'resources': resources(),
        });
      } finally {
        c.dispose();
        if (!gate.isCompleted) gate.complete(second);
      }
    },
  );

  for (final kind in ['palert', 'nied']) {
    for (final action in ['stop', 'dispose']) {
      test(
        '$kind original frame through controller; $action resource ownership',
        () async {
          final c = controller(kind, frames: true);
          var disposed = false;
          try {
            c.play();
            await until(() => _replay.processedFrames >= 1);
            expect(_replay.error, isNull);
            final before = resources();
            expect(before.values.any((v) => v > 0), isTrue);
            final session = _replay.session;
            if (action == 'stop') {
              c.stop();
              await until(() => resources().values.every((v) => v == 0));
              expect(_replay.session, isNull);
            } else {
              c.dispose();
              disposed = true;
              await until(() => resources().values.every((v) => v == 0));
              expect(_replay.session, isNull);
            }
            record('$kind-controller-$action', {
              'before': before,
              'after': resources(),
              'sessionRetained': _replay.session == session,
              'processedFrames': _replay.processedFrames,
            });
          } finally {
            if (!disposed) c.dispose();
          }
        },
      );
    }
  }

  for (final action in ['stop', 'dispose']) {
    test(
      '$action while original station read is blocked and other frames are queued',
      () async {
        final c = controller('palert');
        final gate = Completer<StationHistoryFrame>();
        final frame = _captures['palert']!.$2;
        var loads = 0;
        var disposed = false;
        c.play();
        try {
          final current = _replay.processEntry(
            StationReplayEntry.file(
              frame.receivedAt,
              frame.kind,
              'controlled-read-gate',
              filePath: null,
              load: () {
                loads++;
                return gate.future;
              },
            ),
          );
          final pending = [
            for (var i = 0; i < 3; i++)
              _replay.processEntry(
                StationReplayEntry(
                  frame.receivedAt,
                  frame.kind,
                  'same-original-$i',
                  () {
                    loads++;
                    return frame;
                  },
                ),
              ),
          ];
          expect(_replay.pendingFrames, 3);
          if (action == 'stop') {
            c.stop();
            await Future.wait(pending);
          } else {
            c.dispose();
            disposed = true;
          }
          final queuedAfter = _replay.pendingFrames;
          gate.complete(frame);
          await current;
          await Future.wait(pending);
          expect(loads, 1);
          expect(queuedAfter, 0);
          expect(_replay.processedFrames, 0);
          expect(_replay.session, isNull);
          expect(resources().values.every((v) => v == 0), isTrue);
          record('queued-read-$action', {
            'loads': loads,
            'queuedAfter': queuedAfter,
            'processedAfter': _replay.processedFrames,
            'resources': resources(),
          });
        } finally {
          if (!gate.isCompleted) gate.complete(frame);
          if (!disposed) c.dispose();
        }
      },
    );
  }

  test(
    'dispose during preparation ignores late history load completion',
    () async {
      final (group, _) = _captures['palert']!;
      final loaded = HistoryReplayPackage.fromGroup(group);
      final filePackage = HistoryReplayPackage.files(
        name: loaded.name,
        reports: loaded.reports,
        storedReports: StoredReportHistory(
          recordKey: 'controlled-preparation',
          payloads: {
            for (final r in loaded.reports)
              r: StoredReportPayload(
                signature: historyReportSignature(r),
                isNotEmpty: true,
                load: () async => r,
              ),
          },
        ),
        stationFrames: const [],
        arrivals: loaded.arrivalInstants,
        omittedReports: 0,
      );
      final gate = Completer<EewEventGroup>();
      final c = HistoryReplayController(
        onReport: (_) {
          fail('Late preparation published a report');
        },
        onClear: (_) {},
        loadHistoryGroup: (_) => gate.future,
      )..load(filePackage, storedGroup: group);
      final task = c.playPrepared();
      expect(c.preparing, isTrue);
      c.dispose();
      gate.complete(group);
      await task;
      expect(_replay.session, isNull);
      expect(resources().values.every((v) => v == 0), isTrue);
      record('dispose-preparing', {'resources': resources()});
    },
  );

  test(
    'dispose during original report read discards the late report',
    () async {
      final (group, _) = _captures['palert']!;
      final loaded = HistoryReplayPackage.fromGroup(group);
      final gate = Completer<UnifiedQuakeData>();
      final r = loaded.reports.first;
      final package = HistoryReplayPackage.files(
        name: loaded.name,
        reports: loaded.reports,
        storedReports: StoredReportHistory(
          recordKey: 'controlled-report-read',
          payloads: {
            for (final report in loaded.reports)
              report: StoredReportPayload(
                signature: historyReportSignature(report),
                isNotEmpty: true,
                load: () => gate.future,
              ),
          },
        ),
        stationFrames: const [],
        arrivals: loaded.arrivalInstants,
        omittedReports: 0,
      );
      final seen = <UnifiedQuakeData>[];
      final c = HistoryReplayController(onReport: seen.add, onClear: (_) {})
        ..load(package);
      c.play();
      final session = _replay.session;
      c.dispose();
      gate.complete(r);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen, isEmpty);
      expect(_replay.session, isNull);
      record('dispose-report-read', {
        'reportsPublished': seen.length,
        'sessionRetained': _replay.session == session,
        'resources': resources(),
      });
    },
  );

  test(
    'old controller stop and dispose cannot stop a newer controller session',
    () async {
      final a = controller('palert');
      final b = controller('palert');
      try {
        a.play();
        await _replay.process(_captures['palert']!.$2);
        b.play();
        final owner = _replay.session;
        await _replay.process(_captures['palert']!.$2);
        a.stop();
        expect(_replay.session, owner);
        expect(NativeStationRuntime.workers, 1);
        a.dispose();
        expect(_replay.session, owner);
        record('old-controller-new-owner', {
          'sessionUnchanged': _replay.session == owner,
          'resources': resources(),
        });
        b.stop();
      } finally {
        b.dispose();
      }
    },
  );

  for (final kind in ['palert', 'nied']) {
    test(
      '$kind old active controller disposal preserves the new owner',
      () async {
        final old = controller(kind);
        final current = controller(kind);
        var oldDisposed = false;
        try {
          old.play();
          await _replay.process(_captures[kind]!.$2);
          current.play();
          await _replay.process(_captures[kind]!.$2);
          final session = _replay.session;
          final before = resources();
          expect(session, isNotNull);
          expect(before.values.any((value) => value > 0), isTrue);
          // Do not call old.stop() first: dispose must enforce ownership itself.
          old.dispose();
          oldDisposed = true;
          expect(_replay.session, session);
          expect(current.active, isTrue);
          expect(resources(), before);
          await _replay.process(_captures[kind]!.$2);
          expect(_replay.processedFrames, 2);
          expect(_replay.error, isNull);
          record('$kind-dispose-old-active-owner', {
            'newSessionPreserved': _replay.session == session,
            'resources': resources(),
          });
        } finally {
          if (!oldDisposed) old.dispose();
          current.dispose();
        }
        await until(() => resources().values.every((value) => value == 0));
      },
    );
  }

  test(
    'dispose releases ownership without stop UI or history side effects',
    () async {
      final (group, frame) = _captures['palert']!;
      var clearCalls = 0,
          historyCalls = 0,
          controllerNotices = 0,
          stationNotices = 0;
      final c = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) => clearCalls++,
        historyGroups: () {
          historyCalls++;
          return [group];
        },
      )..load(HistoryReplayPackage.fromGroup(group), storedGroup: group);
      c.play();
      await _replay.process(frame);
      clearCalls = historyCalls = 0;
      c.addListener(() => controllerNotices++);
      c.stationSnapshots.addListener(() => stationNotices++);
      c.dispose();
      await until(() => resources().values.every((value) => value == 0));
      expect(_replay.session, isNull);
      expect(clearCalls, 0);
      expect(historyCalls, 0);
      expect(controllerNotices, 0);
      expect(stationNotices, 0);
      record('dispose-no-stop-ui-side-effects', {
        'onClear': clearCalls,
        'historyReloads': historyCalls,
        'controllerNotices': controllerNotices,
        'stationNotices': stationNotices,
        'resources': resources(),
      });
    },
  );

  test('late old station read cannot overwrite a restarted session', () async {
    final a = controller('palert');
    final b = controller('palert');
    final gate = Completer<StationHistoryFrame>();
    final frame = _captures['palert']!.$2;
    try {
      a.play();
      final old = _replay.processEntry(
        StationReplayEntry.file(
          frame.receivedAt,
          frame.kind,
          'late-old-read',
          filePath: null,
          load: () => gate.future,
        ),
      );
      b.play();
      final session = _replay.session;
      await _replay.process(frame);
      expect(_replay.processedFrames, 1);
      gate.complete(frame);
      await old;
      expect(_replay.session, session);
      expect(_replay.processedFrames, 1);
      expect(_replay.pendingFrames, 0);
      record('restart-late-old-read', {
        'processedFrames': _replay.processedFrames,
        'sessionUnchanged': _replay.session == session,
        'resources': resources(),
      });
      b.stop();
    } finally {
      if (!gate.isCompleted) gate.complete(frame);
      a.dispose();
      b.dispose();
    }
  });

  test(
    'each replay disposal releases workers before the next restart',
    () async {
      for (var i = 0; i < 3; i++) {
        final c = controller('palert');
        c.play();
        await _replay.process(_captures['palert']!.$2);
        c.dispose();
        await until(() => resources().values.every((v) => v == 0));
        expect(_replay.session, isNull);
        expect(NativeStationRuntime.workers, 0);
        record('restart-$i', {'resources': resources()});
      }
    },
  );

  test('production provider dispose releases its replay inference', () async {
    final provider = QuakeProvider(startCatalogServices: false);
    await provider.eewHistoryReadyForTest;
    provider.historyReplay.load(
      HistoryReplayPackage.fromGroup(_captures['palert']!.$1),
    );
    provider.historyReplay.play();
    await _replay.process(_captures['palert']!.$2);
    final session = _replay.session;
    provider.dispose();
    await until(() => resources().values.every((v) => v == 0));
    expect(_replay.session, isNull);
    expect(NativeStationRuntime.workers, 0);
    record('provider-dispose', {
      'sessionRetained': _replay.session == session,
      'resources': resources(),
    });
  });
}
