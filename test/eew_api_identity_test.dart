import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/eew_event_identity.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final records =
    (jsonDecode(
              File(
                'test/fixtures/eew_identity_20261013/reports.original.json',
              ).readAsStringSync(encoding: utf8),
            )
            as List)
        .cast<Map<String, dynamic>>();

UnifiedQuakeData adapt(Map<String, dynamic> record) {
  final raw = Map<String, dynamic>.from(record['raw'] as Map);
  final source = record['source'] as String;
  return switch (record['api']) {
    'jian' => QuakeEventAdapter.convertJian(source, raw)!,
    'fan' => FanService.decodeEventPayload(raw, sourceHint: source)!,
    'jian-icl' => QuakeEventAdapter.convertJianIcl({
      'type': 'icl',
      'Data': raw,
    })!,
    'chinaeew-icl' => QuakeEventAdapter.convertChinaEewIcl(
      raw,
      isSnapshot: true,
    )!,
    'wolfx' || 'wolfx-http' || 'wolfx-root' => QuakeEventAdapter.convert(
      switch (source) {
        'jma_eew' => 'jmaEew',
        'cwa_eew' => 'cwaEew',
        'cenc_eew' => 'ceaEew',
        'sc_eew' => 'scEew',
        'fj_eew' => 'fjEew',
        'cq_eew' => 'cqEew',
        _ => source,
      },
      raw,
      0,
    )!,
    _ => QuakeEventAdapter.convertWhews(source, raw)!,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TtsService().enabled = false;
  });

  test('44 captured originals adapt without changing raw IDs or payloads', () {
    final before = jsonEncode(records);
    for (final record in records) {
      final event = adapt(record);
      expect(event.isEew, isTrue);
      expect(event.eventId, isNotEmpty);
      expect(event.sourcePayload, record['raw']);
      expect(
        UnifiedQuakeData.fromMap(event.toMap()).sourcePayload,
        record['raw'],
      );
    }
    expect(records, hasLength(44));
    expect(jsonEncode(records), before);
  });

  for (final source in ['jmaEew', 'kmaEew', 'cwaEew', 'sa', 'iclEew']) {
    test('$source comparison identity agrees across captured API snapshots', () {
      final events = records
          .map(adapt)
          .where((e) => e.source == source)
          .toList();
      // HTTP ICL provides a list; compare its newest event with the ICL socket.
      final matching = source == 'iclEew'
          ? events.where((e) => e.eventId == events.first.eventId)
          : events;
      expect(matching.length, greaterThanOrEqualTo(2));
      expect(matching.map(canonicalEewEventId).toSet(), hasLength(1));
    });
  }

  test(
    'regional Wolfx report suffixes are excluded from adapted event IDs',
    () {
      for (final source in ['sc_eew', 'fj_eew']) {
        final record = records.firstWhere((r) => r['source'] == source);
        final originalId = record['raw']['EventID'] as String;
        expect(originalId, matches(RegExp(r'_\d+$')));
        expect(
          adapt(record).eventId,
          originalId.replaceFirst(RegExp(r'_\d+$'), ''),
        );
        expect(record['raw']['EventID'], originalId);
      }
    },
  );

  for (final reverse in [false, true]) {
    test(
      'actual CEA/CEA-pr aliases retain one UI/voice and background key; reverse=$reverse',
      () {
        final originals = records
            .where(
              (r) =>
                  (r['api'] == 'jian' || r['api'] == 'fan') &&
                  (r['source'] == 'cea' || r['source'] == 'cea-pr'),
            )
            .map(adapt)
            .toList();
        final reports = reverse ? originals.reversed.toList() : originals;
        final before = jsonEncode(originals.map((e) => e.toMap()).toList());
        fakeAsync((async) {
          final provider = QuakeProvider(startCatalogServices: false);
          final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
          final delivered = <UnifiedQuakeData>[];
          final states = <BackgroundEventResultType>[];
          var announced = 0;
          provider.onUnifiedEventNotified = (_, _) => announced++;
          final controller =
              HistoryReplayController(
                  onReport: (event) {
                    delivered.add(event);
                    provider.handleUnifiedEventForTest(event);
                    states.add(background.process(event).type);
                  },
                  onClear: (_) {},
                )
                ..load(
                  HistoryReplayPackage.fromGroup(
                    EewEventGroup(
                      eventId: reports.first.eventId,
                      reports: reports,
                      firstArrivedAt: reports.first.originTime!,
                    ),
                  ),
                )
                ..play();
          expect(controller.package!.manualTiming, isTrue);
          for (var i = 1; i < reports.length; i++) {
            controller.next();
          }
          expect(provider.unifiedEvents, hasLength(1));
          expect(provider.eewHistory, hasLength(1));
          expect(
            delivered.map(provider.unifiedEventKeyForTest).toSet(),
            hasLength(1),
          );
          expect(background.acceptedEewReportNums, hasLength(1));
          expect(states.first, BackgroundEventResultType.newEvent);
          expect(
            states.skip(1),
            everyElement(BackgroundEventResultType.dropped),
          );
          expect(announced, 1);
          expect(jsonEncode(originals.map((e) => e.toMap()).toList()), before);
          controller.dispose();
          provider.dispose();
        });
      },
    );
  }

  test(
    'learned aliases survive later coordinate revisions; unrelated agencies stay separate',
    () {
      // Controlled admission-model lifecycle states, not altered observations.
      final origin = DateTime.now().toUtc();
      UnifiedQuakeData state(String id, int report, int api, double lat) =>
          UnifiedQuakeData(
            source: 'ceaEew',
            origin: api,
            eventId: id,
            isEew: true,
            timeZone: 0,
            titleText: 'identity lifecycle contract',
            reportNumText: '第$report報',
            useShindo: false,
            maxIntensity: '4',
            className: 'blue',
            hypocenter: '',
            originTime: origin,
            magnitude: 4.0,
            depth: 10,
            lat: lat,
            lng: 104.65,
            apiTypeLabel: api == 1 ? 'FAN' : 'Jian Project',
          );
      final first = state('agency-contract', 1, 4, 28.50);
      final alias = state('transport-contract', 2, 1, 28.50);
      final revised = state('agency-contract', 3, 4, 28.80);
      final provider = QuakeProvider(startCatalogServices: false);
      final background = BackgroundEventProcessor(sourceInfoMagFilters: {});
      for (final event in [first, alias, revised]) {
        provider.handleUnifiedEventForTest(event, suppressEffects: true);
        background.process(event);
      }
      expect(provider.unifiedEvents.single.reportNumText, '第3報');
      expect(provider.unifiedEvents.single.lat, 28.80);
      expect(background.acceptedEewReportNums.values.single, 3);
      expect(
        provider.unifiedEventKeyForTest(alias),
        provider.unifiedEventKeyForTest(revised),
      );
      expect(background.process(alias).type, BackgroundEventResultType.dropped);
      final registry = EewEventIdentityRegistry()..rememberMatch(first, alias);
      final near = state('nearby-contract', 1, 1, 28.51);
      registry.rememberMatch(first, near);
      expect(registry.resolve(near), 'nearby-contract');
      expect(
        registry.resolve(alias.copyWith(source: 'jmaEew')),
        'transport-contract',
      );
      expect(
        registry.resolve(alias.copyWith(replaySessionId: 'isolated-replay')),
        'transport-contract',
      );
      provider.dispose();
    },
  );

  test('one aggregate can also supply different IDs for CEA and CEA-pr', () {
    final events = records
        .where(
          (r) =>
              r['api'] == 'whews-overseas' &&
              (r['source'] == 'cea' || r['source'] == 'cea-pr'),
        )
        .map(adapt)
        .toList();
    expect(events, hasLength(2));
    expect(events[0].eventId, isNot(events[1].eventId));
    expect(events[0].originTime, events[1].originTime);
    expect(events[0].lat, events[1].lat);
    expect(events[0].lng, events[1].lng);
    final registry = EewEventIdentityRegistry()
      ..rememberMatch(events[0], events[1]);
    expect(registry.resolve(events[0]), registry.resolve(events[1]));
  });

  test('alias storage is bounded and replay aliases are released', () {
    final base = adapt(
      records.firstWhere((r) => r['api'] == 'jian' && r['source'] == 'cea'),
    );
    final registry = EewEventIdentityRegistry();
    // Identifier-cache boundary states; no altered capture is processed.
    for (var i = 0; i < EewEventIdentityRegistry.maxAliases; i++) {
      registry.rememberMatch(
        base.copyWith(eventId: 'cache-agency-$i'),
        base.copyWith(eventId: 'cache-transport-$i'),
      );
    }
    expect(
      registry.resolve(base.copyWith(eventId: 'cache-transport-0')),
      'cache-transport-0',
    );
    final latest = EewEventIdentityRegistry.maxAliases - 1;
    expect(
      registry.resolve(base.copyWith(eventId: 'cache-transport-$latest')),
      'cache-agency-$latest',
    );
    final first = base.copyWith(
      eventId: 'session-a',
      replaySessionId: 'test-session',
    );
    final second = base.copyWith(
      eventId: 'session-b',
      replaySessionId: 'test-session',
    );
    registry.rememberMatch(first, second);
    expect(registry.resolve(second), 'session-a');
    registry.clearReplay('test-session');
    expect(registry.resolve(second), 'session-b');
  });
}
