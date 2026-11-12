import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/history_map_product.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_layer.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'usgs_dyfi_test.dart'
    show
        dyfiDetail,
        dyfiEvent,
        originalDetail,
        dyfiGridResponse,
        emptyDyfiDetail;
import 'support/unified_ui_fonts.dart';

class DyfiDisplayProvider extends QuakeProvider {
  DyfiDisplayProvider(UsgsDyfiService service, this.rows, this.cards)
    : super(
        dyfiService: service,
        startCatalogServices: false,
        shakeMapService: UsgsShakeMapService(
          client: MockClient((_) async => http.Response('', 404)),
        ),
      );
  final List<QuakeMessage> rows;
  final List<UnifiedQuakeData> cards;
  @override
  List<QuakeMessage> get historyList => rows;
  @override
  Map<String, List<QuakeMessage>> get historyBySource => {'usgsEqlist': rows};
  @override
  List<UnifiedQuakeData> get unifiedEvents => cards;
  @override
  UnifiedQuakeData? get mobileCameraDisplayEvent => cards.firstOrNull;
}

Future<void> saveDyfiRender(WidgetTester tester, Key key, String name) async {
  if (!const bool.fromEnvironment('DYFI_RENDER')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/ui-previews/dyfi').create(recursive: true);
    await File(
      'build/ui-previews/dyfi/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  for (final width in [390.0, 1266.0]) {
    testWidgets('Panama empty DYFI list and unified UI at width $width', (
      tester,
    ) async {
      await tester.runAsync(loadUnifiedUiFonts);
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = emptyDyfiDetail();
      final event = dyfiEvent(detail);
      final grid = File(
        'test/fixtures/usgs_dyfi/us6000u1em.dyfi_geo_10km.original.geojson',
      ).readAsBytesSync();
      final service = UsgsDyfiService(
        client: MockClient(
          (request) async => request.url.path.endsWith('.geojson')
              ? http.Response.bytes(grid, 200)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      final provider = DyfiDisplayProvider(service, [event], []);
      final state = MapStateProvider();
      await service.observe([event]);
      Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: state),
        ],
        child: MaterialApp(
          theme: unifiedUiTestTheme(),
          home: Scaffold(
            backgroundColor: const Color(0xFF242424),
            body: Center(child: child),
          ),
        ),
      );
      const capture = ValueKey('dyfi-empty-capture');
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: capture,
            child: SizedBox(
              width: width < 600 ? 390 : 446,
              height: 440,
              child: EqlistPanel(embedded: width < 600),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('收到 1 份报告'), findsOneWidget);
      expect(find.text('CDI 未知'), findsOneWidget);
      expect(find.text('暂无可绘制体感网格'), findsOneWidget);
      expect(find.text('0 个体感网格 · 10 km'), findsOneWidget);
      expect(find.byType(UsgsDyfiMiniMap), findsNothing);
      expect(find.textContaining('加载失败'), findsNothing);
      expect(tester.takeException(), isNull);
      await saveDyfiRender(tester, capture, 'dyfi-empty-list-${width.toInt()}');
      provider.selectHistoryMapProducts(event, product: HistoryMapProduct.dyfi);
      await tester.pump();
      final card = provider.historyInfoDisplayEvent!;
      expect(card.maxIntensity, '未知');
      expect(card.className, 'gray');
      expect(card.sourcePayload!['properties']['maxmmi'], '0.0');
      await tester.pumpWidget(
        host(RepaintBoundary(key: capture, child: const AlertModule())),
      );
      await tester.pump();
      expect(find.text('未知'), findsOneWidget);
      expect(find.text('收到 1 份报告'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await saveDyfiRender(
        tester,
        capture,
        'dyfi-empty-unified-${width.toInt()}',
      );
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 350,
            height: 450,
            child: FlutterMap(children: [UsgsDyfiLayer(frame: service.frame)]),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('暂无可绘制体感网格'), findsOneWidget);
      expect(find.textContaining('最高 CDI 未知'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      state.dispose();
      await tester.pump(const Duration(seconds: 1));
    });
  }

  test(
    'USGS magnitude setting filters DYFI manual and automatic UI together',
    () {
      fakeAsync((clock) {
        var detail = dyfiDetail();
        final service = UsgsDyfiService(
          client: MockClient(
            (r) async => r.url.path.endsWith('.geojson')
                ? dyfiGridResponse(r.url)
                : http.Response(jsonEncode(detail), 200),
          ),
        );
        final provider = QuakeProvider(
          startCatalogServices: false,
          dyfiService: service,
          shakeMapService: UsgsShakeMapService(
            client: MockClient((_) async => http.Response('', 404)),
          ),
        );
        clock.flushMicrotasks();
        var event = dyfiEvent(detail);
        unawaited(service.observe([event]));
        clock.flushMicrotasks();
        detail = dyfiDetail(210);
        event = dyfiEvent(detail);
        unawaited(service.observe([event]));
        clock.flushMicrotasks();
        expect(service.automaticFrame?.product.responses, 210);
        provider.selectHistoryMapProducts(
          event,
          product: HistoryMapProduct.dyfi,
        );
        clock.flushMicrotasks();
        provider.setSourceInfoMagFilter(QuakeSourceType.usgs, event.magnitude);
        clock.flushMicrotasks();
        expect(provider.dyfiInfoDisplayEvent, isNotNull);
        expect(provider.historyInfoDisplayEvent?.source, 'usgsDyfi');
        provider.setSourceInfoMagFilter(
          QuakeSourceType.usgs,
          event.magnitude + .1,
        );
        clock.flushMicrotasks();
        expect(service.frameFor(event), isNull);
        expect(service.frame, isNull);
        expect(provider.dyfiInfoDisplayEvent, isNull);
        expect(provider.historyInfoDisplayEvent, isNull);
        provider.setSourceInfoMagFilter(QuakeSourceType.usgs, 0);
        clock.flushMicrotasks();
        expect(service.frameFor(event), isNotNull);
        expect(provider.historyInfoDisplayEvent?.source, 'usgsDyfi');
        provider.setSourceInfoMagFilter(QuakeSourceType.usgs, -1);
        clock.flushMicrotasks();
        expect(service.frame, isNull);
        expect(service.frameFor(event), isNull);
        expect(provider.unifiedDisplayEvents, isEmpty);
        provider.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'manual DYFI, another USGS quake and automatic DYFI have separate lifetimes',
    () {
      fakeAsync((clock) {
        var detail = originalDetail('us6000u0xi');
        final old = dyfiEvent(detail), current = dyfiEvent(dyfiDetail());
        final service = UsgsDyfiService(
          client: MockClient(
            (r) async => r.url.path.endsWith('.geojson')
                ? dyfiGridResponse(r.url)
                : http.Response(jsonEncode(detail), 200),
          ),
        );
        final provider = DyfiDisplayProvider(
          service,
          [current, old],
          [QuakeEventAdapter.catalogInfo(current, 'usgsEqlist')],
        );
        var alerts = 0;
        provider.onUnifiedEventNotified = (_, _) => alerts++;
        unawaited(service.observe([old]));
        clock.flushMicrotasks();
        provider.selectHistoryMapProducts(old, product: HistoryMapProduct.dyfi);
        clock.flushMicrotasks();
        expect(provider.historyInfoDisplayEvent?.source, 'usgsDyfi');
        expect(provider.unifiedDisplayEvents.map((e) => e.source), [
          'usgsDyfi',
          'usgsEqlist',
        ]);
        expect(provider.unifiedDisplayEvents.last.rawEvent, same(current));
        detail = dyfiDetail(210);
        unawaited(service.observe([old, dyfiEvent(detail)]));
        clock.flushMicrotasks();
        expect(provider.unifiedDisplayEvents, hasLength(3));
        expect(provider.dyfiInfoDisplayEvent?.eventId, current.eventId);
        expect(provider.historyInfoDisplayEvent?.eventId, old.eventId);
        final productCard = provider.dyfiInfoDisplayEvent!;
        final presentation = UnifiedEventPresentation.fromEvent(productCard);
        expect(presentation.intensityLabel, 'CDI');
        expect(presentation.intensityValue, '3.5');
        expect(presentation.secondaryText, '收到 210 份报告');
        expect(presentation.timeText, startsWith('更新 '));
        expect(productCard.originTime, dyfiEvent(detail).originTime);
        expect(
          productCard.sourcePayload,
          detail['properties']['products']['dyfi'][0],
        );
        expect(alerts, 0);
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(provider.dyfiInfoDisplayEvent, isNull);
        expect(provider.unifiedDisplayEvents, hasLength(2));
        expect(service.manualFrame?.event.eventId, old.eventId);
        provider.selectHistoryMapProducts(null);
        clock.flushMicrotasks();
        expect(provider.unifiedDisplayEvents.single.rawEvent, same(current));
        expect(alerts, 0);
        provider.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'same-event ordinary quake and DYFI have independent selected states',
    () {
      final event = dyfiEvent(dyfiDetail());
      final state = MapStateProvider();
      state.selectHistoryEvent(event);
      expect(state.isSelectedHistoryEvent(event), isTrue);
      expect(
        state.isSelectedHistoryEvent(event, product: HistoryMapProduct.dyfi),
        isFalse,
      );
      state.selectHistoryEvent(event, product: HistoryMapProduct.dyfi);
      expect(state.isSelectedHistoryEvent(event), isFalse);
      expect(
        state.isSelectedHistoryEvent(event, product: HistoryMapProduct.dyfi),
        isTrue,
      );
      state.clearSelectedHistoryEvent();
      expect(state.selectedHistoryEvent, isNull);
      expect(state.selectedHistoryProduct, HistoryMapProduct.earthquake);
      state.dispose();
    },
  );

  for (final width in [390.0, 935.0, 1266.0, 1578.0, 1700.0]) {
    testWidgets('production list, DYFI map and unified card at width $width', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await loadUnifiedUiFonts();
        await UsgsDyfiMiniMap.prepareOutlines();
        await (FontLoader('MaterialIcons')..addFont(
              File(
                'D:/flutter_windows_3.41.1-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      });
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final detail = dyfiDetail();
      final row = dyfiEvent(detail);
      final service = UsgsDyfiService(
        client: MockClient(
          (r) async => r.url.path.endsWith('.geojson')
              ? dyfiGridResponse(r.url)
              : http.Response(jsonEncode(detail), 200),
        ),
      );
      final provider = DyfiDisplayProvider(service, [row], []);
      final state = MapStateProvider();
      var disposed = false;
      addTearDown(() {
        if (!disposed) {
          provider.dispose();
          state.dispose();
        }
      });
      await service.observe([row]);
      Object? selectionKey;
      state.addListener(() {
        final key = (
          state.selectedHistoryEvent?.eventId,
          state.selectedHistoryProduct,
        );
        if (key == selectionKey) return;
        selectionKey = key;
        provider.selectHistoryMapProducts(
          state.selectedHistoryEvent,
          product: state.selectedHistoryProduct,
        );
      });
      const capture = ValueKey('dyfi-list-capture');
      Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: state),
        ],
        child: MaterialApp(
          theme: unifiedUiTestTheme(),
          home: Scaffold(
            backgroundColor: const Color(0xFF242424),
            body: Center(child: child),
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: capture,
            child: SizedBox(
              width: width < 600 ? 390 : 446,
              height: width < 600 ? 480 : 440,
              child: EqlistPanel(embedded: width < 600),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('收到 191 份报告'), findsOneWidget);
      expect(find.text('15 个体感网格 · 10 km'), findsOneWidget);
      expect(find.byType(UsgsDyfiMiniMap), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(UsgsDyfiMiniMap),
          matching: find.byType(HistoryMarkerLayer),
        ),
        findsNothing,
      );
      await saveDyfiRender(
        tester,
        ValueKey('usgs_group_${row.eventId}'),
        'dyfi-integrated-list-${width.toInt()}',
      );
      await tester.tap(find.byKey(ValueKey('dyfi_list_${row.eventId}')));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect(state.selectedHistoryProduct, HistoryMapProduct.dyfi);
      expect(provider.unifiedDisplayEvents.single.source, 'usgsDyfi');
      expect(find.text('取消显示'), findsOneWidget);
      expect(provider.usgsShakeMap.frame, isNull);
      final frame = service.frame!;
      await tester.pumpWidget(
        host(RepaintBoundary(key: capture, child: const AlertModule())),
      );
      await tester.pump();
      expect(find.text('USGS DYFI 公众体感报告'), findsOneWidget);
      expect(find.text('收到 191 份报告'), findsOneWidget);
      expect(find.text('3.5'), findsOneWidget);
      expect(find.text('CDI'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await saveDyfiRender(
        tester,
        capture,
        'dyfi-integrated-unified-${width.toInt()}',
      );
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 350,
            height: 450,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(frame.focusPoints),
                  padding: const EdgeInsets.all(25),
                ),
              ),
              children: [UsgsDyfiLayer(frame: frame)],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(UsgsDyfiGridLayer), findsOneWidget);
      expect(tester.takeException(), isNull);
      final paint =
          tester
                  .widgetList<CustomPaint>(find.byType(CustomPaint))
                  .firstWhere((w) => w.painter is UsgsDyfiGridPainter)
                  .painter
              as UsgsDyfiGridPainter;
      final shape = paint.shapes.first;
      final point = shape.$2.getBounds().center;
      expect(paint.cellAt(point), same(frame.cells!.first));
      await tester.tapAt(tester.getTopLeft(find.byType(FlutterMap)) + point);
      await tester.pumpAndSettle();
      expect(find.text('DYFI 体感网格'), findsOneWidget);
      expect(find.textContaining('收到 14 份报告'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      state.clearSelectedHistoryEvent();
      await tester.pump();
      expect(provider.historyInfoDisplayEvent, isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      state.dispose();
      disposed = true;
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
