import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

class _Paths extends PathProviderWindows {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<int> _oldRemovals(String path) async {
  final backend = SharedPreferencesWindows()
    // ignore: invalid_use_of_visible_for_testing_member
    ..pathProvider = _Paths(path);
  await backend.getAll();
  final timer = Stopwatch()..start();
  await backend.remove('flutter.wauth_access_token');
  await backend.remove('flutter.wauth_api_token');
  return timer.elapsedMilliseconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['RQ_HISTORY_COPY'];
  test(
    'cold copied history startup keeps only settings and event metadata',
    () async {
      final root = Directory(path!).absolute.path;
      expect(
        root.startsWith(
          '${Directory('tmp').absolute.path}${Platform.pathSeparator}',
        ),
        isTrue,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final previous = SharedPreferencesStorePlatform.instance;
      final before = ProcessInfo.currentRss;
      final timer = Stopwatch()..start();
      final worker = await WindowsPreferencesWorker.start(root);
      SharedPreferencesStorePlatform.instance = worker;
      try {
        final settings = await worker.getAll();
        final groups = await EewHistoryStore(
          preferenceKey: 'unified_eew_history',
        ).restoreForStartup(prefs);
        expect(groups, isNotEmpty);
        expect(groups.every((group) => group.stationFrames.isEmpty), isTrue);
        final result = {
          'elapsedMs': timer.elapsedMilliseconds,
          'rssBefore': before,
          'rssAfter': ProcessInfo.currentRss,
          'settingsKeys': settings.length,
          'events': groups.length,
          'stationFrameReferences': groups.fold<int>(
            0,
            (count, group) =>
                count + (group.storedStations?.frameKeys.length ?? 0),
          ),
          'decodedStationFrames': 0,
        };
        await File('$root/cold_result.json').writeAsString(jsonEncode(result));
        debugPrint(jsonEncode(result));
      } finally {
        SharedPreferencesStorePlatform.instance = previous;
        await worker.close();
      }
    },
    skip: path == null,
  );
  test(
    'real copied history migration, lazy startup and no-op write timings',
    () async {
      final root = Directory(path!).absolute.path;
      final allowed = Directory('tmp').absolute.path;
      expect(
        root.startsWith('$allowed${Platform.pathSeparator}'),
        isTrue,
        reason: 'This probe must never run against installed application data',
      );
      final file = File('$root/shared_preferences.json');
      final originalBytes = await file.readAsBytes();
      final originalHash = sha256.convert(originalBytes).toString();
      final original = jsonDecode(utf8.decode(originalBytes)) as Map;
      final legacy = Directory('$root/legacy_benchmark');
      await legacy.create();
      await file.copy('${legacy.path}/shared_preferences.json');
      final oldMs = await compute(_oldRemovals, legacy.path);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final previous = SharedPreferencesStorePlatform.instance;
      var worker = await WindowsPreferencesWorker.start(root);
      SharedPreferencesStorePlatform.instance = worker;
      try {
        final timer = Stopwatch()..start();
        final settings = await worker.getAllWithPrefix('');
        final migrationMs = timer.elapsedMilliseconds;
        expect(
          settings.keys.any(
            (key) => key.startsWith('flutter.unified_eew_history'),
          ),
          isFalse,
        );
        final backup = File(
          '$root/shared_preferences.before_history_split.json',
        );
        expect(
          sha256.convert(await backup.readAsBytes()).toString(),
          originalHash,
        );
        var verified = 0;
        for (final key in original.keys.cast<String>()) {
          final Object? value;
          if (key.startsWith('flutter.unified_eew_history')) {
            value = await worker.readHistory(key.substring('flutter.'.length));
            verified++;
          } else {
            value = settings[key];
          }
          expect(
            sha256.convert(utf8.encode(jsonEncode(value))).toString(),
            sha256.convert(utf8.encode(jsonEncode(original[key]))).toString(),
            reason: 'Value digest must survive storage migration',
          );
        }
        await worker.close();
        worker = await WindowsPreferencesWorker.start(root);
        SharedPreferencesStorePlatform.instance = worker;
        timer.reset();
        await worker.getAll();
        final coldSettingsMs = timer.elapsedMilliseconds;
        timer.reset();
        final store = EewHistoryStore(preferenceKey: 'unified_eew_history');
        final groups = await store.restoreForStartup(prefs);
        final listMs = timer.elapsedMilliseconds;
        expect(groups, isNotEmpty);
        expect(groups.every((group) => group.stationFrames.isEmpty), isTrue);
        final before = await file.lastModified();
        timer.reset();
        await worker.remove('flutter.wauth_access_token');
        await worker.remove('flutter.wauth_api_token');
        final noopMs = timer.elapsedMilliseconds;
        expect(await file.lastModified(), before);
        final result = {
          'originalBytes': originalBytes.length,
          'settingsBytes': await file.length(),
          'verifiedHistoryValues': verified,
          'migrationMs': migrationMs,
          'coldSettingsMs': coldSettingsMs,
          'historyListMs': listMs,
          'historyEvents': groups.length,
          'decodedStationFramesAtStartup': 0,
          'oldLoginCleanupMs': oldMs,
          'newLoginCleanupMs': noopMs,
        };
        await File(
          '$root/result.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
        // No credentials or raw observations are printed.
        debugPrint(jsonEncode(result));
      } finally {
        SharedPreferencesStorePlatform.instance = previous;
        await worker.close();
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
