import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../../models/eew_event_group.dart';
import '../../models/station_history_frame.dart';
import '../../models/unified_quake_data.dart';
import '../debug/history_replay.dart';
import '../debug/history_replay_directory_io.dart';
import '../debug/station_json_archive.dart';
import '../debug/station_replay_blocks.dart';
import '../debug/station_archive_storage_io.dart' as compression;
import '../replay_history_files.dart';

String validateChunkName(String name) {
  if (!RegExp(r'^\d+_[a-f0-9]{64}\.stations\.json\.gz$').hasMatch(name)) {
    throw const FormatException('Invalid shared station chunk name');
  }
  return name;
}

String validateFrameName(String name) {
  if (!RegExp(
    r'^\d+_(nied|snet|kma|cwa|seisjs|palert|lpgm)_[a-f0-9]{64}\.json(?:\.gz)?$',
  ).hasMatch(name)) {
    throw const FormatException('Invalid station frame file name');
  }
  return name;
}

Future<UnifiedQuakeData> _report(
  String path,
  String digest,
  String signature,
) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
    throw const FormatException('Invalid report file digest');
  }
  final bytes = await File('$path/reports/$digest.json').readAsBytes();
  if (sha256.convert(bytes).toString() != digest) {
    throw const FormatException('Collector report checksum mismatch');
  }
  final report = UnifiedQuakeData.fromMap(
    Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
  );
  if (historyReportSignature(report) != signature) {
    throw const FormatException('Collector report summary mismatch');
  }
  return report;
}

List<Map<String, dynamic>> captureReportIndex(EewEventGroup group) => [
  for (final report in group.reports)
    {
      'fileId': group.storedReports!.payloads[report]!.fileId,
      'signature': group.storedReports!.payloads[report]!.signature,
      'reportInstant': group.storedReports!.payloads[report]!.reportInstant
          ?.toIso8601String(),
    },
];

Future<UnifiedQuakeData> Function() _reportReader(
  String path,
  String digest,
  String signature,
) =>
    () => _report(path, digest, signature);

EewEventGroup restoreCaptureReports(
  EewEventGroup group,
  Map manifest,
  String path,
) {
  if (manifest['folderVersion'] != 1) {
    return group;
  }
  final entries = manifest['reports'] as List;
  if (entries.length != group.reports.length) {
    throw const FormatException('Collector report file count mismatch');
  }
  final refs = <UnifiedQuakeData, StoredReportPayload>{};
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i] as Map;
    final digest = entry['fileId'] as String;
    final signature = entry['signature'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        historyReportSignature(group.reports[i]) != signature) {
      throw const FormatException('Invalid collector report reference');
    }
    refs[group.reports[i]] = StoredReportPayload(
      signature: signature,
      isNotEmpty: true,
      fileId: digest,
      filePath: '$path/reports/$digest.json',
      reportInstant: entry['reportInstant'] == null
          ? null
          : DateTime.parse(entry['reportInstant'] as String),
      load: _reportReader(path, digest, signature),
    );
  }
  return group.copyWith(
    storedReports: StoredReportHistory(recordKey: path, payloads: refs),
  );
}

EewEventGroup saveCaptureReports(
  EewEventGroup group,
  String path,
  ReplayHistoryFiles writer,
  String relativeDirectory,
) {
  final reports = <UnifiedQuakeData>[];
  final refs = <UnifiedQuakeData, StoredReportPayload>{};
  for (final report in group.reports) {
    final previous = group.storedReports?.payloads[report];
    if (previous != null) {
      reports.add(report);
      refs[report] = previous;
      continue;
    }
    final name = writer.acceptCollectorJson(
      '$relativeDirectory/reports',
      '',
      report.toMap(),
    );
    final digest = name.substring(0, 64);
    final signature = historyReportSignature(report);
    final file = File('$path/reports/$digest.json');
    final summary = report.copyWith(clearSourcePayload: true);
    reports.add(summary);
    refs[summary] = StoredReportPayload(
      signature: signature,
      isNotEmpty: report.sourcePayload?.isNotEmpty == true,
      fileId: digest,
      filePath: file.path,
      reportInstant: HistoryReplayPackage.reportInstant(report),
      load: _reportReader(path, digest, signature),
    );
  }
  return group.copyWith(
    reports: reports,
    storedReports: StoredReportHistory(recordKey: path, payloads: refs),
  );
}

