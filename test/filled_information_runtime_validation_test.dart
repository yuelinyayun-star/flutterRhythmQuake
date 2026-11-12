import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_server.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/ntp_service.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/core/utils/world_wrap.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/services/sources/mock_input_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/information_focus_anchor.dart';
import 'package:flutterrhythmquake/widgets/map/jma_info_focus.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_focus.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_layer.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'package:flutterrhythmquake/models/history_map_product.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_focus.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_layer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'information_camera_group_test.dart' show frameFor;
import 'usgs_dyfi_camera_fit_test.dart' show originalFrame, smallestCellSide;
import 'usgs_dyfi_kmz_test.dart' show loadOriginalKenai;

class _Loopback extends HttpOverrides {}

// Archive publication replaces network delivery only. Production provider,
// product-slot admission, rendering and automatic camera policy stay active.
class _ShakePublication extends UsgsShakeMapService {
  _ShakePublication()
    : super(client: MockClient((_) async => http.Response('', 404)));
  UsgsShakeMapFrame? published;
  @override
  UsgsShakeMapFrame? get automaticFrame => published;
  void publish(UsgsShakeMapFrame frame) {
    published = frame;
    notifyListeners();
  }
}

class _DyfiPublication extends UsgsDyfiService {
  _DyfiPublication()
    : super(client: MockClient((_) async => http.Response('', 404)));
  UsgsDyfiFrame? published;
  @override
  UsgsDyfiFrame? get automaticFrame => published;
  void publish(UsgsDyfiFrame frame) {
    published = frame;
    notifyListeners();
  }
}

final _out = Directory(
  Platform.environment['RQ_FILL_OUTPUT'] ??
      'tmp/jma_info_center_20261030/other-filled-runtime',
);
final _results = <Map<String, dynamic>>[];
// Full QuakeMapView owns process-singleton monitor lifetimes. Run each matrix
// member in its own engine with tools/test_filled_information_runtime.ps1.
const _selectedCase = String.fromEnvironment('FILL_CASE');

class _Host {
  _Host(
    this.tester,
    this.size, {
    UsgsShakeMapService? shake,
    UsgsDyfiService? dyfi,
  }) : provider = QuakeProvider(
         startCatalogServices: false,
         nativeUnifiedEvents: true,
         shakeMapService: shake,
         dyfiService: dyfi,
       );
  final WidgetTester tester;
  final Size size;
  final QuakeProvider provider;
  final state = MapStateProvider();
  final map = MapController();
  final imageKey = GlobalKey();
  final client = _Loopback().createHttpClient(null);

