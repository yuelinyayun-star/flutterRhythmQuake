import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/app_edition.dart';
import 'package:flutterrhythmquake/widgets/ui/development_edition_label.dart';

void main() {
  for (final width in [800.0, 1661.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('edition label at $width / $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                        child: const ColoredBox(color: Color(0xFF202020)),
                      ),
                    ),
                    const Positioned(
                      left: 20,
                      bottom: 2,
                      child: DevelopmentEditionLabel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('开发版'),
          AppEdition.isPublic ? findsNothing : findsOneWidget,
        );
        if (!AppEdition.isPublic) {
          final text = tester.widget<Text>(find.text('开发版'));
          expect(text.style!.fontSize, 11);
          expect(text.style!.color, Colors.white54);
          final rect = tester.getRect(find.text('开发版'));
          expect(rect.left, 20);
          expect(rect.bottom, lessThanOrEqualTo(900));
          await tester.tapAt(rect.center);
          expect(taps, 1, reason: 'The label must not intercept map gestures');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
