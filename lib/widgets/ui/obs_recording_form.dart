import 'package:flutter/foundation.dart';
import '../../models/obs_automation_preset.dart';
import '../../models/obs_automation_builtin_presets.dart';
import '../../models/cmt_catalog.dart';
import '../../models/whews_catalog.dart';

typedef ObsRecordingCondition = ({
  ObsAutomationBlockType type,
  Map<String, String> parameters,
});

/// UI options map to existing conditions. No event evaluation, recording owner,
/// timer or action execution is implemented by this form.
class ObsRecordingEndChoice {
  const ObsRecordingEndChoice(
    this.id,
    this.label,
    this.family,
    this.conditions,
  );
  final String id, label, family;
  final List<ObsRecordingCondition> conditions;
  bool get timed => id == 'timed';
}

ObsRecordingCondition _condition(
  ObsAutomationBlockType type,
  String value, {
  String operator = 'equals',
}) => (type: type, parameters: {'operator': operator, 'value': value});
ObsRecordingCondition _title(String value) => (
  type: ObsAutomationBlockType.inputFieldCondition,
  parameters: {
    'family': 'unified',
    'field': 'title',
    'operator': 'contains',
    'value': value,
  },
);
const _information = (
  type: ObsAutomationBlockType.isInformation,
  parameters: <String, String>{},
);

ObsRecordingEndChoice _quake(
  String id,
  String label,
  String agency, {
  String? review,
  List<String> titles = const [],
}) => ObsRecordingEndChoice(id, label, agency, [
  _information,
  _condition(ObsAutomationBlockType.eventType, 'earthquake'),
  _condition(ObsAutomationBlockType.informationAgency, agency),
  if (review != null)
    _condition(ObsAutomationBlockType.informationReviewType, review),
  for (final title in titles) _title(title),
]);

final obsRecordingEndChoices = <ObsRecordingEndChoice>[
  _quake('cenc-reviewed', 'CENC 正式测定', 'cenc', review: 'reviewed'),
  _quake('cenc-automatic', 'CENC 自动测定', 'cenc', review: 'automatic'),
  ObsRecordingEndChoice('cenc-ir', 'CENC 烈度速报', 'cenc', [
    _information,
    _condition(ObsAutomationBlockType.source, 'nowQuakeCencIr'),
  ]),
  _quake('jma-combined', 'JMA 震源・震度情报', 'jma', titles: ['震源', '震度']),
  _quake('jma-prompt', 'JMA 震度速报', 'jma', titles: ['震度速報']),
  _quake('jma-origin', 'JMA 震源情报', 'jma', titles: ['震源に関する情報']),
  _quake('jma-detail', 'JMA 各地震度情报', 'jma', titles: ['各地', '震度']),
  _quake('jma-foreign', 'JMA 远地地震情报', 'jma', titles: ['遠地', '地震']),
  ObsRecordingEndChoice('jma-lpgm', 'JMA 长周期地震动情报', 'jma', [
    _information,
    _condition(ObsAutomationBlockType.source, 'jmaLpgm'),
  ]),
  _quake('cwa-report', 'CWA 地震报告', 'cwa'),
  _quake('kma-report', 'KMA 地震情报', 'kma'),
  _quake('usgs-report', 'USGS 地震情报', 'usgs'),
  _quake('fssn-report', 'FSSN 地震情报', 'fssn'),
  _quake('ssn-report', 'SSN 地震情报', 'ssn'),
  for (final entry in cmtCatalogSources.entries)
    ObsRecordingEndChoice(
      entry.key,
      cmtCatalogLabel(entry.value),
      switch (entry.key) {
        'cencCmt' => 'cenc',
        'jmaCmt' => 'jma',
        'usgsCmt' => 'usgs',
        'fssnCmt' => 'fssn',
        _ => 'nied',
      },
      [_information, _condition(ObsAutomationBlockType.source, entry.key)],
    ),
  ObsRecordingEndChoice('usgs-shakemap', 'USGS ShakeMap 烈度速报', 'usgs', [
    _information,
    _condition(ObsAutomationBlockType.source, 'usgsShakeMap'),
  ]),
  ObsRecordingEndChoice('usgs-dyfi', 'USGS DYFI 体感报告', 'usgs', [
    _information,
    _condition(ObsAutomationBlockType.source, 'usgsDyfi'),
  ]),
  for (final entry in const {
    'hko': 'HKO',
    'emsc': 'EMSC',
    'bcsf': 'BCSF',
    'gfz': 'GFZ',
    'usp': 'USP',
    'geonet': 'GeoNet',
    'ningxia': '宁夏地震局',
    'guangxi': '广西地震局',
    'shanxi': '山西地震局',
    'beijing': '北京地震局',
    'yunnan': '云南地震局',
  }.entries)
    _quake('${entry.key}-report', '${entry.value} 地震情报', entry.key),
  for (final entry in unifiedCatalogSources.entries.where(
    (entry) => entry.value.name != 'geonet' && entry.value.name != 'ssn',
  ))
    ObsRecordingEndChoice(
      entry.key,
      '${whewsCatalogLabel(entry.value)} 地震情报',
      entry.value.name,
      [_information, _condition(ObsAutomationBlockType.source, entry.key)],
    ),
  ObsRecordingEndChoice('tsunami', '海啸情报', 'other', [
    _information,
    _condition(ObsAutomationBlockType.eventType, 'tsunami'),
  ]),
  ObsRecordingEndChoice('volcano', '火山情报', 'other', [
    _information,
    _condition(ObsAutomationBlockType.eventType, 'volcano'),
  ]),
  ObsRecordingEndChoice('ashfall', '降灰预报', 'other', [
    _information,
    _condition(ObsAutomationBlockType.eventType, 'ashfall'),
  ]),
  const ObsRecordingEndChoice('timed', '按既有时限结束', 'globalQuake', []),
];

