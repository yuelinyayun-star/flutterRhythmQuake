import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final inputs = ObsAutomationInputService();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    inputs.resetForTest();
  });

  tearDown(() {
    SoundEffectService().enabled = true;
    inputs.resetForTest();
  });

  test('input field catalogue exposes complete UI and station value sets', () {
    final uiFields = obsAutomationInputFields
        .where(
          (field) =>
              field.family == ObsAutomationInputFieldFamily.common ||
              field.family == ObsAutomationInputFieldFamily.unified,
        )
        .map((field) => field.key)
        .toSet();
    final stationFields = obsAutomationInputFields
        .where(
          (field) =>
              field.family == ObsAutomationInputFieldFamily.common ||
              field.family == ObsAutomationInputFieldFamily.station,
        )
        .map((field) => field.key)
        .toSet();

    expect(uiFields, hasLength(33));
    expect(
      uiFields,
      containsAll(const {
        'inputKind',
        'phase',
        'occurredAt',
        'eventId',
        'source',
        'agency',
        'reviewType',
        'eventType',
        'isEew',
        'magnitude',
        'estimatedIntensity',
        'reportNumber',
        'reportText',
        'title',
        'uiTitle',
        'uiPrimaryText',
        'uiSecondaryText',
        'uiCompactSecondaryText',
        'uiTimeText',
        'uiBadgeLabel',
        'uiBadgeValue',
        'uiApiTypeLabel',
        'uiNotificationBody',
        'hypocenter',
        'depth',
        'latitude',
        'longitude',
        'isFinal',
        'isCanceled',
        'isWarn',
        'apiType',
        'originTime',
        'reportTime',
      }),
    );
    expect(stationFields, hasLength(16));
    expect(
      stationFields,
      containsAll(const {
        'inputKind',
        'phase',
        'occurredAt',
        'eventId',
        'latitude',
        'longitude',
        'network',
        'stationId',
        'stationName',
        'currentStationIntensity',
        'currentStationRawIntensity',
        'previousStationIntensity',
        'previousStationRawIntensity',
        'detectedStationCount',
        'networkMaxIntensity',
        'networkMaxRawIntensity',
      }),
    );
  });

  test(
    'accepted unified UI lifecycle reaches the automation input bus',
    () async {
      final received = <ObsAutomationInputEvent>[];
      final subscription = inputs.events.listen(received.add);
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      provider.handleUnifiedEventForTest(_eew(1));
      provider.handleUnifiedEventForTest(_eew(2));
      provider.handleUnifiedEventForTest(_eew(3, canceled: true));
      provider.dismissUnifiedEventForTest(provider.unifiedEvents.single);

      expect(received.map((event) => event.unifiedPhase), [
        ObsUnifiedEventPhase.added,
        ObsUnifiedEventPhase.updated,
        ObsUnifiedEventPhase.canceled,
        ObsUnifiedEventPhase.removed,
      ]);
      expect(received.every((event) => event.unifiedEvent != null), isTrue);

      provider.dispose();
      await subscription.cancel();
    },
  );

  test(
    'station input emits lifecycle edges and coalesces level changes',
    () async {
      final received = <ObsAutomationInputEvent>[];
      final subscription = inputs.events.listen(received.add);
      final now = DateTime.utc(2026, 8, 20, 12);

      inputs.ingestStationSnapshot('NIED', const []);
      inputs.ingestStationSnapshot('NIED', [
        ObsStationInputSample(
          stationId: 'A001',
          stationName: '测试站',
          active: true,
          intensityLevel: 3,
          intensity: 3.2,
          observedAt: now,
        ),
      ]);
      inputs.ingestStationSnapshot('NIED', [
        ObsStationInputSample(
          stationId: 'A001',
          stationName: '测试站',
          active: true,
          intensityLevel: 4,
          intensity: 4.1,
          observedAt: now.add(const Duration(seconds: 1)),
        ),
      ]);
      inputs.ingestStationSnapshot('NIED', [
        ObsStationInputSample(
          stationId: 'A001',
          stationName: '测试站',
          active: true,
          intensityLevel: 5,
          intensity: 5.0,
          observedAt: now.add(const Duration(seconds: 2)),
        ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 550));
      inputs.ingestStationSnapshot('NIED', const []);

      expect(received.map((event) => event.stationPhase), [
        ObsStationChangePhase.triggered,
        ObsStationChangePhase.intensityIncreased,
        ObsStationChangePhase.ended,
      ]);
      expect(received[1].previousIntensityLevel, 4);
      expect(received[1].intensityLevel, 5);
      expect(received[1].network, 'nied');

      await subscription.cancel();
    },
  );

  test(
    'legacy network callbacks expose confirmed, strong and ended edges',
    () async {
      final received = <ObsAutomationInputEvent>[];
      final subscription = inputs.events.listen(received.add);
      final now = DateTime.utc(2026, 8, 20, 12);

      inputs.ingestLegacyNetworkDetection(
        network: 'KMA',
        maxIntensity: 2,
        observedAt: now,
      );
      inputs.ingestLegacyNetworkDetection(
        network: 'KMA',
        maxIntensity: 4,
        observedAt: now.add(const Duration(seconds: 1)),
      );
      inputs.endLegacyNetworkDetection(
        network: 'KMA',
        observedAt: now.add(const Duration(seconds: 2)),
      );

      expect(received.map((event) => event.networkPhase), [
        ObsNetworkDetectionPhase.confirmed,
        ObsNetworkDetectionPhase.strong,
        ObsNetworkDetectionPhase.ended,
      ]);
      expect(received.every((event) => event.network == 'kma'), isTrue);

      await subscription.cancel();
    },
  );

  test('NIED detector lifecycle stays distinct from station edges', () async {
    final received = <ObsAutomationInputEvent>[];
    final subscription = inputs.events.listen(received.add);
    final now = DateTime.utc(2026, 8, 20, 12);

    EventDetection detection(
      EventDetectionState state,
      int maxIntensity,
      List<String> stationIds,
    ) {
      return EventDetection(
        detectorId: 'nied-test',
        sourceId: 'nied',
        eventId: 'nied-event',
        state: state,
        observedAt: now,
        memberStationIds: stationIds,
        maxIntensity: maxIntensity,
      );
    }

    inputs.ingestEventDetection(
      'NIED',
      detection(EventDetectionState.candidate, 0, ['A']),
    );
    inputs.ingestEventDetection(
      'NIED',
      detection(EventDetectionState.confirmed, 2, ['A', 'B']),
    );
    inputs.ingestEventDetection(
      'NIED',
      detection(EventDetectionState.confirmed, 3, ['A', 'B', 'C']),
    );
    inputs.ingestEventDetection(
      'NIED',
      detection(EventDetectionState.ended, -1, const []),
    );

    expect(received.map((event) => event.networkPhase), [
      ObsNetworkDetectionPhase.candidate,
      ObsNetworkDetectionPhase.confirmed,
      ObsNetworkDetectionPhase.enhanced,
      ObsNetworkDetectionPhase.ended,
    ]);

    await subscription.cancel();
  });
}

UnifiedQuakeData _eew(int report, {bool canceled = false}) {
  final time = DateTime.now().toUtc().add(const Duration(hours: 9, seconds: 5));
  return UnifiedQuakeData(
    source: 'jmaEew',
    origin: 0,
    eventId: 'obs-input-test',
    isEew: true,
    timeZone: 9,
    titleText: canceled ? '緊急地震速報（キャンセル）' : '緊急地震速報',
    reportNumText: '第$report報',
    useShindo: true,
    maxIntensity: canceled ? 'なし' : '4',
    className: canceled ? 'dark-gray' : 'red',
    hypocenter: canceled ? '取り消されました' : '测试震源',
    originTime: time.subtract(const Duration(seconds: 5)),
    reportTime: time.add(Duration(milliseconds: report)),
    magnitude: 5.0,
    depth: 10,
    depthText: '深さ: 10km',
    lat: 35,
    lng: 139,
    isCanceled: canceled,
  );
}
