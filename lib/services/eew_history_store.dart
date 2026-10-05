import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eew_event_group.dart';
import '../models/station_history_frame.dart';
import 'debug/station_json_archive.dart';
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
    entry.key: StationArchiveStorage.encode(
      StationJsonArchive.encode(entry.value),
    ),
};

/// Incremental event storage; the old single JSON list is read-only migration.
class EewHistoryStore {
  static const _archivesPerBatch = 1;
  final String preferenceKey;
  bool _canRemoveLegacy = true;
  final Map<String, StoredStationHistory> _diskRefs = {};
  final Map<String, Digest> _recordDigests = {};
  List<String>? _persistedIndex;
  HistoryStorage? _storage;

  EewHistoryStore({required this.preferenceKey});

  String get indexKey => '${preferenceKey}_index_v2';

  String _frameKey(StationHistoryFrame frame) =>
      '${preferenceKey}_station_${frame.kind}_${frame.receivedAt.microsecondsSinceEpoch}';

  String _archiveKey(StationHistoryFrame frame) =>
      '${preferenceKey}_station_archive_${frame.kind}_${frame.receivedAt.millisecondsSinceEpoch ~/ 30000}';

  String recordKey(EewEventGroup group) {
    final identity = jsonEncode([group.latest.source, group.eventId]);
    return '${preferenceKey}_event_${base64Url.encode(utf8.encode(identity))}';
  }

  Future<List<EewEventGroup>> restoreForStartup(
    SharedPreferences prefs, {
    String? legacyFallbackKey,
  }) async {
    final storage = _storage = historyStorage(prefs);
    final index = (await storage.read(indexKey) as List?)?.cast<String>();
    _persistedIndex = index;
    if (index == null) {
      final text =
          await storage.read(preferenceKey) ??
          (legacyFallbackKey == null
              ? null
              : await storage.read(legacyFallbackKey));
      if (text == null || (text as String).isEmpty) return [];
      final groups = await compute(
        _decodeLegacyHistory,
        text,
        debugLabel: 'legacy-history-migration',
      );
      await _saveSeparate(storage, groups);
      return groups.map(releaseSavedFrames).toList();
    }
    final groups = <EewEventGroup>[];
    for (final key in index) {
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
      groups.add(EewEventGroup.fromMap(map).copyWith(storedStations: refs));
    }
    return groups;
  }

  Future<EewEventGroup> loadStationFrames(EewEventGroup group) async {
    final refs = group.storedStations;
    if (refs == null || refs.frameKeys.isEmpty) return group;
    final storage = _storage;
    if (storage == null) throw StateError('History storage not initialized');
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

  EewEventGroup releaseSavedFrames(EewEventGroup group) {
    final refs = _diskRefs[recordKey(group)];
    if (refs == null) return group;
    final persisted = refs.frameKeys.toSet();
    return group.copyWith(
      storedStations: refs,
      stationFrames: List.unmodifiable(
        group.stationFrames.where(
          (frame) => !persisted.contains(_frameKey(frame)),
        ),
      ),
    );
  }

  Future<void> _saveSeparate(
    HistoryStorage storage,
    List<EewEventGroup> groups,
  ) async {
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
        if (!existing.contains(key)) newFrames[key] = frame;
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
      final text = jsonEncode({
        ...entry.value.toMap(includeStationFrames: false),
        'stationFrameKeys': keys,
        'stationArchiveKeys': archives,
        if (refs.standaloneFrameKeys.isNotEmpty)
          'stationLegacyFrameKeys': refs.standaloneFrameKeys,
      });
      final digest = sha256.convert(utf8.encode(text));
      if (_recordDigests[entry.key] != digest) {
        if (!await storage.write(entry.key, text)) {
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
    if (_canRemoveLegacy) await storage.remove(preferenceKey);
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
            if (restoredArchives.containsKey(archiveKey)) continue;
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
    if (text == null || text.trim().isEmpty) return groups;
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
    final storage = _storage ??= historyStorage(prefs);
    if (!_canRemoveLegacy && groups.isEmpty && !prefs.containsKey(indexKey)) {
      return;
    }
    // All platforms use append-only archives and disk references. Preferences
    // backends still store strings, but no longer retain decoded frame heaps.
    return _saveSeparate(storage, groups);
  }
}
