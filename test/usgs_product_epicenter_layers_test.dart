import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/models/history_map_product.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/unified_event_wave_layers.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_layer.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_shakemap_layer.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'usgs_dyfi_test.dart' show dyfiEvent;
import 'usgs_dyfi_test.dart' as dyfi;
import 'usgs_shakemap_test.dart' as shake;
import 'support/unified_ui_fonts.dart';

const fixture = 'test/fixtures/usgs_dyfi/two_events_20261102';
Future<UsgsDyfiFrame> originalFrame(String name) async {
  final bytes = File(
    '$fixture/$name.detail.original.geojson',
  ).readAsBytesSync();
  final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final grid = File('$fixture/$name.dyfi_geo.kmz').readAsBytesSync();
  final product = UsgsDyfiProduct.fromDetail(raw)!;
  final service = UsgsDyfiService(
    client: MockClient(
      (r) async =>
          http.Response.bytes(r.url == product.gridUrl ? grid : bytes, 200),
    ),
  );
  try {
    await service.select(dyfiEvent(raw));
    expect(service.status, isNull);
    return service.manualFrame!;
  } finally {
    service.dispose();
  }
}

// Publication/selection states only; every earthquake/product/grid stays original.
class OriginalPublication extends UsgsDyfiService {
  OriginalPublication(this.originals)
    : super(client: MockClient((_) async => http.Response('', 404)));
  final List<UsgsDyfiFrame> originals;
  UsgsDyfiFrame? automatic, manual;
  @override
  UsgsDyfiFrame? get automaticFrame => automatic;
  @override
  UsgsDyfiFrame? get manualFrame => manual;
  @override
  UsgsDyfiFrame? get frame => manual ?? automatic;
  @override
  Future<void> select(QuakeMessage? event, {bool showProduct = true}) async {
    manual = event == null || !showProduct
        ? null
        : originals.firstWhere((f) => f.event.eventId == event.eventId);
    notifyListeners();
  }

