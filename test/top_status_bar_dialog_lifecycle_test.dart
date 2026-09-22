import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/ui/top_status_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mock dialog remains valid through exit animation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TopStatusBar())),
    );
    await tester.tap(find.byTooltip('模拟注入'));
    await tester.pumpAndSettle();

    expect(find.text('模拟注入'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.text('本地注入 API'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    final dragHandle = find.byKey(const ValueKey('mock-injection-drag-handle'));
    final before = tester.getTopLeft(dragHandle);
    await tester.drag(dragHandle, const Offset(120, 80));
    await tester.pump();
    expect(tester.getTopLeft(dragHandle), isNot(equals(before)));

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('模拟注入'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
