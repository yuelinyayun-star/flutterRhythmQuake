enum ObsAutomationBlockType {
  unifiedEvent,
  networkDetection,
  stationChange,
  andBranch,
  orBranch,
  unifiedPhase,
  networkPhase,
  stationPhase,
  isEew,
  isInformation,
  eewAgency,
  informationAgency,
  informationReviewType,
  sameEarthquakeAsVariable,
  valueVariableCondition,
  inputFieldMatchesVariable,
  inputFieldCondition,
  compareValues,
  inputFieldValue,
  variableValue,
  arithmeticValue,
  randomValue,
  moduloValue,
  roundValue,
  mathValue,
  textJoinValue,
  textLengthValue,
  textContainsValue,
  comparisonValue,
  booleanValue,
  notValue,
  eventType,
  source,
  magnitude,
  estimatedIntensity,
  reportNumber,
  isFinal,
  networkMaxIntensity,
  detectedStationCount,
  stationId,
  stationName,
  currentStationIntensity,
  previousStationIntensity,
  wait,
  waitForUnifiedEvent,
  waitForInput,
  setEventVariable,
  setValueVariable,
  setVariable,
  changeVariable,
  stopScript,
  startRecord,
  stopRecord,
  pauseRecord,
  resumeRecord,
  splitRecordFile,
  createRecordChapter,
  setTextSourceText,
  setCurrentProgramScene,
  setSceneItemEnabled,
  startReplayBuffer,
  stopReplayBuffer,
  saveReplayBuffer,
}

class ObsAutomationBlock {
  const ObsAutomationBlock({
    required this.id,
    required this.type,
    this.parameters = const {},
  });

  final String id;
  final ObsAutomationBlockType type;
  final Map<String, String> parameters;