  void publish(UsgsDyfiFrame frame) {
    automatic = frame;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);
  testWidgets(
    'manual California selection cannot hide automatic Kenai DYFI epicenter',
    (tester) async {
      late UsgsDyfiFrame california, kenai;
      await tester.runAsync(() async {
        await loadUnifiedUiFonts();
        california = await originalFrame('california');
        kenai = await originalFrame('kenai');
      });
      final service = OriginalPublication([california, kenai]);
      final provider = QuakeProvider(
        startCatalogServices: false,
        dyfiService: service,
        shakeMapService: UsgsShakeMapService(
          client: MockClient((_) async => http.Response('', 404)),
        ),
      );
      provider.selectHistoryMapProducts(
        california.event,
        product: HistoryMapProduct.dyfi,
      );
      service.publish(kenai);
      expect(
        provider.historyInfoDisplayEvent?.eventId,
        california.event.eventId,
      );
      expect(provider.currentUnifiedEvent?.eventId, kenai.event.eventId);
      expect(provider.dyfiMapFrame, same(kenai));
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: unifiedUiTestTheme(),
          home: RepaintBoundary(
            key: capture,
            child: FlutterMap(
              options: MapOptions(
                backgroundColor: const Color(0xff202124),
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(kenai.focusPoints),
                  padding: const EdgeInsets.all(35),
                ),
              ),
              children: [
                UsgsDyfiLayer(frame: provider.dyfiMapFrame),
                UnifiedEventWaveLayers(
                  events: provider.unifiedEvents,
                  mapEvents: provider.unifiedMapEvents,
                  blinkOn: true,
                  waveColor: (_) => Colors.blue,
                ),
                HistoryMarkerLayer(event: california.event),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final auto = tester
          .widgetList<QuakeWaveLayer>(find.byType(QuakeWaveLayer))
          .toList();
      expect(
        auto,
        hasLength(1),
        reason:
            'automatic product must reuse the ordinary information epicenter path',
      );
      expect(auto.single.event.eventId, kenai.event.eventId);
      expect(auto.single.event.latitude, kenai.event.latitude);
      expect(auto.single.event.longitude, kenai.event.longitude);
      expect(auto.single.showWaves, isFalse);
      expect(auto.single.blinkOn, isTrue);
      expect(find.byType(HistoryMarkerLayer), findsOneWidget);
      expect(find.byType(UsgsDyfiGridLayer), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final picture =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/ui-previews/dyfi').create(recursive: true);
        await File(
          'build/ui-previews/dyfi/automatic-kenai-with-manual-california.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets(
    'two automatic DYFI identities both render using original event coordinates',
    (tester) async {
      late UsgsDyfiFrame a, b;
      await tester.runAsync(() async {
        a = await originalFrame('california');
        b = await originalFrame('kenai');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: a.focusPoints.first,
              initialZoom: 2,
            ),
            children: [
              UnifiedEventWaveLayers(
                events: [
                  QuakeEventAdapter.dyfiInfo(a),
                  QuakeEventAdapter.dyfiInfo(b),
                ],
                mapEvents: [a.event, b.event],
                blinkOn: false,
                waveColor: (_) => Colors.blue,
              ),
            ],
          ),
        ),
      );
      final widgets = tester
          .widgetList<QuakeWaveLayer>(find.byType(QuakeWaveLayer))
          .toList();
      expect(widgets.map((w) => w.event.eventId), [
        a.event.eventId,
        b.event.eventId,
      ]);
      expect(widgets.every((w) => !w.showWaves && w.blinkOn), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  test('all source original bytes remain unchanged', () {
    for (final row in jsonDecode(
      File('$fixture/manifest.json').readAsStringSync(),
    )) {
      expect(
        sha256
            .convert(File('$fixture/${row['file']}').readAsBytesSync())
            .toString(),
        row['sha256'],
      );
    }
  });
  testWidgets(
    'automatic ShakeMap uses the same epicenter layer and retains the real MMI contours',
    (tester) async {
      final raw = shake.readJson('ci41345415.detail.original.geojson');
      final frame = UsgsShakeMapFrame(
        event: shake.eventFor(raw),
        product: UsgsShakeMapProduct.fromDetail(raw)!,
        contours: UsgsMmiContour.parse(
          shake.readJson('ci41345415.cont_mmi.original.json'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                frame.event.latitude,
                frame.event.longitude,
              ),
              initialZoom: 6,
            ),
            children: [
              UsgsShakeMapLayer(frame: frame),
              UnifiedEventWaveLayers(
                events: [QuakeEventAdapter.shakeMapInfo(frame)],
                mapEvents: [frame.event],
                blinkOn: false,
                waveColor: (_) => Colors.blue,
              ),
            ],
          ),
        ),
      );
      final marker = tester.widget<QuakeWaveLayer>(find.byType(QuakeWaveLayer));
      expect(marker.showWaves, isFalse);
      expect(marker.blinkOn, isTrue);
      expect(marker.event.latitude, frame.event.latitude);
      expect(marker.event.longitude, frame.event.longitude);
      expect(find.byType(UsgsShakeMapLayer), findsOneWidget);
      expect(frame.contours, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'same-event DYFI and ShakeMap do not duplicate the epicenter or override an ordinary report',
    (tester) async {
      final raw = shake.readJson('ci41345415.detail.original.geojson');
      final sf = UsgsShakeMapFrame(
        event: shake.eventFor(raw),
        product: UsgsShakeMapProduct.fromDetail(raw)!,
        contours: UsgsMmiContour.parse(
          shake.readJson('ci41345415.cont_mmi.original.json'),
        ),
      );
      final dr = dyfi.dyfiDetail();
      final df = UsgsDyfiFrame(
        event: dyfiEvent(dr),
        product: UsgsDyfiProduct.fromDetail(dr)!,
        cells: null,
      );
      final ordinary = QuakeEventAdapter.catalogInfo(sf.event, 'usgsEqlist');
      for (final includeOrdinary in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(sf.event.latitude, sf.event.longitude),
                initialZoom: 5,
              ),
              children: [
                UnifiedEventWaveLayers(
                  events: [
                    QuakeEventAdapter.dyfiInfo(df),
                    QuakeEventAdapter.shakeMapInfo(sf),
                    if (includeOrdinary) ordinary,
                  ],
                  mapEvents: [
                    df.event,
                    sf.event,
                    if (includeOrdinary) sf.event,
                  ],
                  blinkOn: false,
                  waveColor: (_) => Colors.blue,
                ),
              ],
            ),
          ),
        );
        expect(find.byType(QuakeWaveLayer), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
