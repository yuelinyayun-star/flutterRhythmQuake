import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_decoder.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/nied_intensity_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'NIED dots follow painted JMA/P2P intensity independently of card or detection focus',
    (tester) async {
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
      final cache = Directory(
        'tmp/nied_jma_information_expansion_20261103/widget-cache',
      )..createSync(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => cache.absolute.path,
          );
      QuakeMapView.niedMonitorEnabledNotifier.value = false;
      QuakeMapView.niedLpgmEnabledNotifier.value = false;
      QuakeMapView.kmaPewsEnabledNotifier.value = false;
      QuakeMapView.pAlertEnabledNotifier.value = false;
      QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
      QuakeMapView.snetEnabledNotifier.value = false;
      QuakeMapView.tremStationEnabledNotifier.value = false;
      tester.view.physicalSize = const Size(1584, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = QuakeProvider(startCatalogServices: false);
      await tester.runAsync(() => TopoJsonLoader.loadJpEew());
      final map = MapStateProvider();
      final controller = MapController();
      var disposed = false;
      addTearDown(() async {
        if (disposed) return;
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
        map.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: map),
          ],
          child: MaterialApp(
            home: Scaffold(body: QuakeMapView(mapController: controller)),
          ),
        ),
      );
      map.setController(controller, const TestVSync());
      await tester.pump(const Duration(milliseconds: 50));

      dynamic read(String file) =>
          jsonDecode(File(file).readAsStringSync(encoding: utf8));
      final jian = read('test/fixtures/catalog_20260917/jian_all.json') as Map;
      final whews =
          read('test/fixtures/catalog_20260917/whews_all.json') as List;
      final p2p =
          read('test/fixtures/jma_camera_20261030/p2p_history.original.json')
              as List;
      UnifiedQuakeData fromJian(String source) => QuakeEventAdapter.convertJian(
        source,
        Map<String, dynamic>.from(jian['source：$source']['Data'] as Map),
      )!;
      final jma = fromJian('jma');
      final usgs = fromJian('usgs');
      final cases = <(String, UnifiedQuakeData, bool)>[
        ('JIAN JMA', jma, true),
        (
          'WHEWS JMA',
          LocalInjectDecoder.decode(
            whews.firstWhere((e) => e['source'] == 'jma'),
            format: 'whews',
          ).events.single,
          true,
        ),
        for (final type in ['ScalePrompt', 'Destination', 'DetailScale'])
          (
            'P2P $type',
            LocalInjectDecoder.decode(
              p2p.firstWhere((e) => e['issue']['type'] == type),
              format: 'p2p',
            ).events.single,
            true,
          ),
        ('CWA', fromJian('cwa'), false),
        ('CENC', fromJian('cenc'), false),
        ('USGS', usgs, false),
        (
          'P2P foreign without Japanese intensity fill',
          LocalInjectDecoder.decode(
            p2p.firstWhere((e) => e['issue']['type'] == 'Foreign'),
            format: 'p2p',
          ).events.single,
          false,
        ),
        ('JMA EEW', fromJian('jma-eew'), false),
      ];
      const session = 'nied-information-style-scope';
      UnifiedQuakeData deliver(UnifiedQuakeData original) {
        final event = original.copyWith(
          replaySessionId: session,
          replayClockOffset: DateTime.now().toUtc().difference(
            QuakeTime.unifiedInstantUtc(original),
          ),
          arrivedAt: DateTime.now(),
        );
        // Exercise the actual replay delivery callback and native event owner.
        provider.historyReplay.onReport(event);
        return event;
      }

      bool getDots() => tester
          .widget<NiedIntensityLayer>(find.byType(NiedIntensityLayer))
          .informationFocusDotsOnly;
      for (final size in [const Size(1584, 892), const Size(430, 900)]) {
        tester.view.physicalSize = size;
        await tester.pump();
        for (final (name, original, expected) in cases) {
          provider.historyReplay.onClear(session);
          await tester.pump();
          final payload = jsonEncode(original.sourcePayload);
          final event = deliver(original);
          await tester.pump();
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expect(
            provider.unifiedEvents.any(
              (e) => e.source == event.source && e.eventId == event.eventId,
            ),
            true,
            reason: name,
          );
          expect(getDots(), expected, reason: '$name $size');
          expect(jsonEncode(original.sourcePayload), payload);
          debugPrint('NIED_STYLE $name size=$size dots=${getDots()}');
        }
      }
      provider.historyReplay.onClear(session);
      await tester.pump();
      map.pauseAutoZoomForGesture();
      final jmaEvent = deliver(jma);
      final usgsEvent = deliver(usgs);
      await tester.pump();
      provider.setMobileCameraInfoFocus(jmaEvent);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(getDots(), true);
      final jpFill = tester
          .widgetList<IntensityFillLayer>(find.byType(IntensityFillLayer))
          .singleWhere((layer) => layer.source == 'jp');
      expect(
        tester
            .widgetList<PolygonLayer>(
              find.descendant(
                of: find.byWidget(jpFill),
                matching: find.byType(PolygonLayer),
              ),
            )
            .any((layer) => layer.polygons.isNotEmpty),
        true,
      );
      provider.setMobileCameraInfoFocus(usgsEvent);
      await tester.pump();
      expect(provider.unifiedEvents.any((e) => e.source == 'jmaEqlist'), true);
      expect(
        getDots(),
        true,
        reason: 'JMA intensity remains painted when the card switches to USGS',
      );
      provider.setCameraSourceFocus(const []);
      await tester.pump();
      expect(
        getDots(),
        true,
        reason: 'Detection focus must not unbind still-painted JMA intensity',
      );
      provider.historyReplay.onClear(session);
      await tester.pump();
      expect(getDots(), false);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      map.dispose();
      disposed = true;
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
