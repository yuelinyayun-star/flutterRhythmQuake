import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/render_information_loader.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/map_config.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'package:flutterrhythmquake/widgets/ui/event_render_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/unified_ui_fonts.dart';

const fixtureRoot = 'test/fixtures/event_render_20261104';
dynamic original(String name) => jsonDecode(
  File('$fixtureRoot/$name.original.json').readAsStringSync(encoding: utf8),
);
final out = Directory('tmp/event_render_fixes_20261104');

class _Saver extends FilePicker {
  String? requestedName;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    requestedName = fileName;
    return '${out.absolute.path}/$fileName';
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    out.createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => out.absolute.path,
        );
  });
  Future<void> fonts(WidgetTester tester) => tester
      .runAsync(() async {
        await loadUnifiedUiFonts();
        // CustomPainter text has no inherited Theme. Replace the test-only
        // default Ahem glyphs with the app font for actual preview inspection.
        await (FontLoader('Ahem')..addFont(
              rootBundle.load('assets/fonts/MPLUSRounded1c-Regular.ttf'),
            ))
            .load();
        await (FontLoader('JetBrainsMono')..addFont(
              rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf'),
            ))
            .load();
        await VectorBasemapService.instance.load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await AppPageBackground.cachedBytes();
      })
      .then((_) {});

  for (final kind in ['jma', 'cenc']) {
    testWidgets(
      'original user $kind report: observed distribution, aligned stroke, product, export',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 850);
        tester.view.devicePixelRatio = 1;
        await fonts(tester);
        final provider = QuakeProvider(
          startCatalogServices: false,
          nativeUnifiedEvents: true,
        );
        await tester.runAsync(() => provider.eewHistoryReadyForTest);
        final state = MapStateProvider();
        final background = PageBackgroundProvider();
        final jma = QuakeEventAdapter.convertWolfxJmaEqlist(
          Map<String, dynamic>.from(original('wolfx-jma')),
        ).firstWhere((row) => row.originTime == DateTime(2026, 11, 4, 7, 28));
        final cenc = QuakeEventAdapter.convertWolfxCencEqlist(
          Map<String, dynamic>.from(original('wolfx-cenc')),
        ).firstWhere((row) => row.location == '吉尔吉斯斯坦');
        final row = kind == 'jma' ? jma : cenc;
        final event = provider.informationMapEventFor(row);
        expect(event.warnArea, isEmpty);
        if (kind == 'cenc')
          expect(UnifiedEventPresentation.fromEvent(event).title, '中国地震台网地震信息');
        state.selectHistoryEvent(kind == 'jma' ? cenc : jma);
        provider.selectHistoryMapProducts(state.selectedHistoryEvent);
        final selection = provider.historyInfoDisplayEvent;
        final rawBefore = jsonEncode(event.toMap());
        var alerts = 0;
        provider.onUnifiedEventNotified = (_, _) => alerts++;
        final requested = <Uri>[];
        final loader = RenderInformationLoader(
          client: MockClient((request) async {
            requested.add(request.url);
            final name = request.url.host == 'api.p2pquake.net'
                ? 'p2p'
                : request.url.path.startsWith('/event/')
                ? 'cenc-ir-detail'
                : 'cenc-ir';
            return http.Response.bytes(
              File('$fixtureRoot/$name.original.json').readAsBytesSync(),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: state),
              ChangeNotifierProvider<PageBackgroundProvider>.value(
                value: background,
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: unifiedUiTestTheme(),
              home: EventRenderPage(
                event: event,
                informationLoader: loader,
                eventMatcher: provider.matchesInformationRenderEvent,
                cencIrMatcher: provider.informationRenderCencIrBinding,
              ),
            ),
          ),
        );
        await settle(tester);
        if (kind == 'cenc') {
          expect(
            tester
                .widget<GestureDetector>(
                  find.byKey(
                    const ValueKey('render_toggle_region_distribution'),
                  ),
                )
                .onTap,
            isNull,
          );
          expect(find.text('中国地震台网地震信息'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('render_product_selector')),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('烈度速报').last);
          await settle(tester);
          expect(find.byType(CencIrLayer), findsOneWidget);
          expect(
            tester
                .widget<CencIrLayer>(find.byType(CencIrLayer))
                .data!
                .instrumentIntensities,
            hasLength(32),
          );
          expect(find.text('中国地震台网烈度速报'), findsOneWidget);
          expect(find.textContaining('最大仪器烈度'), findsOneWidget);
        } else {
          expect(find.text('震度 1'), findsOneWidget);
          expect(find.textContaining('熊本県熊本'), findsWidgets);
          final fill = tester.widget<IntensityFillLayer>(
            find.byType(IntensityFillLayer),
          );
          final areas = jsonDecode(fill.warnAreaJson) as List;
          expect(areas, hasLength(1));
          expect(areas.single['intensity'], '1');
          final front = tester.renderObject<RenderParagraph>(
            find.byKey(const ValueKey('render_header_intensity_text')),
          );
          final stroke = tester.renderObject<RenderParagraph>(
            find.byKey(const ValueKey('render_stroke_最大震度 1')),
          );
          expect(stroke.size, front.size);
          expect(
            stroke.localToGlobal(Offset.zero),
            front.localToGlobal(Offset.zero),
          );
          final selection = TextSelection(
            baseOffset: 0,
            extentOffset: front.text.toPlainText().length,
          );
          expect(
            stroke.getBoxesForSelection(selection).map((b) => b.toRect()),
            front.getBoxesForSelection(selection).map((b) => b.toRect()),
          );
        }
        expect(
          find.byKey(const ValueKey('render_region_distribution_section')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('render_toggle_region_distribution')),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('render_region_distribution_section')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('render_toggle_region_distribution')),
        );
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('render_canvas_repaint')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${out.path}/$kind-fixed.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
        final saver = _Saver();
        FilePicker.platform = saver;
        await tester.tap(find.byKey(const ValueKey('render_save_image')));
        await settle(tester);
        expect(saver.requestedName, contains(row.location));
        await tester.runAsync(() async {
          final file = File('${out.path}/${saver.requestedName}');
          expect(file.existsSync(), isTrue);
          final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1600);
          expect(frame.image.height, 900);
          frame.image.dispose();
          codec.dispose();
        });
        await tester.tap(find.byKey(const ValueKey('render_aspect_4_3')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('render_save_image')));
        await settle(tester);
        await tester.runAsync(() async {
          final file = File('${out.path}/${saver.requestedName}');
          expect(file.existsSync(), isTrue);
          final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1600);
          expect(frame.image.height, 1200);
          frame.image.dispose();
          codec.dispose();
        });
        await tester.tap(find.byKey(const ValueKey('render_aspect_16_9')));
        await settle(tester);
        expect(provider.historyInfoDisplayEvent, same(selection));
        expect(provider.unifiedEvents, isEmpty);
        expect(alerts, 0);
        expect(jsonEncode(event.toMap()), rawBefore);
        // Basemap control is renderer-local; selecting a raster then returning
        // to vector must not change the main map or refit the event.
        final mainTile = state.tileKey;
        final mapBefore = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera;
        final selector = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('render_basemap_selector')),
        );
        selector.onChanged!('petalLight');
        await tester.pump();
        expect(
          tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
          MapConfig.petalLight,
        );
        expect(state.tileKey, mainTile);
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('render_basemap_selector')),
            )
            .onChanged!(MapConfig.vectorBasemapKey);
        await tester.pump();
        final mapAfter = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!
            .camera;
        debugPrint('BASEMAP_CAMERA $kind before=${mapBefore.center}/${mapBefore.zoom}/${mapBefore.nonRotatedSize} after=${mapAfter.center}/${mapAfter.zoom}/${mapAfter.nonRotatedSize}');
        expect(mapAfter.center, mapBefore.center);
        expect(mapAfter.zoom, mapBefore.zoom);
        final controller = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!;
        var closed = false;
        final subscription = controller.mapEventStream.listen(
          (_) {},
          onDone: () => closed = true,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        expect(closed, isTrue);
        await tester.runAsync(subscription.cancel);
        provider.dispose();
        state.dispose();
        background.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        expect(tester.takeException(), isNull);
        debugPrint(
          'RENDER_FIX_VERIFIED $kind requests=${requested.length} PNG=1600x900 isolated=true',
        );
      },
    );
  }
  testWidgets('production LPGM class 4 retains actual shindo 7 in renderer', (
    tester,
  ) async {
    final provider = QuakeProvider(
      startCatalogServices: false,
      nativeUnifiedEvents: true,
    );
    await tester.runAsync(() => provider.eewHistoryReadyForTest);
    final now = DateTime.now().toUtc();
    provider.acceptJmaLpgm(
      JmaLpgmBulletin(
        eventId: 'lpgm-render-regression',
        serial: 1,
        infoType: '発表',
        headline: '長周期地震動に関する観測情報',
        maxInt: '7',
        maxLgInt: 4,
        lgCategory: '1',
        originTime: now.subtract(const Duration(minutes: 5)),
        reportTime: now,
        latitude: 35,
        longitude: 140,
        depthKm: 20,
        magnitude: 6.2,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    final event = provider.unifiedEvents.single;
    expect(event.maxIntensity, '4');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 492,
            height: 834,
            child: RenderRightSidebarPanel(
              event: event,
              fillSummary: InformationFillSummary.empty,
            ),
          ),
        ),
      ),
    );
    expect(find.text('最大震度 7'), findsOneWidget);
    expect(find.text('长周期 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
