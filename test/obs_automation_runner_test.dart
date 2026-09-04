import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/obs_automation_value_expression.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/obs_automation_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final input = ObsAutomationInputService();

  setUp(input.resetForTest);

  tearDown(input.resetForTest);

  test('CEA waits for matching CENC automatic or reviewed report', () async {
    for (final reviewLabel in ['自动测定', '正式测定']) {
      final executor = _FakeActionExecutor();
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
      );
      addTearDown(runner.dispose);
      runner.configure([_ceaToCencPreset()]);

      final originTime = DateTime.utc(2026, 8, 20, 12);
      input.emitUnifiedEvent(
        _event(
          source: 'ceaEew',
          eventId: 'cea-$reviewLabel',
          isEew: true,
          originTime: originTime,
          lat: 31.2,
          lng: 103.8,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => executor.types.length == 1);
      expect(executor.types, [ObsAutomationBlockType.startRecord]);
      expect(runner.activeWaiterCount, 1);

      input.emitUnifiedEvent(
        _event(
          source: 'cencEqlist',
          eventId: 'unrelated-$reviewLabel',
          isEew: false,
          originTime: originTime,
          lat: 39.9,
          lng: 116.4,
          reportNumText: reviewLabel,
        ),
        ObsUnifiedEventPhase.added,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executor.types, [ObsAutomationBlockType.startRecord]);
      expect(runner.activeWaiterCount, 1);

      input.emitUnifiedEvent(
        _event(
          source: 'cencEqlist',
          eventId: 'matching-$reviewLabel',
          isEew: false,
          originTime: originTime.add(const Duration(seconds: 12)),
          lat: 31.3,
          lng: 103.9,
          reportNumText: reviewLabel,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
      ]);
      expect(runner.activeWaiterCount, 0);
      await runner.dispose();
      input.resetForTest();
    }
  });

  test('concurrent CEA executions keep independent event variables', () async {
    final executor = _FakeActionExecutor();
    final runner = ObsAutomationRunner(
      inputService: input,
      actionExecutor: executor,
    );
    addTearDown(runner.dispose);
    runner.configure([_ceaToCencPreset()]);
    final originTime = DateTime.utc(2026, 8, 20, 12);

    input.emitUnifiedEvent(
      _event(
        source: 'ceaEew',
        eventId: 'cea-a',
        isEew: true,
        originTime: originTime,
        lat: 31.2,
        lng: 103.8,
      ),
      ObsUnifiedEventPhase.added,
    );
    input.emitUnifiedEvent(
      _event(
        source: 'ceaEew',
        eventId: 'cea-b',
        isEew: true,
        originTime: originTime,
        lat: 39.9,
        lng: 116.4,
      ),
      ObsUnifiedEventPhase.added,
    );
    await _waitUntil(() => runner.activeWaiterCount == 2);
    expect(
      executor.types.where(
        (type) => type == ObsAutomationBlockType.startRecord,
      ),
      hasLength(1),
    );

    input.emitUnifiedEvent(
      _event(
        source: 'cencEqlist',
        eventId: 'cenc-a',
        isEew: false,
        originTime: originTime,
        lat: 31.25,
        lng: 103.85,
        reportNumText: '自动测定',
      ),
      ObsUnifiedEventPhase.added,
    );
    await _waitUntil(() => runner.activeWaiterCount == 1);
    expect(
      executor.types.where((type) => type == ObsAutomationBlockType.stopRecord),
      isEmpty,
    );

    input.emitUnifiedEvent(
      _event(
        source: 'cencEqlist',
        eventId: 'cenc-b',
        isEew: false,
        originTime: originTime,
        lat: 39.95,
        lng: 116.45,
        reportNumText: '正式测定',
      ),
      ObsUnifiedEventPhase.added,
    );
    await _waitUntil(() => runner.activeWaiterCount == 0);
    await _waitUntil(
      () =>
          executor.types
              .where((type) => type == ObsAutomationBlockType.stopRecord)
              .length ==
          1,
    );
  });

  test('disabled presets release the lightweight input subscription', () async {
    final runner = ObsAutomationRunner(
      inputService: input,
      actionExecutor: _FakeActionExecutor(),
    );
    addTearDown(runner.dispose);

    runner.configure([_ceaToCencPreset()]);
    expect(runner.isListening, isTrue);
    expect(input.hasListeners, isTrue);

    runner.configure(const []);
    await _waitUntil(() => !runner.isListening);
    expect(input.hasListeners, isFalse);
  });

  test(
    'scalar variables match later input and stop script ends execution',
    () async {
      final executor = _FakeActionExecutor();
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
      );
      addTearDown(runner.dispose);
      runner.configure([_eventIdVariablePreset()]);
      final originTime = DateTime.utc(2026, 8, 20, 12);

      input.emitUnifiedEvent(
        _event(
          source: 'ceaEew',
          eventId: 'same-event',
          isEew: true,
          originTime: originTime,
          lat: 31.2,
          lng: 103.8,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => runner.activeWaiterCount == 1);
      expect(executor.types, [ObsAutomationBlockType.startRecord]);

      input.emitUnifiedEvent(
        _event(
          source: 'cencEqlist',
          eventId: 'other-event',
          isEew: false,
          originTime: originTime,
          lat: 31.2,
          lng: 103.8,
        ),
        ObsUnifiedEventPhase.updated,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runner.activeWaiterCount, 1);

      input.emitUnifiedEvent(
        _event(
          source: 'cencEqlist',
          eventId: 'same-event',
          isEew: false,
          originTime: originTime,
          lat: 31.2,
          lng: 103.8,
        ),
        ObsUnifiedEventPhase.updated,
      );
      await _waitUntil(() => runner.activeWaiterCount == 0);
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
      ]);
    },
  );

  test(
    'generic data blocks extract, calculate, compare and feed actions',
    () async {
      final executor = _FakeActionExecutor();
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
      );
      addTearDown(runner.dispose);
      runner.configure([_genericDataPreset()]);
      final originTime = DateTime.utc(2026, 8, 20, 12);

      input.emitUnifiedEvent(
        _event(
          source: 'ceaEew',
          eventId: 'generic-data',
          isEew: true,
          originTime: originTime,
          lat: 31.2,
          lng: 103.8,
          magnitude: 5.5,
          hypocenter: '测试震中',
        ),
        ObsUnifiedEventPhase.added,
      );

      await _waitUntil(() => executor.blocks.length == 1);
      expect(
        executor.blocks.single.type,
        ObsAutomationBlockType.createRecordChapter,
      );
      expect(executor.blocks.single.parameters['text'], '测试震中 M6.0');
    },
  );

  test('network detection fields can trigger recording', () async {
    final executor = _FakeActionExecutor();
    final runner = ObsAutomationRunner(
      inputService: input,
      actionExecutor: executor,
    );
    addTearDown(runner.dispose);
    runner.configure([_networkRecordingPreset()]);

    input.ingestLegacyNetworkDetection(
      network: 'nied',
      maxIntensity: 3,
      observedAt: DateTime.utc(2026, 8, 20, 12),
    );

    await _waitUntil(() => executor.types.isNotEmpty);
    expect(executor.types, [ObsAutomationBlockType.startRecord]);
  });

  test('station trigger and level fields can trigger recording', () async {
    final executor = _FakeActionExecutor();
    final runner = ObsAutomationRunner(
      inputService: input,
      actionExecutor: executor,
    );
    addTearDown(runner.dispose);
    runner.configure([_stationRecordingPreset()]);
    final now = DateTime.utc(2026, 8, 20, 12);

    input.ingestStationSnapshot('nied', const []);
    input.ingestStationSnapshot('nied', [
      ObsStationInputSample(
        stationId: 'A001',
        stationName: '测试站',
        active: true,
        intensityLevel: 5,
        intensity: 4.7,
        observedAt: now,
      ),
    ]);

    await _waitUntil(() => executor.types.isNotEmpty);
    expect(executor.types, [ObsAutomationBlockType.startRecord]);
  });

  test(
    'OBS subtitle action resolves direct UI fields and expressions',
    () async {
      final executor = _FakeActionExecutor();
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
      );
      addTearDown(runner.dispose);
      runner.configure([_subtitlePreset()]);

      input.emitUnifiedEvent(
        _event(
          source: 'ceaEew',
          eventId: 'subtitle',
          isEew: true,
          originTime: DateTime.utc(2026, 8, 20, 12),
          lat: 31.2,
          lng: 103.8,
          magnitude: 5.5,
          hypocenter: '测试震中',
          reportNumText: '第2报',
        ),
        ObsUnifiedEventPhase.updated,
      );

      await _waitUntil(() => executor.blocks.length == 3);
      expect(executor.blocks[0].parameters['text'], '地震预警 第2报');
      expect(executor.blocks[1].parameters['text'], '地震预警 第2报 | 烈度 V');
      expect(executor.blocks[2].parameters['text'], '地震预警 第2报 / 测试震中');
    },
  );

  test('wait for network input ignores unified UI events', () async {
    final executor = _FakeActionExecutor();
    final runner = ObsAutomationRunner(
      inputService: input,
      actionExecutor: executor,
    );
    addTearDown(runner.dispose);
    runner.configure([_networkWaitPreset()]);
    final originTime = DateTime.utc(2026, 8, 20, 12);

    input.emitUnifiedEvent(
      _event(
        source: 'ceaEew',
        eventId: 'trigger',
        isEew: true,
        originTime: originTime,
        lat: 31.2,
        lng: 103.8,
      ),
      ObsUnifiedEventPhase.added,
    );
    await _waitUntil(() => runner.activeWaiterCount == 1);

    input.emitUnifiedEvent(
      _event(
        source: 'cencEqlist',
        eventId: 'information',
        isEew: false,
        originTime: originTime,
        lat: 31.2,
        lng: 103.8,
      ),
      ObsUnifiedEventPhase.added,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runner.activeWaiterCount, 1);

    input.ingestLegacyNetworkDetection(
      network: 'nied',
      maxIntensity: 2,
      observedAt: originTime,
    );
    await _waitUntil(() => runner.activeWaiterCount == 0);
    await _waitUntil(() => executor.types.length == 1);
    expect(executor.types, [ObsAutomationBlockType.stopRecord]);
  });

  test(
    'wait timeout is cleaned without another input and can stop recording',
    () async {
      final executor = _FakeActionExecutor();
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
      );
      addTearDown(runner.dispose);
      runner.configure([_timeoutPreset()]);
      final originTime = DateTime.utc(2026, 8, 20, 12);

      input.emitUnifiedEvent(
        _event(
          source: 'ceaEew',
          eventId: 'timeout',
          isEew: true,
          originTime: originTime,
          lat: 31.2,
          lng: 103.8,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => runner.activeWaiterCount == 1);
      await _waitUntil(() => runner.activeWaiterCount == 0);
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
      ]);
    },
  );
}

