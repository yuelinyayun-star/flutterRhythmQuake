import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/native_jma_eew.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/widgets/map/history_marker_layer.dart';
import 'package:flutterrhythmquake/widgets/map/unified_event_wave_layers.dart';
import 'package:flutterrhythmquake/widgets/map/vector_basemap_layer.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/local_eew_sidebar_panel.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_alert_card.dart';
import 'support/unified_ui_fonts.dart';
import 'unified_card_layout_test.dart' show capturedCards;
import 'history_panel_layout_test.dart' show HistoryProvider;
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/widgets/ui/history_panel.dart';

const fixtures = 'test/fixtures/jma_plum_20261106';
const label = 'PLUM所得假定震源';
Map<String, dynamic> original(String name) =>
    jsonDecode(File('$fixtures/$name.json').readAsStringSync(encoding: utf8))
        as Map<String, dynamic>;
UnifiedQuakeData report(int n) => QuakeEventAdapter.convertWhews(
  'jma_eew',
  original('whews_report_${n.toString().padLeft(2, '0')}'),
)!;

class _CardProvider extends QuakeProvider {
  _CardProvider(this.card) : super(startCatalogServices: false);
  final UnifiedQuakeData card;
  @override
  List<UnifiedQuakeData> get unifiedEvents => [card];
  @override
  UnifiedQuakeData? get mobileCameraDisplayEvent => card;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  for (var n = 1; n <= 5; n++) {
    test(
      'original PLUM report $n keeps EEW, source values and countdown',
      () async {
        final raw = original('whews_report_${n.toString().padLeft(2, '0')}');
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertWhews('jma_eew', raw)!;
        expect(event.isEew, isTrue);
        expect(event.isAssumption, isTrue);
        expect(event.magnitude, -1);
        expect(event.depth, 10);
        expect(event.maxIntensity, raw['epiIntensity']);
        expect(event.isFinal, raw['final']);
        expect(event.isCanceled, raw['cancel']);
        expect(event.isWarn, isFalse);
        expect(event.sourcePayload, raw);
        final display = UnifiedEventPresentation.fromEvent(event);
      expect(display.title, contains('（予報）（PLUM）'));
        expect(display.secondaryText, label);
        expect(event.titleText, '緊急地震速報（予報）');
        await TravelTimeService().ensureLoaded();
        final estimate = calculateLocalEewEstimate(
          event,
          userLat: 29.36,
          userLng: 120.17,
          elapsedSeconds: 0,
        );
        // Exact unchanged pre-fix result from the read-only audit.
        expect(estimate.secondsToSWave, 465);
        expect(estimate.distanceKm, closeTo(2074.3895292703405, 1e-6));
        expect(estimate.intensity, isNull);
        expect(jsonEncode(raw), before);
        expect(UnifiedQuakeData.fromMap(event.toMap()).isAssumption, isTrue);
      },
    );
  }

  test(
    'previously saved original report recovers PLUM without changing raw fields',
    () {
      final saved = original('whews_saved_report_05');
      final before = jsonEncode(saved);
      expect(saved['isAssumption'], isFalse); // The actual pre-fix record.
      final event = UnifiedQuakeData.fromMap(saved);
      expect(event.isAssumption, isTrue);
      expect(event.isEew, isTrue);
      expect(event.sourcePayload, saved['sourcePayload']);
      expect(UnifiedEventPresentation.fromEvent(event).secondaryText, label);
      expect(jsonEncode(saved), before);
      final summary = event.copyWith(clearSourcePayload: true);
      expect(UnifiedQuakeData.fromMap(summary.toMap()).isAssumption, isTrue);
    },
  );

  test(
    'native flag policy is used; ordinary captured events retain their presentation',
    () {
      if (Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
        expect(NativeJmaEew.supported, isTrue);
      }
      for (final event in capturedCards().values) {
        final before = jsonEncode(event.toMap());
        expect(event.displayTitleText, event.titleText);
        expect(event.plumMissingParametersText, isNull);
        expect(jsonEncode(event.toMap()), before);
      }
      final raw =
          original('jian_documented_non_plum')['Data'] as Map<String, dynamic>;
      final event = QuakeEventAdapter.convertJian('jma-eew', raw)!;
      expect(event.isAssumption, isFalse);
      expect(event.plumMissingParametersText, isNull);
      expect(event.sourcePayload, raw);
    },
  );

