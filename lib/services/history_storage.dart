import 'package:shared_preferences/shared_preferences.dart';
import '../models/station_history_frame.dart';
import '../models/unified_quake_data.dart';
import 'history_storage_stub.dart'
    if (dart.library.io) 'history_storage_io.dart'
    as platform;

abstract class HistoryStorage {
  Future<Object?> read(String key);
  Future<bool> write(String key, Object value);
  Future<bool> remove(String key);
  bool get separate;
}

/// A small header and the unchanged complete record commit in one atomic file.
abstract class HistorySnapshotStorage {
  Future<Map<String, dynamic>?> readSnapshot(String key);
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  );
}

/// Native history stores immutable report/frame files separately from summaries.
abstract class HistoryFileStorage implements HistorySnapshotStorage {
  Future<bool> writeLegacySummary(String key, Map<String, dynamic> snapshot);
  String reportPath(String recordKey, String digest);
  String framePath(String frameKey);
  Future<String> writeReport(String recordKey, Map<String, dynamic> report);
  Future<UnifiedQuakeData> readReport(String recordKey, String digest);
  Future<void> writeFrame(String frameKey, Map<String, dynamic> frame);
  Future<StationHistoryFrame> readFrame(String frameKey);
  Future<void> removeFrame(String frameKey);
}

/// Accepts a single original synchronously, leaving only its disk identity in
/// Dart. Completion/readers must await flushPending before using the files.
abstract class HistoryStreamingStorage implements HistoryFileStorage {
  void acceptFrame(String key, Map<String, dynamic> frame);
  String acceptReport(String key, Map<String, dynamic> report);
  Map<String, dynamic> get pendingStatus;
  Future<void> flushPending();
  void retryPending();
  Future<void> close();
}

HistoryStorage historyStorage(SharedPreferences prefs) =>
    platform.separateHistoryStorage() ?? PreferenceHistoryStorage(prefs);
HistoryStorage? standaloneHistoryStorage() => platform.separateHistoryStorage();
Future<void> initializeHistoryFileStorage() =>
    platform.initializeHistoryFileStorage();

class PreferenceHistoryStorage implements HistoryStorage {
  PreferenceHistoryStorage(this.prefs);
  final SharedPreferences prefs;
  @override
  bool get separate => false;
  @override
  Future<Object?> read(String key) async => prefs.get(key);
  @override
  Future<bool> write(String key, Object value) => value is List
      ? prefs.setStringList(key, value.cast<String>())
      : prefs.setString(key, value as String);
  @override
  Future<bool> remove(String key) =>
      prefs.containsKey(key) ? prefs.remove(key) : Future.value(true);
}
