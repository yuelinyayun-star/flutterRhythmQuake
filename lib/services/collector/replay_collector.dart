import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/quake_time.dart';
import '../../core/utils/replay_event_name.dart';
import '../../models/eew_display_duration.dart';
import '../../models/eew_event_group.dart';
import '../../models/station_history_frame.dart';
import '../../models/unified_quake_data.dart';
import '../debug/history_replay.dart';
import '../native_replay_history_files_io.dart';
import '../replay_history_files.dart';
import 'replay_file_export.dart';

class _Capture {
  _Capture(this.group, this.end, this.directory);
  EewEventGroup group;
  DateTime end;
  final Directory directory;
  final List<String> chunks = [];
  final List<String> frameFiles = [];
  final Set<String> frameSet = {};
  final Set<String> payloadHashes = {};
  bool dirty = true;
  int revision = 0;
  void addFrame(String name) {
    if (!frameSet.add(name)) return;
    frameFiles.add(name);
    dirty = true;
    revision++;
  }
}

class _LatestFrame {
  _LatestFrame(this.name, this.receivedAt, this.kind) : seed = null;
  _LatestFrame.seed(StationHistoryFrame frame)
    : name = null,
      receivedAt = frame.receivedAt,
      kind = frame.kind,
      seed = frame;
  final String? name;
  final String kind;
  final DateTime receivedAt;
  final StationHistoryFrame? seed;
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
  final Map<String, _LatestFrame> _latest = {};
  final Set<String> _obsoleteLatest = {};
  late ReplayHistoryFiles _writer;
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
    _writer = NativeReplayHistoryFiles.supported
        ? NativeReplayHistoryFiles(spool.absolute.path)
        : ReplayHistoryFiles(spool.absolute.path);
    await for (final entry in spool.list(followLinks: false)) {
      if (entry is! Directory ||
          !RegExp(
            r'^(?:.+_)?[a-f0-9]{64}$',
          ).hasMatch(entry.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        continue;
      }
      final manifest = File('${entry.path}/event.json');
      if (!await manifest.exists()) {
        continue;
      }
      final value = jsonDecode(await manifest.readAsString()) as Map;
      final group = EewEventGroup.fromMap(value['group'] as Map);
      if (group.reports.any(
        (report) => excludedEventSources.contains(report.source),
      )) {
        throw StateError('GQ and ICL captures are not permitted');
      }
      final capture = _Capture(
        restoreCaptureReports(group, value, entry.path),
        DateTime.parse(value['end'] as String),
        entry,
      )..dirty = false;
      capture.frameFiles.addAll(
        (value['frames'] as List? ?? const []).cast<String>().map(
          validateFrameName,
        ),
      );
      capture.frameSet.addAll(capture.frameFiles);
      capture.payloadHashes.addAll(
        (value['payloadHashes'] as List? ?? const []).cast<String>(),
      );
      for (final report in group.reports) {
        if (report.sourcePayload != null) {
          capture.payloadHashes.add(
            sha256
                .convert(JsonUtf8Encoder().convert(report.sourcePayload))
                .toString(),
          );
        }
      }
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
    if (!_accepting) {
      throw StateError('Collector is closing');
    }
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
    final payloadHash = sha256
        .convert(JsonUtf8Encoder().convert(event.sourcePayload))
        .toString();
    if (capture != null && capture.payloadHashes.contains(payloadHash)) {
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
        Directory('${spool.path}/${replayEventName(event)}_$key'),
      );
      _active[key] = capture;
      for (final frame in _latest.values.toList()) {
        final age = now.difference(frame.receivedAt);
        final limit = Duration(seconds: frame.kind == 'snet' ? 180 : 90);
        if (!age.isNegative && age <= limit) {
          var name = frame.name;
          if (name == null) {
            name = _writer.acceptCollectorFrame(
              '${frame.receivedAt.microsecondsSinceEpoch}_${frame.kind}_',
              frame.seed!.toMap(),
            );
            _latest[frame.kind] = _LatestFrame(
              name,
              frame.receivedAt,
              frame.kind,
            );
          }
          capture.addFrame(name);
        }
      }
    } else {
      if (capture.group.reports.length >= HistoryReplayPackage.maxReports) {
        throw StateError('Too many reports; capture retained');
      }
      capture.group = capture.group.copyWith(
        reports: [event, ...capture.group.reports],
      );
      final end = _end(event);
      if (end.isAfter(capture.end)) {
        capture.end = end;
      }
      capture.dirty = true;
    }
    capture.group = saveCaptureReports(
      capture.group,
      capture.directory.path,
      _writer,
      capture.directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
    );
    capture.revision++;
    capture.dirty = true;
    capture.payloadHashes.add(payloadHash);
    return true;
  }

