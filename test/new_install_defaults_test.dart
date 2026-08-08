import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/notification_settings_provider.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'new installs use the requested data, map, notification, and TTS defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final notifications = NotificationSettingsProvider();
      await notifications.load(prefs);

      expect(QuakeMapView.fdsnSeedLinkEnabledNotifier.value, isFalse);
      expect(MapStateProvider().isOverlayEnabled('typhoonLayer'), isFalse);
      expect(UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value, isFalse);
      expect(notifications.onEew.notification, isFalse);
      expect(notifications.onEew.sound, isTrue);
      expect(notifications.onEew.focus, isFalse);
      expect(notifications.onEewWarn.notification, isFalse);
      expect(notifications.onEewWarn.sound, isTrue);
      expect(notifications.onEewWarn.focus, isFalse);
      expect(notifications.onReport.notification, isFalse);
      expect(notifications.onReport.sound, isTrue);
      expect(notifications.onReport.focus, isFalse);

      final tts = TtsService();
      await tts.init();
      expect(tts.enabled, isFalse);
      expect(tts.eventEnabled, isFalse);
      expect(tts.countdownEnabled, isFalse);
      expect(tts.updateEnabled, isFalse);
      expect(tts.gptSovitsEnabled, isFalse);
    },
  );

  test(
    'saved notification values still override new-install defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'notif_settings_onEew_sound': false,
        'notif_settings_onEewWarn_sound': false,
        'notif_settings_onReport_sound': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final notifications = NotificationSettingsProvider();

      await notifications.load(prefs);

      expect(notifications.onEew.sound, isFalse);
      expect(notifications.onEewWarn.sound, isFalse);
      expect(notifications.onReport.sound, isFalse);
    },
  );
}
