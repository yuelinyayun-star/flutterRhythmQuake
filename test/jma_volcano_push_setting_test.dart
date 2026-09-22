import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('weather shortcut exposes a persistent volcano push switch', (
    tester,
  ) async {
    final quake = QuakeProvider(jmaVolcanoPushEnabled: true);
    final map = MapStateProvider();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: quake),
          ChangeNotifierProvider.value(value: map),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SettingsPage(weatherOnly: true)),
        ),
      ),
    );
    final toggle = find.byKey(const ValueKey('jma-volcano-push-enabled'));
    await tester.scrollUntilVisible(
      toggle,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('JMA 火山信息推送'), findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pump();
    expect(quake.jmaVolcanoPushEnabled, isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(QuakeProvider.jmaVolcanoPushEnabledPreferenceKey),
      isFalse,
    );
    expect(prefs.containsKey('map_overlay_volcanoLayer'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    quake.dispose();
    map.dispose();
  });
}
