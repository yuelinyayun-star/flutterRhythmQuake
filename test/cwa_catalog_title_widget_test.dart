import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/ui/eqlist_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/unified_ui_fonts.dart';

// Display original captured data without rewriting its timestamp to make an
// old observation pass live admission.
class _CatalogDisplay extends QuakeProvider {
  _CatalogDisplay(this.rows)
    : super(startCatalogServices: false, nativeUnifiedEvents: false);
  final List<QuakeMessage> rows;
  @override
  List<QuakeMessage> get historyList => rows;
  @override
  Map<String, List<QuakeMessage>> get historyBySource => {'cwaEqlist': rows};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'weather_alarm_local_only': false,
    }),
  );
  testWidgets(
    'actual CWA list renders the area for new and previously saved Jian locations',
    (tester) async {
      tester.view.physicalSize = const Size(1050, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadUnifiedUiFonts);
      final raw =
          (jsonDecode(
                    File(
                      'test/fixtures/cwa_catalog_20261028/jian_cwalist.original.json',
                    ).readAsStringSync(encoding: utf8),
                  )
                  as Map)['Data'][0]
              as Map<String, dynamic>;
      final mapper = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: false,
      );
      final event = QuakeEventAdapter.convertJian('cwa', raw)!;
      final row = mapper.unifiedToQuakeMessageForTest(event);
      mapper.dispose();
      final boundary = GlobalKey();
      for (final originalLocation in [false, true]) {
        final provider = _CatalogDisplay([
          originalLocation
              ? row.copyWith(location: raw['placeName'] as String)
              : row,
        ]);
        final map = MapStateProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: map),
            ],
            child: MaterialApp(
              theme: unifiedUiTestTheme(),
              home: Scaffold(
                backgroundColor: const Color(0xff202124),
                body: Center(
                  child: RepaintBoundary(
                    key: boundary,
                    child: const SizedBox(
                      width: 420,
                      height: 220,
                      child: EqlistPanel(embedded: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('臺灣東部海域'), findsOneWidget);
        expect(find.textContaining('花蓮縣政府東方'), findsNothing);
        expect(tester.takeException(), isNull);
        if (!originalLocation) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('tmp/cwa_fields_20261028').create(recursive: true);
            await File(
              'tmp/cwa_fields_20261028/cwa-list-preview.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
        map.dispose();
      }
    },
  );
}