  test(
    'PLUM presentation checks missing magnitude or depth without replacing supplied parameters',
    () {
      // UI-only parameter combinations, not modified source reports or live data.
      final e = report(5);
      expect(
        e.copyWith(magnitude: 4, depth: -1).plumMissingParametersText,
        label,
      );
      expect(
        e.copyWith(magnitude: -1, depth: -1).plumMissingParametersText,
        label,
      );
      final known = e.copyWith(magnitude: 4, depth: 10);
      expect(known.plumMissingParametersText, isNull);
      expect(known.magnitude, 4);
      expect(known.depth, 10);
      expect(
        known.copyWith(source: 'cwaEew').plumMissingParametersText,
        isNull,
      );
      expect(
        known.copyWith(source: 'jmaEqlist', isEew: false).displayTitleText,
        known.titleText,
      );
      expect(
        e.copyWith(titleText: '既有 PLUM 标题').displayTitleText,
        '既有 PLUM 标题',
      );
    },
  );

  testWidgets(
    'actual unified UI, alternate card, history and map keep PLUM waves',
    (tester) async {
      await tester.runAsync(loadUnifiedUiFonts);
      await tester.runAsync(() async {
        // Canvas text without a family otherwise uses test Ahem blocks.
        final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
        for (final family in ['Ahem', 'Roboto']) {
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
        final icons = File(
          'D:/flutter_windows_3.41.1-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (await icons.exists()) {
          await (FontLoader(
            'MaterialIcons',
          )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
        }
      });
      await tester.runAsync(() => TravelTimeService().ensureLoaded());
      tester.view.physicalSize = const Size(1400, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final event = report(5);
      final provider = _CardProvider(event);
      final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
      final history = HistoryProvider([
        EewEventGroup(
          eventId: event.eventId,
          firstArrivedAt: DateTime.utc(2026, 11, 6, 10, 41, 18),
          reports: [for (var n = 5; n >= 1; n--) report(n)],
        ),
      ]);
      final qm = QuakeMessage(
        source: QuakeSourceType.jma_fan,
        eventId: event.eventId,
        location: event.hypocenter,
        magnitude: event.magnitude,
        depth: event.depth,
        latitude: event.lat!,
        longitude: event.lng!,
        originTime: event.originTime!,
        timeZone: 9,
        isAssumption: event.isAssumption,
        isInfoEvent: false,
        jmaShindo: event.maxIntensity,
      );
      final controller = MapController();
      final clock = event.originTime!
          .subtract(const Duration(hours: 1))
          .add(const Duration(seconds: 25));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
          ],
          child: MaterialApp(
            theme: unifiedUiTestTheme(),
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('plum-preview'),
                child: ColoredBox(
                  color: const Color(0xff202124),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 410,
                        child: Column(
                          children: [
                            const AlertModule(),
                            UnifiedAlertCard(event: event),
                            Expanded(
                              child:
                                  ChangeNotifierProvider<QuakeProvider>.value(
                                    value: history,
                                    child: const HistoryPanel(),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: FlutterMap(
                          mapController: controller,
                          options: MapOptions(
                            initialCenter: LatLng(event.lat!, event.lng!),
                            initialZoom: 7,
                            backgroundColor: VectorBasemapLayer.oceanColor,
                          ),
                          children: [
                            const VectorBasemapLayer(),
                            QuakeWaveLayer(
                              event: qm,
                              displayClock: () => clock,
                              sWaveColor: Colors.yellow,
                            ),
                          ],
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
      for (var n = 0; n < 20; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(tester.takeException(), isNull);
      expect(find.text(label), findsNWidgets(3));
      expect(find.textContaining('規模 調査中'), findsNothing);
      expect(find.textContaining('（PLUM）'), findsNWidgets(3));
      expect(
        tester.widget<QuakeWaveLayer>(find.byType(QuakeWaveLayer)).showWaves,
        isTrue,
      );
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('plum-preview')),
        );
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'tmp/jma_plum_fix_20261106/unified-history-map.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      // Exercise the unchanged production aggregator separately, not only a direct layer.
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(event.lat!, event.lng!),
              initialZoom: 7,
            ),
            children: [
              UnifiedEventWaveLayers(
                events: [event],
                mapEvents: [qm],
                waveColor: (_) => Colors.yellow,
                blinkOn: false,
              ),
            ],
          ),
        ),
      );
      final layer = tester.widget<QuakeWaveLayer>(find.byType(QuakeWaveLayer));
      expect(layer.showWaves, isTrue);
      expect(layer.blinkOn, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(event.lat!, event.lng!),
              initialZoom: 7,
            ),
            children: [HistoryMarkerLayer(event: qm)],
          ),
        ),
      );
      expect(
        tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is HistoryCrossPainter,
              ),
            )
            .painter,
        isA<HistoryCrossPainter>().having(
          (p) => p.isPlum,
          'manual PLUM label',
          true,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      history.dispose();
      mapState.dispose();
      controller.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
