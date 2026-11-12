import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/obs_automation_condition_evaluator.dart';
import 'package:flutterrhythmquake/services/obs_automation_runner.dart';
import 'package:flutterrhythmquake/services/native_obs_automation_policy.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/ui/obs_recording_form.dart';

List<TsunamiMessage> originals() {
  final frames =
      jsonDecode(
            File(
              'test/fixtures/tsunami_live_20261024/frame_000.original',
            ).readAsStringSync(encoding: utf8),
          )
          as List;
  return [
    for (final f in frames.whereType<Map>())
      if (f['source'] == 'tsunami')
        TsunamiMessage.parseNmefcTsunami(
          Map<String, dynamic>.from(f['Data'] as Map),
        )
      else if (f['source'] == 'jma_tsunami')
        TsunamiMessage.parseWhewsJmaTsunami(
          Map<String, dynamic>.from(f['Data'] as Map),
        )
      else if (const {
        'cat_tsunami',
        'cwa_tsunami',
        'ptwc',
        'ntwc',
        'incois',
      }.contains(f['source']))
        TsunamiMessage.parseInternationalTsunami(
          TsunamiSource.values.byName(
            (f['source'] as String).replaceFirst('_tsunami', ''),
          ),
          Map<String, dynamic>.from(f['Data'] as Map),
        ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final input = ObsAutomationInputService();
  var seq = 0;
  String id(String prefix) => '$prefix-special-${seq++}';
  setUp(() async {
    SharedPreferences.setMockInitialValues({'tts_enabled': false});
    input.resetForTest();
    SoundEffectService().enabled = false;
    await TtsService().configure(enabled: false, persist: false);
  });
  tearDown(input.resetForTest);

  ObsAutomationStack selected(String option) => obsRecordingChooseEnd(
    buildEewRecordingPreset(nextId: id).stacks.first,
    obsRecordingEndChoices.singleWhere((choice) => choice.id == option),
    id,
    maxSeconds: '300',
    maxDistanceKm: '300',
  );

  test(
    'both LPGM source paths match the saved selector; ordinary JMA and other sources do not',
    () {
      final source = selected(
        'jma-lpgm',
      ).blocks.singleWhere((b) => b.type == ObsAutomationBlockType.source);
      const evaluator = ObsAutomationConditionEvaluator();
      for (final metadata in [
        ('jmaLpgm', false, true),
        ('jmaEqlist', true, true),
        ('jmaEqlist', false, false),
        ('cwaEqlist', false, false),
      ]) {
        // Metadata-only contract objects: no invented earthquake measurements.
        final event = UnifiedQuakeData(
          source: metadata.$1,
          origin: 0,
          eventId: 'metadata-contract',
          isEew: false,
          timeZone: 9,
          titleText: '',
          reportNumText: '',
          useShindo: false,
          maxIntensity: '-',
          className: 'gray',
          hypocenter: '',
          isJmaLpgm: metadata.$2,
        );
        expect(
          evaluator.matchesConditions(
            [source],
            ObsAutomationInputEvent.unified(
              phase: ObsUnifiedEventPhase.added,
              event: event,
            ),
          ),
          metadata.$3,
        );
        expect(event.source, metadata.$1);
      }
    },
  );

  test(
    'original tsunami receipts reach OBS only, preserve payload/time/coordinates, and skip initial snapshots',
    () async {
      final captured = <ObsAutomationInputEvent>[];
      final baseline = QuakeProvider(startCatalogServices: false);
      addTearDown(baseline.dispose);
      final messages = originals();
      for (final message in messages) {
        baseline.handleTsunamiEventForTest(message);
      }
      await baseline.internationalTsunamiListReadyForTest;
      await baseline.jmaTsunamiListReadyForTest;
      final beforeLists = jsonEncode([
        for (final g in baseline.internationalTsunamiListenable.value)
          g.toMap(),
      ]);
      final sub = input.events.listen(captured.add);
      addTearDown(sub.cancel);
      final provider = QuakeProvider(startCatalogServices: false);
      addTearDown(provider.dispose);
      expect(messages, hasLength(7));
      for (final message in messages) {
        final before = jsonEncode(message.toMap());
        final count = captured.length;
        provider.handleTsunamiEventForTest(message);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(captured.length, count + 1);
        final delivery = captured.last;
        expect(delivery.tsunamiEvent!.sourcePayload, message.sourcePayload);
        expect(delivery.unifiedEvent!.lat, message.epicenterLat);
        expect(delivery.unifiedEvent!.lng, message.epicenterLng);
        expect(
          const ObsAutomationConditionEvaluator().readInputField(
            delivery,
            'eventType',
          ),
          'tsunami',
        );
        expect(jsonEncode(message.toMap()), before);
        expect(provider.unifiedEvents, isEmpty);
        input.emitTsunamiEvent(message.copyWith(isInitialSnapshot: true));
        expect(captured.length, count + 1);
      }
      await provider.internationalTsunamiListReadyForTest;
      await provider.jmaTsunamiListReadyForTest;
      expect(
        jsonEncode([
          for (final g in provider.internationalTsunamiListenable.value)
            g.toMap(),
        ]),
        beforeLists,
      );
      expect(
        jsonEncode(provider.nmefcTsunami!.toMap()),
        jsonEncode(baseline.nmefcTsunami!.toMap()),
      );
      expect(
        jsonEncode(provider.catTsunami!.toMap()),
        jsonEncode(baseline.catTsunami!.toMap()),
      );
      expect(
        jsonEncode(provider.cwaTsunami!.toMap()),
        jsonEncode(baseline.cwaTsunami!.toMap()),
      );
      expect(
        jsonEncode(provider.jmaTsunami!.toMap()),
        jsonEncode(baseline.jmaTsunami!.toMap()),
      );
      expect(
        jsonEncode(provider.ptwcTsunami!.toMap()),
        jsonEncode(baseline.ptwcTsunami!.toMap()),
      );
      expect(
        jsonEncode(provider.ntwcTsunami!.toMap()),
        jsonEncode(baseline.ntwcTsunami!.toMap()),
      );
      expect(
        jsonEncode(provider.incoisTsunami!.toMap()),
        jsonEncode(baseline.incoisTsunami!.toMap()),
      );
      expect(
        jsonEncode([
          for (final g in provider.jmaTsunamiListenable.value) g.toMap(),
        ]),
        jsonEncode([
          for (final g in baseline.jmaTsunamiListenable.value) g.toMap(),
        ]),
      );
      expect(NativeObsAutomationPolicy.outputs, 0);
    },
  );

  test(
    'tsunami completes only its same-earthquake waiter and cannot start recording or stop another owner',
    () async {
      final message = originals().firstWhere(
        (m) =>
            m.originTime.isNotEmpty &&
            m.epicenterLat != null &&
            m.epicenterLng != null,
      );
      final bridge = ObsAutomationInputEvent.tsunami(message).unifiedEvent!;
      expect(bridge.originTime, isNotNull);
      final actions = _Actions();
      final finish = Completer<void>();
      final delays = <Duration>[];
      final runner = ObsAutomationRunner(
        inputService: input,
        actionExecutor: actions,
        delay: (duration) {
          delays.add(duration);
          return finish.future;
        },
      );
      addTearDown(runner.dispose);
      final tsunamiRule = selected('tsunami');
      final ordinary = buildEewRecordingPreset(nextId: id).stacks.first;
      // Explicit runner trigger contract, not a claimed historical EEW receipt.
      UnifiedQuakeData trigger(String key, DateTime origin) => UnifiedQuakeData(
        source: 'ceaEew',
        origin: 0,
        eventId: key,
        isEew: true,
        timeZone: 0,
        titleText: '',
        reportNumText: '',
        useShindo: false,
        maxIntensity: '-',
        className: 'gray',
        hypocenter: '',
        originTime: origin,
        lat: bridge.lat,
        lng: bridge.lng,
        magnitude: 5,
      );
      runner.configure([
        ObsAutomationPreset(
          id: 'owners',
          name: 'owners',
          enabled: true,
          stacks: [tsunamiRule, ordinary],
        ),
      ]);
      input.emitUnifiedEvent(
        trigger('owner', bridge.originTime!),
        ObsUnifiedEventPhase.added,
      );
      await until(() => runner.activeWaiterCount == 2);
      // Unmodified CAT bulletin is a different earthquake: it must not finish
      // either recording owner or start the finishing delay.
      input.emitTsunamiEvent(
        originals().singleWhere((m) => m.source == TsunamiSource.cat),
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(runner.activeWaiterCount, 2);
      expect(delays, isEmpty);
      final missingOrigin = originals().singleWhere(
        (m) => m.source == TsunamiSource.jma,
      );
      expect(missingOrigin.originTime, isEmpty);
      input.emitTsunamiEvent(missingOrigin);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(runner.activeWaiterCount, 2);
      expect(delays, isEmpty);
      input.emitTsunamiEvent(message);
      await until(() => delays.isNotEmpty);
      expect(delays, [const Duration(seconds: 30)]);
      expect(actions.calls, [ObsAutomationBlockType.startRecord]);
      finish.complete();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(actions.calls, [ObsAutomationBlockType.startRecord]);
      expect(runner.activeWaiterCount, 1);
      // Even a deliberately generic information start rule must not be started
      // by this end-only receipt, or it would change unrelated trigger behavior.
      runner.configure([
        ObsAutomationPreset(
          id: 'generic',
          name: 'generic',
          enabled: true,
          stacks: [
            ObsAutomationStack(
              id: 'generic',
              x: 0,
              y: 0,
              blocks: [
                ObsAutomationBlock(
                  id: 'input',
                  type: ObsAutomationBlockType.unifiedEvent,
                ),
                ObsAutomationBlock(
                  id: 'info',
                  type: ObsAutomationBlockType.isInformation,
                ),
                ObsAutomationBlock(
                  id: 'start',
                  type: ObsAutomationBlockType.startRecord,
                ),
              ],
            ),
          ],
        ),
      ]);
      input.emitTsunamiEvent(message);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(actions.calls, [ObsAutomationBlockType.startRecord]);
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

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
