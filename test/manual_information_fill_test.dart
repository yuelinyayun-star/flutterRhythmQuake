import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/unified_ui_fonts.dart';

const scenario = String.fromEnvironment(
  'MANUAL_FILL_CASE',
  defaultValue: 'jma',
);
final out = Directory('tmp/manual_information_fill_20261104/render');

dynamic read(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync(encoding: utf8));

UnifiedQuakeData originalEvent() {
  switch (scenario) {
    case 'jma':
      final rows = (read('jma_voice/p2p_history_20260921.json') as List)
          .cast<Map<String, dynamic>>();
      return QuakeEventAdapter.convert(
        'jmaEqlist',
        rows.firstWhere(
          (e) =>
              e['issue']['type'] == 'DetailScale' &&
              e['earthquake']['time'] == '2026/09/21 22:38:00',
        ),
        2,
      )!;
    case 'cwa':
      return QuakeEventAdapter.convert(
        'cwaEqlist',
        read('source_estimation/cwa_report_115068_original.json')
            as Map<String, dynamic>,
        0,
      )!;
    case 'cenc':
      return QuakeEventAdapter.convert(
        'cencEqlist',
        Map<String, dynamic>.from(
          read('cenc_history_20261014/wolfx.original.json')['No1'],
        ),
        0,
      )!;
    case 'kma':
      final rows = read('catalog_20260917/whews_all.json') as List;
      final row = rows.firstWhere((e) => e['source'] == 'kma');
      return QuakeEventAdapter.convertWhews(
        'kma',
        Map<String, dynamic>.from(row['Data']),
      )!;
    default:
      throw StateError(scenario);
  }
}

class _Provider extends QuakeProvider {
  _Provider(this.report)
    : super(startCatalogServices: false, nativeUnifiedEvents: true);
  final UnifiedQuakeData report;
  bool automatic = true;
  @override
  int get unifiedMapRevision => super.unifiedMapRevision + (automatic ? 0 : 1);
  @override
  List<UnifiedQuakeData> get unifiedEvents => automatic ? [report] : [];
  @override
  List<QuakeMessage> get unifiedMapEvents =>
      automatic ? [unifiedToQuakeMessageForTest(report)] : [];
  @override
  UnifiedQuakeData? get currentUnifiedEvent => automatic ? report : null;
  void hideAutomatic() {
    automatic = false;
    notifyListeners();
  }

  void restoreAutomatic() {
    automatic = true;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    out.createSync(recursive: true);
    SharedPreferences.setMockInitialValues({
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
          (_) async => out.absolute.path,
        );
  });

  testWidgets(
    'original $scenario manual selection keeps automatic fill geometry and colors',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      final event = originalEvent();
      final original = jsonEncode(event.toMap());
      final provider = _Provider(event);
      final state = MapStateProvider();
      final controller = MapController();
      final imageKey = GlobalKey();
      await tester.runAsync(() => provider.eewHistoryReadyForTest);
      var notifications = 0;
      provider.onUnifiedEventNotified = (_, _) => notifications++;
      final row = provider.unifiedToQuakeMessageForTest(event);
      await tester.runAsync(loadUnifiedUiFonts);
      expect(row.informationMap!.warnArea, event.warnArea);
      final restored = QuakeMessage.fromMap(
        jsonDecode(jsonEncode(row.toMap())) as Map<String, dynamic>,
      );
      expect(restored.informationMap!.toMap(), row.informationMap!.toMap());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: state),
          ],
          child: MaterialApp(
            home: RepaintBoundary(
              key: imageKey,
              child: Scaffold(body: QuakeMapView(mapController: controller)),
            ),
          ),
        ),
      );
      state.setController(controller, const TestVSync());
      Future<void> settleFill() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 90)),
          );
          await tester.pump(const Duration(milliseconds: 90));
        }
      }

      List<Object?> shapes() => tester
          .widgetList<PolygonLayer>(
            find.descendant(
              of: find.byType(IntensityFillLayer),
              matching: find.byType(PolygonLayer),
            ),
          )
          .expand((layer) => layer.polygons)
          .map(
            (p) => [
              p.color?.toARGB32(),
              p.borderColor.toARGB32(),
              p.borderStrokeWidth,
              p.points
                  .map((point) => [point.latitude, point.longitude])
                  .toList(),
            ],
          )
          .toList();
      await settleFill();
      final automatic = shapes();
      // This original M2.9 KMA bulletin has no painted >=1 region in the
      // existing automatic model. It must remain empty on manual selection.
      if (scenario == 'kma') {
        expect(automatic, isEmpty);
      } else {
        expect(automatic, isNotEmpty);
      }
      // Use the real map-state selection entry point, not the layer directly.
      state.selectHistoryEvent(restored);
      await settleFill();
      expect(find.byType(InformationEventFillLayer), findsOneWidget);
      expect(shapes(), automatic);
      // Manual fill must remain after the automatic report is gone.
      provider.hideAutomatic();
      await settleFill();
      expect(shapes(), automatic);
      expect(provider.selectedInformationMapEvent!.warnArea, event.warnArea);
      expect(
        tester
            .widget<NiedIntensityLayer>(find.byType(NiedIntensityLayer))
            .informationFocusDotsOnly,
        scenario == 'jma',
      );
      expect(
        identical(
          provider.selectedInformationMapEvent,
          provider.selectedInformationMapEvent,
        ),
        isTrue,
      );
      await tester.runAsync(() async {
        final boundary =
            imageKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${out.path}/$scenario-manual.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      state.clearSelectedHistoryEvent();
      await settleFill();
      expect(find.byType(InformationEventFillLayer), findsNothing);
      expect(shapes(), isEmpty);
      expect(provider.selectedInformationMapEvent, isNull);
      provider.restoreAutomatic();
      await settleFill();
      expect(shapes(), automatic);
      expect(notifications, 0);
      expect(jsonEncode(event.toMap()), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugPrint('MANUAL_FILL_VERIFIED $scenario polygons=${automatic.length}');
    },
  );
}
