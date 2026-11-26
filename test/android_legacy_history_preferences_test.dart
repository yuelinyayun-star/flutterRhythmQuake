import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/history_storage_io.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  const personalKey = 'unified_eew_history_event_personal';
  const publicKey = 'unified_eew_history_public_event_public';
  const archiveKey = 'unified_eew_history_station_archive_nied_old';
  const indexKey = 'unified_eew_history_index_v2';
  const report = '{"title":"地震情報","payload":"原始报文\\n"}';
  const archive = 'original-compressed-station-archive';
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rq-legacy-history-');
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'legacy history moves without changing either edition or settings',
    () async {
      final preferences = InMemorySharedPreferencesStore.withData({
        'flutter.$personalKey': report,
        'flutter.$publicKey': report,
        'flutter.$archiveKey': archive,
        'flutter.$indexKey': [personalKey],
        'flutter.background_enabled': true,
        'flutter.eew_history_keep_forever': true,
      });
      await migrateAndroidHistoryPreferences(directory.path, preferences);
      await migrateAndroidHistoryPreferences(directory.path, preferences);

      expect(await preferences.getAll(), {
        'flutter.background_enabled': true,
        'flutter.eew_history_keep_forever': true,
      });

      final storage = DirectoryHistoryStorage(
        directory.path,
        readMigratedPreferences: true,
      );
      addTearDown(storage.close);
      expect(await storage.read(indexKey), [personalKey]);
      expect(await storage.read(personalKey), report);
      expect(await storage.read(publicKey), report);
      expect(await storage.read(archiveKey), archive);
      await storage.writeLegacySummary(personalKey, {'group': 'summary'});
      expect(await storage.read(personalKey), report);
      await storage.write(personalKey, 'new-format-value');
      expect(await storage.read(personalKey), 'new-format-value');
    },
  );

  test(
    'a failed staged write leaves all preference originals available',
    () async {
      final original = <String, Object>{
        'flutter.$personalKey': report,
        'flutter.$publicKey': 3,
      };
      final preferences = InMemorySharedPreferencesStore.withData(original);
      await expectLater(
        migrateAndroidHistoryPreferences(directory.path, preferences),
        throwsFormatException,
      );
      expect(await preferences.getAll(), original);
    },
  );
}
