import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as paths;

import '../../models/eew_event_group.dart';
import '../../models/station_history_frame.dart';
import '../../models/unified_quake_data.dart';
import 'history_replay.dart';
import 'station_replay_blocks.dart';
import 'station_archive_storage_io.dart' as compression;

const replayFolderLayout = 'files-v1';
const _maxEntryBytes = 128 * 1024 * 1024;
const _maxArchiveBytes = 64 * 1024 * 1024 * 1024;
const _maxEntries = 1001001;

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<String> _writeJson((String, Map<String, dynamic>) request) async {
  final (path, value) = request;
  final bytes = JsonUtf8Encoder().convert(value);
  if (bytes.length > _maxEntryBytes) {
    throw const FormatException('单帧或单报超过 128 MiB');
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  final stored = path.endsWith('.gz') ? compression.compress(bytes) : bytes;
  await file.writeAsBytes(stored, flush: true);
  return sha256.convert(stored).toString();
}

/// Only small path descriptors and the manifest cross into the ZIP worker.
Future<void> _zipFiles((String, List<(String, String)>) request) async {
  final (destination, files) = request;
  final encoder = ZipFileEncoder()..create(destination, level: 1);
  try {
    for (final (source, name) in files) {
      await encoder.addFile(File(source), name, name.endsWith('.gz') ? 0 : 1);
    }
  } finally {
    await encoder.close();
  }
  final handle = await File(destination).open(mode: FileMode.append);
  try {
    await handle.flush();
  } finally {
    await handle.close();
  }
}

/// Sources already on disk are compressed directly; expanded frame graphs are
/// never accumulated. Old in-memory packages are converted one frame at a time.
Future<void> exportReplayDirectory(
  HistoryReplayPackage package,
  String destination, {
  bool directoryOnly = false,
}) async {
  final staging = await Directory.systemTemp.createTemp('rq-replay-export-');
  final target = File(destination);
  final pending = File('$destination.pending');
  final files = <(String, String)>[];
  final reports = <Map<String, dynamic>>[];
  var expandedBytes = 0;
  Future<(String, String, int)> item(
    String? existing,
    String temporary,
    Map<String, dynamic> Function() value,
  ) async {
    final path = existing ?? '${staging.path}/$temporary';
    final digest = existing == null
        ? await compute(_writeJson, (
            path,
            value(),
          ), debugLabel: 'write-one-replay-record')
        : await _digest(File(path));
    final length = await File(path).length();
    if (length > _maxEntryBytes) {
      throw const FormatException('单帧或单报超过 128 MiB');
    }
    expandedBytes += length;
    if (expandedBytes > _maxArchiveBytes) {
      throw const FormatException('回放数据超过 64 GiB');
    }
    return (path, digest, length);
  }

  try {
    for (var i = 0; i < package.reports.length; i++) {
      final report = package.reports[i];
      final ref = package.storedReports?.payloads[report];
      if (ref != null && ref.filePath == null) {
        throw StateError('旧历史报文尚未加载');
      }
      var timing = HistoryReplayPackage.reportTiming(report, ref);
      if (timing.needsPayload) {
        final original = await compute(_readReport, (
          ref!.filePath!,
          ref.fileId!,
        ));
        _validateOriginal(original, historyReportSignature(report));
        timing = HistoryReplayPackage.reportTiming(original);
      }
      final record = await item(ref?.filePath, 'report-$i.json', report.toMap);
      final name = 'reports/${i.toString().padLeft(4, '0')}_${record.$2}.json';
      files.add((record.$1, name));
      reports.add({
        'file': name,
        'sha256': record.$2,
        'bytes': record.$3,
        'signature': historyReportSignature(report),
        'summary': report.copyWith(clearSourcePayload: true).toMap(),
        'reportInstant': timing.instant?.toIso8601String(),
        if (ref?.sasmexFields != null) 'sasmexFields': ref!.sasmexFields,
      });
    }
    var count = 0;
    final identities = <String>{};
    for (final frame in StationReplayFrames.describe(package.stationFrames)) {
      final key = '${frame.receivedAt.microsecondsSinceEpoch}_${frame.kind}';
      if (!identities.add(key)) {
        throw const FormatException('重复的测站帧时间');
      }
      if (++count + reports.length + 1 > _maxEntries) {
        throw const FormatException('回放帧数过多');
      }
      final StationHistoryFrame? loaded = frame.filePath == null
          ? await frame.loadAsync()
          : null;
      final suffix = frame.filePath == null || frame.filePath!.endsWith('.gz')
          ? '.json.gz'
          : '.json';
      final record = await item(
        frame.filePath,
        'frame-$count$suffix',
        () => loaded!.toMap(),
      );
      files.add((record.$1, 'frames/${key}_${record.$2}$suffix'));
    }
    if (package.storedStations?.frameKeys.isNotEmpty ?? false) {
      throw StateError('测站文件索引尚未加载');
    }
    final manifest = {
      'format': HistoryReplayPackage.format,
      'version': 3,
      'layout': replayFolderLayout,
      'name': package.name,
      'reports': reports,
      'frameCount': count,
      'omittedReports': package.omittedReports,
      'arrivalInstantsUtc': package.arrivalInstants
          .map((t) => t?.toIso8601String())
          .toList(),
      if (package.captureEndedAt != null)
        'captureEndedAt': package.captureEndedAt!.toIso8601String(),
    };
    final manifestPath = '${staging.path}/manifest.json';
    await compute(_writeJson, (manifestPath, manifest));
    files.insert(0, (manifestPath, 'manifest.json'));
    if (directoryOnly) {
      final directory = Directory(destination);
      await directory.create(recursive: true);
      if (!await directory.list(followLinks: false).isEmpty) {
        throw StateError('回放转换目录必须为空');
      }
      for (final (source, name) in files) {
        final output = File('$destination/$name');
        await output.parent.create(recursive: true);
        // Only move files created by this export, never an existing raw source.
        if (paths.isWithin(staging.path, source)) {
          await File(source).rename(output.path);
        } else {
          await File(source).copy(output.path);
        }
      }
      return;
    }
    await target.parent.create(recursive: true);
    await compute(_zipFiles, (
      pending.path,
      files,
    ), debugLabel: 'stream-replay-zip');
    await pending.rename(target.path);
  } finally {
    if (await pending.exists()) {
      await pending.delete();
    }
    // createTemp returned this exact owned child; no imported path is deleted.
    await staging.delete(recursive: true);
  }
}

Future<String> _extractReplay((String, String) request) async {
  final (source, root) = request;
  final input = InputFileStream(source);
  try {
    final decoder = ZipDecoder();
    final archive = decoder.decodeStream(input);
    if (decoder.directory.fileHeaders.length != archive.length ||
        archive.length > _maxEntries) {
      throw const FormatException('回放压缩包包含重复文件或文件过多');
    }
    var expanded = 0;
    for (final file in archive.files) {
      if (!file.isFile ||
          file.isSymbolicLink ||
          !(file.name == 'manifest.json' ||
              RegExp(
                r'^reports/\d{4}_[a-f0-9]{64}\.json$',
              ).hasMatch(file.name) ||
              RegExp(
                r'^frames/\d+_(nied|snet|kma|cwa|seisjs|palert|lpgm)_[a-f0-9]{64}\.json(?:\.gz)?$',
              ).hasMatch(file.name))) {
        throw const FormatException('回放压缩包含有无效路径或文件类型');
      }
      expanded += file.size;
      if (file.size > _maxEntryBytes || expanded > _maxArchiveBytes) {
        throw const FormatException('回放解压大小超过限制');
      }
      final destination = File('$root/${file.name}');
      await destination.parent.create(recursive: true);
      final output = OutputFileStream(destination.path);
      try {
        file.writeContent(output);
      } finally {
        await output.close();
      }
      if (await destination.length() != file.size) {
        throw const FormatException('回放文件大小不一致');
      }
      if (file.name != 'manifest.json') {
        final expected = RegExp(
          r'_([a-f0-9]{64})\.json(?:\.gz)?$',
        ).firstMatch(file.name)![1]!;
        if (await _digest(destination) != expected) {
          throw const FormatException('回放文件校验失败');
        }
      }
    }
  } finally {
    await input.close();
  }
  return root;
}

Future<Map<String, dynamic>> _readJson(String path) async {
  final file = File(path);
  if (await file.length() > _maxEntryBytes) {
    throw const FormatException('回放文件过大');
  }
  final raw = await file.readAsBytes();
  final bytes = path.endsWith('.gz')
      ? compression.expand(raw, _maxEntryBytes)
      : raw;
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
}

Future<StationHistoryFrame> _readFrame((String, String) request) async {
  if (await _digest(File(request.$1)) != request.$2) {
    throw const FormatException('测站帧校验失败');
  }
  return StationHistoryFrame.fromMap(await _readJson(request.$1));
}

Future<UnifiedQuakeData> _readReport((String, String) request) async {
  if (await _digest(File(request.$1)) != request.$2) {
    throw const FormatException('回放报文校验失败');
  }
  return UnifiedQuakeData.fromMap(await _readJson(request.$1));
}

void _validateOriginal(UnifiedQuakeData original, String signature) {
  if (historyReportSignature(original) != signature ||
      original.sourcePayload?.isNotEmpty != true) {
    throw const FormatException('回放报文与索引不一致');
  }
}

Future<HistoryReplayPackage> openReplayDirectory(
  String root, {
  bool owned = false,
}) async {
  final manifest = await compute(_readJson, '$root/manifest.json');
  if (manifest['format'] != HistoryReplayPackage.format ||
      manifest['version'] != 3 ||
      manifest['layout'] != replayFolderLayout ||
      manifest['reports'] is! List ||
      manifest['name'] is! String ||
      manifest['frameCount'] is! int ||
      manifest['omittedReports'] is! int) {
    throw const FormatException('不是受支持的文件夹回放格式');
  }
  final values = manifest['reports'] as List;
  if (values.isEmpty || values.length > HistoryReplayPackage.maxReports) {
    throw const FormatException('回放报文数量无效');
  }
  final arrivals = manifest['arrivalInstantsUtc'];
  if (arrivals is! List || arrivals.length != values.length) {
    throw const FormatException('报文接收时间索引无效');
  }
  final reports = <UnifiedQuakeData>[];
  final references = <UnifiedQuakeData, StoredReportPayload>{};
  final files = <String>{'manifest.json'};
  for (final v in values) {
    if (v is! Map ||
        v['file'] is! String ||
        !RegExp(
          r'^reports/\d{4}_[a-f0-9]{64}\.json$',
        ).hasMatch(v['file'] as String) ||
        v['sha256'] is! String ||
        !(v['file'] as String).endsWith('_${v['sha256']}.json') ||
        !files.add(v['file'] as String)) {
      throw const FormatException('报文文件索引无效');
    }
    final report = UnifiedQuakeData.fromMap(
      Map<String, dynamic>.from(v['summary'] as Map),
    );
    final signature = historyReportSignature(report);
    if (report.sourcePayload != null || signature != v['signature']) {
      throw const FormatException('报文摘要校验失败');
    }
    final path = '$root/${v['file']}';
    reports.add(report);
    Future<UnifiedQuakeData> loadOriginal() async {
      final original = await compute(_readReport, (
        path,
        v['sha256'] as String,
      ));
      _validateOriginal(original, signature);
      return original;
    }

    final publication = v['reportInstant'] == null
        ? null
        : DateTime.parse(v['reportInstant'] as String);
    references[report] = StoredReportPayload(
      signature: signature,
      isNotEmpty: true,
      fileId: v['sha256'] as String,
      filePath: path,
      reportInstant: publication,
      sasmexFields: v['sasmexFields'] is Map
          ? Map<String, String>.from(v['sasmexFields'] as Map)
          : null,
      load: loadOriginal,
    );
  }
  final entries = <StationReplayEntry>[];
  final timestamps = <String>{};
  final frames = Directory('$root/frames');
  if (await frames.exists()) {
    await for (final entry in frames.list(followLinks: false)) {
      if (entry is! File) {
        throw const FormatException('测站帧目录含非文件项');
      }
      final name = entry.uri.pathSegments.last;
      final match = RegExp(
        r'^(\d+)_(nied|snet|kma|cwa|seisjs|palert|lpgm)_([a-f0-9]{64})\.json(?:\.gz)?$',
      ).firstMatch(name);
      if (match == null || !timestamps.add('${match[1]}_${match[2]}')) {
        throw const FormatException('测站帧索引冲突');
      }
      final receipt = DateTime.fromMicrosecondsSinceEpoch(
        int.parse(match[1]!),
        isUtc: true,
      );
      final kind = match[2]!;
      final hash = match[3]!;
      files.add('frames/$name');
      entries.add(
        StationReplayEntry.file(
          receipt,
          kind,
          hash,
          filePath: entry.path,
          load: () async {
            final frame = await compute(_readFrame, (entry.path, hash));
            if (frame.receivedAt != receipt || frame.kind != kind) {
              throw const FormatException('测站帧与索引不一致');
            }
            return frame;
          },
        ),
      );
    }
  }
  if (entries.length != manifest['frameCount']) {
    throw const FormatException('测站帧数量不一致');
  }
  await for (final file in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (file is File) {
      final name = file.path
          .substring(Directory(root).path.length + 1)
          .replaceAll('\\', '/');
      if (!files.contains(name)) {
        throw const FormatException('回放包含未索引的文件');
      }
    } else if (file is Link) {
      throw const FormatException('回放目录不允许符号链接');
    }
  }
  for (final name in files) {
    if (!await File('$root/$name').exists()) {
      throw const FormatException('回放缺少文件');
    }
  }
  // Validate the entire directory/file index before opening any old body.
  // Repair only the in-memory publication index, one original at a time;
  // neither original manifests nor report bytes are rewritten/retained.
  for (final report in reports) {
    final ref = references[report]!;
    if (HistoryReplayPackage.reportTiming(report, ref).needsPayload) {
      final publication = HistoryReplayPackage.reportTiming(
        await ref.load!(),
      ).instant;
      references[report] = StoredReportPayload(
        signature: ref.signature,
        isNotEmpty: ref.isNotEmpty,
        fileId: ref.fileId,
        filePath: ref.filePath,
        reportInstant: publication,
        sasmexFields: ref.sasmexFields,
        load: ref.load,
      );
    }
  }
  final package = HistoryReplayPackage.files(
    name: manifest['name'] as String,
    reports: reports,
    storedReports: StoredReportHistory(recordKey: root, payloads: references),
    stationFrames: StationReplayFrames(
      entries..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)),
    ),
    arrivals: arrivals.map<DateTime?>((v) {
      if (v == null) {
        return null;
      }
      final time = v is String ? DateTime.tryParse(v) : null;
      if (time == null || !time.isUtc) {
        throw const FormatException('回放接收时间必须包含时区');
      }
      return time;
    }).toList(),
    omittedReports: manifest['omittedReports'] as int,
    captureEndedAt: manifest['captureEndedAt'] == null
        ? null
        : DateTime.parse(manifest['captureEndedAt'] as String),
  );
  if (owned) {
    package.releaseFiles = () async {
      final directory = Directory(root);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    };
  }
  return package;
}