String obsRecordingAgency(ObsAutomationStack rule) =>
    rule.blocks
        .where((block) => block.type == ObsAutomationBlockType.eewAgency)
        .firstOrNull
        ?.parameters['value'] ??
    (obsIsCencInformationRule(rule) ? 'cenc-information' : '');
bool obsRecordingUsesShindo(ObsAutomationStack rule) =>
    const {'jma', 'cwa'}.contains(obsRecordingAgency(rule));
String obsRecordingIntensityLabel(ObsAutomationStack rule) =>
    const {'jma', 'cwa', 'kma'}.contains(obsRecordingAgency(rule))
    ? '震度'
    : '烈度';

// SASMEX exposes detection/warning, not a numeric magnitude or intensity.
// These form options reuse the existing isWarn condition and leave all event
// evaluation and recording ownership to the existing runner.
bool obsRecordingUsesAlertTrigger(ObsAutomationStack rule) =>
    obsRecordingAgency(rule) == 'sasmex';
const obsRecordingAlertTriggers = {
  'all': '检出或警报',
  'warning': '仅地震警报',
  'detection': '仅地震检出',
};
bool _isAlertTriggerFilter(ObsAutomationBlock block) =>
    block.type == ObsAutomationBlockType.magnitude ||
    block.type == ObsAutomationBlockType.estimatedIntensity ||
    block.type == ObsAutomationBlockType.inputFieldCondition &&
        block.parameters['field'] == 'isWarn';

String obsRecordingAlertTrigger(ObsAutomationStack rule) {
  final filters = rule.blocks
      .takeWhile((block) => block.type != ObsAutomationBlockType.startRecord)
      .where(_isAlertTriggerFilter)
      .toList();
  if (filters.isEmpty) return 'all';
  if (filters.length == 1 &&
      filters.single.type == ObsAutomationBlockType.inputFieldCondition &&
      filters.single.parameters['operator'] == 'equals') {
    return switch (filters.single.parameters['value']) {
      'true' => 'warning',
      'false' => 'detection',
      _ => 'custom',
    };
  }
  return 'custom';
}

