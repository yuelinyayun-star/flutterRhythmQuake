import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['RQ_MEMORY_HISTORY_COPY'];
  test(
    'real copied GQ history keeps original exports and persists subsequent reports',
    () async {
      final root = Directory(path!).absolute.path;
      expect(
        root.startsWith(
          '${Directory('tmp').absolute.path}${Platform.pathSeparator}',
        ),
        isTrue,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final previous = SharedPreferencesStorePlatform.instance;
      final worker = await WindowsPreferencesWorker.start(root);
      SharedPreferencesStorePlatform.instance = worker;
      try {
        await worker.getAll();
        final store = EewHistoryStore(preferenceKey: 'unified_eew_history');
        final groups = await store.restoreForStartup(prefs);
        var reports = 0;
        final originalRecords = <String, String>{};
        for (final group in groups) {
          final key = store.recordKey(group);
          final text = await worker.readHistory(key) as String;
          originalRecords[key] = text;
          final original = jsonDecode(text) as Map;
          for (var i = 0; i < group.reports.length; i++) {
            final report = group.reports[i];
            expect(
              jsonEncode(report.sourcePayload),
              jsonEncode(original['reports'][i]['sourcePayload']),
            );
            if (report.source == 'globalQuakeEew' &&
                report.sourcePayload != null) {
              expect(report.sourcePayload, isA<EncodedSourcePayload>());
              reports++;
            }
          }
        }
        expect(reports, greaterThan(100));
        final timer = Stopwatch()..start();
        await store.save(prefs, groups);
        final noopMs = timer.elapsedMilliseconds;
        for (final entry in originalRecords.entries) {
          expect(await worker.readHistory(entry.key), entry.value);
        }
        final original = groups.firstWhere(
          (g) => g.latest.source == 'globalQuakeEew' && g.reportCount >= 2,
        );
        // Replay two original reports in source sequence without editing them.
        final first = original.copyWith(reports: [original.reports.last]);
        await store.save(prefs, [first]);
        final released = store.releaseSavedFrames(first);
        expect(released.latest.sourcePayload, isA<EncodedSourcePayload>());
        final next = released.addReport(
          original.reports[original.reports.length - 2],
        );
        await store.save(prefs, [next]);
        final restarted = EewHistoryStore(preferenceKey: 'unified_eew_history');
        final restored = (await restarted.restoreForStartup(prefs)).single;
        expect(restored.toMap(), next.toMap());
        expect(restored.reportCount, 2);
        // ignore: avoid_print
        print(
          'Original compact GQ reports=$reports; unchanged save=${noopMs}ms; exports and next-report persistence match',
        );
      } finally {
        SharedPreferencesStorePlatform.instance = previous;
        await worker.close();
      }
    },
    skip: path == null,
  );
}