StationReplayEntry _frameEntry(File file, String name) {
  validateFrameName(name);
  final parts = name.split('_');
  final receipt = DateTime.fromMicrosecondsSinceEpoch(
    int.parse(parts[0]),
    isUtc: true,
  );
  final kind = parts[1];
  final hash = parts[2].substring(0, 64);
  return StationReplayEntry.file(
    receipt,
    kind,
    hash,
    filePath: file.path,
    load: () async {
      final bytes = await file.readAsBytes();
      if (sha256.convert(bytes).toString() != hash) {
        throw const FormatException('Collector frame checksum mismatch');
      }
      final expanded = file.path.endsWith('.gz')
          ? compression.expand(bytes, HistoryReplayPackage.maxBytes)
          : bytes;
      final frame = StationHistoryFrame.fromMap(
        jsonDecode(utf8.decode(expanded)) as Map,
      );
      if (frame.kind != kind || frame.receivedAt != receipt) {
        throw const FormatException('Collector frame index mismatch');
      }
      return frame;
    },
  );
}

/// One file per report/frame, compressed only for the final portable export.
Future<(String, String, int)> exportCaptureFile(
  (String, String) request,
) async {
  final (path, destination) = request;
  final manifest =
      jsonDecode(await File('$path/event.json').readAsString(encoding: utf8))
          as Map;
  var group = restoreCaptureReports(
    EewEventGroup.fromMap(manifest['group'] as Map),
    manifest,
    path,
  ).copyWith(captureEndedAt: DateTime.parse(manifest['end'] as String));
  final frames = <StationReplayEntry>[];
  for (final name in (manifest['frames'] as List? ?? const []).cast<String>()) {
    frames.add(
      _frameEntry(
        File(
          '${Directory(path).parent.path}/frames/${validateFrameName(name)}',
        ),
        name,
      ),
    );
  }
  // Old collector checkpoints are converted one legacy chunk at a time.
  final legacy = await Directory(path)
      .list(followLinks: false)
      .where((e) => e is File && e.path.endsWith('.stations.json'))
      .cast<File>()
      .toList();
  for (final name in (manifest['chunks'] as List? ?? const []).cast<String>()) {
    legacy.add(
      File('${Directory(path).parent.path}/chunks/${validateChunkName(name)}'),
    );
  }
  for (final file in legacy) {
    final bytes = await file.readAsBytes();
    final table =
        jsonDecode(
              utf8.decode(
                file.path.endsWith('.gz')
                    ? compression.expand(bytes, HistoryReplayPackage.maxBytes)
                    : bytes,
              ),
            )
            as Map;
    for (final frame in StationJsonArchive.decode(table)) {
      final raw = JsonUtf8Encoder().convert(frame.toMap());
      final digest = sha256.convert(raw).toString();
      final name =
          '${frame.receivedAt.microsecondsSinceEpoch}_${frame.kind}_$digest.json';
      final converted = File('$path/converted-frames/$name');
      await converted.parent.create(recursive: true);
      if (!await converted.exists()) {
        await converted.writeAsBytes(raw, flush: true);
      }
      frames.add(_frameEntry(converted, name));
    }
  }
  group = group.copyWith(
    stationFrames: StationReplayFrames(
      frames..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)),
    ),
  );
  await exportReplayDirectory(
    HistoryReplayPackage.fromGroup(group),
    destination,
  );
  final file = File(destination);
  return (
    destination,
    (await sha256.bind(file.openRead()).first).toString(),
    await file.length(),
  );
}