ObsAutomationStack obsRecordingChooseAlertTrigger(
  ObsAutomationStack rule,
  String choice,
  String Function(String) nextId,
) {
  if (!obsRecordingUsesAlertTrigger(rule) ||
      !obsRecordingAlertTriggers.containsKey(choice)) {
    return rule;
  }
  final start = rule.blocks.indexWhere(
    (block) => block.type == ObsAutomationBlockType.startRecord,
  );
  if (start < 0) return rule;
  final prefix = rule.blocks.take(start).toList();
  final old = prefix.where(_isAlertTriggerFilter).firstOrNull;
  final conditions = prefix
      .where((block) => !_isAlertTriggerFilter(block))
      .toList();
  // Trigger predicates must precede the existing variable/action sequence.
  final actions = conditions.indexWhere(
    (block) =>
        block.type == ObsAutomationBlockType.setValueVariable ||
        block.type == ObsAutomationBlockType.setEventVariable,
  );
  final insertAt = actions < 0 ? conditions.length : actions;
  return rule.copyWith(
    blocks: [
      ...conditions.take(insertAt),
      if (choice != 'all')
        ObsAutomationBlock(
          id: old?.id ?? nextId('block'),
          type: ObsAutomationBlockType.inputFieldCondition,
          parameters: {
            'family': 'unified',
            'field': 'isWarn',
            'operator': 'equals',
            'value': choice == 'warning' ? 'true' : 'false',
          },
        ),
      ...conditions.skip(insertAt),
      ...rule.blocks.skip(start),
    ],
  );
}

const _endTypes = {
  ObsAutomationBlockType.isInformation,
  ObsAutomationBlockType.eventType,
  ObsAutomationBlockType.informationAgency,
  ObsAutomationBlockType.informationReviewType,
  ObsAutomationBlockType.source,
};
bool _isEndCondition(ObsAutomationBlock block) =>
    _endTypes.contains(block.type) ||
    block.type == ObsAutomationBlockType.inputFieldCondition &&
        block.parameters['field'] == 'title';
bool _isWait(ObsAutomationBlock block) => const {
  ObsAutomationBlockType.waitForUnifiedEvent,
  ObsAutomationBlockType.waitForInput,
}.contains(block.type);

ObsRecordingEndChoice? obsRecordingCurrentEnd(ObsAutomationStack rule) {
  final selected = obsRecordingEndChoices
      .where((choice) => choice.id == rule.endConditionId)
      .firstOrNull;
  if (selected != null) return selected;
  final wait = rule.blocks.indexWhere(_isWait);
  if (wait < 0) return obsRecordingEndChoices.last;
  final actual = rule.blocks.skip(wait + 1).where(_isEndCondition).toList();
  return obsRecordingEndChoices
      .where(
        (choice) =>
            !choice.timed &&
            choice.conditions.length == actual.length &&
            choice.conditions.every(
              (condition) => actual.any(
                (block) =>
                    block.type == condition.type &&
                    mapEquals(block.parameters, condition.parameters),
              ),
            ),
      )
      .firstOrNull;
}

List<ObsRecordingEndChoice> obsRecordingAvailableEnds(
  ObsAutomationStack rule, {
  required bool expanded,
}) {
  final own = switch (obsRecordingAgency(rule)) {
    'cea' ||
    'sichuan' ||
    'fujian' ||
    'chongqing' ||
    'icl' ||
    'cenc-information' => 'cenc',
    'sasmex' => 'ssn',
    'shakeAlert' => 'usgs',
    final agency => agency,
  };
  final current = obsRecordingCurrentEnd(rule);
  return [
    for (final choice in obsRecordingEndChoices)
      if ((expanded && !choice.timed) ||
          choice.family == own ||
          choice.id == current?.id)
        choice,
  ];
}

