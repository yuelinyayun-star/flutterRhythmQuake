import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_scale.dart';

void main() {
  testWidgets('sidePanelWidthScale grows on wide desktop windows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(2560, 1440)),
          child: Builder(
            builder: (context) {
              expect(UiScale.compact(context), 1.0);
              expect(
                UiScale.sidePanelWidthScale(context),
                closeTo(2560 / 1280, 0.001),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });

  testWidgets('sidePanelWidthScale never shrinks below compact baseline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: Builder(
            builder: (context) {
              expect(UiScale.compact(context), closeTo(1200 / 1280, 0.001));
              expect(UiScale.sidePanelWidthScale(context), 1.0);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });
}
