import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/event_animation_clock.dart';
import 'package:flutterrhythmquake/models/tsunami_gauge_plan.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/services/native_jma_tsunami.dart';
import 'package:flutterrhythmquake/services/tsunami_gauge_service.dart';
import 'package:flutterrhythmquake/services/tsunami_region_service.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_gauge_layer.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_gauge_marker.dart';
import 'package:flutterrhythmquake/widgets/map/tsunami_region_layer.dart';

class EmptyGeometryService extends TsunamiRegionService {
  @override
  Future<List<Map<String, dynamic>>> load(TsunamiMessage message) async =>
      const [];
}

class PreparedService extends TsunamiGaugeService {
  PreparedService(this.plan);
  final TsunamiGaugePlan plan;
  int calls = 0;
  @override
  Future<TsunamiGaugePlan> prepare(
    TsunamiMessage message, {
    List<Map<String, dynamic>> regions = const [],
    DateTime? now,
  }) async {
    calls++;
    return plan;
  }
}

class DelayedService extends TsunamiGaugeService {
  final pending = Completer<TsunamiGaugePlan>();
  @override
  Future<TsunamiGaugePlan> prepare(
    TsunamiMessage message, {
    List<Map<String, dynamic>> regions = const [],
    DateTime? now,
  }) => message.isActive
      ? pending.future
      : Future.value(const TsunamiGaugePlan());
}

