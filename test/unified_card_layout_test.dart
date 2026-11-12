import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/models/usgs_shakemap.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'package:flutterrhythmquake/services/sources/usgs_shakemap_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'support/unified_ui_fonts.dart';
import 'usgs_dyfi_test.dart' show dyfiDetail, dyfiEvent;
import 'usgs_shakemap_test.dart' show detailVersion, eventFor;

dynamic originalJson(String path) =>
    jsonDecode(File(path).readAsStringSync(encoding: utf8));

// Only captured source reports. No timestamps, coordinates, text or magnitudes
// are changed to make a historic event pass live admission.
Map<String, UnifiedQuakeData> capturedCards() {
  final whews = originalJson('test/fixtures/catalog_20260917/whews_all.json');
  final jian = originalJson('test/fixtures/jian/all.json');
  final dyfi = dyfiDetail();
  final shake = detailVersion('3');
  return {
    for (final frame in whews as List)
      if (const [
        'jma_eew',
        'jma',
        'cwa_eew',
        'sa_eew',
        'cenc',
        'kma',
        'kma_eew',
        'va',
        'usgs',
        'emsc',
      ].contains(frame['source']))
        'WHEWS ${frame['source']}': QuakeEventAdapter.convertWhews(
          frame['source'],
          Map<String, dynamic>.from(frame['Data']),
        )!,
    for (final source in ['cea', 'cea-pr', 'sa', 'cwa-eew'])
      'Jian $source': QuakeEventAdapter.convertJian(
        source,
        Map<String, dynamic>.from(jian['source：$source']['Data']),
      )!,
    for (final group
        in originalJson('test/fixtures/cmt_history_20261009.original.json')
            as List)
      for (final raw in group['rows'] as List)
        group['source']: QuakeEventAdapter.catalogInfo(
          QuakeMessage.fromMap(Map<String, dynamic>.from(raw)),
          group['source'],
        ),
    'SASMEX': SasmexService.parseRelayFrame(
      Map<String, dynamic>.from(
        originalJson('test/fixtures/sasmex_firestore_20261006.relay.json'),
      ),
    )!,
    'DYFI': QuakeEventAdapter.dyfiInfo(
      UsgsDyfiFrame(
        event: dyfiEvent(dyfi),
        product: UsgsDyfiProduct.fromDetail(dyfi)!,
        cells: UsgsDyfiCell.parse(
          originalJson(
            'test/fixtures/usgs_dyfi/ci41345415.dyfi_geo_10km.original.geojson',
          ),
        ),
      ),
    ),
    'ShakeMap': QuakeEventAdapter.shakeMapInfo(
      UsgsShakeMapFrame(
        event: eventFor(shake),
        product: UsgsShakeMapProduct.fromDetail(shake)!,
        contours: UsgsMmiContour.parse(
          originalJson(
            'test/fixtures/usgs_shakemap/us6000u0xi.cont_mmi.original.json',
          ),
        ),
      ),
    ),
  };
}

class _LayoutProvider extends QuakeProvider {
  _LayoutProvider()
    : super(
        startCatalogServices: false,
        dyfiService: UsgsDyfiService(
          client: MockClient((_) async => http.Response('', 404)),
        ),
        shakeMapService: UsgsShakeMapService(
          client: MockClient((_) async => http.Response('', 404)),
        ),
      );
  UnifiedQuakeData? card;
  @override
  List<UnifiedQuakeData> get unifiedEvents => [?card];
  @override
  UnifiedQuakeData? get mobileCameraDisplayEvent => card;
  void show(UnifiedQuakeData next) {
    card = next;
    notifyListeners();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);
  for (final width in [390.0, 935.0, 1266.0, 1578.0, 1700.0]) {
    testWidgets('all captured compact card rows fit at width $width', (
      tester,
    ) async {
      await tester.runAsync(loadUnifiedUiFonts);
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = _LayoutProvider();
      final state = MapStateProvider()..setShowEstimatedEpicenter(false);
      var disposed = false;
      addTearDown(() {
        if (!disposed) {
          provider.dispose();
          state.dispose();
        }
      });
      final cards = capturedCards();
      for (final entry in cards.entries) {
        final before = jsonEncode(entry.value.toMap());
        provider.show(entry.value);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: state),
            ],
            child: MaterialApp(
              theme: unifiedUiTestTheme(),
              home: const Scaffold(body: AlertModule()),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: entry.key);
        final text = find
            .text(UnifiedEventPresentation.fromEvent(entry.value).primaryText)
            .first;
        final column = find
            .ancestor(of: text, matching: find.byType(Column))
            .first;
        final rows = tester
            .widget<Column>(column)
            .children
            .whereType<Text>()
            .toList();
        final bounds = tester.getRect(column);
        double bottom = bounds.top;
        for (final row in rows) {
          final rect = tester.getRect(find.byWidget(row));
          expect(
            rect.top,
            greaterThanOrEqualTo(bottom - .01),
            reason: entry.key,
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(bounds.bottom + .01),
            reason: entry.key,
          );
          bottom = rect.bottom;
        }
        expect(jsonEncode(entry.value.toMap()), before);
      }
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      state.dispose();
      disposed = true;
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
