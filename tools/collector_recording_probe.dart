import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/main_collector.dart' as production;
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/collector/replay_collector.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';
import 'package:flutterrhythmquake/services/sources/station_image_decoder.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';

// Independent content fingerprints traverse original table references, not the
// export interner. They verify every field without expanding a whole replay.
List<String> archiveFingerprints(Map archive) {
  if (archive['format'] != StationJsonArchive.format) {
    throw const FormatException('Invalid archive format');
  }
  final hashes = <String>[];
  for (final node in archive['nodes'] as List) {
    final dynamic content = node is List
        ? [node.first, for (final ref in node.skip(1)) hashes[ref as int]]
        : node;
    hashes.add(sha256.convert(utf8.encode(jsonEncode(content))).toString());
  }
  return [for (final root in archive['frames'] as List) hashes[root as int]];
}

Future<(String, Map<String, int>, String)> verifyRecording(
  (String, String) request,
) async {
  final (path, auditPath) = request;
  final bytes = await File(path).readAsBytes();
  final digest = sha256.convert(bytes).toString();
  final map = jsonDecode(utf8.decode(bytes)) as Map;
  final reports = (map['reports'] as List)
      .map((e) => UnifiedQuakeData.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
  final key = sha256.convert(
    utf8.encode(jsonEncode([reports.first.source, reports.first.eventId])),
  );
  final manifest =
      jsonDecode(await File('$auditPath/$key/event.json').readAsString())
          as Map;
  final expected = EewEventGroup.fromMap(manifest['group'] as Map);
  final originals = reports.map((e) => jsonEncode(e.sourcePayload)).toSet();
  if (originals.length != expected.reports.length ||
      !expected.reports.every(
        (e) => originals.contains(jsonEncode(e.sourcePayload)),
      )) {
    throw StateError('Original reports changed');
  }
  final remaining = <String, int>{};
  final archive = map['stationArchive'] as Map;
  for (final hash in archiveFingerprints(archive)) {
    remaining.update(hash, (v) => v + 1, ifAbsent: () => 1);
  }
  final counts = <String, int>{};
  final chunks = await Directory('$auditPath/$key')
      .list()
      .where((e) => e is File && e.path.endsWith('.stations.json'))
      .cast<File>()
      .toList();
  chunks.addAll([
    for (final name in manifest['chunks'] as List? ?? const [])
      File('$auditPath/chunks/$name'),
  ]);
  for (final chunk in chunks) {
    final bytes = await chunk.readAsBytes();
    final saved =
        jsonDecode(
              utf8.decode(
                chunk.path.endsWith('.gz') ? gzip.decode(bytes) : bytes,
              ),
            )
            as Map;
    for (final frame in StationJsonArchive.decode(saved)) {
      counts.update(frame.kind, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final hash in archiveFingerprints(saved)) {
      final count = remaining[hash] ?? 0;
      if (count == 0) throw StateError('Checkpoint observation changed');
      remaining[hash] = count - 1;
    }
  }
  if (remaining.values.any((count) => count != 0)) {
    throw StateError('Export contains observations absent from checkpoints');
  }
  return (reports.first.source, counts, digest);
}

Future<void> main() async {
  try {
    await runProbe();
  } catch (error, stack) {
    stdout.writeln(jsonEncode({'phase': 'failed', 'error': error.toString()}));
    stderr.writeln(stack);
    exit(1);
  }
}

Future<void> runProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  StationImageDecoder.cpuOnly = true;
  final env = Platform.environment;
  final rootPath = env['RQ_PROBE_ROOT'];
  final paths = env['RQ_PROBE_EVENTS']?.split(',');
  final seconds = int.tryParse(env['RQ_PROBE_SECONDS'] ?? '300');
  if (rootPath == null ||
      !Directory(rootPath).isAbsolute ||
      paths == null ||
      paths.isEmpty ||
      seconds == null ||
      seconds < 60 ||
      seconds > 1800) {
    stderr.writeln(
      'Set isolated absolute RQ_PROBE_ROOT and original event files.',
    );
    exit(64);
  }
  final root = Directory(rootPath);
  if (await root.exists()) {
    stderr.writeln(
      'Probe directory must be new; existing data will not be overwritten.',
    );
    exit(64);
  }
  await root.create(recursive: true);
  final fixtures = <HistoryReplayPackage>[];
  for (final path in paths) {
    fixtures.add(HistoryReplayPackage.decode(await File(path).readAsString()));
  }
  final base = fixtures.first.reports.first.arrivedAt!.toUtc();
  final watch = Stopwatch();
  DateTime clock() => base.add(watch.elapsed);
  final spool = Directory('${root.path}/active');
  final outbox = Directory('${root.path}/outbox');
  await spool.create();
  // Only the checkpoint envelope controls the test window. Reports and all
  // original source JSON remain unchanged; this is not an actual quake replay.
  for (final fixture in fixtures) {
    final event = fixture.reports.first;
    final key = sha256.convert(
      utf8.encode(jsonEncode([event.source, event.eventId])),
    );
    final directory = Directory('${spool.path}/$key');
    await directory.create();
    final group = EewEventGroup(
      eventId: event.eventId,
      reports: fixture.reports,
      firstArrivedAt: fixture.reports.first.arrivedAt!.toUtc(),
    );
    await File('${directory.path}/event.json').writeAsString(
      jsonEncode({
        'group': group.toMap(includeStationFrames: false),
        'end': base.add(Duration(seconds: seconds + 2)).toIso8601String(),
      }),
      encoding: utf8,
      flush: true,
    );
  }
  final collector = ReplayCollector(
    spool: spool,
    output: outbox,
    stations: StationHistoryFrame.kinds,
    now: clock,
  );
  await collector.open();
  final capture = StationHistoryCapture.instance;
  final counts = <String, int>{};
  final stationCounts = <String, int>{};
  final subscriptions = <StreamSubscription<dynamic>>[];
  final stops = <void Function()>[];
  var phase = 'recording';
  var accepting = true;
  var busy = false;
  DateTime? firstLiveReceipt;
  DateTime? lastLiveReceipt;
  void receive(StationHistoryFrame frame) {
    if (!accepting) return;
    firstLiveReceipt ??= frame.receivedAt;
    lastLiveReceipt = frame.receivedAt;
    counts.update(frame.kind, (v) => v + 1, ifAbsent: () => 1);
    stationCounts[frame.kind] =
        (frame.snapshot[frame.kind == 'lpgm' ? 'topStations' : 'stations']
                as List)
            .length;
    collector.addStation(
      StationHistoryFrame(
        receivedAt: clock(),
        snapshot: frame.snapshot,
        originalJson: frame.originalJson,
      ),
    );
  }

  capture.addListener(receive);
  final sample = Timer.periodic(const Duration(seconds: 5), (_) {
    stdout.writeln(
      jsonEncode({
        'phase': phase,
        'elapsedMs': watch.elapsedMilliseconds,
        'rssBytes': ProcessInfo.currentRss,
        'active': collector.activeCount,
        'frames': counts,
      }),
    );
  });
  final checkpoint = Timer.periodic(const Duration(seconds: 5), (_) async {
    if (busy) return;
    busy = true;
    final duration = Stopwatch()..start();
    try {
      await collector.tick(finalize: false);
      stdout.writeln(
        jsonEncode({
          'phase': 'checkpoint',
          'elapsedMs': watch.elapsedMilliseconds,
          'operationMs': duration.elapsedMilliseconds,
          'rssBytes': ProcessInfo.currentRss,
        }),
      );
    } catch (error) {
      stderr.writeln('Probe checkpoint failed: $error');
      exit(1);
    } finally {
      busy = false;
    }
  });
  watch.start();
  runApp(const SizedBox.shrink());
  unawaited(NtpService().syncTime());
  NtpService().startPeriodicSync();
  production.startCollectorStations(
    enabled: StationHistoryFrame.kinds,
    capture: capture,
    status: (source, connected) => stdout.writeln('$source $connected'),
    subscriptions: subscriptions,
    stopSources: stops,
  );
  stdout.writeln(
    jsonEncode({
      'phase': 'start',
      'testClockBase': base.toIso8601String(),
      'recordSeconds': seconds,
      'eventCount': collector.activeCount,
      'pid': pid,
    }),
  );
  await Future<void>.delayed(Duration(seconds: seconds));
  accepting = false;
  checkpoint.cancel();
  while (busy) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await collector.tick(finalize: false);
  var chunkBytes = 0;
  var chunkCount = 0;
  await for (final entity in spool.list(recursive: true)) {
    if (entity is File &&
        (entity.path.endsWith('.stations.json') ||
            entity.path.endsWith('.stations.json.gz'))) {
      chunkBytes += await entity.length();
      chunkCount++;
    }
  }
  stdout.writeln(
    jsonEncode({
      'phase': 'recorded',
      'frames': counts,
      'stationCounts': stationCounts,
      'chunkBytes': chunkBytes,
      'chunkCount': chunkCount,
      'firstLiveReceiptUtc': firstLiveReceipt?.toIso8601String(),
      'lastLiveReceiptUtc': lastLiveReceipt?.toIso8601String(),
      'rssBytes': ProcessInfo.currentRss,
    }),
  );
  phase = 'prepare-audit';
  final audit = Directory('${root.path}/audit');
  await audit.create();
  await for (final entity in spool.list(recursive: true)) {
    if (entity is File &&
        (entity.path.endsWith('.stations.json') ||
            entity.path.endsWith('.stations.json.gz') ||
            entity.path.endsWith('/event.json'))) {
      final relative = entity.path.substring(spool.path.length);
      final copy = File('${audit.path}$relative');
      await copy.parent.create(recursive: true);
      await entity.copy(copy.path);
    }
  }
  await Future<void>.delayed(const Duration(seconds: 3));
  phase = 'export';
  final exportWatch = Stopwatch()..start();
  stdout.writeln(
    jsonEncode({
      'phase': phase,
      'elapsedMs': watch.elapsedMilliseconds,
      'rssBytes': ProcessInfo.currentRss,
    }),
  );
  final files = await collector.tick();
  stdout.writeln(
    jsonEncode({
      'phase': 'exported',
      'elapsedMs': watch.elapsedMilliseconds,
      'operationMs': exportWatch.elapsedMilliseconds,
      'rssBytes': ProcessInfo.currentRss,
      'files': [
        for (final file in files)
          {'name': file.uri.pathSegments.last, 'bytes': await file.length()},
      ],
    }),
  );
  if (files.length != fixtures.length) {
    throw StateError('Not all test captures exported');
  }
  capture.removeListener(receive);
  for (final stop in stops) {
    stop();
  }
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  phase = 'verify';
  // Independent bounded verification is run by the measurement driver.
  await collector.close();
  phase = 'settle';
  await Future<void>.delayed(const Duration(seconds: 15));
  sample.cancel();
  stdout.writeln(
    jsonEncode({'phase': 'done', 'rssBytes': ProcessInfo.currentRss}),
  );
  exit(0);
}
