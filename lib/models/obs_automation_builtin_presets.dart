import 'obs_automation_preset.dart';

const obsEewM5RecordingPresetName = 'EEW M5 分机构自动录制';

ObsAutomationPreset buildEewM5RecordingPreset({
  required String Function(String prefix) nextId,
  bool enabled = false,
}) {
  const agencies = <_AgencyRecordingRule>[
    _AgencyRecordingRule(
      triggerAgency: 'cea',
      stopAgency: 'cenc',
      requireReviewed: true,
    ),
    _AgencyRecordingRule(
      triggerAgency: 'sichuan',
      stopAgency: 'cenc',
      requireReviewed: true,
    ),
    _AgencyRecordingRule(
      triggerAgency: 'fujian',
      stopAgency: 'cenc',
      requireReviewed: true,
    ),
    _AgencyRecordingRule(
      triggerAgency: 'chongqing',
      stopAgency: 'cenc',
      requireReviewed: true,
    ),
    _AgencyRecordingRule(
      triggerAgency: 'jma',
      stopAgency: 'jma',
      titleContains: '震源',
    ),
    _AgencyRecordingRule(triggerAgency: 'cwa', stopAgency: 'cwa'),
    _AgencyRecordingRule(triggerAgency: 'kma', stopAgency: 'kma'),
  ];

  final stacks = <ObsAutomationStack>[];
  for (var index = 0; index < agencies.length; index++) {
    final rule = agencies[index];
    final column = index % 4;
    final row = index ~/ 4;
    stacks.add(
      ObsAutomationStack(
        id: nextId('stack'),
        x: 48 + column * 680,
        y: 48 + row * 900,
        blocks: _agencyRecordingBlocks(rule, nextId),
      ),
    );
  }

  return ObsAutomationPreset(
    id: nextId('preset'),
    name: obsEewM5RecordingPresetName,
    enabled: enabled,
    stacks: stacks,
  );
}

List<ObsAutomationBlock> _agencyRecordingBlocks(
  _AgencyRecordingRule rule,
  String Function(String prefix) nextId,
) {
  ObsAutomationBlock block(
    ObsAutomationBlockType type, [
    Map<String, String> parameters = const {},
  ]) {
    return ObsAutomationBlock(
      id: nextId('block'),
      type: type,
      parameters: parameters,
    );
  }

  return [
    block(ObsAutomationBlockType.unifiedEvent),
    block(ObsAutomationBlockType.unifiedPhase, const {
      'operator': 'equals',
      'value': 'added',
    }),
    block(ObsAutomationBlockType.isEew),
    block(ObsAutomationBlockType.magnitude, const {
      'operator': 'greaterThanOrEqual',
      'value': '5.0',
    }),
    block(ObsAutomationBlockType.eewAgency, {
      'operator': 'equals',
      'value': rule.triggerAgency,
    }),
    block(ObsAutomationBlockType.setValueVariable, const {
      'field': 'agency',
      'name': 'EEW发报机构',
    }),
    block(ObsAutomationBlockType.setEventVariable, const {'name': '目标EEW'}),
    block(ObsAutomationBlockType.startRecord),
    block(ObsAutomationBlockType.waitForUnifiedEvent, const {
      'timeoutSeconds': '3600',
      'onTimeout': 'stopRecord',
    }),
    block(ObsAutomationBlockType.isInformation),
    block(ObsAutomationBlockType.eventType, const {
      'operator': 'equals',
      'value': 'earthquake',
    }),
    block(ObsAutomationBlockType.informationAgency, {
      'operator': 'equals',
      'value': rule.stopAgency,
    }),
    if (rule.requireReviewed)
      block(ObsAutomationBlockType.informationReviewType, const {
        'operator': 'equals',
        'value': 'reviewed',
      }),
    if (rule.titleContains != null)
      block(ObsAutomationBlockType.inputFieldCondition, {
        'family': 'unified',
        'field': 'title',
        'operator': 'contains',
        'value': rule.titleContains!,
      }),
    block(ObsAutomationBlockType.sameEarthquakeAsVariable, const {
      'variable': '目标EEW',
      'maxSeconds': '300',
      'maxDistanceKm': '300',
    }),
    block(ObsAutomationBlockType.wait, const {'seconds': '20'}),
    block(ObsAutomationBlockType.stopRecord),
    block(ObsAutomationBlockType.stopScript),
  ];
}

class _AgencyRecordingRule {
  const _AgencyRecordingRule({
    required this.triggerAgency,
    required this.stopAgency,
    this.requireReviewed = false,
    this.titleContains,
  });

  final String triggerAgency;
  final String stopAgency;
  final bool requireReviewed;
  final String? titleContains;
}
