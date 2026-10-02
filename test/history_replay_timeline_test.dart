import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_replay_test.dart' as recorded;

HistoryReplayPackage captured(String name) => HistoryReplayPackage.decode(
  File('test/fixtures/history_replay/$name.rqreplay').readAsStringSync(),
);

EewEventGroup saved(HistoryReplayPackage package) => EewEventGroup(
  eventId: package.reports.first.eventId,
  reports: package.reports,
  firstArrivedAt: package.reports.first.arrivedAt!,
  stationFrames: package.stationFrames,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final cwa = captured('cwa_1150074');
  final cea = captured('cea_202609290220');
  final interval = cea.reports.first.arrivedAt!.difference(
    cwa.reports.first.arrivedAt!,
  );

  test('timeline is off by default and imported events stay isolated', () {
    fakeAsync((async) {
      final output = <UnifiedQuakeData>[];
      final controller = HistoryReplayController(
        onReport: output.add,
        onClear: (_) {},
        now: async.getClock(DateTime.utc(2026, 10, 2)).now,
      )..importPackages([cwa, cea]);
      expect(controller.timelineLinked, isFalse);
      controller.play();
      async.elapse(const Duration(seconds: 30));
      expect(output.length, 4);
      expect(output.every((e) => e.source == cwa.reports.first.source), isTrue);
      expect(controller.linkedEventCount, 1);
      controller.dispose();
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('CWA anchor plays CEA at its original saved arrival on one clock', () {
    expect(interval, const Duration(microseconds: 19334990));
    final before = [cwa.encode(), cea.encode()];
    fakeAsync((async) {
      final output = <UnifiedQuakeData>[];
      final controller =
          HistoryReplayController(
              onReport: output.add,
              onClear: (_) {},
              now: async.getClock(DateTime.utc(2026, 10, 2)).now,
            )
            ..importPackages([cwa, cea])
            ..restoreTimelineLinked(true)
            ..play();
      expect(controller.linkedEventCount, 2);
      expect(controller.totalReports, 5);
      expect(controller.usesArrivalTimeline, isTrue);
      expect(output.length, 1);
      async.elapse(cwa.duration);
      expect(output.length, 4);
      async.elapse(interval - cwa.duration - const Duration(microseconds: 1));
      expect(output.length, 4);
      async.elapse(const Duration(microseconds: 1));
      expect(output.length, 5);
      final originals = [...cwa.reports, ...cea.reports];
      for (var i = 0; i < output.length; i++) {
        expect(output[i].sourcePayload, originals[i].sourcePayload);
        expect(output[i].originTime, originals[i].originTime);
        expect(output[i].reportTime, originals[i].reportTime);
        expect(output[i].replayClockOffset, output.first.replayClockOffset);
      }
      expect(
        output.last.arrivedAt!.difference(output.first.arrivedAt!),
        interval,
      );
      expect([cwa.encode(), cea.encode()], before);
      controller.dispose();
    });
  });

  test('CEA anchor restores only the latest still-active CWA report', () {
    fakeAsync((async) {
      final output = <UnifiedQuakeData>[];
      final controller =
          HistoryReplayController(
              onReport: output.add,
              onClear: (_) {},
              now: async.getClock(DateTime.utc(2026, 10, 2)).now,
            )
            ..importPackages([cea, cwa])
            ..restoreTimelineLinked(true)
            ..play();
      async.elapse(Duration.zero);
      expect(controller.linkedEventCount, 2);
      expect(controller.totalReports, 2);
      expect(controller.position, cea.reports.first.arrivedAt!.toUtc());
      expect(output.length, 2);
      expect(output.last.sourcePayload, cwa.reports.last.sourcePayload);
      expect(output.last.reportNumText, cwa.reports.last.reportNumText);
      expect(output.first.replayClockOffset, output.last.replayClockOffset);
      controller.dispose();
    });
  });

  test(
    'history and imports deduplicate and unrelated original events are excluded',
    () {
      final unrelated = HistoryReplayPackage.fromGroup(
        recorded.group([recorded.recordedEew()]),
      );
      fakeAsync((async) {
        final output = <UnifiedQuakeData>[];
        final controller =
            HistoryReplayController(
                onReport: output.add,
                onClear: (_) {},
                now: async.getClock(DateTime.utc(2026, 10, 2)).now,
                historyGroups: () => [saved(cwa), saved(cea)],
              )
              ..importPackages([cwa, cea, unrelated])
              ..restoreTimelineLinked(true)
              ..play();
        async.elapse(interval);
        expect(controller.linkedEventCount, 2);
        expect(output.length, 5);
        controller.stop();
        async.elapse(const Duration(hours: 1));
        expect(output.length, 5);
        expect(async.nonPeriodicTimerCount, 0);
        controller.play();
        async.elapse(interval);
        expect(output.length, 10);
        controller.dispose();
        expect(async.nonPeriodicTimerCount, 0);
      });
    },
  );

  test(
    'events expire independently and the session lasts until the last one',
    () {
      fakeAsync((async) {
        final expired = <UnifiedQuakeData>[];
        final controller =
            HistoryReplayController(
                onReport: (_) {},
                onClear: (_) {},
                onEventExpired: (_, report) => expired.add(report),
                now: async.getClock(DateTime.utc(2026, 10, 2)).now,
              )
              ..importPackages([cwa, cea])
              ..restoreTimelineLinked(true)
              ..play();
        // These captures have different original expiry instants. The first
        // callback must not end the other event's replay.
        for (var i = 0; i < 3600 && expired.isEmpty && controller.active; i++) {
          async.elapse(const Duration(seconds: 1));
        }
        expect(expired, isNotEmpty);
        expect(controller.active, isTrue);
        async.elapse(const Duration(hours: 1));
        expect(controller.active, isFalse);
        expect(async.nonPeriodicTimerCount, 0);
        controller.dispose();
      });
    },
  );

  test(
    'shared station and LPGM JSON frames appear once on the linked timeline',
    () {
      // Empty transport frames verify scheduling and deduplication, not invented
      // station observations. The original earthquake captures are unchanged.
      final at = cea.reports.first.arrivedAt!;
      final frames = [
        StationHistoryFrame(
          receivedAt: at,
          snapshot: {'kind': 'nied', 'stations': []},
        ),
        StationHistoryFrame(
          receivedAt: at,
          snapshot: {'kind': 'lpgm', 'topStations': []},
        ),
      ];
      final first = HistoryReplayPackage.fromGroup(
        saved(cwa).copyWith(stationFrames: frames),
      );
      final second = HistoryReplayPackage.fromGroup(
        saved(cea).copyWith(stationFrames: frames),
      );
      fakeAsync((async) {
        final controller =
            HistoryReplayController(
                onReport: (_) {},
                onClear: (_) {},
                now: async.getClock(DateTime.utc(2026, 10, 2)).now,
              )
              ..importPackages([first, second])
              ..restoreTimelineLinked(true)
              ..play();
        expect(controller.totalStationFrames, 2);
        expect(controller.stationSnapshots.value, isEmpty);
        async.elapse(interval);
        expect(
          controller.stationSnapshots.value.keys,
          unorderedEquals(['nied', 'lpgm']),
        );
        expect(
          controller.stationSnapshots.value['lpgm']!.toMap(),
          frames.last.toMap(),
        );
        controller.stop();
        expect(controller.stationSnapshots.value, isEmpty);
        expect(async.nonPeriodicTimerCount, 0);
        controller.dispose();
      });
    },
  );

  test(
    'a setting change applies on restart without altering an active plan',
    () {
      fakeAsync((async) {
        final controller =
            HistoryReplayController(
                onReport: (_) {},
                onClear: (_) {},
                now: async.getClock(DateTime.utc(2026, 10, 2)).now,
              )
              ..importPackages([cwa, cea])
              ..play();
        controller.setTimelineLinked(true);
        controller.restoreTimelineLinked(false);
        expect(controller.timelineLinked, isTrue);
        expect(controller.linkedEventCount, 1);
        controller.play();
        expect(controller.linkedEventCount, 2);
        async.flushMicrotasks();
        controller.dispose();
      });
    },
  );

  test(
    'conflicting station records fail without stopping the running replay',
    () {
      // Same empty transport snapshot but different raw JSON availability.
      // Do not invent station readings to test conflict handling.
      final at = cea.reports.first.arrivedAt!;
      final first = HistoryReplayPackage.fromGroup(
        saved(cwa).copyWith(
          stationFrames: [
            StationHistoryFrame(
              receivedAt: at,
              snapshot: {'kind': 'nied', 'stations': []},
            ),
          ],
        ),
      );
      final second = HistoryReplayPackage.fromGroup(
        saved(cea).copyWith(
          stationFrames: [
            StationHistoryFrame(
              receivedAt: at,
              snapshot: {'kind': 'nied', 'stations': []},
              originalJson: {},
            ),
          ],
        ),
      );
      fakeAsync((async) {
        final output = <UnifiedQuakeData>[];
        final controller =
            HistoryReplayController(
                onReport: output.add,
                onClear: (_) {},
                now: async.getClock(DateTime.utc(2026, 10, 2)).now,
              )
              ..importPackages([first, second])
              ..play();
        final session = output.single.replaySessionId;
        controller.restoreTimelineLinked(true);
        expect(controller.play, throwsFormatException);
        expect(controller.active, isTrue);
        async.elapse(first.duration);
        expect(output.length, 4);
        expect(output.last.replaySessionId, session);
        controller.dispose();
      });
    },
  );

  test(
    'provider restores the switch and simultaneous events do not write history',
    () async {
      SharedPreferences.setMockInitialValues({
        HistoryReplayController.timelinePreferenceKey: true,
        'unified_eew_history': jsonEncode([
          saved(cwa).toMap(),
          saved(cea).toMap(),
        ]),
      });
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final before = jsonEncode(
        provider.eewHistory.map((e) => e.toMap()).toList(),
      );
      final replay = provider.historyReplay;
      expect(replay.timelineLinked, isTrue);
      replay.load(cea, remember: false);
      replay.play();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(provider.unifiedEvents.where((e) => e.isReplay).length, 2);
      expect(
        jsonEncode(provider.eewHistory.map((e) => e.toMap()).toList()),
        before,
      );
      replay.stop();
      expect(provider.unifiedEvents, isEmpty);
      provider.dispose();
    },
  );
}
