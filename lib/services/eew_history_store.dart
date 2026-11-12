import 'dart:convert';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eew_event_group.dart';
import '../models/source_payload.dart';
import '../models/station_history_frame.dart';
import '../models/unified_quake_data.dart';
import '../models/unified_event_presentation.dart';
import '../core/utils/quake_time.dart';
import 'quake_event_adapter.dart';
import 'debug/station_json_archive.dart';
import 'debug/native_station_archive.dart';
import 'debug/station_archive_storage.dart';
import 'debug/station_replay_blocks.dart';
import 'debug/station_archive_storage_web.dart'
    if (dart.library.io) 'debug/station_archive_storage_io.dart'
    as compression;
import 'history_storage.dart';

List<EewEventGroup> _decodeLegacyHistory(String text) =>
    (jsonDecode(text) as List)
        .map((value) => EewEventGroup.fromMap(value as Map))
        .toList();

List<StationHistoryFrame> _decodeLegacyStationFile(String text) {
  final value = StationArchiveStorage.decode(text);
  return value['format'] == StationJsonArchive.format
      ? StationJsonArchive.decode(value)
      : [StationHistoryFrame.fromMap(value)];
}

// Bind file metadata in its own synchronous scope. A stored loader must not
// retain the asynchronous save/load operation's expanded event/frame locals.
Future<StationHistoryFrame> Function() _frameFileReader(
  HistoryFileStorage storage,
  String key,
  String kind,
  DateTime receipt,
) => () async {
  final frame = await storage.readFrame(key);
  if (frame.kind != kind || frame.receivedAt != receipt) {
    throw const FormatException('Saved frame identity mismatch');
  }
  return frame;
};

Map<String, dynamic> _indexStoredFrames(Map<String, String> values) => {
  'format': StationReplayFrames.format,
  'blocks': [
    for (final text in values.values)
      () {
        final encoded = StationArchiveStorage.decode(text);
        if (encoded['format'] == StationJsonArchive.format) {
          return StationReplayFrames.encodeBlock(
            encoded,
            text.startsWith(StationArchiveStorage.prefix)
                ? base64.decode(
                    text.substring(StationArchiveStorage.prefix.length),
                  )
                : compression.compress(utf8.encode(text)),
          );
        }
        final table = StationJsonArchive.encode([
          StationHistoryFrame.fromMap(encoded),
        ]);
        return StationReplayFrames.encodeBlock(
          table,
          compression.compress(JsonUtf8Encoder().convert(table)),
        );
      }(),
  ],
};

Map<String, String> _encodeStationHistoryArchives(
  Map<String, List<StationHistoryFrame>> archives,
) => {
  for (final entry in archives.entries)
    entry.key: NativeStationArchive.supported
        ? StationArchiveStorage.wrapCompressed(
            NativeStationArchive.encodeCompressed([
              for (final frame in entry.value) frame.toMap(),
            ]),
          )
        : StationArchiveStorage.encode(StationJsonArchive.encode(entry.value)),
};

/// Incremental event storage; the old single JSON list is read-only migration.
class _FrameIndex {
  _FrameIndex(Iterable<String> initial) {
    for (final key in initial) {
      add(key);
    }
  }
  final keys = <String>[];
  final positions = <String, int>{};
  void add(String key) {
    if (positions.containsKey(key)) return;
    positions[key] = keys.length;
    keys.add(key);
  }
}

/// Immutable-length view over an append-only index. An arriving frame does
/// not copy all preceding keys, and an in-flight manifest keeps its own length.
class _FrameKeys extends ListBase<String> {
  _FrameKeys(this.index) : _length = index.keys.length;
  final _FrameIndex index;
  final int _length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Read-only history index');
  @override
  String operator [](int i) {
    RangeError.checkValidIndex(i, this);
    return index.keys[i];
  }

  @override
  void operator []=(int i, String value) =>
      throw UnsupportedError('Read-only history index');
  @override
  bool contains(Object? value) {
    final position = index.positions[value];
    return position != null && position < length;
  }
}

class EewHistoryStore {
  static const _archivesPerBatch = 1;
  final String preferenceKey;
  bool _canRemoveLegacy = true;
  final Map<String, StoredStationHistory> _diskRefs = {};
  final Map<String, Digest> _recordDigests = {};
  final Map<String, Map<String, StoredReportPayload>> _fileReports = {};
  final Set<String> _folderRecords = {};
  final Set<String> _migratedArchives = {};
  List<String>? _persistedIndex;
  HistoryStorage? _storage;
  final _liveIndices = <String, _FrameIndex>{};
  final _acceptedFrames = <String>{};
  final _receiptRevisions = <String, int>{};
  final _liveReportSignatures = <String, Set<String>>{};
  // Weak keys: remembering a durable group must not retain its expanded raw
  // payload after the provider replaces it with the compact historical copy.
  final _savedGroups = Expando<bool>('durable-history');
  final _releasedGroups = Expando<EewEventGroup>('compact-history');
  final _deferredGroups = Expando<EewEventGroup>('deferred-history');
  final Map<EewEventGroup, Future<EewEventGroup>> _reportLoads = Map.identity();
  static const _snapshotFormat = 'rhythmquake-history-snapshot-v1';
  static const _snapshotPresentationVersion = 1;

  EewHistoryStore({required this.preferenceKey, HistoryStorage? storage})
    : _storage = storage ?? standaloneHistoryStorage();
  bool get supportsDeferredReports => _storage is HistorySnapshotStorage;
  bool get streamsOriginals => _storage is HistoryStreamingStorage;
  Map<String, dynamic> get pendingFileWrites =>
      _storage is HistoryStreamingStorage
      ? (_storage as HistoryStreamingStorage).pendingStatus
      : const {};

