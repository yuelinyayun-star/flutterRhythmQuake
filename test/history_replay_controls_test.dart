import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_controls.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:provider/provider.dart';

import 'history_replay_test.dart' as recorded;
import 'history_panel_layout_test.dart' show HistoryProvider;

class ReplayFilePicker extends FilePicker {
  String? inputPath;
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
    if (inputPath == null) return null;
    return FilePickerResult([
      PlatformFile(
        path: inputPath,
        name: 'recorded.rqreplay',
        size: await File(inputPath!).length(),
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
    picker = ReplayFilePicker();
    FilePicker.platform = picker;
    temp = await Directory.systemTemp.createTemp('rhythmquake-replay-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

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
        tester.widget<IconButton>(find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '未保存原始报文',
        )).onPressed,
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
