import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/manual_location_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    ValueChanged<ManualLocationCoordinates?> result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result(
                  await showDialog<ManualLocationCoordinates>(
                    context: context,
                    builder: (_) => const ManualLocationDialog(
                      latitude: 29.3,
                      longitude: 120.1,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final action in ['保存', '取消', 'back', 'barrier']) {
    testWidgets('focused coordinate input survives $action exit animation', (
      tester,
    ) async {
      ManualLocationCoordinates? result;
      await open(tester, (value) => result = value);
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '29.306959');
      await tester.enterText(fields.last, '120.075058');
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      if (action == 'back') {
        Navigator.of(tester.element(fields.first)).pop();
      } else if (action == 'barrier') {
        await tester.tapAt(const Offset(10, 10));
      } else {
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
      }
      // Exercise the frame after pop, before the dialog route is unmounted.
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(ManualLocationDialog), findsNothing);
      expect(
        result,
        action == '保存' ? (latitude: 29.306959, longitude: 120.075058) : null,
      );
      // Reopening must get fresh controllers, not the disposed old ones.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        '29.300000',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('invalid and nonfinite coordinates stay in the dialog', (
    tester,
  ) async {
    var saved = false;
    await open(tester, (_) => saved = true);
    for (final (lat, lng, error) in [
      ('NaN', '120', '请输入有效的数字坐标'),
      ('29', 'Infinity', '请输入有效的数字坐标'),
      ('91', '120', '纬度范围必须在 -90 ~ 90'),
      ('29', '181', '经度范围必须在 -180 ~ 180'),
    ]) {
      await tester.enterText(find.byType(TextField).first, lat);
      await tester.enterText(find.byType(TextField).last, lng);
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text(error), findsOneWidget);
      expect(saved, false);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