  Future<void> flushFiles() async {
    final storage = _storage;
    if (storage is HistoryStreamingStorage) {
      await (storage as HistoryStreamingStorage).flushPending();
    }
  }

  Future<void> close() async {
    final storage = _storage;
    if (storage is HistoryStreamingStorage) {
      await (storage as HistoryStreamingStorage).close();
    }
  }

  /// Called on receipt, before any asynchronous save. The model is serialized
  /// once and transferred to the bounded native file owner, never queued here.
  EewEventGroup acceptFrame(EewEventGroup group, StationHistoryFrame frame) {
    final storage = _storage;
    if (storage is! HistoryStreamingStorage) {
      return group.copyWith(stationFrames: [...group.stationFrames, frame]);
    }
    final files = storage as HistoryStreamingStorage;
    final record = recordKey(group);
    final key = _frameKey(frame);
    final index = _liveIndices.putIfAbsent(
      record,
      () => _FrameIndex({
        ...?_diskRefs[record]?.frameKeys,
        ...?group.storedStations?.frameKeys,
      }),
    );
    if (index.positions.containsKey(key)) return group;
    if (!_acceptedFrames.contains(key)) {
      files.acceptFrame(key, frame.toMap());
      _acceptedFrames.add(key);
    }
    index.add(key);
    _receiptRevisions[record] = (_receiptRevisions[record] ?? 0) + 1;
    final prior = _diskRefs[record] ?? group.storedStations;
    final refs = StoredStationHistory(
      frameKeys: _FrameKeys(index),
      archiveKeys: prior?.archiveKeys ?? const [],
      standaloneFrameKeys: prior?.standaloneFrameKeys ?? const [],
      files: true,
    );
    _diskRefs[record] = refs;
    return group.copyWith(storedStations: refs);
  }

  /// Only the history copy is compacted. Active EEW/UI reports keep their
  /// original payload; no event classification or matching happens here.
  EewEventGroup acceptReports(EewEventGroup group) {
    final storage = _storage;
    if (storage is! HistoryStreamingStorage) return group;
    final files = storage as HistoryStreamingStorage;
    final key = recordKey(group);
    for (final report in group.reports) {
      if (report.sourcePayload == null ||
          group.storedReports?.payloads.containsKey(report) == true) {
        continue;
      }
      final signature = _reportSignature(report);
      final id = files.acceptReport(key, report.toMap());
      _receiptRevisions[key] = (_receiptRevisions[key] ?? 0) + 1;
      (_fileReports[key] ??= {})[signature] = StoredReportPayload(
        signature: signature,
        isNotEmpty: report.sourcePayload!.isNotEmpty,
        fileId: id,
        filePath: files.reportPath(key, id),
        load: _reportFileReader(key, id, signature),
      );
    }
    final result = _deferReports(group, key);
    final retained = _liveReportSignatures[key] = {
      for (final report in result.reports)
        result.storedReports?.payloads[report]?.signature ??
            _reportSignature(report),
    };
    _fileReports[key]?.removeWhere(
      (signature, _) => !retained.contains(signature),
    );
    return result;
  }

  String get indexKey => '${preferenceKey}_index_v2';

  /// Deterministic record identity shared by both isolates. The recording
  /// owner in the background engine must derive the same key without a group.
  static String recordKeyFor(
    String preferenceKey,
    String source,
    String eventId,
  ) {
    final identity = jsonEncode([source, eventId]);
    return '${preferenceKey}_event_${base64Url.encode(utf8.encode(identity))}';
  }

  String _frameKey(StationHistoryFrame frame) =>
      '${preferenceKey}_station_${frame.kind}_${frame.receivedAt.microsecondsSinceEpoch}';

  String _archiveKey(StationHistoryFrame frame) =>
      '${preferenceKey}_station_archive_${frame.kind}_${frame.receivedAt.millisecondsSinceEpoch ~/ 30000}';

  String recordKey(EewEventGroup group) =>
      recordKeyFor(preferenceKey, group.latest.source, group.eventId);

  String _reportSignature(UnifiedQuakeData report) =>
      historyReportSignature(report);

  EewEventGroup _deferReports(EewEventGroup group, String key) {
    final reports = <UnifiedQuakeData>[];
    final references = <UnifiedQuakeData, StoredReportPayload>{};
    for (final report in group.reports) {
      final previous = group.storedReports?.payloads[report];
      if (previous != null) {
        reports.add(report);
        final file = _fileReports[key]?[previous.signature];
        references[report] = previous.fileId == null && file?.fileId != null
            ? StoredReportPayload(
                signature: previous.signature,
                isNotEmpty: previous.isNotEmpty,
                reportInstant: previous.reportInstant,
                sasmexFields: previous.sasmexFields,
                fileId: file!.fileId,
                filePath: file.filePath,
                load: file.load,
              )
            : previous;
      } else if (report.sourcePayload != null) {
        final snapshot = report.copyWith(
          clearSourcePayload: true,
          displayEstimatedIntensity: estimatedEewIntensityValue(report),
          displayEstimateResolved: true,
        );
        final time =
            report.reportTime ??
            QuakeEventAdapter.savedReportTime(
              report.sourcePayload!,
              report.timeZone,
            );
        reports.add(snapshot);
        references[snapshot] = StoredReportPayload(
          signature: _reportSignature(snapshot),
          fileId: _fileReports[key]?[_reportSignature(snapshot)]?.fileId,
          filePath: _fileReports[key]?[_reportSignature(snapshot)]?.filePath,
          load: _fileReports[key]?[_reportSignature(snapshot)]?.load,
          isNotEmpty: report.sourcePayload!.isNotEmpty,
          sasmexFields: report.source == 'sasmex'
              ? {
                  for (final key in const ['msgType', 'severity'])
                    if (report.sourcePayload![key] is String)
                      key: report.sourcePayload![key] as String,
                }
              : null,
          reportInstant: time == null
              ? null
              : QuakeTime.unifiedInstantUtc(report, value: time),
        );
      } else {
        reports.add(report);
      }
    }
    return group.copyWith(
      reports: List.unmodifiable(reports),
      storedReports: references.isEmpty
          ? null
          : StoredReportHistory(recordKey: key, payloads: references),
      clearStoredReports: references.isEmpty,
    );
  }

