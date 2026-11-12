import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/models/jma_tsunami_list.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_list_card.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_tsunami_sidebar.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_gauge_marker.dart';
import 'package:flutterrhythmquake/models/tsunami_gauge_plan.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_region_layer.dart';
import 'package:flutterrhythmquake/widgets/map/international_tsunami_layer.dart';

const fixtureRoot = 'test/fixtures/tsunami_presentation_20261023';
Future<TsunamiMessage> decodeCase(Map<String, dynamic> item) async {
  var m = LocalInjectDecoder.decode({
    'source': item['source'],
    'Data': item['Data'],
  }, format: 'whews').tsunamis.single;
  final raw = File(item['original'] as String).readAsStringSync();
  final original = raw.trimLeft().startsWith('<') ? null : jsonDecode(raw);
  if ((m.source == TsunamiSource.ptwc || m.source == TsunamiSource.ntwc) &&
      original is Map &&
      original.containsKey('twcEventID')) {
    final detail = await NativeJmaTsunami.prepareAsync({
      'op': 'noaaDetail',
      'json': jsonEncode(original),
    });
    m = m.copyWith(
      officialDetail: Map<String, dynamic>.from(detail['detail'] as Map),
      areas: [
        for (final a in detail['areas'] as List)
          TsunamiAreaInfo.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
    );
  } else if (m.source == TsunamiSource.incois &&
      original is List &&
      original.isNotEmpty &&
      original.first is Map &&
      (original.first as Map).containsKey('event_info')) {
    final detail = await NativeJmaTsunami.prepareAsync({
      'op': 'incoisDetail',
      'json': jsonEncode(original),
    });
    m = m.copyWith(officialDetail: detail);
  }
  return m.prepareWaveData();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('TsunamiReview');
    font.addFont(
      Future.value(
        ByteData.sublistView(
          File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
        ),
      ),
    );
    await font.load();
  });
  if (!NativeJmaTsunami.supported) {
    test(
      'requires actual native library',
      () {},
      skip: 'Set RQ_STATION_CORE_LIBRARY',
    );
    return;
  }
  final files =
      Directory('$fixtureRoot/cases')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final models = <String, TsunamiMessage>{};
  for (final file in files) {
    final item = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    test('source audit ${item['key']}', () async {
      final original = File(item['original'] as String).readAsBytesSync();
      expect(sha256.convert(original).toString(), item['sha256']);
      final before = jsonEncode(item);
      final m = await decodeCase(item);
      models[item['key'] as String] = m;
      final command = {
        'message': m.toMap(),
        'nowMs': m.reportInstantUtc!.millisecondsSinceEpoch,
      };
      final list = await NativeJmaTsunami.prepareAsync({
        'op': 'internationalProject',
        ...command,
      });
      final side = await NativeJmaTsunami.prepareAsync({
        'op': m.source == TsunamiSource.nmefc
            ? 'nmefcSidebar'
            : 'internationalSidebar',
        ...command,
      });
      expect(side['error'], isNull);
      expect(side['cells'], isNotEmpty);
      for (final g in list['groups'] as List) {
        expect((g as Map)['caption'], startsWith(m.source.displayLabel));
        JmaTsunamiListGroup.fromMap(g);
      }
      if (m.isCancellation) {
        expect(list['groups'], isEmpty);
      }
      if (item['key'] == 'ntwc_t06p1k_12') {
        expect(side['stationCount'], 298);
        expect(
          (side['cells'] as List)
              .where((v) => (v as Map)['observation'] is Map)
              .length,
          30,
        );
      }
      if (item['key'] == 'ntwc_t06p1k_16')
        expect(
          (side['cells'] as List)
              .where((v) => (v as Map)['observation'] is Map)
              .length,
          36,
        );
      if (item['key'] == 'incois_incois2025otqm_3') {
        expect(side['stationCount'], 3);
        final station = (m.waveData['stations'] as List).first as Map;
        expect(station['stationName'], '21416');
        expect(station['latitude'], 48);
        expect(station['longitude'], 163.49);
        expect(station['observed']['value'], '0.90');
        expect(station['observed']['metres'], isNull);
      }
      if (item['key'] == 'nmefc_20240403_3') {
        expect(m.observations.single.maxWaveHeightMeters, .3);
        expect(m.areas.first.description, '100-300cm');
        expect((list['groups'] as List).first['className'], 'orange');
      }
      expect(jsonEncode(item), before);
      expect(File(item['original'] as String).readAsBytesSync(), original);
    });
  }
  test('export audited models without changing raw source fields', () async {
    final p = Directory('tmp/tsunami_sidebar_20261023/models')
      ..createSync(recursive: true);
    for (final item in models.entries) {
      File(
        '${p.path}/${item.key}.json',
      ).writeAsStringSync(jsonEncode(item.value.toMap()));
    }
    expect(models.values.map((m) => m.source).toSet().length, 6);
  });
  test(
    'right sidebar visibility restores and persists independently of source models',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      UiRuntimeFlags.restoreTsunamiSidebarVisible(prefs);
      expect(UiRuntimeFlags.tsunamiSidebarVisibleNotifier.value, true);
      final before = jsonEncode(models['nmefc_20240403_3']!.toMap());
      await UiRuntimeFlags.setTsunamiSidebarVisible(false);
      expect(prefs.getBool(UiRuntimeFlags.tsunamiSidebarVisibleKey), false);
      UiRuntimeFlags.tsunamiSidebarVisibleNotifier.value = true;
      UiRuntimeFlags.restoreTsunamiSidebarVisible(prefs);
      expect(UiRuntimeFlags.tsunamiSidebarVisibleNotifier.value, false);
      expect(jsonEncode(models['nmefc_20240403_3']!.toMap()), before);
      await UiRuntimeFlags.setTsunamiSidebarVisible(true);
    },
  );
  testWidgets(
    'original no-threat reports use standard one-unit cells and move down below newer quake reports',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final info = models['incois_incois2025otqm_3']!;
      final prepared = await tester.runAsync(
        () => NativeJmaTsunami.prepareAsync({
          'op': 'internationalProject',
          'message': info.toMap(),
        }),
      );
      final group = JmaTsunamiListGroup.fromMap(
        (prepared!['groups'] as List).single as Map,
      );
      expect(group.pinned, false);
      expect(group.informationText, '印度沿岸无海啸威胁');
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      final mapState = MapStateProvider();
      final manager = EqlistManager();
      await tester.runAsync(() => provider.eewHistoryReadyForTest);
      addTearDown(() => manager.updateCwaList([]));
      provider.internationalTsunamiListenable.value = [group];
      // Real source earthquake parameters and original source clocks, not invented events.
      QuakeMessage quake(TsunamiMessage m) => QuakeMessage(
        source: QuakeSourceType.cwa,
        eventId: m.eventId,
        location: m.epicenterName,
        magnitude: m.magnitude!,
        latitude: m.epicenterLat!,
        longitude: m.epicenterLng!,
        depth: m.depth!,
        originTime: DateTime.parse(m.originTime),
        timeZone: m.timeZone,
        isHistory: true,
        isInfoEvent: true,
      );
      final older = quake(models['cwa_113003_1']!);
      final newer = quake(models['captured_oct_cwa_tsunami']!);
      manager.updateCwaList([older]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: mapState),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'TsunamiReview',
              ),
            ),
            home: const Scaffold(body: EqlistPanel()),
          ),
        ),
      );
      Future<void> ready() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
      }

      await ready();
      final compact = find.byKey(ValueKey('jma_tsunami_${group.key}'));
      final oldCard = find.byKey(
        ValueKey('catalog_${older.source.name}_${older.eventId}'),
      );
      final infoCell = find.byKey(
        ValueKey('jma_tsunami_cell_${group.grade}_1'),
      );
      expect(infoCell, findsOneWidget);
      expect(tester.getSize(infoCell).height, closeTo(76 * 1600 / 1700, .1));
      expect(
        tester.getTopLeft(compact).dy,
        lessThan(tester.getTopLeft(oldCard).dy),
      );
      manager.updateCwaList([newer, older]);
      await ready();
      final newCard = find.byKey(
        ValueKey('catalog_${newer.source.name}_${newer.eventId}'),
      );
      expect(
        tester.getTopLeft(newCard).dy,
        lessThan(tester.getTopLeft(compact).dy),
      );
      expect(
        tester.getTopLeft(compact).dy,
        lessThan(tester.getTopLeft(oldCard).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      mapState.dispose();
    },
  );
  testWidgets(
    'original coastal gauges keep true anchors without displaced grid labels',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      final now = DateTime.now();
      final messages = [
        for (final key in ['cwa_113003_1', 'nmefc_20240403_3'])
          // Mock display envelope only. Source geometry, places, readings and their times stay original.
          models[key]!.copyWith(
            reportTime: now.toIso8601String(),
            expires: now.add(const Duration(hours: 1)).toIso8601String(),
          ),
      ];
      final controllers = [for (final _ in messages) MapController()];
      for (final c in controllers) {
        addTearDown(c.dispose);
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'TsunamiReview',
            ),
            home: Scaffold(
              body: Row(
                children: [
                  for (var index = 0; index < messages.length; index++)
                    Expanded(
                      child: FlutterMap(
                        mapController: controllers[index],
                        options: const MapOptions(
                          initialCenter: LatLng(24, 122),
                          initialZoom: 5,
                          backgroundColor: Color(0xFF202124),
                        ),
                        children: [
                          InternationalTsunamiLayer(
                            tsunami: messages[index],
                            showObservations: false,
                          ),
                          TsunamiRegionLayer(tsunami: messages[index]),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(TsunamiGaugeMarker).evaluate().length >= 8) break;
      }
      final cwa = find.byWidgetPredicate(
        (w) =>
            w is TsunamiGaugeMarker &&
            (w.key as ValueKey<String>).value.startsWith('tsunami_gauge_cwa_'),
      );
      final nmefc = find.byWidgetPredicate(
        (w) =>
            w is TsunamiGaugeMarker &&
            (w.key as ValueKey<String>).value.startsWith(
              'tsunami_gauge_nmefc_',
            ),
      );
      expect(cwa, findsOneWidget);
      expect(nmefc, findsOneWidget);
      expect(tester.widget<TsunamiGaugeMarker>(cwa).data.members.length, 6);
      expect(tester.widget<TsunamiGaugeMarker>(nmefc).data.members.length, 2);
      void trueAnchors() {
        for (final layer in tester.widgetList<MarkerLayer>(
          find.byType(MarkerLayer),
        )) {
          for (final marker in layer.markers.where(
            (m) => m.child is FittedBox,
          )) {
            expect(marker.alignment, const Alignment(0, -0.3714285714));
          }
        }
      }

      trueAnchors();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File(
          'tmp/tsunami_sidebar_20261023/default-zoom-gauges.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
      for (final c in controllers) {
        c.move(const LatLng(24, 122), 5.6);
      }
      await tester.pump();
      trueAnchors();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'INCOIS no-threat and single NTWC CAT reports use standard one-unit cards',
    (tester) async {
      tester.view.physicalSize = const Size(1230, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final samples = <JmaTsunamiListGroup>[];
      for (final key in [
        'incois_incois2025otqm_3',
        'ntwc_t06p1k_12',
        'cat_BOLETIN_SEGUIMIENTO_007_20250730_070828',
      ]) {
        final view = await tester.runAsync(
          () => NativeJmaTsunami.prepareAsync({
            'op': 'internationalProject',
            'message': models[key]!.toMap(),
          }),
        );
        samples.add(
          (view!['groups'] as List)
              .map((v) => JmaTsunamiListGroup.fromMap(v as Map))
              .firstWhere((g) => g.rows.length == 1),
        );
      }
      final capture = GlobalKey();
      for (final width in [220.0, 330.0, 400.0]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamily: 'TsunamiReview',
              ),
              home: Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in samples)
                      SizedBox(
                        width: width,
                        child: JmaTsunamiListCard(
                          key: ValueKey(g.key),
                          group: g,
                          scale: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
          if (find
                  .byWidgetPredicate(
                    (w) =>
                        w.key is ValueKey<String> &&
                        (w.key as ValueKey<String>).value.startsWith(
                          'jma_tsunami_cell_',
                        ),
                  )
                  .evaluate()
                  .length ==
              3)
            break;
        }
        for (final g in samples) {
          final cell = find.descendant(
            of: find.byKey(ValueKey(g.key)),
            matching: find.byKey(ValueKey('jma_tsunami_cell_${g.grade}_1')),
          );
          expect(
            cell,
            findsOneWidget,
            reason: '${g.source} should use one unit at width $width',
          );
          expect(tester.getSize(cell).height, 76);
          final box =
              tester.widget<Container>(cell).decoration as BoxDecoration;
          expect(box.border, isNotNull);
        }
        expect(tester.takeException(), isNull);
        if (width == 400)
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1.5);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            File(
              'tmp/tsunami_sidebar_20261023/one-unit-cards-verified.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'six sources keep independent list state; cancellation removes only its source',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      addTearDown(provider.dispose);
      await provider.eewHistoryReadyForTest;
      final picked = <TsunamiSource, TsunamiMessage>{
        for (final m in models.values) m.source: m,
      };
      for (final m in picked.values) {
        provider.handleTsunamiEventForTest(
          m.copyWith(
            reportTime: DateTime.now().toIso8601String(),
            expires: DateTime.now()
                .add(const Duration(hours: 1))
                .toIso8601String(),
            isInitialSnapshot: true,
          ),
        );
      }
      await provider.internationalTsunamiListReadyForTest;
      expect(
        provider.internationalTsunamiListenable.value
            .map((g) => g.source)
            .toSet()
            .length,
        6,
      );
      final m = picked[TsunamiSource.ntwc]!;
      provider.handleTsunamiEventForTest(
        TsunamiMessage(
          source: m.source,
          timeZone: m.timeZone,
          eventId: m.eventId,
          reportTime: DateTime.now()
              .add(const Duration(seconds: 1))
              .toIso8601String(),
          bulletinLevel: 'cancellation',
          isInitialSnapshot: true,
        ),
      );
      await provider.internationalTsunamiListReadyForTest;
      expect(
        provider.internationalTsunamiListenable.value.any(
          (g) => g.source == 'ntwc',
        ),
        false,
      );
      expect(
        provider.internationalTsunamiListenable.value
            .map((g) => g.source)
            .toSet()
            .length,
        5,
      );
    },
  );
  testWidgets(
    'international left card and right viewport render original observations without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = models['ntwc_t06p1k_12']!;
      final view = await tester.runAsync(
        () => NativeJmaTsunami.prepareAsync({
          'op': 'internationalProject',
          'message': m.toMap(),
        }),
      );
      final g = JmaTsunamiListGroup.fromMap(
        (view!['groups'] as List).first as Map,
      );
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: ThemeData(
              fontFamily: 'TsunamiReview',
              brightness: Brightness.dark,
            ),
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: JmaTsunamiListCard(group: g, scale: 1),
                  ),
                  SizedBox(
                    width: 400,
                    height: 440,
                    child: JmaTsunamiSidebar.international(
                      message: m,
                      scale: 1,
                      maxHeight: 440,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find
            .byKey(const ValueKey('jma_tsunami_sidebar_viewport'))
            .evaluate()
            .isNotEmpty)
          break;
      }
      expect(
        find.byKey(const ValueKey('jma_tsunami_sidebar_viewport')),
        findsOneWidget,
      );
      expect(find.text('观测'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final out = File('tmp/tsunami_sidebar_20261023/review-native-font.png');
        out.writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pump(const Duration(seconds: 13));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'compact NMEFC ranges occupy one unit; gauge labels stay readable and source pages continue',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final message = models['nmefc_20240403_3']!;
      final result = await tester.runAsync(
        () => NativeJmaTsunami.prepareAsync({
          'op': 'internationalProject',
          'message': message.toMap(),
        }),
      );
      final groups = [
        for (final g in result!['groups'] as List)
          JmaTsunamiListGroup.fromMap(g as Map),
      ];
      expect(groups.first.rows.first.height, '100-300cm');
      final ntwc = models['ntwc_t06p1k_12']!;
      final nativePlan = await tester.runAsync(
        () => NativeJmaTsunami.prepareAsync({
          'op': 'gaugePlan',
          'message': ntwc.toMap(),
        }),
      );
      final plan = TsunamiGaugePlan.fromMap(nativePlan!);
      final gauge = plan.markers.firstWhere((v) => v.observedFraction != null);
      final bucket = PageStorageBucket(), capture = GlobalKey();
      Widget page() => RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: 'TsunamiReview',
            brightness: Brightness.dark,
          ),
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 400,
                    child: Column(
                      children: [
                        for (final g in groups)
                          JmaTsunamiListCard(group: g, scale: 1),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 290,
                    height: 300,
                    child: JmaTsunamiSidebar.international(
                      message: ntwc,
                      scale: 1,
                      maxHeight: 300,
                    ),
                  ),
                  SizedBox(
                    width: 290,
                    height: 300,
                    child: JmaTsunamiSidebar.international(
                      message: models['incois_incois2025otqm_3']!,
                      scale: 1,
                      maxHeight: 300,
                    ),
                  ),
                  SizedBox(
                    width:
                        TsunamiGaugeMarker.markerWidth *
                        TsunamiGaugeMarker.scaleAtZoom(5),
                    height:
                        TsunamiGaugeMarker.markerHeight *
                        TsunamiGaugeMarker.scaleAtZoom(5),
                    child: FittedBox(child: TsunamiGaugeMarker(data: gauge)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> ready() async {
        for (var i = 0; i < 90; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (find
                  .byKey(const ValueKey('jma_tsunami_cell_warning_1'))
                  .evaluate()
                  .isNotEmpty &&
              find
                      .byKey(const ValueKey('jma_tsunami_sidebar_page'))
                      .evaluate()
                      .length ==
                  2)
            break;
        }
      }

      await tester.pumpWidget(page());
      await ready();
      expect(
        find.byKey(const ValueKey('jma_tsunami_cell_warning_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('jma_tsunami_cell_watch_1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final pageText = tester
          .widgetList<Text>(
            find.byKey(const ValueKey('jma_tsunami_sidebar_page')),
          )
          .map((v) => v.data)
          .toList();
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File(
          'tmp/tsunami_sidebar_20261023/review-compact-comparison.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page());
      await ready();
      final resumed = tester
          .widgetList<Text>(
            find.byKey(const ValueKey('jma_tsunami_sidebar_page')),
          )
          .map((v) => v.data)
          .toList();
      expect(resumed, isNot(pageText));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        TsunamiGaugeMarker.bodyHeight * TsunamiGaugeMarker.scaleAtZoom(5),
        closeTo(50, 1),
      );
    },
  );
  for (final key in [
    'nmefc_20240403_3',
    'cwa_114005_4',
    'ptwc_25210002_4',
    'ntwc_t06p1k_16',
    'incois_incois2025otqm_3',
    'cat_BOLETIN_SEGUIMIENTO_007_20250730_070828',
  ]) {
    testWidgets('original $key fits compact right sidebar and left card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final m = models[key]!;
      final view = await tester.runAsync(
        () => NativeJmaTsunami.prepareAsync({
          'op': 'internationalProject',
          'message': m.toMap(),
        }),
      );
      final g = JmaTsunamiListGroup.fromMap(
        (view!['groups'] as List).first as Map,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 390,
                  child: JmaTsunamiListCard(group: g, scale: 1),
                ),
                SizedBox(
                  width: 290,
                  height: 300,
                  child: JmaTsunamiSidebar.international(
                    message: m,
                    scale: 1,
                    maxHeight: 300,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find
            .byKey(const ValueKey('jma_tsunami_sidebar_viewport'))
            .evaluate()
            .isNotEmpty)
          break;
      }
      expect(
        find.byKey(const ValueKey('jma_tsunami_sidebar_viewport')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 13));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final key in [
    'cat_BOLETIN_SEGUIMIENTO_007_20250730_070828',
    'ptwc_25210002_4',
    'ntwc_t06p1k_12',
    'incois_incois2025otqm_3',
    'nmefc_20240403_3',
    'cwa_113003_1',
  ]) {
    for (final height in [260.0, 320.0]) {
      testWidgets(
        'full right shell $key at height $height uses real font on every page',
        (tester) async {
          tester.view.physicalSize = const Size(1100, 750);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final item =
              jsonDecode(
                    File('$fixtureRoot/cases/$key.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          final m = (await tester.runAsync(() => decodeCase(item)))!;
          final shellCapture = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'TsunamiReview',
                brightness: Brightness.dark,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: shellCapture,
                  child: SizedBox(
                    width: 290,
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 7,
                              ),
                              child: LayoutBuilder(
                                builder: (context, c) =>
                                    JmaTsunamiSidebar.international(
                                      message: m,
                                      scale: .94,
                                      maxHeight: c.maxHeight,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          const SizedBox(
                            height: 60,
                            child: Text(
                              '长期地震动观测 (beta)\n最大 SVA: 0.049  最大阶级: 0',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 80; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump();
            if (find
                .byKey(const ValueKey('jma_tsunami_sidebar_page'))
                .evaluate()
                .isNotEmpty)
              break;
          }
          expect(
            find.byKey(const ValueKey('jma_tsunami_sidebar_page')),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$key first page within complete sidebar',
          );
          if (key.startsWith('cat_') && height == 260) {
            await tester.runAsync(() async {
              final image =
                  await (shellCapture.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              File(
                'tmp/tsunami_sidebar_20261023/cat-full-sidebar-fixed.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            });
          }
          final count = int.parse(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('jma_tsunami_sidebar_page')),
                )
                .data!
                .split('/')
                .last,
          );
          for (var i = 1; i < count; i++) {
            await tester.pump(const Duration(seconds: 12));
            expect(
              tester.takeException(),
              isNull,
              reason: '$key page ${i + 1}/$count',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
