import 'package:shared_preferences/shared_preferences.dart';
import 'history_storage_stub.dart'
    if (dart.library.io) 'history_storage_io.dart'
    as platform;

abstract class HistoryStorage {
  Future<Object?> read(String key);
  Future<bool> write(String key, Object value);
  Future<bool> remove(String key);
  bool get separate;
}

HistoryStorage historyStorage(SharedPreferences prefs) =>
    platform.separateHistoryStorage() ?? PreferenceHistoryStorage(prefs);

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
