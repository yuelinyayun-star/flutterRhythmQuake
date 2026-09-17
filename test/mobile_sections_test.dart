import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:flutterrhythmquake/widgets/ui/mobile_sections.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/widgets/ui/cmt_sidebar_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final bytes = await font.readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'weather overlays the same mounted map and reports page activity',
    (tester) async {
      var mounts = 0;
      var disposes = 0;
      final changes = <MobileSection>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileSectionHost(
              seismic: _LifecycleProbe(
                onMount: () => mounts++,
                onDispose: () => disposes++,
              ),
              weather: const Align(
                alignment: Alignment.bottomCenter,
                child: Text('weather-content'),
              ),
              onSectionChanged: changes.add,
              settingsBuilder: (_) => const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mobile-section-weather')));
      await tester.pump();
      expect(find.text('map-state'), findsOneWidget);
      expect(find.text('weather-content'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-section-settings')));
      await tester.pump();
      expect(find.text('map-state'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mobile-section-seismic')));
      await tester.pump();
      expect(find.text('map-state'), findsOneWidget);
      expect(mounts, 1);
      expect(disposes, 0);
      expect(changes, [
        MobileSection.weather,
        MobileSection.settings,
        MobileSection.seismic,
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'section switches retain map state and use text-only navigation',
    (tester) async {
      var mounts = 0;
      var disposes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileSectionHost(
              seismic: _LifecycleProbe(
                onMount: () => mounts++,
                onDispose: () => disposes++,
              ),
              settingsBuilder: (back) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: TextButton(
                    onPressed: back,
                    child: const Text('返回原页面'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(mounts, 1);
      expect(find.byType(Icon), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mobile-section-weather')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mobile-weather-reserved')),
        findsOneWidget,
      );
      expect(find.text('map-state'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mobile-section-settings')));
      await tester.pump();
      expect(find.text('返回原页面'), findsOneWidget);
      await tester.tap(find.text('返回原页面'));
      await tester.pump();
      expect(find.text('map-state'), findsOneWidget);
      expect(mounts, 1);
      expect(disposes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'double line resizes continuously and list scroll is independent',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 600,
              child: MobileEventListLayout(
                alert: const SizedBox(height: 120, child: Text('统一 UI')),
                divider: const SizedBox(height: 5, child: Divider()),
                actions: const SizedBox(height: 36),
                list: ListView.builder(
                  controller: controller,
                  itemExtent: 48,
                  itemCount: 50,
                  itemBuilder: (_, i) => Text('record $i'),
                ),
              ),
            ),
          ),
        ),
      );
      final grip = find.byKey(const ValueKey('mobile-list-grip'));
      final viewport = find.byKey(const ValueKey('mobile-list-viewport'));
      expect(tester.getSize(viewport).height, 0);
      await tester.drag(grip, const Offset(0, -100));
      await tester.pump();
      final first = tester.getSize(viewport).height;
      expect(first, greaterThan(50));
      await tester.drag(grip, const Offset(0, -140));
      await tester.pump();
      final second = tester.getSize(viewport).height;
      expect(second, greaterThan(first + 80));
      expect(tester.getBottomLeft(grip).dy, tester.getTopLeft(viewport).dy);
      await tester.drag(viewport, const Offset(0, -70));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(tester.getSize(viewport).height, second);
      final offset = controller.offset;
      await tester.tap(grip);
      await tester.pump();
      expect(tester.getSize(viewport).height, 0);
      await tester.tap(grip);
      await tester.pump();
      expect(controller.offset, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list ceiling preserves full UI height and allows UI to move up',
    (tester) async {
      final alertHeight = ValueNotifier<double>(180);
      addTearDown(alertHeight.dispose);
      const alertKey = ValueKey('full-alert-content');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 600,
              child: ValueListenableBuilder<double>(
                valueListenable: alertHeight,
                builder: (_, height, _) => MobileEventListLayout(
                  alert: SizedBox(key: alertKey, height: height),
                  actions: const SizedBox(height: 36),
                  divider: const Divider(),
                  list: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      );
      final grip = find.byKey(const ValueKey('mobile-list-grip'));
      final viewport = find.byKey(const ValueKey('mobile-list-viewport'));
      final alert = find.byKey(alertKey);
      final initialTop = tester.getTopLeft(alert).dy;
      await tester.drag(grip, const Offset(0, -1000));
      await tester.pump();
      expect(tester.getSize(alert).height, 180);
      expect(tester.getTopLeft(alert).dy, lessThan(initialTop - 250));
      expect(tester.getSize(viewport).height, 348);
      expect(tester.getBottomLeft(alert).dy, tester.getTopLeft(grip).dy);
      expect(tester.getBottomLeft(grip).dy, tester.getTopLeft(viewport).dy);
      alertHeight.value = 240;
      await tester.pump();
      expect(tester.getSize(alert).height, 240);
      expect(tester.getSize(viewport).height, 288);
      expect(tester.getBottomLeft(alert).dy, tester.getTopLeft(grip).dy);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile sidebar scales as a whole and keeps hit testing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileSeismicOverlays(
            stations: const SizedBox(),
            events: const SizedBox(),
            sidebar: Column(
              children: [
                TextButton(onPressed: () => taps++, child: const Text('下一条')),
              ],
            ),
          ),
        ),
      ),
    );
    final frame = tester.getRect(
      find.byKey(const ValueKey('mobile-sidebar-frame')),
    );
    expect(frame.width, closeTo(145, .001));
    expect(frame.height, closeTo(324 * .85, .001));
    expect(frame.right, 378);
    expect(frame.top, 74);
    await tester.tap(find.text('下一条'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  for (final (size, textScale) in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(430, 932), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(390, 844), 1.3),
  ]) {
    testWidgets(
      'existing alert, list and station widgets fit $size at $textScale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final provider = QuakeProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => provider),
              ChangeNotifierProvider(create: (_) => MapStateProvider()),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: MobileSectionHost(
                    settingsBuilder: (_) => const SizedBox(),
                    seismic: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xFF45545C)),
                        ),
                        Positioned.fill(
                          child: MobileSeismicOverlays(
                            stations: StationDashboard(
                              data: StationSummaryData(),
                              phoneMode: true,
                            ),
                            sidebar: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 17,
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: CmtSidebarPanel(
                                      scale: (v) => v,
                                      event: QuakeMessage(
                                        source: QuakeSourceType.usgsCmt,
                                        eventId: 'us-test',
                                        location: '测试位置',
                                        magnitude: 5.6,
                                        latitude: 28.55,
                                        longitude: 104.67,
                                        depth: 5,
                                        originTime: DateTime(2026, 8, 3, 13),
                                        nodalPlane1: '358/45/85',
                                        nodalPlane2: '185/45/95',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 62),
                                ],
                              ),
                            ),
                            events: AlertModule(
                              layoutBuilder: (content, strip) =>
                                  MobileEventListLayout(
                                    alert: content,
                                    divider: strip,
                                    list: const EqlistPanel(embedded: true),
                                    actions: const SizedBox(height: 36),
                                  ),
                            ),
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
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        provider.handleUnifiedEventForTest(
          UnifiedQuakeData(
            source: 'cencEqlist',
            origin: 0,
            eventId: 'CC.20260725060436.5',
            isEew: false,
            timeZone: 0,
            titleText: '中国地震台网地震信息',
            reportNumText: '正式测定',
            useShindo: false,
            maxIntensity: '7.0',
            className: 'orange',
            hypocenter: '瓦努阿图群岛',
            originTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 1),
            ),
            reportTime: DateTime.now().toUtc(),
            magnitude: 5.9,
            depth: 40,
            depthText: '深度: 40km',
            lat: -15.2,
            lng: 167.1,
            apiTypeLabel: 'Wolfx',
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('瓦努阿图群岛'), findsWidgets);
        expect(tester.takeException(), isNull);
        for (final label in [
          'NIED',
          'S-net',
          'KMA',
          'SeisJS',
          'TREM',
          'P-Alert',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.drag(
          find.byKey(const ValueKey('mobile-list-grip')),
          const Offset(0, -450),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .getSize(find.byKey(const ValueKey('mobile-list-viewport')))
              .height,
          greaterThan(0),
        );
        final alertViewport = find.byKey(
          const PageStorageKey('mobile-unified-events'),
        );
        final alertScroll = tester.widget<SingleChildScrollView>(alertViewport);
        expect(
          tester.getSize(alertViewport).height,
          tester.getSize(find.byWidget(alertScroll.child!)).height,
        );
        expect(tester.takeException(), isNull);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File(
            'tmp/mobile_ui_review/phone_${size.width.toInt()}_$textScale.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({required this.onMount, required this.onDispose});
  final VoidCallback onMount;
  final VoidCallback onDispose;
  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Center(child: Text('map-state'));
}
