import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_server.dart';
import 'package:flutterrhythmquake/services/native_camera_focus.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:flutterrhythmquake/services/sources/mock_input_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_focus.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealLoopback extends HttpOverrides {}

const _verifyDefaultExpiry = bool.fromEnvironment('VERIFY_DEFAULT_EXPIRY');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'original HTTP report reaches native provider and centered rendered map without a desktop window',
    (tester) async {
      expect(NativeCameraFocus.supported, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
      final out = Directory('tmp/jma_info_center_20261030/headless-http')
        ..createSync(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => out.absolute.path,
          );
      QuakeMapView.niedMonitorEnabledNotifier.value = false;
      QuakeMapView.niedLpgmEnabledNotifier.value = false;
      QuakeMapView.kmaPewsEnabledNotifier.value = false;
      QuakeMapView.pAlertEnabledNotifier.value = false;
      QuakeMapView.wolfxSeisJsEnabledNotifier.value = false;
      QuakeMapView.snetEnabledNotifier.value = false;
      QuakeMapView.tremStationEnabledNotifier.value = false;
      tester.view.physicalSize = const Size(1584, 794);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mock = MockInputService();
      SourceManager().registerSource(mock);
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
      );
      // Existing, explicit simulation setting: retain original old telegrams.
      // No source timestamp or payload is rewritten.
      provider.setShowStaleInfoEvent(!_verifyDefaultExpiry);
      final map = MapStateProvider();
      final controller = MapController();
      final imageKey = GlobalKey();
      final fonts = FontLoader('JetBrainsMono')
        ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf'));
      await fonts.load();
      final client = _RealLoopback().createHttpClient(null);
      final bytes = File(
        'tmp/jma_info_center_20261030/runtime-injected-original.json',
      ).readAsBytesSync();
      final raw = jsonDecode(utf8.decode(bytes));
      Map<String, dynamic>? responseBody;
      final trace = <Map<String, dynamic>>[];
      provider.addListener(
        () => trace.add({
          'active': provider.unifiedEvents.map((e) => e.eventId).toList(),
        }),
      );
      await tester.runAsync(() async {
        await provider.eewHistoryReadyForTest;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        await LocalInjectServer.start(port: port);
      });
      final beforeCalls = NativeCameraFocus.calls;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: map),
          ],
          child: MaterialApp(
            home: RepaintBoundary(
              key: imageKey,
              child: Scaffold(body: QuakeMapView(mapController: controller)),
            ),
          ),
        ),
      );
      map.setController(controller, const TestVSync());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        final request = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${LocalInjectServer.boundPort}/inject?format=p2p',
          ),
        );
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.add(bytes);
        final response = await request.close();
        expect(response.statusCode, 200);
        responseBody = jsonDecode(await utf8.decoder.bind(response).join());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(responseBody!['injected'], 1);
      await tester.pump();
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.sourcePayload, raw);
      expect(
        provider.unifiedEvents.single.magnitude,
        raw['earthquake']['hypocenter']['magnitude'],
      );
      expect(provider.unifiedEvents.single.source, 'jmaEqlist');
      if (_verifyDefaultExpiry) {
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(provider.unifiedEvents, isEmpty);
        File('${out.path}/default-expiry-evidence.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'originalId': raw['id'],
            'http': responseBody,
            'sourcePayloadUnchanged': true,
            'activeAfterTwoSeconds': provider.unifiedEvents.length,
            'trace': trace,
          }),
          encoding: utf8,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => LocalInjectServer.stop());
        client.close(force: true);
        provider.dispose();
        map.dispose();
        mock.dispose();
        debugDefaultTargetPlatformOverride = null;
        debugPrint(
          'DEFAULT_EXPIRY_REPRODUCED: HTTP injected=1 but old report disappears within 2 seconds',
        );
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1400)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      final context = tester.element(find.byType(QuakeMapView));
      final viewport = cencIrViewportPadding(
        context,
      )!.deflateRect(Offset.zero & tester.view.physicalSize);
      final epi = LatLng(
        (raw['earthquake']['hypocenter']['latitude'] as num).toDouble(),
        (raw['earthquake']['hypocenter']['longitude'] as num).toDouble(),
      );
      final pixel = controller.camera.latLngToScreenOffset(epi);
      expect((pixel - viewport.center).distance, lessThan(1));
      // An acknowledged old message must survive well past the prior missed capture.
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(provider.unifiedEvents, hasLength(1));
      expect(
        (controller.camera.latLngToScreenOffset(epi) - viewport.center)
            .distance,
        lessThan(1),
      );
      expect(NativeCameraFocus.calls, greaterThan(beforeCalls));
      expect(NativeCameraFocus.outputs, 0);
      final boundary =
          imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${out.path}/jma-centered.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
        File('${out.path}/evidence.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'mode':
                'headless Flutter engine; production HTTP, Mock source, native provider, map and Release Rust DLL',
            'originalId': raw['id'],
            'http': responseBody,
            'activeAfter20Seconds': provider.unifiedEvents
                .map((e) => e.eventId)
                .toList(),
            'epicenterPixel': [pixel.dx, pixel.dy],
            'viewportCenter': [viewport.center.dx, viewport.center.dy],
            'errorPixels': (pixel - viewport.center).distance,
            'cameraNativeCalls': NativeCameraFocus.calls - beforeCalls,
            'outstandingOutputs': NativeCameraFocus.outputs,
            'sourcePayloadUnchanged': true,
            'trace': trace,
          }),
          encoding: utf8,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => LocalInjectServer.stop());
      client.close(force: true);
      provider.dispose();
      map.dispose();
      mock.dispose();
      debugDefaultTargetPlatformOverride = null;
      debugPrint(
        'HEADLESS_HTTP_VERIFIED id=${raw['id']} errorPx=${(pixel - viewport.center).distance} nativeCalls=${NativeCameraFocus.calls - beforeCalls} outputs=${NativeCameraFocus.outputs}',
      );
    },
    skip: !NativeCameraFocus.supported,
  );
}
