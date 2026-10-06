import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/quake_time.dart';
import '../../models/eew_display_duration.dart';
import '../../models/eew_event_group.dart';
import '../../models/station_history_frame.dart';
import '../../models/unified_quake_data.dart';
import '../debug/history_replay.dart';
import '../debug/station_json_archive.dart';
import 'replay_file_export.dart';

(Uint8List, String) _encodeFrames(List<StationHistoryFrame> frames) {
  final bytes = Uint8List.fromList(
    GZipCodec(
      level: 1,
    ).encode(JsonUtf8Encoder().convert(StationJsonArchive.encode(frames))),
  );
  return (bytes, sha256.convert(bytes).toString());
}

class _Capture {
  _Capture(this.group, this.end, this.directory);
  EewEventGroup group;
  DateTime end;
  final Directory directory;
  final List<StationHistoryFrame> pending = [];
  final List<String> chunks = [];
  bool dirty = true;
}

/// Dedicated-process collector. No UI, user preferences or GQ ownership.
/// Checkpoints are independent from the application's history/settings store.
class ReplayCollector {
  static const excludedEventSources = {'globalQuakeEew', 'iclEew'};

  ReplayCollector({
    required this.spool,
    required this.output,
    required Set<String> stations,
    DateTime Function()? now,
    this.maxSpoolBytes = 8 * 1024 * 1024 * 1024,
  }) : stations = Set.unmodifiable(stations),
       _now = now ?? DateTime.now {
    if (!StationHistoryFrame.kinds.containsAll(stations)) {
      throw ArgumentError('Unknown station kind');
    }
    if (spool.absolute.path == output.absolute.path) {
      throw ArgumentError('Spool and output must be separate directories');
    }
  }

  final Directory spool;
  final Directory output;
  final Set<String> stations;
  final DateTime Function() _now;
  final int maxSpoolBytes;
  final Map<String, _Capture> _active = {};
  final Map<String, StationHistoryFrame> _latest = {};
  RandomAccessFile? _lock;
  bool _busy = false;
  bool _accepting = true;
  int get activeCount => _active.length;

