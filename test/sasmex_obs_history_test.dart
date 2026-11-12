import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/obs_automation_builtin_presets.dart';
import 'package:flutterrhythmquake/models/obs_automation_preset.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/history_storage.dart';
import 'package:flutterrhythmquake/services/obs_automation_condition_evaluator.dart';
import 'package:flutterrhythmquake/services/obs_automation_input_service.dart';
import 'package:flutterrhythmquake/services/obs_automation_runner.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/unified_ui_fonts.dart';

Map<String, dynamic> _frame() =>
    jsonDecode(
          File(
            'test/fixtures/sasmex_firestore_20261017.relay.json',
          ).readAsStringSync(encoding: utf8),
        )
        as Map<String, dynamic>;
UnifiedQuakeData _event() => SasmexService.parseRelayFrame(_frame())!;
EewEventGroup _group() {
  final e = _event();
  return EewEventGroup(
    eventId: e.eventId,
    reports: [e],
    firstArrivedAt: DateTime.utc(2026, 10, 17, 9, 36, 58),
  );
}

class _Executor implements ObsAutomationActionExecutor {
  final actions = <ObsAutomationBlockType>[];
  @override
  Future<void> execute(ObsAutomationBlock block) async =>
      actions.add(block.type);
}

class _Storage implements HistoryStorage, HistorySnapshotStorage {
  _Storage(this.delegate);
  final HistoryStorage delegate;
  int bodyReads = 0;
  @override
  bool get separate => delegate.separate;
  @override
  Future<Object?> read(String key) {
    if (key.contains('_event_')) bodyReads++;
    return delegate.read(key);
  }

  @override
  Future<bool> write(String key, Object value) => delegate.write(key, value);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<Map<String, dynamic>?> readSnapshot(String key) =>
      (delegate as HistorySnapshotStorage).readSnapshot(key);
  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) => (delegate as HistorySnapshotStorage).writeWithSnapshot(
    key,
    value,
    snapshot,
  );
}

class _HistoryProvider extends QuakeProvider {
  _HistoryProvider(this.groups);
  final List<EewEventGroup> groups;
  @override
  List<EewEventGroup> get eewHistory => groups;
}

Future<void> _wait(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), true);
}

