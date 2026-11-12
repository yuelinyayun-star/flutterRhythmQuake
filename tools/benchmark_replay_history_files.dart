import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:flutterrhythmquake/services/native_replay_history_files_io.dart';
import 'package:flutterrhythmquake/services/replay_history_files.dart';

/// Standalone AOT component benchmark over retained, unchanged frame files.
/// Each invocation owns a fresh tmp output; source archives are read-only.
Future<void> main(List<String> args) async {
  if (args.length != 3 || !{'dart', 'native'}.contains(args[0])) {
    throw ArgumentError(
      'mode, frozen original-file index, new workspace tmp root',
    );
  }
  final output = Directory(args[2]).absolute;
  final allowed = Directory('tmp/native_history_files_20261023').absolute;
  if (!path.isWithin(allowed.path, output.path) || output.existsSync()) {
    throw ArgumentError('A new isolated workspace tmp output is required');
  }
  final selected =
      jsonDecode(await File(args[1]).readAsString(encoding: utf8)) as Map;
  final frames = <Map<String, dynamic>>[];
  final checksums = <String>[];
  final counts = <String, int>{};
  for (final entry in selected['frames'] as List) {
    final encoded = await File(entry['path'] as String).readAsBytes();
    if (sha256.convert(encoded).toString() != entry['gzipSha256']) {
      throw StateError('Original benchmark input changed');
    }
    final json = gzip.decode(encoded);
    final frame = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(json)) as Map,
    );
    final kind = (frame['snapshot'] as Map)['kind'] as String;
    counts[kind] = (counts[kind] ?? 0) + 1;
    frames.add(frame);
    checksums.add(sha256.convert(JsonUtf8Encoder().convert(frame)).toString());
  }
  if (frames.isEmpty) {
    throw StateError('No retained original station frames');
  }
  // Load the DLL in both processes so its initial mapping is not a mode bias.
  final baselineSessions = NativeReplayHistoryFiles.sessions;
  final backend = args[0] == 'native'
      ? NativeReplayHistoryFiles(output.path)
      : ReplayHistoryFiles(output.path);
  final baselineRss = ProcessInfo.currentRss;
  var writeUs = 0, duplicateUs = 0, readUs = 0, files = 0;
  try {
    for (var round = 0; round < 5; round++) {
      for (var i = 0; i < frames.length; i++) {
        final key = 'frame_${round}_$i';
        final watch = Stopwatch()..start();
        await backend.writeFrame(key, frames[i]);
        writeUs += watch.elapsedMicroseconds;
        watch.reset();
        await backend.writeFrame(key, frames[i]);
        duplicateUs += watch.elapsedMicroseconds;
        watch.reset();
        final restored = await backend.readFrame(key);
        readUs += watch.elapsedMicroseconds;
        final checksum = sha256
            .convert(JsonUtf8Encoder().convert(restored))
            .toString();
        if (checksum != checksums[i]) {
          throw StateError('Original complete JSON mismatch at $key');
        }
        files++;
      }
    }
  } finally {
    if (backend is NativeReplayHistoryFiles) {
      backend.dispose();
    }
  }
  if (NativeReplayHistoryFiles.results != 0 ||
      NativeReplayHistoryFiles.sessions != baselineSessions) {
    throw StateError('Native replay storage resources retained');
  }
  final result = {
    'mode': args[0],
    'sourceKinds': counts,
    'files': files,
    'writeMicroseconds': writeUs,
    'duplicateMicroseconds': duplicateUs,
    'readMicroseconds': readUs,
    'baselineRss': baselineRss,
    'finalRss': ProcessInfo.currentRss,
    'peakRss': ProcessInfo.maxRss,
    'nativeResults': NativeReplayHistoryFiles.results,
    'nativeSessions': NativeReplayHistoryFiles.sessions,
    'originalJsonSha256': checksums,
  };
  await File(
    '${output.path}/metrics.json',
  ).writeAsString(jsonEncode(result), encoding: utf8, flush: true);
  stdout.writeln(jsonEncode(result));
}
