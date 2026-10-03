import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/replay_station_display.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/eew_history_store.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_nied_station_metadata.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/nied_replay_fixture.dart';

HistoryReplayPackage cwa() => HistoryReplayPackage.decode(
  File('test/fixtures/history_replay/cwa_1150074.rqreplay').readAsStringSync(),
);

// Empty transport frames exercise scheduling, not fabricated observations.
StationHistoryFrame emptyFrame(String kind, DateTime receivedAt) =>
    StationHistoryFrame(
      receivedAt: receivedAt,
      snapshot: {
        'kind': kind,
        if (kind == 'lpgm') ...{
          'dataTime': receivedAt.toIso8601String(),
          'maxSva': 0.0,
          'maxClass': 0,
          'topStations': [],
        } else
          'stations': [],
      },
    );

EewEventGroup groupWith(List<StationHistoryFrame> frames) => EewEventGroup(
  eventId: cwa().reports.first.eventId,
  firstArrivedAt: cwa().times.first,
  reports: cwa().reports.reversed.toList(),
  stationFrames: frames,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('all seven sources including LPGM round trip as JSON only', () {
    final start = cwa().times.first;
    final frames = [
      for (final kind in StationHistoryFrame.kinds) emptyFrame(kind, start),
    ];
    final original = HistoryReplayPackage.fromGroup(groupWith(frames));
    final text = original.encode();
    final map = jsonDecode(text) as Map;
    expect(map['stationArchive']['format'], StationJsonArchive.format);
    expect(text, isNot(contains('imageBytes')));
    final restored = HistoryReplayPackage.decode(text);
    expect(
      restored.stationFrames.map((f) => f.toMap()),
      frames.map((f) => f.toMap()),
    );
    expect(
      restored.reports.map((r) => r.toMap()),
      original.reports.map((r) => r.toMap()),
    );
    final display = ReplayStationDisplay()
      ..update({for (final f in frames) f.kind: f});
    expect(display.lpgm, isNotNull);
    expect(display.lpgm!.topStations, isEmpty);
    display.update({});
    expect(display.lpgm, isNull);
  });

  test(
    'captured original NIED JSON survives immutable capture and table storage',
    () {
      final metadata =
          jsonDecode(
                File(
                  'test/fixtures/whews_nied/stations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final observations =
          jsonDecode(
                File(
                  'test/fixtures/whews_nied/observations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final capture = StationHistoryCapture();
      capture.retainOriginal('captured.nied', 'metadata', metadata);
      capture.retainOriginal('captured.nied', 'data', observations);
      var evaluations = 0;
      Map<String, dynamic> snapshot() {
        evaluations++;
        return {'kind': 'nied', 'stations': []};
      }

      capture.publish(
        'nied',
        snapshot,
        source: 'captured.nied',
        receivedAt: DateTime.parse('2026-09-08T10:47:23.899674Z'),
      );
      expect(evaluations, 0, reason: 'No snapshot serialization while idle');
      final frame = capture.latest.single;
      expect(frame.originalJson, {'metadata': metadata, 'data': observations});
      expect(
        identical(frame.originalJson, capture.original('captured.nied')),
        isTrue,
      );
      expect(() => frame.originalJson!['data'] = null, throwsUnsupportedError);
      final repeated = List<StationHistoryFrame>.filled(8, frame);
      final archive = StationJsonArchive.encode(repeated);
      final encoded = jsonEncode(archive);
      expect(
        encoded.length,
        lessThan(jsonEncode(repeated.map((f) => f.toMap()).toList()).length),
      );
      final restored = StationJsonArchive.decode(jsonDecode(encoded) as Map);
      expect(restored.map((f) => f.toMap()), repeated.map((f) => f.toMap()));
      expect(
        identical(
          restored.first.originalJson!['metadata'],
          restored.last.originalJson!['metadata'],
        ),
        isTrue,
        reason: 'Immutable table metadata stays shared across restored frames',
      );
      expect(
        () => (restored.first.originalJson!['metadata'] as Map)['data'] = null,
        throwsUnsupportedError,
      );
      expect(
        () => (restored.first.originalJson!['data'] as Map).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('JSON tables reject missing references and cyclic expansion', () {
    expect(
      () => StationJsonArchive.decode({
        'format': StationJsonArchive.format,
        'nodes': [
          ['l', 0],
        ],
        'frames': [0],
      }),
      throwsFormatException,
    );
    final nodes = <dynamic>[0];
    for (var i = 0; i < 24; i++) {
      nodes.add(['l', i, i]);
    }
    expect(
      () => StationJsonArchive.decode({
        'format': StationJsonArchive.format,
        'nodes': nodes,
        'frames': [24],
      }),
      throwsFormatException,
    );
  });

  test('malformed detection JSON is rejected before playback', () {
    expect(
      () => StationHistoryFrame(
        receivedAt: cwa().times.first,
        snapshot: {
          'kind': 'nied',
          'stations': [],
          'detection': {'stage': 'idle'},
        },
      ),
      throwsFormatException,
    );
  });

  test(
    'an original GIF is archived as station JSON without image bytes',
    () async {
      final file = File(
        'test/fixtures/nied_recovery/'
        '20260610180120.lmoni.jma_s.gif',
      );
      final decoded = (await decodeNiedGifFile(file))!;
      final service = LmoniImageService()..start();
      addTearDown(service.stop);
      final accepted = service.stationStream.firstWhere(
        (stations) => stations != null,
      );
      final stamp = DateTime(2026, 6, 10, 18, 1, 20);
      service.processPixels(
        decoded.packedRgb,
        surfaceGifBytes: decoded.gifBytes,
        dataTime: stamp,
        receivedAt: stamp,
      );
      final stations = (await accepted)!;
      final snapshot = ForegroundStationPayload.nied(
        stations,
        source: 'lmoni',
        includeTrackingHistory: false,
      );
      final frame = StationHistoryFrame(
        receivedAt: DateTime.utc(2026, 6, 10, 9, 1, 20),
        snapshot: snapshot,
      );
      final json = jsonEncode(StationJsonArchive.encode([frame]));
      expect(json, isNot(contains('imageBytes')));
      expect(json, isNot(contains('surfaceGifBytes')));
      final restored = StationJsonArchive.decode(
        jsonDecode(json) as Map,
      ).single;
      expect(restored.originalJson, isNull);
      final display = ReplayStationDisplay()..update({'nied': restored});
      expect(display.nied, hasLength(1630));
      expect(
        ForegroundStationPayload.nied(
          display.nied,
          source: 'lmoni',
          includeTrackingHistory: false,
        ),
        snapshot,
      );
    },
  );

  test(
    'actual captured NIED observations survive decoded station playback',
    () async {
      final metadata =
          jsonDecode(
                File(
                  'test/fixtures/whews_nied/stations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/whews_nied/observations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final before = jsonEncode(raw);
      final service = WhewsStationService(
        kind: WhewsStationKind.nied,
        apiToken: '',
      );
      final accepted = <WhewsStationFrame>[];
      final subscription = service.frameStream.listen(accepted.add);
      service.handleMessageForTesting(metadata);
      service.handleMessageForTesting(raw);
      // The frame owns its original JSON even if the shared latest cache changes.
      StationHistoryCapture.instance.restoreOriginal('whews.nied', {});
      await Future<void>.delayed(Duration.zero);
      expect(accepted, hasLength(1));
      final networkFrame = accepted.single;
      expect(networkFrame.originalJson, {'metadata': metadata, 'data': raw});
      final stations = buildWhewsNiedStations(networkFrame.coordinates);
      for (var i = 0; i < stations.length; i++) {
        final value = networkFrame.values[i];
        stations[i].updateFromContinuousShindo(
          whewsNiedSnetValueIsValid(value) ? value : null,
        );
      }
      final snapshot = ForegroundStationPayload.nied(
        stations,
        source: 'whews',
        includeTrackingHistory: false,
      );
      final frame = StationHistoryFrame(
        receivedAt: networkFrame.dataTime,
        snapshot: snapshot,
        originalJson: networkFrame.originalJson,
      );
      final restored = StationJsonArchive.decode(
        jsonDecode(jsonEncode(StationJsonArchive.encode([frame]))) as Map,
      ).single;
      final display = ReplayStationDisplay()..update({'nied': restored});
      expect(display.nied.length, stations.length);
      expect(
        ForegroundStationPayload.nied(
          display.nied,
          source: 'whews',
          includeTrackingHistory: false,
        ),
        snapshot,
      );
      expect(restored.originalJson!['data'], raw);
      expect(jsonEncode(raw), before);
      await subscription.cancel();
      service.dispose();
    },
  );

  test(
    'JSON chunks update references for overlapping events without dropping frames',
    () async {
      final start = cwa().times.first;
      final firstFrame = emptyFrame('nied', start);
      final secondFrame = emptyFrame(
        'nied',
        start.add(const Duration(seconds: 1)),
      );
      final thirdFrame = emptyFrame(
        'nied',
        start.add(const Duration(milliseconds: 1500)),
      );
      var first = groupWith([firstFrame, secondFrame]);
      final second = groupWith([
        secondFrame,
      ]).copyWith(eventId: 'shared-chunk-owner');
      final prefs = await SharedPreferences.getInstance();
      final store = EewHistoryStore(preferenceKey: 'chunk-test');
      await store.save(prefs, [first, second]);
      expect(
        prefs.getKeys().where((key) => key.contains('_station_archive_')),
        hasLength(1),
      );
      first = first.copyWith(
        stationFrames: [firstFrame, secondFrame, thirdFrame],
      );
      await store.save(prefs, [first, second]);
      var restored = EewHistoryStore(
        preferenceKey: 'chunk-test',
      ).restore(prefs);
      expect(
        restored.first.stationFrames.map((f) => f.toMap()),
        first.stationFrames.map((f) => f.toMap()),
      );
      expect(restored.last.stationFrames.single.toMap(), secondFrame.toMap());
      await store.save(prefs, [second]);
      restored = EewHistoryStore(preferenceKey: 'chunk-test').restore(prefs);
      expect(restored.single.stationFrames.single.toMap(), secondFrame.toMap());
      expect(
        prefs.getKeys().where((key) => key.contains('_station_archive_')),
        hasLength(1),
      );
    },
  );

  test(
    'live EEW records all seven sources and replay alone never records',
    () async {
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final capture = StationHistoryCapture.instance;
      provider.historyReplay.load(cwa());
      provider.historyReplay.play();
      expect(capture.recording, isFalse);
      final recorded = cwa().reports.first;
      // Only project the test's live clock. Keep the recorded source body unchanged.
      final live = recorded.copyWith(
        originTime: recorded.originTime!.add(
          provider.unifiedEvents.first.replayClockOffset,
        ),
      );
      provider.handleUnifiedEventForTest(
        live,
        alreadyAccepted: true,
        suppressEffects: true,
      );
      expect(capture.recording, isTrue);
      for (final kind in StationHistoryFrame.kinds) {
        final frame = emptyFrame(kind, DateTime.now().toUtc());
        capture.publish(
          kind,
          () => frame.snapshot,
          receivedAt: frame.receivedAt,
        );
      }
      expect(
        provider.eewHistory.single.stationFrames.map((f) => f.kind).toSet(),
        StationHistoryFrame.kinds,
      );
      expect(
        provider.eewHistory.single.latest.sourcePayload,
        recorded.sourcePayload,
      );
      provider.dismissUnifiedEventForTest(live);
      expect(capture.recording, isFalse);
      expect(provider.eewHistory.single.captureEndedAt, isNotNull);
      final count = provider.eewHistory.single.stationFrames.length;
      capture.publish(
        'lpgm',
        () => emptyFrame('lpgm', DateTime.now()).snapshot,
      );
      expect(provider.eewHistory.single.stationFrames.length, count);
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      final restored = EewHistoryStore(
        preferenceKey: 'unified_eew_history',
      ).restore(prefs);
      expect(restored.single.stationFrames.length, count);
      expect(restored.single.captureEndedAt, isNotNull);
    },
  );

  test(
    'multiple encoding batches keep all frames and skip unchanged archives',
    () async {
      final start = cwa().times.first;
      final frames = [
        for (final offset in [Duration.zero, const Duration(seconds: 30)])
          for (final kind in StationHistoryFrame.kinds)
            emptyFrame(kind, start.add(offset)),
      ];
      final prefs = await SharedPreferences.getInstance();
      final store = EewHistoryStore(preferenceKey: 'batch-history');
      final group = groupWith(frames);
      await store.save(prefs, [group]);
      final archives = prefs
          .getKeys()
          .where((key) => key.contains('_station_archive_'))
          .toList();
      expect(archives, hasLength(14));
      for (final key in archives) {
        await prefs.setString(key, '${prefs.getString(key)} ');
      }
      await store.save(prefs, [group]);
      for (final key in archives) {
        expect(
          prefs.getString(key),
          endsWith(' '),
          reason: 'Unchanged archive is not re-encoded or rewritten',
        );
      }
      final restored = EewHistoryStore(
        preferenceKey: 'batch-history',
      ).restore(prefs);
      expect(
        restored.single.stationFrames.map((f) => f.toMap()),
        frames.map((f) => f.toMap()),
      );
      await store.save(prefs, []);
      expect(archives.any(prefs.containsKey), isFalse);
    },
  );

  test(
    'incremental store restores frames and keeps shared frames until last owner is removed',
    () async {
      final frames = [
        for (final kind in StationHistoryFrame.kinds)
          emptyFrame(kind, cwa().times.first),
      ];
      final prefs = await SharedPreferences.getInstance();
      final store = EewHistoryStore(preferenceKey: 'test-history');
      final first = groupWith(frames);
      // Separate storage identity only; the original EEW body is unchanged.
      final second = first.copyWith(eventId: 'second-storage-owner');
      await store.save(prefs, [first, second]);
      final stationKeys = prefs
          .getKeys()
          .where((key) => key.contains('_station_'))
          .toSet();
      expect(stationKeys.length, 7);
      final restored = EewHistoryStore(
        preferenceKey: 'test-history',
      ).restore(prefs);
      expect(
        restored.first.stationFrames.map((f) => f.toMap()),
        frames.map((f) => f.toMap()),
      );
      await store.save(prefs, [second]);
      expect(stationKeys.every(prefs.containsKey), isTrue);
      await store.save(prefs, []);
      expect(stationKeys.any(prefs.containsKey), isFalse);
    },
  );

  test(
    'disabled cached stations stay out of live history and re-enable waits for a frame',
    () async {
      final capture = StationHistoryCapture.instance;
      final enabledBefore = {
        for (final kind in StationHistoryFrame.kinds)
          kind: capture.isEnabled(kind),
      };
      addTearDown(() {
        for (final entry in enabledBefore.entries) {
          capture.setEnabled(entry.key, entry.value);
        }
      });
      for (final kind in StationHistoryFrame.kinds) {
        capture.setEnabled(kind, false);
      }
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      addTearDown(provider.dispose);
      capture.setEnabled('nied', true);
      capture.publish(
        'nied',
        () => emptyFrame('nied', DateTime.now()).snapshot,
      );
      capture.setEnabled('nied', false);
      capture.setEnabled('lpgm', true);
      capture.publish(
        'lpgm',
        () => emptyFrame('lpgm', DateTime.now()).snapshot,
      );
      provider.historyReplay.load(cwa());
      provider.historyReplay.play();
      final recorded = cwa().reports.first;
      final live = recorded.copyWith(
        originTime: recorded.originTime!.add(
          provider.unifiedEvents.first.replayClockOffset,
        ),
        arrivedAt: DateTime.now().toUtc(),
      );
      provider.handleUnifiedEventForTest(
        live,
        alreadyAccepted: true,
        suppressEffects: true,
      );
      expect(provider.eewHistory.single.stationFrames.map((f) => f.kind), [
        'lpgm',
      ]);
      capture.publish(
        'nied',
        () => emptyFrame('nied', DateTime.now()).snapshot,
      );
      expect(provider.eewHistory.single.stationFrames.map((f) => f.kind), [
        'lpgm',
      ]);
      capture.setEnabled('nied', true);
      expect(provider.eewHistory.single.stationFrames.map((f) => f.kind), [
        'lpgm',
      ]);
      capture.publish(
        'nied',
        () => emptyFrame('nied', DateTime.now()).snapshot,
      );
      final group = provider.eewHistory.single;
      expect(group.stationFrames.map((f) => f.kind), ['lpgm', 'nied']);
      capture.setEnabled('nied', false);
      capture.publish(
        'nied',
        () => emptyFrame('nied', DateTime.now()).snapshot,
      );
      expect(provider.eewHistory.single.stationFrames, group.stationFrames);
      provider.dismissUnifiedEventForTest(live);
      final prefs = await SharedPreferences.getInstance();
      final store = EewHistoryStore(preferenceKey: 'enabled-station-history');
      await store.save(prefs, provider.eewHistory);
      final restored = EewHistoryStore(
        preferenceKey: 'enabled-station-history',
      ).restore(prefs);
      expect(
        restored.single.stationFrames.map((f) => f.toMap()),
        group.stationFrames.map((f) => f.toMap()),
      );
      expect(
        HistoryReplayPackage.fromGroup(restored.single).stationFrames,
        hasLength(2),
      );
    },
  );

  test('station timeline continues after the last report plus 30 seconds', () {
    final start = cwa().times.first;
    final package = HistoryReplayPackage.fromGroup(
      groupWith([
        emptyFrame('nied', start),
        emptyFrame('lpgm', start.add(const Duration(minutes: 8))),
      ]),
    );
    fakeAsync((async) {
      final clock = async.getClock(DateTime.utc(2026, 10, 2));
      final controller =
          HistoryReplayController(
              onReport: (_) {},
              onClear: (_) {},
              now: clock.now,
            )
            ..load(package)
            ..play();
      expect(controller.stationSnapshots.value.keys, ['nied']);
      async.elapse(package.duration + const Duration(seconds: 30));
      expect(controller.active, isTrue);
      expect(controller.holding, isTrue);
      async.elapse(
        const Duration(minutes: 8) -
            package.duration -
            const Duration(seconds: 30),
      );
      expect(controller.stationSnapshots.value.containsKey('lpgm'), isTrue);
      expect(controller.active, isTrue);
      async.elapse(const Duration(seconds: 30));
      expect(controller.active, isFalse);
      expect(controller.stationSnapshots.value, isEmpty);
      expect(async.nonPeriodicTimerCount, 0);
      controller.dispose();
    });
  });

  test(
    'stop cancels all pending station frames and restart has a fresh display',
    () {
      final start = cwa().times.first;
      final package = HistoryReplayPackage.fromGroup(
        groupWith([
          emptyFrame('nied', start),
          emptyFrame('lpgm', start.add(const Duration(minutes: 1))),
        ]),
      );
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2026, 10, 2));
        final controller =
            HistoryReplayController(
                onReport: (_) {},
                onClear: (_) {},
                now: clock.now,
              )
              ..load(package)
              ..play();
        controller.stop();
        async.elapse(const Duration(minutes: 2));
        expect(controller.stationSnapshots.value, isEmpty);
        expect(async.nonPeriodicTimerCount, 0);
        controller.play();
        expect(controller.stationSnapshots.value.keys, ['nied']);
        controller.stop();
        controller.dispose();
      });
    },
  );
}
