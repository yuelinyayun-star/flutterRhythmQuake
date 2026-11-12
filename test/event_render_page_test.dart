import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/vector_basemap_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:flutterrhythmquake/widgets/ui/event_render_page.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/unified_ui_fonts.dart';

class _DisplayProvider extends QuakeProvider {
  _DisplayProvider(this.report) : super(startCatalogServices: false);
  final UnifiedQuakeData report;
  @override
  List<UnifiedQuakeData> get unifiedEvents => [report];
}

Future<void> _settleRenderLayers(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void _writePngSafe(Directory out, String fileName, Uint8List pngBytes) {
  for (final name in [
    fileName,
    'latest_$fileName',
    'preview_$fileName',
    'framed_$fileName',
    'sig_$fileName',
    'wm_$fileName',
    'dist_$fileName',
    'final_$fileName',
    'dist2_$fileName',
  ]) {
    final target = File('${out.path}/$name');
    try {
      target.writeAsBytesSync(pngBytes);
    } on FileSystemException {
      try {
        if (target.existsSync()) target.deleteSync();
        target.writeAsBytesSync(pngBytes);
      } on FileSystemException {
        // Ignore if currently memory-mapped by IDE image viewer.
      }
    }
  }
}

Future<void> _saveScreenshot(
  WidgetTester tester,
  GlobalKey screenshotKey,
  String fileName,
) async {
  await tester.runAsync(() async {
    final boundary =
        screenshotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('tmp/event_render_window_20261104')
      ..createSync(recursive: true);
    _writePngSafe(out, fileName, bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _saveFinderScreenshot(
  WidgetTester tester,
  Finder finder,
  String fileName,
) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject(finder) as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('tmp/event_render_window_20261104')
      ..createSync(recursive: true);
    _writePngSafe(out, fileName, bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(1280, 850), const Size(390, 844)]) {
    testWidgets(
      'render button opens floating render workspace in both layout modes without selecting at $size',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SoundEffectService().enabled = false;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final raw =
            (jsonDecode(
                      File(
                        'test/fixtures/jma_voice/p2p_history_20260921.json',
                      ).readAsStringSync(encoding: utf8),
                    )
                    as List)
                .cast<Map<String, dynamic>>()
                .firstWhere(
                  (r) =>
                      r['issue']['type'] == 'DetailScale' &&
                      r['earthquake']['time'] == '2026/09/21 22:38:00',
                );
        final original = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
        final provider = _DisplayProvider(original);
        final row = provider.unifiedToQuakeMessageForTest(original);
        final manager = EqlistManager();
        manager.updateJmaList([row]);
        final state = MapStateProvider();
        final background = PageBackgroundProvider();
        final screenshotKey = GlobalKey();
        await tester.runAsync(() async {
          await provider.eewHistoryReadyForTest;
          await loadUnifiedUiFonts();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await AppPageBackground.cachedBytes();
        });
        final originalData = jsonEncode(original.toMap());
        var alerts = 0;
        provider.onUnifiedEventNotified = (_, _) => alerts++;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: state),
              ChangeNotifierProvider<PageBackgroundProvider>.value(
                value: background,
              ),
            ],
            child: RepaintBoundary(
              key: screenshotKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: unifiedUiTestTheme(),
                home: Scaffold(body: EqlistPanel(embedded: size.width < 600)),
              ),
            ),
          ),
        );
        await tester.pump();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text(row.location).first));
        await tester.pump();
        expect(find.text('复制信息'), findsOneWidget);
        expect(find.text('地图显示'), findsOneWidget);
        expect(find.text('渲染事件'), findsOneWidget);
        // The existing map selection is unrelated to the rendering workspace.
        final other = QuakeEventAdapter.convertWolfxCencEqlist(
          Map<String, dynamic>.from(
            jsonDecode(
                  File(
                    'test/fixtures/cenc_history_20261009/wolfx.original.json',
                  ).readAsStringSync(encoding: utf8),
                )
                as Map,
          ),
        ).first;
        state.selectHistoryEvent(other);
        provider.selectHistoryMapProducts(other);
        final selection = provider.historyInfoDisplayEvent;
        await tester.pump();
        await tester.tap(find.text('渲染事件'));
        await tester.pump();
        await _settleRenderLayers(tester);

        final page = tester.widget<EventRenderPage>(
          find.byType(EventRenderPage),
        );
        expect(page.event, same(original));
        expect(page.buildInformationFillLayer().event, same(page.event));
        expect(find.byType(InformationEventFillLayer), findsOneWidget);
        expect(find.byType(VectorBasemapLayer), findsOneWidget);
        expect(find.byType(HistoryMarkerLayer), findsOneWidget);
        expect(find.byKey(const ValueKey('render_map_panel')), findsOneWidget);
        expect(find.byType(RenderMapPanel), findsOneWidget);
        expect(
          find.byKey(const ValueKey('render_right_sidebar_panel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('render_header_title')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('render_header_hypocenter')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('render_header_mag_depth')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('render_header_time')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('render_header_intensity_box')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('render_header_intensity_text')),
              )
              .data,
          '最大震度 3',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('render_canvas_watermark')),
              )
              .data,
          'RhythmQuake绘制',
        );
        expect(
          find.byKey(const ValueKey('render_region_distribution_section')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('render_distribution_title')),
              )
              .data,
          '震度分布',
        );
        expect(find.text('震度 3'), findsOneWidget);
        expect(find.text('震度 2'), findsOneWidget);
        expect(find.text('震度 1'), findsOneWidget);
        expect(find.textContaining('宮崎県北部山沿い'), findsOneWidget);

        // Toggle off and back on.
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
        expect(
          find.byKey(const ValueKey('render_region_distribution_section')),
          findsOneWidget,
        );
        expect(
          RenderRightSidebarPanel(
            event: QuakeEventAdapter.catalogInfo(other, 'cencEqlist'),
            fillSummary: InformationFillSummary.empty,
          ),
          isNotNull,
        );
        final content = find.byKey(const ValueKey('event_render_content'));
        expect(content, findsOneWidget);

        // Verify polygons are painted and epicenter is centered in full-map mode.
        final polygons = tester
            .widgetList<PolygonLayer>(
              find.descendant(
                of: find.byType(IntensityFillLayer),
                matching: find.byType(PolygonLayer),
              ),
            )
            .expand((layer) => layer.polygons)
            .toList();
        expect(polygons.length, 95);

        final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
        final epicenter = LatLng(original.lat!, original.lng!);
        final fullCamera = flutterMap.mapController!.camera;
        final fullEpicenterOffset = fullCamera.getOffsetFromOrigin(epicenter);
        const fullPadding = EventRenderPage.fullMapViewportPadding;
        final expectedFullCenterX =
            fullPadding.left +
            (EventRenderPage.fullMapPanelSize.width - fullPadding.horizontal) /
                2;
        final expectedFullCenterY =
            fullPadding.top +
            (EventRenderPage.fullMapPanelSize.height - fullPadding.vertical) /
                2;
        expect(fullEpicenterOffset.dx, closeTo(expectedFullCenterX, 1.0));
        expect(fullEpicenterOffset.dy, closeTo(expectedFullCenterY, 1.0));

        if (size.width >= 1000) {
          await _saveScreenshot(
            tester,
            screenshotKey,
            'window-full-${size.width.toInt()}.png',
          );
          await _saveFinderScreenshot(
            tester,
            find.byKey(const ValueKey('render_canvas_repaint')),
            'canvas_full_empty_panel.png',
          );
        }

        // Switch to Mode A (分栏悬浮) and verify epicenter is centered in the
        // split map panel.
        await tester.tap(find.byKey(const ValueKey('render_layout_split')));
        await tester.pump();
        await _settleRenderLayers(tester);

        final splitCamera = flutterMap.mapController!.camera;
        final splitEpicenterOffset = splitCamera.getOffsetFromOrigin(epicenter);
        expect(
          splitEpicenterOffset.dx,
          closeTo(EventRenderPage.splitMapPanelSize.width / 2, 1.0),
        );
        expect(
          splitEpicenterOffset.dy,
          closeTo(EventRenderPage.splitMapPanelSize.height / 2, 1.0),
        );

        await _saveScreenshot(
          tester,
          screenshotKey,
          'window-${size.width.toInt()}.png',
        );
        if (size.width >= 1000) {
          await _saveFinderScreenshot(
            tester,
            find.byKey(const ValueKey('render_canvas_repaint')),
            'canvas_split_empty_panel.png',
          );
        }

        // Switch to 4:3 aspect ratio (1600×1200) and verify canvas size,
        // sidebar width (492), and epicenter centering in both split and full modes.
        expect(find.byKey(const ValueKey('render_aspect_16_9')), findsOneWidget);
        expect(find.byKey(const ValueKey('render_aspect_4_3')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('render_aspect_4_3')));
        await tester.pump();
        await _settleRenderLayers(tester);

        final canvas4x3Box = tester.widget<SizedBox>(
          find.byKey(const ValueKey('event_render_canvas')),
        );
        expect(canvas4x3Box.width, 1600);
        expect(canvas4x3Box.height, 1200);

        final split4x3Size = EventRenderPage.splitMapPanelSizeFor(
          EventRenderAspectRatio.ratio4x3,
        );
        final split4x3Camera = flutterMap.mapController!.camera;
        final split4x3Offset = split4x3Camera.getOffsetFromOrigin(epicenter);
        expect(split4x3Offset.dx, closeTo(split4x3Size.width / 2, 1.0));
        expect(split4x3Offset.dy, closeTo(split4x3Size.height / 2, 1.0));
        if (size.width >= 1000) {
          await _saveFinderScreenshot(
            tester,
            find.byKey(const ValueKey('render_canvas_repaint')),
            'canvas_split_4_3.png',
          );
        }

        await tester.tap(find.byKey(const ValueKey('render_layout_full_map')));
        await tester.pump();
        await _settleRenderLayers(tester);

        final full4x3Size = EventRenderPage.fullMapPanelSizeFor(
          EventRenderAspectRatio.ratio4x3,
        );
        final full4x3Camera = flutterMap.mapController!.camera;
        final full4x3Offset = full4x3Camera.getOffsetFromOrigin(epicenter);
        final expectedFull4x3CenterX =
            fullPadding.left +
            (full4x3Size.width - fullPadding.horizontal) / 2;
        final expectedFull4x3CenterY =
            fullPadding.top +
            (full4x3Size.height - fullPadding.vertical) / 2;
        expect(full4x3Offset.dx, closeTo(expectedFull4x3CenterX, 1.0));
        expect(full4x3Offset.dy, closeTo(expectedFull4x3CenterY, 1.0));
        if (size.width >= 1000) {
          await _saveFinderScreenshot(
            tester,
            find.byKey(const ValueKey('render_canvas_repaint')),
            'canvas_full_4_3.png',
          );
        }

        // Switch back to 16:9 aspect ratio (1600×900).
        await tester.tap(find.byKey(const ValueKey('render_aspect_16_9')));
        await tester.pump();
        final canvas16x9Box = tester.widget<SizedBox>(
          find.byKey(const ValueKey('event_render_canvas')),
        );
        expect(canvas16x9Box.width, 1600);
        expect(canvas16x9Box.height, 900);

        expect(state.selectedHistoryEvent, same(other));
        expect(provider.historyInfoDisplayEvent, same(selection));
        expect(alerts, 0);

        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(EventRenderPage), findsNothing);
        expect(state.selectedHistoryEvent, same(other));
        expect(jsonEncode(original.toMap()), originalData);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        manager.updateJmaList([]);
        provider.dispose();
        state.dispose();
        background.dispose();
      },
    );
  }

  testWidgets(
    'right sidebar displays source-specific intensity label for JMA/CWA, CENC estimated, and CENC-IR',
    (tester) async {
      await tester.runAsync(() async {
        await loadUnifiedUiFonts();
      });
      final cencRow = QuakeEventAdapter.convertWolfxCencEqlist(
        Map<String, dynamic>.from(
          jsonDecode(
                File(
                  'test/fixtures/cenc_history_20261009/wolfx.original.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map,
        ),
      ).first;
      final cencEvent = QuakeEventAdapter.catalogInfo(cencRow, 'cencEqlist');
      final cencIrEvent = cencEvent.copyWith(
        source: 'nowQuakeCencIr',
        titleText: '中国地震台网烈度速报',
        maxIntensity: '4',
      );
      final cwaEvent = cencEvent.copyWith(
        source: 'cwaEqlist',
        titleText: '中央氣象署 地震報告',
        useShindo: true,
        maxIntensity: '4',
      );

      final fakeRegion = TopoJsonRegion(
        name: '估算测试区',
        code: '999',
        polygons: const [],
      );
      final estimatedGroup = PaintedRegionGroup(
        levelKey: 'IV',
        badgeText: 'IV',
        levelLabel: '烈度 IV (4度)',
        levelRangeText: '计算值 3.5~4.4',
        color: const Color(0xFF44BB66),
        sortOrder: 4,
        regions: [
          PaintedRegionDetail(
            region: fakeRegion,
            rawValue: 4.0,
            levelKey: 'IV',
            badgeText: 'IV',
            levelLabel: '烈度 IV (4度)',
            levelRangeText: '计算值 3.5~4.4',
            valueText: 'IV度 (4.00)',
            color: const Color(0xFF44BB66),
            sortOrder: 4,
          ),
        ],
      );
      final estimatedSummary = InformationFillSummary(
        scaleTitle: '中国地震烈度表 (CSIS)',
        sourceModeLabel: '震源距离衰减模型估算填色',
        isObserved: false,
        regions: estimatedGroup.regions,
        groups: [estimatedGroup],
        legendStops: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: unifiedUiTestTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 492,
                    height: 834,
                    child: RenderRightSidebarPanel(
                      event: cwaEvent,
                      fillSummary: InformationFillSummary.empty,
                    ),
                  ),
                  SizedBox(
                    width: 492,
                    height: 834,
                    child: RenderRightSidebarPanel(
                      event: cencEvent,
                      fillSummary: estimatedSummary,
                    ),
                  ),
                  SizedBox(
                    width: 492,
                    height: 834,
                    child: RenderRightSidebarPanel(
                      event: cencIrEvent,
                      fillSummary: InformationFillSummary.empty,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('最大震度 4'), findsOneWidget);
      expect(find.textContaining('预估烈度 '), findsOneWidget);
      expect(find.text('最大仪器烈度 IV'), findsOneWidget);
      // Locally estimated summary (isObserved == false) must NEVER draw region distribution.
      expect(find.text('估算测试区'), findsNothing);
    },
  );

  testWidgets(
    'right sidebar displays max lpgm badge after max shindo and truncates overflowing lower region distribution with ellipsis',
    (tester) async {
      await tester.runAsync(() async {
        await loadUnifiedUiFonts();
      });
      final cencRow = QuakeEventAdapter.convertWolfxCencEqlist(
        Map<String, dynamic>.from(
          jsonDecode(
                File(
                  'test/fixtures/cenc_history_20261009/wolfx.original.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map,
        ),
      ).first;
      final baseEvent = QuakeEventAdapter.catalogInfo(cencRow, 'jmaEqlist');
      const bulletin = JmaLpgmBulletin(
        eventId: '20260921212540',
        serial: 1,
        infoType: '発表',
        headline: '長周期地震動に関する観測情報',
        maxInt: '5-',
        maxLgInt: 3,
        lgCategory: '3',
      );
      final lpgmEvent = baseEvent.copyWith(
        source: 'jmaEqlist',
        titleText: '長周期地震動に関する観測情報',
        useShindo: true,
        maxIntensity: '5弱',
        jmaLpgmBulletin: bulletin,
      );

      PaintedRegionGroup makeGroup(
        String key,
        double order,
        Color color,
        int count,
      ) {
        final details = [
          for (var i = 1; i <= count; i++)
            PaintedRegionDetail(
              region: TopoJsonRegion(
                name: '等級$key地域名称番号第$i区',
                code: '$key-$i',
                polygons: const [],
              ),
              rawValue: order,
              levelKey: key,
              badgeText: key,
              levelLabel: '长周期 $key',
              levelRangeText: '',
              valueText: key,
              color: color,
              sortOrder: order,
            ),
        ];
        return PaintedRegionGroup(
          levelKey: key,
          badgeText: key,
          levelLabel: '长周期 $key',
          levelRangeText: '',
          color: color,
          sortOrder: order,
          regions: details,
        );
      }

      // Intentionally pass unsorted groups with many regions so lower levels overflow.
      final g1 = makeGroup('1', 1, const Color(0xFFF2E55C), 25);
      final g3 = makeGroup('3', 3, const Color(0xFFE53E3E), 3);
      final g2 = makeGroup('2', 2, const Color(0xFFE6A732), 25);
      final observedSummary = InformationFillSummary(
        scaleTitle: 'JMA 长周期地震动阶级',
        sourceModeLabel: '长周期观测区域填色',
        isObserved: true,
        regions: [...g3.regions, ...g2.regions, ...g1.regions],
        groups: [g1, g3, g2],
        legendStops: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: unifiedUiTestTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 492,
                height: 786,
                child: RenderRightSidebarPanel(
                  event: lpgmEvent,
                  fillSummary: observedSummary,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('render_header_intensity_text')),
            )
            .data,
        '最大震度 5-',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('render_header_lpgm_text')))
            .data,
        '长周期 3',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('render_distribution_title')),
            )
            .data,
        '长周期分布',
      );
      // Highest group (长周期 3) is rendered first, lowest overflowing group (长周期 1) is truncated.
      expect(find.text('长周期 3'), findsNWidgets(2));
      expect(find.text('长周期 2'), findsOneWidget);
      expect(find.text('长周期 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
