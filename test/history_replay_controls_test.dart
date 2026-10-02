import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_controls.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_replay_test.dart' as recorded;
import 'history_panel_layout_test.dart' show HistoryProvider;
import 'history_replay_timeline_test.dart' show captured, saved;

class ReplayFilePicker extends FilePicker {
  String? inputPath;
  List<String>? inputPaths;
  bool? lastAllowMultiple;
  String? outputPath;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastAllowMultiple = allowMultiple;
    final paths = inputPaths ?? (inputPath == null ? <String>[] : [inputPath!]);
    if (paths.isEmpty) return null;
    return FilePickerResult([
      for (final path in paths)
        PlatformFile(
          path: path,
          name: 'recorded.rqreplay',
          size: await File(path).length(),
        ),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => outputPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReplayFilePicker picker;
  late Directory temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    picker = ReplayFilePicker();
    FilePicker.platform = picker;
    temp = await Directory.systemTemp.createTemp('rhythmquake-replay-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  testWidgets('timeline switch is available before selecting any history', (
    tester,
  ) async {
    final provider = HistoryProvider([]);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<QuakeProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: HistoryPanel())),
      ),
    );
    expect(find.text('时间轴联动回放'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(provider.historyReplay.timelineLinked, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(HistoryReplayController.timelinePreferenceKey),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'clicking a history card includes other effective history events',
    (tester) async {
      final provider = HistoryProvider([
        saved(captured('cwa_1150074')),
        saved(captured('cea_202609290220')),
      ]);
      addTearDown(provider.dispose);
      provider.historyReplay.restoreTimelineLinked(true);
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox(width: 350, child: HistoryPanel())),
          ),
        ),
      );
      await tester.tap(find.byTooltip('回放已保存报文').first);
      await tester.pump();
      expect(provider.historyReplay.linkedEventCount, 2);
      expect(provider.historyReplay.totalReports, 5);
      expect(provider.historyReplay.importedPackages, isEmpty);
      expect(find.textContaining('联动 2 个事件'), findsOneWidget);
      provider.historyReplay.stop();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [280.0, 520.0]) {
    testWidgets(
      'multiple imports, switching anchor and atomic failed batch at $width',
      (tester) async {
        final output = <UnifiedQuakeData>[];
        final controller = HistoryReplayController(
          onReport: output.add,
          onClear: (_) {},
        );
        addTearDown(controller.dispose);
        picker.inputPaths = [
          'test/fixtures/history_replay/cwa_1150074.rqreplay',
          'test/fixtures/history_replay/cea_202609290220.rqreplay',
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: HistoryReplayControls(controller: controller),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('导入回放包'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(picker.lastAllowMultiple, isTrue);
        expect(controller.importedPackages.length, 2);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('播放回放'));
        await tester.pump();
        expect(controller.totalReports, 5);
        await tester.tap(find.byTooltip('已导入回放'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuItem<HistoryReplayPackage>).last);
        await tester.pumpAndSettle();
        expect(
          controller.package!.identity,
          captured('cea_202609290220').identity,
        );
        await tester.tap(find.byTooltip('播放回放'));
        await tester.pump();
        expect(controller.totalReports, 2);
        final current = controller.package;
        final invalid = '${temp.path}/invalid.rqreplay';
        await tester.runAsync(
          () => File(invalid).writeAsString('{bad json', encoding: utf8),
        );
        picker.inputPaths = [picker.inputPaths!.first, invalid];
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('导入回放包'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(controller.package, same(current));
        expect(controller.importedPackages.length, 2);
        expect(controller.active, isTrue);
        expect(find.textContaining('导入失败'), findsOneWidget);
        expect(tester.takeException(), isNull);
        controller.stop();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'history actions enable only saved reports and start shared playback',
    (tester) async {
      final event = recorded.recordedEew();
      final missing = UnifiedQuakeData.fromMap({
        ...event.toMap(),
        'eventId': 'legacy-without-payload',
        'sourcePayload': null,
      });
      final provider = HistoryProvider([
        recorded.group([event]),
        recorded.group([missing]),
      ]);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox(width: 350, child: HistoryPanel())),
          ),
        ),
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '未保存原始报文',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('回放已保存报文'));
      await tester.pump();
      expect(provider.historyReplay.active, isTrue);
      expect(find.byTooltip('停止回放'), findsOneWidget);
      await tester.tap(find.byTooltip('停止回放'));
      await tester.pump();
      expect(provider.historyReplay.active, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'desktop export writes a round-trippable UTF-8 package and handles cancel',
    () async {
      final package = HistoryReplayPackage.fromGroup(
        recorded.group([recorded.recordedEew()]),
      );
      expect(await exportHistoryReplay(package), isFalse);
      picker.outputPath = '${temp.path}/captured.rqreplay';
      expect(await exportHistoryReplay(package), isTrue);
      final restored = HistoryReplayPackage.decode(
        await File(picker.outputPath!).readAsString(),
      );
      expect(restored.reports.single.toMap(), package.reports.single.toMap());
    },
  );

  testWidgets('both history play buttons close the drawer and keep playing', (
    tester,
  ) async {
    final provider = HistoryProvider([
      recorded.group([recorded.recordedEew()]),
    ]);
    addTearDown(provider.dispose);
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<QuakeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            key: scaffold,
            drawer: const Drawer(child: HistoryPanel()),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回放已保存报文'));
    await tester.pumpAndSettle();
    expect(scaffold.currentState!.isDrawerOpen, isFalse);
    expect(provider.historyReplay.active, isTrue);
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.textContaining('静音'), findsNothing);
    await tester.tap(find.byTooltip('重新回放'));
    await tester.pumpAndSettle();
    expect(scaffold.currentState!.isDrawerOpen, isFalse);
    expect(provider.historyReplay.active, isTrue);
    provider.historyReplay.stop();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty history still offers controls for an imported replay', (
    tester,
  ) async {
    final provider = HistoryProvider([]);
    addTearDown(provider.dispose);
    provider.historyReplay.load(
      HistoryReplayPackage.fromGroup(recorded.group([recorded.recordedEew()])),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<QuakeProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: HistoryPanel())),
      ),
    );
    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(find.byTooltip('播放回放'), findsOneWidget);
    await tester.tap(find.byTooltip('播放回放'));
    await tester.pump();
    expect(provider.historyReplay.active, isTrue);
    await tester.tap(find.byTooltip('停止回放'));
    await tester.pump();
    expect(provider.historyReplay.active, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'history play action uses station frames added after the card was built',
    (tester) async {
      final event = HistoryReplayPackage.decode(
        File(
          'test/fixtures/history_replay/cwa_1150074.rqreplay',
        ).readAsStringSync(),
      ).reports.first;
      final original = recorded.group([event]);
      final provider = HistoryProvider([original]);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox(width: 350, child: HistoryPanel())),
          ),
        ),
      );
      final frame = StationHistoryFrame(
        receivedAt: event.arrivedAt!,
        snapshot: {'kind': 'nied', 'stations': []},
      );
      provider.eewHistory[0] = original.copyWith(stationFrames: [frame]);
      await tester.tap(find.byTooltip('回放已保存报文'));
      await tester.pump();
      expect(
        provider.historyReplay.package!.stationFrames.single.toMap(),
        frame.toMap(),
      );
      expect(provider.historyReplay.active, isTrue);
      provider.historyReplay.stop();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [280.0, 520.0]) {
    testWidgets('import, play, stop and malformed import at width $width', (
      tester,
    ) async {
      final output = <UnifiedQuakeData>[];
      final cleared = <String>[];
      final controller = HistoryReplayController(
        onReport: output.add,
        onClear: cleared.add,
      );
      addTearDown(controller.dispose);
      final package = HistoryReplayPackage.fromGroup(
        recorded.group([recorded.recordedEew()]),
      );
      picker.inputPath = '${temp.path}/captured.rqreplay';
      await tester.runAsync(
        () => File(
          picker.inputPath!,
        ).writeAsString(package.encode(), encoding: utf8),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: HistoryReplayControls(controller: controller),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('导入回放包'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(controller.package, isNotNull);
      expect(output, isEmpty);
      await tester.tap(find.byTooltip('播放回放'));
      await tester.pump();
      expect(output.length, 1);
      expect(controller.active, isTrue);
      final activePackage = controller.package;
      await tester.runAsync(
        () => File(picker.inputPath!).writeAsString('{bad json'),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('导入回放包'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(controller.package, same(activePackage));
      expect(controller.active, isTrue);
      expect(find.textContaining('导入失败'), findsOneWidget);
      await tester.tap(find.byTooltip('停止回放'));
      await tester.pump();
      expect(cleared.length, 1);
      expect(controller.active, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
