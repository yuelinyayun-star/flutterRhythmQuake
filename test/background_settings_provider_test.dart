import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/background_api.dart';
import 'package:flutterrhythmquake/core/background_station_connection.dart';
import 'package:flutterrhythmquake/providers/background_settings_provider.dart';

void main() {
  test('boot auto-start defaults off and persists independently', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = BackgroundSettingsProvider();

    await settings.load(prefs);
    expect(settings.enabled, isFalse);
    expect(settings.autoStartOnBoot, isFalse);

    await settings.setAutoStartOnBoot(true);
    expect(settings.autoStartOnBoot, isTrue);
    expect(prefs.getBool('background_auto_start_on_boot'), isTrue);

    final reloaded = BackgroundSettingsProvider();
    await reloaded.load(prefs);
    expect(reloaded.autoStartOnBoot, isTrue);
  });

  test(
    'station preferences persist and pause only hidden Android feeds',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = BackgroundSettingsProvider();
      await settings.load(prefs);
      const retained = {
        BackgroundStationConnection.kma,
        BackgroundStationConnection.fssn,
      };
      expect(
        BackgroundStationConnection.values.where(
          settings.keepsStationConnected,
        ),
        isEmpty,
      );
      for (final station in retained) {
        await settings.setStationConnected(station, true);
      }
      final reloaded = BackgroundSettingsProvider();
      await reloaded.load(prefs);
      expect(
        BackgroundStationConnection.values.where(
          reloaded.keepsStationConnected,
        ),
        unorderedEquals(retained),
      );
      expect(
        BackgroundStationConnection.paused(
          uiVisible: false,
          read: prefs.getBool,
        ),
        BackgroundStationConnection.values.toSet().difference(retained),
      );
      expect(
        BackgroundStationConnection.paused(
          uiVisible: true,
          read: prefs.getBool,
        ),
        isEmpty,
      );
      expect(reloaded.eewEnabled, isTrue);
      expect(reloaded.reportEnabled, isTrue);
    },
  );

  test(
    'API mode and manual choices are separate from global API settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'api_source_wolfx_enabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = BackgroundSettingsProvider();
      await settings.load(prefs);
      expect(settings.automaticApis, isTrue);
      await settings.setAutomaticApis(false);
      await settings.setApiConnected(BackgroundApi.wolfx, true);
      await settings.setApiConnected(BackgroundApi.rhythm, true);
      await settings.setAutomaticApis(true);

      final reloaded = BackgroundSettingsProvider();
      await reloaded.load(prefs);
      expect(reloaded.automaticApis, isTrue);
      expect(reloaded.keepsApiConnected(BackgroundApi.wolfx), isTrue);
      expect(reloaded.keepsApiConnected(BackgroundApi.rhythm), isTrue);
      expect(prefs.getBool('api_source_wolfx_enabled'), isFalse);

      await reloaded.setAutomaticApis(false);
      await reloaded.setApiConnected(BackgroundApi.rhythm, false);
      await settings.load(prefs);
      expect(settings.automaticApis, isFalse);
      expect(settings.keepsApiConnected(BackgroundApi.wolfx), isTrue);
      expect(settings.keepsApiConnected(BackgroundApi.rhythm), isFalse);
    },
  );
}
