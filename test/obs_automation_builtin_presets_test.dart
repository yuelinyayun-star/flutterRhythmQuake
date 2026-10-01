import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/app_edition.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/obs_automation_runner.dart';
import 'package:flutterrhythmquake/services/obs_automation_runtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final input = ObsAutomationInputService();

  setUp(input.resetForTest);
  tearDown(input.resetForTest);

  test(
    'EEW preset contains the requested threshold and complete agency flow',
    () {
      var sequence = 0;
      final preset = buildEewRecordingPreset(
        nextId: (prefix) => '$prefix-${sequence++}',
      );

      expect(preset.name, obsEewRecordingPresetName);
      expect(preset.enabled, isFalse);
      expect(preset.stacks, hasLength(_expectedStackCount));

      final expectedRules = <String, ({String stopAgency, bool reviewed})>{
        'cea': (stopAgency: 'cenc', reviewed: true),
        'sichuan': (stopAgency: 'cenc', reviewed: true),
        'fujian': (stopAgency: 'cenc', reviewed: true),
        'chongqing': (stopAgency: 'cenc', reviewed: true),
        'jma': (stopAgency: 'jma', reviewed: false),
        'cwa': (stopAgency: 'cwa', reviewed: false),
        'kma': (stopAgency: 'kma', reviewed: false),
        if (AppEdition.hasIcl) 'icl': (stopAgency: 'cenc', reviewed: true),
      };

      for (final stack in preset.stacks) {
        final eewAgency = _singleBlock(stack, ObsAutomationBlockType.eewAgency);
        final triggerAgency = eewAgency.parameters['value']!;
        if (triggerAgency == 'globalQuake') {
          expect(
            _singleBlock(
              stack,
              ObsAutomationBlockType.unifiedEvent,
            ).parameters['oncePerEvent'],
            'true',
          );
          expect(
            _singleBlock(
              stack,
              ObsAutomationBlockType.magnitude,
            ).parameters['value'],
            '6.9',
          );
          expect(
            _singleBlock(
              stack,
              ObsAutomationBlockType.wait,
            ).parameters['seconds'],
            '3600',
          );
          expect(stack.blocks.map((block) => block.type), [
            ObsAutomationBlockType.unifiedEvent,
            ObsAutomationBlockType.isEew,
            ObsAutomationBlockType.eewAgency,
            ObsAutomationBlockType.magnitude,
            ObsAutomationBlockType.startRecord,
            ObsAutomationBlockType.wait,
            ObsAutomationBlockType.stopRecord,
            ObsAutomationBlockType.stopScript,
          ]);
          continue;
        }
        final expected = expectedRules[triggerAgency];
        expect(expected, isNotNull, reason: 'unexpected agency $triggerAgency');
        expect(
          _singleBlock(stack, ObsAutomationBlockType.unifiedPhase).parameters,
          containsPair('value', 'added'),
        );
        final magnitudeBlocks = stack.blocks.where(
          (block) => block.type == ObsAutomationBlockType.magnitude,
        );
        if (triggerAgency == 'jma' || triggerAgency == 'kma') {
          expect(
            magnitudeBlocks.single.parameters['value'],
            triggerAgency == 'jma' ? '4.0' : '5.0',
          );
        } else {
          expect(magnitudeBlocks, isEmpty);
        }
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
          containsPair('seconds', '30'),
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
        jmaStack.blocks
            .where(
              (block) =>
                  block.type == ObsAutomationBlockType.inputFieldCondition,
            )
            .map((block) => block.parameters['value']),
        ['震源', '震度'],
      );
    },
  );

  test(
    'domestic EEW records immediately even with unknown magnitude',
    () async {
      for (final source in [
        'ceaEew',
        'scEew',
        'fjEew',
        'cqEew',
        'cwaEew',
        if (AppEdition.hasIcl) 'iclEew',
      ]) {
        for (final magnitude in [-1.0, 3.0, 4.9]) {
          input.resetForTest();
          final executor = _FakeActionExecutor();
          final runner = _runner(input, executor);
          input.emitUnifiedEvent(
            _event(
              source: source,
              eventId: '$source-$magnitude',
              isEew: true,
              originTime: DateTime.utc(2026, 8, 21, 12),
              magnitude: magnitude,
            ),
            ObsUnifiedEventPhase.added,
          );
          await _waitUntil(() => runner.activeWaiterCount == 1);
          expect(executor.types, [ObsAutomationBlockType.startRecord]);
          await runner.dispose();
        }
      }
    },
  );

  test('JMA starts at M4 and KMA keeps its M5 threshold', () async {
    for (final rule in [
      (source: 'jmaEew', magnitude: 3.9, records: false),
      (source: 'jmaEew', magnitude: 4.0, records: true),
      (source: 'jmaEew', magnitude: 4.9, records: true),
      (source: 'jmaEew', magnitude: -1.0, records: false),
      (source: 'kmaEew', magnitude: 4.9, records: false),
      (source: 'kmaEew', magnitude: 5.0, records: true),
    ]) {
      input.resetForTest();
      final executor = _FakeActionExecutor();
      final runner = _runner(input, executor);
      input.emitUnifiedEvent(
        _event(
          source: rule.source,
          eventId: '${rule.source}-${rule.magnitude}',
          isEew: true,
          originTime: DateTime.utc(2026, 8, 21, 12),
          magnitude: rule.magnitude,
        ),
        ObsUnifiedEventPhase.added,
      );
      if (rule.records) {
        await _waitUntil(() => runner.activeWaiterCount == 1);
        expect(executor.types, [ObsAutomationBlockType.startRecord]);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(executor.types, isEmpty);
      }
      await runner.dispose();
    }
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
    'JMA waits for combined information, ignoring preliminary and incomplete reports',
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

      for (final title in ['震度速報', '震源に関する情報', '各地の震度に関する情報', '遠地地震に関する情報']) {
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
          titleText: '震源・震度に関する情報',
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
    },
  );

  test('JMA accepts combined P2P and WHEWS hypocenter titles', () async {
    for (final title in ['震度・震源に関する情報', '震源・震度に関する情報', '震源・震度情報']) {
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

  test(
    'recording stops only after the matched report plus 30 seconds',
    () async {
      final executor = _FakeActionExecutor();
      final delayFinished = Completer<void>();
      Duration? waited;
      final runner = _runner(
        input,
        executor,
        delay: (duration) {
          waited = duration;
          return delayFinished.future;
        },
      );
      addTearDown(runner.dispose);
      final time = DateTime.utc(2026, 8, 21, 12);
      input.emitUnifiedEvent(
        _event(
          source: 'cwaEew',
          eventId: 'cwa-delay',
          isEew: true,
          originTime: time,
          magnitude: 3,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => runner.activeWaiterCount == 1);
      input.emitUnifiedEvent(
        _event(
          source: 'cwaEqlist',
          eventId: 'cwa-information',
          isEew: false,
          originTime: time,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => waited != null);
      expect(waited, const Duration(seconds: 30));
      expect(executor.types, [ObsAutomationBlockType.startRecord]);
      delayFinished.complete();
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
    },
  );

  test(
    'legacy template upgrade preserves identity, enabled state and layout',
    () {
      final legacy = _legacyPreset(enabled: true);
      final original = jsonEncode(legacy.toJson());
      final result = upgradeBuiltInEewRecordingPresets([legacy]);
      final upgraded = result.single;
      expect(upgraded.id, legacy.id);
      expect(upgraded.enabled, isTrue);
      expect(upgraded.name, obsEewRecordingPresetName);
      expect(upgraded.stacks, hasLength(_expectedStackCount));
      for (var i = 0; i < legacy.stacks.length; i++) {
        expect(upgraded.stacks[i].id, legacy.stacks[i].id);
        expect(upgraded.stacks[i].x, legacy.stacks[i].x);
        expect(upgraded.stacks[i].y, legacy.stacks[i].y);
        expect(
          _singleBlock(
            upgraded.stacks[i],
            ObsAutomationBlockType.startRecord,
          ).id,
          _singleBlock(legacy.stacks[i], ObsAutomationBlockType.startRecord).id,
        );
        expect(
          _singleBlock(
            upgraded.stacks[i],
            ObsAutomationBlockType.wait,
          ).parameters['seconds'],
          '30',
        );
      }
      expect(jsonEncode(legacy.toJson()), original);
      expect(
        identical(upgradeBuiltInEewRecordingPresets(result), result),
        isTrue,
      );
      final ids = upgraded.stacks
          .expand((stack) => stack.blocks)
          .map((block) => block.id)
          .toList();
      expect(ids.toSet().length, ids.length);
    },
  );

  test('legacy template upgrade leaves edited user programs untouched', () {
    final legacy = _legacyPreset();
    final stack = legacy.stacks.first;
    final edited = legacy.copyWith(
      stacks: [
        stack.copyWith(
          blocks: stack.blocks
              .map(
                (block) => block.type == ObsAutomationBlockType.wait
                    ? block.copyWith(parameters: const {'seconds': '45'})
                    : block,
              )
              .toList(),
        ),
        ...legacy.stacks.skip(1),
      ],
    );
    final presets = [edited];
    expect(
      identical(upgradeBuiltInEewRecordingPresets(presets), presets),
      isTrue,
    );
    expect(isBuiltInEewRecordingPreset(edited), isTrue);
  });

  test(
    'runtime persists the legacy template upgrade before enabling it',
    () async {
      SharedPreferences.setMockInitialValues({
        obsAutomationPresetsPreferenceKey: jsonEncode(
          ObsAutomationPresetDocument(
            presets: [_legacyPreset(enabled: true)],
          ).toJson(),
        ),
      });
      final prefs = await SharedPreferences.getInstance();
      final runtime = ObsAutomationRuntimeService();
      addTearDown(() => runtime.runner.configure(const []));
      await runtime.reloadPresets(preferences: prefs);
      expect(runtime.presetErrorNotifier.value, isNull);
      expect(runtime.runner.isListening, isTrue);
      final saved = ObsAutomationPresetDocument.fromJson(
        jsonDecode(prefs.getString(obsAutomationPresetsPreferenceKey)!)
            as Map<String, dynamic>,
      );
      expect(saved.presets.single.name, obsEewRecordingPresetName);
      expect(saved.presets.single.enabled, isTrue);
      expect(saved.presets.single.stacks, hasLength(_expectedStackCount));
    },
  );

  test('previous template gains GQ without changing other rules or layout', () {
    final previous = _previousPreset(enabled: true);
    final before = previous.stacks
        .map((stack) => jsonEncode(stack.toJson()))
        .toList();
    final upgraded = upgradeBuiltInEewRecordingPresets([previous]).single;
    expect(upgraded.enabled, isTrue);
    expect(upgraded.id, previous.id);
    expect(upgraded.stacks, hasLength(_expectedStackCount));
    expect(
      upgraded.stacks
          .take(previous.stacks.length)
          .map((stack) => jsonEncode(stack.toJson()))
          .toList(),
      before,
    );
    expect(
      upgraded.stacks.where(
        (stack) =>
            _singleBlock(
              stack,
              ObsAutomationBlockType.eewAgency,
            ).parameters['value'] ==
            'globalQuake',
      ),
      AppEdition.hasGlobalQuake ? hasLength(1) : isEmpty,
    );
    final once = [upgraded];
    expect(identical(upgradeBuiltInEewRecordingPresets(once), once), isTrue);
  });

  test('customized current template is not overwritten by GQ migration', () {
    final previous = _previousPreset();
    final first = previous.stacks.first;
    final edited = previous.copyWith(
      stacks: [
        first.copyWith(
          blocks: first.blocks
              .map(
                (block) => block.type == ObsAutomationBlockType.wait
                    ? block.copyWith(parameters: const {'seconds': '45'})
                    : block,
              )
              .toList(),
        ),
        ...previous.stacks.skip(1),
      ],
    );
    final presets = [edited];
    expect(
      identical(upgradeBuiltInEewRecordingPresets(presets), presets),
      isTrue,
    );
  });

  test('GQ is absent in the public edition', () {
    var id = 0;
    final preset = buildEewRecordingPreset(
      nextId: (prefix) => '$prefix-${id++}',
    );
    expect(
      preset.stacks.any(
        (stack) =>
            _singleBlock(
              stack,
              ObsAutomationBlockType.eewAgency,
            ).parameters['value'] ==
            'globalQuake',
      ),
      AppEdition.hasGlobalQuake,
    );
  });

  test(
    'GQ starts at M6.9 on added or updated and records for one hour',
    () async {
      for (final source in ['globalQuakeEew', 'gqEew']) {
        input.resetForTest();
        final executor = _FakeActionExecutor();
        final finished = Completer<void>();
        final delays = <Duration>[];
        final runner = _runner(
          input,
          executor,
          delay: (duration) {
            delays.add(duration);
            return finished.future;
          },
        );
        final time = DateTime.utc(2026, 8, 21, 12);
        void emit(double magnitude, ObsUnifiedEventPhase phase, {String? id}) =>
            input.emitUnifiedEvent(
              _event(
                source: source,
                eventId: id ?? 'gq-threshold',
                isEew: true,
                originTime: time,
                magnitude: magnitude,
              ),
              phase,
            );
        emit(6.8, ObsUnifiedEventPhase.added);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(executor.types, isEmpty);
        emit(6.9, ObsUnifiedEventPhase.updated);
        await _waitUntil(() => delays.isNotEmpty);
        expect(delays, [const Duration(hours: 1)]);
        expect(executor.types, [ObsAutomationBlockType.startRecord]);
        emit(7.2, ObsUnifiedEventPhase.updated);
        emit(7.2, ObsUnifiedEventPhase.added);
        emit(7.2, ObsUnifiedEventPhase.canceled, id: 'gq-canceled');
        emit(7.2, ObsUnifiedEventPhase.removed, id: 'gq-removed');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(delays, hasLength(1));
        expect(executor.types, [ObsAutomationBlockType.startRecord]);
        finished.complete();
        await _waitUntil(() => executor.types.length == 2);
        expect(executor.types.last, ObsAutomationBlockType.stopRecord);
        emit(7.3, ObsUnifiedEventPhase.updated);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(delays, hasLength(1));
        expect(executor.types, hasLength(2));
        await runner.dispose();
      }
    },
    skip: !AppEdition.hasGlobalQuake,
  );

  test(
    'distinct GQ events share recording until the last hour ends',
    () async {
      final executor = _FakeActionExecutor();
      final delays = <Completer<void>>[];
      final runner = _runner(
        input,
        executor,
        delay: (duration) {
          expect(duration, const Duration(hours: 1));
          final delay = Completer<void>();
          delays.add(delay);
          return delay.future;
        },
      );
      addTearDown(runner.dispose);
      for (final id in ['gq-a', 'gq-b']) {
        input.emitUnifiedEvent(
          _event(
            source: 'globalQuakeEew',
            eventId: id,
            isEew: true,
            originTime: DateTime.utc(2026, 8, 21, 12),
            magnitude: 7,
          ),
          ObsUnifiedEventPhase.added,
        );
      }
      await _waitUntil(() => delays.length == 2);
      expect(executor.types, [ObsAutomationBlockType.startRecord]);
      delays.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executor.types, [ObsAutomationBlockType.startRecord]);
      delays.last.complete();
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
    },
    skip: !AppEdition.hasGlobalQuake,
  );

  test(
    'GQ and domestic EEW both hold recording until their own finish',
    () async {
      for (final gqFinishesFirst in [true, false]) {
        input.resetForTest();
        final executor = _FakeActionExecutor();
        final hour = Completer<void>();
        final tail = Completer<void>();
        var waitingHour = false;
        var waitingTail = false;
        final runner = _runner(
          input,
          executor,
          delay: (duration) {
            if (duration == const Duration(hours: 1)) {
              waitingHour = true;
              return hour.future;
            }
            expect(duration, const Duration(seconds: 30));
            waitingTail = true;
            return tail.future;
          },
        );
        final time = DateTime.utc(2026, 8, 21, 12);
        input.emitUnifiedEvent(
          _event(
            source: 'globalQuakeEew',
            eventId: 'gq-overlap',
            isEew: true,
            originTime: time,
            magnitude: 6.9,
          ),
          ObsUnifiedEventPhase.added,
        );
        input.emitUnifiedEvent(
          _event(
            source: 'ceaEew',
            eventId: 'cea-overlap',
            isEew: true,
            originTime: time,
            magnitude: 3,
          ),
          ObsUnifiedEventPhase.added,
        );
        await _waitUntil(() => waitingHour && runner.activeWaiterCount == 1);
        input.emitUnifiedEvent(
          _event(
            source: 'cencEqlist',
            eventId: 'cenc-overlap',
            isEew: false,
            originTime: time,
            reportNumText: '正式测定',
          ),
          ObsUnifiedEventPhase.added,
        );
        await _waitUntil(() => waitingTail);
        expect(executor.types, [ObsAutomationBlockType.startRecord]);
        (gqFinishesFirst ? hour : tail).complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(executor.types, [ObsAutomationBlockType.startRecord]);
        (gqFinishesFirst ? tail : hour).complete();
        await _waitUntil(() => executor.types.length == 2);
        expect(executor.types.last, ObsAutomationBlockType.stopRecord);
        await runner.dispose();
      }
    },
    skip: !AppEdition.hasGlobalQuake,
  );

  test(
    'disabled GQ delay cannot stop a later recording',
    () async {
      final executor = _FakeActionExecutor();
      final oldHour = Completer<void>();
      final newHour = Completer<void>();
      var delays = 0;
      final runner = _runner(
        input,
        executor,
        delay: (_) {
          return delays++ == 0 ? oldHour.future : newHour.future;
        },
      );
      addTearDown(runner.dispose);
      final time = DateTime.utc(2026, 8, 21, 12);
      input.emitUnifiedEvent(
        _event(
          source: 'globalQuakeEew',
          eventId: 'old-gq',
          isEew: true,
          originTime: time,
          magnitude: 7,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => delays == 1);
      runner.configure(const []);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var id = 0;
      runner.configure([
        buildEewRecordingPreset(
          nextId: (prefix) => '$prefix-${id++}',
          enabled: true,
        ),
      ]);
      input.emitUnifiedEvent(
        _event(
          source: 'globalQuakeEew',
          eventId: 'new-gq',
          isEew: true,
          originTime: time,
          magnitude: 7,
        ),
        ObsUnifiedEventPhase.added,
      );
      await _waitUntil(() => delays == 2);
      oldHour.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executor.types, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.startRecord,
      ]);
      newHour.complete();
      await _waitUntil(() => executor.types.length == 3);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
    },
    skip: !AppEdition.hasGlobalQuake,
  );

  test(
    'active GQ timers remain deduplicated beyond the completed-key cache',
    () async {
      final executor = _FakeActionExecutor();
      final delays = <Completer<void>>[];
      final runner = _runner(
        input,
        executor,
        delay: (_) {
          final delay = Completer<void>();
          delays.add(delay);
          return delay.future;
        },
      );
      addTearDown(runner.dispose);
      final time = DateTime.utc(2026, 8, 21, 12);
      for (var i = 0; i < 513; i++) {
        input.emitUnifiedEvent(
          _event(
            source: 'globalQuakeEew',
            eventId: 'gq-$i',
            isEew: true,
            originTime: time,
            magnitude: 7,
          ),
          ObsUnifiedEventPhase.added,
        );
      }
      await _waitUntil(() => delays.length == 513);
      input.emitUnifiedEvent(
        _event(
          source: 'globalQuakeEew',
          eventId: 'gq-0',
          isEew: true,
          originTime: time,
          magnitude: 7.1,
        ),
        ObsUnifiedEventPhase.updated,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delays, hasLength(513));
      for (final delay in delays) {
        delay.complete();
      }
      await _waitUntil(() => executor.types.length == 2);
      expect(executor.types, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
      ]);
    },
    skip: !AppEdition.hasGlobalQuake,
  );

  test(
    'failed GQ start can retry on a later qualifying update',
    () async {
      final executor = _FakeActionExecutor()..failNextStart = true;
      final hour = Completer<void>();
      var waiting = false;
      final runner = _runner(
        input,
        executor,
        delay: (_) {
          waiting = true;
          return hour.future;
        },
      );
      addTearDown(runner.dispose);
      final time = DateTime.utc(2026, 8, 21, 12);
      void emit(ObsUnifiedEventPhase phase) => input.emitUnifiedEvent(
        _event(
          source: 'globalQuakeEew',
          eventId: 'gq-retry',
          isEew: true,
          originTime: time,
          magnitude: 6.9,
        ),
        phase,
      );
      emit(ObsUnifiedEventPhase.added);
      await _waitUntil(() => runner.lastError != null);
      expect(waiting, isFalse);
      emit(ObsUnifiedEventPhase.updated);
      await _waitUntil(() => waiting);
      expect(executor.types, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.startRecord,
      ]);
      hour.complete();
      await _waitUntil(() => executor.types.length == 3);
      expect(executor.types.last, ObsAutomationBlockType.stopRecord);
    },
    skip: !AppEdition.hasGlobalQuake,
  );
}

int get _expectedStackCount =>
    7 + (AppEdition.hasIcl ? 1 : 0) + (AppEdition.hasGlobalQuake ? 1 : 0);

ObsAutomationPreset _previousPreset({bool enabled = false}) {
  var sequence = 0;
  final current = buildEewRecordingPreset(
    nextId: (prefix) => '$prefix-${sequence++}',
    enabled: enabled,
  );
  return current.copyWith(
    stacks: current.stacks
        .where(
          (stack) =>
              _singleBlock(
                stack,
                ObsAutomationBlockType.eewAgency,
              ).parameters['value'] !=
              'globalQuake',
        )
        .toList(),
  );
}

ObsAutomationPreset _legacyPreset({bool enabled = false}) {
  var sequence = 0;
  final next = buildEewRecordingPreset(
    nextId: (prefix) => '$prefix-${sequence++}',
    enabled: enabled,
  );
  return next.copyWith(
    name: 'EEW M5 分机构自动录制',
    stacks: next.stacks
        .where(
          (stack) =>
              _singleBlock(
                    stack,
                    ObsAutomationBlockType.eewAgency,
                  ).parameters['value'] !=
                  'icl' &&
              _singleBlock(
                    stack,
                    ObsAutomationBlockType.eewAgency,
                  ).parameters['value'] !=
                  'globalQuake',
        )
        .map((stack) {
          final blocks = stack.blocks
              .where(
                (block) =>
                    block.type != ObsAutomationBlockType.magnitude &&
                    !(block.type ==
                            ObsAutomationBlockType.inputFieldCondition &&
                        block.parameters['value'] == '震度'),
              )
              .map(
                (block) => block.type == ObsAutomationBlockType.wait
                    ? block.copyWith(parameters: const {'seconds': '20'})
                    : block,
              )
              .toList();
          blocks.insert(
            3,
            ObsAutomationBlock(
              id: 'legacy-mag-${sequence++}',
              type: ObsAutomationBlockType.magnitude,
              parameters: const {
                'operator': 'greaterThanOrEqual',
                'value': '5.0',
              },
            ),
          );
          return stack.copyWith(
            x: stack.x + 13,
            y: stack.y + 17,
            blocks: blocks,
          );
        })
        .toList(),
  );
}

ObsAutomationBlock _singleBlock(
  ObsAutomationStack stack,
  ObsAutomationBlockType type,
) {
  return stack.blocks.singleWhere((block) => block.type == type);
}

ObsAutomationRunner _runner(
  ObsAutomationInputService input,
  _FakeActionExecutor executor, {
  Future<void> Function(Duration duration)? delay,
}) {
  var sequence = 0;
  final runner = ObsAutomationRunner(
    inputService: input,
    actionExecutor: executor,
    delay: delay ?? (_) async {},
  );
  runner.configure([
    buildEewRecordingPreset(
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
  bool failNextStart = false;

  @override
  Future<void> execute(ObsAutomationBlock block) async {
    types.add(block.type);
    if (block.type == ObsAutomationBlockType.startRecord && failNextStart) {
      failNextStart = false;
      throw StateError('recording start failed');
    }
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
