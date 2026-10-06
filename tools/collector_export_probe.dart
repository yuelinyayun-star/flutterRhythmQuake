import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/collector/replay_collector.dart';

Future<void> copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entry in source.list(followLinks: false)) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is File && name != 'collector.lock') {
      await entry.copy('${destination.path}/$name');
    } else if (entry is Directory) {
      await copyDirectory(entry, Directory('${destination.path}/$name'));
    }
  }
}

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final root = Directory(Platform.environment['RQ_PROBE_ROOT']!);
    final input = Directory(Platform.environment['RQ_EXPORT_INPUT']!);
    if (!root.isAbsolute || await root.exists() || !await input.exists()) {
      throw ArgumentError(
        'New isolated absolute root and original checkpoint directory required',
      );
    }
    final spool = Directory('${root.path}/active');
    final audit = Directory('${root.path}/audit');
    await copyDirectory(input, spool);
    await copyDirectory(input, audit);
    final manifests = await spool
        .list()
        .where((e) => e is Directory && !e.path.endsWith('/chunks'))
        .cast<Directory>()
        .toList();
    var now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final directory in manifests) {
      final value =
          jsonDecode(await File('${directory.path}/event.json').readAsString())
              as Map;
      final end = DateTime.parse(
        value['end'] as String,
      ).add(const Duration(seconds: 1));
      if (end.isAfter(now)) now = end;
    }
    final collector = ReplayCollector(
      spool: spool,
      output: Directory('${root.path}/outbox'),
      stations: StationHistoryFrame.kinds,
      now: () => now,
    );
    await collector.open();
    runApp(const SizedBox.shrink());
    stdout.writeln(
      jsonEncode({
        'phase': 'start',
        'mode': 'export-original-checkpoints',
        'eventCount': collector.activeCount,
        'pid': pid,
      }),
    );
    stdout.writeln(
      jsonEncode({'phase': 'export', 'rssBytes': ProcessInfo.currentRss}),
    );
    final watch = Stopwatch()..start();
    final files = await collector.tick();
    stdout.writeln(
      jsonEncode({
        'phase': 'exported',
        'operationMs': watch.elapsedMilliseconds,
        'rssBytes': ProcessInfo.currentRss,
        'files': [
          for (final file in files)
            {'name': file.uri.pathSegments.last, 'bytes': await file.length()},
        ],
      }),
    );
    if (files.length != manifests.length) {
      throw StateError('Not all original captures exported');
    }
    // The measurement driver performs independent bounded verification after
    // this process exits; validation must not recreate the old full-frame heap.
    await collector.close();
    stdout.writeln(
      jsonEncode({'phase': 'done', 'rssBytes': ProcessInfo.currentRss}),
    );
    exit(0);
  } catch (error, stack) {
    stdout.writeln(jsonEncode({'phase': 'failed', 'error': error.toString()}));
    stderr.writeln(stack);
    exit(1);
  }
}
