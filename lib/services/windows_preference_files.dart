import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

Future<Map<String, Object>> _readSettingsFile(String path) =>
    WindowsPreferenceFiles(path)._loadFile();

/// Used only by the serial preferences worker. History values never enter the
/// UI's SharedPreferences cache and are read individually for replay.
class WindowsPreferenceFiles {
  WindowsPreferenceFiles(this.supportPath);

  final String supportPath;
  Map<String, Object>? _settings;
  static bool isHistoryKey(String key) =>
      key == 'flutter.unified_eew_history' ||
      key.startsWith('flutter.unified_eew_history_');

  File get _settingsFile => File('$supportPath/shared_preferences.json');
  Directory get _historyDirectory => Directory('$supportPath/eew_history');
  File _record(String key) => File(
    '${_historyDirectory.path}/${sha256.convert(utf8.encode(key))}.json',
  );

  Future<void> _writeJson(File file, Object value) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(jsonEncode(value), encoding: utf8, flush: true);
    await pending.rename(file.path);
  }

  Future<Map<String, Object>> _load() async {
    if (_settings != null) return _settings!;
    final path = supportPath;
    // Migration's large temporary JSON heap dies with this short-lived isolate.
    final settings = await Isolate.run<Map<String, Object>>(
      () => _readSettingsFile(path),
    );
    _settings = settings;
    return settings;
  }

  Future<Map<String, Object>> _loadFile() async {
    final exists = await _settingsFile.exists();
    final text = exists ? await _settingsFile.readAsString(encoding: utf8) : '';
    final all = text.isEmpty
        ? <String, Object>{}
        : Map<String, Object>.from(jsonDecode(text) as Map);
    final history = all.keys.where(isHistoryKey).toList();
    if (history.isNotEmpty) {
      // Keep the untouched original; publish the small settings file only
      // after every history value is durably written. Interrupted migration
      // can be repeated from the original file without losing any records.
      final backup = File(
        '$supportPath/shared_preferences.before_history_split.json',
      );
      if (!await backup.exists()) {
        await _settingsFile.copy('${backup.path}.tmp');
        await File('${backup.path}.tmp').rename(backup.path);
      }
      for (final key in history) {
        await _writeJson(_record(key), {'key': key, 'value': all[key]});
      }
      for (final key in history) {
        all.remove(key);
      }
      await _writeJson(_settingsFile, all);
    }
    return all;
  }

  Future<Map<String, Object>> getAll(
    String prefix,
    Set<String>? allowList,
  ) async => {
    for (final entry in (await _load()).entries)
      if (entry.key.startsWith(prefix) &&
          (allowList == null || allowList.contains(entry.key)))
        entry.key: entry.value,
  };

  Future<Object?> readHistory(String key) async {
    await _load();
    if (!isHistoryKey(key)) throw ArgumentError.value(key, 'history key');
    final file = _record(key);
    if (!await file.exists()) return null;
    final record = jsonDecode(await file.readAsString(encoding: utf8)) as Map;
    if (record['key'] != key) {
      throw const FormatException('History key mismatch');
    }
    return record['value'];
  }

  Future<bool> setValue(String key, Object value) async {
    final settings = await _load();
    if (isHistoryKey(key)) {
      // The history store already skips unchanged archives.
      await _writeJson(_record(key), {'key': key, 'value': value});
    } else {
      final previous = settings[key];
      if (previous == value ||
          (previous is List &&
              value is List &&
              previous.length == value.length &&
              previous.indexed.every((item) => item.$2 == value[item.$1]))) {
        return true;
      }
      final next = {...settings, key: value};
      await _writeJson(_settingsFile, next);
      _settings = next;
    }
    return true;
  }

  Future<bool> remove(String key) async {
    final settings = await _load();
    if (isHistoryKey(key)) {
      final file = _record(key);
      if (await file.exists()) await file.delete();
    } else if (settings.containsKey(key)) {
      final next = {...settings}..remove(key);
      await _writeJson(_settingsFile, next);
      _settings = next;
    }
    return true;
  }

  Future<bool> clear(String prefix, Set<String>? allowList) async {
    final settings = await _load();
    final next = {...settings}
      ..removeWhere(
        (key, _) =>
            key.startsWith(prefix) &&
            (allowList == null || allowList.contains(key)),
      );
    if (next.length != settings.length) {
      await _writeJson(_settingsFile, next);
      _settings = next;
    }
    // SharedPreferences.clear clears settings, not separately stored history.
    return true;
  }
}
