import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/sources/sasmex_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';

// Explicit protocol/lifecycle unit scenarios, not captured upstream messages.
// These are never sent to the running app or production relay. Existing raw
// October 6 captures and their source timestamps remain untouched.
Map<String, dynamic> _body(String id) {
  final now = DateTime.now().toUtc();
  return {
    'eventId': id,
    'epochMs': now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
    'sent': now.subtract(const Duration(seconds: 10)).toIso8601String(),
    'updated': now.subtract(const Duration(seconds: 3)).toIso8601String(),
    'lat': 16.2,
    'lng': -97.9,
    'region': 'Oaxaca',
    'severity': 'Moderate',
    'msgType': 'Alert',
    'description': 'Unit description',
    'circle': '16.2,-97.9 10',
  };
}

Map<String, dynamic> _frame(
  Map<String, dynamic> body, [
  String type = 'update',
]) => {'type': type, 'Data': body};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'detection, hypocenter revision and warning share increasing reports',
    () async {
      final service = SasmexService();
      addTearDown(service.dispose);
      final original = _body('unit-revisions');
      final originalText = jsonEncode(original);
      final first = (await service.acceptRelayFrameForTest(_frame(original)))!;
      final moved = {...original, 'lat': 16.3, 'lng': -97.8};
      final second = (await service.acceptRelayFrameForTest(_frame(moved)))!;
      final warning = {...moved, 'severity': 'Severe'};
      final third = (await service.acceptRelayFrameForTest(_frame(warning)))!;
      expect(
        [first.reportNumText, second.reportNumText, third.reportNumText],
        ['第1報', '第2報', '第3報'],
      );
      expect(second.lat, 16.3);
      expect(second.lng, -97.8);
      expect(second.isWarn, false);
      expect(third.isWarn, true);
      expect(
        UnifiedEventPresentation.fromEvent(third).title,
        'SASMEX 地震警报 第3報',
      );
      expect(
        [first, second, third].every((event) => event.hasReportSequence),
        true,
      );
      expect(first.sourcePayload, original);
      expect(second.sourcePayload, moved);
      expect(third.sourcePayload, warning);
      expect(jsonEncode(original), originalText);
      expect(original.containsKey('reportNumText'), false);
    },
  );

  for (final field in [
    'lat',
    'lng',
    'epochMs',
    'sent',
    'region',
    'circle',
    'msgType',
    'severity',
    'description',
    'intensidad',
    'grado',
    'severidad',
    'event',
  ]) {
    test(
      '$field revision advances the same event without a warning upgrade',
      () async {
        final service = SasmexService();
        addTearDown(service.dispose);
        final first = _body('unit-field-$field');
        final dynamic changed = switch (field) {
          'lat' => 16.31,
          'lng' => -97.81,
          'epochMs' => (first[field] as int) + 100,
          'sent' => DateTime.parse(
            first[field] as String,
          ).add(const Duration(milliseconds: 100)).toIso8601String(),
          'severity' => 'Minor',
          'grado' || 'severidad' => 2,
          _ => 'Unit revised $field',
        };
        await service.acceptRelayFrameForTest(_frame(first));
        final next = (await service.acceptRelayFrameForTest(
          _frame({...first, field: changed}),
        ))!;
        expect(next.reportNumText, '第2報');
        expect(next.isWarn, false);
        expect(next.sourcePayload![field], changed);
      },
    );
  }

  test(
    'duplicates, object order, timestamp-only frames and snapshots keep the report',
    () async {
      final service = SasmexService();
      addTearDown(service.dispose);
      final first = _body('unit-duplicates');
      await service.acceptRelayFrameForTest(_frame(first, 'snapshot'));
      final changed = {...first, 'lat': 16.3};
      await service.acceptRelayFrameForTest(_frame(changed));
      final repeated = Map<String, dynamic>.fromEntries(
        changed.entries.toList().reversed,
      );
      for (final type in ['update', 'snapshot', 'query_response']) {
        final event = (await service.acceptRelayFrameForTest(
          _frame(repeated, type),
        ))!;
        expect(event.reportNumText, '第2報');
        expect(event.isSnapshot, type != 'update');
      }
      final timeOnly = {
        ...changed,
        'updated': DateTime.now().toUtc().toIso8601String(),
      };
      expect(
        (await service.acceptRelayFrameForTest(
          _frame(timeOnly),
        ))!.reportNumText,
        '第2報',
      );
      expect(
        await service.acceptRelayFrameForTest({'type': 'heartbeat'}),
        null,
      );
      expect(
        await service.acceptRelayFrameForTest(
          _frame({...changed, 'isReplay': true}),
        ),
        null,
      );
      expect(
        await service.acceptRelayFrameForTest(
          _frame({...changed, 'isSimulation': true}),
        ),
        null,
      );
      expect(
        (await service.acceptRelayFrameForTest(
          _frame(_body('unit-new-event')),
        ))!.reportNumText,
        '第1報',
      );
    },
  );

  test(
    'earlier source timestamp and previously seen bodies cannot displace the latest report',
    () async {
      final service = SasmexService();
      addTearDown(service.dispose);
      final first = _body('unit-old-report');
      final latest = {...first, 'lat': 16.4, 'severity': 'Severe'};
      await service.acceptRelayFrameForTest(_frame(first));
      await service.acceptRelayFrameForTest(_frame(latest));
      expect(await service.acceptRelayFrameForTest(_frame(first)), null);
      expect(
        await service.acceptRelayFrameForTest(_frame(first, 'snapshot')),
        null,
      );
      final delayed = {
        ...latest,
        'lat': 16.5,
        'updated': DateTime.parse(
          first['updated'] as String,
        ).subtract(const Duration(seconds: 1)).toIso8601String(),
      };
      expect(await service.acceptRelayFrameForTest(_frame(delayed)), null);
      expect(
        (await service.acceptRelayFrameForTest(_frame(latest)))!.reportNumText,
        '第2報',
      );
    },
  );

  test(
    'restart preserves numbers and a demonstrably newer reconnect revision advances once',
    () async {
      final firstService = SasmexService();
      final first = _body('unit-restart');
      final changed = {...first, 'lat': 16.4};
      await firstService.acceptRelayFrameForTest(_frame(first));
      await firstService.acceptRelayFrameForTest(_frame(changed));
      await firstService.flushReportsForTest();
      firstService.dispose();
      final restored = SasmexService();
      addTearDown(restored.dispose);
      expect(
        (await restored.acceptRelayFrameForTest(
          _frame(changed, 'snapshot'),
        ))!.reportNumText,
        '第2報',
      );
      expect(await restored.acceptRelayFrameForTest(_frame(first)), null);
      final newBody = {...changed, 'lng': -97.7};
      // Different cache contents alone are not evidence of a newer report.
      expect(
        await restored.acceptRelayFrameForTest(
          _frame(newBody, 'query_response'),
        ),
        null,
      );
      newBody['updated'] = DateTime.now().toUtc().toIso8601String();
      expect(
        (await restored.acceptRelayFrameForTest(
          _frame(newBody, 'snapshot'),
        ))!.reportNumText,
        '第3報',
      );
      expect(
        (await restored.acceptRelayFrameForTest(
          _frame(newBody),
        ))!.reportNumText,
        '第3報',
      );
      // A genuine later correction can restore an earlier value.
      final correction = {
        ...first,
        'updated': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 1))
            .toIso8601String(),
      };
      expect(
        (await restored.acceptRelayFrameForTest(
          _frame(correction),
        ))!.reportNumText,
        '第4報',
      );
    },
  );

  test(
    'foreground UI, map and background admission reject old numbered reports',
    () async {
      final service = SasmexService();
      final provider = QuakeProvider();
      addTearDown(service.dispose);
      addTearDown(provider.dispose);
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      final firstBody = _body('unit-admission');
      final first = (await service.acceptRelayFrameForTest(_frame(firstBody)))!;
      final revised = (await service.acceptRelayFrameForTest(
        _frame({...firstBody, 'lat': 16.35}),
      ))!;
      final warning = (await service.acceptRelayFrameForTest(
        _frame({...firstBody, 'lat': 16.35, 'severity': 'Severe'}),
      ))!;
      for (final event in [first, revised, warning]) {
        provider.handleUnifiedEventForTest(event, suppressEffects: true);
        expect(
          background.process(UnifiedQuakeData.fromMap(event.toMap())).type,
          event == first
              ? BackgroundEventResultType.newEvent
              : BackgroundEventResultType.update,
        );
        expect(provider.unifiedEvents, hasLength(1));
        expect(
          provider.unifiedEvents.single.reportNumText,
          event.reportNumText,
        );
        expect(provider.unifiedMapEvents.single.latitude, event.lat);
      }
      for (final stale in [
        first,
        revised,
        warning,
        warning.copyWith(isSnapshot: true),
      ]) {
        provider.handleUnifiedEventForTest(stale, suppressEffects: true);
        expect(
          background.process(stale).type,
          BackgroundEventResultType.dropped,
        );
      }
      expect(provider.unifiedEvents.single.reportNumText, '第3報');
      expect(provider.unifiedEvents.single.isWarn, true);
      expect(provider.unifiedMapEvents.single.reportNumText, '第3報');
      expect(provider.eewHistory.single.reportCount, 3);
      expect(
        provider.eewHistory.single.reports.map((event) => event.reportNumText),
        ['第3報', '第2報', '第1報'],
      );
      expect(
        AlertVoiceHelper.generateUnifiedEventText(warning, phase: 'warn'),
        contains('第3报'),
      );
      expect(background.acceptedEewReportNums['sasmex|unit-admission'], 3);
      final restartedBackground = BackgroundEventProcessor(
        sourceInfoMagFilters: {},
        acceptedEewReportNums: background.acceptedEewReportNums,
      );
      expect(
        restartedBackground.process(first).type,
        BackgroundEventResultType.dropped,
      );
    },
  );

  test(
    'actual WS receiver numbers parameter changes and upgrades before forwarding to UI',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final connected = Completer<WebSocket>();
      final listener = server.listen((request) async {
        connected.complete(await WebSocketTransformer.upgrade(request));
      });
      final service = SasmexService(
        url: 'ws://127.0.0.1:${server.port}/sasmex-eew',
      );
      final events = StreamController<UnifiedQuakeData>();
      final receiver = service.onUnifiedEvent.listen(events.add);
      final iterator = StreamIterator(events.stream);
      WebSocket? socket;
      try {
        service.connect();
        socket = await connected.future.timeout(const Duration(seconds: 3));
        final first = _body('unit-wire');
        for (final body in [
          first,
          {...first, 'lat': 16.4},
          {...first, 'lat': 16.4, 'severity': 'Severe'},
        ]) {
          socket.add(jsonEncode(_frame(body)));
          expect(
            await iterator.moveNext().timeout(const Duration(seconds: 3)),
            true,
          );
          expect(iterator.current.sourcePayload, body);
          expect(iterator.current.hasReportSequence, true);
        }
        expect(iterator.current.reportNumText, '第3報');
        expect(iterator.current.isWarn, true);
      } finally {
        service.dispose();
        await socket?.close();
        await receiver.cancel();
        await iterator.cancel();
        await events.close();
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'accepted parameter revisions and warning upgrades reach Windows EEW voice with their number',
    () async {
      if (!Platform.isWindows) return;
      final tts = TtsService();
      await tts.init();
      await tts.stop();
      await tts.configure(
        enabled: true,
        eventEnabled: true,
        updateEnabled: true,
        gptSovitsEnabled: false,
        persist: false,
      );
      final spoken = <String>[];
      final speech = StreamController<String>();
      final iterator = StreamIterator(speech.stream);
      tts.windowsSpeechOverrideForTest = (text) async {
        spoken.add(text);
        speech.add(text);
      };
      final service = SasmexService();
      final provider = QuakeProvider();
      try {
        final first = _body('unit-voice');
        final bodies = [
          first,
          {...first, 'lat': 16.4},
          {...first, 'lat': 16.4, 'severity': 'Severe'},
        ];
        for (var index = 0; index < bodies.length; index++) {
          final event = (await service.acceptRelayFrameForTest(
            _frame(bodies[index]),
          ))!;
          provider.handleUnifiedEventForTest(event);
          expect(
            await iterator.moveNext().timeout(const Duration(seconds: 3)),
            true,
          );
          expect(iterator.current, contains('第${index + 1}报'));
          expect(iterator.current, contains(index == 2 ? '地震警报' : '地震检出'));
        }
        final duplicate = (await service.acceptRelayFrameForTest(
          _frame(bodies.last),
        ))!;
        provider.handleUnifiedEventForTest(duplicate);
        expect(await service.acceptRelayFrameForTest(_frame(first)), null);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(spoken, hasLength(3));
        expect(provider.unifiedEvents.single.reportNumText, '第3報');
      } finally {
        provider.dispose();
        service.dispose();
        await tts.stop();
        tts.windowsSpeechOverrideForTest = null;
        await iterator.cancel();
        await speech.close();
      }
    },
  );
}
