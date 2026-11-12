import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/history_storage.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_panel_layout_test.dart' show HistoryProvider;

class _MemoryHistory implements HistoryStorage, HistorySnapshotStorage {
  final values = <String, Object>{};
  final snapshots = <String, Map<String, dynamic>>{};
  int bodyReads = 0;
  @override
  bool get separate => true;
  @override
  Future<Object?> read(String key) async {
    if (key.contains('_event_')) bodyReads++;
    return values[key];
  }

  @override
  Future<bool> write(String key, Object value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    snapshots.remove(key);
    return true;
  }

  @override
  Future<Map<String, dynamic>?> readSnapshot(String key) async =>
      snapshots[key];
  @override
  Future<bool> writeWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) async {
    values[key] = value;
    snapshots[key] = snapshot;
    return true;
  }
}

class _AlertProvider extends QuakeProvider {
  _AlertProvider(UnifiedQuakeData event)
    : unifiedEvents = [event],
      super(startCatalogServices: false);
  @override
  final List<UnifiedQuakeData> unifiedEvents;
}

Map<String, dynamic> _fixture(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;

UnifiedQuakeData _capturedCwa() => QuakeEventAdapter.convertJian(
  'cwa-eew',
  Map<String, dynamic>.from(
    _fixture(
          'source_estimation/cwa_1150075_prediction_reference.json',
        )['sourcePayload']
        as Map,
  ),
)!;

UnifiedQuakeData _capturedCea() => QuakeEventAdapter.convertJian(
  'cea',
  Map<String, dynamic>.from(
    (_fixture('jian/all.json')['source：cea'] as Map)['Data'] as Map,
  ),
)!;

EewEventGroup _group(UnifiedQuakeData report) => EewEventGroup(
  eventId: report.eventId,
  reports: [report],
  firstArrivedAt: report.originTime!,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, capture) in [
    ('CWA', _capturedCwa),
    ('CEA', _capturedCea),
  ]) {
    test(
      '$name estimates survive lazy storage and exact replay export',
      () async {
        final event = capture();
        final original = jsonEncode(event.toMap());
        final expected = estimatedEewIntensityValue(event);
        expect(expected, isNotNull);
        final storage = _MemoryHistory();
        final prefs = await SharedPreferences.getInstance();
        EewHistoryStore store() => EewHistoryStore(
          preferenceKey: 'unified_eew_history',
          storage: storage,
        );
        await store().save(prefs, [_group(event)]);
        final cold = store();
        final summary = (await cold.restoreForStartup(
          prefs,
          lazyReports: true,
        )).single;
        expect(storage.bodyReads, 0);
        expect(summary.latest.sourcePayload, isNull);
        expect(summary.latest.displayEstimatedIntensity, expected);
        expect(estimatedEewIntensityValue(summary.latest), expected);
        expect(summary.latest.maxIntensity, event.maxIntensity);
        final loaded = await cold.loadReports(summary);
        expect(jsonEncode(loaded.latest.toMap()), original);
        final package = HistoryReplayPackage.decode(
          HistoryReplayPackage.fromGroup(loaded).encode(),
        );
        expect(jsonEncode(package.reports.single.toMap()), original);
        final emitted = <UnifiedQuakeData>[];
        final controller =
            HistoryReplayController(onReport: emitted.add, onClear: (_) {})
              ..load(package)
              ..play();
        addTearDown(controller.dispose);
        expect(emitted.single.apiTypeLabel, 'Mock · 回放');
        expect(estimatedEewIntensityValue(emitted.single), expected);
        expect(emitted.single.sourcePayload, event.sourcePayload);
        expect(jsonEncode(event.toMap()), original);
      },
    );
  }

  test(
    'summary preserves adjusted prediction and suppressed training state',
    () async {
      // Standalone optional-field contract checks, not rewritten captures.
      for (final optional in [
        {'pgaAdj': 2},
        {'pgaAdj': 'invalid'},
        {'isTraining': true},
      ]) {
        final event = UnifiedQuakeData(
          source: 'cwaEew',
          origin: 4,
          eventId: 'optional-field-contract',
          isEew: true,
          timeZone: 8,
          titleText: 'contract',
          reportNumText: '第1報',
          useShindo: true,
          maxIntensity: '-',
          className: 'gray',
          hypocenter: '',
          magnitude: 4.7,
          depth: 30,
          lat: 22.45,
          lng: 120.34,
          originTime: DateTime.utc(2000),
          apiTypeLabel: 'Jian Project',
          sourcePayload: optional,
        );
        final storage = _MemoryHistory();
        final prefs = await SharedPreferences.getInstance();
        final store = EewHistoryStore(
          preferenceKey: 'unified_eew_history',
          storage: storage,
        );
        final original = _group(event);
        await store.save(prefs, [original]);
        final summary = store.releaseSavedFrames(original, deferReports: true);
        expect(summary.latest.sourcePayload, isNull);
        expect(
          estimatedEewIntensityValue(summary.latest),
          estimatedEewIntensityValue(event),
        );
      }
    },
  );

  test(
    'old summaries rebuild display metadata once without rewriting originals',
    () async {
      final storage = _MemoryHistory();
      final prefs = await SharedPreferences.getInstance();
      EewHistoryStore store() => EewHistoryStore(
        preferenceKey: 'unified_eew_history',
        storage: storage,
      );
      final original = _group(_capturedCwa());
      final writer = store();
      await writer.save(prefs, [original]);
      final key = writer.recordKey(original);
      final originalText = storage.values[key];
      final old = storage.snapshots[key]!;
      old.remove('presentationVersion');
      for (final report in (old['group'] as Map)['reports'] as List) {
        (report as Map).remove('displayEstimatedIntensity');
        report.remove('displayEstimateResolved');
      }
      final upgraded = (await store().restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(storage.bodyReads, 1);
      expect(estimatedEewIntensityValue(upgraded.latest), '3');
      expect(storage.values[key], originalText);
      storage.bodyReads = 0;
      final cold = (await store().restoreForStartup(
        prefs,
        lazyReports: true,
      )).single;
      expect(storage.bodyReads, 0);
      expect(estimatedEewIntensityValue(cold.latest), '3');
    },
  );

  for (final width in [280.0, 390.0]) {
    testWidgets('history shows estimated badges without overflow at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = HistoryProvider([
        _group(_capturedCwa()),
        _group(_capturedCea()),
      ]);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: MaterialApp(home: Scaffold(body: HistoryPanel())),
        ),
      );
      expect(find.text('预估震度'), findsOneWidget);
      expect(find.text('预估烈度'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (name, capture, label) in [
    ('CWA', _capturedCwa, '预估震度'),
    ('CEA', _capturedCea, '预估烈度'),
  ]) {
    testWidgets('$name replay card shows the same estimate as live', (
      tester,
    ) async {
      final emitted = <UnifiedQuakeData>[];
      final controller =
          HistoryReplayController(onReport: emitted.add, onClear: (_) {})
            ..load(HistoryReplayPackage.fromGroup(_group(capture())))
            ..play();
      addTearDown(controller.dispose);
      final provider = _AlertProvider(emitted.single);
      final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
          ],
          child: const MaterialApp(home: Scaffold(body: AlertModule())),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.stop();
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      mapState.dispose();
      await tester.pump();
    });
  }
}
