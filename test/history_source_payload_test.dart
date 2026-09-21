import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/global_quake_service_io.dart';
import 'package:flutterrhythmquake/services/sources/p2pquake_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic fixture(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'WHEWS captures original bodies before aliases for every fixture source',
    () {
      final frames = fixture('catalog_20260917/whews_all.json') as List;
      var converted = 0;
      for (final frame in frames) {
        final raw = Map<String, dynamic>.from(frame['Data'] as Map);
        final before = jsonEncode(raw);
        final event = QuakeEventAdapter.convertWhews(
          frame['source'] as String,
          raw,
        );
        if (event == null) continue;
        converted++;
        expect(
          jsonEncode(event.sourcePayload),
          before,
          reason: frame['source'],
        );
        expect(jsonEncode(raw), before);
        final handedOff = UnifiedQuakeData.fromMap(
          jsonDecode(jsonEncode(event.toMap())),
        );
        expect(handedOff.sourcePayload, raw);
      }
      expect(converted, greaterThan(30));
    },
  );

  test('Jian keeps original event bodies including nested fields', () {
    final frames = fixture('jian/all.json') as Map;
    var converted = 0;
    for (final entry in frames.entries) {
      if (entry.value is! Map || entry.value['Data'] is! Map) continue;
      final type = entry.key.toString().split('：').last;
      final raw = Map<String, dynamic>.from(entry.value['Data'] as Map);
      final before = jsonEncode(raw);
      final event = QuakeEventAdapter.convertJian(type, raw);
      if (event == null) continue;
      converted++;
      expect(jsonEncode(event.sourcePayload), before);
      expect(jsonEncode(raw), before);
    }
    expect(converted, greaterThan(30));
  });

  test('stored payload is deeply independent and immutable after handoff', () {
    final frames = fixture('catalog_20260917/whews_all.json') as List;
    final raw = Map<String, dynamic>.from(
      frames.firstWhere((f) => f['source'] == 'jma')['Data'],
    );
    final before = jsonEncode(raw);
    final event = QuakeEventAdapter.convertWhews('jma', raw)!;
    (raw['comments'] as Map).clear();
    (raw['intensities'] as List).clear();
    expect(jsonEncode(event.sourcePayload), before);
    final restored = UnifiedQuakeData.fromMap(
      jsonDecode(jsonEncode(event.toMap())),
    );
    expect(
      () => (restored.sourcePayload!['comments'] as Map).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (restored.sourcePayload!['intensities'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(jsonEncode(restored.sourcePayload), before);
  });

  test('FAN normalization retains the complete input event body', () async {
    // Replay an unmodified captured event using the shared FAN event schema.
    final frames = fixture('catalog_20260917/whews_all.json') as List;
    final frame = frames.firstWhere((f) => f['source'] == 'jma_eew');
    final raw = frame['Data'];
    final service = FanService();
    final events = <UnifiedQuakeData>[];
    final subscription = service.onUnifiedEvent.listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      service.dispose();
    });
    service.handleMessageForTesting(jsonEncode({'type': 'update', ...frame}));
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.sourcePayload, raw);
    expect(events.single.sourcePayload!.containsKey('isSea'), isTrue);
    expect(events.single.sourcePayload!.containsKey('eventId'), isFalse);
  });

  test(
    'P2P merged display still carries only the current original report',
    () async {
      final frames = (fixture('jma_voice/p2p_history_20260921.json') as List)
          .where((f) => f['earthquake']['time'] == '2026/09/21 22:38:00')
          .toList();
      final service = P2PQuakeService();
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        service.dispose();
      });
      // Detail first, then the earlier source reports: exercise the merge path
      // without modifying any captured report values.
      for (final frame in frames) {
        service.handleMessageForTesting(jsonEncode(frame));
      }
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(3));
      for (var i = 0; i < frames.length; i++) {
        expect(events[i].sourcePayload, frames[i]);
      }
      expect(events.last.hypocenter, isNotEmpty);
      expect(events.last.sourcePayload!['issue']['type'], 'ScalePrompt');
    },
  );

  test('report groups and copyWith retain each corresponding body', () {
    final frames = fixture('catalog_20260917/whews_all.json') as List;
    final reports = <UnifiedQuakeData>[
      for (final frame in frames)
        if (frame['source'] == 'jma_eew' || frame['source'] == 'cwa_eew')
          QuakeEventAdapter.convertWhews(
            frame['source'],
            Map<String, dynamic>.from(frame['Data']),
          )!,
    ];
    for (final report in reports) {
      final group = EewEventGroup(
        eventId: report.eventId,
        reports: [report],
        firstArrivedAt: report.originTime!,
      );
      final restored = EewEventGroup.fromMap(
        jsonDecode(jsonEncode(group.toMap())),
      );
      expect(restored.latest.sourcePayload, report.sourcePayload);
      expect(
        report.copyWith(isSnapshot: true).sourcePayload,
        report.sourcePayload,
      );
      final replaced = group.addReport(report);
      expect(replaced.reportCount, group.reportCount);
      expect(replaced.latest.sourcePayload, report.sourcePayload);
    }
  });

  test('legacy history without original payload remains readable', () {
    final frame = (fixture('catalog_20260917/whews_all.json') as List).first;
    final event = QuakeEventAdapter.convertWhews(
      frame['source'],
      Map<String, dynamic>.from(frame['Data']),
    )!;
    final map = event.toMap()..remove('sourcePayload');
    final restored = UnifiedQuakeData.fromMap(map);
    expect(restored.eventId, event.eventId);
    expect(restored.sourcePayload, isNull);
    expect(restored.toMap()['sourcePayload'], isNull);
  });

  test(
    'provider restores and persists original payloads without live replay',
    () async {
      final frame = (fixture('catalog_20260917/whews_all.json') as List).first;
      final event = QuakeEventAdapter.convertWhews(
        frame['source'],
        Map<String, dynamic>.from(frame['Data']),
      )!;
      final group = EewEventGroup(
        eventId: event.eventId,
        reports: [event],
        firstArrivedAt: event.originTime!,
      );
      SharedPreferences.setMockInitialValues({
        'unified_eew_history': jsonEncode([group.toMap()]),
      });
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.eewHistory.single.latest.sourcePayload, frame['Data']);
      expect(provider.unifiedEvents, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('unified_eew_history');
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final saved = jsonDecode(prefs.getString('unified_eew_history')!) as List;
      expect(saved.single['reports'].single['sourcePayload'], frame['Data']);
    },
  );

  test('real GQ stream snapshots preserve Java classes and custom blocks', () {
    final bytes = File(
      'test/fixtures/global_quake/stream_20260921.bin',
    ).readAsBytesSync();
    final payloads = GlobalQuakeService().decodePayloadsForTesting(bytes);
    expect(payloads, isNotEmpty);
    final encoded = jsonEncode(payloads);
    expect(jsonDecode(encoded), payloads);
    expect(encoded, contains('java.util.CollSer'));
    expect(encoded, contains('customData'));
    expect(encoded, contains('blockDataBase64'));
    expect(
      payloads.every((p) => p['format'] == 'java-object-stream-decoded-v1'),
      isTrue,
    );
  });
}
