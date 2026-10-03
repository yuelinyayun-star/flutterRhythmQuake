import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'history_storage.dart';
import 'windows_preferences_worker.dart';

HistoryStorage? separateHistoryStorage() {
  final backend = SharedPreferencesStorePlatform.instance;
  return backend is WindowsPreferencesWorker
      ? _WindowsHistoryStorage(backend)
      : null;
}

class _WindowsHistoryStorage implements HistoryStorage {
  _WindowsHistoryStorage(this.worker);
  final WindowsPreferencesWorker worker;
  @override
  bool get separate => true;
  @override
  Future<Object?> read(String key) => worker.readHistory(key);
  @override
  Future<bool> write(String key, Object value) =>
      worker.writeHistory(key, value);
  @override
  Future<bool> remove(String key) => worker.removeHistory(key);
}