  ObsAutomationBlock copyWith({
    ObsAutomationBlockType? type,
    Map<String, String>? parameters,
  }) {
    return ObsAutomationBlock(
      id: id,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (parameters.isNotEmpty) 'parameters': parameters,
  };

  factory ObsAutomationBlock.fromJson(Map<String, dynamic> json) {
    final rawParameters = json['parameters'];
    final parameters = <String, String>{};
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        parameters[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    return ObsAutomationBlock(
      id: json['id']?.toString() ?? '',
      type: _enumByName(
        ObsAutomationBlockType.values,
        json['type'],
        ObsAutomationBlockType.unifiedEvent,
      ),
      parameters: parameters,
    );
  }
}

class ObsAutomationStack {
  const ObsAutomationStack({
    required this.id,
    required this.x,
    required this.y,
    required this.blocks,
  });

  final String id;
  final double x;
  final double y;
  final List<ObsAutomationBlock> blocks;

  ObsAutomationStack copyWith({
    double? x,
    double? y,
    List<ObsAutomationBlock>? blocks,
  }) {
    return ObsAutomationStack(
      id: id,
      x: x ?? this.x,
      y: y ?? this.y,
      blocks: blocks ?? this.blocks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };

  factory ObsAutomationStack.fromJson(Map<String, dynamic> json) {
    return ObsAutomationStack(
      id: json['id']?.toString() ?? '',
      x: _toDouble(json['x']),
      y: _toDouble(json['y']),
      blocks: _mapList(json['blocks'])
          .map(ObsAutomationBlock.fromJson)
          .where((block) => block.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ObsAutomationPreset {
  const ObsAutomationPreset({
    required this.id,
    required this.name,
    required this.enabled,
    required this.stacks,
  });

  static const int schemaVersion = 3;

  final String id;
  final String name;
  final bool enabled;
  final List<ObsAutomationStack> stacks;

  ObsAutomationPreset copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<ObsAutomationStack>? stacks,
  }) {
    return ObsAutomationPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      stacks: stacks ?? this.stacks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'stacks': stacks.map((stack) => stack.toJson()).toList(),
  };

  factory ObsAutomationPreset.fromJson(Map<String, dynamic> json) {
    return ObsAutomationPreset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名预设',
      enabled: json['enabled'] == true,
      stacks: _mapList(json['stacks'])
          .map(ObsAutomationStack.fromJson)
          .where((stack) => stack.id.isNotEmpty && stack.blocks.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ObsAutomationPresetDocument {
  const ObsAutomationPresetDocument({required this.presets});

  final List<ObsAutomationPreset> presets;

  Map<String, dynamic> toJson() => {
    'schemaVersion': ObsAutomationPreset.schemaVersion,
    'presets': presets.map((preset) => preset.toJson()).toList(),
  };

  factory ObsAutomationPresetDocument.fromJson(Map<String, dynamic> json) {
    final version = int.tryParse(json['schemaVersion']?.toString() ?? '');
    if (version == 1) return _migrateVersionOne(json);
    if (version == 2) return _migrateVersionTwo(json);
    if (version != ObsAutomationPreset.schemaVersion) {
      throw FormatException('Unsupported OBS automation schema: $version');
    }
    return ObsAutomationPresetDocument(
      presets: _mapList(json['presets'])
          .map(ObsAutomationPreset.fromJson)
          .where((preset) => preset.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}

ObsAutomationPresetDocument _migrateVersionOne(Map<String, dynamic> root) {
  var sequence = 0;
  String nextId(String prefix) => 'migrated-$prefix-${sequence++}';

  final presets = <ObsAutomationPreset>[];
  for (final rawPreset in _mapList(root['presets'])) {
    final blocks = <ObsAutomationBlock>[
      ObsAutomationBlock(
        id: nextId('block'),
        type: ObsAutomationBlockType.unifiedEvent,
      ),
      ObsAutomationBlock(
        id: nextId('block'),
        type: ObsAutomationBlockType.unifiedPhase,
        parameters: {
          'operator': 'equals',
          'value': switch (rawPreset['trigger']?.toString()) {
            'unifiedEventUpdated' => 'updated',
            'unifiedEventRemoved' => 'removed',
            _ => 'added',
          },
        },
      ),
    ];

    for (final condition in _mapList(rawPreset['conditions'])) {
      final type = switch (condition['field']?.toString()) {
        'source' => ObsAutomationBlockType.source,
        'magnitude' => ObsAutomationBlockType.magnitude,
        'estimatedIntensity' => ObsAutomationBlockType.estimatedIntensity,
        'reportNumber' => ObsAutomationBlockType.reportNumber,
        'isFinal' => ObsAutomationBlockType.isFinal,
        _ => ObsAutomationBlockType.eventType,
      };
      blocks.add(
        ObsAutomationBlock(
          id: condition['id']?.toString().isNotEmpty == true
              ? condition['id'].toString()
              : nextId('block'),
          type: type,
          parameters: {
            'operator': condition['operator']?.toString() ?? 'equals',
            'value': condition['value']?.toString() ?? '',
          },
        ),
      );
    }

    for (final action in _mapList(rawPreset['actions'])) {
      final type = _enumByName(
        ObsAutomationBlockType.values,
        action['type'],
        ObsAutomationBlockType.startRecord,
      );
      blocks.add(
        ObsAutomationBlock(
          id: action['id']?.toString().isNotEmpty == true
              ? action['id'].toString()
              : nextId('block'),
          type: type,
          parameters: action['parameter']?.toString().isNotEmpty == true
              ? {'text': action['parameter'].toString()}
              : const {},
        ),
      );
    }

    final presetId = rawPreset['id']?.toString();
    presets.add(
      ObsAutomationPreset(
        id: presetId?.isNotEmpty == true ? presetId! : nextId('preset'),
        name: rawPreset['name']?.toString() ?? '迁移的 OBS 预设',
        enabled: rawPreset['enabled'] == true,
        stacks: [
          ObsAutomationStack(id: nextId('stack'), x: 56, y: 56, blocks: blocks),
        ],
      ),
    );
  }
  return ObsAutomationPresetDocument(presets: presets);
}

ObsAutomationPresetDocument _migrateVersionTwo(Map<String, dynamic> root) {
  var sequence = 0;
  String nextId() => 'migrated-v2-condition-${sequence++}';

  final presets = _mapList(root['presets'])
      .map((rawPreset) {
        final preset = ObsAutomationPreset.fromJson(rawPreset);
        final stacks = preset.stacks
            .map((stack) {
              final blocks = <ObsAutomationBlock>[];
              for (final block in stack.blocks) {
                final phase = block.parameters['phase'];
                final parameters = Map<String, String>.from(block.parameters)
                  ..remove('phase');
                blocks.add(block.copyWith(parameters: parameters));
                if (phase == null || phase.isEmpty || phase == 'any') continue;
                final conditionType = switch (block.type) {
                  ObsAutomationBlockType.unifiedEvent =>
                    ObsAutomationBlockType.unifiedPhase,
                  ObsAutomationBlockType.networkDetection =>
                    ObsAutomationBlockType.networkPhase,
                  ObsAutomationBlockType.stationChange =>
                    ObsAutomationBlockType.stationPhase,
                  _ => null,
                };
                if (conditionType == null) continue;
                blocks.add(
                  ObsAutomationBlock(
                    id: nextId(),
                    type: conditionType,
                    parameters: {'operator': 'equals', 'value': phase},
                  ),
                );
              }
              return stack.copyWith(blocks: blocks);
            })
            .toList(growable: false);
        return preset.copyWith(stacks: stacks);
      })
      .toList(growable: false);
  return ObsAutomationPresetDocument(presets: presets);
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

Iterable<Map<String, dynamic>> _mapList(Object? raw) sync* {
  if (raw is! List) return;
  for (final item in raw) {
    if (item is Map<String, dynamic>) {
      yield item;
    } else if (item is Map) {
      yield Map<String, dynamic>.from(item);
    }
  }
}
