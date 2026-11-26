import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'history_storage.dart';
import 'windows_preferences_worker.dart';
import 'replay_history_files.dart';
import 'native_replay_history_files_io.dart';
import '../models/station_history_frame.dart';
import '../models/unified_quake_data.dart';

String? _portableRoot;

Future<void> initializeHistoryFileStorage() async {
  if (SharedPreferencesStorePlatform.instance is WindowsPreferencesWorker) {
    return;
  }
  final root =
      '${(await getApplicationSupportDirectory()).path}/replay_history/v3';
  if (Platform.isAndroid) {
    final token = RootIsolateToken.instance!;
    try {
      await Isolate.run(() async {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        await migrateAndroidHistoryPreferences(
          root,
          SharedPreferencesStorePlatform.instance,
        );
      }, debugName: 'migrate-legacy-history-preferences');
    } catch (error) {
      // The original preferences remain available if staging or readback fails.
      debugPrint('Legacy EEW history migration failed: ${error.runtimeType}');
    }
  }
  _portableRoot = root;
}

HistoryStorage? separateHistoryStorage() {
  final backend = SharedPreferencesStorePlatform.instance;
  return backend is WindowsPreferencesWorker
      ? _WindowsHistoryStorage(backend)
      : _portableRoot == null
      ? null
      : DirectoryHistoryStorage(
          _portableRoot!,
          readMigratedPreferences: Platform.isAndroid,
        );
}

ReplayHistoryFiles _openHistoryFiles(String root) =>
    NativeReplayHistoryFiles.supported
    ? NativeReplayHistoryFiles(root)
    : ReplayHistoryFiles(root);

String _legacyPreferencesPath(String root) => '$root/legacy_preferences';

@visibleForTesting
Future<void> migrateAndroidHistoryPreferences(
  String root,
  SharedPreferencesStorePlatform preferences,
) async {
  const preferencePrefix = 'flutter.';
  const historyPrefix = '${preferencePrefix}unified_eew_history';
  final history = Map.of(
    await preferences.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: historyPrefix)),
    ),
  );
  history.removeWhere(
    (key, _) => key != historyPrefix && !key.startsWith('${historyPrefix}_'),
  );
  if (history.isEmpty) return;

  final destination = await Directory(
    _legacyPreferencesPath(root),
  ).create(recursive: true);
  // Android can start the UI and the service in separate isolate groups.
  // Each migrator stages in its own directory and publishes immutable values.
  final staging = await destination.createTemp('migration-');
  final stagedFiles = _openHistoryFiles(staging.path);
  final legacyFiles = _openHistoryFiles(destination.path);
  try {
    for (final entry in history.entries) {
      final key = entry.key.substring(preferencePrefix.length);
      final value = entry.value;
      if (value is! String &&
          (value is! List || value.any((v) => v is! String))) {
        throw const FormatException('Invalid legacy EEW history preference');
      }
      await stagedFiles.writeRecord(key, value, null);
      final saved = (await stagedFiles.record(key))?['value'];
      if (value is List && saved is List
          ? !listEquals(value, saved)
          : value != saved) {
        throw const FormatException('Legacy EEW history readback differs');
      }
      final target = File(legacyFiles.recordPath(key));
      await target.parent.create(recursive: true);
      await File(stagedFiles.recordPath(key)).rename(target.path);
    }
    if (!await preferences.clearWithParameters(
      ClearParameters(
        filter: PreferencesFilter(
          prefix: historyPrefix,
          allowList: history.keys.toSet(),
        ),
      ),
    )) {
      throw StateError(
        'Unable to commit legacy EEW history preference removal',
      );
    }
  } finally {
    stagedFiles.dispose();
    legacyFiles.dispose();
    await staging.delete(recursive: true);
  }
}

