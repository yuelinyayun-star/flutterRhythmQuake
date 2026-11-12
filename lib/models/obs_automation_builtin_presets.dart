import '../core/app_edition.dart';
import '../services/native_obs_automation_policy.dart';
import 'obs_automation_preset.dart';

const obsEewRecordingPresetName = 'EEW 分机构自动录制';
const obsRecordingDefaultLimitSeconds = '1800';
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
  bool includeSasmex = true,
  bool includeShakeAlert = true,
  bool originalThresholds = false,
  String recordingLimit = obsRecordingDefaultLimitSeconds,
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
      titleContains: legacy || originalThresholds ? '震源' : '各地',
      minimumMagnitude: originalThresholds ? 4 : 0,
      requireIntensityTitle: true,
    ),
    _AgencyRecordingRule(triggerAgency: 'cwa', stopAgency: 'cwa'),
    _AgencyRecordingRule(
      triggerAgency: 'kma',
      stopAgency: 'kma',
      minimumMagnitude: originalThresholds ? 5 : 0,
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
        blocks: _agencyRecordingBlocks(
          rule,
          nextId,
          legacy: legacy,
          recordingLimit: recordingLimit,
        ),
      ),
    );
  }
  if (!legacy && includeGlobalQuake && AppEdition.hasGlobalQuake) {
    stacks.add(
      _globalQuakeRecordingStack(
        nextId,
        index: stacks.length,
        minimumMagnitude: originalThresholds ? '6.9' : '5.0',
        recordingLimit: recordingLimit,
      ),
    );
  }
  if (!legacy && includeSasmex) {
    final index = stacks.length;
    stacks.add(
      ObsAutomationStack(
        id: nextId('stack'),
        x: 48 + index % 4 * 680,
        y: 48 + index ~/ 4 * 900,
        blocks: _agencyRecordingBlocks(
          const _AgencyRecordingRule(
            triggerAgency: 'sasmex',
            stopAgency: 'ssn',
            minimumMagnitude: null,
          ),
          nextId,
          recordingLimit: recordingLimit,
        ),
      ),
    );
  }

  if (!legacy && includeShakeAlert) {
    stacks.add(buildShakeAlertRecordingRule(nextId));
  }

  return ObsAutomationPreset(
    id: nextId('preset'),
    name: legacy ? _legacyPresetName : obsEewRecordingPresetName,
    enabled: enabled,
    stacks: stacks,
  );
}

ObsAutomationStack buildShakeAlertRecordingRule(
  String Function(String prefix) nextId,
) => ObsAutomationStack(
  id: nextId('stack'),
  x: 48,
  y: 2748,
  blocks: _agencyRecordingBlocks(
    const _AgencyRecordingRule(triggerAgency: 'shakeAlert', stopAgency: 'usgs'),
    nextId,
  ),
);

ObsAutomationStack _globalQuakeRecordingStack(
  String Function(String prefix) nextId, {
  required int index,
  String minimumMagnitude = '5.0',
  String recordingLimit = obsRecordingDefaultLimitSeconds,
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
      block(ObsAutomationBlockType.magnitude, {
        'operator': 'greaterThanOrEqual',
        'value': minimumMagnitude,
      }),
      block(ObsAutomationBlockType.startRecord),
      block(ObsAutomationBlockType.wait, {'seconds': recordingLimit}),
      block(ObsAutomationBlockType.stopRecord),
      block(ObsAutomationBlockType.stopScript),
    ],
  );
}

List<ObsAutomationBlock> _agencyRecordingBlocks(
  _AgencyRecordingRule rule,
  String Function(String prefix) nextId, {
  bool legacy = false,
  String recordingLimit = obsRecordingDefaultLimitSeconds,
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
    if (legacy || (rule.minimumMagnitude ?? 0) > 0)
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
    block(ObsAutomationBlockType.waitForUnifiedEvent, {
      'timeoutSeconds': recordingLimit,
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
    this.minimumMagnitude = 0,
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
    recordingLimit: '3600', // Historical fingerprint, not a new default.
  );
  final previous = _buildRecordingPreset(
    nextId: (prefix) => 'previous-$prefix-${sequence++}',
    includeGlobalQuake: false,
    includeSasmex: false,
    includeShakeAlert: false,
    recordingLimit: '3600',
  );
  final previousWithGlobalQuake = _buildRecordingPreset(
    nextId: (prefix) => 'previous-gq-$prefix-${sequence++}',
    includeSasmex: false,
    includeShakeAlert: false,
    recordingLimit: '3600',
  );
  final originalTemplates = [
    for (final mode in [0, 1, 2])
      _buildRecordingPreset(
        nextId: (prefix) => 'original-$prefix-${sequence++}',
        originalThresholds: true,
        recordingLimit: '3600',
        includeGlobalQuake: mode != 0,
        includeSasmex: mode == 2,
        includeShakeAlert: false,
      ),
  ];
  var changed = false;
  final upgraded = presets
      .map((preset) {
        // The settings form appends this independent information rule. Its
        // configuration must survive an otherwise untouched EEW template upgrade.
        final hasCencInformation =
            preset.stacks.lastOrNull?.id == '${preset.id}:cenc-information-v1';
        final managedStacks = hasCencInformation
            ? preset.stacks.take(preset.stacks.length - 1).toList()
            : preset.stacks;
        final candidates = preset.name == _legacyPresetName
            ? [legacy]
            : preset.name == obsEewRecordingPresetName
            ? [previous, previousWithGlobalQuake, ...originalTemplates]
            : <ObsAutomationPreset>[];
        final template = candidates.where((candidate) {
          if (candidate.stacks.length != managedStacks.length) return false;
          for (var i = 0; i < candidate.stacks.length; i++) {
            final actual = managedStacks[i].blocks;
            final expected = candidate.stacks[i].blocks;
            if (actual.length != expected.length) return false;
            for (var j = 0; j < actual.length; j++) {
              if (actual[j].type != expected[j].type ||
                  actual[j].parameters.length !=
                      expected[j].parameters.length ||
                  !expected[j].parameters.entries.every(
                    (entry) => actual[j].parameters[entry.key] == entry.value,
                  )) {
                return false;
              }
            }
          }
          return true;
        }).firstOrNull;
        if (template == null) return preset;
        // This migration predates the new defaults. Preserve its historical
        // timing contract; changing defaults must not rewrite saved programs.
        final replacement = _buildRecordingPreset(
          nextId: (prefix) => '${preset.id}:upgrade:$prefix:${sequence++}',
          enabled: preset.enabled,
          recordingLimit: '3600',
          includeShakeAlert: false,
        );
        final stacks = <ObsAutomationStack>[];
        for (var i = 0; i < replacement.stacks.length; i++) {
          final next = replacement.stacks[i];
          if (i >= managedStacks.length) {
            stacks.add(next);
            continue;
          }
          final previous = managedStacks[i];
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
        return preset.copyWith(
          name: replacement.name,
          stacks: [...stacks, if (hasCencInformation) preset.stacks.last],
        );
      })
      .toList(growable: false);
  final result = changed ? upgraded : presets;
  final additions = NativeObsAutomationPolicy.missingShakeAlertRules(result);
  if (additions.isEmpty) return result;
  return [
    for (var index = 0; index < result.length; index++)
      if (additions.contains(index))
        result[index].copyWith(
          stacks: [
            ...result[index].stacks,
            buildShakeAlertRecordingRule(
              (prefix) =>
                  '${result[index].id}:shake-alert-v1:$prefix:${sequence++}',
            ),
          ],
        )
      else
        result[index],
  ];
}
