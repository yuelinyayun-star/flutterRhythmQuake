import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
