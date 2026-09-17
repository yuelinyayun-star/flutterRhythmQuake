import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/core/utils/alert_voice_helper.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/jian_sources.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/jian_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';

// Raw, unmodified capture is tested separately from synthetic lifecycle cases.
Map<String, dynamic> scenario(
  String type, {
  String id = 'scenario-1',
  int number = 1,
}) => {
  'id': id,
  'number': number,
  'serial': number,
  'originTime': DateTime.now().toUtc().millisecondsSinceEpoch,
  'latitude': 35.0,
  'longitude': 140.0,
  'depth': 10.0,
  'magnitude': 5.0,
  'placeName': '测试震中',
  'intensity': '3',
  'infoTypeName': '[正式测定]',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final captured =
      jsonDecode(File('test/fixtures/jian/all.json').readAsStringSync()) as Map;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  for (final type in jianEarthquakeSources.keys) {
    test('raw $type capture: identity, timestamp, raw immutability, voice', () {
      final raw = Map<String, dynamic>.from(
        (captured['source：$type'] as Map)['Data'] as Map,
      );
      final original = jsonEncode(raw);
      final event = QuakeEventAdapter.convertJian(type, raw)!;
      expect(jsonEncode(raw), original);
      expect(event.source, jianEarthquakeSources[type]);
      expect(event.origin, QuakeEventAdapter.jianOrigin);
      expect(event.apiTypeLabel, 'Jian Project');
      expect(event.eventId, raw['id'].toString());
      expect(event.isEew, jianEewTypes.contains(type));
      expect(event.useSourceTimeForExpiry, isTrue);
      final timestamp = raw['originTime'];
      if (timestamp is num) {
        expect(
          QuakeTime.unifiedInstantUtc(event).millisecondsSinceEpoch,
          timestamp,
        );
      }
      expect(event.reportTime == null, raw['reportTime'] == null);
      expect(event.sourcePayload, raw);
      expect(jianSourceType(event.source), isNotNull);
      final voice = AlertVoiceHelper.generateUnifiedEventText(
        event,
        phase: 'first',
      );
      expect(voice, isNot(contains('whews_')));
      expect(UnifiedQuakeData.fromMap(event.toMap()).toMap(), event.toMap());
    });
  }

  for (final type in jianEarthquakeSources.keys.where(
    (type) => !jianEewTypes.contains(type),
  )) {
    test(
      '$type uses the same foreground/background filter, expiry and replay path',
      () async {
        final provider = QuakeProvider();
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          provider.dispose();
        });
        final event = QuakeEventAdapter.convertJian(type, scenario(type))!;
        final sourceType = jianSourceType(event.source)!;
        var actions = 0;
        provider.onUnifiedEventNotified = (_, _) => actions++;
        final history = event.copyWith(isHistory: true);
        provider.handleUnifiedEventForTest(history);
        expect(provider.unifiedEvents, isEmpty);
        expect(actions, 0);
        var processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
        expect(
          processor.process(history).type,
          BackgroundEventResultType.history,
        );
        expect(processor.seenUnifiedInfoEvents, isEmpty);
        final stale = event.copyWith(
          originTime: event.originTime!.subtract(const Duration(days: 2)),
        );
        provider.handleUnifiedEventForTest(stale);
        expect(provider.unifiedEvents, isEmpty);
        expect(
          processor.process(stale).type,
          BackgroundEventResultType.dropped,
        );
        provider.setSourceInfoMagFilter(sourceType, -1);
        processor = BackgroundEventProcessor(
          sourceInfoMagFilters: {'source_mag_filter_${sourceType.name}': -1},
        );
        provider.handleUnifiedEventForTest(event);
        provider.handleUnifiedEventForTest(history);
        expect(provider.unifiedEvents, isEmpty);
        expect(
          processor.process(event).type,
          BackgroundEventResultType.dropped,
        );
        expect(
          processor.process(history).type,
          BackgroundEventResultType.dropped,
        );
        provider.setSourceInfoMagFilter(sourceType, 6);
        provider.handleUnifiedEventForTest(event);
        expect(provider.unifiedEvents, isEmpty);
        provider.setSourceInfoMagFilter(sourceType, 0);
        processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
        provider.handleUnifiedEventForTest(event);
        expect(provider.unifiedEvents, hasLength(1));
        expect(actions, 1);
        expect(
          processor.process(event).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(event);
        expect(actions, 1);
        expect(
          processor.process(event).type,
          BackgroundEventResultType.dropped,
        );
        expect(provider.unifiedSourceTypeForTest(event), sourceType);
      },
    );
  }

  for (final type in jianEewTypes) {
    test(
      '$type EEW uses existing source report sequence and rejects stale reports',
      () async {
        final provider = QuakeProvider();
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          provider.dispose();
        });
        final processor = BackgroundEventProcessor(sourceInfoMagFilters: {});
        final event = QuakeEventAdapter.convertJian(
          type,
          scenario(type, number: 2),
        )!;
        final otherApi = event.copyWith(origin: 1, apiTypeLabel: 'FAN');
        provider.handleUnifiedEventForTest(otherApi);
        expect(
          processor.process(otherApi).type,
          BackgroundEventResultType.newEvent,
        );
        provider.handleUnifiedEventForTest(event);
        expect(
          processor.process(event).type,
          BackgroundEventResultType.dropped,
        );
        expect(provider.unifiedEvents, hasLength(1));
        final update = event.copyWith(reportNumText: '第3報');
        provider.handleUnifiedEventForTest(update);
        expect(
          processor.process(update).type,
          BackgroundEventResultType.update,
        );
        expect(provider.unifiedEvents.single.reportNumText, '第3報');
        final expired = event.copyWith(
          eventId: 'old-scenario',
          originTime: event.originTime!.subtract(const Duration(hours: 1)),
        );
        provider.handleUnifiedEventForTest(expired);
        expect(provider.unifiedEvents, hasLength(1));
        expect(
          processor.process(expired).type,
          BackgroundEventResultType.dropped,
        );
      },
    );
  }

  test(
    'JMA cancellation, training, PLUM and missing hypocenter are explicit',
    () {
      final raw = scenario('jma-eew')
        ..addAll({'isCancel': true, 'isPLUM': true, 'isFinal': true});
      final event = QuakeEventAdapter.convertJian('jma-eew', raw)!;
      expect(event.isCanceled, isTrue);
      expect(event.isFinal, isTrue);
      expect(event.isAssumption, isTrue);
      raw['isTraining'] = true;
      expect(QuakeEventAdapter.convertJian('jma-eew', raw), isNull);
      final unknown = QuakeEventAdapter.convertJian('jma', {
        'id': 'unknown-scenario',
        'hypocenterUnknown': true,
        'magnitudeUnknown': true,
        'latitude': 0,
        'longitude': 0,
        'depth': null,
        'magnitude': 0,
      })!;
      expect(unknown.originTime, isNull);
      expect(unknown.reportTime, isNull);
      expect(unknown.lat, isNull);
      expect(unknown.lng, isNull);
      expect(unknown.magnitude, -1);
      final missingEewTime = QuakeEventAdapter.convertJian('jma-eew', {
        'id': 'missing-time-scenario',
      })!;
      expect(
        BackgroundEventProcessor(
          sourceInfoMagFilters: {},
        ).process(missingEewTime).type,
        BackgroundEventResultType.dropped,
      );
    },
  );

  test(
    'unnumbered KMA live revisions update; cached and cross-API bodies cannot roll back',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final raw = <String, dynamic>{
        'id': 'unnumbered-kma-scenario',
        'originTime': DateTime.now().millisecondsSinceEpoch,
        'latitude': 35,
        'longitude': 129,
        'depth': 10,
        'magnitude': 5.3,
        'placeName': '测试位置',
        'maxMMI': 4,
        'isWarn': true,
      };
      final event = QuakeEventAdapter.convertJian('kma-eew', raw)!;
      expect(event.reportNumText, isEmpty);
      expect(event.hasReportSequence, isFalse);
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: {},
        acceptedEewReportNums: {'kmaEew|unnumbered-kma-scenario': 0},
      );
      provider.handleUnifiedEventForTest(event);
      expect(processor.process(event).type, BackgroundEventResultType.newEvent);
      final update = event.copyWith(magnitude: 5.4, maxIntensity: '5');
      provider.handleUnifiedEventForTest(update);
      expect(processor.process(update).type, BackgroundEventResultType.update);
      provider.handleUnifiedEventForTest(update);
      expect(processor.process(update).type, BackgroundEventResultType.dropped);
      for (final stale in [
        event.copyWith(isSnapshot: true),
        event.copyWith(origin: 1, apiTypeLabel: 'FAN'),
      ]) {
        provider.handleUnifiedEventForTest(stale);
        expect(
          processor.process(stale).type,
          BackgroundEventResultType.dropped,
        );
      }
      expect(provider.unifiedEvents.single.magnitude, 5.4);
      expect(provider.unifiedEvents.single.maxIntensity, '5');
    },
  );

  test('multi-hazard and station frames are not coerced into earthquakes', () {
    for (final type in [
      'weather',
      'gdacs',
      'jma-volcano',
      'ifrc-alert',
      'usgs-volcano',
      'usgs-vona',
      'kmoni',
      's-net',
      'kma-station',
    ]) {
      expect(QuakeEventAdapter.convertJian(type, scenario(type)), isNull);
    }
  });

  test(
    'catalog replay fills CENC list and cannot roll back a newer JMA report',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final cenc = QuakeEventAdapter.convertJian(
        'cenc',
        scenario('cenc', id: 'cenc-history-scenario'),
        isHistory: true,
      )!;
      provider.handleUnifiedEventForTest(cenc);
      expect(
        provider.historyBySource['cencEqlist']!.any(
          (item) => item.eventId == cenc.eventId,
        ),
        isTrue,
      );
      final jma = QuakeEventAdapter.convertJian(
        'jma',
        scenario('jma', id: 'jma-revision-scenario'),
      )!;
      final latest = jma.copyWith(
        reportTime: jma.originTime!.add(const Duration(seconds: 10)),
        magnitude: 5.2,
      );
      provider.handleUnifiedEventForTest(latest);
      provider.handleUnifiedEventForTest(
        jma.copyWith(isHistory: true, reportTime: jma.originTime),
      );
      final row = provider.historyBySource['jmaEqlist']!.firstWhere(
        (item) => item.eventId == jma.eventId,
      );
      expect(row.magnitude, 5.2);
      expect(provider.unifiedEvents.single.magnitude, 5.2);
    },
  );

  test('history ordering retains the newest 50 records after mixed replay', () {
    final manager = EqlistManager();
    final base = DateTime(2040, 1, 1);
    for (var i = 60; i >= 0; i--) {
      manager.upsertBucketItem(
        'cencEqlist',
        QuakeMessage(
          source: QuakeSourceType.cenc,
          eventId: 'ordered-history-$i',
          location: '排序测试',
          magnitude: 5,
          latitude: 35,
          longitude: 140,
          depth: 10,
          originTime: base.add(Duration(minutes: i)),
          timeZone: 8,
          isHistory: true,
        ),
        replayOnly: true,
      );
    }
    expect(manager.cencList, hasLength(50));
    expect(manager.cencList.first.eventId, 'ordered-history-60');
    expect(manager.cencList.last.eventId, 'ordered-history-11');
  });

  testWidgets(
    'one socket, fullwidth-colon snapshot, live and history frames; stop cancels timers',
    (tester) async {
      final channel = FakeChannel();
      var opens = 0;
      final service = JianService(
        socketFactory: (_) {
          opens++;
          return channel;
        },
      );
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);
      service.connect();
      service.connect();
      await tester.pump();
      expect(opens, 1);
      channel.frames.add(jsonEncode(captured));
      await tester.pump();
      expect(events, hasLength(jianEarthquakeSources.length));
      expect(
        events.where((event) => !event.isEew).every((event) => event.isHistory),
        isTrue,
      );
      expect(service.ignoredTypes, contains('weather'));
      channel.frames.add(
        jsonEncode({'type': 'cenc', 'Data': scenario('cenc')}),
      );
      await tester.pump();
      expect(events.last.isHistory, isFalse);
      channel.frames.add(
        File('test/fixtures/jian/jmalist_response.json').readAsStringSync(),
      );
      await tester.pump();
      expect(
        events.where((event) => event.source == 'jmaEqlist' && event.isHistory),
        hasLength(51),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(channel.sent, isNotEmpty);
      service.disconnect();
      await tester.pump(const Duration(minutes: 10));
      expect(opens, 1);
      unawaited(subscription.cancel());
      service.dispose();
    },
  );

  testWidgets(
    'disconnect reconnects once after cooldown and then receives new frames',
    (tester) async {
      final sockets = <FakeChannel>[];
      final service = JianService(
        now: tester.binding.clock.now,
        socketFactory: (_) {
          final socket = FakeChannel();
          sockets.add(socket);
          return socket;
        },
      );
      final events = <UnifiedQuakeData>[];
      final sub = service.onUnifiedEvent.listen(events.add);
      service.connect();
      await tester.pump();
      expect(sockets, hasLength(1));
      unawaited(sockets.first.frames.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 44));
      expect(sockets, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(sockets, hasLength(2));
      sockets.last.frames.add(
        jsonEncode({'type': 'cenc', 'Data': scenario('cenc')}),
      );
      await tester.pump();
      expect(events, hasLength(1));
      service.dispose();
      unawaited(sub.cancel());
    },
  );

  testWidgets('IP ban persists cooldown and never reconnects in a tight loop', (
    tester,
  ) async {
    final channel = FakeChannel();
    var opens = 0;
    final states = <SourceStatus>[];
    final service = JianService(
      socketFactory: (_) {
        opens++;
        return channel;
      },
    );
    service.onStatusChanged = states.add;
    service.connect();
    await tester.pump();
    channel.frames.add(
      jsonEncode({'type': 'error', 'message': '您的IP已被封禁，请联系管理员进行处理'}),
    );
    await tester.pump();
    expect(states.last, SourceStatus.error);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(JianService.retryAfterPreferenceKey),
      greaterThan(DateTime.now().millisecondsSinceEpoch + 23 * 3600000),
    );
    await tester.pump(const Duration(minutes: 10));
    expect(opens, 1);
    service.dispose();
  });

  testWidgets('disconnected handshake cannot resurrect the disabled source', (
    tester,
  ) async {
    final ready = Completer<void>();
    final channel = FakeChannel(ready: ready.future);
    final states = <SourceStatus>[];
    final service = JianService(socketFactory: (_) => channel);
    service.onStatusChanged = states.add;
    service.connect();
    await tester.pump();
    service.disconnect();
    ready.complete();
    await tester.pump();
    expect(states.last, SourceStatus.disconnected);
    expect(states, isNot(contains(SourceStatus.connected)));
    service.dispose();
  });
}

class FakeChannel implements WebSocketChannel {
  FakeChannel({Future<void>? ready}) : ready = ready ?? Future<void>.value();
  final frames = StreamController<dynamic>();
  final sent = <Object?>[];
  @override
  final Future<void> ready;
  @override
  Stream<dynamic> get stream => frames.stream;
  @override
  late final WebSocketSink sink = FakeSink(sent);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSink implements WebSocketSink {
  FakeSink(this.sent);
  final List<Object?> sent;
  final _done = Completer<void>();
  @override
  void add(dynamic value) => sent.add(value);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
