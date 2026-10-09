import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usgs_shakemap_test.dart' show eventFor, readJson;

List<QuakeMessage> earlyReports() =>
    (jsonDecode(
              File(
                'test/fixtures/early_est_history_20261009.original.json',
              ).readAsStringSync(encoding: utf8),
            )
            as List)
        .map((raw) => QuakeMessage.fromMap(Map<String, dynamic>.from(raw)))
        .toList();

// Expose already captured events as existing cards without inventing feed
// payloads or changing their time to pass realtime admission.
class _DisplayProvider extends QuakeProvider {
  _DisplayProvider(this.cards);
  final List<UnifiedQuakeData> cards;
  @override
  List<UnifiedQuakeData> get unifiedEvents => List.unmodifiable(cards);
}

List<UnifiedQuakeData> capturedCards() => [
  for (final file in const [
    'us6000u0xi.detail.original.geojson',
    'ci41345415.detail.original.geojson',
    'aka2026tvzrwv.detail.original.geojson',
  ])
    QuakeEventAdapter.catalogInfo(eventFor(readJson(file)), 'usgsEqlist'),
  QuakeEventAdapter.catalogInfo(earlyReports().last, 'earlyEst'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test(
    'map selection preserves original row and replaces/clears only display',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      var alerts = 0;
      provider.onUnifiedEventNotified = (_, _) => alerts++;
      final reports = earlyReports();
      final before = jsonEncode(reports.last.toMap());
      provider.selectHistoryMapProducts(reports.last);
      final info = provider.unifiedDisplayEvents.single;
      expect(info.rawEvent, same(reports.last));
      expect(info.eventId, reports.last.eventId);
      expect(info.originTime, reports.last.originTime);
      expect(info.reportTime, reports.last.reportTime);
      expect(info.lat, reports.last.latitude);
      expect(info.lng, reports.last.longitude);
      expect(info.magnitude, 5.0);
      expect(info.reportNumText, '第9報');
      expect(info.apiTypeLabel, 'WHEWS');
      expect(info.isHistory, isTrue);
      expect(info.isEew, isFalse);
      provider.selectHistoryMapProducts(reports.first);
      expect(provider.unifiedDisplayEvents.single.reportNumText, '第6報');
      expect(provider.unifiedDisplayEvents, hasLength(1));
      provider.selectHistoryMapProducts(null);
      expect(provider.unifiedDisplayEvents, isEmpty);
      expect(provider.unifiedEvents, isEmpty);
      expect(provider.unifiedMapEvents, isEmpty);
      expect(provider.currentUnifiedEvent, isNull);
      expect(alerts, 0);
      expect(jsonEncode(reports.last.toMap()), before);
    },
  );

  test(
    'existing newer Early-est card wins over selected older transport row',
    () {
      final reports = earlyReports();
      final latest = QuakeEventAdapter.catalogInfo(reports.last, 'earlyEst');
      final provider = _DisplayProvider([latest]);
      addTearDown(provider.dispose);
      provider.selectHistoryMapProducts(reports.first);
      expect(provider.unifiedDisplayEvents, [latest]);
      expect(provider.unifiedDisplayEvents.single.reportNumText, '第9報');
      provider.selectHistoryMapProducts(null);
      expect(provider.unifiedDisplayEvents, [latest]);
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('selected real history joins existing info carousel at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final existing = capturedCards();
      // A second real agency row is distinct from the four existing events.
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/cenc_ir_mojiang_20260914170727.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      final selected = QuakeMessage(
        source: QuakeSourceType.cenc,
        eventId: raw['eq_id'],
        location: raw['hypocenter'],
        magnitude: (raw['magnitude'] as num).toDouble(),
        latitude: (raw['latitude'] as num).toDouble(),
        longitude: (raw['longitude'] as num).toDouble(),
        depth: (raw['depth'] as num).toDouble(),
        originTime: DateTime.parse(raw['happen_time']),
        timeZone: 8,
        isHistory: true,
      );
      // Keep connection startup timers outside the widget's virtual clock.
      // Advancing the carousel must not start external catalogue sockets.
      final provider = (await tester.runAsync(
        () async => _DisplayProvider(existing),
      ))!;
      final mapState = MapStateProvider();
      provider.selectHistoryMapProducts(selected);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider.value(value: mapState),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: AlertModule())),
          ),
        ),
      );
      final phone = size.shortestSide < 600;
      expect(find.text(selected.location), findsOneWidget);
      expect(find.text(phone ? '1/5' : '1/2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(phone ? '2/5' : '2/2'), findsOneWidget);
      expect(find.text(existing[phone ? 0 : 3].hypocenter), findsOneWidget);
      provider.selectHistoryMapProducts(null);
      await tester.pump();
      expect(find.text(selected.location), findsNothing);
      expect(provider.unifiedDisplayEvents, existing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      mapState.dispose();
    });
  }
}