// Explicit OBS condition unit inputs, not observed SSN deliveries. The SASNO
// fixture and its original timestamps are never rewritten for these tests.
UnifiedQuakeData _ssnUnit({
  String source = 'whews_ssn',
  int second = 50,
  double latitude = 17.64686,
}) => UnifiedQuakeData(
  source: source,
  origin: 3,
  eventId: 'unit-ssn-$source-$second-$latitude',
  isEew: false,
  timeZone: 8,
  titleText: 'SSN 地震信息',
  reportNumText: '',
  useShindo: false,
  maxIntensity: '-',
  className: 'gray',
  hypocenter: '',
  originTime: DateTime.utc(2026, 10, 17, 17, 36, second),
  lat: latitude,
  lng: -101.55189,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'tts_enabled': false}));

  test(
    'original SASNO starts OBS without magnitude, ignores duplicates and stops after matching SSN + 30s',
    () async {
      final originalBytes = File(
        'test/fixtures/sasmex_firestore_20261017.original.json',
      ).readAsBytesSync();
      expect(
        sha256.convert(originalBytes).toString(),
        '668842f7958b668b23dddf263d6831abff3996a6d40cb50303a5346497b3dbc5',
      );
      await TtsService().configure(enabled: false, persist: false);
      final input = ObsAutomationInputService()..resetForTest();
      final received = <ObsAutomationInputEvent>[];
      final sub = input.events.listen(received.add);
      final executor = _Executor();
      final finish = Completer<void>();
      Duration? delay;
      var id = 0;
      final runner =
          ObsAutomationRunner(
            inputService: input,
            actionExecutor: executor,
            delay: (duration) {
              delay = duration;
              return finish.future;
            },
          )..configure([
            buildEewRecordingPreset(nextId: (p) => '$p-${id++}', enabled: true),
          ]);
      final provider = QuakeProvider(
        eewClock: () => DateTime.utc(2026, 10, 17, 9, 36, 58),
      );
      final service = SasmexService();
      try {
        await provider.eewHistoryReadyForTest;
        final e = (await service.acceptRelayFrameForTest(_frame()))!;
        expect(e.magnitude, -1);
        provider.handleUnifiedEventForTest(e);
        await _wait(() => runner.activeWaiterCount == 1);
        expect(executor.actions, [ObsAutomationBlockType.startRecord]);
        expect(
          provider.eewHistory.single.latest.sourcePayload,
          _frame()['Data'],
        );
        expect(
          const ObsAutomationConditionEvaluator().readInputField(
            received.single,
            'agency',
          ),
          'sasmex',
        );
        expect(
          obsAutomationInputFields
              .singleWhere((f) => f.key == 'agency')
              .options,
          containsPair('sasmex', 'SASMEX（墨西哥）'),
        );
        provider.handleUnifiedEventForTest(e);
        input.emitUnifiedEvent(e, ObsUnifiedEventPhase.updated);
        input.emitUnifiedEvent(
          _ssnUnit(source: 'usgsEqlist'),
          ObsUnifiedEventPhase.added,
        );
        input.emitUnifiedEvent(
          _ssnUnit(latitude: 30),
          ObsUnifiedEventPhase.added,
        );
        input.emitUnifiedEvent(
          _ssnUnit(second: 650),
          ObsUnifiedEventPhase.added,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(executor.actions, [ObsAutomationBlockType.startRecord]);
        expect(delay, isNull);
        input.emitUnifiedEvent(_ssnUnit(), ObsUnifiedEventPhase.added);
        await _wait(() => delay != null);
        expect(delay, const Duration(seconds: 30));
        expect(executor.actions, [ObsAutomationBlockType.startRecord]);
        finish.complete();
        await _wait(() => executor.actions.length == 2);
        expect(executor.actions.last, ObsAutomationBlockType.stopRecord);
      } finally {
        provider.dispose();
        service.dispose();
        await sub.cancel();
        await runner.dispose();
        input.resetForTest();
      }
    },
  );

  test(
    'current built-in template gains SASMEX without overwriting existing stacks or edited programs',
    () {
      var id = 0;
      final current = buildEewRecordingPreset(
        nextId: (p) => '$p-${id++}',
        enabled: true,
      );
      final previous = current.copyWith(
        stacks: current.stacks
            .where(
              (s) => !s.blocks.any(
                (b) =>
                    b.type == ObsAutomationBlockType.eewAgency &&
                    b.parameters['value'] == 'sasmex',
              ),
            )
            .toList(),
      );
      final upgraded = upgradeBuiltInEewRecordingPresets([previous]).single;
      expect(upgraded.id, previous.id);
      expect(upgraded.enabled, previous.enabled);
      expect(upgraded.stacks.length, previous.stacks.length + 1);
      for (var i = 0; i < previous.stacks.length; i++) {
        expect(upgraded.stacks[i].toJson(), previous.stacks[i].toJson());
      }
      final once = [upgraded];
      expect(identical(upgradeBuiltInEewRecordingPresets(once), once), true);
      final edited = previous.copyWith(
        stacks: [
          previous.stacks.first.copyWith(
            blocks: previous.stacks.first.blocks
                .where((b) => b.type != ObsAutomationBlockType.stopRecord)
                .toList(),
          ),
          ...previous.stacks.skip(1),
        ],
      );
      final custom = [edited];
      expect(
        identical(upgradeBuiltInEewRecordingPresets(custom), custom),
        true,
      );
    },
  );

  late Directory directory;
  late WindowsPreferencesWorker worker;
  late SharedPreferencesStorePlatform previousPlatform;
  late SharedPreferences prefs;
  late _Storage storage;
  EewHistoryStore store() =>
      EewHistoryStore(preferenceKey: 'unified_eew_history', storage: storage);

  group('SASMEX disk history', () {
    setUp(() async {
      prefs = await SharedPreferences.getInstance();
      previousPlatform = SharedPreferencesStorePlatform.instance;
      directory = await Directory.systemTemp.createTemp(
        'rhythmquake-sasmex-fix-',
      );
      worker = await WindowsPreferencesWorker.start(directory.path);
      SharedPreferencesStorePlatform.instance = worker;
      storage = _Storage(historyStorage(prefs));
    });
    tearDown(() async {
      SharedPreferencesStorePlatform.instance = previousPlatform;
      await worker.close();
      expect(
        directory.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}rhythmquake-sasmex-fix-',
        ),
        true,
      );
      await directory.delete(recursive: true);
    });

    test(
      'cold summaries display severity without reading originals; loading, export and replay preserve body',
      () async {
        final writer = store();
        final original = _group();
        await writer.save(prefs, [original]);
        final originalText = await worker.readHistory(
          writer.recordKey(original),
        );
        storage.bodyReads = 0;
        final cold = store();
        final summary = (await cold.restoreForStartup(
          prefs,
          lazyReports: true,
        )).single;
        expect(storage.bodyReads, 0);
        expect(summary.latest.sourcePayload, isNull);
        final fields =
            summary.storedReports!.payloads[summary.latest]!.sasmexFields;
        expect(fields, {'msgType': 'Alert', 'severity': 'Minor'});
        final display = UnifiedEventPresentation.fromEvent(
          summary.latest,
          sourceSummary: fields,
        );
        expect(display.intensityValue, '轻微');
        expect(display.secondaryText, '类型：Alert · 严重性：Minor');
        expect(
          display.timeText,
          UnifiedEventPresentation.fromEvent(_event()).timeText,
        );
        await cold.save(prefs, [summary]);
        expect(storage.bodyReads, 0);
        expect(
          await worker.readHistory(writer.recordKey(original)),
          originalText,
        );
        final loaded = await cold.loadReports(summary);
        expect(storage.bodyReads, 1);
        expect(loaded.latest.sourcePayload, _frame()['Data']);
        final package = HistoryReplayPackage.decode(
          HistoryReplayPackage.fromGroup(loaded).encode(),
        );
        final delivered = <UnifiedQuakeData>[];
        final replay =
            HistoryReplayController(onReport: delivered.add, onClear: (_) {})
              ..load(package, remember: false)
              ..play();
        try {
          expect(delivered.single.isReplay, true);
          expect(delivered.single.sourcePayload, _frame()['Data']);
          expect(delivered.single.originTime, _event().originTime);
        } finally {
          replay.dispose();
        }
      },
    );

    test(
      'old SASMEX summary is upgraded once without altering the saved original',
      () async {
        final writer = store();
        final original = _group();
        await writer.save(prefs, [original]);
        final key = writer.recordKey(original);
        final text = (await worker.readHistory(key)) as String;
        final old = (await storage.readSnapshot(key))!;
        for (final payload in old['payloads'] as List) {
          (payload as Map).remove('sasmexFields');
        }
        await storage.writeWithSnapshot(key, text, old);
        storage.bodyReads = 0;
        final summary = (await store().restoreForStartup(
          prefs,
          lazyReports: true,
        )).single;
        expect(storage.bodyReads, 1);
        expect(
          summary
              .storedReports!
              .payloads[summary.latest]!
              .sasmexFields!['severity'],
          'Minor',
        );
        expect(await worker.readHistory(key), text);
        storage.bodyReads = 0;
        await store().restoreForStartup(prefs, lazyReports: true);
        expect(storage.bodyReads, 0);
      },
    );

    for (final width in [280.0, 350.0]) {
      testWidgets('history card uses unified SASMEX fields at width $width', (
        tester,
      ) async {
        await tester.runAsync(loadUnifiedUiFonts);
        await tester.runAsync(() => (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load());
        final summary = await tester.runAsync(() async {
          await store().save(prefs, [_group()]);
          return (await store().restoreForStartup(
            prefs,
            lazyReports: true,
          )).single;
        });
        final provider = _HistoryProvider([summary!]);
        final map = MapStateProvider();
        const capture = ValueKey('sasmex-history');
        tester.view.physicalSize = Size(width, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<QuakeProvider>.value(value: provider),
                ChangeNotifierProvider<MapStateProvider>.value(value: map),
              ],
              child: MaterialApp(
                theme: unifiedUiTestTheme(),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: capture,
                      child: const ColoredBox(
                        color: Color(0xFF0A0A0A),
                        child: HistoryPanel(),
                      ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('轻微'), findsOneWidget);
          expect(find.text('严重性'), findsOneWidget);
          expect(find.text('类型：Alert · 严重性：Minor'), findsOneWidget);
          expect(
            find.text(UnifiedEventPresentation.fromEvent(_event()).timeText),
            findsOneWidget,
          );
          expect(find.textContaining('規模 調査中'), findsNothing);
          expect(find.textContaining('深度 --'), findsNothing);
          expect(tester.takeException(), isNull);
          if (Platform.environment['SASMEX_CAPTURE_DIRECTORY']
              case final String output) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(capture),
              );
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/history-${width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        } finally {
          await tester.pumpWidget(const SizedBox());
          provider.dispose();
          map.dispose();
          await tester.pump();
        }
      });
    }
  });
}
