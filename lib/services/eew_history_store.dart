import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eew_event_group.dart';
import '../models/station_history_frame.dart';
import 'debug/station_json_archive.dart';
import 'history_storage.dart';

List<EewEventGroup> _decodeLegacyHistory(String text) =>
    (jsonDecode(text) as List)
        .map((value) => EewEventGroup.fromMap(value as Map))
        .toList();

List<StationHistoryFrame> _decodeStoredFrames(
  (List<String>, Map<String, String>, String) request,
) {
  final (keys, values, prefix) = request;
  final frames = <String, StationHistoryFrame>{};
  for (final entry in values.entries) {
    final encoded = jsonDecode(entry.value) as Map;
    final decoded = encoded['format'] == StationJsonArchive.format
        ? StationJsonArchive.decode(encoded)
        : [StationHistoryFrame.fromMap(encoded)];
    for (final frame in decoded) {
      frames['${prefix}_station_${frame.kind}_${frame.receivedAt.microsecondsSinceEpoch}'] =
          frame;
    }
  }
  return [
    for (final key in keys)
      frames[key] ?? (throw FormatException('Missing station frame: $key')),
  ];
}

Map<String, String> _encodeStationHistoryArchives(
  Map<String, List<StationHistoryFrame>> archives,
) => {
  for (final entry in archives.entries)
    entry.key: jsonEncode(StationJsonArchive.encode(entry.value)),
};

/// Incremental event storage; the old single JSON list is read-only migration.
class EewHistoryStore {
  static const _archivesPerBatch = 8;
  final String preferenceKey;
  final Map<String, EewEventGroup> _saved = {};
  final Map<String, StationHistoryFrame> _savedFrames = {};
  final Map<String, List<StationHistoryFrame>> _savedArchives = {};
  final Map<String, List<String>> _savedArchiveKeys = {};
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
    if (!storage.separate) {
      return restore(prefs, legacyFallbackKey: legacyFallbackKey);
    }
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
    final saved = await compute(_decodeStoredFrames, (
      refs.frameKeys,
      encoded,
      preferenceKey,
    ), debugLabel: 'history-stations-read');
    final frames = {
      for (final frame in saved) _frameKey(frame): frame,
      for (final frame in group.stationFrames) _frameKey(frame): frame,
    };
    return group.copyWith(
      stationFrames: List.unmodifiable(frames.values),
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
    await storage.remove(preferenceKey);
  }

  List<EewEventGroup> restore(
    SharedPreferences prefs, {
    String? legacyFallbackKey,
  }) {
    final index = prefs.getStringList(indexKey);
    final groups = <EewEventGroup>[];
    if (index != null) {
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
              jsonDecode(archiveText) as Map,
            );
            restoredArchives[archiveKey] = frames;
            _savedArchives[archiveKey] = frames;
            for (final frame in frames) {
              _savedFrames[_frameKey(frame)] = frame;
            }
          }
          final frames = <StationHistoryFrame>[];
          for (final frameKey in map['stationFrameKeys'] as List? ?? const []) {
            final archived = _savedFrames[frameKey];
            if (archived != null) {
              frames.add(archived);
              continue;
            }
            final encodedFrame = prefs.getString(frameKey as String);
            if (encodedFrame == null) {
              throw const FormatException('Missing station frame');
            }
            final encoded = jsonDecode(encodedFrame) as Map;
            final frame = encoded['format'] == StationJsonArchive.format
                ? StationJsonArchive.decode(encoded).single
                : StationHistoryFrame.fromMap(encoded);
            frames.add(frame);
            _savedFrames[frameKey] = frame;
          }
          final group = EewEventGroup.fromMap(map).copyWith(
            stationFrames: frames.isEmpty ? null : List.unmodifiable(frames),
          );
          groups.add(group);
          _saved[key] = group;
          _savedArchiveKeys[key] =
              (map['stationArchiveKeys'] as List? ?? const [])
                  .cast<String>()
                  .toList();
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
    if (storage.separate) return _saveSeparate(storage, groups);
    if (!_canRemoveLegacy && groups.isEmpty && !prefs.containsKey(indexKey)) {
      return;
    }
    final next = {for (final group in groups) recordKey(group): group};
    final nextFrames = {
      for (final group in groups)
        for (final frame in group.stationFrames) _frameKey(frame): frame,
    };
    final chunks = <String, List<StationHistoryFrame>>{};
    for (final frame in nextFrames.values) {
      (chunks[_archiveKey(frame)] ??= []).add(frame);
    }
    final nextArchives = <String, List<StationHistoryFrame>>{};
    final chunkKeys = <String, String>{};
    for (final entry in chunks.entries) {
      entry.value.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      final revision = sha256.convert(
        utf8.encode(jsonEncode(entry.value.map(_frameKey).toList())),
      );
      final key = '${entry.key}_$revision';
      chunkKeys[entry.key] = key;
      nextArchives[key] = entry.value;
    }
    // Fixed time chunks share metadata without rewriting completed events.
    final pendingArchives = <String, List<StationHistoryFrame>>{};
    for (final entry in nextArchives.entries) {
      final previous = _savedArchives[entry.key];
      if (previous != null &&
          listEquals(previous, entry.value) &&
          prefs.containsKey(entry.key)) {
        continue;
      }
      pendingArchives[entry.key] = entry.value;
    }
    Future<void> persistBatch(
      Map<String, List<StationHistoryFrame>> batch,
    ) async {
      final encodedArchives = await compute(
        _encodeStationHistoryArchives,
        batch,
        debugLabel: 'eew-station-history-encode',
      );
      for (final entry in encodedArchives.entries) {
        if (!await prefs.setString(entry.key, entry.value)) {
          throw StateError('Could not persist station history archive');
        }
      }
    }

