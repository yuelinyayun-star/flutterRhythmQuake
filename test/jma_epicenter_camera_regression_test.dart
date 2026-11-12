import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/jma_info_focus.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Original P2P body for the exact earthquake in the user's screenshot.
final rawBody = File(
  'test/fixtures/jma_camera_20261030/p2p_history.original.json',
).readAsStringSync(encoding: utf8);
final raw = (jsonDecode(rawBody) as List)
    .cast<Map<String, dynamic>>()
    .singleWhere((e) => e['id'] == '6ae45a03e88ee598246bf44c');
final event = QuakeEventAdapter.convert('jmaEqlist', raw, 2)!;
final epicenter = LatLng(event.lat!, event.lng!);
final points = jmaInfoFocusPoints(
  warnAreaJson: event.warnArea,
  epicenterLatitude: event.lat,
  epicenterLongitude: event.lng,
);

class _AcceptedReport extends QuakeProvider {
  _AcceptedReport()
    : super(startCatalogServices: false, nativeUnifiedEvents: false);
  bool visible = false;
  @override
  List<UnifiedQuakeData> get unifiedEvents => visible ? [event] : const [];
  @override
  List<QuakeMessage> get unifiedMapEvents =>
      visible ? [unifiedToQuakeMessageForTest(event)] : const [];
  @override
  UnifiedQuakeData? get currentUnifiedEvent => visible ? event : null;
  void show() {
    visible = true;
    notifyListeners();
  }
}

Future<void> finishMove(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1400)),
  );
  await tester.pump(const Duration(milliseconds: 30));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('historical camera changes reproduce the offshore displacement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const size = Size(1584, 794);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final map = MapStateProvider();
    final controller = MapController();
    addTearDown(map.dispose);
    late EdgeInsets padding;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            padding = cencIrViewportPadding(context)!;
            return FlutterMap(
              mapController: controller,
              options: MapOptions(initialCenter: epicenter, initialZoom: 6),
              children: const [],
            );
          },
        ),
      ),
    );
    map.setController(controller, const TestVSync());
    final viewport = padding.deflateRect(Offset.zero & size);
    final hypo = raw['earthquake']['hypocenter'] as Map;
    final report = QuakeMessage(
      source: QuakeSourceType.wolfx,
      eventId: raw['id'],
      location: hypo['name'],
      latitude: epicenter.latitude,
      longitude: epicenter.longitude,
      magnitude: (hypo['magnitude'] as num).toDouble(),
      depth: (hypo['depth'] as num).toDouble(),
      originTime: event.originTime!,
    );
    // Before 1963af9: information uses the event coordinates.
    map.smartMoveToEvents(
      [report],
      padding: 1,
      force: true,
      minInterval: Duration.zero,
    );
    await finishMove(tester);
    final before = controller.camera.latLngToScreenOffset(epicenter);
    expect((before - size.center(Offset.zero)).distance, lessThan(1));
    // 1963af9 introduced the combined epicenter/region point bounds.
    map.smartMoveToPoints(
      points,
      padding: 0.8,
      force: true,
      minInterval: Duration.zero,
    );
    await finishMove(tester);
    final first = controller.camera.latLngToScreenOffset(epicenter);
    expect((first - size.center(Offset.zero)).distance, greaterThan(40));
    // 81f89d1 enabled this viewport fit for JMA; current single-event path.
    map.smartMoveToPoints(
      points,
      padding: 0.8,
      viewportPadding: padding,
      force: true,
      minInterval: Duration.zero,
    );
    await finishMove(tester);
    final current = controller.camera.latLngToScreenOffset(epicenter);
    expect((current - viewport.center).distance, greaterThan(150));
    debugPrint(
      'JMA_ORIGIN before1963af9=$before introduced1963af9=$first '
      'after81f89d1=$current viewportCenter=${viewport.center} '
      'currentErrorPx=${(current - viewport.center).distance}',
    );
    expect(
      File(
        'test/fixtures/jma_camera_20261030/p2p_history.original.json',
      ).readAsStringSync(encoding: utf8),
      rawBody,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(1584, 794)]) {
    testWidgets(
      'actual JMA information keeps epicenter at viewport center $size',
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
        final cache = Directory('tmp/jma_info_center_20261030/widget-cache')
          ..createSync(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async => cache.absolute.path,
            );
        QuakeMapView.niedMonitorEnabledNotifier.value = false;
        QuakeMapView.niedLpgmEnabledNotifier.value = false;
        QuakeMapView.kmaPewsEnabledNotifier.value = false;
        QuakeMapView.pAlertEnabledNotifier.value = false;
        QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
        QuakeMapView.snetEnabledNotifier.value = false;
        QuakeMapView.tremStationEnabledNotifier.value = false;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = _AcceptedReport();
        final map = MapStateProvider();
        final controller = MapController();
        await tester.runAsync(() => provider.eewHistoryReadyForTest);
        final nativeCalls = NativeCameraFocus.supported
            ? NativeCameraFocus.calls
            : 0;
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
        provider.show();
        await tester.pump();
        await tester.pump();
        await finishMove(tester);
        final context = tester.element(find.byType(QuakeMapView));
        final viewport = cencIrViewportPadding(
          context,
        )!.deflateRect(Offset.zero & size);
        final pixel = controller.camera.latLngToScreenOffset(epicenter);
        debugPrint(
          'JMA_ACTUAL $size epicenter=$pixel '
          'viewportCenter=${viewport.center} errorPx=${(pixel - viewport.center).distance}',
        );
        expect((pixel - viewport.center).distance, lessThan(1));
        for (final point in points) {
          expect(
            viewport
                .inflate(1)
                .contains(controller.camera.latLngToScreenOffset(point)),
            isTrue,
          );
        }
        expect(
          File(
            'test/fixtures/jma_camera_20261030/p2p_history.original.json',
          ).readAsStringSync(encoding: utf8),
          rawBody,
        );
        if (NativeCameraFocus.supported) {
          expect(NativeCameraFocus.calls, greaterThan(nativeCalls));
          expect(NativeCameraFocus.outputs, 0);
        }
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
        map.dispose();
      },
    );
  }
}