  Future<void> start() async {
    provider.setShowStaleInfoEvent(true);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(() async {
      await provider.eewHistoryReadyForTest;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      await LocalInjectServer.start(port: port);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: provider),
          ChangeNotifierProvider<MapStateProvider>.value(value: state),
        ],
        child: MaterialApp(
          home: RepaintBoundary(
            key: imageKey,
            child: Scaffold(body: QuakeMapView(mapController: map)),
          ),
        ),
      ),
    );
    state.setController(map, const TestVSync());
    final actualMap = tester.widget<FlutterMap>(find.byType(FlutterMap).first);
    expect(actualMap.options.initialRotation, 0);
    expect(actualMap.options.interactionOptions.flags & InteractiveFlag.rotate, 0);
    expect(actualMap.options.interactionOptions.keyboardOptions.enableQERotating, isFalse);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> inject(
    Map<String, dynamic> original,
    String format, {
    String? source,
    int expectedActive = 1,
  }) async {
    final decoded = LocalInjectDecoder.decode(
      original,
      format: format,
      source: source,
    ).events.single;
    debugPrint(
      'INCOMING_REPORT id=${decoded.eventId} history=${decoded.isHistory} sourceExpiry=${decoded.useSourceTimeForExpiry} origin=${decoded.origin} originTime=${decoded.originTime} reportTime=${decoded.reportTime} magnitude=${decoded.magnitude}',
    );
    final bytes = utf8.encode(jsonEncode(original));
    await tester.runAsync(() async {
      final query = {'format': format, 'source': ?source};
      final request = await client.postUrl(
        Uri.http('127.0.0.1:${LocalInjectServer.boundPort}', '/inject', query),
      );
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.add(bytes);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(
        jsonDecode(await utf8.decoder.bind(response).join())['injected'],
        1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle();
    expect(provider.unifiedEvents, hasLength(expectedActive));
    expect(
      provider.unifiedEvents.any(
        (e) =>
            jsonEncode(e.sourcePayload) ==
            jsonEncode(
              format == 'unified'
                  ? original['sourcePayload'] ?? original
                  : original,
            ),
      ),
      isTrue,
      reason:
          'incoming=${original['id']} active=${provider.unifiedEvents.map((e) => '${e.eventId}/${e.sourcePayload?['id']}').toList()}',
    );
  }

  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1450)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1350)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }

  BuildContext get context => tester.element(find.byType(QuakeMapView));
  Rect get viewport => (cencIrViewportPadding(context) ?? EdgeInsets.zero)
      .deflateRect(Offset.zero & size);

  Future<void> record(
    String name, {
    List<LatLng> points = const [],
    LatLng? anchor,
    bool allVisible = true,
    EdgeInsets? productPadding,
  }) async {
    final visible = productPadding == null
        ? viewport
        : productPadding.deflateRect(Offset.zero & size);
    final error = anchor == null
        ? null
        : (map.camera.latLngToScreenOffset(anchor) - visible.center).distance;
    if (error != null) expect(error, lessThan(1));
    var outside = 0;
    for (final point in points) {
      final displayed = LatLng(
        point.latitude,
        WorldWrap.longitudeClosestTo(
          point.longitude,
          map.camera.center.longitude,
        ),
      );
      if (!visible
          .inflate(1)
          .contains(map.camera.latLngToScreenOffset(displayed))) {
        outside++;
      }
    }
    expect(NativeCameraFocus.outputs, 0);
    _results.add({
      'case': name,
      'width': size.width,
      'height': size.height,
      'zoom': map.camera.zoom,
      'focusPoints': points.length,
      'outsidePoints': outside,
      'anchorErrorPixels': error,
      'nativeOutputs': NativeCameraFocus.outputs,
      'requiresAllPointsVisible': allVisible,
      'passed': !allVisible || outside == 0,
    });
    await tester.runAsync(() async {
      final boundary =
          imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${_out.path}/$name-${size.width.toInt()}.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      File('${_out.path}/results.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_results),
        encoding: utf8,
      );
      File('${_out.path}/$name-${size.width.toInt()}.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_results.last),
        encoding: utf8,
      );
    });
    debugPrint('OTHER_FILL_RESULT ${_results.last}');
    if (allVisible) expect(outside, 0);
    debugPrint('OTHER_FILL_VERIFIED ${_results.last}');
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => LocalInjectServer.stop());
    client.close(force: true);
    provider.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mock = MockInputService();
  setUpAll(() {
    _out.createSync(recursive: true);
    SourceManager().registerSource(mock);
  });
  tearDownAll(mock.dispose);
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'weather_alarm_local_only': false,
      'api_source_nied_monitor_enabled': false,
      'api_source_nied_lpgm_enabled': false,
      'api_source_kma_pews_enabled': false,
      'api_source_palert_enabled': false,
      'api_source_wolfx_seisjs_enabled': false,
      'api_source_snet_enabled': false,
      'trem_station_enabled': false,
    });
    SoundEffectService().enabled = false;
    TtsService().enabled = false;
    QuakeMapView.niedMonitorEnabledNotifier.value = false;
    QuakeMapView.niedLpgmEnabledNotifier.value = false;
    QuakeMapView.kmaPewsEnabledNotifier.value = false;
    QuakeMapView.pAlertEnabledNotifier.value = false;
    QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
    QuakeMapView.snetEnabledNotifier.value = false;
    QuakeMapView.tremStationEnabledNotifier.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => _out.absolute.path,
        );
  });

  for (final size in [const Size(1584, 850), const Size(430, 900)]) {
    testWidgets(
      'original Kenai DYFI actually draws grids and epicenter in automatic and manual main map $size',
      (tester) async {
        late UsgsDyfiFrame frame;
        await tester.runAsync(() async {
          frame = await loadOriginalKenai();
        });
        final service = _DyfiPublication();
        final host = _Host(tester, size, dyfi: service);
        await host.start();
        try {
          service.publish(frame);
          await host.settle();
          final marker = find.byWidgetPredicate(
            (w) =>
                w is QuakeWaveLayer && w.event.eventId == frame.event.eventId,
          );
          expect(marker, findsOneWidget);
          final painter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<UsgsDyfiGridPainter>()
              .single;
          expect(painter.frame.cells, hasLength(71));
          final visible = Offset.zero & size;
          final drawn = painter.shapes
              .where((shape) => shape.$2.getBounds().overlaps(visible))
              .length;
          expect(drawn, greaterThan(0));
          final anchor = LatLng(frame.event.latitude, frame.event.longitude);
          await host.record(
            'dyfi-kenai-auto',
            anchor: anchor,
            productPadding: usgsProductViewportPadding(host.context),
          );
          host.state.selectHistoryEvent(
            frame.event,
            product: HistoryMapProduct.dyfi,
          );
          await host.settle();
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is HistoryMarkerLayer &&
                  w.event?.eventId == frame.event.eventId,
            ),
            findsOneWidget,
          );
          await host.record('dyfi-kenai-manual');
          debugPrint(
            'KENAI_RENDER ${jsonEncode({'width': size.width, 'cells': frame.cells!.length, 'visibleCells': drawn, 'markers': marker.evaluate().length})}',
          );
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'dyfi-kenai-${size.width.toInt()}',
    );
    for (final place in ['jan-mayen', 'flores']) {
      testWidgets(
        'original GQ EEW $place retains epicenter ${size.width}',
        (tester) async {
          final file = File(
            place == 'jan-mayen'
                ? 'test/fixtures/eew_camera_20261101/gq_jan_mayen_report4.original.json'
                : 'test/fixtures/global_quake/captured_report_only_20261018.json',
          );
          final originalBytes = file.readAsBytesSync();
          final document = jsonDecode(utf8.decode(originalBytes));
          final raw = Map<String, dynamic>.from(
            place == 'jan-mayen'
                ? document as Map
                : (document['reports'] as List).first as Map,
          );
          final now = place == 'jan-mayen'
              ? DateTime(2026, 11, 1, 19, 12, 6)
              : DateTime.parse(
                  raw['originTime'] as String,
                ).add(const Duration(seconds: 174));
          final ntp = NtpService();
          final oldClock = (ntp.deviceOffset, ntp.lastSyncedAt, ntp.isSynced);
          ntp.restoreClockSample(
            now.difference(DateTime.now()).inMilliseconds,
            DateTime.now(),
            true,
          );
          final host = _Host(tester, size);
          try {
            await tester.runAsync(() => TravelTimeService().ensureLoaded());
            await host.start();
            // The screenshot is already following this EEW, after the long-haul
            // flight. Start there so this exercises wave fit, not first arrival.
            host.map.move(
              LatLng(
                (raw['lat'] as num).toDouble(),
                (raw['lng'] as num).toDouble(),
              ),
              6,
            );
            await host.inject(raw, 'unified');
            await host.settle();
            expect(host.provider.unifiedEvents.single.isEew, isTrue);
            final event = host.provider.unifiedMapEvents.single;
            final anchor = LatLng(event.latitude, event.longitude);
            final pixel = host.map.camera.latLngToScreenOffset(anchor);
            final error = (pixel - size.center(Offset.zero)).distance;
            final result = {
              'place': place,
              'width': size.width,
              'errorPx': error,
              'zoom': host.map.camera.zoom,
              'epicenterPixel': [pixel.dx, pixel.dy],
              'nativeCalls': NativeCameraFocus.calls,
              'nativeOutputs': NativeCameraFocus.outputs,
            };
            debugPrint('EEW_ENTRANCE ${jsonEncode(result)}');
            File(
              '${_out.path}/gq-$place-${size.width.toInt()}-metrics.json',
            ).writeAsStringSync(jsonEncode(result));
            expect(error, lessThan(1));
            if (place == 'jan-mayen') {
              expect(host.map.camera.zoom, closeTo(4.5, 1e-9));
            }
            expect(NativeCameraFocus.outputs, 0);
            expect(
              sha256.convert(file.readAsBytesSync()),
              sha256.convert(originalBytes),
            );
            await host.record('gq-$place-${size.width.toInt()}');
          } finally {
            await host.close();
            ntp.restoreClockSample(oldClock.$1, oldClock.$2, oldClock.$3);
          }
        },
        skip:
            !NativeCameraFocus.supported ||
            _selectedCase != 'gq-$place-${size.width.toInt()}',
      );
    }
    for (final source in ['cenc', 'cwa']) {
      testWidgets(
        'ordinary $source information fits its actual modeled fill and remains non-EEW $size',
        (tester) async {
          final file = File(
            source == 'cenc'
                ? 'test/fixtures/cenc_history_20261014/wolfx.original.json'
                : 'test/fixtures/cwa_catalog_20261028/trem_list.original.json',
          );
          final hash = sha256.convert(file.readAsBytesSync());
          final original = jsonDecode(file.readAsStringSync(encoding: utf8));
          final raw = Map<String, dynamic>.from(
            source == 'cenc' ? original['No1'] as Map : original[1] as Map,
          );
          final host = _Host(tester, size);
          await tester.runAsync(() async {
            await TopoJsonLoader.loadCnEew();
            await TopoJsonLoader.loadTwEew();
          });
          await host.start();
          try {
            await host.inject(raw, 'wolfx', source: '${source}Eqlist');
            expect(host.provider.unifiedEvents.single.isEew, isFalse);
            expect(host.provider.unifiedEvents.single.originTime, isNotNull);
            final fill = find.byWidgetPredicate(
              (w) =>
                  w is IntensityFillLayer &&
                  w.source == (source == 'cenc' ? 'cn' : 'tw'),
            );
            expect(fill, findsOneWidget);
            final polygons = tester
                .widgetList<PolygonLayer>(
                  find.descendant(
                    of: fill,
                    matching: find.byType(PolygonLayer),
                  ),
                )
                .expand((w) => w.polygons)
                .toList();
            expect(polygons, isNotEmpty);
            final event = host.provider.unifiedEvents.single;
            await host.record(
              '$source-modeled-information',
              points: polygons.expand((p) => p.points).toList(),
              anchor: LatLng(event.lat!, event.lng!),
            );
            expect(sha256.convert(file.readAsBytesSync()), hash);
          } finally {
            await host.close();
          }
        },
        skip:
            !NativeCameraFocus.supported ||
            _selectedCase != '$source-modeled-${size.width.toInt()}',
      );
    }

    testWidgets(
      'filled information carousel and contained new report never move the shared viewport $size',
      (tester) async {
        final first =
            jsonDecode(
                  File(
                    'test/fixtures/source_estimation/cwa_report_115068_original.json',
                  ).readAsStringSync(encoding: utf8),
                )
                as Map<String, dynamic>;
        final next =
            jsonDecode(
                  File(
                    'test/fixtures/cwa_catalog_20261028/trem_detail.original.json',
                  ).readAsStringSync(encoding: utf8),
                )
                as Map<String, dynamic>;
        final jma =
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
        final host = _Host(tester, size);
        await tester.runAsync(() async {
          await TopoJsonLoader.loadTwEew();
          await TopoJsonLoader.loadJpEew();
        });
        await host.start();
        try {
          await host.inject(first, 'wolfx', source: 'cwaEqlist');
          await host.inject(jma, 'p2p', expectedActive: 2);
          await host.settle();
          List<LatLng> filledPoints() => tester
              .widgetList<PolygonLayer>(
                find.descendant(
                  of: find.byType(IntensityFillLayer),
                  matching: find.byType(PolygonLayer),
                ),
              )
              .expand((layer) => layer.polygons)
              .expand((p) => p.points)
              .toList();
          final padding =
              cencIrViewportPadding(host.context) ?? const EdgeInsets.all(50);
          final initial = filledPoints();
          expect(initial, isNotEmpty);
          await host.record(
            'shared-fill-initial',
            points: initial,
            productPadding: padding,
          );
          final center = host.map.camera.center, zoom = host.map.camera.zoom;
          var moves = 0;
          final subscription = host.map.mapEventStream.listen((_) => moves++);
          try {
            for (var i = 0; i < 8; i++) {
              host.provider.setCurrentUnifiedIndex(i % 2);
              await tester.pump(const Duration(seconds: 1));
              expect(host.map.camera.center, center);
              expect(host.map.camera.zoom, zoom);
            }
            expect(moves, 0);
            // A different original report arrives inside the already fitted area.
            // Its raw body/time/observations remain unchanged.
            await host.inject(
              next,
              'wolfx',
              source: 'cwaEqlist',
              expectedActive: 2,
            );
            expect(
              host.provider.unifiedEvents.any(
                (e) => e.sourcePayload?['id'] == next['id'],
              ),
              isTrue,
            );
            expect(host.map.camera.center, center);
            expect(host.map.camera.zoom, zoom);
            expect(moves, 0);
            await host.record(
              'shared-fill-contained-update',
              points: filledPoints(),
              productPadding: padding,
            );
            File(
              '${_out.path}/shared-stability-${size.width.toInt()}.json',
            ).writeAsStringSync(
              jsonEncode({
                'carouselTurns': 8,
                'containedNewReport': next['id'],
                'mapEvents': moves,
                'centerUnchanged': true,
                'zoomUnchanged': true,
              }),
              encoding: utf8,
            );
            final far =
                (jsonDecode(
                          File(
                            'test/fixtures/jma_camera_20261030/p2p_history.original.json',
                          ).readAsStringSync(encoding: utf8),
                        )
                        as List)
                    .cast<Map<String, dynamic>>()
                    .singleWhere((r) => r['id'] == '6ae45a03e88ee598246bf44c');
            await host.inject(far, 'p2p', expectedActive: 2);
            host.provider.setCurrentUnifiedIndex(
              host.provider.unifiedEvents.indexWhere(
                (e) => e.sourcePayload?['id'] == far['id'],
              ),
            );
            await host.settle();
            expect(moves, greaterThan(0));
            expect(host.map.camera.center, isNot(center));
            final farFill = find.byWidgetPredicate(
              (w) => w is IntensityFillLayer && w.source == 'jp',
            );
            final farPoints = tester
                .widgetList<PolygonLayer>(
                  find.descendant(
                    of: farFill,
                    matching: find.byType(PolygonLayer),
                  ),
                )
                .expand((w) => w.polygons)
                .expand((p) => p.points)
                .toList();
            final farEvent = host.provider.unifiedEvents.firstWhere(
              (e) => e.sourcePayload?['id'] == far['id'],
            );
            await host.record(
              'outside-information-refits',
              points: farPoints,
              anchor: LatLng(farEvent.lat!, farEvent.lng!),
            );
          } finally {
            await tester.runAsync(subscription.cancel);
          }
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'shared-${size.width.toInt()}',
    );

    testWidgets(
      'actual CWA observed counties retain their original epicenter camera $size',
      (tester) async {
        final file = File(
          'test/fixtures/source_estimation/cwa_report_115068_original.json',
        );
        final originalHash = sha256.convert(file.readAsBytesSync());
        final raw =
            jsonDecode(file.readAsStringSync(encoding: utf8))
                as Map<String, dynamic>;
        final host = _Host(tester, size);
        await tester.runAsync(TopoJsonLoader.loadTwEew);
        await host.start();
        try {
          await host.inject(raw, 'wolfx', source: 'cwaEqlist');
          final event = host.provider.unifiedEvents.single;
          final fill = find.byWidgetPredicate(
            (w) =>
                w is IntensityFillLayer &&
                w.mode == IntensityFillMode.cwaObserved,
          );
          expect(fill, findsOneWidget);
          final polygons = tester
              .widgetList<PolygonLayer>(
                find.descendant(of: fill, matching: find.byType(PolygonLayer)),
              )
              .expand((w) => w.polygons)
              .toList();
          expect(polygons, isNotEmpty);
          // The current request explicitly extends fill fitting to information.
          expect(
            informationFocusAnchor(
              event,
              host.provider.unifiedMapEvents.single,
              hasInformationFill: true,
            ),
            isNotNull,
          );
          await host.record(
            'cwa-observed-fill',
            points: polygons.expand((p) => p.points).toList(),
            anchor: LatLng(event.lat!, event.lng!),
          );
          expect(sha256.convert(file.readAsBytesSync()), originalHash);
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'cwa-${size.width.toInt()}',
    );

    testWidgets(
      'actual HTTP JMA ScalePrompt to Destination to DetailScale preserves distinct cameras $size',
      (tester) async {
        final file = File('test/fixtures/jma_voice/p2p_history_20260921.json');
        final hash = sha256.convert(file.readAsBytesSync());
        final originals =
            (jsonDecode(file.readAsStringSync(encoding: utf8)) as List)
                .cast<Map<String, dynamic>>();
        final host = _Host(tester, size);
        await host.start();
        try {
          for (final type in ['ScalePrompt', 'Destination', 'DetailScale']) {
            final raw = originals.firstWhere(
              (e) =>
                  e['issue']['type'] == type &&
                  e['earthquake']['time'] == '2026/09/21 22:38:00',
            );
            await host.inject(raw, 'p2p');
            final event = host.provider.unifiedEvents.single;
            final mapEvent = host.provider.unifiedMapEvents.single;
            final points = jmaInfoFocusPoints(
              warnAreaJson: event.warnArea,
              epicenterLatitude: event.lat,
              epicenterLongitude: event.lng,
            );
            expect(points.length, greaterThan(1));
            final anchor = informationFocusAnchor(event, mapEvent);
            if (type == 'DetailScale') {
              expect(anchor, isNotNull);
            } else {
              expect(anchor, isNull);
            }
            await host.record('jma-$type', points: points, anchor: anchor);
          }
          expect(sha256.convert(file.readAsBytesSync()), hash);
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'jma-${size.width.toInt()}',
    );

    testWidgets(
      'actual ShakeMap publication uses original contours and automatic map entry $size',
      (tester) async {
        final service = _ShakePublication();
        final host = _Host(tester, size, shake: service);
        await host.start();
        try {
          final frame = frameFor('ci41345415');
          expect(frame.contours, isNotEmpty);
          final before = NativeCameraFocus.calls;
          service.publish(frame);
          await host.settle();
          expect(host.provider.unifiedEvents.single.source, 'usgsShakeMap');
          expect(host.provider.shakeMapFrame, same(frame));
          expect(NativeCameraFocus.calls, greaterThan(before));
          final painter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((widget) => widget.painter)
              .whereType<UsgsMmiContourPainter>()
              .single;
          expect(painter.frame, same(frame));
          expect(
            UsgsMmiContourPainter.hasVisibleContour(frame, painter.camera),
            isTrue,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is QuakeWaveLayer &&
                  widget.event.eventId == frame.event.eventId,
            ),
            findsOneWidget,
          );
          // Check the actual original contours, rather than empty grid margins.
          await host.record(
            'shakemap-ci41345415',
            points: shakeMapFocusPoints(frame),
            anchor: LatLng(frame.event.latitude, frame.event.longitude),
            productPadding: usgsProductViewportPadding(host.context),
          );
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'shakemap-${size.width.toInt()}',
    );

    testWidgets(
      'actual empty Alaska ShakeMap fits original dateline bounds without inventing contours $size',
      (tester) async {
        final service = _ShakePublication();
        final host = _Host(tester, size, shake: service);
        await host.start();
        try {
          final frame = frameFor('aka2026tvzrwv');
          expect(frame.contours, isEmpty);
          service.publish(frame);
          await host.settle();
          expect(host.provider.shakeMapFrame, same(frame));
          expect(host.provider.unifiedEvents.single.source, 'usgsShakeMap');
          expect(host.map.camera.zoom, greaterThanOrEqualTo(2));
          final padding = usgsProductViewportPadding(host.context);
          await host.record(
            'shakemap-empty-aka2026tvzrwv',
            points: shakeMapFocusPoints(frame),
            anchor: LatLng(frame.event.latitude, frame.event.longitude),
            productPadding: padding,
            allVisible: true,
          );
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'empty-${size.width.toInt()}',
    );

    testWidgets(
      'actual DYFI publication preserves epicenter and existing grid legibility priority $size',
      (tester) async {
        final service = _DyfiPublication();
        final host = _Host(tester, size, dyfi: service);
        await host.start();
        try {
          final frame = originalFrame('us6000u0xi');
          service.publish(frame);
          await host.settle();
          expect(host.provider.unifiedEvents.single.source, 'usgsDyfi');
          expect(host.provider.dyfiMapFrame, same(frame));
          expect(
            smallestCellSide(host.map.camera, frame),
            greaterThanOrEqualTo(dyfiMinimumCellPixels - 1e-5),
          );
          await host.record(
            'dyfi-us6000u0xi',
            points: frame.focusPoints,
            anchor: LatLng(frame.event.latitude, frame.event.longitude),
            allVisible: false,
            productPadding: usgsProductViewportPadding(host.context),
          );
        } finally {
          await host.close();
        }
      },
      skip:
          !NativeCameraFocus.supported ||
          _selectedCase != 'dyfi-${size.width.toInt()}',
    );
  }
}
