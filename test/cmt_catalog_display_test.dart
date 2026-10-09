import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/cmt_catalog.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/fssn_cmt_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/cmt_badge.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';

import 'usgs_shakemap_test.dart' show eventFor, readJson;

Map<String, QuakeMessage> capturedSolutions() => {
  for (final group
      in jsonDecode(
            File(
              'test/fixtures/cmt_history_20261009.original.json',
            ).readAsStringSync(encoding: utf8),
          )
          as List)
    for (final row in group['rows'] as List)
      group['source'] as String: QuakeMessage.fromMap(
        Map<String, dynamic>.from(row),
      ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    for (final bucket in EqlistManager().getAllBuckets().values) {
      bucket.clear();
    }
  });
  tearDown(() {
    SoundEffectService().enabled = true;
    for (final bucket in EqlistManager().getAllBuckets().values) {
      bucket.clear();
    }
  });

  test(
    'real mechanisms have their own rows and repeated delivery stays one row',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      var alerts = 0;
      provider.onUnifiedEventNotified = (_, _) => alerts++;
      final originals = capturedSolutions();
      for (var pass = 0; pass < 2; pass++) {
        for (final entry in originals.entries) {
          provider.handleUnifiedEventForTest(
            QuakeEventAdapter.catalogInfo(entry.value, entry.key),
          );
        }
      }
      expect(provider.historyList, hasLength(originals.length));
      for (final entry in originals.entries) {
        final row = provider.historyBySource[entry.key]!.single;
        expect(row.source, entry.value.source);
        expect(row.eventId, entry.value.eventId);
        expect(row.originTime, entry.value.originTime);
        expect(row.nodalPlane1, entry.value.nodalPlane1);
        expect(row.nodalPlane2, entry.value.nodalPlane2);
        expect(row.centroidDepth, entry.value.centroidDepth);
        expect(row.momentTensor?.toMap(), entry.value.momentTensor?.toMap());
        expect(row.cmtMetadata?.toMap(), entry.value.cmtMetadata?.toMap());
      }
      expect(provider.unifiedEvents, isEmpty);
      expect(alerts, 0);
    },
  );

  test(
    'USGS origin and its CMT retain separate rows with the same original ID',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final cmt = capturedSolutions()['usgsCmt']!;
      final origin = eventFor(readJson('us6000u0xi.detail.original.geojson'));
      expect(origin.eventId, cmt.eventId);
      EqlistManager().upsertBucketItem('usgsEqlist', origin);
      provider.handleUnifiedEventForTest(
        QuakeEventAdapter.catalogInfo(cmt, 'usgsCmt'),
      );
      expect(provider.historyList, hasLength(2));
      expect(provider.historyList.map((e) => e.source).toSet(), {
        QuakeSourceType.usgs,
        QuakeSourceType.usgsCmt,
      });
      provider.selectHistoryMapProducts(cmt);
      final info = provider.unifiedDisplayEvents.single;
      expect(info.source, 'usgsCmt');
      expect(info.rawEvent, same(cmt));
      expect(info.momentTensor?.toMap(), cmt.momentTensor?.toMap());
      provider.toggleSource('usgsCmt');
      expect(provider.historyList.single.source, QuakeSourceType.usgs);
      provider.toggleSource('usgsCmt');
      expect(provider.historyList, hasLength(2));
    },
  );

  testWidgets(
    'CMT list entries reuse mechanism badges and their own source labels',
    (tester) async {
      final provider = (await tester.runAsync(() async => QuakeProvider()))!;
      final mapState = MapStateProvider();
      for (final entry in capturedSolutions().entries) {
        provider.handleUnifiedEventForTest(
          QuakeEventAdapter.catalogInfo(entry.value, entry.key),
        );
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider.value(value: mapState),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(width: 500, height: 550, child: EqlistPanel()),
            ),
          ),
        ),
      );
      expect(find.byType(CmtBadge), findsNWidgets(4));
      for (final event in capturedSolutions().values) {
        expect(find.text(cmtCatalogLabel(event.source)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      mapState.dispose();
    },
  );

  testWidgets('selected historical CMT reuses map beachball instead of cross', (
    tester,
  ) async {
    final event = capturedSolutions()['usgsCmt']!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(event.latitude, event.longitude),
            ),
            children: [HistoryMarkerLayer(event: event)],
          ),
        ),
      ),
    );
    expect(find.byType(FssnCmtLayer), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is HistoryCrossPainter,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
