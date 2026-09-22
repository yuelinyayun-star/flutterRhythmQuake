import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_controls.dart';
import 'package:flutterrhythmquake/widgets/ui/wauth_token_field.dart';

void main() {
  for (final width in [280.0, 390.0, 1024.0]) {
    testWidgets('token field fits a $width wide settings row', (tester) async {
      final controller = TextEditingController(text: 'test-business-token');
      addTearDown(controller.dispose);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: SettingsControlRow(
                  title: 'WAuth 账号授权',
                  leading: Icons.account_circle_outlined,
                  control: WAuthTokenField(
                    controller: controller,
                    onSave: () => saves++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('显示 Token'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.byTooltip('保存 WAuth API Token'));
      expect(saves, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('busy token field cannot edit or submit', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WAuthTokenField(
            controller: controller,
            onSave: () => saves++,
            busy: true,
          ),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byTooltip('保存 WAuth API Token'));
    expect(saves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