    // Batch native isolate transfers without copying an entire legacy archive.
    var batch = <String, List<StationHistoryFrame>>{};
    for (final entry in pendingArchives.entries) {
      batch[entry.key] = entry.value;
      if (batch.length == _archivesPerBatch) {
        await persistBatch(batch);
        batch = {};
      }
    }
    if (batch.isNotEmpty) await persistBatch(batch);
    final nextArchiveKeys = <String, List<String>>{};
    for (final entry in next.entries) {
      final frameKeys = entry.value.stationFrames.map(_frameKey).toList();
      final archiveKeys = entry.value.stationFrames
          .map((frame) => chunkKeys[_archiveKey(frame)]!)
          .toSet()
          .toList();
      nextArchiveKeys[entry.key] = archiveKeys;
      if (identical(_saved[entry.key], entry.value) &&
          listEquals(_savedArchiveKeys[entry.key], archiveKeys) &&
          prefs.containsKey(entry.key)) {
        continue;
      }
      if (!await prefs.setString(
        entry.key,
        jsonEncode({
          ...entry.value.toMap(includeStationFrames: false),
          if (frameKeys.isNotEmpty) 'stationFrameKeys': frameKeys,
          if (archiveKeys.isNotEmpty) 'stationArchiveKeys': archiveKeys,
        }),
      )) {
        throw StateError('Could not persist EEW history event');
      }
    }
    // Publish the index only after all referenced records have been written.
    if (!await prefs.setStringList(indexKey, next.keys.toList())) {
      throw StateError('Could not persist EEW history index');
    }
    final removed = _saved.keys.where((key) => !next.containsKey(key)).toList();
    final removedFrames = _savedFrames.keys
        .where((key) => !nextFrames.containsKey(key))
        .toList();
    final removedArchives = _savedArchives.keys
        .where((key) => !nextArchives.containsKey(key))
        .toList();
    _saved
      ..clear()
      ..addAll(next);
    _savedFrames
      ..clear()
      ..addAll(nextFrames);
    _savedArchives
      ..clear()
      ..addAll(nextArchives);
    _savedArchiveKeys
      ..clear()
      ..addAll(nextArchiveKeys);
    for (final key in removed) {
      await prefs.remove(key);
    }
    for (final key in removedFrames) {
      await prefs.remove(key);
    }
    for (final key in removedArchives) {
      await prefs.remove(key);
    }
    for (final key in nextFrames.keys) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
    if (_canRemoveLegacy) await prefs.remove(preferenceKey);
  }
}
