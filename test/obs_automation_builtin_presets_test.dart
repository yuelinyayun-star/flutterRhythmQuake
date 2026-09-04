import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/obs_automation_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final input = ObsAutomationInputService();

  setUp(input.resetForTest);
  tearDown(input.resetForTest);

  test(
    'EEW M5 preset contains one complete flow for every supported agency',
    () {
      var sequence = 0;
      final preset = buildEewM5RecordingPreset(
        nextId: (prefix) => '$prefix-${sequence++}',
      );

      expect(preset.name, obsEewM5RecordingPresetName);
      expect(preset.enabled, isFalse);
      expect(preset.stacks, hasLength(7));

      final expectedRules = <String, ({String stopAgency, bool reviewed})>{
        'cea': (stopAgency: 'cenc', reviewed: true),
        'sichuan': (stopAgency: 'cenc', reviewed: true),
        'fujian': (stopAgency: 'cenc', reviewed: true),
        'chongqing': (stopAgency: 'cenc', reviewed: true),
        'jma': (stopAgency: 'jma', reviewed: false),
        'cwa': (stopAgency: 'cwa', reviewed: false),
        'kma': (stopAgency: 'kma', reviewed: false),
      };

      for (final stack in preset.stacks) {
        final eewAgency = _singleBlock(stack, ObsAutomationBlockType.eewAgency);
        final triggerAgency = eewAgency.parameters['value']!;
        final expected = expectedRules[triggerAgency];
        expect(expected, isNotNull, reason: 'unexpected agency $triggerAgency');
        expect(
          _singleBlock(stack, ObsAutomationBlockType.unifiedPhase).parameters,
          containsPair('value', 'added'),
        );
        expect(
          _singleBlock(stack, ObsAutomationBlockType.magnitude).parameters,
          containsPair('value', '5.0'),
        );
        expect(
          _singleBlock(
            stack,
            ObsAutomationBlockType.setValueVariable,
          ).parameters,
          containsPair('name', 'EEW发报机构'),
        );
        expect(
          _singleBlock(
            stack,
            ObsAutomationBlockType.setEventVariable,
          ).parameters,
          containsPair('name', '目标EEW'),
        );
        expect(
          _singleBlock(
            stack,
            ObsAutomationBlockType.informationAgency,
          ).parameters['value'],
          expected!.stopAgency,
        );
        expect(
          stack.blocks
              .where(
                (block) =>
                    block.type == ObsAutomationBlockType.informationReviewType,
              )
              .isNotEmpty,
          expected.reviewed,
        );
        expect(
          _singleBlock(
            stack,
            ObsAutomationBlockType.sameEarthquakeAsVariable,
          ).parameters['variable'],
          '目标EEW',
        );
        expect(
          stack.blocks.map((block) => block.type),
          containsAllInOrder([
            ObsAutomationBlockType.startRecord,
            ObsAutomationBlockType.waitForUnifiedEvent,
            ObsAutomationBlockType.wait,
            ObsAutomationBlockType.stopRecord,
            ObsAutomationBlockType.stopScript,
          ]),
        );
        expect(
          _singleBlock(stack, ObsAutomationBlockType.wait).parameters,
          containsPair('seconds', '20'),
        );
      }

      final jmaStack = preset.stacks.singleWhere(
        (stack) =>
            _singleBlock(
              stack,
              ObsAutomationBlockType.eewAgency,
            ).parameters['value'] ==
            'jma',
      );
      expect(
        _singleBlock(
          jmaStack,
          ObsAutomationBlockType.inputFieldCondition,
        ).parameters,
        containsPair('value', '震源'),
      );
    },
  );

  test('M4.9 EEW does not start recording', () async {
    final executor = _FakeActionExecutor();
    final runner = _runner(input, executor);
    addTearDown(runner.dispose);

    input.emitUnifiedEvent(
      _event(
        source: 'ceaEew',
        eventId: 'cea-m49',
        isEew: true,
        originTime: DateTime.utc(2026, 8, 21, 12),
        magnitude: 4.9,
      ),
      ObsUnifiedEventPhase.added,
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(executor.types, isEmpty);
    expect(runner.activeWaiterCount, 0);
  });

  test('China EEW waits for matching CENC reviewed report', () async {
    final executor = _FakeActionExecutor();
    final runner = _runner(input, executor);
    addTearDown(runner.dispose);
    final originTime = DateTime.utc(2026, 8, 21, 12);

    input.emitUnifiedEvent(
      _event(
        source: 'ceaEew',
        eventId: 'cea-m5',
        isEew: true,
        originTime: originTime,
        magnitude: 5,
      ),
      ObsUnifiedEventPhase.added,
    );
    await _waitUntil(() => runner.activeWaiterCount == 1);
    expect(executor.types, [ObsAutomationBlockType.startRecord]);

    input.emitUnifiedEvent(
      _event(
        source: 'cencEqlist',
        eventId: 'cenc-auto',
        isEew: false,
        originTime: originTime.add(const Duration(seconds: 10)),
        reportNumText: '自动测定',
      ),
      ObsUnifiedEventPhase.added,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runner.activeWaiterCount, 1);
    expect(executor.types, [ObsAutomationBlockType.startRecord]);

    input.emitUnifiedEvent(
      _event(
        source: 'cencEqlist',
        eventId: 'cenc-other',
        isEew: false,
        originTime: originTime.add(const Duration(seconds: 10)),
        lat: 39.9,
        lng: 116.4,
        reportNumText: '正式测定',
      ),
      ObsUnifiedEventPhase.added,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runner.activeWaiterCount, 1);

    input.emitUnifiedEvent(
      _event(
        source: 'cencEqlist',
        eventId: 'cenc-reviewed',
        isEew: false,
        originTime: originTime.add(const Duration(seconds: 12)),
        reportNumText: '正式测定',
      ),
      ObsUnifiedEventPhase.added,
    );
    await _waitUntil(() => executor.types.length == 2);
    expect(executor.types, [
      ObsAutomationBlockType.startRecord,
      ObsAutomationBlockType.stopRecord,
    ]);
    expect(runner.activeWaiterCount, 0);
  });

  test(
    'JMA ignores non-hypocenter bulletins and investigation state',
    () async {
      final executor = _FakeActionExecutor();
      final runner = _runner(input, executor);
      addTearDown(runner.dispose);
      final originTime = DateTime.utc(2026, 8, 21, 12);

      input.emitUnifiedEvent(
        _event(
          source: 'jmaEew',
          eventId: 'jma-eew',
          isEew: true,
          originTime: originTime,
          magnitude: 5.2,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => runner.activeWaiterCount == 1);

      for (final title in ['震度速報', '各地の震度に関する情報']) {
        input.emitUnifiedEvent(
          _event(
            source: 'jmaEqlist',
            eventId: 'jma-$title',
            isEew: false,
            originTime: originTime,
            titleText: title,
          ),
          ObsUnifiedEventPhase.added,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(runner.activeWaiterCount, 1);
      }

      input.emitUnifiedEvent(
        _event(
          source: 'jmaEqlist',
          eventId: 'jma-investigating',
          isEew: false,
          originTime: originTime,
          titleText: '震源・震度に関する情報',
          lat: null,
          lng: null,
        ),
        ObsUnifiedEventPhase.added,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runner.activeWaiterCount, 1);
      expect(executor.types, [ObsAutomationBlockType.startRecord]);

      input.emitUnifiedEvent(
        _event(
          source: 'jmaEqlist',
          eventId: 'jma-destination',
          isEew: false,
          originTime: originTime.add(const Duration(seconds: 8)),
          titleText: '震源に関する情報',
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
    },
  );

  test('JMA accepts combined P2P and WHEWS hypocenter titles', () async {
    for (final title in ['震度・震源に関する情報', '震源・震度に関する情報']) {
      input.resetForTest();
      final executor = _FakeActionExecutor();
      final runner = _runner(input, executor);
      final originTime = DateTime.utc(2026, 8, 21, 12);

      input.emitUnifiedEvent(
        _event(
          source: 'jmaEew',
          eventId: 'jma-eew-$title',
          isEew: true,
          originTime: originTime,
          magnitude: 5.5,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => runner.activeWaiterCount == 1);
      input.emitUnifiedEvent(
        _event(
          source: 'jmaEqlist',
          eventId: 'jma-info-$title',
          isEew: false,
          originTime: originTime,
          titleText: title,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
      await runner.dispose();
    }
  });

  test('CWA and KMA wait for their corresponding information agency', () async {
    for (final pair in const [
      (eew: 'cwaEew', information: 'cwaEqlist'),
      (eew: 'kmaEew', information: 'kmaEqlist'),
    ]) {
      input.resetForTest();
      final executor = _FakeActionExecutor();
      final runner = _runner(input, executor);
      final originTime = DateTime.utc(2026, 8, 21, 12);

      input.emitUnifiedEvent(
        _event(
          source: pair.eew,
          eventId: '${pair.eew}-m5',
          isEew: true,
          originTime: originTime,
          magnitude: 5,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => runner.activeWaiterCount == 1);
      input.emitUnifiedEvent(
        _event(
          source: 'cencEqlist',
          eventId: 'wrong-agency',
          isEew: false,
          originTime: originTime,
          reportNumText: '正式测定',
        ),
        ObsUnifiedEventPhase.added,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runner.activeWaiterCount, 1);
      input.emitUnifiedEvent(
        _event(
          source: pair.information,
          eventId: '${pair.information}-match',
          isEew: false,
          originTime: originTime.add(const Duration(seconds: 15)),
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
      await runner.dispose();
    }
  });
}

ObsAutomationBlock _singleBlock(
  ObsAutomationStack stack,
  ObsAutomationBlockType type,
) {
  return stack.blocks.singleWhere((block) => block.type == type);
}

ObsAutomationRunner _runner(
  ObsAutomationInputService input,
  _FakeActionExecutor executor,
) {
  var sequence = 0;
  final runner = ObsAutomationRunner(
    inputService: input,
    actionExecutor: executor,
    delay: (_) async {},
  );
  runner.configure([
    buildEewM5RecordingPreset(
      nextId: (prefix) => '$prefix-${sequence++}',
      enabled: true,
    ),
  ]);
  return runner;
}

UnifiedQuakeData _event({
  required String source,
  required String eventId,
  required bool isEew,
  required DateTime originTime,
  double magnitude = -1,
  double? lat = 31.2,
  double? lng = 103.8,
  String titleText = '地震信息',
  String reportNumText = '',
}) {
  return UnifiedQuakeData(
    source: source,
    origin: 1,
    eventId: eventId,
    isEew: isEew,
    timeZone: 8,
    titleText: isEew ? '地震预警' : titleText,
    reportNumText: reportNumText,
    useShindo: false,
    maxIntensity: '5.0',
    className: 'orange',
    hypocenter: lat == null || lng == null ? '' : '测试震中',
    originTime: originTime,
    lat: lat,
    lng: lng,
    magnitude: magnitude,
  );
}

class _FakeActionExecutor implements ObsAutomationActionExecutor {
  final List<ObsAutomationBlockType> types = [];

  @override
  Future<void> execute(ObsAutomationBlock block) async {
    types.add(block.type);
  }
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