  StoredStationHistory _stationRefs(Map map) => StoredStationHistory(
    files: map['stationFileLayout'] == 'frames-v1',
    frameKeys: List<String>.from(map['stationFrameKeys'] as List? ?? const []),
    archiveKeys: List<String>.from(
      map['stationArchiveKeys'] as List? ?? const [],
    ),
    standaloneFrameKeys: List<String>.from(
      map['stationLegacyFrameKeys'] as List? ??
          ((map['stationArchiveKeys'] as List? ?? const []).isEmpty
              ? map['stationFrameKeys'] as List? ?? const []
              : const []),
    ),
  );

  Map<String, dynamic> _snapshot(
    EewEventGroup group,
    StoredStationHistory refs,
    Digest digest,
  ) {
    final key = recordKey(group);
    final deferred = _deferReports(group, key);
    return {
      'format': _snapshotFormat,
      'presentationVersion': _snapshotPresentationVersion,
      if (_folderRecords.contains(key)) 'folderVersion': 1,
      'key': 'flutter.$key',
      'recordDigest': digest.toString(),
      'group': {
        ...deferred.toMap(includeStationFrames: false, summaryOnly: true),
        'stationFrameKeys': refs.frameKeys,
        'stationArchiveKeys': refs.archiveKeys,
        'stationLegacyFrameKeys': refs.standaloneFrameKeys,
        if (refs.files) 'stationFileLayout': 'frames-v1',
      },
      'payloads': [
        for (var i = 0; i < deferred.reports.length; i++)
          if (deferred.storedReports?.payloads[deferred.reports[i]]
              case final ref?)
            {
              'index': i,
              'signature': ref.signature,
              if (ref.fileId != null) 'fileId': ref.fileId,
              'notEmpty': ref.isNotEmpty,
              if (ref.sasmexFields != null) 'sasmexFields': ref.sasmexFields,
              'reportInstant': ref.reportInstant?.toIso8601String(),
            },
      ],
    };
  }

  EewEventGroup _fromSnapshot(String key, Map<String, dynamic> snapshot) {
    if (snapshot['format'] != _snapshotFormat ||
        snapshot['presentationVersion'] != _snapshotPresentationVersion ||
        snapshot['key'] != 'flutter.$key') {
      throw const FormatException('Invalid saved history snapshot');
    }
    final map = snapshot['group'] as Map;
    final group = EewEventGroup.fromMap(map);
    final references = <UnifiedQuakeData, StoredReportPayload>{};
    for (final value in snapshot['payloads'] as List) {
      final index = value['index'] as int;
      if (index < 0 || index >= group.reports.length) {
        throw const FormatException('Invalid saved history report index');
      }
      final report = group.reports[index];
      if (report.sourcePayload != null ||
          value['signature'] != _reportSignature(report)) {
        throw const FormatException('Saved history summary differs');
      }
      references[report] = StoredReportPayload(
        signature: value['signature'] as String,
        fileId: value['fileId'] as String?,
        filePath: value['fileId'] is String && _storage is HistoryFileStorage
            ? (_storage as HistoryFileStorage).reportPath(
                key,
                value['fileId'] as String,
              )
            : null,
        load: value['fileId'] is String && _storage is HistoryFileStorage
            ? _reportFileReader(
                key,
                value['fileId'] as String,
                value['signature'] as String,
              )
            : null,
        isNotEmpty: value['notEmpty'] as bool,
        sasmexFields: value['sasmexFields'] is Map
            ? Map<String, String>.from(value['sasmexFields'] as Map)
            : null,
        reportInstant: value['reportInstant'] == null
            ? null
            : DateTime.parse(value['reportInstant'] as String),
      );
    }
    final digest = snapshot['recordDigest'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid saved history digest');
    }
    _recordDigests[key] = Digest([
      for (var i = 0; i < digest.length; i += 2)
        int.parse(digest.substring(i, i + 2), radix: 16),
    ]);
    final refs = _diskRefs[key] = _stationRefs(map);
    _fileReports[key] = {
      for (final ref in references.values) ref.signature: ref,
    };
    if (snapshot['folderVersion'] == 1) {
      _folderRecords.add(key);
    }
    return group.copyWith(
      storedStations: refs,
      storedReports: references.isEmpty
          ? null
          : StoredReportHistory(recordKey: key, payloads: references),
    );
  }

  /// Hydrated originals belong to this caller only, never to a permanent cache.
  Future<EewEventGroup> loadReports(EewEventGroup group) {
    if (!group.hasDeferredReports) {
      return Future.value(group);
    }
    return _reportLoads.putIfAbsent(
      group,
      () => _readReports(group).whenComplete(() {
        _reportLoads.remove(group);
      }),
    );
  }

  Future<EewEventGroup> _readReports(EewEventGroup group) async {
    await flushFiles();
    final storage = _storage;
    if (storage == null) {
      throw StateError('History storage not initialized');
    }
    final references = group.storedReports!;
    if (references.payloads.values.every((ref) => ref.load != null)) {
      final reports = <UnifiedQuakeData>[];
      for (final report in group.reports) {
        reports.add(await references.payloads[report]?.load?.call() ?? report);
      }
      return group.copyWith(
        reports: List.unmodifiable(reports),
        clearStoredReports: true,
      );
    }
    final text = await storage.read(references.recordKey);
    if (text is! String) {
      throw const FormatException('Missing saved history record');
    }
    final saved = EewEventGroup.fromMap(jsonDecode(text) as Map);
    final bySignature = {
      for (final report in saved.reports) _reportSignature(report): report,
    };
    final reports = <UnifiedQuakeData>[];
    for (final report in group.reports) {
      final ref = references.payloads[report];
      if (ref == null) {
        reports.add(report);
        continue;
      }
      final original = bySignature[ref.signature];
      if (original == null || original.sourcePayload == null) {
        throw const FormatException(
          'Saved history changed; reload the selection',
        );
      }
      reports.add(original);
    }
    return group.copyWith(
      reports: List.unmodifiable(reports),
      clearStoredReports: true,
    );
  }

