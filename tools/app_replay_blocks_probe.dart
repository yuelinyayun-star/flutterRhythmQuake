import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/debug/station_replay_blocks.dart';
import 'package:flutterrhythmquake/services/debug/replay_station_display.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage_io.dart'
    as compression;

HistoryReplayPackage readReplay(String path) =>
    HistoryReplayPackage.decode(File(path).readAsStringSync(encoding: utf8));

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const SizedBox.shrink());
    final directory = Directory(Platform.environment['RQ_REPLAY_PROBE_INPUT']!);
    final files = await directory
        .list()
        .where((e) => e is File && e.path.endsWith('.rqreplay'))
        .cast<File>()
        .toList();
    if (files.isEmpty) {
      throw StateError('Original verified replay files required');
    }
    final results = <Map<String, dynamic>>[];
    for (final file in files) {
      final watch = Stopwatch()..start();
      stdout.writeln(
        jsonEncode({
          'phase': 'import',
          'file': file.path,
          'rssBytes': ProcessInfo.currentRss,
        }),
      );
      final package = await compute(readReplay, file.path);
      final importMs = watch.elapsedMilliseconds;
      if (package.stationFrames is! StationReplayFrames) {
        throw StateError('Compressed archive required');
      }
      final frames = package.stationFrames as StationReplayFrames;
      stdout.writeln(
        jsonEncode({
          'phase': 'decode-playback',
          'rssBytes': ProcessInfo.currentRss,
        }),
      );
      final actual = <String, int>{};
      final kinds = <String, int>{};
      final display = ReplayStationDisplay();
      for (final frame in frames) {
        final hash = sha256
            .convert(JsonUtf8Encoder().convert(frame.toMap()))
            .toString();
        actual.update(hash, (v) => v + 1, ifAbsent: () => 1);
        kinds.update(frame.kind, (v) => v + 1, ifAbsent: () => 1);
        display.update({frame.kind: frame});
      }
      final playbackMs = watch.elapsedMilliseconds - importMs;
      frames.release();
      display.update({});
      stdout.writeln(
        jsonEncode({
          'phase': 'verify-original',
          'rssBytes': ProcessInfo.currentRss,
        }),
      );
      final expected = <String, int>{};
      for (final block in frames.archive!['blocks'] as List) {
        final table =
            jsonDecode(
                  utf8.decode(
                    compression.expand(
                      base64.decode(block['data'] as String),
                      HistoryReplayPackage.maxBytes,
                    ),
                  ),
                )
                as Map;
        for (final frame in StationJsonArchive.decode(table)) {
          final hash = sha256
              .convert(JsonUtf8Encoder().convert(frame.toMap()))
              .toString();
          expected.update(hash, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      if (actual.length != expected.length ||
          actual.entries.any((e) => expected[e.key] != e.value)) {
        throw StateError(
          'Decoded full frame JSON differs from original block JSON',
        );
      }
      results.add({
        'file': file.path,
        'bytes': await file.length(),
        'importMs': importMs,
        'decodeAndDisplayMs': playbackMs,
        'verificationMs': watch.elapsedMilliseconds - importMs - playbackMs,
        'frames': frames.length,
        'kinds': kinds,
        'fullFrameJsonHashMatch': true,
        'durationSeconds': package.playbackDuration.inSeconds,
      });
    }
    stdout.writeln(
      jsonEncode({
        'phase': 'done',
        'results': results,
        'rssBytes': ProcessInfo.currentRss,
      }),
    );
    exit(0);
  } catch (error, stack) {
    stdout.writeln(jsonEncode({'phase': 'failed', 'error': error.toString()}));
    stderr.writeln(stack);
    exit(1);
  }
}
