import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

List<StationHistoryFrame> readFrames(String path) => StationJsonArchive.decode(
  jsonDecode(File(path).readAsStringSync(encoding: utf8)) as Map,
);

Map<String, int> fingerprints(List<StationHistoryFrame> frames) {
  final result = <String, int>{};
  for (final frame in frames) {
    final key = sha256
        .convert(utf8.encode(jsonEncode(frame.toMap())))
        .toString();
    result.update(key, (v) => v + 1, ifAbsent: () => 1);
  }
  return result;
}

Future<void> main() async {
  try {
    await probe();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<void> probe() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final root = Directory(env['RQ_APP_PROBE_ROOT']!);
  if (!root.isAbsolute || await root.exists()) {
    throw ArgumentError('Use a new isolated absolute RQ_APP_PROBE_ROOT');
  }
  final chunks = await Directory(env['RQ_APP_PROBE_CHUNKS']!)
      .list()
      .where((e) => e is File && e.path.endsWith('.stations.json'))
      .cast<File>()
      .toList();
  chunks.sort((a, b) => a.path.compareTo(b.path));
  if (chunks.isEmpty) throw StateError('Original recorded chunks required');
  final fixture = HistoryReplayPackage.decode(
    await File(env['RQ_APP_PROBE_EVENT']!).readAsString(),
  );
  await root.create(recursive: true);
  final worker = await WindowsPreferencesWorker.start(root.path);
  SharedPreferencesStorePlatform.instance = worker;
  final prefs = await SharedPreferences.getInstance();
  final store = EewHistoryStore(preferenceKey: 'unified_eew_history');
  await store.restoreForStartup(prefs);
  var group = EewEventGroup(
    eventId: fixture.reports.first.eventId,
    reports: fixture.reports,
    firstArrivedAt: fixture.times.first,
  );
  var phase = 'save';
  final peaks = <String, int>{};
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    final rss = ProcessInfo.currentRss;
    if (rss > (peaks[phase] ?? 0)) peaks[phase] = rss;
  });
  runApp(const SizedBox.shrink());
  final expected = <String, int>{};
  var totalFrames = 0;
  var originalBytes = 0;
  var saveMs = 0;
  for (final chunk in chunks) {
    phase = 'read-original';
    final frames = await compute(readFrames, chunk.path);
    totalFrames += frames.length;
    originalBytes += await chunk.length();
    phase = 'audit-original';
    for (final entry in (await compute(fingerprints, frames)).entries) {
      expected.update(
        entry.key,
        (v) => v + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    phase = 'save';
    group = group.copyWith(stationFrames: [...group.stationFrames, ...frames]);
    final watch = Stopwatch()..start();
    await store.save(prefs, [group]);
    saveMs += watch.elapsedMilliseconds;
    group = store.releaseSavedFrames(group);
    if (group.stationFrames.isNotEmpty) {
      throw StateError('Saved frames retained in APP memory');
    }
    stdout.writeln(
      jsonEncode({
        'phase': phase,
        'frames': totalFrames,
        'saveMs': watch.elapsedMilliseconds,
        'rss': ProcessInfo.currentRss,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  phase = 'startup-restore';
  final restarted = EewHistoryStore(preferenceKey: 'unified_eew_history');
  final watch = Stopwatch()..start();
  final restored = (await restarted.restoreForStartup(prefs)).single;
  final restoreMs = watch.elapsedMilliseconds;
  if (restored.stationFrames.isNotEmpty ||
      restored.storedStations!.frameKeys.length != totalFrames) {
    throw StateError('Startup eagerly loaded frames or lost references');
  }
  phase = 'replay-load';
  watch.reset();
  final loaded = await restarted.loadStationFrames(restored);
  final loadMs = watch.elapsedMilliseconds;
  phase = 'verify';
  final actual = await compute(fingerprints, loaded.stationFrames);
  if (expected.length != actual.length ||
      !expected.entries.every((e) => actual[e.key] == e.value)) {
    throw StateError('Original APP station JSON changed');
  }
  final bytes = [
    for (final e
        in await root
            .list(recursive: true)
            .where((e) => e is File)
            .cast<File>()
            .toList())
      await e.length(),
  ].fold<int>(0, (a, b) => a + b);
  timer.cancel();
  await worker.close();
  final result = {
    'passed': true,
    'frames': totalFrames,
    'originalChunkBytes': originalBytes,
    'storedBytes': bytes,
    'saveMs': saveMs,
    'startupRestoreMs': restoreMs,
    'replayLoadMs': loadMs,
    'phaseRssPeaks': peaks,
    'note':
        'APP history store only, not whole APP UI. Original server probe observations unchanged; isolated files.',
  };
  await File(
    '${root.path}/report.json',
  ).writeAsString(jsonEncode(result), encoding: utf8, flush: true);
  stdout.writeln(jsonEncode(result));
}
