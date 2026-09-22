import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/widgets/ui/local_inject_settings.dart';

void main() {
  testWidgets('invalid unsaved port does not prevent disabling injection', (tester) async {
    SharedPreferences.setMockInitialValues({'debug_local_inject_enabled': true});
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: LocalInjectSettings())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('local-inject-port')), '0');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('debug_local_inject_enabled'), isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  for (final width in [280.0, 520.0, 1180.0]) {
    testWidgets('local injection controls fit width $width', (tester) async {
      SharedPreferences.setMockInitialValues({
        'debug_local_inject_port': 18765,
      });
      tester.view.physicalSize = Size(width, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: const Padding(
              padding: EdgeInsets.all(12),
              child: LocalInjectSettings(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('18765'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byTooltip('保存端口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
