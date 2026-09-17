import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CarouselProvider extends QuakeProvider {
  @override
  final List<UnifiedQuakeData> unifiedEvents = List.generate(
    5,
    (i) => UnifiedQuakeData(
      source: 'cencEqlist',
      origin: 0,
      eventId: 'carousel-fixture-$i',
      isEew: false,
      timeZone: 0,
      titleText: 'Carousel fixture',
      reportNumText: '1',
      useShindo: false,
      maxIntensity: '3',
      className: 'orange',
      hypocenter: 'Fixture $i',
      originTime: DateTime.utc(2026, 9, 6),
      reportTime: DateTime.utc(2026, 9, 6),
      magnitude: 5,
      depth: 10,
      depthText: '10km',
      lat: 30,
      lng: 130,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 900),
  ]) {
    final phone = size.shortestSide < 600;
    testWidgets('carousel page size and timer at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>(
              create: (_) => _CarouselProvider(),
            ),
            ChangeNotifierProvider(create: (_) => MapStateProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: AlertModule())),
          ),
        ),
      );
      final cards = find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.key.toString().contains('unified_card_'),
      );
      expect(cards, findsNWidgets(phone ? 1 : 4));
      expect(find.text(phone ? '1/5' : '1/2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(cards, findsOneWidget);
      expect(find.text(phone ? '2/5' : '2/2'), findsOneWidget);
      expect(find.text('Fixture ${phone ? 1 : 4}'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(cards, findsNWidgets(phone ? 1 : 4));
      expect(find.text(phone ? '3/5' : '1/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
