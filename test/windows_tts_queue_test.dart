import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/p2pquake_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows TTS finishes one event before starting the next', () async {
    if (!Platform.isWindows) return;
    SharedPreferences.setMockInitialValues({
      TtsService.enabledKey: true,
      TtsService.eventEnabledKey: true,
      TtsService.updateEnabledKey: true,
    });
    final tts = TtsService();
    await tts.init();
    await tts.stop();
    final firstFinished = Completer<void>();
    final secondStarted = Completer<void>();
    final started = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async {
      started.add(text);
      if (started.length == 1) {
        await firstFinished.future;
      } else {
        secondStarted.complete();
      }
    };
    addTearDown(() async {
      if (!firstFinished.isCompleted) firstFinished.complete();
      await tts.stop();
      tts.windowsSpeechOverrideForTest = null;
    });

    await tts.speakEvent(
      'first',
      dedupeKey: 'windows-queue-first',
      delay: Duration.zero,
    );
    await tts.speakEvent(
      'second',
      dedupeKey: 'windows-queue-second',
      delay: Duration.zero,
    );
    await Future<void>.delayed(Duration.zero);
    expect(started, ['first']);

    firstFinished.complete();
    await secondStarted.future.timeout(const Duration(seconds: 2));
    expect(started, ['first', 'second']);
  });

  test('captured Kumamoto P2P event reaches Windows TTS', () async {
    if (!Platform.isWindows) return;
    SharedPreferences.setMockInitialValues({
      TtsService.enabledKey: true,
      TtsService.eventEnabledKey: true,
      TtsService.updateEnabledKey: true,
    });
    final tts = TtsService();
    await tts.init();
    await tts.stop();
    await tts.configure(enabled: true, eventEnabled: true, persist: false);
    final spoken = Completer<String>();
    tts.windowsSpeechOverrideForTest = (text) async {
      if (!spoken.isCompleted) spoken.complete(text);
    };
    addTearDown(() async {
      await tts.stop();
      tts.windowsSpeechOverrideForTest = null;
    });

    final service = P2PQuakeService();
    final eventReceived = Completer<UnifiedQuakeData>();
    final subscription = service.onUnifiedEvent.listen((event) {
      if (!eventReceived.isCompleted) eventReceived.complete(event);
    });
    addTearDown(subscription.cancel);
    addTearDown(service.dispose);
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    final raw = File(
      'test/fixtures/jma_voice/p2p_kumamoto_20260924.json',
    ).readAsStringSync();
    service.handleMessageForTesting(raw);
    final event = await eventReceived.future.timeout(
      const Duration(seconds: 2),
    );
    provider.handleUnifiedEventForTest(event, alreadyAccepted: true);

    final text = await spoken.future.timeout(const Duration(seconds: 5));
    expect(text, contains('各地震度信息'));
    expect(text, contains('观测到震度2的地区：'));
  });

  test('removing an information card drops its queued voice only', () async {
    if (!Platform.isWindows) return;
    final tts = TtsService();
    await tts.init();
    await tts.stop();
    await tts.configure(enabled: true, eventEnabled: true, persist: false);
    final blocked = Completer<void>();
    final remainingStarted = Completer<void>();
    final started = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async {
      started.add(text);
      if (text == 'blocker') await blocked.future;
      if (text == 'remaining') remainingStarted.complete();
    };
    addTearDown(() async {
      if (!blocked.isCompleted) blocked.complete();
      await tts.stop();
      tts.windowsSpeechOverrideForTest = null;
    });
    await tts.speak('blocker');
    await Future<void>.delayed(Duration.zero);
    await tts.speakEvent(
      'removed',
      dedupeKey: 'removed-info',
      eventKey: 'emsc|removed',
      delay: Duration.zero,
    );
    await tts.speakEvent(
      'remaining',
      dedupeKey: 'remaining-info',
      eventKey: 'emsc|remaining',
      delay: Duration.zero,
    );
    tts.discardEvent('emsc|removed');
    blocked.complete();
    await remainingStarted.future.timeout(const Duration(seconds: 2));
    expect(started, ['blocker', 'remaining']);
  });
}
