import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:provider/provider.dart';

void main() {
  final manager = EqlistManager();

  setUp(() {
    _clear(manager);
  });

  tearDown(() {
    _clear(manager);
  });

  for (final size in [const Size(390, 844), const Size(1600, 900)]) {
    testWidgets('WHEWS catalog chip and mapped card fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = QuakeProvider();
      final event = QuakeEventAdapter.convertWhews('bgs', {
        'id': 'bgs_20260723101500',
        'magnitude': 2.4,
        'placeName': 'NORWICH, NORFOLK',
        'shockTime': '2026-07-23 18:15:00',
        'updateTime': '2026-07-23 18:15:00',
        'longitude': 1.29,
        'latitude': 52.63,
        'depth': 8.0,
      })!;
      provider.handleUnifiedEventForTest(event);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(create: (_) => MapStateProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(body: EqlistPanel(embedded: size.width < 600)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('BGS(1)'), findsOneWidget);
      expect(find.text('BGS'), findsOneWidget);
      expect(find.text(event.hypocenter), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('BGS(1)'));
      await tester.tap(find.text('BGS(1)'));
      await tester.pump();
      expect(find.text(event.hypocenter), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }

  testWidgets(
    'cached Korean KMA names display mapped without rewriting history',
    (tester) async {
      final cached = QuakeMessage(
        source: QuakeSourceType.kma_eq,
        eventId: 'kma_20260723034704',
        location: '경상북도',
        magnitude: 4.2,
        latitude: 36.1,
        longitude: 128.2,
        depth: 12,
        originTime: DateTime(2026, 7, 23, 2, 47, 4),
        timeZone: 8,
        maxIntensity: 4,
        isHistory: true,
        isInfoEvent: true,
      );
      manager.updateKmaList([cached]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => QuakeProvider()),
            ChangeNotifierProvider(create: (_) => MapStateProvider()),
          ],
          child: const MaterialApp(home: Scaffold(body: EqlistPanel())),
        ),
      );
      await tester.pump();
      expect(find.text('韩国附近'), findsOneWidget);
      expect(find.text('경상북도'), findsNothing);
      expect(find.text('2026-07-23 02:47 (UTC+8)'), findsOneWidget);
      expect(cached.location, '경상북도');
      expect(manager.kmaList.single.location, '경상북도');
    },
  );

  testWidgets('JMA shindo plus is rendered as a top-right suffix', (
    tester,
  ) async {
    manager.updateJmaList([
      QuakeMessage(
        source: QuakeSourceType.jma_fan,
        eventId: 'jma-plus-ui',
        location: '岩手県沖',
        magnitude: 6.9,
        latitude: 39,
        longitude: 142,
        depth: 50,
        originTime: DateTime(2026, 6, 25, 7, 30),
        isHistory: true,
        isInfoEvent: true,
        maxIntensity: 6,
        jmaShindo: '6+',
      ),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => QuakeProvider()),
          ChangeNotifierProvider(create: (_) => MapStateProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: EqlistPanel())),
      ),
    );
    await tester.pump();

    expect(find.text('6+'), findsNothing);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('JMA investigation displays the same hypocenter text as UI', (
    tester,
  ) async {
    manager.updateJmaList([
      QuakeMessage(
        source: QuakeSourceType.jma_fan,
        eventId: 'jma-investigating-ui',
        location: '',
        magnitude: -1,
        latitude: 0,
        longitude: 0,
        depth: -1,
        originTime: DateTime(2026, 8, 9, 14, 5),
        isHistory: true,
        isInfoEvent: true,
        jmaShindo: '4',
        infoTypeName: '震源・震度に関する情報',
      ),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => QuakeProvider()),
          ChangeNotifierProvider(create: (_) => MapStateProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: EqlistPanel())),
      ),
    );
    await tester.pump();

    expect(find.text('震源 調査中'), findsOneWidget);
    expect(find.text('規模 調査中'), findsOneWidget);
  });
}

void _clear(EqlistManager manager) {
  for (final entry in manager.getAllBuckets().entries) {
    if (entry.key.startsWith('whews_')) entry.value.clear();
  }
  manager.updateJmaList(const []);
  manager.updateCencList(const []);
  manager.updateUsgsList(const []);
  manager.updateFssnList(const []);
  manager.updateKmaList(const []);
  manager.updateCwaList(const []);
  manager.updateEmscList(const []);
}
