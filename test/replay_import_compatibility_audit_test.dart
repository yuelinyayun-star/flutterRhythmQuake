// A2 regressions: original v1/v2, new v3 and pre-fix v3 use the real import/play
// entrypoints with the production history-loader configuration.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/history_replay_directory_io.dart';
import 'package:flutterrhythmquake/services/native_replay_policy.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_controls.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_file_io.dart'
    as replay_file;

import 'history_replay_controls_test.dart'
    show ReplayFilePicker, waitForFileAction;

const originals = <String, String>{
  'v1-cwa': 'test/fixtures/history_replay/cwa_1150074.rqreplay',
  'v1-cea': 'test/fixtures/history_replay/cea_202609290220.rqreplay',
  'v2-gq': 'test/fixtures/global_quake/captured_report_only_20261018.json',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final paths = <String, String>{};
  final expected = <String, HistoryReplayPackage>{};
  final hashes = <String, String>{};
  final evidence = <Map<String, Object?>>[];

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('rq-a2-compat-audit-');
    FilePicker.platform = ReplayFilePicker();
    for (final entry in originals.entries) {
      final bytes = await File(entry.value).readAsBytes();
      hashes[entry.value] = sha256.convert(bytes).toString();
      final package = HistoryReplayPackage.decode(utf8.decode(bytes));
      paths[entry.key] = entry.value;
      expected[entry.key] = package;
      // New-format containers are made by the production exporter from the
      // unchanged original reports; no version or observation field is edited.
      final key = 'v3-from-${entry.key}';
      final path = '${temp.path}/$key.rqreplay';
      await exportReplayDirectory(package, path);
      paths[key] = path;
      expected[key] = package;
    }
    const baseline =
        'test/fixtures/history_replay/cea_202609290220_v3_pre_fix.rqreplay';
    paths['v3-pre-fix-cea'] = baseline;
    expected['v3-pre-fix-cea'] = expected['v1-cea']!;
    hashes[baseline] = sha256
        .convert(await File(baseline).readAsBytes())
        .toString();
  });

  tearDownAll(() async {
    for (final entry in hashes.entries) {
      expect(
        sha256.convert(await File(entry.key).readAsBytes()).toString(),
        entry.value,
      );
    }
    final output = Directory('tmp/replay_import_fix_20261102');
    await output.create(recursive: true);
    await File('${output.path}/results.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'originalSha256': hashes,
        'cases': evidence,
        'productionChanged': true,
        'nativePolicyUsed': NativeReplayPolicy.supported,
        'nativeCalls': NativeReplayPolicy.supported
            ? NativeReplayPolicy.calls
            : 0,
        'outstandingNativeOutputs': NativeReplayPolicy.supported
            ? NativeReplayPolicy.outputs
            : 0,
      }),
      encoding: utf8,
    );
    await temp.delete(recursive: true);
  });

  for (final key in [
    'v1-cwa',
    'v1-cea',
    'v2-gq',
    'v3-from-v1-cwa',
    'v3-from-v1-cea',
    'v3-from-v2-gq',
    'v3-pre-fix-cea',
  ]) {
    for (final linked in [false, true]) {
      test(
        'FIX $key linked=$linked: original times and prepared file playback',
        () async {
          final original = expected[key]!;
          final package = await replay_file.importReplay(paths[key]!);
          var loaderCalls = 0;
          final delivered = <UnifiedQuakeData>[];
          final controller = HistoryReplayController(
            onReport: delivered.add,
            onClear: (_) {},
            historyGroups: () => [],
            loadHistoryGroup: (group) async {
              loaderCalls++;
              return group;
            },
          );
          try {
            expect(package.hasFileReports, isTrue);
            expect(package.storedStations, isNull);
            expect(package.reports.length, original.reports.length);
            expect(package.times, original.times);
            expect(package.timing, original.timing);
            if (key.endsWith('cea')) {
              expect(
                original.times.single.toIso8601String(),
                '2026-09-28T18:20:44.000Z',
              );
              expect(
                package.times.single.toIso8601String(),
                '2026-09-28T18:20:44.000Z',
              );
              expect(original.timing, HistoryReplayTiming.report);
              expect(package.timing, HistoryReplayTiming.report);
              expect(
                package.storedReports!.payloads.values.single.reportInstant,
                original.times.single,
              );
              expect(
                original.reports.single.sourcePayload!['ReportTime'],
                '2026-09-29 02:20:44',
              );
            }
            expect(package.captureEndedAt, original.captureEndedAt);
            for (var i = 0; i < package.reports.length; i++) {
              final loaded = await package
                  .storedReports!
                  .payloads[package.reports[i]]!
                  .load!();
              expect(loaded.toMap(), original.reports[i].toMap());
            }
            controller.restoreTimelineLinked(linked);
            controller.importPackages([package]);
            await controller.playPrepared();
            expect(controller.active, isTrue);
            expect(controller.preparing, isFalse);
            expect(loaderCalls, 0);
            for (var i = 0; i < 200 && delivered.isEmpty; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            expect(delivered, isNotEmpty);
            expect(
              delivered.first.sourcePayload,
              original.reports.first.sourcePayload,
            );
            expect(controller.playbackError, isNull);
            evidence.add({
              'case': key,
              'timelineLinked': linked,
              'reportCount': original.reports.length,
              'allOriginalReportsMatch': true,
              'allTimesMatch': true,
              'originalTiming': original.timing.name,
              'importedTiming': package.timing.name,
              'originalTimes': original.times
                  .map((t) => t.toIso8601String())
                  .toList(),
              'importedTimes': package.times
                  .map((t) => t.toIso8601String())
                  .toList(),
              'hasFileReports': package.hasFileReports,
              'preparedError': null,
              'historyLoaderCalls': loaderCalls,
              'preparedPlaybackDeliveredOriginalPayload': true,
            });
          } finally {
            controller.dispose();
          }
        },
      );
    }
  }

  test(
    'pre-fix v3 keeps raw files and re-exports a complete publication index',
    () async {
      final path = paths['v3-pre-fix-cea']!;
      Map manifest(String path) {
        final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
        return jsonDecode(
              utf8.decode(archive.find('manifest.json')!.readBytes()!),
            )
            as Map;
      }

      expect(
        (manifest(path)['reports'] as List).single['reportInstant'],
        isNull,
      );
      final package = await replay_file.importReplay(path);
      try {
        final ref = package.storedReports!.payloads.values.single;
        final reportBytes = await File(ref.filePath!).readAsBytes();
        final destination = '${temp.path}/reexported-pre-fix.rqreplay';
        await exportReplayDirectory(package, destination);
        expect(
          (manifest(destination)['reports'] as List).single['reportInstant'],
          '2026-09-28T18:20:44.000Z',
        );
        expect(await File(ref.filePath!).readAsBytes(), reportBytes);
        final reopened = await replay_file.importReplay(destination);
        try {
          expect(reopened.times, expected['v1-cea']!.times);
          final loaded =
              await reopened.storedReports!.payloads.values.single.load!();
          expect(loaded.toMap(), expected['v1-cea']!.reports.single.toMap());
        } finally {
          await reopened.releaseFiles!();
        }
      } finally {
        await package.releaseFiles!();
      }
    },
  );

  test(
    'multiple imports can link and switch anchors with production history loader',
    () async {
      final cwa = await replay_file.importReplay(paths['v1-cwa']!);
      final cea = await replay_file.importReplay(paths['v3-pre-fix-cea']!);
      var calls = 0;
      final controller = HistoryReplayController(
        onReport: (_) {},
        onClear: (_) {},
        historyGroups: () => [],
        loadHistoryGroup: (group) async {
          calls++;
          return group;
        },
      );
      try {
        controller.importPackages([cwa, cea]);
        controller.restoreTimelineLinked(true);
        await controller.playPrepared();
        expect(controller.active, isTrue);
        expect(controller.linkedEventCount, 2);
        expect(controller.totalReports, 5);
        controller.load(cea);
        await controller.playPrepared();
        expect(controller.active, isTrue);
        expect(controller.linkedEventCount, 2);
        expect(calls, 0);
      } finally {
        controller.dispose();
      }
    },
  );

  for (final key in ['v1-cwa', 'v2-gq', 'v3-from-v1-cwa', 'v3-pre-fix-cea']) {
    testWidgets('FIX actual import/play buttons play original data: $key', (
      tester,
    ) async {
      final previous = FilePicker.platform;
      final picker = ReplayFilePicker()..inputPath = paths[key];
      FilePicker.platform = picker;
      var loaderCalls = 0;
      final delivered = <UnifiedQuakeData>[];
      final controller = HistoryReplayController(
        onReport: delivered.add,
        onClear: (_) {},
        loadHistoryGroup: (group) async {
          loaderCalls++;
          return group;
        },
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 520,
                child: HistoryReplayControls(controller: controller),
              ),
            ),
          ),
        );
        await tester.runAsync(() => tester.tap(find.byTooltip('导入回放包')));
        await waitForFileAction(
          tester,
          () => controller.importedPackages.isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(controller.package!.hasFileReports, isTrue);
        await tester.runAsync(() => tester.tap(find.byTooltip('播放回放')));
        await waitForFileAction(tester, () => delivered.isNotEmpty);
        await tester.pump();
        expect(
          find.textContaining('Missing saved replay selection'),
          findsNothing,
        );
        expect(controller.active, isTrue);
        expect(
          delivered.first.sourcePayload,
          expected[key]!.reports.first.sourcePayload,
        );
        expect(loaderCalls, 0);
        expect(tester.takeException(), isNull);
        evidence.add({
          'case': key,
          'actualImportAndPlayButtons': true,
          'originalPayloadDelivered': true,
          'visibleError': null,
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        FilePicker.platform = previous;
      }
    });
  }
}
