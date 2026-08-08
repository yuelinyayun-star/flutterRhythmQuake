import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
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
