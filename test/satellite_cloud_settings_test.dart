import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('cloud switches are off, independent and persisted at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'map_overlay_cloudLayer': true});
      final quake = QuakeProvider(jmaVolcanoPushEnabled: true);
      final map = MapStateProvider()..setOverlayEnabled('cloudLayer', true);
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
      for (final source in ['jma', 'nsmc']) {
        final key = '${source}SatelliteCloudLayer';
        final toggle = find.byKey(ValueKey('$source-satellite-cloud-enabled'));
        await tester.scrollUntilVisible(
          toggle,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<Switch>(toggle).value, isFalse);
        expect(map.isOverlayEnabled(key), isFalse);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(map.isOverlayEnabled(key), isTrue);
        expect(tester.widget<Switch>(toggle).value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('map_overlay_$key'), isTrue);
        expect(map.isOverlayEnabled('cloudLayer'), isTrue);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(map.isOverlayEnabled(key), isFalse);
        expect(prefs.getBool('map_overlay_$key'), isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      quake.dispose();
      map.dispose();
    });
  }
}