  bool _needsSasmexPresentationUpgrade(Map<String, dynamic> snapshot) {
    final reports = (snapshot['group'] as Map?)?['reports'];
    if (reports is! List) {
      return false;
    }
    return (snapshot['payloads'] as List? ?? const []).any((value) {
      final index = value['index'] as int;
      return index >= 0 &&
          index < reports.length &&
          reports[index]['source'] == 'sasmex' &&
          value['sasmexFields'] is! Map;
    });
  }

  Future<List<EewEventGroup>> restoreForStartup(
    SharedPreferences prefs, {
    String? legacyFallbackKey,
    bool lazyReports = false,
    bool migrateLegacy = true,
  }) async {
    final storage = _storage ??= historyStorage(prefs);
    lazyReports = lazyReports && storage is HistorySnapshotStorage;
    final index = (await storage.read(indexKey) as List?)?.cast<String>();
    _persistedIndex = index;
    if (index == null) {
      if (!migrateLegacy) return const [];
      final text =
          await storage.read(preferenceKey) ??
          (legacyFallbackKey == null
              ? null
              : await storage.read(legacyFallbackKey));
      if (text == null || (text as String).isEmpty) {
        return [];
      }
      final groups = await compute(
        _decodeLegacyHistory,
        text,
        debugLabel: 'legacy-history-migration',
      );
      await _saveSeparate(storage, groups);
      return groups
          .map((group) => releaseSavedFrames(group, deferReports: lazyReports))
          .toList();
    }
    final groups = <EewEventGroup>[];
    for (final key in index) {
      if ((lazyReports || storage is HistoryFileStorage) &&
          storage is HistorySnapshotStorage) {
        final snapshot = await (storage as HistorySnapshotStorage).readSnapshot(
          key,
        );
        if (snapshot != null) {
          // Early snapshots did not retain payload-dependent badge estimates.
          // Rebuild that known cache version once from the unchanged original.
          final needsPresentationUpgrade =
              snapshot['format'] == _snapshotFormat &&
              (snapshot['presentationVersion'] == null ||
                  _needsSasmexPresentationUpgrade(snapshot));
          if (needsPresentationUpgrade &&
              storage is HistoryFileStorage &&
              snapshot['folderVersion'] == 1) {
            // Presentation caches can be rebuilt from independent originals;
            // never reinterpret their summary-only manifest as a raw record.
            final legacySummary = _fromSnapshot(key, {
              ...snapshot,
              'presentationVersion': _snapshotPresentationVersion,
            });
            final complete = await loadReports(legacySummary);
            await _writeFolderGroup(storage as HistoryFileStorage, complete);
            final upgraded = releaseSavedFrames(
              complete,
              deferReports: lazyReports,
            );
            groups.add(upgraded);
            continue;
          }
          if (!needsPresentationUpgrade) {
            var group = _fromSnapshot(key, snapshot);
            if (!lazyReports) {
              group = await loadReports(group);
            }
            _savedGroups[group] = true;
            groups.add(group);
            continue;
          }
        }
      }
      final text = await storage.read(key);
      if (text is! String) {
        throw FormatException('Missing history record: $key');
      }
      final map = jsonDecode(text) as Map;
      _recordDigests[key] = sha256.convert(utf8.encode(text));
      final refs = StoredStationHistory(
        frameKeys: List<String>.from(
          map['stationFrameKeys'] as List? ?? const [],
        ),
        archiveKeys: List<String>.from(
          map['stationArchiveKeys'] as List? ?? const [],
        ),
        standaloneFrameKeys: List<String>.from(
          map['stationLegacyFrameKeys'] as List? ??
              ((map['stationArchiveKeys'] as List? ?? const []).isEmpty
                  ? map['stationFrameKeys'] as List? ?? const []
                  : const []),
        ),
      );
      _diskRefs[key] = refs;
      var group = EewEventGroup.fromMap(
        map,
        compactHistoricalPayload: storage is! HistoryFileStorage,
      ).copyWith(storedStations: refs);
      if (storage is HistoryFileStorage) {
        // Cache only a summary. Raw legacy files stay untouched, and station
        // migration is deferred until this event is selected or updated.
        if (!await (storage as HistoryFileStorage).writeLegacySummary(
          key,
          _snapshot(group, refs, _recordDigests[key]!),
        )) {
          throw StateError('Legacy history summary write failed');
        }
        if (lazyReports) {
          group = _deferReports(group, key);
        }
        _savedGroups[group] = true;
        groups.add(group);
        continue;
      }
      if (lazyReports) {
        if (storage is HistorySnapshotStorage &&
            !await (storage as HistorySnapshotStorage).writeWithSnapshot(
              key,
              text,
              _snapshot(group, refs, _recordDigests[key]!),
            )) {
          throw StateError('History snapshot migration failed');
        }
        group = _deferReports(group, key);
      }
      _savedGroups[group] = true;
      groups.add(group);
    }
    return groups;
  }

