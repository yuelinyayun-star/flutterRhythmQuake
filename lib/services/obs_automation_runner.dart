import 'dart:async';

import '../models/obs_automation_preset.dart';
import 'obs_automation_condition_evaluator.dart';
import 'obs_automation_input_service.dart';
import 'obs_websocket_service.dart';

abstract interface class ObsAutomationActionExecutor {
  Future<void> execute(ObsAutomationBlock block);
}

class ObsWebSocketActionExecutor implements ObsAutomationActionExecutor {
  const ObsWebSocketActionExecutor(this.service);

  final ObsWebSocketService service;

  @override
  Future<void> execute(ObsAutomationBlock block) async {
    switch (block.type) {
      case ObsAutomationBlockType.startRecord:
        await service.startRecord();
      case ObsAutomationBlockType.stopRecord:
        await service.stopRecord();
      case ObsAutomationBlockType.pauseRecord:
        await service.pauseRecord();
      case ObsAutomationBlockType.resumeRecord:
        await service.resumeRecord();
      case ObsAutomationBlockType.splitRecordFile:
        await service.splitRecordFile();
      case ObsAutomationBlockType.createRecordChapter:
        await service.createRecordChapter(
          chapterName: block.parameters['text'],
        );
      case ObsAutomationBlockType.setTextSourceText:
        await service.setInputText(
          inputName: block.parameters['inputName'] ?? '',
          text: block.parameters['text'] ?? '',
        );
      case ObsAutomationBlockType.setCurrentProgramScene:
        await service.setCurrentProgramScene(
          block.parameters['sceneName'] ?? '',
        );
      case ObsAutomationBlockType.setSceneItemEnabled:
        await service.setSceneItemEnabled(
          sceneName: block.parameters['sceneName'] ?? '',
          sourceName: block.parameters['sourceName'] ?? '',
          enabled: block.parameters['enabled'] == 'true',
        );
      case ObsAutomationBlockType.startReplayBuffer:
        await service.startReplayBuffer();
      case ObsAutomationBlockType.stopReplayBuffer:
        await service.stopReplayBuffer();
      case ObsAutomationBlockType.saveReplayBuffer:
        await service.saveReplayBuffer();
      default:
        throw StateError(
          'Unsupported OBS automation action: ${block.type.name}',
        );
    }
  }
}

class ObsAutomationRunner {
  ObsAutomationRunner({
    required ObsAutomationInputService inputService,
    required ObsAutomationActionExecutor actionExecutor,
    ObsAutomationConditionEvaluator evaluator =
        const ObsAutomationConditionEvaluator(),
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  }) : _inputService = inputService,
       _actionExecutor = actionExecutor,
       _evaluator = evaluator,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  static const triggerEventVariable = '触发事件';
  static const currentEventVariable = '当前事件';
  static const _maxActiveWaiters = 64;

  final ObsAutomationInputService _inputService;
  final ObsAutomationActionExecutor _actionExecutor;
  final ObsAutomationConditionEvaluator _evaluator;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;
  final List<_WaitingExecution> _waiters = [];
  final Set<String> _recordingOwners = {};
  final Set<String> _replayBufferOwners = {};

  StreamSubscription<ObsAutomationInputEvent>? _subscription;
  Timer? _waiterExpiryTimer;
  List<ObsAutomationPreset> _presets = const [];
  Future<void> _inputQueue = Future.value();
  int _executionSequence = 0;
  bool _disposed = false;
  String? _lastError;

  bool get isListening => _subscription != null;
  int get activeWaiterCount => _waiters.length;
  String? get lastError => _lastError;

  void configure(List<ObsAutomationPreset> presets) {
    if (_disposed) return;
    _presets = presets
        .where((preset) => preset.enabled)
        .toList(growable: false);
    if (_presets.isEmpty) {
      unawaited(_stopListening());
      return;
    }
    _subscription ??= _inputService.events.listen(_enqueueInput);
  }

