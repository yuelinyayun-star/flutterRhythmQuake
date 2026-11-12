import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/eew_event_identity.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_panel_layout_test.dart' show HistoryProvider;
import 'support/unified_ui_fonts.dart';

// Report objects extracted unchanged from the two user-provided cloud archives.
final _archives =
    (jsonDecode(
              File(
                'test/fixtures/history_replay/cwa_1150076_cloud_original_reports.json',
              ).readAsStringSync(encoding: utf8),
            )
            as List)
        .cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _maps() => [
  for (final archive in _archives)
    ...List<Map<String, dynamic>>.from(archive['reports'] as List),
];

HistoryReplayPackage _package({int? archiveIndex}) {
  final archives = archiveIndex == null ? _archives : [_archives[archiveIndex]];
  return HistoryReplayPackage.decode(
    jsonEncode({
      'format': HistoryReplayPackage.format,
      'version': HistoryReplayPackage.version,
      'name': 'CWA 1150076 cloud reports',
      'omittedReports': 0,
      'arrivalInstantsUtc': [
        for (final archive in archives)
          ...archive['arrivalInstantsUtc'] as List,
      ],
      'reports': [
        for (final archive in archives) ...archive['reports'] as List,
      ],
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cloudFolder = String.fromEnvironment('CLOUD_REPLAY_DIRECTORY');
  const previewFolder = String.fromEnvironment('EEW_PREVIEW_DIRECTORY');
  setUpAll(() async {
    if (previewFolder.isNotEmpty) await loadUnifiedUiFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'extracted report fixture matches both complete cloud archive hashes',
    () {
      expect(_maps(), hasLength(4));
      if (cloudFolder.isEmpty) return;
      for (final archive in _archives) {
        final file = File('$cloudFolder/${archive['filename']}');
        final bytes = file.readAsBytesSync();
        expect(sha256.convert(bytes).toString(), archive['sha256']);
        final full = jsonDecode(utf8.decode(bytes)) as Map;
        expect(full['reports'], archive['reports']);
        expect(full['arrivalInstantsUtc'], archive['arrivalInstantsUtc']);
      }
    },
  );

  test(
    'original raw adapters agree on comparison identity without rewriting IDs',
    () {
      final maps = _maps();
      final before = jsonEncode(maps);
      for (final saved in maps) {
        final raw = Map<String, dynamic>.from(saved['sourcePayload'] as Map);
        final UnifiedQuakeData current;
        switch (saved['origin']) {
          case 4:
            current = QuakeEventAdapter.convertJian('cwa-eew', raw)!;
          case 1:
            current = FanService.decodeEventPayload(
              raw,
              sourceHint: 'cwa_eew',
            )!;
          default:
            current = QuakeEventAdapter.convert('cwaEew', raw, 0)!;
        }
        expect(current.eventId, saved['eventId']);
        expect(current.sourcePayload, saved['sourcePayload']);
        expect(canonicalEewEventId(current), '1150076');
        expect(current.magnitude, saved['magnitude']);
        expect(current.depth, saved['depth']);
      }
      expect(jsonEncode(maps), before);
    },
  );

  test(
    'original arrival order leaves one third-report card and one history group',
    () {
      final provider = QuakeProvider(startCatalogServices: false);
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final states = <BackgroundEventResultType>[];
      fakeAsync((async) {
        final clock = async.getClock(DateTime.now());
        final controller =
            HistoryReplayController(
                now: clock.now,
                onReport: (report) {
                  provider.handleUnifiedEventForTest(
                    report,
                    suppressEffects: true,
                  );
                  states.add(background.process(report).type);
                },
                onClear: (_) {},
              )
              ..load(_package())
              ..play();
        async.elapse(const Duration(seconds: 20));
        expect(states, [
          BackgroundEventResultType.newEvent,
          BackgroundEventResultType.update,
          BackgroundEventResultType.update,
          BackgroundEventResultType.dropped,
        ]);
        expect(provider.unifiedEvents, hasLength(1));
        expect(provider.unifiedEvents.single.reportNumText, '第3報');
        expect(provider.unifiedEvents.single.magnitude, 4.6);
        expect(provider.eewHistory, hasLength(1));
        expect(provider.eewHistory.single.reportCount, 3);
        controller.dispose();
        provider.dispose();
      });
    },
  );

  test('unknown CWA ID formats and other agencies are not stripped', () {
    final report = UnifiedQuakeData.fromMap(_maps().last);
    for (final id in ['cwa.gov.tw_earthquakeEW_1150077', 'unknown_1150076']) {
      expect(
        canonicalEewEventId(report.copyWith(eventId: id)),
        isNot('1150076'),
      );
    }
    expect(
      canonicalEewEventId(report.copyWith(source: 'ceaEew')),
      report.eventId,
    );
  });

  for (final archiveIndex in [null, 1]) {
    testWidgets('cloud replay renders estimates; archive=$archiveIndex', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = QuakeProvider(startCatalogServices: false);
      final map = MapStateProvider()..setShowEstimatedEpicenter(false);
      provider.historyReplay.load(_package(archiveIndex: archiveIndex));
      provider.historyReplay.play();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: map),
          ],
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: const Scaffold(
              body: RepaintBoundary(
                key: ValueKey('cloud-replay-preview'),
                child: AlertModule(),
              ),
            ),
          ),
        ),
      );
      // The production controller's clock is real time; advance the widget
      // timer queue across each newly scheduled recorded arrival separately.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 20));
      }
      expect(provider.historyReplay.played, archiveIndex == null ? 4 : 1);
      final latest = provider.unifiedEvents.single;
      expect(latest.reportNumText, archiveIndex == null ? '第3報' : '第1報');
      expect(latest.magnitude, archiveIndex == null ? 4.6 : 4.5);
      expect(find.text('预估震度'), findsOneWidget);
      expect(find.text(unifiedEewIntensityValue(latest)), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (previewFolder.isNotEmpty && archiveIndex == null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('cloud-replay-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$previewFolder/cloud-replay-third-report.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      provider.historyReplay.stop();
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      map.dispose();
      await tester.pump();
    });
  }

  testWidgets(
    'original cloud history shows estimates in collapsed and expanded rows',
    (tester) async {
      final reports = _package(archiveIndex: 0).reports.reversed.toList();
      final group = EewEventGroup(
        eventId: '1150076',
        reports: reports,
        firstArrivedAt: reports.last.arrivedAt!,
      );
      final provider = HistoryProvider([group]);
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: const Scaffold(body: HistoryPanel()),
          ),
        ),
      );
      expect(find.text('预估震度'), findsOneWidget);
      await tester.tap(find.text('3报'));
      await tester.pump();
      expect(find.text('预估震度'), findsNWidgets(3));
      expect(find.text('3'), findsNWidgets(2));
      expect(find.text('2'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
