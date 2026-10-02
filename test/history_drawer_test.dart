import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/history_drawer.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_controls.dart';
import 'package:provider/provider.dart';

import 'history_panel_layout_test.dart' show HistoryProvider;
import 'history_replay_timeline_test.dart' show captured, saved;

// Contrasting layout backdrop, not a geographic or earthquake data fixture.
class _Backdrop extends CustomPainter {
  const _Backdrop();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var x = 0; x < size.width; x += 24) {
      for (var y = 0; y < size.height; y += 24) {
        paint.color = (x ~/ 24 + y ~/ 24).isEven
            ? const Color(0xFF24484E)
            : const Color(0xFF58625A);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 24, 24),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => false;
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
  for (final width in [280.0, 390.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'glass history drawer, original reports and close action at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final cwa = captured('cwa_1150074');
          final cea = captured('cea_202609290220');
          final provider = HistoryProvider([
            saved(cwa).copyWith(reports: cwa.reports.reversed.toList()),
            saved(cea),
          ]);
          addTearDown(provider.dispose);
          provider.historyReplay.restoreTimelineLinked(true);
          provider.historyReplay.load(cwa, remember: false);
          final scaffold = GlobalKey<ScaffoldState>();
          await tester.pumpWidget(
            ChangeNotifierProvider<QuakeProvider>.value(
              value: provider,
              child: MaterialApp(
                theme: ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: preview ? 'HistoryTest' : null,
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const ValueKey('history-glass-preview'),
                  child: Scaffold(
                    key: scaffold,
                    drawerScrimColor: Colors.black.withValues(alpha: 0.22),
                    drawer: const HistoryDrawer(),
                    body: const CustomPaint(
                      painter: _Backdrop(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          );
          scaffold.currentState!.openDrawer();
          await tester.pumpAndSettle();
          expect(find.byType(BackdropFilter), findsOneWidget);
          final drawer = tester.widget<Drawer>(find.byType(Drawer));
          expect(drawer.backgroundColor, Colors.transparent);
          expect(drawer.width, width < 366 ? width - 16 : 350);
          expect(find.text('历史记录'), findsOneWidget);
          expect(find.text('时间轴联动回放'), findsOneWidget);
          expect(find.byTooltip('回放已保存报文'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          final decorated = find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color ==
                    SettingsControlStyle.panel,
          );
          expect(decorated, findsOneWidget);

          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('history-glass-preview')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            // Header pixels over two backdrop stripes stay distinct through one
            // translucent surface; an opaque drawer would hide the background.
            int redAt(int x, int y) => rgba.getUint8((y * image.width + x) * 4);
            expect((redAt(6, 84) - redAt(30, 84)).abs(), greaterThan(2));
            if (preview && scale == 1 && width == 390) {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('build/ui-previews/history-glass.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
            }
            image.dispose();
          });
          await tester.tap(find.byTooltip('关闭历史记录'));
          await tester.pumpAndSettle();
          expect(scaffold.currentState!.isDrawerOpen, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