/// IO platforms use the same file layout. Preferences are a read-only legacy
/// migration source, never the destination of newly received frames/reports.
class DirectoryHistoryStorage
    implements HistoryStorage, HistoryStreamingStorage {
  DirectoryHistoryStorage(String root, {bool readMigratedPreferences = false})
    : files = _openHistoryFiles(root),
      _legacyPreferences = readMigratedPreferences
          ? _openHistoryFiles(_legacyPreferencesPath(root))
          : null;
  final ReplayHistoryFiles files;
  final ReplayHistoryFiles? _legacyPreferences;
  @override
  bool get separate => true;
  @override
  Future<Object?> read(String key) async =>
      (await files.record(key))?['value'] ??
      (await _legacyPreferences?.record(key))?['value'] ??
      (await SharedPreferences.getInstance()).get(key);
  @override
  Future<bool> write(String key, Object value) =>
      files.writeRecord(key, value, null);
  @override
  Future<bool> remove(String key) => files.remove(key);
  @override
  Future<Map<String, dynamic>?> readSnapshot(String key) async {
    final value = (await files.record(key))?['snapshot'];
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) => files.writeRecord(key, value, snapshot);
  @override
  Future<bool> writeLegacySummary(String key, Map<String, dynamic> snapshot) =>
      files.writeRecord(key, null, snapshot);
  @override
  String reportPath(String key, String digest) => files.reportPath(key, digest);
  @override
  String framePath(String key) => files.framePath(key);
  @override
  Future<String> writeReport(String key, Map<String, dynamic> report) async {
    await flushPending();
    return files.writeReport(key, report);
  }

  @override
  Future<UnifiedQuakeData> readReport(String key, String digest) async {
    await flushPending();
    return UnifiedQuakeData.fromMap(await files.readReport(key, digest));
  }

  @override
  Future<void> writeFrame(String key, Map<String, dynamic> frame) async {
    await flushPending();
    await files.writeFrame(key, frame);
  }

  @override
  Future<StationHistoryFrame> readFrame(String key) async {
    await flushPending();
    return StationHistoryFrame.fromMap(await files.readFrame(key));
  }

  @override
  Future<void> removeFrame(String key) async {
    await flushPending();
    await files.remove(key, frame: true);
  }

  @override
  void acceptFrame(String key, Map<String, dynamic> frame) =>
      files.acceptFrame(key, frame);
  @override
  String acceptReport(String key, Map<String, dynamic> report) =>
      files.acceptReport(key, report);
  @override
  Map<String, dynamic> get pendingStatus => files.pendingStatus;
  @override
  Future<void> flushPending() => files.flushPending();
  @override
  void retryPending() => files.retryPending();
  @override
  Future<void> close() async {
    await flushPending();
    files.dispose();
    _legacyPreferences?.dispose();
  }
}

class _WindowsHistoryStorage
    implements HistoryStorage, HistoryStreamingStorage {
  _WindowsHistoryStorage(this.worker);
  final WindowsPreferencesWorker worker;
  @override
  bool get separate => true;
  @override
  Future<Object?> read(String key) => worker.replayFileOperation('read', [key]);
  @override
  Future<bool> write(String key, Object value) => worker
      .replayFileOperation('write', [key, value, null])
      .then((v) => v as bool);
  @override
  Future<bool> remove(String key) =>
      worker.replayFileOperation('remove', [key]).then((v) => v as bool);
  @override
  Future<Map<String, dynamic>?> readSnapshot(String key) => worker
      .replayFileOperation('snapshot', [key])
      .then((v) => v == null ? null : Map<String, dynamic>.from(v as Map));
  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) => worker
      .replayFileOperation('write', [key, value, snapshot])
      .then((v) => v as bool);

  ReplayHistoryFiles get files =>
      ReplayHistoryFiles('${worker.supportPath}/replay_history/v3');
  late final ReplayHistoryFiles _live = NativeReplayHistoryFiles.supported
      ? NativeReplayHistoryFiles(files.root)
      : ReplayHistoryFiles(files.root);
  @override
  void acceptFrame(String key, Map<String, dynamic> frame) =>
      _live.acceptFrame(key, frame);
  @override
  String acceptReport(String key, Map<String, dynamic> report) =>
      _live.acceptReport(key, report);
  @override
  Map<String, dynamic> get pendingStatus => _live.pendingStatus;
  @override
  Future<void> flushPending() => _live.flushPending();
  @override
  void retryPending() => _live.retryPending();
  @override
  Future<void> close() async {
    await flushPending();
    _live.dispose();
  }

  @override
  Future<bool> writeLegacySummary(String key, Map<String, dynamic> snapshot) =>
      worker
          .replayFileOperation('write', [key, null, snapshot])
          .then((v) => v as bool);
  @override
  String reportPath(String recordKey, String digest) =>
      files.reportPath(recordKey, digest);
  @override
  String framePath(String frameKey) => files.framePath(frameKey);
  @override
  Future<String> writeReport(String recordKey, Map<String, dynamic> report) =>
      worker
          .replayFileOperation('report-write', [recordKey, report])
          .then((v) => v as String);
  @override
  Future<UnifiedQuakeData> readReport(String recordKey, String digest) async {
    await flushPending();
    return await worker.replayFileOperation('report-read', [recordKey, digest])
        as UnifiedQuakeData;
  }

  @override
  Future<void> writeFrame(String frameKey, Map<String, dynamic> frame) async {
    await worker.replayFileOperation('frame-write', [frameKey, frame]);
  }

  @override
  Future<StationHistoryFrame> readFrame(String frameKey) async {
    await flushPending();
    return await worker.replayFileOperation('frame-read', [frameKey])
        as StationHistoryFrame;
  }

  @override
  Future<void> removeFrame(String frameKey) async {
    await worker.replayFileOperation('frame-remove', [frameKey]);
  }
}
