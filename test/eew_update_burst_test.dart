import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    await TravelTimeService().load();
  });

  tearDown(() => SoundEffectService().enabled = true);

  test(
    '20 reports keep every raw-order state update but publish one latest UI snapshot',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var listenerCalls = 0;
      final effectReports = <String>[];
      provider.addListener(() => listenerCalls++);
      provider.onUnifiedEventNotified = (event, _) {
        effectReports.add(event.reportNumText);
      };

      for (var report = 1; report <= 20; report++) {
        provider.handleUnifiedEventForTest(_jmaEew(report));
      }

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.reportNumText, '第20報');
      expect(provider.eewHistory, hasLength(1));
      expect(provider.eewHistory.single.reportCount, 20);
      expect(
        provider.eewHistory.single.reports.map((event) => event.reportNumText),
        orderedEquals([
          for (var report = 20; report >= 1; report--) '第$report報',
        ]),
      );

      // 首报立即发布；其余 19 报在同一个突发窗口内不逐报重建 UI。
      expect(listenerCalls, 1);
      expect(effectReports, ['第1報']);

      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(listenerCalls, 2);
      expect(provider.unifiedEvents.single.reportNumText, '第20報');

      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(effectReports, ['第1報', '第20報']);
      provider.dispose();
    },
  );

  test(
    'final report bypasses burst merging and cancels stale effects',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var listenerCalls = 0;
      final effectReports = <String>[];
      provider.addListener(() => listenerCalls++);
      provider.onUnifiedEventNotified = (event, _) {
        effectReports.add(event.reportNumText);
      };

      for (var report = 1; report < 20; report++) {
        provider.handleUnifiedEventForTest(_jmaEew(report));
      }
      provider.handleUnifiedEventForTest(_jmaEew(20, isFinal: true));

      expect(provider.unifiedEvents.single.reportNumText, '第20報（最終）');
      expect(provider.unifiedEvents.single.isFinal, isTrue);
      expect(provider.eewHistory.single.reportCount, 20);
      expect(listenerCalls, 2);
      expect(effectReports, ['第1報', '第20報（最終）']);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(listenerCalls, 2);
      expect(effectReports, ['第1報', '第20報（最終）']);
      provider.dispose();
    },
  );

  test(
    'cancel report bypasses burst merging and cancels stale effects',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var listenerCalls = 0;
      final effectReports = <String>[];
      provider.addListener(() => listenerCalls++);
      provider.onUnifiedEventNotified = (event, _) {
        effectReports.add(event.reportNumText);
      };

      provider.handleUnifiedEventForTest(_jmaEew(1));
      provider.handleUnifiedEventForTest(_jmaEew(2));
      provider.handleUnifiedEventForTest(_jmaEew(3, isCanceled: true));

      expect(provider.unifiedEvents.single.reportNumText, '第3報');
      expect(provider.unifiedEvents.single.isCanceled, isTrue);
      expect(provider.eewHistory.single.reportCount, 3);
      expect(listenerCalls, 2);
      expect(effectReports, ['第1報', '第3報']);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(listenerCalls, 2);
      expect(effectReports, ['第1報', '第3報']);
      provider.dispose();
    },
  );

  test('unchanged EEW reports do not fill the voice queue', () async {
    if (!Platform.isWindows) return;
    final tts = TtsService();
    await tts.init();
    await tts.stop();
    await tts.configure(
      enabled: true,
      eventEnabled: true,
      updateEnabled: true,
      gptSovitsEnabled: false,
      persist: false,
    );
    final spoken = <String>[];
    tts.windowsSpeechOverrideForTest = (text) async => spoken.add(text);
    addTearDown(() async {
      await tts.stop();
      tts.windowsSpeechOverrideForTest = null;
    });
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    for (var report = 1; report <= 20; report++) {
      provider.handleUnifiedEventForTest(_jmaEew(report));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(spoken, hasLength(1));
    expect(spoken.single, contains('第1报'));

    provider.handleUnifiedEventForTest(_jmaEew(21).copyWith(maxIntensity: '6'));
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    expect(spoken, hasLength(2));
    expect(spoken.last, contains('第21报'));
  });

  test(
    'warning upgrade speaks even when ordinary updates are disabled',
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
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.handleUnifiedEventForTest(
        _jmaEew(
          1,
        ).copyWith(isWarn: false, maxIntensity: '2', className: 'gray'),
      );
      provider.handleUnifiedEventForTest(
        _jmaEew(2).copyWith(isWarn: true, maxIntensity: '5', className: 'red'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(spoken, hasLength(1));
      expect(spoken.single, contains('第2报'));
    },
  );
}

UnifiedQuakeData _jmaEew(
  int report, {
  bool isFinal = false,
  bool isCanceled = false,
}) {
  // Unified JMA 时间按“无时区的 JST 墙上时间”解释。
  final now = DateTime.now().toUtc().add(const Duration(hours: 9));
  return UnifiedQuakeData(
    source: 'jmaEew',
    origin: 0,
    eventId: '20260728152718',
    isEew: true,
    timeZone: 9,
    titleText: isCanceled ? '緊急地震速報（キャンセル）' : '緊急地震速報（警報）',
    reportNumText: '第$report報${isFinal ? '（最終）' : ''}',
    useShindo: true,
    maxIntensity: isCanceled ? 'なし' : '7',
    className: isCanceled ? 'dark-gray' : 'purple',
    hypocenter: isCanceled ? '取り消されました' : '熊本県熊本地方',
    originTime: now.subtract(const Duration(seconds: 5)),
    reportTime: now,
    magnitude: 7.1,
    depth: 16,
    depthText: '深さ: 16km',
    lat: 32.625,
    lng: 130.6783,
    isWarn: !isCanceled,
    isFinal: isFinal,
    isCanceled: isCanceled,
    warnArea: '[{"name":"熊本県熊本","intensity":"7","className":"purple"}]',
  );
}
