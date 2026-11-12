import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/obs_automation_runner.dart';
import 'package:flutterrhythmquake/services/obs_automation_condition_evaluator.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/widgets/ui/obs_recording_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var sequence = 0;
  String id(String prefix) => '$prefix-form-${sequence++}';
  final input = ObsAutomationInputService();
  setUp(input.resetForTest);
  tearDown(input.resetForTest);
  ObsAutomationStack informationRule() => obsBuildCencInformationRule(
    'form',
    id,
    maxSeconds: '300',
    maxDistanceKm: '300',
    timeoutSeconds: '3600',
  );

  test(
    'existing recording rules retain their original defaults and recognized end conditions',
    () {
      final preset = buildEewRecordingPreset(nextId: id);
      final original = preset.toJson();
      for (final rule in preset.stacks) {
        expect(
          obsRecordingCurrentEnd(rule),
          isNotNull,
          reason: obsRecordingAgency(rule),
        );
        final available = obsRecordingAvailableEnds(rule, expanded: false);
        expect(
          available.map((choice) => choice.id),
          contains(obsRecordingCurrentEnd(rule)!.id),
        );
      }
      expect(preset.toJson(), original);
    },
  );

  test(
    'SASMEX form choices match unchanged source data and keep original start and stop behavior',
    () {
      final preset = buildEewRecordingPreset(nextId: id);
      final rule = preset.stacks.singleWhere(obsRecordingUsesAlertTrigger);
      final original = rule.toJson();
      final frame =
          jsonDecode(
                File(
                  'test/fixtures/sasmex_firestore_20261017.relay.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      final unchangedFrame = jsonEncode(frame);
      final detection = SasmexService.parseRelayFrame(frame)!;
      // Explicit Severe protocol input, not an observed warning or a rewrite
      // of the captured original frame above.
      final warning = SasmexService.parseRelayFrame({
        'type': 'update',
        'Data': {
          'id': 'unit-warning',
          'epochMs': 1791381600000,
          'severity': 'Severe',
        },
      })!;
      const evaluator = ObsAutomationConditionEvaluator();
      expect(obsRecordingAlertTrigger(rule), 'all');
      for (final choice in obsRecordingAlertTriggers.keys) {
        final changed = obsRecordingChooseAlertTrigger(rule, choice, id);
        final prefix = changed.blocks
            .takeWhile((b) => b.type != ObsAutomationBlockType.startRecord)
            .toList();
        for (final event in [detection, warning]) {
          expect(
            evaluator.matchesBlocks(
              prefix,
              ObsAutomationInputEvent.unified(
                phase: ObsUnifiedEventPhase.added,
                event: event,
              ),
            ),
            choice == 'all' || (choice == 'warning') == event.isWarn,
            reason: '$choice / ${event.titleText}',
          );
        }
        expect(
          changed.blocks.skip(prefix.length).map((b) => b.toJson()).toList(),
          rule.blocks
              .skipWhile((b) => b.type != ObsAutomationBlockType.startRecord)
              .map((b) => b.toJson())
              .toList(),
        );
        expect(
          ObsAutomationStack.fromJson(changed.toJson()).toJson(),
          changed.toJson(),
        );
      }
      expect(
        obsRecordingChooseAlertTrigger(rule, 'all', id).toJson(),
        original,
      );
      final ordinary = preset.stacks.first;
      expect(
        identical(
          obsRecordingChooseAlertTrigger(ordinary, 'warning', id),
          ordinary,
        ),
        isTrue,
      );
      expect(jsonEncode(frame), unchangedFrame);
      expect(rule.toJson(), original);
    },
  );

  test(
    'previous default thresholds migrate to GQ M5 and other EEW zero without changing CENC or stop flows',
    () {
      final generated = buildEewRecordingPreset(nextId: id);
      // This fixture represents the actual previous one-hour defaults.
      final current = generated.copyWith(
        stacks: [
          for (final rule in generated.stacks)
            if (obsRecordingAgency(rule) != 'shakeAlert')
              rule.copyWith(
                blocks: [
                  for (final block in rule.blocks)
                    if (block.type ==
                        ObsAutomationBlockType.waitForUnifiedEvent)
                      block.copyWith(
                        parameters: {
                          ...block.parameters,
                          'timeoutSeconds': '3600',
                        },
                      )
                    else if (obsRecordingAgency(rule) == 'globalQuake' &&
                        block.type == ObsAutomationBlockType.wait)
                      block.copyWith(
                        parameters: {...block.parameters, 'seconds': '3600'},
                      )
                    else
                      block,
                ],
              ),
        ],
      );
      final old = current.copyWith(
        stacks: [
          for (final rule in current.stacks)
            if (const {
              'jma',
              'kma',
              'globalQuake',
            }.contains(obsRecordingAgency(rule)))
              rule.copyWith(
                blocks:
                    [
                      for (final block in rule.blocks)
                        if (block.type != ObsAutomationBlockType.magnitude)
                          if (block.type ==
                                  ObsAutomationBlockType.inputFieldCondition &&
                              block.parameters['value'] == '各地')
                            block.copyWith(
                              parameters: {...block.parameters, 'value': '震源'},
                            )
                          else
                            block,
                    ]..insert(
                      rule.blocks.indexWhere(
                            (b) => b.type == ObsAutomationBlockType.eewAgency,
                          ) +
                          1,
                      ObsAutomationBlock(
                        id: id('old-mag'),
                        type: ObsAutomationBlockType.magnitude,
                        parameters: {
                          'operator': 'greaterThanOrEqual',
                          'value': switch (obsRecordingAgency(rule)) {
                            'jma' => '4.0',
                            'kma' => '5.0',
                            _ => '6.9',
                          },
                        },
                      ),
                    ),
              )
            else
              rule,
          obsBuildCencInformationRule(
            current.id,
            id,
            maxSeconds: '300',
            maxDistanceKm: '300',
            timeoutSeconds: '3600',
          ),
        ],
      );
      // The previous JMA/KMA template stores magnitude before agency.
      final previous = old.copyWith(
        stacks: [
          for (final rule in old.stacks)
            if (const {'jma', 'kma'}.contains(obsRecordingAgency(rule)))
              rule.copyWith(
                blocks: [...rule.blocks]
                  ..insert(
                    3,
                    rule.blocks.singleWhere(
                      (b) => b.type == ObsAutomationBlockType.magnitude,
                    ),
                  )
                  ..removeAt(5),
              )
            else
              rule,
        ],
      );
      final before = jsonEncode(previous.toJson());
      final upgraded = upgradeBuiltInEewRecordingPresets([previous]).single;
      expect(identical(upgraded, previous), isFalse);
      for (var i = 0; i < current.stacks.length; i++) {
        final rule = upgraded.stacks[i];
        final magnitudes = rule.blocks.where(
          (b) => b.type == ObsAutomationBlockType.magnitude,
        );
        if (obsRecordingAgency(rule) == 'globalQuake') {
          expect(magnitudes.single.parameters['value'], '5.0');
        } else {
          expect(magnitudes, isEmpty);
        }
        final original = previous.stacks[i];
        expect(rule.id, original.id);
        expect(
          rule.blocks
              .skipWhile((b) => b.type != ObsAutomationBlockType.startRecord)
              .map((b) => b.toJson())
              .toList(),
          original.blocks
              .skipWhile((b) => b.type != ObsAutomationBlockType.startRecord)
              .map(
                (b) =>
                    obsRecordingAgency(original) == 'jma' &&
                        b.type == ObsAutomationBlockType.inputFieldCondition &&
                        b.parameters['value'] == '震源'
                    ? b
                          .copyWith(
                            parameters: {...b.parameters, 'value': '各地'},
                          )
                          .toJson()
                    : b.toJson(),
              )
              .toList(),
        );
      }
      final cenc = upgraded.stacks.singleWhere(obsIsCencInformationRule);
      expect(cenc.toJson(), previous.stacks.last.toJson());
      expect(
        cenc.blocks
            .singleWhere((b) => b.type == ObsAutomationBlockType.magnitude)
            .parameters['value'],
        '5.0',
      );
      final once = [upgraded];
      expect(identical(upgradeBuiltInEewRecordingPresets(once), once), isTrue);
      expect(jsonEncode(previous.toJson()), before);
    },
  );

  test(
    'end source mapping preserves the trigger, same earthquake check, delay and stop operations',
    () {
      final original = informationRule();
      final changed = obsRecordingChooseEnd(
        original,
        obsRecordingEndChoices.singleWhere((choice) => choice.id == 'cencCmt'),
        id,
        maxSeconds: '300',
        maxDistanceKm: '300',
      );
      final firstWait = original.blocks.indexWhere(
        (block) => block.type == ObsAutomationBlockType.waitForUnifiedEvent,
      );
      expect(
        changed.blocks
            .take(firstWait + 1)
            .map((block) => block.toJson())
            .toList(),
        original.blocks
            .take(firstWait + 1)
            .map((block) => block.toJson())
            .toList(),
      );
      for (final type in [
        ObsAutomationBlockType.sameEarthquakeAsVariable,
        ObsAutomationBlockType.wait,
        ObsAutomationBlockType.stopRecord,
        ObsAutomationBlockType.stopScript,
      ]) {
        expect(
          changed.blocks.singleWhere((block) => block.type == type).toJson(),
          original.blocks.singleWhere((block) => block.type == type).toJson(),
        );
      }
      final zeroDelay = obsRecordingSetDelay(changed, '0', id);
      expect(
        zeroDelay.blocks.where(
          (block) => block.type == ObsAutomationBlockType.wait,
        ),
        isEmpty,
      );
      expect(obsRecordingDelay(zeroDelay), '0');
    },
  );

  test(
    'CENC automatic information triggers at M5, deduplicates updates and stops on matching reviewed information',
    () async {
      final executor = _Actions();
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
        delay: (_) async {},
      );
      addTearDown(runner.dispose);
      final rule = informationRule().copyWith(enabled: true);
      runner.configure([
        ObsAutomationPreset(
          id: 'information',
          name: 'information',
          enabled: true,
          stacks: [rule],
        ),
      ]);
      final origin = DateTime.utc(2026, 8, 20, 12);
      for (final event in [
        _event('ceaEew', 'eew', origin, isEew: true),
        _event('cencEqlist', 'low', origin, review: '自动测定', magnitude: 4.9),
        _event('cencEqlist', 'formal-first', origin, review: '正式测定'),
      ]) {
        input.emitUnifiedEvent(event, ObsUnifiedEventPhase.added);
      }
      await _settle();
      expect(executor.calls, isEmpty);
      final automatic = _event(
        'cencEqlist',
        'qualifying',
        origin,
        review: '自动测定',
      );
      input.emitUnifiedEvent(automatic, ObsUnifiedEventPhase.updated);
      await _until(() => runner.activeWaiterCount == 1);
      input.emitUnifiedEvent(
        automatic.copyWith(magnitude: 6),
        ObsUnifiedEventPhase.updated,
      );
      await _settle();
      expect(executor.calls, [ObsAutomationBlockType.startRecord]);
      expect(runner.activeWaiterCount, 1);
      input.emitUnifiedEvent(
        _event(
          'cencEqlist',
          'unrelated',
          origin.add(const Duration(hours: 1)),
          review: '正式测定',
        ),
        ObsUnifiedEventPhase.added,
      );
      await _settle();
      expect(executor.calls, [ObsAutomationBlockType.startRecord]);
      input.emitUnifiedEvent(
        _event('cencEqlist', 'matching', origin, review: '正式测定'),
        ObsUnifiedEventPhase.updated,
      );
      await _until(() => executor.calls.length == 2);
      expect(executor.calls, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
      ]);
    },
  );

  test(
    'information and EEW share recording: ending one and saving UI settings cannot stop the other',
    () async {
      final executor = _Actions();
      final delays = <int, Completer<void>>{};
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: executor,
        delay: (duration) =>
            (delays[duration.inSeconds] = Completer<void>()).future,
      );
      addTearDown(runner.dispose);
      final cea = buildEewRecordingPreset(
        nextId: id,
      ).stacks.first.copyWith(enabled: true);
      final info = informationRule().copyWith(enabled: true);
      final preset = ObsAutomationPreset(
        id: 'ownership',
        name: 'ownership',
        enabled: true,
        stacks: [cea, info],
      );
      runner.configure([preset]);
      final originA = DateTime.utc(2026, 8, 20, 12);
      final originB = originA.add(const Duration(hours: 1));
      input.emitUnifiedEvent(
        _event('ceaEew', 'B-eew', originB, isEew: true),
        ObsUnifiedEventPhase.added,
      );
      input.emitUnifiedEvent(
        _event('cencEqlist', 'A-auto', originA, review: '自动测定'),
        ObsUnifiedEventPhase.added,
      );
      await _until(() => runner.activeWaiterCount == 2);
      expect(executor.calls, [ObsAutomationBlockType.startRecord]);
      input.emitUnifiedEvent(
        _event('cencEqlist', 'A-reviewed', originA, review: '正式测定'),
        ObsUnifiedEventPhase.updated,
      );
      await _until(() => delays.containsKey(20));
      delays[20]!.complete();
      await _settle();
      expect(executor.calls, [ObsAutomationBlockType.startRecord]);
      // A form selection/reload affects future executions; the B recording's
      // existing stop condition and recording ownership must remain intact.
      final modified = obsRecordingChooseEnd(
        cea,
        obsRecordingEndChoices.singleWhere(
          (choice) => choice.id == 'cenc-automatic',
        ),
        id,
        maxSeconds: '300',
        maxDistanceKm: '300',
      );
      runner.configure([
        preset.copyWith(stacks: [modified, info]),
      ]);
      input.emitUnifiedEvent(
        _event('cencEqlist', 'B-reviewed', originB, review: '正式测定'),
        ObsUnifiedEventPhase.updated,
      );
      await _until(() => delays.containsKey(30));
      expect(executor.calls, [ObsAutomationBlockType.startRecord]);
      delays[30]!.complete();
      await _until(() => executor.calls.length == 2);
      expect(executor.calls, [
        ObsAutomationBlockType.startRecord,
        ObsAutomationBlockType.stopRecord,
      ]);
      expect(runner.activeWaiterCount, 0);
    },
  );
}

class _Actions implements ObsAutomationActionExecutor {
  final calls = <ObsAutomationBlockType>[];
  @override
  Future<void> execute(ObsAutomationBlock block) async {
    calls.add(block.type);
  }
}

UnifiedQuakeData _event(
  String source,
  String eventId,
  DateTime origin, {
  bool isEew = false,
  String review = '',
  double magnitude = 5.5,
}) => UnifiedQuakeData(
  source: source,
  origin: 0,
  eventId: eventId,
  isEew: isEew,
  timeZone: 0,
  titleText: review,
  reportNumText: review,
  useShindo: false,
  maxIntensity: '5',
  className: 'yellow',
  hypocenter: 'fixture',
  originTime: origin,
  magnitude: magnitude,
  lat: 31.2,
  lng: 103.8,
  depth: 10,
);
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
