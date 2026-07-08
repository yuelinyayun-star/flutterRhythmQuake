import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
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
}

void _clear(EqlistManager manager) {
  manager.updateJmaList(const []);
  manager.updateCencList(const []);
  manager.updateUsgsList(const []);
  manager.updateFssnList(const []);
  manager.updateKmaList(const []);
  manager.updateCwaList(const []);
  manager.updateEmscList(const []);
}
