import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_list_card.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_sidebar.dart';
import 'support/unified_ui_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reported serialized height field renders 0.2m in both JMA lists',
    (tester) async {
      tester.view.physicalSize = const Size(800, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadUnifiedUiFonts);
      // Protocol fixture using the exact malformed display text in the user's
      // screenshot, not presented as a captured complete upstream bulletin.
      const field = 'map[type:津波の高さ unit:m value:0.2]';
      final raw = <String, dynamic>{
        'createTime': '2026-11-06 19:53:00',
        'areas': [
          {
            'name': '千葉県九十九里・外房',
            'kind': '津波予報',
            'maxHeight': 0.2,
            'maxHeightDesc': field,
            'arrivalTime': '',
            'condition': '',
          },
        ],
      };
      final before = jsonEncode(raw);
      final message = await tester.runAsync(
        () => TsunamiMessage.parseJmaSourceAsync('whews', raw),
      );
      expect(message!.sourcePayload, raw);
      expect(jsonEncode(raw), before);
      expect(message.areas.single.height, 0.2);
      final projected = NativeJmaTsunami.prepare({
        'op': 'project',
        'message': message.toMap(),
        'nowMs': 0,
      });
      final groups = [
        for (final row in projected['groups'] as List)
          JmaTsunamiListGroup.fromMap(row as Map),
      ];
      expect(groups.single.rows.single.height, '0.2m');
      expect(groups.single.rows.single.arrivalTime, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          theme: unifiedUiTestTheme(),
          home: Scaffold(
            backgroundColor: const Color(0xff202124),
            body: RepaintBoundary(
              key: const ValueKey('quantity-height-render'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 380,
                    child: JmaTsunamiListCard(group: groups.single, scale: 1),
                  ),
                  const SizedBox(width: 30),
                  SizedBox(
                    width: 300,
                    height: 400,
                    child: JmaTsunamiSidebar(
                      groups: groups,
                      scale: 1,
                      maxHeight: 400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('0.2m'), findsNWidgets(2));
      expect(find.textContaining('map['), findsNothing);
      for (final element in find.text('0.2m').evaluate()) {
        expect(
          tester
              .getSize(find.byElementPredicate((e) => identical(e, element)))
              .height,
          lessThan(30),
        );
      }
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('quantity-height-render')),
        );
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('tmp/jma_tsunami_height_20261106')
            ..createSync(recursive: true);
          File(
            '${dir.path}/left-and-right-height.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
