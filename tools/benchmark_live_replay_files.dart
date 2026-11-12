import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/native_replay_history_files_io.dart';

/// AOT measurement of the production model -> FFI -> bounded Rust writer.
/// Reads unmodified retained frame files; output is a new owned temp child.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Original frame directory required');
  }
  final source = Directory(args.single).absolute;
  final parent = Directory('tmp/replay_stream_aot_20261110').absolute;
  await parent.create(recursive: true);
  final output = await parent.createTemp('files-');
  if (output.path.startsWith('${source.path}${Platform.pathSeparator}')) {
    throw ArgumentError('Output must be outside original data');
  }
  final baselineSessions = NativeReplayHistoryFiles.sessions;
  final writer = NativeReplayHistoryFiles(output.path);
  final samples = <Map<String, dynamic>>[];
  final latencies = <int>[];
  final hashes = <String, String>{};
  final watch = Stopwatch()..start();
  try {
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json.gz')) continue;
      final frame = StationHistoryFrame.fromMap(
        jsonDecode(utf8.decode(gzip.decode(await entity.readAsBytes()))) as Map,
      );
      final key = '${frame.kind}_${frame.receivedAt.microsecondsSinceEpoch}';
      final body = frame.toMap();
      hashes[key] = sha256.convert(JsonUtf8Encoder().convert(body)).toString();
      final accept = Stopwatch()..start();
      writer.acceptFrame(key, body);
      latencies.add(accept.elapsedMicroseconds);
      if (latencies.length % 500 == 0) {
        samples.add({
          'frames': latencies.length,
          'rss': ProcessInfo.currentRss,
          'writer': writer.pendingStatus,
        });
      }
    }
    await writer.flushPending();
    final writeMs = watch.elapsedMilliseconds;
    for (final entry in hashes.entries) {
      final restored = await writer.readFrame(entry.key);
      if (sha256.convert(JsonUtf8Encoder().convert(restored)).toString() !=
          entry.value) {
        throw StateError('Original frame changed: ${entry.key}');
      }
    }
    latencies.sort();
    final metrics = {
      'frames': latencies.length,
      'writeMs': writeMs,
      'readAndVerifyMs': watch.elapsedMilliseconds - writeMs,
      'acceptLatencyUs': {
        'median': latencies[latencies.length ~/ 2],
        'p95': latencies[(latencies.length * .95).floor()],
        'max': latencies.last,
      },
      'rss': ProcessInfo.currentRss,
      'peakRss': ProcessInfo.maxRss,
      'samples': samples,
      'writer': writer.pendingStatus,
    };
    await File(
      '${parent.path}/metrics.json',
    ).writeAsString(jsonEncode(metrics), encoding: utf8, flush: true);
    stdout.writeln(jsonEncode(metrics));
  } finally {
    await writer.flushPending();
    writer.dispose();
    if (NativeReplayHistoryFiles.sessions != baselineSessions ||
        NativeReplayHistoryFiles.results != 0) {
      throw StateError('Replay file owner/results retained after close');
    }
    // This exact createTemp child is owned by this measurement only.
    await output.delete(recursive: true);
  }
}
