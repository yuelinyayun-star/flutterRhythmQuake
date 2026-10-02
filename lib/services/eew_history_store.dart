import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eew_event_group.dart';
import '../models/station_history_frame.dart';
import 'debug/station_json_archive.dart';

/// Incremental event storage; the old single JSON list is read-only migration.
class EewHistoryStore {
  final String preferenceKey;
  final Map<String, EewEventGroup> _saved = {};
  final Map<String, StationHistoryFrame> _savedFrames = {};
  final Map<String, List<StationHistoryFrame>> _savedArchives = {};
  final Map<String, List<String>> _savedArchiveKeys = {};
  bool _canRemoveLegacy = true;

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
    for (final entry in nextArchives.entries) {
      final previous = _savedArchives[entry.key];
      if (previous != null &&
          listEquals(previous, entry.value) &&
          prefs.containsKey(entry.key)) {
        continue;
      }
      if (!await prefs.setString(
        entry.key,
        jsonEncode(StationJsonArchive.encode(entry.value)),
      )) {
        throw StateError('Could not persist station history archive');
      }
    }
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
