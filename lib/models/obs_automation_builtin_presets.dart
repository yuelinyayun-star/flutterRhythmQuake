import '../core/app_edition.dart';
import 'obs_automation_preset.dart';

const obsEewRecordingPresetName = 'EEW 分机构自动录制';
const _legacyPresetName = 'EEW M5 分机构自动录制';

bool isBuiltInEewRecordingPreset(ObsAutomationPreset preset) =>
    preset.name == obsEewRecordingPresetName ||
    preset.name == _legacyPresetName;

ObsAutomationPreset buildEewRecordingPreset({
  required String Function(String prefix) nextId,
  bool enabled = false,
}) => _buildRecordingPreset(nextId: nextId, enabled: enabled);

ObsAutomationPreset _buildRecordingPreset({
  required String Function(String prefix) nextId,
  bool enabled = false,
  bool legacy = false,
  bool includeGlobalQuake = true,
}) {
  final agencies = <_AgencyRecordingRule>[
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
      minimumMagnitude: 4,
      requireIntensityTitle: true,
    ),
    _AgencyRecordingRule(triggerAgency: 'cwa', stopAgency: 'cwa'),
    _AgencyRecordingRule(
      triggerAgency: 'kma',
      stopAgency: 'kma',
      minimumMagnitude: 5,
    ),
    if (!legacy && AppEdition.hasIcl)
      _AgencyRecordingRule(
        triggerAgency: 'icl',
        stopAgency: 'cenc',
        requireReviewed: true,
      ),
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
        blocks: _agencyRecordingBlocks(rule, nextId, legacy: legacy),
      ),
    );
  }
  if (!legacy && includeGlobalQuake && AppEdition.hasGlobalQuake) {
    stacks.add(_globalQuakeRecordingStack(nextId, index: stacks.length));
  }

  return ObsAutomationPreset(
    id: nextId('preset'),
    name: legacy ? _legacyPresetName : obsEewRecordingPresetName,
    enabled: enabled,
    stacks: stacks,
  );
}

ObsAutomationStack _globalQuakeRecordingStack(
  String Function(String prefix) nextId, {
  required int index,
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
    id: nextId('stack'),
    x: 48 + index % 4 * 680,
    y: 48 + index ~/ 4 * 900,
    blocks: [
      block(ObsAutomationBlockType.unifiedEvent, const {
        'oncePerEvent': 'true',
      }),
      block(ObsAutomationBlockType.isEew),
      block(ObsAutomationBlockType.eewAgency, const {
        'operator': 'equals',
        'value': 'globalQuake',
      }),
      block(ObsAutomationBlockType.magnitude, const {
        'operator': 'greaterThanOrEqual',
        'value': '6.9',
      }),
      block(ObsAutomationBlockType.startRecord),
      block(ObsAutomationBlockType.wait, const {'seconds': '3600'}),
      block(ObsAutomationBlockType.stopRecord),
      block(ObsAutomationBlockType.stopScript),
    ],
  );
}

List<ObsAutomationBlock> _agencyRecordingBlocks(
  _AgencyRecordingRule rule,
  String Function(String prefix) nextId, {
  bool legacy = false,
}) {
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
    if (legacy || rule.minimumMagnitude != null)
      block(ObsAutomationBlockType.magnitude, {
        'operator': 'greaterThanOrEqual',
        'value': (legacy ? 5.0 : rule.minimumMagnitude!).toStringAsFixed(1),
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
    if (!legacy && rule.requireIntensityTitle)
      block(ObsAutomationBlockType.inputFieldCondition, const {
        'family': 'unified',
        'field': 'title',
        'operator': 'contains',
        'value': '震度',
      }),
    block(ObsAutomationBlockType.sameEarthquakeAsVariable, const {
      'variable': '目标EEW',
      'maxSeconds': '300',
      'maxDistanceKm': '300',
    }),
    block(ObsAutomationBlockType.wait, {'seconds': legacy ? '20' : '30'}),
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
    this.minimumMagnitude,
    this.requireIntensityTitle = false,
  });

  final String triggerAgency;
  final String stopAgency;
  final bool requireReviewed;
  final String? titleContains;
  final double? minimumMagnitude;
  final bool requireIntensityTitle;
}

// Only upgrade the original template; never replace user-edited programs.
List<ObsAutomationPreset> upgradeBuiltInEewRecordingPresets(
  List<ObsAutomationPreset> presets,
) {
  var sequence = 0;
  final legacy = _buildRecordingPreset(
    nextId: (prefix) => 'legacy-$prefix-${sequence++}',
    legacy: true,
  );
  final previous = _buildRecordingPreset(
    nextId: (prefix) => 'previous-$prefix-${sequence++}',
    includeGlobalQuake: false,
  );
  var changed = false;
  final upgraded = presets
      .map((preset) {
        final template = preset.name == _legacyPresetName
            ? legacy
            : preset.name == obsEewRecordingPresetName &&
                  AppEdition.hasGlobalQuake
            ? previous
            : null;
        if (template == null ||
            preset.stacks.length != template.stacks.length) {
          return preset;
        }
        for (var i = 0; i < template.stacks.length; i++) {
          final actual = preset.stacks[i].blocks;
          final expected = template.stacks[i].blocks;
          if (actual.length != expected.length) return preset;
          for (var j = 0; j < actual.length; j++) {
            if (actual[j].type != expected[j].type ||
                actual[j].parameters.length != expected[j].parameters.length ||
                !expected[j].parameters.entries.every(
                  (entry) => actual[j].parameters[entry.key] == entry.value,
                )) {
              return preset;
            }
          }
        }
        final replacement = buildEewRecordingPreset(
          nextId: (prefix) => '${preset.id}:upgrade:$prefix:${sequence++}',
          enabled: preset.enabled,
        );
        final stacks = <ObsAutomationStack>[];
        for (var i = 0; i < replacement.stacks.length; i++) {
          final next = replacement.stacks[i];
          if (i >= preset.stacks.length) {
            stacks.add(next);
            continue;
          }
          final previous = preset.stacks[i];
          final available = previous.blocks.toList();
          final blocks = next.blocks
              .map((block) {
                final index = available.indexWhere(
                  (old) => old.type == block.type,
                );
                if (index < 0) return block;
                final old = available.removeAt(index);
                return old.copyWith(parameters: block.parameters);
              })
              .toList(growable: false);
          stacks.add(previous.copyWith(blocks: blocks));
        }
        changed = true;
        return preset.copyWith(name: replacement.name, stacks: stacks);
      })
      .toList(growable: false);
  return changed ? upgraded : presets;
}