  void addStation(StationHistoryFrame frame) {
    if (!_accepting || !stations.contains(frame.kind)) {
      return;
    }
    if (_active.isEmpty) {
      final previous = _latest[frame.kind]?.name;
      if (previous != null) _obsoleteLatest.add(previous);
      // Preserve the existing idle policy: no station files without an event.
      // At most one seed per enabled kind, never an accumulating frame list.
      _latest[frame.kind] = _LatestFrame.seed(frame);
      return;
    }
    final name = _writer.acceptCollectorFrame(
      '${frame.receivedAt.microsecondsSinceEpoch}_${frame.kind}_',
      frame.toMap(),
    );
    final previous = _latest[frame.kind];
    if (previous?.name != null && previous!.name != name) {
      _obsoleteLatest.add(previous.name!);
    }
    _latest[frame.kind] = _LatestFrame(name, frame.receivedAt, frame.kind);
    for (final capture in _active.values.toList()) {
      if (!frame.receivedAt.isAfter(capture.end)) {
        capture.addFrame(name);
      }
    }
  }

  Future<void> _atomicWrite(File file, String contents) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, encoding: utf8, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _checkpoint(_Capture capture) async {
    await capture.directory.create(recursive: true);
    if (capture.dirty) {
      await _writer.flushPending();
      final group = capture.group;
      final end = capture.end;
      final revision = capture.revision;
      await _atomicWrite(
        File('${capture.directory.path}/event.json'),
        jsonEncode({
          'folderVersion': 1,
          'group': group.toMap(includeStationFrames: false, summaryOnly: true),
          'reports': captureReportIndex(group),
          'end': end.toIso8601String(),
          'chunks': capture.chunks,
          'frames': capture.frameFiles,
          'payloadHashes': capture.payloadHashes.toList(),
        }),
      );
      capture.dirty = capture.revision != revision;
    }
  }

  Future<void> _checkpointAll() async {
    await _writer.flushPending();
    final now = _now().toUtc();
    _latest.removeWhere((kind, frame) {
      final expired =
          now.difference(frame.receivedAt) >
          Duration(seconds: kind == 'snet' ? 180 : 90);
      if (expired && frame.name != null) _obsoleteLatest.add(frame.name!);
      return expired;
    });
    for (final capture in _active.values.toList()) {
      await _checkpoint(capture);
    }
    final retained = {
      for (final capture in _active.values) ...capture.frameFiles,
      for (final frame in _latest.values)
        if (frame.name != null) frame.name!,
    };
    for (final name in _obsoleteLatest.toList()) {
      if (!retained.contains(name)) {
        final file = File('${spool.path}/frames/${validateFrameName(name)}');
        if (await file.exists()) await file.delete();
      }
      // Active captures now own their files; a later latest replacement will
      // re-register its old name. Do not build a second full frame-name queue.
      _obsoleteLatest.remove(name);
    }
  }

  Future<List<File>> tick({bool finalize = true}) async {
    if (_busy) {
      return const [];
    }
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
              if (await entity.exists()) {
                rethrow;
              }
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
        if (!finalize || _now().toUtc().isBefore(capture.end)) {
          continue;
        }
        final savedReportCount = capture.group.reports.length;
        final (path, hash, _) = await compute(exportCaptureFile, (
          capture.directory.path,
          '${output.path}/${entry.key}.export.tmp',
        ));
        final temporary = File(path);
        // A new report may arrive during encoding and extend the capture.
        if (capture.dirty || capture.group.reports.length != savedReportCount) {
          await temporary.delete();
          continue;
        }
        final destination = File(
          '${output.path}/${replayEventName(capture.group.latest)}_$hash.rqreplay',
        );
        if (await destination.exists()) {
          if ((await sha256.bind(destination.openRead()).first).toString() !=
              hash) {
            throw StateError('Output name collision; capture retained');
          }
        }
        if (capture.dirty || capture.group.reports.length != savedReportCount) {
          await temporary.delete();
          continue;
        }
        // No await in this short commit section: a late report cannot mutate
        // a capture between publication and removal from the active map.
        temporary.renameSync(destination.path);
        // Delete only this collector's capture after durable export.
        capture.directory.deleteSync(recursive: true);
        _active.remove(entry.key);
        final retained = {for (final item in _active.values) ...item.chunks};
        for (final name in capture.chunks) {
          if (!retained.contains(name)) {
            final chunk = File('${spool.path}/chunks/$name');
            if (chunk.existsSync()) {
              chunk.deleteSync();
            }
          }
        }
        final retainedFrames = {
          for (final item in _active.values) ...item.frameFiles,
          for (final frame in _latest.values)
            if (frame.name != null) frame.name!,
        };
        for (final name in capture.frameFiles) {
          if (!retainedFrames.contains(name)) {
            final frame = File(
              '${spool.path}/frames/${validateFrameName(name)}',
            );
            if (frame.existsSync()) {
              frame.deleteSync();
            }
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
    if (_lock == null) return;
    _accepting = false;
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _obsoleteLatest.addAll(
      _latest.values.map((f) => f.name).whereType<String>(),
    );
    _latest.clear();
    await tick(finalize: false);
    await _writer.flushPending();
    _writer.dispose();
    await _lock?.unlock();
    await _lock?.close();
    _lock = null;
  }
}