  Future<EewEventGroup> loadStationFrames(EewEventGroup group) async {
    await flushFiles();
    final fileStorage = _storage;
    if (fileStorage is HistoryFileStorage &&
        ((!_folderRecords.contains(recordKey(group)) &&
                group.storedStations?.files != true) ||
            group.storedStations?.archiveKeys.isNotEmpty == true ||
            group.storedStations?.standaloneFrameKeys.isNotEmpty == true)) {
      await _writeFolderGroup(fileStorage as HistoryFileStorage, group);
      group = releaseSavedFrames(group, deferReports: true);
    }
    if (fileStorage is HistoryFileStorage &&
        (_folderRecords.contains(recordKey(group)) ||
            group.storedStations?.files == true)) {
      final refs = group.storedStations;
      if (refs == null || refs.frameKeys.isEmpty) {
        return group;
      }
      final entries = <String, StationReplayEntry>{};
      for (final key in refs.frameKeys) {
        final match = RegExp(
          r'_station_(nied|snet|kma|cwa|seisjs|palert|lpgm)_(\d+)$',
        ).firstMatch(key);
        if (match == null) {
          throw const FormatException('Invalid frame file reference');
        }
        final kind = match[1]!;
        final receipt = DateTime.fromMicrosecondsSinceEpoch(
          int.parse(match[2]!),
          isUtc: true,
        );
        entries[key] = StationReplayEntry.file(
          receipt,
          kind,
          key,
          filePath: (fileStorage as HistoryFileStorage).framePath(key),
          load: _frameFileReader(
            fileStorage as HistoryFileStorage,
            key,
            kind,
            receipt,
          ),
        );
      }
      for (final frame in group.stationFrames) {
        entries[_frameKey(frame)] = StationReplayEntry(
          frame.receivedAt,
          frame.kind,
          _frameKey(frame),
          () => frame,
        );
      }
      return group.copyWith(
        stationFrames: StationReplayFrames(
          entries.values.toList()
            ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)),
        ),
        clearStoredStations: true,
      );
    }
    group = await loadReports(group);
    final refs = group.storedStations;
    if (refs == null || refs.frameKeys.isEmpty) {
      return group;
    }
    final storage = _storage;
    if (storage == null) {
      throw StateError('History storage not initialized');
    }
    final encoded = <String, String>{};
    final keys = {
      ...refs.archiveKeys,
      ...refs.standaloneFrameKeys,
      if (refs.archiveKeys.isEmpty) ...refs.frameKeys,
    };
    for (final key in keys) {
      final value = await storage.read(key);
      if (value is! String) {
        throw FormatException('Missing station archive: $key');
      }
      encoded[key] = value;
    }
    final indexed = await compute(
      _indexStoredFrames,
      encoded,
      debugLabel: 'history-stations-index',
    );
    final saved = StationReplayFrames.decode(indexed);
    final byKey = {
      for (final entry in saved.entries)
        '${preferenceKey}_station_${entry.kind}_${entry.receivedAt.microsecondsSinceEpoch}':
            entry,
    };
    final frames = <String, StationReplayEntry>{
      for (final key in refs.frameKeys)
        key:
            byKey[key] ??
            (throw FormatException('Missing station frame: $key')),
      for (final entry in StationReplayFrames.describe(group.stationFrames))
        '${preferenceKey}_station_${entry.kind}_${entry.receivedAt.microsecondsSinceEpoch}':
            entry,
    };
    return group.copyWith(
      stationFrames: StationReplayFrames(
        frames.values.toList()
          ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)),
        release: [saved.release],
      ),
      clearStoredStations: true,
    );
  }

  EewEventGroup releaseSavedFrames(
    EewEventGroup group, {
    bool deferReports = false,
  }) {
    final cache = deferReports ? _deferredGroups : _releasedGroups;
    final released = cache[group];
    final refs = _diskRefs[recordKey(group)];
    if (released != null && identical(released.storedStations, refs)) {
      return released;
    }
    if (refs == null) {
      return group;
    }
    final persisted = refs.frameKeys.toSet();
    var result = group.copyWith(
      reports: List.unmodifiable(
        group.reports.map((report) {
          final payload = report.sourcePayload;
          return !deferReports &&
                  report.source == 'globalQuakeEew' &&
                  payload != null
              ? report.copyWith(sourcePayload: compactSourcePayload(payload))
              : report;
        }),
      ),
      storedStations: refs,
      stationFrames: List.unmodifiable(
        group.stationFrames.where(
          (frame) => !persisted.contains(_frameKey(frame)),
        ),
      ),
    );
    final durablySaved = _savedGroups[group] == true;
    // A newer report can arrive while an older provider save is awaiting IO.
    // Its body must stay in memory until that exact group has been committed.
    if (deferReports && durablySaved) {
      result = _deferReports(result, recordKey(group));
    }
    if (!deferReports || durablySaved) {
      cache[group] = result;
    }
    if (_savedGroups[group] == true) {
      _savedGroups[result] = true;
    }
    return result;
  }

  Future<void> _saveSeparate(
    HistoryStorage storage,
    List<EewEventGroup> groups, {
    Map<String, int>? receiptVersions,
  }) async {
    if (storage is HistoryFileStorage) {
      return _saveFolder(
        storage,
        storage as HistoryFileStorage,
        groups,
        receiptVersions ?? Map.of(_receiptRevisions),
      );
    }
    final next = {for (final group in groups) recordKey(group): group};
    final newFrames = <String, StationHistoryFrame>{};
    final prior = <String, StoredStationHistory>{};
    for (final entry in next.entries) {
      final old = _diskRefs[entry.key];
      final refs = entry.value.storedStations;
      prior[entry.key] = StoredStationHistory(
        frameKeys: {...?old?.frameKeys, ...?refs?.frameKeys}.toList(),
        archiveKeys: {...?old?.archiveKeys, ...?refs?.archiveKeys}.toList(),
        standaloneFrameKeys: {
          ...?old?.standaloneFrameKeys,
          ...?refs?.standaloneFrameKeys,
        }.toList(),
      );
      final existing = prior[entry.key]!.frameKeys.toSet();
      for (final frame in entry.value.stationFrames) {
        final key = _frameKey(frame);
        if (!existing.contains(key)) {
          newFrames[key] = frame;
        }
      }
    }
    final chunks = <String, List<StationHistoryFrame>>{};
    for (final frame in newFrames.values) {
      (chunks[_archiveKey(frame)] ??= []).add(frame);
    }
    final frameArchives = <String, String>{};
    final entries = chunks.entries.toList();
    for (var offset = 0; offset < entries.length; offset += _archivesPerBatch) {
      final batch = <String, List<StationHistoryFrame>>{};
      for (final chunk in entries.skip(offset).take(_archivesPerBatch)) {
        chunk.value.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
        final revision = sha256.convert(
          utf8.encode(jsonEncode(chunk.value.map(_frameKey).toList())),
        );
        final key = '${chunk.key}_$revision';
        batch[key] = chunk.value;
        for (final frame in chunk.value) {
          frameArchives[_frameKey(frame)] = key;
        }
      }
      final encoded = await compute(
        _encodeStationHistoryArchives,
        batch,
        debugLabel: 'history-stations-write',
      );
      for (final entry in encoded.entries) {
        if (!await storage.write(entry.key, entry.value)) {
          throw StateError('History archive write failed');
        }
      }
    }
    final nextRefs = <String, StoredStationHistory>{};
    for (final entry in next.entries) {
      final old = prior[entry.key]!;
      final keys = {
        ...old.frameKeys,
        ...entry.value.stationFrames.map(_frameKey),
      }.toList();
      final archives = {
        ...old.archiveKeys,
        for (final key in keys)
          if (frameArchives.containsKey(key)) frameArchives[key]!,
      }.toList();
      final refs = StoredStationHistory(
        frameKeys: keys,
        archiveKeys: archives,
        standaloneFrameKeys: old.standaloneFrameKeys,
      );
      nextRefs[entry.key] = refs;
      final savedRefs = _diskRefs[entry.key];
      if (_savedGroups[entry.value] == true &&
          savedRefs != null &&
          listEquals(savedRefs.frameKeys, refs.frameKeys) &&
          listEquals(savedRefs.archiveKeys, refs.archiveKeys) &&
          listEquals(savedRefs.standaloneFrameKeys, refs.standaloneFrameKeys)) {
        continue;
      }
      final complete = await loadReports(entry.value);
      final text = jsonEncode({
        ...complete.toMap(includeStationFrames: false),
        'stationFrameKeys': keys,
        'stationArchiveKeys': archives,
        if (refs.standaloneFrameKeys.isNotEmpty)
          'stationLegacyFrameKeys': refs.standaloneFrameKeys,
      });
      final digest = sha256.convert(utf8.encode(text));
      if (_recordDigests[entry.key] != digest) {
        final success = storage is HistorySnapshotStorage
            ? await (storage as HistorySnapshotStorage).writeWithSnapshot(
                entry.key,
                text,
                _snapshot(complete, refs, digest),
              )
            : await storage.write(entry.key, text);
        if (!success) {
          throw StateError('History record write failed');
        }
        _recordDigests[entry.key] = digest;
      }
    }
    final index = next.keys.toList();
    if (!listEquals(_persistedIndex, index) &&
        !await storage.write(indexKey, index)) {
      throw StateError('History index write failed');
    }
    _persistedIndex = index;
    final retained = {
      for (final refs in nextRefs.values) ...refs.archiveKeys,
      for (final refs in nextRefs.values) ...refs.standaloneFrameKeys,
    };
    for (final key
        in _diskRefs.keys.where((key) => !next.containsKey(key)).toList()) {
      await storage.remove(key);
      _recordDigests.remove(key);
    }
    final previous = {
      for (final refs in _diskRefs.values) ...refs.archiveKeys,
      for (final refs in _diskRefs.values) ...refs.standaloneFrameKeys,
    };
    for (final key in previous.difference(retained)) {
      await storage.remove(key);
    }
    _diskRefs
      ..clear()
      ..addAll(nextRefs);
    for (final group in groups) {
      _savedGroups[group] = true;
    }
    if (_canRemoveLegacy) {
      await storage.remove(preferenceKey);
    }
  }

  Future<UnifiedQuakeData> _readFileReport(
    String key,
    String fileId,
    String signature,
  ) async {
    final report = await (_storage as HistoryFileStorage).readReport(
      key,
      fileId,
    );
    if (_reportSignature(report) != signature) {
      throw const FormatException('Saved report summary mismatch');
    }
    return report;
  }

  Future<UnifiedQuakeData> Function() _reportFileReader(
    String key,
    String fileId,
    String signature,
  ) =>
      () => _readFileReport(key, fileId, signature);

  Future<void> _writeFolderGroup(
    HistoryFileStorage files,
    EewEventGroup group,
  ) async {
    final input = group;
    if (group.storedReports?.payloads.values.any((ref) => ref.fileId == null) ==
        true) {
      group = await loadReports(group);
    }
    final key = recordKey(group);
    final previous = _diskRefs[key];
    final incoming = group.storedStations;
    final frameKeys = <String>{
      ...?previous?.frameKeys,
      ...?incoming?.frameKeys,
    };
    final alreadyFolder =
        _folderRecords.contains(key) ||
        previous?.files == true ||
        incoming?.files == true;
    if (!alreadyFolder ||
        previous?.archiveKeys.isNotEmpty == true ||
        incoming?.archiveKeys.isNotEmpty == true ||
        previous?.standaloneFrameKeys.isNotEmpty == true ||
        incoming?.standaloneFrameKeys.isNotEmpty == true) {
      final archives = <String>{
        ...?previous?.archiveKeys,
        ...?incoming?.archiveKeys,
        ...?previous?.standaloneFrameKeys,
        ...?incoming?.standaloneFrameKeys,
      };
      for (final archive in archives) {
        if (_migratedArchives.contains(archive)) {
          continue;
        }
        final text = await _storage!.read(archive);
        if (text is! String) {
          throw FormatException('Missing legacy station file: $archive');
        }
        final frames = await compute(
          _decodeLegacyStationFile,
          text,
          debugLabel: 'migrate-one-station-file',
        );
        for (final frame in frames) {
          await files.writeFrame(_frameKey(frame), frame.toMap());
        }
        _migratedArchives.add(archive);
      }
    }
    for (final frame in group.stationFrames) {
      final frameKey = _frameKey(frame);
      if (!frameKeys.contains(frameKey)) {
        await files.writeFrame(frameKey, frame.toMap());
        frameKeys.add(frameKey);
      }
    }
    final refs = StoredStationHistory(
      frameKeys: frameKeys.toList(),
      archiveKeys: const [],
      files: true,
    );
    if (_savedGroups[group] == true &&
        alreadyFolder &&
        previous != null &&
        listEquals(previous.frameKeys, refs.frameKeys)) {
      return;
    }
    final reportFiles = <String, StoredReportPayload>{};
    for (final report in group.reports) {
      final old = group.storedReports?.payloads[report];
      if (old != null) {
        if (old.fileId == null) {
          throw StateError('Legacy report requires migration');
        }
        reportFiles[old.signature] = old;
      } else if (report.sourcePayload != null) {
        final signature = _reportSignature(report);
        final fileId = await files.writeReport(key, report.toMap());
        reportFiles[signature] = StoredReportPayload(
          signature: signature,
          isNotEmpty: report.sourcePayload!.isNotEmpty,
          fileId: fileId,
          filePath: files.reportPath(key, fileId),
          load: _reportFileReader(key, fileId, signature),
        );
      }
    }
    _fileReports[key] = {...?_fileReports[key], ...reportFiles};
    _folderRecords.add(key);
    final deferred = _deferReports(group, key);
    final value = jsonEncode({
      ...deferred.toMap(includeStationFrames: false, summaryOnly: true),
      'stationFrameKeys': refs.frameKeys,
      'stationArchiveKeys': const [],
      'stationFileLayout': 'frames-v1',
    });
    final digest = sha256.convert(utf8.encode(value));
    if (!await files.writeWithSnapshot(
      key,
      value,
      _snapshot(group, refs, digest),
    )) {
      throw StateError('Directory history manifest write failed');
    }
    _recordDigests[key] = digest;
    // Frames can arrive while this manifest is committing. Its fixed-length
    // view remains immutable; newer accepted keys belong to the next manifest.
    final live = _liveIndices[key];
    _diskRefs[key] = live != null && live.keys.length > refs.frameKeys.length
        ? StoredStationHistory(
            frameKeys: _FrameKeys(live),
            archiveKeys: const [],
            files: true,
          )
        : refs;
    _savedGroups[group] = true;
    _savedGroups[input] = true;
    _deferredGroups[input] = null;
    _releasedGroups[input] = null;
    final reportSignatures =
        _liveReportSignatures[key] ?? reportFiles.keys.toSet();
    _fileReports[key]?.removeWhere(
      (signature, _) => !reportSignatures.contains(signature),
    );
  }

  Future<void> _saveFolder(
    HistoryStorage storage,
    HistoryFileStorage files,
    List<EewEventGroup> groups,
    Map<String, int> receiptVersions,
  ) async {
    await flushFiles();
    final previous = Map<String, StoredStationHistory>.of(_diskRefs);
    final keys = <String>[];
    for (final group in groups) {
      final key = recordKey(group);
      if (!(_savedGroups[group] == true &&
          !_folderRecords.contains(key) &&
          group.storedStations?.files != true)) {
        await _writeFolderGroup(files, group);
      }
      keys.add(key);
    }
    if (!listEquals(keys, _persistedIndex) &&
        !await storage.write(indexKey, keys)) {
      throw StateError('Directory history index write failed');
    }
    _persistedIndex = keys;
    // A new event/frame can arrive during the older index commit. Its files
    // must survive until the provider's coalesced next snapshot includes it.
    final retained = {
      ...keys,
      for (final key in _diskRefs.keys)
        if (_receiptRevisions[key] != receiptVersions[key]) key,
    };
    final retainedFrames = {
      for (final key in retained) ..._diskRefs[key]!.frameKeys,
    };
    for (final key in previous.keys.where((key) => !retained.contains(key))) {
      await storage.remove(key);
      _diskRefs.remove(key);
      _recordDigests.remove(key);
      _fileReports.remove(key);
      _folderRecords.remove(key);
      _liveIndices.remove(key);
      _receiptRevisions.remove(key);
      _liveReportSignatures.remove(key);
    }
    for (final frame in {
      for (final refs in previous.values) ...refs.frameKeys,
    }.difference(retainedFrames)) {
      await files.removeFrame(frame);
    }
    _acceptedFrames.removeWhere((key) => !retainedFrames.contains(key));
    // Legacy history files remain untouched as the migration recovery source.
  }

  /// Reconciles frames written by the background recording owner into this
  /// (UI-side) store. Merges the reported keys with the known disk refs so a
  /// later local save keeps both sets alive.
  EewEventGroup adoptStoredFrameKeys(
    String key,
    EewEventGroup group,
    List<String> frameKeys,
  ) {
    if (frameKeys.isEmpty) return group;
    final prior = _diskRefs[key] ?? group.storedStations;
    final merged = {...?prior?.frameKeys, ...frameKeys}.toList();
    final refs = StoredStationHistory(
      frameKeys: merged,
      archiveKeys: prior?.archiveKeys ?? const [],
      standaloneFrameKeys: prior?.standaloneFrameKeys ?? const [],
      files: true,
    );
    _diskRefs[key] = refs;
    final index = _liveIndices.putIfAbsent(
      key,
      () => _FrameIndex({...?prior?.frameKeys}),
    );
    for (final frameKey in frameKeys) {
      index.add(frameKey);
    }
    _acceptedFrames.addAll(frameKeys);
    return group.copyWith(storedStations: refs);
  }

  /// Reads a single record from disk for records this isolate has never seen
  /// (e.g. the UI engine was dead for the whole recording window).
  Future<EewEventGroup?> restoreRecordFromDisk(String key) async {
    final storage = _storage;
    if (storage == null) return null;
    if (storage is HistorySnapshotStorage) {
      try {
        final snapshot = await (storage as HistorySnapshotStorage).readSnapshot(
          key,
        );
        if (snapshot != null && snapshot['format'] == _snapshotFormat) {
          return _fromSnapshot(key, snapshot);
        }
      } on Object {
        // Fall through to the raw record branch.
      }
    }
    final text = await storage.read(key);
    if (text is! String) return null;
    try {
      final map = jsonDecode(text) as Map;
      final refs = StoredStationHistory(
        frameKeys: List<String>.from(
          map['stationFrameKeys'] as List? ?? const [],
        ),
        archiveKeys: List<String>.from(
          map['stationArchiveKeys'] as List? ?? const [],
        ),
        standaloneFrameKeys: List<String>.from(
          map['stationLegacyFrameKeys'] as List? ?? const [],
        ),
      );
      _diskRefs[key] = refs;
      return EewEventGroup.fromMap(map).copyWith(storedStations: refs);
    } on Object catch (error) {
      debugPrint('EEW history record restore failed: $error');
      return null;
    }
  }

  List<EewEventGroup> restore(
    SharedPreferences prefs, {
    String? legacyFallbackKey,
  }) {
    final index = prefs.getStringList(indexKey);
    final groups = <EewEventGroup>[];
    if (index != null) {
      final savedFrames = <String, StationHistoryFrame>{};
      final restoredArchives = <String, List<StationHistoryFrame>>{};
      for (final key in index) {
        try {
          final text = prefs.getString(key);
          if (text == null) {
            throw const FormatException('Missing history event');
          }
          final map = jsonDecode(text) as Map;
          for (final archiveKey
              in map['stationArchiveKeys'] as List? ?? const []) {
            if (restoredArchives.containsKey(archiveKey)) {
              continue;
            }
            final archiveText = prefs.getString(archiveKey as String);
            if (archiveText == null) {
              throw const FormatException('Missing station archive');
            }
            final frames = StationJsonArchive.decode(
              StationArchiveStorage.decode(archiveText),
            );
            restoredArchives[archiveKey] = frames;
            for (final frame in frames) {
              savedFrames[_frameKey(frame)] = frame;
            }
          }
          final frames = <StationHistoryFrame>[];
          for (final frameKey in map['stationFrameKeys'] as List? ?? const []) {
            final archived = savedFrames[frameKey];
            if (archived != null) {
              frames.add(archived);
              continue;
            }
            final encodedFrame = prefs.getString(frameKey as String);
            if (encodedFrame == null) {
              throw const FormatException('Missing station frame');
            }
            final encoded = StationArchiveStorage.decode(encodedFrame);
            final frame = encoded['format'] == StationJsonArchive.format
                ? StationJsonArchive.decode(encoded).single
                : StationHistoryFrame.fromMap(encoded);
            frames.add(frame);
            savedFrames[frameKey] = frame;
          }
          final group = EewEventGroup.fromMap(map).copyWith(
            stationFrames: frames.isEmpty ? null : List.unmodifiable(frames),
          );
          groups.add(group);
          _diskRefs[key] = StoredStationHistory(
            frameKeys: (map['stationFrameKeys'] as List? ?? const [])
                .cast<String>()
                .toList(),
            archiveKeys: (map['stationArchiveKeys'] as List? ?? const [])
                .cast<String>()
                .toList(),
            standaloneFrameKeys:
                (map['stationLegacyFrameKeys'] as List? ??
                        ((map['stationArchiveKeys'] as List? ?? const [])
                                .isEmpty
                            ? map['stationFrameKeys'] as List? ?? const []
                            : const []))
                    .cast<String>()
                    .toList(),
          );
          _recordDigests[key] = sha256.convert(utf8.encode(text));
        } on Object catch (error) {
          debugPrint('EEW history record restore skipped: $error');
        }
      }
      return groups;
    }
    final text =
        prefs.getString(preferenceKey) ??
        (legacyFallbackKey == null ? null : prefs.getString(legacyFallbackKey));
    if (text == null || text.trim().isEmpty) {
      return groups;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        _canRemoveLegacy = false;
        return groups;
      }
      for (final value in decoded) {
        if (value is! Map) {
          _canRemoveLegacy = false;
          continue;
        }
        try {
          groups.add(EewEventGroup.fromMap(value));
        } on Object catch (error) {
          _canRemoveLegacy = false;
          debugPrint('Legacy EEW history record restore skipped: $error');
        }
      }
    } on Object catch (error) {
      _canRemoveLegacy = false;
      debugPrint('Legacy EEW history restore failed: $error');
    }
    return groups;
  }

  Future<void> save(SharedPreferences prefs, List<EewEventGroup> groups) async {
    final receiptVersions = Map<String, int>.of(_receiptRevisions);
    final storage = _storage ??= historyStorage(prefs);
    if (!_canRemoveLegacy && groups.isEmpty && !prefs.containsKey(indexKey)) {
      return;
    }
    // IO clients use individual files. The preference/archive branch remains
    // for non-filesystem clients and explicit old-format compatibility only.
    return _saveSeparate(storage, groups, receiptVersions: receiptVersions);
  }
}
