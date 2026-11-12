import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/history_replay_directory_io.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/history_storage.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'history_replay_timeline_test.dart' show captured, saved;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late WindowsPreferencesWorker worker;
  late SharedPreferencesStorePlatform previous;
  late SharedPreferences prefs;
  late HistoryStorage storage;
  EewHistoryStore store() =>
      EewHistoryStore(preferenceKey: 'unified_eew_history', storage: storage);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    previous = SharedPreferencesStorePlatform.instance;
    directory = await Directory.systemTemp.createTemp('rq-folder-test-');
    worker = await WindowsPreferencesWorker.start(directory.path);
    SharedPreferencesStorePlatform.instance = worker;
    storage = historyStorage(prefs);
    expect(storage, isA<HistoryFileStorage>());
  });
  tearDown(() async {
    SharedPreferencesStorePlatform.instance = previous;
    await worker.close();
    await directory.delete(recursive: true);
  });

  test(
    'recorded reports append as immutable files; cold load defers every body',
    () async {
      final original = saved(captured('cwa_1150074'));
      final chronological = original.reports.reversed.toList();
      final writer = store();
      await writer.save(prefs, [
        original.copyWith(reports: [chronological.first]),
      ]);
      final reportsDir = (await Directory(
        '${directory.path}/replay_history/v3/events',
      ).list().toList()).single;
      final firstFile =
          (await Directory('${reportsDir.path}/reports').list().toList()).single
              as File;
      final firstBytes = await firstFile.readAsBytes();
      final firstModified = await firstFile.lastModified();
      var cold = store();
      var group = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(group.reports.single.sourcePayload, isNull);
      for (final report in chronological.skip(1)) {
        group = group.addReport(report);
      }
      await cold.save(prefs, [group]);
      expect(await firstFile.readAsBytes(), firstBytes);
      expect(await firstFile.lastModified(), firstModified);
      cold = store();
      group = (await cold.restoreForStartup(prefs, lazyReports: true)).single;
      expect(group.reports.every((r) => r.sourcePayload == null), isTrue);
      final manifest = await File(
        '${reportsDir.path}/event.json',
      ).readAsString();
      expect(manifest, isNot(contains('"sourcePayload":{')));
      final hydrated = await cold.loadReports(group);
      expect(
        hydrated.reports.map((r) => r.toMap()),
        unorderedEquals(original.reports.map((r) => r.toMap())),
      );
    },
  );

  test(
    'individual frames remain on disk during preparation, export and import',
    () async {
      final original = saved(captured('cwa_1150074'));
      // Empty protocol frames test storage ownership, not invented observations.
      final frames = [
        for (final kind in StationHistoryFrame.kinds)
          StationHistoryFrame(
            receivedAt: original.firstArrivedAt,
            snapshot: {
              'kind': kind,
              if (kind == 'lpgm') 'topStations': [] else 'stations': [],
            },
          ),
      ];
      final writer = store();
      await writer.save(prefs, [original.copyWith(stationFrames: frames)]);
      final cold = store();
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      final prepared = await cold.loadStationFrames(summary);
      expect(prepared.reports.every((r) => r.sourcePayload == null), isTrue);
      final entries = StationReplayFrames.describe(
        prepared.stationFrames,
      ).toList();
      expect(entries, hasLength(frames.length));
      expect(
        entries.every((e) => e.filePath != null && e.cachedFrame == null),
        isTrue,
      );
      for (final entry in entries) {
        expect(
          (await entry.loadAsync()).toMap(),
          frames.singleWhere((f) => f.kind == entry.kind).toMap(),
        );
        expect(
          entry.cachedFrame,
          isNull,
          reason: 'No whole-recording expanded cache',
        );
      }
      final zip = File('${directory.path}/review.rqreplay');
      await exportReplayDirectory(
        HistoryReplayPackage.fromGroup(prepared),
        zip.path,
      );
      final stream = InputFileStream(zip.path);
      final archive = ZipDecoder().decodeStream(stream);
      expect(
        archive.files.where((f) => f.name.startsWith('frames/')),
        hasLength(frames.length),
      );
      expect(
        archive.files.where((f) => f.name.startsWith('reports/')),
        hasLength(original.reportCount),
      );
      final manifest =
          jsonDecode(utf8.decode(archive.find('manifest.json')!.readBytes()!))
              as Map;
      expect(manifest['version'], 3);
      expect(manifest, isNot(contains('stationArchive')));
      await stream.close();
      final imported = await importReplayFile(zip.path);
      try {
        expect(imported.reports.every((r) => r.sourcePayload == null), isTrue);
        for (final report in imported.reports) {
          final hydrated =
              await imported.storedReports!.payloads[report]!.load!();
          expect(
            hydrated.toMap(),
            original.reports
                .singleWhere(
                  (r) =>
                      historyReportSignature(r) ==
                      historyReportSignature(report),
                )
                .toMap(),
          );
        }
        for (final entry in StationReplayFrames.describe(
          imported.stationFrames,
        )) {
          expect(
            (await entry.loadAsync()).toMap(),
            frames.singleWhere((f) => f.kind == entry.kind).toMap(),
          );
        }
      } finally {
        await imported.releaseFiles?.call();
      }
    },
  );

  test(
    'playback reads one report at a time; stopping ignores an in-flight read',
    () async {
      final original = saved(captured('cwa_1150074'));
      await store().save(prefs, [original]);
      final cold = store();
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      final package = HistoryReplayPackage.fromGroup(summary);
      final output = <UnifiedQuakeData>[];
      final controller = HistoryReplayController(
        onReport: output.add,
        onClear: (_) {},
        loadHistoryGroup: cold.loadStationFrames,
      );
      try {
        controller.load(package, storedGroup: summary, remember: false);
        await controller.playPrepared();
        for (var i = 0; i < 100 && output.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(output, hasLength(1));
        expect(
          output.single.sourcePayload,
          original.reports.first.sourcePayload,
        );
        expect(
          controller.package!.reports.every((r) => r.sourcePayload == null),
          isTrue,
        );
        controller.stop();
        final count = output.length;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(output, hasLength(count));
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'legacy event files migrate without changing any original file',
    () async {
      final original = saved(captured('cwa_1150074'));
      final legacy = store();
      final key = legacy.recordKey(original);
      await worker.writeHistory(key, jsonEncode(original.toMap()));
      await worker.writeHistory(legacy.indexKey, [key]);
      final oldFiles = await Directory(
        '${directory.path}/eew_history',
      ).list().where((e) => e is File).cast<File>().toList();
      final originals = {
        for (final f in oldFiles) f.path: await f.readAsBytes(),
      };
      final cold = store();
      var group = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(
        group.storedReports!.payloads.values.every((r) => r.fileId == null),
        isTrue,
      );
      await cold.save(prefs, [group]);
      expect(
        await Directory('${directory.path}/replay_history/v3/frames').exists(),
        isFalse,
      );
      group = await cold.loadStationFrames(group);
      expect((await cold.loadReports(group)).toMap(), original.toMap());
      for (final e in originals.entries) {
        expect(await File(e.key).readAsBytes(), e.value);
      }
      expect(
        group.storedReports!.payloads.values.every((r) => r.fileId != null),
        isTrue,
      );
    },
  );

  test(
    'failed manifest commit retains original ownership and permits exact retry',
    () async {
      final original = saved(captured('cwa_1150074'));
      final writer = store();
      final files = storage as HistoryFileStorage;
      // The application owns this derived path; block only its pending manifest.
      final reportPath = files.reportPath(writer.recordKey(original), '0' * 64);
      final event = Directory(File(reportPath).parent.parent.path);
      final obstruction = Directory('${event.path}/event.json.pending');
      await obstruction.create(recursive: true);
      await expectLater(
        writer.save(prefs, [original]),
        throwsA(isA<StateError>()),
      );
      expect(
        writer.releaseSavedFrames(original, deferReports: true),
        same(original),
      );
      expect(
        (await store().restoreForStartup(prefs, lazyReports: true)),
        isEmpty,
      );
      await obstruction.delete();
      await writer.save(prefs, [original]);
      final cold = store();
      final restored = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect((await cold.loadReports(restored)).toMap(), original.toMap());
    },
  );

  test(
    'legacy JSON import converts off-thread into independent report files',
    () async {
      final original = captured('cwa_1150074');
      final imported = await importReplayFile(
        'test/fixtures/history_replay/cwa_1150074.rqreplay',
      );
      try {
        expect(imported.reports.every((r) => r.sourcePayload == null), isTrue);
        expect(imported.reports.length, original.reports.length);
        for (var i = 0; i < imported.reports.length; i++) {
          final report = imported.reports[i];
          expect(
            (await imported.storedReports!.payloads[report]!.load!()).toMap(),
            original.reports[i].toMap(),
          );
        }
      } finally {
        await imported.releaseFiles?.call();
      }
    },
  );

  test(
    'directory presentation upgrades rebuild from unchanged original report files',
    () async {
      final original = saved(captured('cwa_1150074'));
      await store().save(prefs, [original]);
      final eventDir = (await Directory(
        '${directory.path}/replay_history/v3/events',
      ).list().toList()).single;
      final file = File('${eventDir.path}/event.json');
      final manifest = jsonDecode(await file.readAsString()) as Map;
      (manifest['snapshot'] as Map).remove('presentationVersion');
      for (final report
          in (manifest['snapshot']['group'] as Map)['reports'] as List) {
        (report as Map)
          ..remove('displayEstimatedIntensity')
          ..remove('displayEstimateResolved');
      }
      await file.writeAsString(jsonEncode(manifest), encoding: utf8);
      final cold = store();
      final summary = (await cold.restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(summary.savedReportCount, original.reportCount);
      expect(summary.reports.every((r) => r.sourcePayload == null), isTrue);
      expect((await cold.loadReports(summary)).toMap(), original.toMap());
      expect(
        jsonDecode(
          await file.readAsString(),
        )['snapshot']['presentationVersion'],
        1,
      );
    },
  );

  test(
    'unsafe ZIP paths and duplicate station frame identities are rejected',
    () async {
      final file = File('${directory.path}/unsafe.rqreplay');
      final archive = Archive()
        ..add(ArchiveFile.string('../outside.json', '{}'));
      await file.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(importReplayFile(file.path), throwsFormatException);
      expect(await File('${directory.path}/outside.json').exists(), isFalse);
    },
  );
}
