import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
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
    'main UI persists accepted information and EEW state for background',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      provider.handleUnifiedEventForTest(_informationEvent());
      provider.handleUnifiedEventForTest(_eewEvent());
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final seenInformation =
          prefs.getStringList(
            BackgroundEventProcessor.seenUnifiedInfoEventsPreferenceKey,
          ) ??
          const <String>[];
      final acceptedEew =
          prefs.getStringList(
            BackgroundEventProcessor.acceptedEewReportNumsPreferenceKey,
          ) ??
          const <String>[];

      expect(
        seenInformation.any(
          (row) => row.startsWith('fssnEqlist|handoff-info|'),
        ),
        isTrue,
      );
      expect(
        acceptedEew.any((row) => row.startsWith('jmaEew|handoff-eew|5|')),
        isTrue,
      );
    },
  );

  test('restored information updates UI without replaying notifications',
      () async {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final report = _informationEvent();
    var notificationCount = 0;
    provider.onUnifiedEventNotified = (_, _) => notificationCount++;

    provider.handleUnifiedEventForTest(report,
        alreadyAccepted: true, suppressEffects: true);

    expect(provider.unifiedEvents.single.eventId, report.eventId);
    expect(notificationCount, 0);
  });
}

UnifiedQuakeData _informationEvent() {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: 'fssnEqlist',
    origin: 1,
    eventId: 'handoff-info',
    isEew: false,
    timeZone: 0,
    titleText: '地震信息',
    reportNumText: '正式测定',
    useShindo: false,
    maxIntensity: '4',
    className: 'green',
    hypocenter: '测试区域',
    originTime: now.subtract(const Duration(minutes: 1)),
    reportTime: now,
    magnitude: 5,
    depth: 10,
    depthText: '深度: 10km',
    lat: 30,
    lng: 120,
  );
}

UnifiedQuakeData _eewEvent() {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: 'jmaEew',
    origin: 1,
    eventId: 'handoff-eew',
    isEew: true,
    timeZone: 0,
    titleText: '紧急地震速报',
    reportNumText: '第5报',
    useShindo: true,
    maxIntensity: '5-',
    className: 'orange',
    hypocenter: '测试区域',
    originTime: now.subtract(const Duration(seconds: 5)),
    reportTime: now,
    magnitude: 5.5,
    depth: 20,
    depthText: '深度: 20km',
    lat: 35,
    lng: 139,
  );
}
