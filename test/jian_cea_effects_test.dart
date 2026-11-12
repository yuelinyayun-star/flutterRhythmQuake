import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/core/utils/jian_cea_eew.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/notification_settings_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/notification_service.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  final captureFile = File('test/fixtures/jian/all.json');
  final capturedText = captureFile.readAsStringSync(encoding: utf8);
  final captures = jsonDecode(capturedText) as Map;
  tearDownAll(
    () => expect(captureFile.readAsStringSync(encoding: utf8), capturedText),
  );

  for (final (type, level, color) in [
    ('cea', 6, 'yellow'),
    ('cea-pr', 4, 'blue'),
  ]) {
    test('original $type speech and threshold use the badge estimate', () {
      final raw = Map<String, dynamic>.from(
        (captures['source：$type'] as Map)['Data'] as Map,
      );
      final before = jsonEncode(raw);
      final event = QuakeEventAdapter.convertJian(type, raw)!;
      final saved = jsonEncode(event.toMap());
      expect(jianCeaEstimatedIntensity(event), level);
      expect(effectiveEewIntensityText(event), '$level');
      expect(effectiveEewClassName(event), color);
      expect(
        AlertVoiceHelper.generateUnifiedEventText(event, phase: 'first'),
        contains('预计最大烈度$level'),
      );
      expect(event.maxIntensity, '-');
      expect(event.className, 'gray');
      expect(jsonEncode(event.toMap()), saved);
      expect(jsonEncode(raw), before);
    });
  }

  test('derived thresholds preserve source warning flags and other feeds', () {
    final event = model(magnitude: 6);
    expect(effectiveEewWarn(event), isTrue);
    expect(event.isWarn, isFalse);
    expect(
      effectiveEewWarn(event.copyWith(sourcePayload: {'isWarn': false})),
      isFalse,
    );
    for (final invalid in [
      event.copyWith(isCanceled: true),
      event.copyWith(isAssumption: true),
      event.copyWith(sourcePayload: {'isTraining': true}),
      event.copyWith(depth: -1),
      event.copyWith(magnitude: double.nan),
      event.copyWith(apiTypeLabel: 'FAN'),
      event.copyWith(source: 'sa'),
    ]) {
      expect(effectiveEewWarn(invalid), isFalse);
      expect(jianCeaEstimatedIntensity(invalid), isNull);
    }
    // Saved history still needs the same badge estimate; it must not issue a
    // derived live warning. Presentation and notification admission differ.
    final historical = event.copyWith(isHistory: true);
    expect(effectiveEewWarn(historical), isFalse);
    expect(
      jianCeaEstimatedIntensity(historical),
      jianCeaEstimatedIntensity(event),
    );
    final reported = event.copyWith(maxIntensity: '6.5', className: 'orange');
    expect(jianCeaEstimatedIntensity(reported), isNull);
    expect(effectiveEewWarn(reported), isTrue);
    expect(
      AlertVoiceHelper.generateUnifiedEventText(reported, phase: 'first'),
      contains('预计最大烈度6.5'),
    );
  });

  testWidgets('Jian CEA estimate plays caution, then warning on upgrade', (
    tester,
  ) async {
    final provider = QuakeProvider(startCatalogServices: false);
    final settings = NotificationSettingsProvider();
    final played = <String>[];
    final notifications = NotificationService(
      provider,
      settings,
      playSound: played.add,
    );
    try {
      await tester.pump();
      final first = model();
      provider.handleUnifiedEventForTest(first);
      expect(played, ['issue', 'caution']);
      provider.handleUnifiedEventForTest(
        first.copyWith(magnitude: 6, reportNumText: '第2報'),
      );
      expect(played, ['issue', 'caution', 'update', 'warn']);
      expect(provider.unifiedEvents.single.maxIntensity, '-');
      expect(provider.unifiedEvents.single.isWarn, isFalse);
    } finally {
      notifications.dispose();
      provider.dispose();
      settings.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });

  test(
    'same-report enrichment updates desktop and background without rollback',
    () {
      final provider = QuakeProvider(startCatalogServices: false);
      addTearDown(provider.dispose);
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final first = model();
      final enriched = first.copyWith(maxIntensity: '7', className: 'orange');
      provider.handleUnifiedEventForTest(first);
      expect(
        background.process(first).type,
        BackgroundEventResultType.newEvent,
      );
      provider.handleUnifiedEventForTest(enriched);
      expect(
        background.process(enriched).type,
        BackgroundEventResultType.update,
      );
      expect(provider.unifiedEvents.single.maxIntensity, '7');
      for (final stale in [
        first,
        enriched,
        first.copyWith(reportNumText: '第0報'),
        enriched.copyWith(maxIntensity: '8', isSnapshot: true),
        enriched.copyWith(maxIntensity: '8', origin: 1, apiTypeLabel: 'FAN'),
      ]) {
        provider.handleUnifiedEventForTest(stale);
        expect(
          background.process(stale).type,
          BackgroundEventResultType.dropped,
        );
        expect(provider.unifiedEvents.single.maxIntensity, '7');
      }
    },
  );

  test('same-report revisions need a newer source time or pure enrichment', () {
    final first = model();
    expect(
      isJianCeaSameReportRevision(
        first,
        first.copyWith(maxIntensity: '7', magnitude: 6),
      ),
      isFalse,
    );
    final older = first.copyWith(reportTime: first.originTime);
    final newer = older.copyWith(
      magnitude: 6,
      reportTime: first.originTime!.add(const Duration(seconds: 1)),
    );
    expect(isJianCeaSameReportRevision(older, newer), isTrue);
    expect(isJianCeaSameReportRevision(newer, older), isFalse);
    final provider = QuakeProvider(startCatalogServices: false);
    addTearDown(provider.dispose);
    final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
    provider.handleUnifiedEventForTest(older);
    expect(background.process(older).type, BackgroundEventResultType.newEvent);
    provider.handleUnifiedEventForTest(newer);
    expect(background.process(newer).type, BackgroundEventResultType.update);
    provider.handleUnifiedEventForTest(older);
    expect(background.process(older).type, BackgroundEventResultType.dropped);
    expect(provider.unifiedEvents.single.magnitude, newer.magnitude);
  });

  test(
    'derived warning upgrade speaks when ordinary updates are disabled',
    () async {
      if (!Platform.isWindows) return;
      final tts = TtsService();
      await tts.init();
      await tts.stop();
      await tts.configure(
        enabled: true,
        eventEnabled: true,
        updateEnabled: false,
        gptSovitsEnabled: false,
        persist: false,
      );
      final spoken = <String>[];
      tts.windowsSpeechOverrideForTest = (text) async => spoken.add(text);
      addTearDown(() async {
        await tts.stop();
        tts.windowsSpeechOverrideForTest = null;
      });
      final provider = QuakeProvider(startCatalogServices: false);
      addTearDown(provider.dispose);
      final first = model();
      provider.handleUnifiedEventForTest(first);
      provider.handleUnifiedEventForTest(
        first.copyWith(magnitude: 6, reportNumText: '第2報'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(spoken, hasLength(1));
      expect(spoken.single, contains('第2报'));
      expect(spoken.single, contains('预计最大烈度8'));
    },
  );
}

// Model-only lifecycle cases; captured observations above remain unchanged.
UnifiedQuakeData model({double magnitude = 4.7}) => UnifiedQuakeData(
  source: 'ceaEew',
  origin: QuakeEventAdapter.jianOrigin,
  eventId: 'jian-cea-model-boundary',
  isEew: true,
  timeZone: 0,
  titleText: '中国地震预警网地震预警',
  reportNumText: '第1報',
  useShindo: false,
  maxIntensity: '-',
  className: 'gray',
  hypocenter: 'model boundary',
  magnitude: magnitude,
  depth: 10,
  lat: 30,
  lng: 100,
  originTime: DateTime.now().toUtc(),
  apiTypeLabel: 'Jian Project',
  sourcePayload: const {},
);
