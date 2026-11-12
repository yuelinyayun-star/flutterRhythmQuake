import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> waitFor(
  List<String> spoken,
  int count, {
  int milliseconds = 700,
}) async {
  final end = DateTime.now().add(Duration(milliseconds: milliseconds));
  while (spoken.length < count && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(spoken, hasLength(count));
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
      updateEnabled: true,
      gptSovitsEnabled: false,
      persist: false,
    );
  });
  tearDown(() async {
    await tts.stop();
    tts.windowsSpeechOverrideForTest = null;
  });

  for (final kind in [
    EewSpeechKind.first,
    EewSpeechKind.update,
    EewSpeechKind.warn,
  ]) {
    test(
      'new update replaces a playing ${kind.name} without waiting for completion',
      () async {
        if (!Platform.isWindows) return;
        final oldFinished = Completer<void>();
        addTearDown(() {
          if (!oldFinished.isCompleted) oldFinished.complete();
        });
        final spoken = <String>[];
        tts.windowsSpeechOverrideForTest = (text) async {
          spoken.add(text);
          if (text == 'old ${kind.name}') await oldFinished.future;
        };
        final key = 'replace|${kind.name}';
        await tts.speakEew(
          'old ${kind.name}',
          eventKey: key,
          dedupeKey: '$key:1',
          kind: kind,
          delay: Duration.zero,
        );
        await waitFor(spoken, 1);
        // Default 1250ms delay must not postpone replacement of playing speech.
        await tts.speakEew(
          'latest ${kind.name}',
          eventKey: key,
          dedupeKey: '$key:2',
          kind: EewSpeechKind.update,
        );
        await waitFor(spoken, 2);
        expect(oldFinished.isCompleted, isFalse);
        expect(spoken.last, 'latest ${kind.name}');
        oldFinished.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(spoken, hasLength(2));
      },
    );
  }

  test(
    'same report key admits changed text and still suppresses exact duplicates',
    () async {
      if (!Platform.isWindows) return;
      final oldFinished = Completer<void>();
      addTearDown(() {
        if (!oldFinished.isCompleted) oldFinished.complete();
      });
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text == 'old body') await oldFinished.future;
      };
      await tts.speakEew(
        'old body',
        eventKey: 'same-report',
        dedupeKey: 'same-report:update:1',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
      await waitFor(spoken, 1);
      await tts.speakEew(
        'new body',
        eventKey: 'same-report',
        dedupeKey: 'same-report:update:1',
        kind: EewSpeechKind.update,
      );
      await waitFor(spoken, 2);
      expect(oldFinished.isCompleted, isFalse);
      await tts.speakEew(
        'new body',
        eventKey: 'same-report',
        dedupeKey: 'same-report:update:1',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(spoken, ['old body', 'new body']);
    },
  );

  test(
    'a different event update does not interrupt a playing critical EEW',
    () async {
      if (!Platform.isWindows) return;
      final finished = Completer<void>();
      addTearDown(() {
        if (!finished.isCompleted) finished.complete();
      });
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text == 'A warning') await finished.future;
      };
      await tts.speakEew(
        'A warning',
        eventKey: 'independent-A',
        dedupeKey: 'independent-A:1',
        kind: EewSpeechKind.warn,
        delay: Duration.zero,
      );
      await waitFor(spoken, 1);
      await tts.speakEew(
        'B update',
        eventKey: 'independent-B',
        dedupeKey: 'independent-B:1',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(spoken, ['A warning']);
      finished.complete();
      await waitFor(spoken, 2);
      expect(spoken.last, 'B update');
    },
  );

  test(
    'disabled updates keep playing speech; warning upgrades still replace it',
    () async {
      if (!Platform.isWindows) return;
      await tts.configure(updateEnabled: false, persist: false);
      final finished = Completer<void>();
      addTearDown(() {
        if (!finished.isCompleted) finished.complete();
      });
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text == 'first') await finished.future;
      };
      await tts.speakEew(
        'first',
        eventKey: 'switch',
        dedupeKey: 'switch:1',
        kind: EewSpeechKind.first,
        delay: Duration.zero,
      );
      await waitFor(spoken, 1);
      await tts.speakEew(
        'ordinary update',
        eventKey: 'switch',
        dedupeKey: 'switch:2',
        kind: EewSpeechKind.update,
        delay: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(spoken, ['first']);
      await tts.speakEew(
        'warning',
        eventKey: 'switch',
        dedupeKey: 'switch:warn',
        kind: EewSpeechKind.warn,
      );
      await waitFor(spoken, 2);
      expect(finished.isCompleted, isFalse);
      expect(spoken.last, 'warning');
    },
  );

  test(
    'ordered same-report revisions replace speech within the dedupe window',
    () async {
      if (!Platform.isWindows) return;
      final finished = [Completer<void>(), Completer<void>()];
      addTearDown(() {
        for (final signal in finished) {
          if (!signal.isCompleted) signal.complete();
        }
      });
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text.contains('震级4.7')) await finished[0].future;
        if (text.contains('震级4.8')) await finished[1].future;
      };
      final provider = QuakeProvider(startCatalogServices: false);
      addTearDown(provider.dispose);
      final now = DateTime.now().toUtc();
      // Model-only ordered publication states; no captured raw data is rewritten.
      final first = UnifiedQuakeData(
        source: 'ceaEew',
        origin: 4,
        eventId: 'same-report-model',
        isEew: true,
        timeZone: 0,
        titleText: '中国地震预警网地震预警',
        reportNumText: '第1报',
        useShindo: false,
        maxIntensity: '5',
        className: 'green',
        hypocenter: 'model boundary',
        magnitude: 4.7,
        depth: 10,
        lat: 30,
        lng: 100,
        originTime: now,
        reportTime: now,
        apiTypeLabel: 'Jian Project',
      );
      provider.handleUnifiedEventForTest(first);
      await waitFor(spoken, 1, milliseconds: 2200);
      for (final (magnitude, seconds) in [(4.8, 1), (4.9, 2)]) {
        provider.handleUnifiedEventForTest(
          first.copyWith(
            magnitude: magnitude,
            reportTime: now.add(Duration(seconds: seconds)),
          ),
        );
        await waitFor(spoken, seconds + 1);
        expect(spoken.last, contains('震级$magnitude'));
        expect(spoken.last, contains('第1报'));
      }
      expect(finished.every((signal) => !signal.isCompleted), isTrue);
      expect(provider.unifiedEvents.single.magnitude, 4.9);
      provider.handleUnifiedEventForTest(first);
      expect(provider.unifiedEvents.single.magnitude, 4.9);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(spoken, hasLength(3));
    },
  );

  test(
    'accepted UI reports replace playing speech even at unchanged intensity',
    () async {
      if (!Platform.isWindows) return;
      final oldFinished = Completer<void>();
      addTearDown(() {
        if (!oldFinished.isCompleted) oldFinished.complete();
      });
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        if (text.contains('第1报')) await oldFinished.future;
      };
      final provider = QuakeProvider(startCatalogServices: false);
      addTearDown(provider.dispose);
      // Model-level report lifecycle, not modified upstream observations.
      final first = UnifiedQuakeData(
        source: 'ceaEew',
        origin: 1,
        eventId: 'replacement-model',
        isEew: true,
        timeZone: 0,
        titleText: '中国地震预警网地震预警',
        reportNumText: '第1报',
        useShindo: false,
        maxIntensity: '5',
        className: 'green',
        hypocenter: 'model boundary',
        magnitude: 4.7,
        depth: 10,
        lat: 30,
        lng: 100,
        originTime: DateTime.now().toUtc(),
        apiTypeLabel: 'FAN',
      );
      provider.handleUnifiedEventForTest(first);
      await waitFor(spoken, 1, milliseconds: 2200);
      provider.handleUnifiedEventForTest(
        first.copyWith(reportNumText: '第2报', magnitude: 4.8),
      );
      provider.handleUnifiedEventForTest(
        first.copyWith(reportNumText: '第3报', magnitude: 4.9),
      );
      expect(provider.unifiedEvents.single.reportNumText, '第3报');
      await waitFor(spoken, 2);
      expect(oldFinished.isCompleted, isFalse);
      expect(spoken.last, contains('第3报'));
      expect(spoken.last, contains('震级4.9'));
      provider.handleUnifiedEventForTest(first);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(provider.unifiedEvents.single.reportNumText, '第3报');
      expect(spoken, hasLength(2));
    },
  );
}
