import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';
import 'jma_eew_long_period_badge_test.dart' as original;
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('render six actual Flutter badges from unified alert card', (
    tester,
  ) async {
    await tester.runAsync(loadUnifiedUiFonts);
    tester.view.physicalSize = const Size(1600, 1120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = original.whews();
    final data = <(String, int?)>[
      ('字段缺失', null),
      ('上游等级 0', 0),
      ('长周期等级 1', 1),
      ('长周期等级 2', 2),
      ('长周期等级 3', 3),
      ('长周期等级 4', 4),
    ];
    UnifiedQuakeData variant(int? level) {
      final raw = Map<String, dynamic>.from(source.sourcePayload!);
      raw.remove('maxLgInt');
      if (level != null) raw['maxLgInt'] = '$level';
      return source.copyWith(sourcePayload: raw);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: unifiedUiTestTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('six-grades'),
            child: ColoredBox(
              color: const Color(0xff202124),
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JMA EEW · 长周期显示对照（真实 Flutter 组件）',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '测试数据仅替换预测长周期字段；其余内容沿用 WHEWS 样例',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 25),
                    for (int row = 0; row < 3; row++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int col = 0; col < 2; col++)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data[row * 2 + col].$1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  UnifiedAlertCard(
                                    event: variant(data[row * 2 + col].$2),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 25),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final entry in data) {
      final event = variant(entry.$2);
      expect(event.eewLongPeriodClass, entry.$2 == 0 ? null : entry.$2);
    }
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('six-grades')),
      );
      final image = await boundary.toImage(pixelRatio: 1.4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('tmp/jma_eew_long_period_badge_20261106')
        ..createSync(recursive: true);
      File(
        '${folder.path}/six-grades-render.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