Future<void> _convertLegacyReplay((String, String) request) async {
  final package = HistoryReplayPackage.decode(
    await File(request.$1).readAsString(encoding: utf8),
  );
  await exportReplayDirectory(package, request.$2, directoryOnly: true);
}

Future<HistoryReplayPackage> importReplayFile(String path) async {
  final handle = await File(path).open();
  late final List<int> magic;
  try {
    magic = await handle.read(4);
  } finally {
    await handle.close();
  }
  if (magic.length >= 4 &&
      magic[0] == 0x50 &&
      magic[1] == 0x4b &&
      magic[2] == 3 &&
      magic[3] == 4) {
    final root = await Directory.systemTemp.createTemp('rq-replay-import-');
    try {
      await compute(_extractReplay, (
        path,
        root.path,
      ), debugLabel: 'extract-replay-files');
      return await openReplayDirectory(root.path, owned: true);
    } catch (_) {
      await root.delete(recursive: true);
      rethrow;
    }
  }
  if (await File(path).length() > HistoryReplayPackage.maxBytes) {
    throw const FormatException('旧 JSON 回放包超过 128 MiB');
  }
  // Compatibility is read-only. New saves/exports always use the directory ZIP.
  final root = await Directory.systemTemp.createTemp('rq-replay-import-');
  try {
    await compute(_convertLegacyReplay, (
      path,
      root.path,
    ), debugLabel: 'convert-legacy-replay-files');
    return await openReplayDirectory(root.path, owned: true);
  } catch (_) {
    await root.delete(recursive: true);
    rethrow;
  }
}