ObsAutomationStack obsRecordingChooseEnd(
  ObsAutomationStack rule,
  ObsRecordingEndChoice choice,
  String Function(String) nextId, {
  required String maxSeconds,
  required String maxDistanceKm,
  String? timeoutSeconds,
}) {
  final blocks = rule.blocks;
  final start = blocks.indexWhere(
    (block) => block.type == ObsAutomationBlockType.startRecord,
  );
  if (start < 0) return rule;
  final wait = blocks.indexWhere(_isWait);
  final limit = wait >= 0
      ? blocks[wait].parameters['timeoutSeconds'] ??
            obsRecordingDefaultLimitSeconds
      : blocks
                .skip(start + 1)
                .where((block) => block.type == ObsAutomationBlockType.wait)
                .firstOrNull
                ?.parameters['seconds'] ??
            obsRecordingDefaultLimitSeconds;
  if (choice.timed) {
    if (wait < 0) return rule.copyWith(endConditionId: choice.id);
    return rule.copyWith(
      endConditionId: choice.id,
      blocks: [
        ...blocks.take(start + 1),
        ObsAutomationBlock(
          id: nextId('block'),
          type: ObsAutomationBlockType.wait,
          parameters: {'seconds': limit},
        ),
        ...blocks
            .skip(start + 1)
            .where(
              (block) =>
                  block.type == ObsAutomationBlockType.stopRecord ||
                  block.type == ObsAutomationBlockType.stopScript,
            ),
      ],
    );
  }
  if (wait < 0) {
    // The existing fixed-duration rule gains only the explicitly selected end
    // condition. Execution still uses the original waiter and shared owners.
    return rule.copyWith(
      endConditionId: choice.id,
      blocks: [
        ...blocks.take(start + 1),
        ObsAutomationBlock(
          id: nextId('block'),
          type: ObsAutomationBlockType.waitForUnifiedEvent,
          parameters: {
            'timeoutSeconds': timeoutSeconds ?? limit,
            'onTimeout': 'stopRecord',
          },
        ),
        for (final condition in choice.conditions)
          ObsAutomationBlock(
            id: nextId('block'),
            type: condition.type,
            parameters: condition.parameters,
          ),
        ObsAutomationBlock(
          id: nextId('block'),
          type: ObsAutomationBlockType.sameEarthquakeAsVariable,
          parameters: {
            'variable': '触发事件',
            'maxSeconds': maxSeconds,
            'maxDistanceKm': maxDistanceKm,
          },
        ),
        ...blocks
            .skip(start + 1)
            .where(
              (block) =>
                  block.type == ObsAutomationBlockType.stopRecord ||
                  block.type == ObsAutomationBlockType.stopScript,
            ),
      ],
    );
  }
  // Keep IDs and all non-selector blocks, especially same-earthquake matching,
  // post-information delay, stopRecord and stopScript, exactly as they were.
  final old = blocks.skip(wait + 1).where(_isEndCondition).toList();
  final replacement = <ObsAutomationBlock>[];
  for (final condition in choice.conditions) {
    final index = old.indexWhere(
      (block) =>
          block.type == condition.type &&
          (condition.type != ObsAutomationBlockType.inputFieldCondition ||
              block.parameters['field'] == condition.parameters['field']),
    );
    final previous = index < 0 ? null : old.removeAt(index);
    replacement.add(
      previous?.copyWith(parameters: condition.parameters) ??
          ObsAutomationBlock(
            id: nextId('block'),
            type: condition.type,
            parameters: condition.parameters,
          ),
    );
  }
  final first = blocks.indexWhere(_isEndCondition, wait + 1);
  return rule.copyWith(
    endConditionId: choice.id,
    blocks: [
      ...blocks.take(first < 0 ? wait + 1 : first),
      ...replacement,
      ...blocks
          .skip(first < 0 ? wait + 1 : first)
          .where((block) => !_isEndCondition(block)),
    ],
  );
}

String obsRecordingDelay(ObsAutomationStack rule) {
  final wait = rule.blocks.indexWhere(_isWait);
  if (wait < 0) return '';
  return rule.blocks
          .skip(wait + 1)
          .where((block) => block.type == ObsAutomationBlockType.wait)
          .firstOrNull
          ?.parameters['seconds'] ??
      '0';
}

