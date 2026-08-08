import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutterrhythmquake/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TTS restores saved switches before the first event', () async {
    SharedPreferences.setMockInitialValues({
      TtsService.enabledKey: true,
      TtsService.eventEnabledKey: true,
      TtsService.countdownEnabledKey: true,
      TtsService.updateEnabledKey: true,
    });

    final tts = TtsService();
    await tts.init();

    expect(tts.enabled, isTrue);
    expect(tts.eventEnabled, isTrue);
    expect(tts.countdownEnabled, isTrue);
    expect(tts.updateEnabled, isTrue);
  });
}