ObsAutomationPreset _ceaToCencPreset() {
  return ObsAutomationPreset(
    id: 'preset-cea-cenc',
    name: 'CEA 到 CENC',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-cea-cenc',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.unifiedEvent),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'unified',
            'field': 'phase',
            'operator': 'equals',
            'value': 'added',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'unified',
            'field': 'eventType',
            'operator': 'equals',
            'value': 'eew',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'unified',
            'field': 'agency',
            'operator': 'equals',
            'value': 'cea',
          }),
          _block(ObsAutomationBlockType.setEventVariable, const {
            'name': '目标地震',
          }),
          _block(ObsAutomationBlockType.startRecord),
          _block(ObsAutomationBlockType.waitForUnifiedEvent, const {
            'timeoutSeconds': '1800',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'unified',
            'field': 'eventType',
            'operator': 'equals',
            'value': 'earthquake',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'unified',
            'field': 'agency',
            'operator': 'equals',
            'value': 'cenc',
          }),
          _block(ObsAutomationBlockType.sameEarthquakeAsVariable, const {
            'variable': '目标地震',
            'maxSeconds': '300',
            'maxDistanceKm': '300',
          }),
          _block(ObsAutomationBlockType.stopRecord),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _eventIdVariablePreset() {
  return ObsAutomationPreset(
    id: 'preset-value-variable',
    name: '事件编号变量',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-value-variable',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.unifiedEvent),
          _block(ObsAutomationBlockType.unifiedPhase, const {
            'operator': 'equals',
            'value': 'added',
          }),
          _block(ObsAutomationBlockType.setValueVariable, const {
            'field': 'eventId',
            'name': '目标编号',
          }),
          _block(ObsAutomationBlockType.startRecord),
          _block(ObsAutomationBlockType.waitForInput, const {
            'kind': 'unifiedEvent',
            'timeoutSeconds': '1800',
          }),
          _block(ObsAutomationBlockType.inputFieldMatchesVariable, const {
            'field': 'eventId',
            'operator': 'equals',
            'variable': '目标编号',
          }),
          _block(ObsAutomationBlockType.stopRecord),
          _block(ObsAutomationBlockType.stopScript),
          _block(ObsAutomationBlockType.saveReplayBuffer),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _genericDataPreset() {
  final adjustedMagnitude = const ObsAutomationValueNode.operation(
    'arithmetic',
    options: {'operator': 'add'},
    arguments: [
      ObsAutomationValueNode.inputField('magnitude', family: 'unified'),
      ObsAutomationValueNode.literal('0.5'),
    ],
  ).encode();
  return ObsAutomationPreset(
    id: 'preset-generic-data',
    name: '通用数据积木',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-generic-data',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.unifiedEvent),
          _block(ObsAutomationBlockType.setValueVariable, const {
            'field': 'magnitude',
            'name': '当前震级',
          }),
          _block(ObsAutomationBlockType.setValueVariable, const {
            'field': 'hypocenter',
            'name': '震中名称',
          }),
          _block(ObsAutomationBlockType.setVariable, const {
            'name': '保存的震级',
            'valueKind': 'inputField',
            'value': 'magnitude',
          }),
          _block(ObsAutomationBlockType.setVariable, {
            'name': '调整后震级',
            'valueKind': 'expression',
            'value': adjustedMagnitude,
          }),
          _block(ObsAutomationBlockType.setVariable, const {
            'name': '阈值',
            'value': '5',
          }),
          _block(ObsAutomationBlockType.changeVariable, const {
            'name': '阈值',
            'operation': 'add',
            'operand': '0.4',
          }),
          _block(ObsAutomationBlockType.compareValues, const {
            'leftKind': 'variable',
            'leftValue': '保存的震级',
            'operator': 'greaterThan',
            'rightKind': 'variable',
            'rightValue': '阈值',
          }),
          _block(ObsAutomationBlockType.createRecordChapter, const {
            'text': '{{震中名称}} M{{调整后震级}}',
          }),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _networkWaitPreset() {
  return ObsAutomationPreset(
    id: 'preset-network-wait',
    name: '等待台网',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-network-wait',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.unifiedEvent),
          _block(ObsAutomationBlockType.isEew),
          _block(ObsAutomationBlockType.waitForInput, const {
            'kind': 'networkDetection',
            'timeoutSeconds': '1800',
          }),
          _block(ObsAutomationBlockType.networkPhase, const {
            'operator': 'equals',
            'value': 'confirmed',
          }),
          _block(ObsAutomationBlockType.stopRecord),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _networkRecordingPreset() {
  return ObsAutomationPreset(
    id: 'preset-network-recording',
    name: '台网检出录制',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-network-recording',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.networkDetection, const {
            'network': 'nied',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'station',
            'field': 'phase',
            'operator': 'equals',
            'value': 'confirmed',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'station',
            'field': 'networkMaxRawIntensity',
            'operator': 'greaterThanOrEqual',
            'value': '3',
          }),
          _block(ObsAutomationBlockType.startRecord),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _stationRecordingPreset() {
  return ObsAutomationPreset(
    id: 'preset-station-recording',
    name: '测站检出录制',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-station-recording',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.stationChange, const {
            'network': 'nied',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'station',
            'field': 'phase',
            'operator': 'equals',
            'value': 'triggered',
          }),
          _block(ObsAutomationBlockType.inputFieldCondition, const {
            'family': 'station',
            'field': 'currentStationIntensity',
            'operator': 'greaterThanOrEqual',
            'value': '5',
          }),
          _block(ObsAutomationBlockType.startRecord),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _subtitlePreset() {
  final titleAndBadge = const ObsAutomationValueNode.operation(
    'join',
    arguments: [
      ObsAutomationValueNode.operation(
        'join',
        arguments: [
          ObsAutomationValueNode.inputField('uiTitle', family: 'unified'),
          ObsAutomationValueNode.literal(' | 烈度 '),
        ],
      ),
      ObsAutomationValueNode.inputField('uiBadgeValue', family: 'unified'),
    ],
  ).encode();
  return ObsAutomationPreset(
    id: 'preset-subtitle',
    name: 'OBS 字幕',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-subtitle',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.unifiedEvent),
          _block(ObsAutomationBlockType.setTextSourceText, const {
            'inputName': '顶部标题',
            'textKind': 'inputField',
            'textValue': 'uiTitle',
            'textFamily': 'unified',
          }),
          _block(ObsAutomationBlockType.setTextSourceText, {
            'inputName': '完整字幕',
            'textKind': 'expression',
            'textValue': titleAndBadge,
            'textFamily': 'unified',
          }),
          _block(ObsAutomationBlockType.setTextSourceText, const {
            'inputName': '模板字幕',
            'textKind': 'literal',
            'textValue': '{{uiTitle}} / {{uiPrimaryText}}',
            'textFamily': 'unified',
          }),
        ],
      ),
    ],
  );
}

ObsAutomationPreset _timeoutPreset() {
  return ObsAutomationPreset(
    id: 'preset-timeout',
    name: '等待超时',
    enabled: true,
    stacks: [
      ObsAutomationStack(
        id: 'stack-timeout',
        x: 0,
        y: 0,
        blocks: [
          _block(ObsAutomationBlockType.unifiedEvent),
          _block(ObsAutomationBlockType.startRecord),
          _block(ObsAutomationBlockType.waitForInput, const {
            'kind': 'networkDetection',
            'timeoutSeconds': '0.03',
            'onTimeout': 'stopRecord',
          }),
        ],
      ),
    ],
  );
}

ObsAutomationBlock _block(
  ObsAutomationBlockType type, [
  Map<String, String> parameters = const {},
]) {
  return ObsAutomationBlock(
    id: 'block-${type.name}-$parameters',
    type: type,
    parameters: parameters,
  );
}

UnifiedQuakeData _event({
  required String source,
  required String eventId,
  required bool isEew,
  required DateTime originTime,
  required double lat,
  required double lng,
  String reportNumText = '',
  double magnitude = -1,
  String hypocenter = '测试震中',
}) {
  return UnifiedQuakeData(
    source: source,
    origin: 1,
    eventId: eventId,
    isEew: isEew,
    timeZone: 8,
    titleText: isEew ? '地震预警' : '地震信息',
    reportNumText: reportNumText,
    useShindo: false,
    maxIntensity: '5.0',
    className: 'orange',
    hypocenter: hypocenter,
    originTime: originTime,
    lat: lat,
    lng: lng,
    magnitude: magnitude,
  );
}

class _FakeActionExecutor implements ObsAutomationActionExecutor {
  final List<ObsAutomationBlockType> types = [];
  final List<ObsAutomationBlock> blocks = [];

  @override
  Future<void> execute(ObsAutomationBlock block) async {
    types.add(block.type);
    blocks.add(block);
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
