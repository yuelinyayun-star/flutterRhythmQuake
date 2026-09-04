import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/obs_automation_value_expression.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/obs_automation_condition_evaluator.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';

void main() {
  const evaluator = ObsAutomationConditionEvaluator();
  final now = DateTime.utc(2026, 8, 20, 12);

  ObsAutomationBlock block(
    ObsAutomationBlockType type, {
    Map<String, String> parameters = const {},
  }) {
    return ObsAutomationBlock(
      id: 'block-${type.name}-$parameters',
      type: type,
      parameters: parameters,
    );
  }

  UnifiedQuakeData quake({
    String source = 'jmaEew',
    bool isEew = true,
    double magnitude = 5.5,
    String maxIntensity = '5强',
    bool useShindo = true,
    bool isFinal = false,
    String eventId = 'event-1',
    DateTime? originTime,
    double? lat,
    double? lng,
    String reportNumText = '第3报',
  }) {
    return UnifiedQuakeData(
      source: source,
      origin: 1,
      eventId: eventId,
      isEew: isEew,
      timeZone: 9,
      titleText: isEew ? '紧急地震速报' : '地震信息',
      reportNumText: reportNumText,
      useShindo: useShindo,
      maxIntensity: maxIntensity,
      className: 'red',
      hypocenter: '测试震中',
      magnitude: magnitude,
      isFinal: isFinal,
      originTime: originTime,
      lat: lat,
      lng: lng,
    );
  }

  test('unified conditions use AND and reject unavailable values', () {
    final blocks = [
      block(ObsAutomationBlockType.unifiedEvent),
      block(
        ObsAutomationBlockType.unifiedPhase,
        parameters: const {'operator': 'equals', 'value': 'added'},
      ),
      block(
        ObsAutomationBlockType.eventType,
        parameters: const {'operator': 'equals', 'value': 'eew'},
      ),
      block(
        ObsAutomationBlockType.magnitude,
        parameters: const {'operator': 'greaterThanOrEqual', 'value': '5.0'},
      ),
      block(ObsAutomationBlockType.startRecord),
    ];

    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(),
          occurredAt: now,
        ),
      ),
      isTrue,
    );
    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.updated,
          event: quake(),
          occurredAt: now,
        ),
      ),
      isFalse,
    );
    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(magnitude: -1),
          occurredAt: now,
        ),
      ),
      isFalse,
    );
  });

  test('EEW and information conditions are mutually exclusive', () {
    final eewBlocks = [
      block(ObsAutomationBlockType.unifiedEvent),
      block(ObsAutomationBlockType.isEew),
    ];
    final informationBlocks = [
      block(ObsAutomationBlockType.unifiedEvent),
      block(ObsAutomationBlockType.isInformation),
    ];
    final eewInput = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(),
      occurredAt: now,
    );
    final informationInput = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(isEew: false),
      occurredAt: now,
    );

    expect(evaluator.matchesBlocks(eewBlocks, eewInput), isTrue);
    expect(evaluator.matchesBlocks(eewBlocks, informationInput), isFalse);
    expect(evaluator.matchesBlocks(informationBlocks, eewInput), isFalse);
    expect(
      evaluator.matchesBlocks(informationBlocks, informationInput),
      isTrue,
    );
    expect(
      evaluator.matchesBlocks(
        informationBlocks,
        ObsAutomationInputEvent.networkDetection(
          network: 'nied',
          phase: ObsNetworkDetectionPhase.confirmed,
          occurredAt: now,
        ),
      ),
      isFalse,
    );
  });

  test('EEW agency uses normalized institution instead of API origin', () {
    const sources = {
      'jmaEew': 'jma',
      'cwaEew': 'cwa',
      'ceaEew': 'cea',
      'scEew': 'sichuan',
      'fjEew': 'fujian',
      'cqEew': 'chongqing',
      'kmaEew': 'kma',
      'sa': 'shakeAlert',
      'globalQuakeEew': 'globalQuake',
    };

    for (final entry in sources.entries) {
      final blocks = [
        block(ObsAutomationBlockType.unifiedEvent),
        block(
          ObsAutomationBlockType.eewAgency,
          parameters: {'operator': 'equals', 'value': entry.value},
        ),
      ];
      expect(
        evaluator.matchesBlocks(
          blocks,
          ObsAutomationInputEvent.unified(
            phase: ObsUnifiedEventPhase.added,
            event: quake(source: entry.key),
            occurredAt: now,
          ),
        ),
        isTrue,
        reason: entry.key,
      );
    }

    final jmaCondition = [
      block(ObsAutomationBlockType.unifiedEvent),
      block(
        ObsAutomationBlockType.eewAgency,
        parameters: const {'operator': 'equals', 'value': 'jma'},
      ),
    ];
    expect(
      evaluator.matchesBlocks(
        jmaCondition,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(source: 'jmaEqlist', isEew: false),
          occurredAt: now,
        ),
      ),
      isFalse,
    );
    expect(
      evaluator.matchesBlocks(
        jmaCondition,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(source: 'unknownEew'),
          occurredAt: now,
        ),
      ),
      isFalse,
    );
  });

  test('information agency and review type use unified UI fields', () {
    final automatic = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(source: 'cencEqlist', isEew: false, reportNumText: '自动测定'),
      occurredAt: now,
    );
    expect(
      evaluator.matchesConditions([
        block(
          ObsAutomationBlockType.informationAgency,
          parameters: const {'operator': 'equals', 'value': 'cenc'},
        ),
        block(
          ObsAutomationBlockType.informationReviewType,
          parameters: const {'operator': 'equals', 'value': 'automatic'},
        ),
      ], automatic),
      isTrue,
    );
  });

  test('UI presentation fields reuse the canonical unified UI text', () {
    final event = quake(maxIntensity: '5强');
    final input = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.updated,
      event: event,
      occurredAt: now,
    );
    final presentation = UnifiedEventPresentation.fromEvent(event);

    expect(evaluator.readInputField(input, 'uiTitle'), presentation.title);
    expect(
      evaluator.readInputField(input, 'uiPrimaryText'),
      presentation.primaryText,
    );
    expect(
      evaluator.readInputField(input, 'uiSecondaryText'),
      presentation.secondaryText,
    );
    expect(
      evaluator.readInputField(input, 'uiCompactSecondaryText'),
      presentation.compactSecondaryText,
    );
    expect(
      evaluator.readInputField(input, 'uiTimeText'),
      presentation.timeText,
    );
    expect(
      evaluator.readInputField(input, 'uiBadgeLabel'),
      presentation.intensityLabel,
    );
    expect(
      evaluator.readInputField(input, 'uiBadgeValue'),
      presentation.intensityValue,
    );
    expect(
      evaluator.readInputField(input, 'uiApiTypeLabel'),
      presentation.apiTypeLabel,
    );
    expect(
      evaluator.readInputField(input, 'uiNotificationBody'),
      presentation.notificationBody,
    );

    final romanInput = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(maxIntensity: '9', useShindo: false),
      occurredAt: now,
    );
    expect(evaluator.readInputField(romanInput, 'uiBadgeLabel'), '烈度');
    expect(evaluator.readInputField(romanInput, 'uiBadgeValue'), 'IX');
  });

  test('generic station fields cover detection and station conditions', () {
    final network = ObsAutomationInputEvent.networkDetection(
      network: 'nied',
      phase: ObsNetworkDetectionPhase.confirmed,
      occurredAt: now,
      detectedStationCount: 4,
      maxIntensity: 5,
    );
    expect(
      evaluator.matchesConditions([
        block(
          ObsAutomationBlockType.inputFieldCondition,
          parameters: const {
            'field': 'network',
            'operator': 'equals',
            'value': 'nied',
          },
        ),
        block(ObsAutomationBlockType.andBranch),
        block(
          ObsAutomationBlockType.inputFieldCondition,
          parameters: const {
            'field': 'detectedStationCount',
            'operator': 'greaterThanOrEqual',
            'value': '3',
          },
        ),
      ], network),
      isTrue,
    );

    final station = ObsAutomationInputEvent.stationChange(
      network: 'nied',
      phase: ObsStationChangePhase.triggered,
      current: ObsStationInputSample(
        stationId: 'A001',
        stationName: '测试站',
        active: true,
        intensityLevel: 6,
        intensity: 5.8,
        observedAt: now,
      ),
    );
    expect(
      evaluator.matchesConditions([
        block(
          ObsAutomationBlockType.inputFieldCondition,
          parameters: const {
            'field': 'currentStationIntensity',
            'operator': 'greaterThanOrEqual',
            'value': '6',
          },
        ),
      ], station),
      isTrue,
    );
  });

  test('same-earthquake condition rejects missing data and honors bounds', () {
    final originTime = DateTime.utc(2026, 8, 20, 12);
    final saved = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(originTime: originTime, lat: 31.2, lng: 103.8),
      occurredAt: now,
    );
    final context = ObsAutomationEvaluationContext(
      eventVariables: {'目标地震': saved},
    );
    final condition = block(
      ObsAutomationBlockType.sameEarthquakeAsVariable,
      parameters: const {
        'variable': '目标地震',
        'maxSeconds': '60',
        'maxDistanceKm': '30',
      },
    );
    final matching = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(
        eventId: 'event-2',
        originTime: originTime.add(const Duration(seconds: 60)),
        lat: 31.3,
        lng: 103.9,
      ),
      occurredAt: now,
    );
    expect(
      evaluator.matchesConditions([condition], matching, context: context),
      isTrue,
    );
    expect(
      evaluator.matchesConditions(
        [condition],
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(eventId: 'missing-location'),
          occurredAt: now,
        ),
        context: context,
      ),
      isFalse,
    );
  });

  test('input field values can be compared with named scalar variables', () {
    final event = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.updated,
      event: quake(eventId: 'shared-id', magnitude: 5.5),
      occurredAt: now,
    );
    final context = ObsAutomationEvaluationContext(
      valueVariables: const {'目标编号': 'shared-id', '初始震级': 5.0},
    );
    expect(
      evaluator.matchesConditions(
        [
          block(
            ObsAutomationBlockType.inputFieldMatchesVariable,
            parameters: const {
              'field': 'eventId',
              'operator': 'equals',
              'variable': '目标编号',
            },
          ),
          block(ObsAutomationBlockType.andBranch),
          block(
            ObsAutomationBlockType.inputFieldMatchesVariable,
            parameters: const {
              'field': 'magnitude',
              'operator': 'greaterThan',
              'variable': '初始震级',
            },
          ),
        ],
        event,
        context: context,
      ),
      isTrue,
    );
  });

  test(
    'one generic field condition covers agency, review type and numbers',
    () {
      final event = ObsAutomationInputEvent.unified(
        phase: ObsUnifiedEventPhase.added,
        event: quake(
          source: 'cencEqlist',
          isEew: false,
          magnitude: 5.5,
          reportNumText: '自动测定',
        ),
        occurredAt: now,
      );
      final conditions = [
        block(
          ObsAutomationBlockType.inputFieldCondition,
          parameters: const {
            'field': 'agency',
            'operator': 'equals',
            'value': 'cenc',
          },
        ),
        block(ObsAutomationBlockType.andBranch),
        block(
          ObsAutomationBlockType.inputFieldCondition,
          parameters: const {
            'field': 'reviewType',
            'operator': 'equals',
            'value': 'automatic',
          },
        ),
        block(ObsAutomationBlockType.andBranch),
        block(
          ObsAutomationBlockType.inputFieldCondition,
          parameters: const {
            'field': 'magnitude',
            'operator': 'greaterThanOrEqual',
            'value': '5.0',
          },
        ),
      ];

      expect(evaluator.matchesConditions(conditions, event), isTrue);
      expect(
        evaluator.matchesConditions([
          block(
            ObsAutomationBlockType.inputFieldCondition,
            parameters: const {
              'field': 'stationId',
              'operator': 'equals',
              'value': 'missing',
            },
          ),
        ], event),
        isFalse,
      );
    },
  );

  test('generic value comparison resolves fields variables and literals', () {
    final event = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.updated,
      event: quake(
        source: 'cencEqlist',
        isEew: false,
        magnitude: 5.5,
        reportNumText: '自动测定',
      ),
      occurredAt: now,
    );
    final context = ObsAutomationEvaluationContext(
      valueVariables: const {'目标机构': 'cenc', '最低震级': 5.0},
    );

    expect(
      evaluator.matchesConditions(
        [
          block(
            ObsAutomationBlockType.compareValues,
            parameters: const {
              'leftKind': 'inputField',
              'leftValue': 'agency',
              'operator': 'equals',
              'rightKind': 'variable',
              'rightValue': '目标机构',
            },
          ),
          block(ObsAutomationBlockType.andBranch),
          block(
            ObsAutomationBlockType.compareValues,
            parameters: const {
              'leftKind': 'inputField',
              'leftValue': 'magnitude',
              'operator': 'greaterThanOrEqual',
              'rightKind': 'variable',
              'rightValue': '最低震级',
            },
          ),
          block(ObsAutomationBlockType.andBranch),
          block(
            ObsAutomationBlockType.compareValues,
            parameters: const {
              'leftKind': 'variable',
              'leftValue': '目标机构',
              'operator': 'equals',
              'rightKind': 'literal',
              'rightValue': 'cenc',
            },
          ),
        ],
        event,
        context: context,
      ),
      isTrue,
    );
  });

  test('generic value comparison rejects unavailable field or variable', () {
    final event = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(),
      occurredAt: now,
    );

    for (final parameters in const [
      {
        'leftKind': 'inputField',
        'leftValue': 'stationId',
        'operator': 'equals',
        'rightKind': 'literal',
        'rightValue': 'NIED-001',
      },
      {
        'leftKind': 'variable',
        'leftValue': '不存在',
        'operator': 'equals',
        'rightKind': 'literal',
        'rightValue': '1',
      },
    ]) {
      expect(
        evaluator.matchesConditions([
          block(ObsAutomationBlockType.compareValues, parameters: parameters),
        ], event),
        isFalse,
      );
    }
  });

  test('nested Scratch value expressions evaluate original input values', () {
    final event = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.updated,
      event: quake(magnitude: 5.5),
      occurredAt: now,
    );
    final context = ObsAutomationEvaluationContext(
      valueVariables: const {'增量': 0.5, '启用': true},
    );

    Object? resolve(ObsAutomationValueNode node) {
      return evaluator.resolveValueReference(
        event,
        kind: 'expression',
        value: node.encode(),
        context: context,
      );
    }

    const sum = ObsAutomationValueNode.operation(
      'arithmetic',
      options: {'operator': 'add'},
      arguments: [
        ObsAutomationValueNode.inputField('magnitude', family: 'unified'),
        ObsAutomationValueNode.variable('增量'),
      ],
    );
    expect(resolve(sum), 6.0);
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'arithmetic',
          options: {'operator': 'multiply'},
          arguments: [sum, ObsAutomationValueNode.literal('2')],
        ),
      ),
      12.0,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'modulo',
          arguments: [
            ObsAutomationValueNode.literal('10'),
            ObsAutomationValueNode.literal('3'),
          ],
        ),
      ),
      1.0,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'round',
          arguments: [ObsAutomationValueNode.literal('1.6')],
        ),
      ),
      2,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'math',
          options: {'operator': 'sqrt'},
          arguments: [ObsAutomationValueNode.literal('9')],
        ),
      ),
      3.0,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'join',
          arguments: [
            ObsAutomationValueNode.inputField('hypocenter', family: 'unified'),
            ObsAutomationValueNode.literal(' M'),
          ],
        ),
      ),
      '测试震中 M',
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'length',
          arguments: [ObsAutomationValueNode.literal('震中')],
        ),
      ),
      2,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'contains',
          arguments: [
            ObsAutomationValueNode.literal('测试震中'),
            ObsAutomationValueNode.literal('震中'),
          ],
        ),
      ),
      isTrue,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'comparison',
          options: {'operator': 'greaterThan'},
          arguments: [sum, ObsAutomationValueNode.literal('5')],
        ),
      ),
      isTrue,
    );
    expect(
      resolve(
        const ObsAutomationValueNode.operation(
          'boolean',
          options: {'operator': 'and'},
          arguments: [
            ObsAutomationValueNode.variable('启用'),
            ObsAutomationValueNode.operation(
              'not',
              arguments: [ObsAutomationValueNode.literal('false')],
            ),
          ],
        ),
      ),
      isTrue,
    );
    final random = resolve(
      const ObsAutomationValueNode.operation(
        'random',
        arguments: [
          ObsAutomationValueNode.literal('3'),
          ObsAutomationValueNode.literal('5'),
        ],
      ),
    );
    expect(random, isA<int>());
    expect(random as int, inInclusiveRange(3, 5));
  });

  test('explicit AND composes generic variable conditions', () {
    final event = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.updated,
      event: quake(),
      occurredAt: now,
    );
    final context = ObsAutomationEvaluationContext(
      valueVariables: const {'计数': 3, '标签': 'CEA-CENC'},
    );
    final conditions = [
      block(
        ObsAutomationBlockType.valueVariableCondition,
        parameters: const {
          'variable': '计数',
          'operator': 'greaterThanOrEqual',
          'value': '2',
        },
      ),
      block(ObsAutomationBlockType.andBranch),
      block(
        ObsAutomationBlockType.valueVariableCondition,
        parameters: const {
          'variable': '标签',
          'operator': 'contains',
          'value': 'CENC',
        },
      ),
    ];

    expect(
      evaluator.matchesConditions(conditions, event, context: context),
      isTrue,
    );
    expect(
      evaluator.matchesConditions(
        [...conditions, block(ObsAutomationBlockType.andBranch)],
        event,
        context: context,
      ),
      isFalse,
    );
  });

  test('OR separates complete input branches', () {
    final blocks = [
      block(
        ObsAutomationBlockType.networkDetection,
        parameters: const {'network': 'nied'},
      ),
      block(
        ObsAutomationBlockType.networkPhase,
        parameters: const {'operator': 'equals', 'value': 'confirmed'},
      ),
      block(ObsAutomationBlockType.orBranch),
      block(ObsAutomationBlockType.unifiedEvent),
      block(
        ObsAutomationBlockType.eventType,
        parameters: const {'operator': 'equals', 'value': 'eew'},
      ),
      block(
        ObsAutomationBlockType.unifiedPhase,
        parameters: const {'operator': 'equals', 'value': 'added'},
      ),
      block(ObsAutomationBlockType.startRecord),
    ];

    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.networkDetection(
          network: 'nied',
          phase: ObsNetworkDetectionPhase.confirmed,
          occurredAt: now,
        ),
      ),
      isTrue,
    );
    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.networkDetection(
          network: 'nied',
          phase: ObsNetworkDetectionPhase.candidate,
          occurredAt: now,
        ),
      ),
      isFalse,
    );
    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(),
          occurredAt: now,
        ),
      ),
      isTrue,
    );
    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.unified(
          phase: ObsUnifiedEventPhase.added,
          event: quake(isEew: false),
          occurredAt: now,
        ),
      ),
      isFalse,
    );
  });

  test('network conditions compare station count and normalized shindo', () {
    final blocks = [
      block(
        ObsAutomationBlockType.networkDetection,
        parameters: const {'network': 'any'},
      ),
      block(
        ObsAutomationBlockType.networkMaxIntensity,
        parameters: const {'operator': 'greaterThanOrEqual', 'value': '7'},
      ),
      block(
        ObsAutomationBlockType.detectedStationCount,
        parameters: const {'operator': 'greaterThanOrEqual', 'value': '3'},
      ),
    ];

    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.networkDetection(
          network: 'kma',
          phase: ObsNetworkDetectionPhase.strong,
          occurredAt: now,
          maxIntensity: 6,
          detectedStationCount: 4,
        ),
      ),
      isTrue,
    );
    expect(
      evaluator.matchesBlocks(
        blocks,
        ObsAutomationInputEvent.networkDetection(
          network: 'kma',
          phase: ObsNetworkDetectionPhase.strong,
          occurredAt: now,
          maxIntensity: 6,
        ),
      ),
      isFalse,
    );
  });

  test('station conditions use UI shindo order and text operators', () {
    final current = ObsStationInputSample(
      stationId: 'KMA-001',
      stationName: 'Seoul Test',
      active: true,
      intensityLevel: 6,
      observedAt: now,
    );
    final previous = ObsStationInputSample(
      stationId: 'KMA-001',
      stationName: 'Seoul Test',
      active: true,
      intensityLevel: 4,
      observedAt: now.subtract(const Duration(seconds: 1)),
    );
    final event = ObsAutomationInputEvent.stationChange(
      network: 'kma',
      phase: ObsStationChangePhase.intensityIncreased,
      current: current,
      previous: previous,
    );
    final blocks = [
      block(
        ObsAutomationBlockType.stationChange,
        parameters: const {'network': 'kma'},
      ),
      block(
        ObsAutomationBlockType.stationPhase,
        parameters: const {'operator': 'equals', 'value': 'intensityIncreased'},
      ),
      block(
        ObsAutomationBlockType.stationName,
        parameters: const {'operator': 'contains', 'value': 'seoul'},
      ),
      block(
        ObsAutomationBlockType.currentStationIntensity,
        parameters: const {'operator': 'greaterThanOrEqual', 'value': '7'},
      ),
      block(
        ObsAutomationBlockType.previousStationIntensity,
        parameters: const {'operator': 'lessThan', 'value': '5'},
      ),
    ];

    expect(evaluator.matchesBlocks(blocks, event), isTrue);
  });

  test('invalid OR and blocks after actions do not match', () {
    final event = ObsAutomationInputEvent.unified(
      phase: ObsUnifiedEventPhase.added,
      event: quake(),
      occurredAt: now,
    );
    expect(
      evaluator.matchesBlocks([
        block(ObsAutomationBlockType.unifiedEvent),
        block(ObsAutomationBlockType.orBranch),
      ], event),
      isFalse,
    );
    expect(
      evaluator.matchesBlocks([
        block(ObsAutomationBlockType.unifiedEvent),
        block(ObsAutomationBlockType.startRecord),
        block(ObsAutomationBlockType.eventType),
      ], event),
      isFalse,
    );
  });
}