ObsAutomationStack obsRecordingSetDelay(
  ObsAutomationStack rule,
  String value,
  String Function(String) nextId,
) {
  final wait = rule.blocks.indexWhere(_isWait);
  if (wait < 0) return rule;
  final blocks = [...rule.blocks];
  final index = blocks.indexWhere(
    (block) => block.type == ObsAutomationBlockType.wait,
    wait + 1,
  );
  if (double.tryParse(value) == 0) {
    if (index >= 0) blocks.removeAt(index);
  } else if (index >= 0) {
    blocks[index] = blocks[index].copyWith(
      parameters: {...blocks[index].parameters, 'seconds': value},
    );
  } else {
    final stop = blocks.indexWhere(
      (block) => block.type == ObsAutomationBlockType.stopRecord,
      wait + 1,
    );
    if (stop < 0) return rule;
    blocks.insert(
      stop,
      ObsAutomationBlock(
        id: nextId('block'),
        type: ObsAutomationBlockType.wait,
        parameters: {'seconds': value},
      ),
    );
  }
  return rule.copyWith(blocks: blocks);
}

bool obsIsCencInformationRule(ObsAutomationStack rule) {
  final trigger = rule.blocks
      .takeWhile((block) => block.type != ObsAutomationBlockType.startRecord)
      .toList();
  return trigger.any(
        (block) => block.type == ObsAutomationBlockType.isInformation,
      ) &&
      trigger.any(
        (block) =>
            block.type == ObsAutomationBlockType.informationAgency &&
            block.parameters['value'] == 'cenc',
      ) &&
      trigger.any(
        (block) =>
            block.type == ObsAutomationBlockType.informationReviewType &&
            block.parameters['value'] == 'automatic',
      );
}

ObsAutomationStack obsBuildCencInformationRule(
  String presetId,
  String Function(String) nextId, {
  required String maxSeconds,
  required String maxDistanceKm,
  required String timeoutSeconds,
}) {
  ObsAutomationBlock block(
    ObsAutomationBlockType type, [
    Map<String, String> parameters = const {},
  ]) => ObsAutomationBlock(
    id: nextId('block'),
    type: type,
    parameters: parameters,
  );
  return ObsAutomationStack(
    id: '$presetId:cenc-information-v1',
    x: 0,
    y: 0,
    enabled: false,
    endConditionId: 'cenc-reviewed',
    blocks: [
      block(ObsAutomationBlockType.unifiedEvent, const {
        'oncePerEvent': 'true',
      }),
      block(ObsAutomationBlockType.isInformation),
      block(ObsAutomationBlockType.eventType, const {
        'operator': 'equals',
        'value': 'earthquake',
      }),
      block(ObsAutomationBlockType.informationAgency, const {
        'operator': 'equals',
        'value': 'cenc',
      }),
      block(ObsAutomationBlockType.informationReviewType, const {
        'operator': 'equals',
        'value': 'automatic',
      }),
      block(ObsAutomationBlockType.magnitude, const {
        'operator': 'greaterThanOrEqual',
        'value': '5.0',
      }),
      block(ObsAutomationBlockType.startRecord),
      block(ObsAutomationBlockType.waitForUnifiedEvent, {
        'timeoutSeconds': timeoutSeconds,
        'onTimeout': 'stopRecord',
      }),
      block(ObsAutomationBlockType.isInformation),
      block(ObsAutomationBlockType.eventType, const {
        'operator': 'equals',
        'value': 'earthquake',
      }),
      block(ObsAutomationBlockType.informationAgency, const {
        'operator': 'equals',
        'value': 'cenc',
      }),
      block(ObsAutomationBlockType.informationReviewType, const {
        'operator': 'equals',
        'value': 'reviewed',
      }),
      block(ObsAutomationBlockType.sameEarthquakeAsVariable, {
        'variable': '触发事件',
        'maxSeconds': maxSeconds,
        'maxDistanceKm': maxDistanceKm,
      }),
      block(ObsAutomationBlockType.wait, const {'seconds': '20'}),
      block(ObsAutomationBlockType.stopRecord),
      block(ObsAutomationBlockType.stopScript),
    ],
  );
}
