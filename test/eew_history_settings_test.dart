import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_history_retention.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/eew_history_settings.dart';
import 'package:provider/provider.dart';

import 'history_panel_layout_test.dart' show HistoryProvider;
import 'eew_history_retention_test.dart' show storageGroups;

class SettingsHistoryProvider extends HistoryProvider {
  SettingsHistoryProvider([List<EewEventGroup>? groups]) : super(groups ?? []);
  EewHistoryRetention retention = const EewHistoryRetention();

  @override
  EewHistoryRetention get eewHistoryRetention => retention;

  @override
  Future<void> setEewHistoryRetention(EewHistoryRetention value) async {
    retention = value;
    final retained = value.apply(eewHistory);
    eewHistory
      ..clear()
      ..addAll(retained);
    historyListenable.value++;
  }
}

void main() {
  const preview = bool.fromEnvironment('HISTORY_UI_PREVIEW');
  setUpAll(() async {
    if (!preview) return;
    final font = FontLoader('HistoryTest')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets(
    'lowering the limit requires confirmation before removing events',
    (tester) async {
      final provider = SettingsHistoryProvider(storageGroups());
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<QuakeProvider>.value(
          value: provider,
          child: const MaterialApp(home: Scaffold(body: EewHistorySettings())),
        ),
      );
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.byTooltip('保存上限'));
      await tester.pumpAndSettle();
      expect(find.text('调整历史保存上限'), findsOneWidget);
      expect(provider.eewHistory.length, 40);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(provider.retention.maxPerSource, 15);
      expect(provider.eewHistory.length, 40);
      await tester.tap(find.byTooltip('保存上限'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(provider.retention.maxPerSource, 1);
      expect(provider.eewHistory.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [280.0, 390.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'history settings edit and permanent switch at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 650);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final provider = SettingsHistoryProvider();
          addTearDown(provider.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            ChangeNotifierProvider<QuakeProvider>.value(
              value: provider,
              child: MaterialApp(
                theme: ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: preview ? 'HistoryTest' : null,
                  ),
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 650),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: boundary,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: EewHistorySettings(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('永久保存'), findsOneWidget);
          expect(find.text('每个预警源保存上限'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('eew-history-limit')),
            '42',
          );
          await tester.tap(find.byTooltip('保存上限'));
          await tester.pumpAndSettle();
          expect(provider.retention.maxPerSource, 42);
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          expect(provider.retention.keepForever, isTrue);
          expect(
            tester.widget<TextField>(find.byType(TextField)).enabled,
            isFalse,
          );
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          expect(provider.retention.keepForever, isFalse);
          expect(
            tester.widget<TextField>(find.byType(TextField)).enabled,
            isTrue,
          );
          await tester.enterText(
            find.byKey(const ValueKey('eew-history-limit')),
            '0',
          );
          await tester.tap(find.byTooltip('保存上限'));
          await tester.pumpAndSettle();
          expect(provider.retention.maxPerSource, 42);
          expect(find.text('保存上限必须是大于 0 的整数'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('eew-history-limit')),
            '42',
          );
          ScaffoldMessenger.of(
            tester.element(find.byType(EewHistorySettings)),
          ).removeCurrentSnackBar();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (preview) {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await render.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final output = Directory('build/diagnostics/history_replay');
              await output.create(recursive: true);
              await File(
                '${output.path}/settings_${width.toInt()}_$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
