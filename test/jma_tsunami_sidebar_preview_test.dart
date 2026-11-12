import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_sidebar.dart';
import 'jma_tsunami_sidebar_test.dart' as support;

void main() {
  testWidgets('render actual sidebar with unchanged documented samples', (
    tester,
  ) async {
    final groups = <JmaTsunamiListGroup>[];
    await tester.runAsync(() async {
      final fonts = FontLoader('JmaPreview')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await fonts.load();
      const root = 'test/fixtures/jma_tsunami';
      final forecast =
          jsonDecode(
                File(
                  '$root/whews.forecast_stations.documented.json',
                ).readAsStringSync(),
              )
              as Map;
      final observation =
          jsonDecode(
                '{${File('$root/whews.observations.documented.fragment.txt').readAsStringSync()}}',
              )
              as Map;
      // Independent documentation examples. No times, heights or names changed.
      for (final payload in [forecast['Data'], observation]) {
        final parsed = await NativeJmaTsunami.prepareAsync({
          'op': 'parse',
          'transport': 'whews',
          'payload': payload,
        });
        final view = await NativeJmaTsunami.prepareAsync({
          'op': 'project',
          'message': parsed,
          'nowMs': 0,
        });
        groups.addAll([
          for (final group in view['groups'] as List)
            JmaTsunamiListGroup.fromMap(group as Map),
        ]);
      }
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final phone in [false, true]) {
      final capture = GlobalKey();
      final size = Size(phone ? 320 : 420, phone ? 240 : 200);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'JmaPreview',
              ),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: phone ? const Size(390, 850) : const Size(1700, 1000),
              ),
              child: Scaffold(
                backgroundColor: const Color(0xFF17191B),
                body: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        phone ? '手机 UI · 每行一项' : '桌面 UI · 每行两项',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '文档原样本预览 · 非实时\n预报与观测为两份独立示例',
                        style: TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                      const SizedBox(height: 10),
                      JmaTsunamiSidebar(
                        groups: groups,
                        scale: 1,
                        maxHeight: size.height - 90,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await support.ready(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final out = File(
          'tmp/jma_sidebar_20261020/${phone ? 'phone' : 'desktop'}.png',
        );
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
