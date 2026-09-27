import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitForCount(List<String> spoken, int count) async {
  for (var i = 0; i < 100; i++) {
    if (spoken.length >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Expected $count spoken messages, got $spoken');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tts = TtsService();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tts.init();
    await tts.stop();
    await tts.configure(
      enabled: true,
      eventEnabled: true,
      countdownEnabled: true,
      updateEnabled: true,
      gptSovitsEnabled: false,
      persist: false,
    );
  });

  tearDown(() async {
    await tts.stop();
    tts.windowsSpeechOverrideForTest = null;
  });

  test('burst updates keep only the latest pending report per event', () async {
    if (!Platform.isWindows) return;
    final blocker = Completer<void>();
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async {
      spoken.add(text);
      if (text == 'blocker') await blocker.future;
    };
    addTearDown(() {
      if (!blocker.isCompleted) blocker.complete();
    });

    await tts.speak('blocker');
    await _waitForCount(spoken, 1);
    for (var report = 2; report <= 8; report++) {
      await tts.speakEew(
        'report $report',
        eventKey: 'JMA|burst',
        dedupeKey: 'JMA|burst:$report',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
    }
    blocker.complete();
    await _waitForCount(spoken, 2);
    expect(spoken, ['blocker', 'report 8']);
  });

  test(
    'cancel supersedes same-event updates and precedes other events',
    () async {
      if (!Platform.isWindows) return;
      final blocker = Completer<void>();
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text == 'blocker') await blocker.future;
      };
      addTearDown(() {
        if (!blocker.isCompleted) blocker.complete();
      });

      await tts.speak('blocker');
      await _waitForCount(spoken, 1);
      await tts.speakEew(
        'A update',
        eventKey: 'JMA|critical-A',
        dedupeKey: 'critical-A:update',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
      await tts.speakEew(
        'B first',
        eventKey: 'JMA|critical-B',
        dedupeKey: 'critical-B:first',
        kind: EewSpeechKind.first,
        delay: Duration.zero,
      );
      await tts.speakEew(
        'A warn',
        eventKey: 'JMA|critical-A',
        dedupeKey: 'critical-A:warn',
        kind: EewSpeechKind.warn,
        delay: Duration.zero,
      );
      await tts.speakEew(
        'A cancel',
        eventKey: 'JMA|critical-A',
        dedupeKey: 'critical-A:cancel',
        kind: EewSpeechKind.cancel,
        delay: Duration.zero,
      );
      blocker.complete();
      await _waitForCount(spoken, 3);
      expect(spoken, ['blocker', 'A cancel', 'B first']);
    },
  );

  test('a newer update invalidates one still waiting for its delay', () async {
    if (!Platform.isWindows) return;
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async => spoken.add(text);

    await tts.speakEew(
      'old report',
      eventKey: 'JMA|delayed',
      dedupeKey: 'delayed:old',
      kind: EewSpeechKind.update,
      delay: const Duration(seconds: 2),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tts.speakEew(
      'new report',
      eventKey: 'JMA|delayed',
      dedupeKey: 'delayed:new',
      kind: EewSpeechKind.update,
      delay: Duration.zero,
    );
    await _waitForCount(spoken, 1);
    expect(spoken, ['new report']);
  });

  test(
    'a pending first report uses the newest text without duplicating it',
    () async {
      if (!Platform.isWindows) return;
      final blocker = Completer<void>();
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text == 'blocker') await blocker.future;
      };
      addTearDown(() {
        if (!blocker.isCompleted) blocker.complete();
      });

      await tts.speak('blocker');
      await _waitForCount(spoken, 1);
      await tts.speakEew(
        'first report',
        eventKey: 'JMA|refresh',
        dedupeKey: 'refresh:first',
        kind: EewSpeechKind.first,
        delay: Duration.zero,
      );
      await tts.speakEew(
        'latest report',
        eventKey: 'JMA|refresh',
        dedupeKey: 'refresh:update',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
      blocker.complete();
      await _waitForCount(spoken, 2);
      expect(spoken, ['blocker', 'latest report']);
    },
  );

  test('countdown does not clear a waiting critical EEW', () async {
    if (!Platform.isWindows) return;
    final blocker = Completer<void>();
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async {
      spoken.add(text);
      if (text == 'blocker') await blocker.future;
    };
    addTearDown(() {
      if (!blocker.isCompleted) blocker.complete();
    });

    await tts.speak('blocker');
    await _waitForCount(spoken, 1);
    await tts.speakEew(
      'critical warning',
      eventKey: 'JMA|countdown',
      dedupeKey: 'countdown:warn',
      kind: EewSpeechKind.warn,
      delay: Duration.zero,
    );
    await tts.speakCountdown('JMA|countdown', 5);
    blocker.complete();
    await _waitForCount(spoken, 2);
    expect(spoken, ['blocker', 'critical warning']);
  });

  test('arrival does not interrupt or overtake a critical EEW', () async {
    if (!Platform.isWindows) return;
    final blocker = Completer<void>();
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async {
      spoken.add(text);
      if (text == 'blocker') await blocker.future;
    };
    addTearDown(() {
      if (!blocker.isCompleted) blocker.complete();
    });

    await tts.speak('blocker');
    await _waitForCount(spoken, 1);
    await tts.speakEew(
      'critical warning',
      eventKey: 'JMA|arrival',
      dedupeKey: 'arrival:warn',
      kind: EewSpeechKind.warn,
      delay: Duration.zero,
    );
    await tts.speakArrival('JMA|arrival');
    blocker.complete();
    await _waitForCount(spoken, 2);
    expect(spoken, ['blocker', 'critical warning']);
  });

  test('critical EEW cancels an ordinary report still in its delay', () async {
    if (!Platform.isWindows) return;
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async => spoken.add(text);

    await tts.speak('ordinary report', delay: const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tts.speakEew(
      'critical warning',
      eventKey: 'JMA|preempt',
      dedupeKey: 'preempt:warn',
      kind: EewSpeechKind.warn,
      delay: Duration.zero,
    );
    await _waitForCount(spoken, 1);
    expect(spoken, ['critical warning']);
  });

  test('the update switch does not silence warning or cancellation', () async {
    if (!Platform.isWindows) return;
    await tts.configure(updateEnabled: false, persist: false);
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async => spoken.add(text);

    await tts.speakEew(
      'ordinary update',
      eventKey: 'JMA|disabled',
      dedupeKey: 'disabled:update',
      kind: EewSpeechKind.update,
      delay: Duration.zero,
    );
    await tts.speakEew(
      'warning upgrade',
      eventKey: 'JMA|disabled',
      dedupeKey: 'disabled:warn',
      kind: EewSpeechKind.warn,
      delay: Duration.zero,
    );
    await _waitForCount(spoken, 1);
    expect(spoken, ['warning upgrade']);
    await tts.speakEew(
      'canceled',
      eventKey: 'JMA|disabled',
      dedupeKey: 'disabled:cancel',
      kind: EewSpeechKind.cancel,
      delay: Duration.zero,
    );
    await _waitForCount(spoken, 2);
    expect(spoken, ['warning upgrade', 'canceled']);
  });

  test('disabled updates still refresh a pending first report', () async {
    if (!Platform.isWindows) return;
    await tts.configure(updateEnabled: false, persist: false);
    final blocker = Completer<void>();
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async {
      spoken.add(text);
      if (text == 'blocker') await blocker.future;
    };
    addTearDown(() {
      if (!blocker.isCompleted) blocker.complete();
    });

    await tts.speak('blocker');
    await _waitForCount(spoken, 1);
    await tts.speakEew(
      'first report',
      eventKey: 'JMA|disabled-refresh',
      dedupeKey: 'disabled-refresh:first',
      kind: EewSpeechKind.first,
      delay: Duration.zero,
    );
    await tts.speakEew(
      'latest report',
      eventKey: 'JMA|disabled-refresh',
      dedupeKey: 'disabled-refresh:update',
      kind: EewSpeechKind.update,
      delay: Duration.zero,
    );
    blocker.complete();
    await _waitForCount(spoken, 2);
    expect(spoken, ['blocker', 'latest report']);
  });
}
