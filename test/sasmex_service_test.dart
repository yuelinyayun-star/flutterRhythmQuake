import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/widgets/map/wave_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Existing protocol unit input, not an observed upstream alert. Never inject
// this into the live app or change its timestamp to make it appear current.
const _relayUnitInput = <String, dynamic>{
  'id': 'web-1',
  'eventId': 'web-1',
  'epochMs': 1791381600000,
  'region': 'Santa María Huazolotitlán, Oax.',
  'lat': 16.29569,
  'lng': -97.90988,
  'intensidad': 'Moderado',
  'grado': 2,
  'severidad': 3,
  'severity': 'Moderate',
  'isWarn': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses our relay update using the webpage severity semantics', () {
    final event = SasmexService.parseRelayEvent(_relayUnitInput);

    expect(event, isNotNull);
    expect(event!.source, QuakeSourceType.sasmex);
    expect(event.eventId, 'web-1');
    expect(event.location, 'Santa María Huazolotitlán, Oax.');
    expect(event.latitude, 16.29569);
    expect(event.longitude, -97.90988);
    expect(event.isInfoEvent, isFalse);
    expect(event.isWarn, isFalse);
    expect(event.infoTypeName, 'SASMEX 地震检出');
    expect(event.apiTypeLabel, 'Rhythm');
  });

  test('Severe enters unified EEW without a location or range verdict', () {
    final event = SasmexService.parseRelayFrame({
      'type': 'update',
      'Data': {
        'id': 'web-severe',
        'epochMs': 1791381600000,
        'severity': 'Severe',
        'isWarn': true,
      },
    });

    expect(event, isNotNull);
    expect(event!.titleText, 'SASMEX 地震警报');
    expect(event.isWarn, isTrue);
    expect(event.isEew, isTrue);
    expect(event.lat, isNull);
    expect(event.lng, isNull);
    expect(event.magnitude, -1);
    expect(event.depth, -1);
    expect(event.maxIntensity, '-');
    expect(UnifiedEventPresentation.fromEvent(event).intensityValue, '严重');
  });

  test('global title rule does not require a station range verdict', () {
    expect(SasmexService.displayTitle(severity: 'Severe'), 'SASMEX 地震警报');
    expect(SasmexService.displayTitle(severity: 'Minor'), 'SASMEX 地震检出');
  });

  test('converted original October 6 document uses the unified severity UI', () {
    final original = jsonDecode(File(
      'test/fixtures/sasmex_firestore_20261006.original.json',
    ).readAsStringSync(encoding: utf8));
    final frame = jsonDecode(File(
      'test/fixtures/sasmex_firestore_20261006.relay.json',
    ).readAsStringSync(encoding: utf8)) as Map<String, dynamic>;
    final event = SasmexService.parseRelayFrame(frame)!;
    final presentation = UnifiedEventPresentation.fromEvent(event);
    expect(event.originTime, DateTime.utc(2026, 10, 6, 4, 9, 46));
    expect(event.lat, original['epicenter']['latitude']);
    expect(event.lng, original['epicenter']['longitude']);
    expect(event.isWarn, false);
    expect(event.sourcePayload!['original'], original);
    expect(event.sourcePayload!['severity'], 'Minor');
    expect(event.sourcePayload!['severityOrigin'], 'intensity');
    expect(presentation.intensityValue, '轻微');
    expect(presentation.secondaryText, '类型：未知 · 严重性：Minor');
    expect(presentation.detailText, contains('上游强度文字：Leve'));
    expect(presentation.title, 'SASMEX 地震检出 第1報');
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    provider.handleUnifiedEventForTest(event, suppressEffects: true);
    expect(provider.unifiedEvents, isEmpty);
  });

  test(
    'SASMEX card uses raw type and severity with a Chinese severity badge',
    () {
      final event = _originalProtocolPresentationEvent();
      final presentation = UnifiedEventPresentation.fromEvent(event);
      expect(presentation.title, 'SASMEX 地震检出 第1報');
      expect(event.reportNumText, '第1報');
      expect(presentation.primaryText, '地点未知');
      expect(presentation.secondaryText, '类型：Alert · 严重性：Moderate');
      expect(presentation.compactSecondaryText, presentation.secondaryText);
      expect(presentation.intensityLabel, '严重性');
      expect(presentation.intensityValue, '中等');
      expect(presentation.timeText, startsWith('发布 '));
      expect(presentation.detailText, contains('上游标题：Sismo'));
      expect(presentation.detailText, contains('原始描述：Descripción original'));
      expect(presentation.detailText, contains('更新时间原文：2026-10-07T14:00:00Z'));
      expect(presentation.notificationBody, contains('严重性 中等'));
      expect(presentation.notificationBody, isNot(contains('規模 調査中')));
      expect(presentation.notificationBody, isNot(contains('烈度')));
      expect(event.magnitude, -1);
      expect(event.maxIntensity, '-');
      expect(event.sourcePayload!['description'], 'Descripción original');
    },
  );

  for (final size in [const Size(900, 500), const Size(390, 844)]) {
    testWidgets('SASMEX unified card and severity badge fit at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final event = _originalProtocolPresentationEvent();
      final provider = _StaticCardProvider(event);
      final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<QuakeProvider>.value(value: provider),
              ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
            ],
            child: const MaterialApp(home: Scaffold(body: AlertModule())),
          ),
        );
        await tester.pump();
        expect(find.text('SASMEX 地震检出 第1報'), findsOneWidget);
        expect(find.text('类型：Alert · 严重性：Moderate'), findsOneWidget);
        expect(find.text('中等'), findsOneWidget);
        expect(find.text('严重性'), findsOneWidget);
        expect(find.text('Rhythm'), findsOneWidget);
        final timeText = UnifiedEventPresentation.fromEvent(event).timeText;
        expect(find.text(timeText), findsOneWidget);
        expect(
          tester.getRect(find.text('Rhythm')).top,
          greaterThan(tester.getRect(find.text(timeText)).bottom),
        );
        expect(find.textContaining('規模 調査中'), findsNothing);
        expect(find.text('烈度'), findsNothing);
        expect(tester.takeException(), isNull);
        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip).first);
        expect(tooltip.message, contains('原始严重性：Moderate'));
        expect(tooltip.message, contains('消息类型：Alert'));
        await tester.longPress(find.text('类型：Alert · 严重性：Moderate'));
        await tester.pumpAndSettle();
        expect(find.text(tooltip.message!), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        mapState.dispose();
        await tester.pump();
      }
    });
  }

  test('does not invent an event time', () {
    expect(SasmexService.parseRelayEvent({'id': 'without-time'}), isNull);
  });

  test(
    'relay frames preserve coordinates and payload through map conversion',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      for (final type in ['update', 'snapshot', 'query_response']) {
        final unified = SasmexService.parseRelayFrame({
          'type': type,
          'Data': _relayUnitInput,
        })!;
        expect(unified.isEew, isTrue);
        expect(unified.hasReportSequence, isFalse);
        expect(unified.reportNumText, '第1報');
        expect(unified.isSnapshot, type != 'update');
        expect(unified.useSourceTimeForExpiry, isTrue);
        expect(unified.sourcePayload, _relayUnitInput);
        expect(unified.hypocenter, contains('墨西哥'));
        expect(unified.hypocenter, matches(RegExp(r'[\u4e00-\u9fff]')));
        expect(unified.sourcePayload!['region'], _relayUnitInput['region']);
        final display = UnifiedEventPresentation.fromEvent(unified);
        expect(display.secondaryText, '类型：未知 · 严重性：Moderate');
        expect(display.primaryText, unified.hypocenter);
        expect(
          display.detailText,
          contains('原始地点：${_relayUnitInput['region']}'),
        );
        expect(display.detailText, contains('上游强度文字：Moderado'));
        expect(display.detailText, contains('grado 原值：2'));
        expect(display.detailText, contains('severidad 原值：3'));
        expect(
          unified.originTime!.millisecondsSinceEpoch,
          _relayUnitInput['epochMs'],
        );
        final handoff = UnifiedQuakeData.fromMap(unified.toMap());
        final mapEvent = provider.unifiedToQuakeMessageForTest(handoff);
        expect(mapEvent.source, QuakeSourceType.sasmex);
        expect(mapEvent.isInfoEvent, isFalse);
        expect(mapEvent.latitude, _relayUnitInput['lat']);
        expect(mapEvent.longitude, _relayUnitInput['lng']);
        expect(mapEvent.apiTypeLabel, 'Rhythm');
        expect(mapEvent.maxIntensity, isNull);
      }
    },
  );

  test(
    'our WSS receiver emits the unified stream rather than the legacy stream',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSubscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(jsonEncode({'type': 'update', 'Data': _relayUnitInput}));
      });
      final service = SasmexService(
        url: 'ws://127.0.0.1:${server.port}/sasmex-eew',
      );
      final legacy = <QuakeMessage>[];
      final legacySubscription = service.onEvent.listen(legacy.add);
      final received = service.onUnifiedEvent.first.timeout(
        const Duration(seconds: 5),
      );
      try {
        service.connect();
        final event = await received;
        expect(event.source, 'sasmex');
        expect(event.isEew, isTrue);
        expect(event.hasReportSequence, isTrue);
        expect(event.reportNumText, '第1報');
        expect(event.lat, _relayUnitInput['lat']);
        expect(event.lng, _relayUnitInput['lng']);
        expect(event.sourcePayload, _relayUnitInput);
        expect(legacy, isEmpty);
      } finally {
        service.dispose();
        await legacySubscription.cancel();
        await serverSubscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'original public snapshot with empty realtime cache produces no event',
    () {
      final original =
          jsonDecode(
                File(
                  'server/kma_pews_relay/test_fixtures/sasmex_snapshot_original.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      expect(original['sasmexCap']['Data'], isNotNull);
      for (final type in ['snapshot', 'query_response']) {
        expect(
          SasmexService.parseRelayFrame({
            'type': type,
            'Data': original['sasnoRealtime']['Data'],
          }),
          isNull,
        );
      }
    },
  );

  testWidgets(
    'expired SASMEX protocol input has no active website wave extent',
    (tester) async {
      final quakeProvider = QuakeProvider();
      final mapProvider = MapStateProvider();
      final controller = MapController();
      final event = quakeProvider.unifiedToQuakeMessageForTest(
        SasmexService.parseRelayFrame({
          'type': 'update',
          'Data': _relayUnitInput,
        })!,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: LatLng(event.latitude, event.longitude),
                initialZoom: 6,
              ),
              children: const [],
            ),
          ),
        );
        mapProvider.setController(controller, const TestVSync());
        final zoom = mapProvider.smartMoveToEvents(
          [event],
          waveEvents: [event],
          minZoom: 4.5,
          maxZoom: 8,
          force: true,
        );
        expect(zoom, 8);
        await tester.pumpAndSettle();
        expect(
          controller.camera.center.latitude,
          closeTo(event.latitude, 0.00001),
        );
        expect(
          controller.camera.center.longitude,
          closeTo(event.longitude, 0.00001),
        );
      } finally {
        mapProvider.dispose();
        quakeProvider.dispose();
      }
    },
  );

  test('old protocol input is never renewed into a current EEW', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = SasmexService.parseRelayFrame({
      'type': 'snapshot',
      'Data': _relayUnitInput,
    })!;
    provider.handleUnifiedEventForTest(event, suppressEffects: true);
    expect(provider.unifiedEvents, isEmpty);
    expect(provider.unifiedMapEvents, isEmpty);
    final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
    expect(background.process(event).type, BackgroundEventResultType.dropped);
    expect(
      event.originTime!.millisecondsSinceEpoch,
      _relayUnitInput['epochMs'],
    );
  });

  test(
    'our existing painter draws the epicenter cross without wave estimates',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final event = SasmexService.parseRelayFrame({
        'type': 'update',
        'Data': _relayUnitInput,
      })!;
      final mapEvent = provider.unifiedToQuakeMessageForTest(event);
      final camera = MapCamera(
        crs: const Epsg3857(),
        center: LatLng(mapEvent.latitude, mapEvent.longitude),
        zoom: 6,
        rotation: 0,
        nonRotatedSize: const Size(400, 400),
      );
      WavePainter painter({bool blinkOn = true}) => WavePainter(
        event: mapEvent,
        camera: camera,
        showWaves: false,
        showEpicenterLabel: false,
        blinkOn: blinkOn,
      );
      expect(
        (Canvas canvas) => painter().paint(canvas, const Size(400, 400)),
        paints
          ..line(p1: const Offset(186, 186), p2: const Offset(214, 214))
          ..line(p1: const Offset(214, 186), p2: const Offset(186, 214))
          ..line(color: Colors.red, strokeWidth: 2.5)
          ..line(color: Colors.red, strokeWidth: 2.5),
      );
      expect(
        (Canvas canvas) => painter().paint(canvas, const Size(400, 400)),
        isNot(paints..circle()),
      );
      expect(
        (Canvas canvas) =>
            painter(blinkOn: false).paint(canvas, const Size(400, 400)),
        paintsNothing,
      );
      expect(
        painter().shouldRepaint(
          WavePainter(
            event: provider.unifiedToQuakeMessageForTest(event),
            camera: camera,
            showWaves: false,
            showEpicenterLabel: false,
          ),
        ),
        isTrue,
      );
    },
  );
}

UnifiedQuakeData _originalProtocolPresentationEvent() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/sasmex_protocol_unit.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map<String, dynamic>;
  return SasmexService.parseRelayFrame({
    'type': 'snapshot',
    'Data': fixture['relayEvent'],
  })!;
}

// Display-only protocol test: the original old timestamp remains untouched.
// No active source connection or alert admission is used to make the card visible.
class _StaticCardProvider extends QuakeProvider {
  _StaticCardProvider(this.event);
  final UnifiedQuakeData event;
  @override
  List<UnifiedQuakeData> get unifiedEvents => [event];
}