  Future<void> open() async {
    await spool.create(recursive: true);
    await output.create(recursive: true);
    _lock = await File(
      '${spool.path}/collector.lock',
    ).open(mode: FileMode.append);
    await _lock!.lock(FileLock.exclusive);
    await for (final entry in spool.list(followLinks: false)) {
      if (entry is! Directory ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(entry.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        continue;
      }
      final manifest = File('${entry.path}/event.json');
      if (!await manifest.exists()) continue;
      final value = jsonDecode(await manifest.readAsString()) as Map;
      final group = EewEventGroup.fromMap(value['group'] as Map);
      if (group.reports.any(
        (report) => excludedEventSources.contains(report.source),
      )) {
        throw StateError('GQ and ICL captures are not permitted');
      }
      final capture = _Capture(
        group,
        DateTime.parse(value['end'] as String),
        entry,
      )..dirty = false;
      for (final name
          in (value['chunks'] as List? ?? const []).cast<String>()) {
        capture.chunks.add(validateChunkName(name));
      }
      _active[_key(group.latest)] = capture;
    }
  }

  static String _key(UnifiedQuakeData event) => sha256
      .convert(utf8.encode(jsonEncode([event.source, event.eventId])))
      .toString();

  static DateTime _end(UnifiedQuakeData event) {
    final arrival = event.arrivedAt!.toUtc();
    final expiry = event.isCanceled
        ? arrival.add(eewDisplayDuration(event))
        : QuakeTime.unifiedInstantUtc(event).add(eewDisplayDuration(event));
    final tail = arrival.add(const Duration(seconds: 30));
    return (expiry.isAfter(tail) ? expiry : tail).add(
      const Duration(seconds: 30),
    );
  }

  bool addEvent(UnifiedQuakeData event) {
    if (!_accepting) throw StateError('Collector is closing');
    if (excludedEventSources.contains(event.source) ||
        !event.isEew ||
        event.isReplay ||
        event.isHistory ||
        event.isEmpty ||
        event.sourcePayload?.isNotEmpty != true ||
        event.originTime == null ||
        event.arrivedAt == null) {
      return false;
    }
    final now = _now().toUtc();
    final origin = QuakeTime.unifiedInstantUtc(event);
    if (origin.isAfter(now.add(const Duration(seconds: 15))) ||
        now.difference(origin) > HistoryReplayPackage.maxDuration) {
      return false;
    }
    // Reconnects and repeated pushes must not revive expired earthquakes.
    if (!event.isCanceled &&
        origin.add(eewDisplayDuration(event)).isBefore(now)) {
      return false;
    }
    final key = _key(event);
    var capture = _active[key];
    if (event.isCanceled && capture == null) {
      final stamp = event.reportTime == null
          ? null
          : QuakeTime.unifiedInstantUtc(event, value: event.reportTime);
      if (stamp == null ||
          stamp.isBefore(origin) ||
          now.difference(stamp) > const Duration(seconds: 60) ||
          stamp.isAfter(now.add(const Duration(seconds: 15)))) {
        return false;
      }
    }
    if (capture != null &&
        capture.group.reports.any(
          (report) =>
              jsonEncode(report.sourcePayload) ==
              jsonEncode(event.sourcePayload),
        )) {
      return false;
    }
    if (capture == null) {
      if (_active.length >= 64) {
        throw StateError('Too many pending captures');
      }
      capture = _Capture(
        EewEventGroup(
          eventId: event.eventId,
          reports: [event],
          firstArrivedAt: event.arrivedAt!.toUtc(),
        ),
        _end(event),
        Directory('${spool.path}/$key'),
      );
      _active[key] = capture;
      for (final frame in _latest.values) {
        final age = now.difference(frame.receivedAt);
        final limit = Duration(seconds: frame.kind == 'snet' ? 180 : 90);
        if (!age.isNegative && age <= limit) capture.pending.add(frame);
      }
    } else {
      if (capture.group.reports.length >= HistoryReplayPackage.maxReports) {
        throw StateError('Too many reports; capture retained');
      }
      capture.group = capture.group.copyWith(
        reports: [event, ...capture.group.reports],
      );
      final end = _end(event);
      if (end.isAfter(capture.end)) capture.end = end;
      capture.dirty = true;
    }
    return true;
  }

  void addStation(StationHistoryFrame frame) {
    if (!_accepting || !stations.contains(frame.kind)) return;
    _latest[frame.kind] = frame;
    for (final capture in _active.values) {
      if (!frame.receivedAt.isAfter(capture.end)) capture.pending.add(frame);
    }
  }

  Future<void> _atomicWrite(File file, String contents) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, encoding: utf8, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _checkpoint(
    _Capture capture,
    List<StationHistoryFrame> frames,
    String? chunk,
  ) async {
    await capture.directory.create(recursive: true);
    if (capture.dirty || chunk != null) {
      final group = capture.group;
      final end = capture.end;
      await _atomicWrite(
        File('${capture.directory.path}/event.json'),
        jsonEncode({
          'group': group.toMap(includeStationFrames: false),
          'end': end.toIso8601String(),
          'chunks': [...capture.chunks, ?chunk],
        }),
      );
      capture.dirty = !identical(group, capture.group) || capture.end != end;
    }
    if (chunk != null) capture.chunks.add(chunk);
    capture.pending.removeRange(0, frames.length);
  }

  Future<void> _checkpointAll() async {
    // Freeze every window before awaiting: overlapping captures share one batch.
    final batches = <(List<StationHistoryFrame>, List<_Capture>)>[];
    for (final capture in _active.values) {
      final frames = List<StationHistoryFrame>.of(capture.pending);
      var found = false;
      for (final batch in batches) {
        if (batch.$1.length == frames.length &&
            frames.indexed.every((e) => identical(e.$2, batch.$1[e.$1]))) {
          batch.$2.add(capture);
          found = true;
          break;
        }
      }
      if (!found) batches.add((frames, [capture]));
    }
    for (final (frames, captures) in batches) {
      String? name;
      if (frames.isNotEmpty) {
        final (bytes, digest) = await compute(_encodeFrames, frames);
        name =
            '${frames.first.receivedAt.microsecondsSinceEpoch}_$digest.stations.json.gz';
        final directory = Directory('${spool.path}/chunks');
        await directory.create(recursive: true);
        final file = File('${directory.path}/$name');
        if (await file.exists()) {
          if (sha256.convert(await file.readAsBytes()).toString() != digest) {
            throw StateError('Station chunk collision; capture retained');
          }
        } else {
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          await temporary.rename(file.path);
        }
      }
      for (final capture in captures) {
        await _checkpoint(capture, frames, name);
      }
    }
  }

  Future<List<File>> tick({bool finalize = true}) async {
    if (_busy) return const [];
    _busy = true;
    try {
      var usage = 0;
      for (final directory in [spool, output]) {
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            try {
              usage += await entity.length();
            } on FileSystemException {
              // The uploader may remove an acknowledged outbox file.
              if (await entity.exists()) rethrow;
            }
          }
        }
      }
      if (usage >= maxSpoolBytes) {
        throw StateError('Spool quota reached; nothing deleted');
      }
      final completed = <File>[];
      await _checkpointAll();
      for (final entry in _active.entries.toList()) {
        final capture = entry.value;
        if (!finalize || _now().toUtc().isBefore(capture.end)) continue;
        final savedReportCount = capture.group.reports.length;
        final (path, hash, _) = await compute(exportCaptureFile, (
          capture.directory.path,
          '${output.path}/${entry.key}.export.tmp',
        ));
        final temporary = File(path);
        // A new report may arrive during encoding and extend the capture.
        if (capture.dirty ||
            capture.pending.isNotEmpty ||
            capture.group.reports.length != savedReportCount) {
          await temporary.delete();
          continue;
        }
        final destination = File(
          '${output.path}/RhythmQuake_${entry.key}_$hash.rqreplay',
        );
        if (await destination.exists()) {
          if ((await sha256.bind(destination.openRead()).first).toString() !=
              hash) {
            throw StateError('Output name collision; capture retained');
          }
        }
        if (capture.dirty ||
            capture.pending.isNotEmpty ||
            capture.group.reports.length != savedReportCount) {
          await temporary.delete();
          continue;
        }
        // No await in this short commit section: a late report cannot mutate
        // a capture between publication and removal from the active map.
        temporary.renameSync(destination.path);
        // Delete only this collector's hash-named capture after durable export.
        capture.directory.deleteSync(recursive: true);
        _active.remove(entry.key);
        final retained = {for (final item in _active.values) ...item.chunks};
        for (final name in capture.chunks) {
          if (!retained.contains(name)) {
            final chunk = File('${spool.path}/chunks/$name');
            if (chunk.existsSync()) chunk.deleteSync();
          }
        }
        completed.add(destination);
      }
      return completed;
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    _accepting = false;
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await tick(finalize: false);
    await _lock?.unlock();
    await _lock?.close();
    _lock = null;
  }
}
