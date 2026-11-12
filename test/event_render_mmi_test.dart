import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/page_background_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/render_information_loader.dart';
import 'package:flutterrhythmquake/services/vector_basemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'package:flutterrhythmquake/widgets/ui/app_page_background.dart';
import 'package:flutterrhythmquake/widgets/ui/event_render_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/unified_ui_fonts.dart';
import 'usgs_shakemap_test.dart' show eventFor;

const root = 'test/fixtures/event_render_mmi_20261105';
final detailBytes = File(
  '$root/nc75462637.detail.original.geojson',
).readAsBytesSync();
final contourBytes = File(
  '$root/nc75462637.cont_mmi.original.json',
).readAsBytesSync();
final detail = jsonDecode(utf8.decode(detailBytes)) as Map<String, dynamic>;

class TrackingClient extends MockClient {
  TrackingClient(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'original screenshot event: isolated reader, original version/MMI/lines, disposal',
    () async {
      final event = eventFor(detail);
      final product = UsgsShakeMapProduct.fromDetail(detail)!;
      final requests = <Uri>[];
      final client = TrackingClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          request.url == product.contoursUrl ? contourBytes : detailBytes,
          200,
        );
      });
      final loader = RenderInformationLoader(client: client);
      final frame = (await loader.shakeMap(event))!;
      expect(requests, [Uri.parse(event.usgsDetailUrl!), product.contoursUrl]);
      expect(frame.event, same(event));
      expect(frame.product.version, '8');
      expect(frame.product.maxMmi, 2.816);
      expect(frame.contours.length, 9);
      final expected = UsgsMmiContour.parse(
        jsonDecode(utf8.decode(contourBytes)) as Map<String, dynamic>,
      );
      for (var i = 0; i < expected.length; i++) {
        expect(frame.contours[i].value, expected[i].value);
        expect(frame.contours[i].colorArgb, expected[i].colorArgb);
        expect(frame.contours[i].weight, expected[i].weight);
        expect(frame.contours[i].lines, expected[i].lines);
      }
      loader.close();
      loader.close();
      expect(client.closed, isTrue);
      expect(await loader.shakeMap(event), isNull);
    },
  );

  test(
    'wrong official event is rejected; other sources never request ShakeMap',
    () async {
      var requests = 0;
      final loader = RenderInformationLoader(
        client: TrackingClient((_) async {
          requests++;
          return http.Response.bytes(
            File(
              'test/fixtures/usgs_shakemap/ci41345415.detail.original.geojson',
            ).readAsBytesSync(),
            200,
          );
        }),
      );
      await expectLater(loader.shakeMap(eventFor(detail)), throwsStateError);
      expect(requests, 1);
      final nonUsgs = QuakeMessage(
        source: QuakeSourceType.cenc,
        eventId: 'test',
        location: '',
        magnitude: 0,
        latitude: 0,
        longitude: 0,
        depth: 0,
        originTime: DateTime(2026),
      );
      expect(await loader.shakeMap(nonUsgs), isNull);
      expect(requests, 1);
      loader.close();
    },
  );

  testWidgets(
    'USGS actual list button forwards clicked row without changing map selection',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      final map = MapStateProvider();
      final background = PageBackgroundProvider();
      await tester.runAsync(() => provider.eewHistoryReadyForTest);
      await tester.runAsync(() async {
        await VectorBasemapService.instance.load();
        await AppPageBackground.cachedBytes();
      });
      final event = eventFor(detail);
      final manager = EqlistManager();
      manager.updateUsgsList([event]);
      final otherDetail =
          jsonDecode(
                File(
                  'test/fixtures/usgs_shakemap/ci41345415.detail.original.geojson',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      final previous = eventFor(otherDetail);
      map.selectHistoryEvent(previous);
      final selection = map.selectedHistoryEvent;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: map),
            ChangeNotifierProvider<PageBackgroundProvider>.value(
              value: background,
            ),
          ],
          child: MaterialApp(home: const Scaffold(body: EqlistPanel())),
        ),
      );
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text(event.location).first));
      await tester.pump();
      await tester.tap(find.text('渲染事件'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final page = tester.widget<EventRenderPage>(find.byType(EventRenderPage));
      expect(page.usgsEvent, same(event));
      expect(page.event.eventId, event.eventId);
      expect(map.selectedHistoryEvent, same(selection));
      expect(provider.historyInfoDisplayEvent, isNull);
      // The engine test deliberately blocks default network requests. The
      // previous test verifies these exact original responses independently.
      await tester.pumpWidget(const SizedBox.shrink());
      await mouse.removePointer();
      manager.updateUsgsList([]);
      provider.dispose();
      map.dispose();
      background.dispose();
    },
  );

  testWidgets(
    'MMI renders, fits, exports and switches without affecting ordinary fill',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await loadUnifiedUiFonts();
        await (FontLoader('Ahem')..addFont(
              rootBundle.load('assets/fonts/MPLUSRounded1c-Regular.ttf'),
            ))
            .load();
        await (FontLoader('Roboto')..addFont(
              rootBundle.load('assets/fonts/MPLUSRounded1c-Regular.ttf'),
            ))
            .load();
        await (FontLoader('JetBrainsMono')..addFont(
              rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf'),
            ))
            .load();
        await VectorBasemapService.instance.load();
        await AppPageBackground.cachedBytes();
      });
      final event = eventFor(detail);
      final snapshot = QuakeEventAdapter.catalogInfo(event, 'usgsEqlist');
      final before = jsonEncode(snapshot.toMap());
      final requests = <Uri>[];
      final product = UsgsShakeMapProduct.fromDetail(detail)!;
      final client = TrackingClient((request) async {
        requests.add(request.url);
        return http.Response.bytes(
          request.url == product.contoursUrl ? contourBytes : detailBytes,
          200,
        );
      });
      final background = PageBackgroundProvider();
      Future<void> settleUi() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: background,
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: EventRenderPage(
              event: snapshot,
              usgsEvent: event,
              informationLoader: RenderInformationLoader(client: client),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(UsgsShakeMapLayer), findsOneWidget);
      expect(find.byType(InformationEventFillLayer), findsNothing);
      expect(find.byType(HistoryMarkerLayer), findsOneWidget);
      final sidebar = tester.widget<RenderRightSidebarPanel>(
        find.byType(RenderRightSidebarPanel),
      );
      expect(sidebar.shakeMap!.product.maxMmi, 2.816);
      final badge = tester.widget<Text>(
        find.byKey(const ValueKey('render_header_intensity_text')),
      );
      expect(badge.data, '最大 MMI 2.8');
      expect(find.textContaining('预估烈度'), findsNothing);
      expect(requests.length, 2);

      Future<void> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('render_canvas_repaint')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('tmp/event_render_mmi_20261105')
              ..createSync(recursive: true);
            File(
              '${dir.path}/$name.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            expect(image.width, 1600);
          } finally {
            image.dispose();
          }
        });
      }

      void checkCamera() {
        final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
        final camera = map.mapController!.camera;
        for (final point in shakeMapFocusPoints(sidebar.shakeMap!)) {
          final screen = camera.latLngToScreenOffset(point);
          expect(screen.dx, inInclusiveRange(35, 977));
          expect(
            screen.dy,
            inInclusiveRange(35, camera.nonRotatedSize.height - 35),
          );
        }
        final epicenter = camera.latLngToScreenOffset(
          shakeMapFocusPoints(sidebar.shakeMap!).first,
        );
        expect(epicenter.dx, closeTo(506, 1));
        expect(epicenter.dy, closeTo(camera.nonRotatedSize.height / 2, 1));
      }

      checkCamera();
      await capture('nc75462637-mmi-16x9');
      for (final mode in [
        'render_layout_split',
        'render_aspect_4_3',
        'render_layout_full_map',
      ]) {
        await tester.tap(find.byKey(ValueKey(mode)));
        await settleUi();
        checkCamera();
        expect(tester.takeException(), isNull);
      }
      await capture('nc75462637-mmi-4x3');
      Future<void> select(String text) async {
        await tester.tap(
          find.byKey(const ValueKey('render_shakemap_selector')),
        );
        await settleUi();
        await tester.tap(find.text(text).last);
        await settleUi();
      }

      await select('地震情报');
      expect(find.byType(UsgsShakeMapLayer), findsNothing);
      expect(find.byType(InformationEventFillLayer), findsOneWidget);
      await select('ShakeMap · MMI');
      expect(find.byType(UsgsShakeMapLayer), findsOneWidget);
      expect(requests.length, 2);
      expect(jsonEncode(snapshot.toMap()), before);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(client.closed, isTrue);
      background.dispose();
    },
  );
}
