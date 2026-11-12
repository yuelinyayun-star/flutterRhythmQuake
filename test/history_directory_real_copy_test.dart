import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/history_replay_directory_io.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/history_storage.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'history_lazy_loading_test.dart' show LegacyWorkerHistory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final copy = Platform.environment['RQ_FOLDER_HISTORY_COPY'];
  final mode = Platform.environment['RQ_FOLDER_HISTORY_MODE'] ?? 'folder';
  final converted = Platform.environment['RQ_CONVERTED_REPLAY_COPY'];
  test(
    'converted real copy preserves every report and frame with bounded file reads',
    () async {
      final directory = Directory(converted!).absolute;
      final allowed = Directory('tmp').absolute.path;
      if (!directory.path.startsWith('$allowed${Platform.pathSeparator}')) {
        throw ArgumentError('Only workspace tmp copies are accepted');
      }
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final previous = SharedPreferencesStorePlatform.instance;
      final worker = await WindowsPreferencesWorker.start(directory.path);
      SharedPreferencesStorePlatform.instance = worker;
      try {
        final current = EewHistoryStore(
          preferenceKey: 'unified_eew_history',
          storage: historyStorage(prefs),
        );
        final old = EewHistoryStore(
          preferenceKey: 'unified_eew_history',
          storage: LegacyWorkerHistory(worker),
        );
        final groups = await current.restoreForStartup(
          prefs,
          lazyReports: true,
        );
        final watch = Stopwatch()..start();
        final prepared = [
          for (final group in groups) await current.loadStationFrames(group),
        ];
        final prepareMicros = watch.elapsedMicroseconds;
        var frameCount = 0, reportCount = 0;
        final oldGroups = await old.restoreForStartup(prefs, lazyReports: true);
        for (var i = 0; i < groups.length; i++) {
          final group = groups[i];
          final original = oldGroups.singleWhere(
            (g) =>
                g.eventId == group.eventId &&
                g.latest.source == group.latest.source,
          );
          final originals = await old.loadStationFrames(original);
          final oldEntries = {
            for (final e in StationReplayFrames.describe(
              originals.stationFrames,
            ))
              '${e.kind}_${e.receivedAt.microsecondsSinceEpoch}': e,
          };
          final entries = StationReplayFrames.describe(
            prepared[i].stationFrames,
          ).toList();
          expect(entries.length, oldEntries.length);
          for (final entry in entries) {
            final other =
                oldEntries['${entry.kind}_${entry.receivedAt.microsecondsSinceEpoch}']!;
            final a = (await entry.loadAsync()).toMap();
            final b = (await other.loadAsync()).toMap();
            expect(
              sha256.convert(JsonUtf8Encoder().convert(a)),
              sha256.convert(JsonUtf8Encoder().convert(b)),
              reason:
                  'Exact JSON values and types: ${entry.kind} ${entry.receivedAt}',
            );
            expect(entry.cachedFrame, isNull);
            frameCount++;
          }
          final a = await current.loadReports(group),
              b = await old.loadReports(original);
          expect(
            a.reports.map((r) => r.toMap()),
            b.reports.map((r) => r.toMap()),
          );
          reportCount += a.reports.length;
          if (originals.stationFrames is StationReplayFrames) {
            (originals.stationFrames as StationReplayFrames).release();
          }
        }
        final result = {
          'validatedEvents': groups.length,
          'validatedFrames': frameCount,
          'validatedReports': reportCount,
          'prepareMicroseconds': prepareMicros,
          'assertions': 'all original values and times equal',
        };
        await File(
          '${directory.path}/verified-current.json',
        ).writeAsString(jsonEncode(result), encoding: utf8);
        stdout.writeln(jsonEncode(result));
      } finally {
        SharedPreferencesStorePlatform.instance = previous;
        await worker.close();
      }
    },
    skip: converted == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
  test(
    'unchanged local history copy benchmarks storage preparation and ZIP export',
    () async {
      final source = Directory(copy!).absolute;
      final allowed = Directory('tmp').absolute.path;
      if (!source.path.startsWith('$allowed${Platform.pathSeparator}')) {
        throw ArgumentError('Only workspace tmp copies are accepted');
      }
      final working = Directory(
        '${source.parent.path}/bench_${mode}_${DateTime.now().microsecondsSinceEpoch}',
      );
      await Directory('${working.path}/eew_history').create(recursive: true);
      final originals = <String, Digest>{};
      await for (final file in Directory('${source.path}/eew_history').list()) {
        if (file is File) {
          originals[file.path] = await sha256.bind(file.openRead()).first;
          await file.copy(
            '${working.path}/eew_history/${file.uri.pathSegments.last}',
          );
        }
      }
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final previous = SharedPreferencesStorePlatform.instance;
      final worker = await WindowsPreferencesWorker.start(working.path);
      SharedPreferencesStorePlatform.instance = worker;
      var peak = ProcessInfo.currentRss;
      final baseline = peak;
      final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (ProcessInfo.currentRss > peak) {
          peak = ProcessInfo.currentRss;
        }
      });
      try {
        final storage = mode == 'legacy'
            ? LegacyWorkerHistory(worker)
            : historyStorage(prefs);
        final store = EewHistoryStore(
          preferenceKey: 'unified_eew_history',
          storage: storage,
        );
        final watch = Stopwatch()..start();
        final groups = await store.restoreForStartup(prefs, lazyReports: true);
        if (mode == 'folder') {
          // Migration is deliberately on demand; measure it separately from a
          // subsequent warm selection, not as an ordinary application startup.
          for (final group in groups) {
            await store.loadStationFrames(group);
          }
        }
        final migrationMs = watch.elapsedMilliseconds;
        stdout.writeln('Initial restore/migration complete: $migrationMs ms');
        final cold = EewHistoryStore(
          preferenceKey: 'unified_eew_history',
          storage: storage,
        );
        watch.reset();
        final summaries = await cold.restoreForStartup(
          prefs,
          lazyReports: true,
        );
        final startupMs = watch.elapsedMilliseconds;
        watch.reset();
        final prepared = <EewEventGroup>[];
        for (final group in summaries) {
          prepared.add(await cold.loadStationFrames(group));
        }
        final preparationMs = watch.elapsedMilliseconds;
        stdout.writeln('Warm preparation complete: $preparationMs ms');
        final entries = [
          for (final group in prepared)
            ...StationReplayFrames.describe(group.stationFrames),
        ];
        final preparationPeak = peak;
        watch.reset();
        for (final entry in entries.take(20)) {
          await entry.loadAsync();
        }
        final first20Ms = watch.elapsedMilliseconds;
        final package = HistoryReplayPackage.fromGroup(prepared.first);
        watch.reset();
        var exportBytes = 0;
        var exportOnlyMs = 0;
        if (mode == 'folder') {
          final output = '${working.path}/history-review.rqreplay';
          await exportReplayDirectory(package, output);
          exportOnlyMs = watch.elapsedMilliseconds;
          stdout.writeln('ZIP export complete: $exportOnlyMs ms');
          exportBytes = await File(output).length();
          final imported = await importReplayFile(output);
          try {
            expect(imported.reports.length, package.reports.length);
            final old = EewHistoryStore(
              preferenceKey: 'unified_eew_history',
              storage: LegacyWorkerHistory(worker),
            );
            final oldGroups = await old.restoreForStartup(
              prefs,
              lazyReports: true,
            );
            final oldGroup = oldGroups.singleWhere(
              (g) =>
                  g.eventId == prepared.first.eventId &&
                  g.latest.source == prepared.first.latest.source,
            );
            final oldPrepared = await old.loadStationFrames(oldGroup);
            final oldEntries = {
              for (final e in StationReplayFrames.describe(
                oldPrepared.stationFrames,
              ))
                '${e.kind}_${e.receivedAt.microsecondsSinceEpoch}': e,
            };
            final newEntries = StationReplayFrames.describe(
              imported.stationFrames,
            ).toList();
            expect(newEntries.length, oldEntries.length);
            for (var i = 0; i < newEntries.length; i++) {
              final entry = newEntries[i];
              expect(
                (await entry.loadAsync()).toMap(),
                (await oldEntries['${entry.kind}_${entry.receivedAt.microsecondsSinceEpoch}']!
                        .loadAsync())
                    .toMap(),
              );
            }
            final restored = await cold.loadReports(summaries.first);
            for (final report in imported.reports) {
              final raw =
                  await imported.storedReports!.payloads[report]!.load!();
              expect(
                raw.toMap(),
                restored.reports
                    .singleWhere(
                      (r) =>
                          historyReportSignature(r) ==
                          historyReportSignature(report),
                    )
                    .toMap(),
              );
            }
          } finally {
            await imported.releaseFiles?.call();
          }
        } else {
          final bytes = await Future(() => package.encodeBytes());
          exportOnlyMs = watch.elapsedMilliseconds;
          exportBytes = bytes.length;
          await File(
            '${working.path}/legacy-size.txt',
          ).writeAsString('$exportBytes');
        }
        final exportAndCheckMs = watch.elapsedMilliseconds;
        var folderBytes = 0, folderFiles = 0;
        final native = Directory('${working.path}/replay_history/v3');
        if (await native.exists()) {
          await for (final file in native.list(
            recursive: true,
            followLinks: false,
          )) {
            if (file is File) {
              folderFiles++;
              folderBytes += await file.length();
            }
          }
        }
        final metrics = {
          'mode': mode,
          'events': groups.length,
          'frames': entries.length,
          'initialRestoreOrMigrationMs': migrationMs,
          'warmSummaryMs': startupMs,
          'prepareMs': preparationMs,
          'first20FramesMs': first20Ms,
          'baselineRss': baseline,
          'preparationPeakRss': preparationPeak,
          'wholeTestPeakRss': peak,
          'exportOnlyMs': exportOnlyMs,
          'exportAndIntegrityCheckMs': exportAndCheckMs,
          'exportBytes': exportBytes,
          'directoryBytes': folderBytes,
          'directoryFiles': folderFiles,
          'working': working.path,
        };
        for (final entry in originals.entries) {
          expect(
            await sha256.bind(File(entry.key).openRead()).first,
            entry.value,
          );
        }
        await File('${working.path}/metrics.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(metrics),
          encoding: utf8,
        );
        stdout.writeln(jsonEncode(metrics));
      } finally {
        sampler.cancel();
        SharedPreferencesStorePlatform.instance = previous;
        await worker.close();
      }
    },
    skip: copy == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
