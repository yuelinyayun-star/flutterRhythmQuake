import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/services/sources/native_replay_log_session.dart';
import 'reference_dart_port/nied_replay_archive_reference_20261016.dart';
import 'benchmark_tcp_ingress.dart' show cpu100ns;

const sourceDirectory =
    'tmp/native_replay_logger_baseline_20261016_204500/original';
const source = '$sourceDirectory/nied_replay_20261016_114940.json';
const recordInput = '$sourceDirectory/records.original.bin';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final native = args[0] == 'native';
  final output = Directory(args[1]);
  check(!output.existsSync(), 'Use a fresh isolated output directory');
  output.createSync(recursive: true);
  final headerFile = File(source).openSync();
  final sourcePrefix = utf8.decode(
    headerFile.readSync(512),
    allowMalformed: true,
  );
  headerFile.closeSync();
  final sessionStart = RegExp(
    r'"session_start"\s*:\s*"([^"]+)"',
  ).firstMatch(sourcePrefix)!.group(1)!;
  // Drop the full reference tree before measuring; both sides stream the same
  // unchanged record spans. Validation uses a fresh read AFTER measurement.
  final first = Map<String, dynamic>.from(
    jsonDecode(
          File(
            '$sourceDirectory/capture_first_metadata.json',
          ).readAsStringSync(),
        )
        as Map,
  );
  final gif = File('$sourceDirectory/first.original.gif').readAsBytesSync();
  const stamp = '20261016_114940';
  // Same DLL loaded in both independent AOT processes.
  check(
    NativeReplayLogSession.activeWorkers == 0,
    'Archive worker already exists',
  );
  final nativeOwner = native ? NativeReplayLogSession() : null;
  final dart = native
      ? null
      : DartReplayArchiveReference(output.path, sessionStart, stamp);
  if (nativeOwner != null) {
    nativeOwner.capture({
      'jst': first['jst'],
      'url': first['url'],
      'layer': first['layer'],
      'fallback_name': (first['path'] as String).split('/').last,
    }, gif);
    nativeOwner.start(
      sessionStart: sessionStart,
      stamp: stamp,
      outputDirectory: output.path,
      writeToDisk: true,
    );
    nativeOwner.barrier();
  } else {
    dart!.capture(first, gif);
  }
  final input = File(recordInput).openSync();
  final startRss = ProcessInfo.currentRss;
  var peak = startRss, count = 0, maxSubmitUs = 0, maxSaveUs = 0;
  final submissionTimes = <int>[];
  final saveTimes = <int>[];
  final startCpu = cpu100ns();
  final watch = Stopwatch()..start();
  try {
    while (true) {
      final header = input.readSync(8);
      if (header.isEmpty) break;
      check(header.length == 8, 'Truncated original record header');
      final h = ByteData.sublistView(header),
          size = h.getUint32(0, Endian.little),
          kind = h.getUint32(4, Endian.little);
      final raw = input.readSync(size);
      check(raw.length == size, 'Truncated original record');
      // Producer decode is identical in both modes; the native production
      // bridge also encodes each NEW record once. No accumulated Dart tree.
      final row = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(raw)) as Map,
      );
      final submit = Stopwatch()..start();
      if (nativeOwner != null) {
        nativeOwner.append(kind, row);
      } else {
        dart!.append(row);
      }
      submit.stop();
      submissionTimes.add(submit.elapsedMicroseconds);
      if (submit.elapsedMicroseconds > maxSubmitUs) {
        maxSubmitUs = submit.elapsedMicroseconds;
      }
      count++;
      if (count % 80 == 0) {
        final save = Stopwatch()..start();
        if (nativeOwner != null) {
          nativeOwner.saveSync();
        } else {
          dart!.save();
        }
        save.stop();
        saveTimes.add(save.elapsedMicroseconds);
        if (save.elapsedMicroseconds > maxSaveUs) {
          maxSaveUs = save.elapsedMicroseconds;
        }
      }
      if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
    }
    if (nativeOwner != null) {
      nativeOwner.saveSync();
    } else {
      dart!.save();
    }
    watch.stop();
    final elapsed = watch.elapsedMicroseconds / 1000;
    final cpu = (cpu100ns() - startCpu) / 10000;
    final endRss = ProcessInfo.currentRss;
    if (endRss > peak) peak = endRss;
    final status = nativeOwner?.refreshStatus();
    final path = nativeOwner == null
        ? dart!.logPath
        : status!['log_path'] as String;
    submissionTimes.sort();
    saveTimes.sort();
    // Whole-result equality and byte checks do not contaminate timing/RSS.
    final original = jsonDecode(File(source).readAsStringSync()) as Map;
    final result = jsonDecode(File(path).readAsStringSync()) as Map;
    check(
      jsonEncode(result['frames']) == jsonEncode(original['frames']),
      'Original records changed',
    );
    for (final key in ['frame_count', 'detection_count', 'epicenter_count']) {
      check(result[key] == original[key], 'Archive counter changed: $key');
    }
    final package =
        jsonDecode(
              File(
                '${result['capture_directory']}/nied_replay.json',
              ).readAsStringSync(),
            )
            as Map;
    check(
      jsonEncode(package) == jsonEncode(result),
      'Package and main log disagree',
    );
    final captured = File(
      '${result['capture_directory']}/${first['path']}',
    ).readAsBytesSync();
    check(
      sha256.convert(captured).toString() == sha256.convert(gif).toString(),
      'Original GIF changed',
    );
    nativeOwner?.dispose();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (NativeReplayLogSession.activeWorkers != 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    check(NativeReplayLogSession.activeWorkers == 0, 'Archive worker leaked');
    stdout.writeln(
      jsonEncode({
        'mode': native ? 'native' : 'dart',
        'records': count,
        'elapsedMs': elapsed,
        'processCpuMs': cpu,
        'startRssMiB': startRss / 1048576,
        'peakRssMiB': peak / 1048576,
        'endRssMiB': endRss / 1048576,
        'maxSubmitUs': maxSubmitUs,
        'submitP99Us': submissionTimes[(submissionTimes.length * 0.99).floor()],
        'maxSaveUs': maxSaveUs,
        'saveP99Us': saveTimes[(saveTimes.length * 0.99).floor()],
        'peakQueuedBytes': status?['peak_queued_bytes'],
        'outputBytes': File(path).lengthSync(),
        'originalRecordsEqual': true,
        'originalGifEqual': true,
        'remainingWorkers': NativeReplayLogSession.activeWorkers,
        'inputSha256': sha256
            .convert(File(source).readAsBytesSync())
            .toString(),
      }),
    );
  } finally {
    input.closeSync();
    nativeOwner?.dispose();
  }
}
