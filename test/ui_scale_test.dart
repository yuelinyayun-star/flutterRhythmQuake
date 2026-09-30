import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_scale.dart';

void main() {
  test('native platforms retain the shortest-side layout rule', () {
    for (final platform in TargetPlatform.values) {
      for (final size in [
        const Size(1200, 500),
        const Size(844, 390),
        const Size(390, 844),
        const Size(1200, 800),
      ]) {
        expect(
          UiScale.shouldUsePhoneLayout(size, isWeb: false, platform: platform),
          size.shortestSide < UiScale.phoneBreakpoint,
          reason: '$platform at $size',
        );
      }
    }
  });

  test('web desktop keeps desktop UI in a short browser window', () {
    expect(
      UiScale.shouldUsePhoneLayout(
        const Size(1200, 500),
        isWeb: true,
        platform: TargetPlatform.windows,
      ),
      isFalse,
    );
  });

  test('web phone keeps phone UI in landscape', () {
    expect(
      UiScale.shouldUsePhoneLayout(
        const Size(844, 390),
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
  });

  test('web narrow desktop window and tablet keep existing layout rules', () {
    expect(
      UiScale.shouldUsePhoneLayout(
        const Size(500, 800),
        isWeb: true,
        platform: TargetPlatform.windows,
      ),
      isTrue,
    );
    expect(
      UiScale.shouldUsePhoneLayout(
        const Size(800, 1024),
        isWeb: true,
        platform: TargetPlatform.iOS,
      ),
      isFalse,
    );
  });

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