Widget mapWith(
  TsunamiMessage message,
  TsunamiGaugeService service, {
  MapController? controller,
  DateTime Function()? now,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: FlutterMap(
      mapController: controller,
      options: const MapOptions(
        initialCenter: LatLng(32.7, 130.3),
        initialZoom: 5,
      ),
      children: [
        TsunamiGaugeLayer(tsunami: message, service: service, now: now),
      ],
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TsunamiMessage forecast;
  late TsunamiGaugePlan originalPlan;
  setUpAll(() async {
    if (!NativeJmaTsunami.supported) return;
    final doc =
        jsonDecode(
              File(
                'test/fixtures/jma_tsunami/whews.forecast_stations.documented.json',
              ).readAsStringSync(),
            )
            as Map;
    forecast = TsunamiMessage.parseWhewsJmaTsunami(
      Map<String, dynamic>.from(doc['Data'] as Map),
    );
    originalPlan = await TsunamiGaugeService().prepare(forecast);
  });

  testWidgets(
    'an authoritative empty warning geometry cannot restore station gauges',
    (tester) async {
      final detail =
          jsonDecode(
                File(
                  'test/fixtures/noaa_ntwc_advisory_20250918.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final message = TsunamiMessage(
        source: TsunamiSource.ntwc,
        grade: TsunamiGrade.watch,
        officialDetail: detail,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(52.3, 173.6),
                initialZoom: 7,
              ),
              children: [
                TsunamiRegionLayer(
                  tsunami: message,
                  service: EmptyGeometryService(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TsunamiGaugeLayer), findsNothing);
      expect(find.byType(TsunamiGaugeMarker), findsNothing);
    },
  );

  testWidgets(
    'native forecast enters map; click opens detail without moving camera or starting a clock',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      final service = PreparedService(originalPlan);
      final leases = EventAnimationClock.instance.activeLeaseCount;
      await tester.pumpWidget(
        mapWith(forecast, service, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TsunamiGaugeMarker), findsOneWidget);
      expect(find.text('1m'), findsOneWidget);
      expect(find.text('待观测'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
      final center = controller.camera.center;
      controller.move(center, 8);
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      await tester.tap(find.byType(TsunamiGaugeMarker));
      await tester.pumpAndSettle();
      expect(find.text('JMA 海啸观测'), findsOneWidget);
      expect(find.text('预报区域：有明・八代海'), findsOneWidget);
      expect(controller.camera.center, center);
      expect(EventAnimationClock.instance.activeLeaseCount, leases);
      expect(tester.takeException(), isNull);
    },
    skip: !NativeJmaTsunami.supported,
  );

  testWidgets(
    'cancellation does not allow a pending old map plan to reappear',
    (tester) async {
      final service = DelayedService();
      await tester.pumpWidget(mapWith(forecast, service));
      await tester.pump();
      await tester.pumpWidget(
        mapWith(
          forecast.copyWith(
            grade: TsunamiGrade.none,
            bulletinLevel: 'cancellation',
          ),
          service,
        ),
      );
      service.pending.complete(originalPlan);
      await tester.pumpAndSettle();
      expect(find.byType(TsunamiGaugeMarker), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: !NativeJmaTsunami.supported,
  );

  testWidgets(
    'gauge scales continuously at its geographic anchor and keeps label builds out of camera frames',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      final service = PreparedService(originalPlan);
      await tester.pumpWidget(
        mapWith(forecast, service, controller: controller),
      );
      await tester.pumpAndSettle();
      final body = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TsunamiGaugePainter,
      );
      double paintedHeight() {
        final render = tester.renderObject<RenderBox>(body);
        return (render.localToGlobal(render.size.bottomRight(Offset.zero)) -
                render.localToGlobal(Offset.zero))
            .dy;
      }

      final at5 = paintedHeight();
      expect(at5, inInclusiveRange(49, 51));
      final marker = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .single;
      final anchor = marker.point;
      final previousRebuild = debugOnRebuildDirtyWidget;
      var labelBuilds = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is TsunamiGaugeMarker) labelBuilds++;
        previousRebuild?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousRebuild);
      for (var frame = 0; frame < 60; frame++) {
        controller.move(
          LatLng(anchor.latitude + frame * .0001, anchor.longitude),
          5,
        );
        await tester.pump();
      }
      expect(labelBuilds, 0);
      for (var frame = 1; frame <= 30; frame++) {
        controller.move(anchor, 5 + frame / 30);
        await tester.pump();
      }
      final at6 = paintedHeight();
      expect(at6, greaterThan(at5));
      expect(at6, inInclusiveRange(64, 66));
      expect(labelBuilds, 0);
      controller.move(anchor, 7);
      await tester.pumpAndSettle();
      expect(paintedHeight(), closeTo(85.577, .1));
      controller.move(anchor, 3);
      await tester.pumpAndSettle();
      expect(paintedHeight(), closeTo(32.091, .1));
      controller.move(anchor, 10);
      await tester.pumpAndSettle();
      expect(paintedHeight(), closeTo(102.4, .1));
      expect(
        tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers
            .single
            .point,
        anchor,
      );
      expect(service.calls, 1);
      // Hit testing uses the scaled bounds and still reaches the detail dialog.
      await tester.tap(find.byType(TsunamiGaugeMarker));
      await tester.pumpAndSettle();
      expect(find.text('JMA 海啸观测'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !NativeJmaTsunami.supported,
  );

  testWidgets(
    'expiry removes a gauge even with no new report',
    (tester) async {
      // Lifecycle-only protocol metadata. No original source field is changed.
      var now = DateTime.utc(2026, 10, 22, 4);
      final expiredAt = now.add(const Duration(seconds: 2));
      final message = forecast.copyWith(expires: expiredAt.toIso8601String());
      await tester.pumpWidget(
        mapWith(message, PreparedService(originalPlan), now: () => now),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TsunamiGaugeMarker), findsOneWidget);
      now = expiredAt;
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(TsunamiGaugeMarker), findsNothing);
    },
    skip: !NativeJmaTsunami.supported,
  );

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets(
      '28px gauge has no flex overflow at text scale $scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: TsunamiGaugeMarker(data: originalPlan.markers.first),
                ),
              ),
            ),
          ),
        );
        final paint = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is TsunamiGaugePainter,
        );
        expect(tester.getSize(paint).width, 28);
        expect(TsunamiGaugeMarker.borderColor, const Color(0xFFCBD0D5));
        expect(tester.takeException(), isNull);
      },
      skip: !NativeJmaTsunami.supported,
    );
  }

  testWidgets(
    'render actual Flutter gauge using independent unchanged documentation examples',
    (tester) async {
      final boundary = GlobalKey();
      late TsunamiGaugeData observation;
      await tester.runAsync(() async {
        final font = FontLoader('GaugePreview')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
              ),
            ),
          );
        await font.load();
        final raw =
            jsonDecode(
                  '{${File('test/fixtures/jma_tsunami/whews.observations.documented.fragment.txt').readAsStringSync()}}',
                )
                as Map;
        final station =
            (raw['observations'] as List).first['stations'][0] as Map;
        // This standalone reading has no claimed location or paired forecast.
        observation = TsunamiGaugeData(
          id: 'documented-reading',
          name: station['name'] as String,
          latitude: 0,
          longitude: 0,
          forecastText: '—',
          forecastUnit: '',
          forecastLabel: '预计未提供',
          observationText: station['maxHeight'] as String,
          observationUnit: 'm',
          observationLabel: '最大观测',
        );
      });
      tester.view.physicalSize = const Size(360, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'GaugePreview',
              ),
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFF202124),
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      '原文独立示例 · 不代表同一地区',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TsunamiGaugeMarker(data: originalPlan.markers.first),
                        TsunamiGaugeMarker(data: observation),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final output = File('tmp/tsunami_gauge_20261022/flutter-gauge.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        image.dispose();
      });
    },
    skip: !NativeJmaTsunami.supported,
  );
}