  void _enqueueInput(ObsAutomationInputEvent event) {
    _inputQueue = _inputQueue.then((_) => _processInput(event)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _lastError = error.toString();
    });
  }

  Future<void> _processInput(ObsAutomationInputEvent event) async {
    _removeExpiredWaiters();
    final matchingWaiters = _waiters
        .where((waiter) {
          if (!_evaluator.matchesInputKind(waiter.inputKind, event)) {
            return false;
          }
          return _evaluator.matchesConditions(
            waiter.conditions,
            event,
            context: ObsAutomationEvaluationContext(
              eventVariables: waiter.execution.variables,
              valueVariables: waiter.execution.valueVariables,
            ),
          );
        })
        .toList(growable: false);

    for (final waiter in matchingWaiters) {
      _waiters.remove(waiter);
      waiter.execution.currentEvent = event;
      waiter.execution.variables[currentEventVariable] = event;
      unawaited(_advance(waiter.execution, waiter.resumeIndex));
    }
    if (matchingWaiters.isNotEmpty) _scheduleWaiterExpiry();

    for (final preset in _presets) {
      for (final stack in preset.stacks) {
        final parsed = _parseStack(stack);
        if (parsed == null ||
            !_evaluator.matchesBlocks(parsed.triggerBlocks, event)) {
          continue;
        }
        final execution = _Execution(
          id: '${preset.id}:${stack.id}:${_executionSequence++}',
          presetId: preset.id,
          blocks: stack.blocks,
          currentEvent: event,
          variables: {triggerEventVariable: event, currentEventVariable: event},
          valueVariables: {},
        );
        unawaited(_advance(execution, parsed.programStart));
      }
    }
  }

  Future<void> _advance(_Execution execution, int startIndex) async {
    var index = startIndex;
    try {
      while (!_disposed && index < execution.blocks.length) {
        final block = execution.blocks[index];
        if (_isCondition(block.type)) {
          final conditionStart = index;
          index++;
          while (index < execution.blocks.length &&
              (_isCondition(execution.blocks[index].type) ||
                  execution.blocks[index].type ==
                      ObsAutomationBlockType.andBranch)) {
            index++;
          }
          if (!_evaluator.matchesConditions(
            execution.blocks.sublist(conditionStart, index),
            execution.currentEvent,
            context: ObsAutomationEvaluationContext(
              eventVariables: execution.variables,
              valueVariables: execution.valueVariables,
            ),
          )) {
            return;
          }
          continue;
        }
        switch (block.type) {
          case ObsAutomationBlockType.wait:
            final seconds = _positiveDouble(
              block.parameters['seconds'],
              fallback: 1,
            );
            await _delay(Duration(milliseconds: (seconds * 1000).round()));
            index++;
          case ObsAutomationBlockType.setEventVariable:
            final name = block.parameters['name']?.trim() ?? '';
            if (name.isNotEmpty) {
              execution.variables[name] = execution.currentEvent;
            }
            index++;
          case ObsAutomationBlockType.setValueVariable:
            final name = block.parameters['name']?.trim() ?? '';
            if (name.isNotEmpty) {
              final value = _evaluator.readInputField(
                execution.currentEvent,
                block.parameters['field'],
              );
              if (value != null) execution.valueVariables[name] = value;
            }
            index++;
          case ObsAutomationBlockType.setVariable:
            final name = block.parameters['name']?.trim() ?? '';
            if (name.isNotEmpty) {
              final value = _evaluator.resolveValueReference(
                execution.currentEvent,
                kind: block.parameters['valueKind'] ?? 'literal',
                value: block.parameters['value'] ?? '',
                context: ObsAutomationEvaluationContext(
                  eventVariables: execution.variables,
                  valueVariables: execution.valueVariables,
                ),
              );
              if (value != null) {
                execution.valueVariables[name] = value is String
                    ? _parseScalar(value)
                    : value;
              }
            }
            index++;
          case ObsAutomationBlockType.changeVariable:
            _changeVariable(execution, block);
            index++;
          case ObsAutomationBlockType.waitForUnifiedEvent:
          case ObsAutomationBlockType.waitForInput:
            final conditionStart = index + 1;
            var resumeIndex = conditionStart;
            while (resumeIndex < execution.blocks.length &&
                (_isCondition(execution.blocks[resumeIndex].type) ||
                    execution.blocks[resumeIndex].type ==
                        ObsAutomationBlockType.andBranch)) {
              resumeIndex++;
            }
            final timeoutSeconds = _positiveDouble(
              block.parameters['timeoutSeconds'],
              fallback: 1800,
            );
            if (_waiters.length >= _maxActiveWaiters) {
              _waiters.removeAt(0);
            }
            _waiters.add(
              _WaitingExecution(
                execution: execution,
                inputKind:
                    block.type == ObsAutomationBlockType.waitForUnifiedEvent
                    ? 'unifiedEvent'
                    : block.parameters['kind'] ?? 'unifiedEvent',
                conditions: execution.blocks.sublist(
                  conditionStart,
                  resumeIndex,
                ),
                resumeIndex: resumeIndex,
                expiresAt: _now().add(
                  Duration(milliseconds: (timeoutSeconds * 1000).round()),
                ),
                timeoutBehavior: block.parameters['onTimeout'] ?? 'stopScript',
              ),
            );
            _scheduleWaiterExpiry();
            return;
          case ObsAutomationBlockType.stopScript:
            return;
          case ObsAutomationBlockType.startRecord:
          case ObsAutomationBlockType.stopRecord:
          case ObsAutomationBlockType.pauseRecord:
          case ObsAutomationBlockType.resumeRecord:
          case ObsAutomationBlockType.splitRecordFile:
          case ObsAutomationBlockType.createRecordChapter:
          case ObsAutomationBlockType.setTextSourceText:
          case ObsAutomationBlockType.setCurrentProgramScene:
          case ObsAutomationBlockType.setSceneItemEnabled:
          case ObsAutomationBlockType.startReplayBuffer:
          case ObsAutomationBlockType.stopReplayBuffer:
          case ObsAutomationBlockType.saveReplayBuffer:
            await _executeAction(execution, block);
            index++;
          default:
            throw StateError(
              'Invalid program block ${block.type.name} in ${execution.id}',
            );
        }
      }
    } catch (error) {
      _lastError = '${execution.presetId}: $error';
    }
  }

  _ParsedStack? _parseStack(ObsAutomationStack stack) {
    final blocks = stack.blocks;
    if (blocks.isEmpty || !_isInput(blocks.first.type)) return null;
    var index = 0;
    while (index < blocks.length) {
      if (!_isInput(blocks[index].type)) return null;
      index++;
      var sawCondition = false;
      var expectsConditionAfterAnd = false;
      while (index < blocks.length) {
        if (_isCondition(blocks[index].type)) {
          sawCondition = true;
          expectsConditionAfterAnd = false;
          index++;
          continue;
        }
        if (blocks[index].type == ObsAutomationBlockType.andBranch) {
          if (!sawCondition || expectsConditionAfterAnd) return null;
          expectsConditionAfterAnd = true;
          index++;
          continue;
        }
        break;
      }
      if (expectsConditionAfterAnd) return null;
      if (index < blocks.length &&
          blocks[index].type == ObsAutomationBlockType.orBranch) {
        index++;
        if (index >= blocks.length) return null;
        continue;
      }
      break;
    }
    if (index >= blocks.length) return null;
    final triggerBlocks = blocks.sublist(0, index);
    if (!_validProgram(blocks.sublist(index))) return null;
    return _ParsedStack(triggerBlocks: triggerBlocks, programStart: index);
  }

  bool _validProgram(List<ObsAutomationBlock> blocks) {
    var acceptsConditions = false;
    var previousWasCondition = false;
    var expectsConditionAfterAnd = false;
    for (final block in blocks) {
      if (block.type == ObsAutomationBlockType.waitForUnifiedEvent) {
        if (expectsConditionAfterAnd) return false;
        acceptsConditions = true;
        previousWasCondition = false;
        continue;
      }
      if (block.type == ObsAutomationBlockType.waitForInput) {
        if (expectsConditionAfterAnd) return false;
        acceptsConditions = true;
        previousWasCondition = false;
        continue;
      }
      if (_isCondition(block.type)) {
        if (!acceptsConditions) return false;
        previousWasCondition = true;
        expectsConditionAfterAnd = false;
        continue;
      }
      if (block.type == ObsAutomationBlockType.andBranch) {
        if (!previousWasCondition || expectsConditionAfterAnd) return false;
        expectsConditionAfterAnd = true;
        continue;
      }
      if (expectsConditionAfterAnd) return false;
      if (block.type == ObsAutomationBlockType.setEventVariable ||
          block.type == ObsAutomationBlockType.setValueVariable ||
          block.type == ObsAutomationBlockType.setVariable ||
          block.type == ObsAutomationBlockType.changeVariable) {
        acceptsConditions = true;
        previousWasCondition = false;
        continue;
      }
      if (_isProgramAction(block.type)) {
        acceptsConditions = false;
        previousWasCondition = false;
        continue;
      }
      return false;
    }
    return !expectsConditionAfterAnd;
  }

  void _removeExpiredWaiters() {
    final now = _now();
    final expired = _waiters
        .where((waiter) => !waiter.expiresAt.isAfter(now))
        .toList(growable: false);
    if (expired.isNotEmpty) {
      _waiters.removeWhere(expired.contains);
      for (final waiter in expired) {
        switch (waiter.timeoutBehavior) {
          case 'continue':
            unawaited(_advance(waiter.execution, waiter.resumeIndex));
            break;
          case 'stopRecord':
            unawaited(
              _executeAction(
                waiter.execution,
                const ObsAutomationBlock(
                  id: 'wait-timeout-stop-record',
                  type: ObsAutomationBlockType.stopRecord,
                ),
              ),
            );
            break;
          default:
            break;
        }
      }
    }
    _scheduleWaiterExpiry();
  }

  void _scheduleWaiterExpiry() {
    _waiterExpiryTimer?.cancel();
    _waiterExpiryTimer = null;
    if (_waiters.isEmpty || _disposed) return;
    var earliest = _waiters.first.expiresAt;
    for (final waiter in _waiters.skip(1)) {
      if (waiter.expiresAt.isBefore(earliest)) earliest = waiter.expiresAt;
    }
    final delay = earliest.difference(_now());
    _waiterExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _removeExpiredWaiters,
    );
  }

  Future<void> _executeAction(
    _Execution execution,
    ObsAutomationBlock block,
  ) async {
    final resolvedBlock = _resolveActionParameters(execution, block);
    switch (block.type) {
      case ObsAutomationBlockType.startRecord:
        if (!_recordingOwners.add(execution.id)) return;
        if (_recordingOwners.length > 1) return;
        try {
          await _actionExecutor.execute(resolvedBlock);
        } catch (_) {
          _recordingOwners.remove(execution.id);
          rethrow;
        }
        return;
      case ObsAutomationBlockType.stopRecord:
        if (_recordingOwners.remove(execution.id)) {
          if (_recordingOwners.isNotEmpty) return;
        } else {
          _recordingOwners.clear();
        }
        await _actionExecutor.execute(resolvedBlock);
        return;
      case ObsAutomationBlockType.startReplayBuffer:
        if (!_replayBufferOwners.add(execution.id)) return;
        if (_replayBufferOwners.length > 1) return;
        try {
          await _actionExecutor.execute(resolvedBlock);
        } catch (_) {
          _replayBufferOwners.remove(execution.id);
          rethrow;
        }
        return;
      case ObsAutomationBlockType.stopReplayBuffer:
        if (_replayBufferOwners.remove(execution.id)) {
          if (_replayBufferOwners.isNotEmpty) return;
        } else {
          _replayBufferOwners.clear();
        }
        await _actionExecutor.execute(resolvedBlock);
        return;
      default:
        await _actionExecutor.execute(resolvedBlock);
    }
  }

  ObsAutomationBlock _resolveActionParameters(
    _Execution execution,
    ObsAutomationBlock block,
  ) {
    if (block.parameters.isEmpty) return block;
    final parameters = block.parameters.map<String, String>((key, raw) {
      final value = _resolveTemplate(execution, raw);
      return MapEntry(key, value);
    });
    final context = ObsAutomationEvaluationContext(
      eventVariables: execution.variables,
      valueVariables: execution.valueVariables,
    );
    if (block.type == ObsAutomationBlockType.setTextSourceText) {
      final text = _evaluator.resolveValueReference(
        execution.currentEvent,
        kind: parameters['textKind'] ?? 'literal',
        value: parameters['textValue'] ?? parameters['text'] ?? '',
        context: context,
      );
      parameters['text'] = text?.toString() ?? '';
    }
    if (block.type == ObsAutomationBlockType.setSceneItemEnabled) {
      final enabled = _evaluator.resolveValueReference(
        execution.currentEvent,
        kind: parameters['enabledKind'] ?? 'literal',
        value: parameters['enabledValue'] ?? 'true',
        context: context,
      );
      parameters['enabled'] = _asBool(enabled).toString();
    }
    return block.copyWith(parameters: parameters);
  }

  String _resolveTemplate(_Execution execution, String raw) {
    final pattern = RegExp(r'\{\{([^{}]+)\}\}');
    return raw.replaceAllMapped(pattern, (match) {
      final name = match.group(1)?.trim() ?? '';
      final replacement = execution.valueVariables.containsKey(name)
          ? execution.valueVariables[name]
          : _evaluator.readInputField(execution.currentEvent, name);
      return replacement?.toString() ?? match.group(0)!;
    });
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  Object _parseScalar(String raw) {
    final normalized = raw.trim();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return num.tryParse(normalized) ?? raw;
  }

  void _changeVariable(_Execution execution, ObsAutomationBlock block) {
    final name = block.parameters['name']?.trim() ?? '';
    if (name.isEmpty) return;
    final operation = block.parameters['operation'] ?? 'add';
    final operandRaw = _resolveTemplate(
      execution,
      block.parameters['operand'] ?? '',
    );
    if (operation == 'append') {
      final current = execution.valueVariables[name]?.toString() ?? '';
      execution.valueVariables[name] = '$current$operandRaw';
      return;
    }
    final currentRaw = execution.valueVariables[name];
    final current = currentRaw is num
        ? currentRaw.toDouble()
        : double.tryParse(currentRaw?.toString() ?? '');
    final operand = double.tryParse(operandRaw.trim());
    if (current == null || operand == null) {
      throw StateError('Variable "$name" requires numeric operands.');
    }
    execution.valueVariables[name] = switch (operation) {
      'subtract' => current - operand,
      'multiply' => current * operand,
      'divide' when operand != 0 => current / operand,
      'divide' => throw StateError('Variable "$name" cannot divide by zero.'),
      _ => current + operand,
    };
  }

  bool _isInput(ObsAutomationBlockType type) => const {
    ObsAutomationBlockType.unifiedEvent,
    ObsAutomationBlockType.networkDetection,
    ObsAutomationBlockType.stationChange,
  }.contains(type);

  bool _isCondition(ObsAutomationBlockType type) => const {
    ObsAutomationBlockType.unifiedPhase,
    ObsAutomationBlockType.networkPhase,
    ObsAutomationBlockType.stationPhase,
    ObsAutomationBlockType.isEew,
    ObsAutomationBlockType.isInformation,
    ObsAutomationBlockType.eewAgency,
    ObsAutomationBlockType.informationAgency,
    ObsAutomationBlockType.informationReviewType,
    ObsAutomationBlockType.sameEarthquakeAsVariable,
    ObsAutomationBlockType.valueVariableCondition,
    ObsAutomationBlockType.inputFieldMatchesVariable,
    ObsAutomationBlockType.inputFieldCondition,
    ObsAutomationBlockType.compareValues,
    ObsAutomationBlockType.eventType,
    ObsAutomationBlockType.source,
    ObsAutomationBlockType.magnitude,
    ObsAutomationBlockType.estimatedIntensity,
    ObsAutomationBlockType.reportNumber,
    ObsAutomationBlockType.isFinal,
    ObsAutomationBlockType.networkMaxIntensity,
    ObsAutomationBlockType.detectedStationCount,
    ObsAutomationBlockType.stationId,
    ObsAutomationBlockType.stationName,
    ObsAutomationBlockType.currentStationIntensity,
    ObsAutomationBlockType.previousStationIntensity,
  }.contains(type);

  bool _isProgramAction(ObsAutomationBlockType type) => const {
    ObsAutomationBlockType.wait,
    ObsAutomationBlockType.setEventVariable,
    ObsAutomationBlockType.setValueVariable,
    ObsAutomationBlockType.setVariable,
    ObsAutomationBlockType.changeVariable,
    ObsAutomationBlockType.stopScript,
    ObsAutomationBlockType.startRecord,
    ObsAutomationBlockType.stopRecord,
    ObsAutomationBlockType.pauseRecord,
    ObsAutomationBlockType.resumeRecord,
    ObsAutomationBlockType.splitRecordFile,
    ObsAutomationBlockType.createRecordChapter,
    ObsAutomationBlockType.setTextSourceText,
    ObsAutomationBlockType.setCurrentProgramScene,
    ObsAutomationBlockType.setSceneItemEnabled,
    ObsAutomationBlockType.startReplayBuffer,
    ObsAutomationBlockType.stopReplayBuffer,
    ObsAutomationBlockType.saveReplayBuffer,
  }.contains(type);

  double _positiveDouble(String? raw, {required double fallback}) {
    final value = double.tryParse(raw ?? '');
    return value != null && value.isFinite && value > 0 ? value : fallback;
  }

  Future<void> _stopListening() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _waiterExpiryTimer?.cancel();
    _waiterExpiryTimer = null;
    _waiters.clear();
    _recordingOwners.clear();
    _replayBufferOwners.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopListening();
  }
}

class _ParsedStack {
  const _ParsedStack({required this.triggerBlocks, required this.programStart});

  final List<ObsAutomationBlock> triggerBlocks;
  final int programStart;
}

class _Execution {
  _Execution({
    required this.id,
    required this.presetId,
    required this.blocks,
    required this.currentEvent,
    required this.variables,
    required this.valueVariables,
  });

  final String id;
  final String presetId;
  final List<ObsAutomationBlock> blocks;
  ObsAutomationInputEvent currentEvent;
  final Map<String, ObsAutomationInputEvent> variables;
  final Map<String, Object?> valueVariables;
}

class _WaitingExecution {
  const _WaitingExecution({
    required this.execution,
    required this.inputKind,
    required this.conditions,
    required this.resumeIndex,
    required this.expiresAt,
    required this.timeoutBehavior,
  });

  final _Execution execution;
  final String inputKind;
  final List<ObsAutomationBlock> conditions;
  final int resumeIndex;
  final DateTime expiresAt;
  final String timeoutBehavior;
}
