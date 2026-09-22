import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

UnifiedQuakeData recordedEew() {
  final frames =
      jsonDecode(
            File(
              'test/fixtures/catalog_20260917/whews_all.json',
            ).readAsStringSync(),
          )
          as List;
  final frame = frames.firstWhere((e) => e['source'] == 'jma_eew');
  return QuakeEventAdapter.convertWhews(
    frame['source'],
    Map<String, dynamic>.from(frame['Data']),
  )!;
}

EewEventGroup group(List<UnifiedQuakeData> reports) => EewEventGroup(
  eventId: reports.first.eventId,
  reports: reports,
  firstArrivedAt: reports.first.originTime!,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stopping replay leaves a same-agency live event and its history intact',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final captured = recordedEew();
      final package = HistoryReplayPackage.fromGroup(group([captured]));
      provider.historyReplay.load(package);
      provider.historyReplay.play();
      // Isolated live-input projection; the captured raw payload/file is unchanged.
      final offset = provider.unifiedEvents.single.replayClockOffset;
      final live = captured.copyWith(
        originTime: captured.originTime!.add(offset),
      );
      provider.handleUnifiedEventForTest(live, alreadyAccepted: true);
      expect(provider.unifiedEvents.where((e) => e.isReplay).length, 1);
      expect(provider.unifiedEvents.where((e) => !e.isReplay).length, 1);
      expect(provider.currentUnifiedEvent!.isReplay, isFalse);
      final before = jsonEncode(
        provider.eewHistory.map((e) => e.toMap()).toList(),
      );
      provider.historyReplay.stop();
      expect(provider.unifiedEvents.single.eventId, captured.eventId);
      provider.historyReplay.play();
      provider.historyReplay.stop();
      expect(
        jsonEncode(provider.eewHistory.map((e) => e.toMap()).toList()),
        before,
      );
      expect(provider.unifiedEvents.single.isReplay, isFalse);
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'package round trip preserves complete recorded raw report and timestamps',
    () {
      final event = recordedEew();
      final before = jsonEncode(event.toMap());
      final package = HistoryReplayPackage.fromGroup(group([event]));
      final restored = HistoryReplayPackage.decode(package.encode());
      expect(jsonEncode(restored.reports.single.toMap()), before);
      expect(jsonEncode(event.toMap()), before);
      expect(
        restored.times.single,
        QuakeTime.unifiedInstantUtc(
          event,
          value: QuakeEventAdapter.savedReportTime(
            event.sourcePayload!,
            event.timeZone,
          ),
        ),
      );
      expect(
        () => restored.reports.single.sourcePayload!.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('missing original reports are counted and never invented', () {
    final event = recordedEew();
    final missing = UnifiedQuakeData.fromMap({
      ...event.toMap(),
      'sourcePayload': null,
    });
    final package = HistoryReplayPackage.fromGroup(group([missing, event]));
    expect(package.omittedReports, 1);
    expect(package.reports.length, 1);
    expect(
      () => HistoryReplayPackage.fromGroup(group([missing])),
      throwsFormatException,
    );
  });

  test('invalid package and unsupported version fail before playback', () {
    final package = HistoryReplayPackage.fromGroup(group([recordedEew()]));
    final map = jsonDecode(package.encode()) as Map<String, dynamic>;
    for (final invalid in [
      {...map, 'version': 999},
      {...map, 'reports': []},
      {
        ...map,
        'reports': [null],
      },
      {
        ...map,
        'reports': ['bad'],
      },
      {
        ...map,
        'reports': [
          {...package.reports.single.toMap(), 'sourcePayload': {}},
        ],
      },
      {
        ...map,
        'reports': [
          {...package.reports.single.toMap(), 'lat': 1000},
        ],
      },
    ]) {
      expect(
        () => HistoryReplayPackage.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    }
    expect(() => HistoryReplayPackage.decode('{'), throwsFormatException);
  });

  test(
    'existing simulation reports without publication times require manual advance',
    () {
      // Existing simulation input, not an observation and not rewritten here.
      final input =
          jsonDecode(
                File(
                  'tools/fixtures/tohoku_20110311_eew_burst.json',
                ).readAsStringSync(),
              )
              as Map;
      final original = (input['reports'] as List).take(2).map((raw) {
        return QuakeEventAdapter.convert(
          'jmaEew',
          Map<String, dynamic>.from(raw),
          0,
        )!;
      }).toList();
      // The existing scenario metadata supplies origin time, but no report times.
      final reports = original
          .map(
            (e) => e.copyWith(
              originTime: DateTime.parse(input['meta']['truth']['originJst']),
            ),
          )
          .toList();
      final package = HistoryReplayPackage.fromGroup(group(reports));
      expect(package.manualTiming, isTrue);
      fakeAsync((async) {
        final output = <UnifiedQuakeData>[];
        final controller =
            HistoryReplayController(onReport: output.add, onClear: (_) {})
              ..load(package)
              ..play();
        async.elapse(const Duration(minutes: 1));
        expect(output.length, 1);
        controller.next();
        expect(output.length, 2);
        expect(controller.holding, isTrue);
        controller.next();
        expect(output.length, 2);
        controller.dispose();
        expect(async.nonPeriodicTimerCount, 0);
      });
    },
  );

  test('original report intervals, cancellation and restart are isolated', () {
    // Two unmodified captured reports exercise the scheduler across event types.
    final frames =
        jsonDecode(
              File(
                'test/fixtures/catalog_20260917/whews_all.json',
              ).readAsStringSync(),
            )
            as List;
    final eew = recordedEew();
    final events = <UnifiedQuakeData>[];
    for (final frame in frames) {
      final event = QuakeEventAdapter.convertWhews(
        frame['source'],
        Map<String, dynamic>.from(frame['Data']),
      );
      if (event?.originTime == null || event?.reportTime == null) continue;
      final diff = QuakeTime.unifiedInstantUtc(
        event!,
        value: event.reportTime,
      ).difference(HistoryReplayPackage.reportInstant(eew)!).abs();
      if (diff > Duration.zero && diff < const Duration(hours: 24)) {
        events.add(event);
      }
    }
    expect(events, isNotEmpty);
    final package = HistoryReplayPackage.fromGroup(group([eew, events.first]));
    fakeAsync((async) {
      final clock = async.getClock(DateTime.utc(2026, 9, 22));
      final output = <UnifiedQuakeData>[];
      final cleared = <String>[];
      final controller =
          HistoryReplayController(
              onReport: output.add,
              onClear: cleared.add,
              now: clock.now,
            )
            ..load(package)
            ..play();
      expect(output.length, 1);
      expect(output.single.originTime, package.reports.first.originTime);
      expect(output.single.sourcePayload, package.reports.first.sourcePayload);
      final firstId = output.single.replaySessionId;
      async.elapse(package.duration - const Duration(milliseconds: 1));
      expect(output.length, 1);
      controller.stop();
      async.elapse(package.duration);
      expect(output.length, 1);
      expect(cleared, [firstId]);
      controller.play();
      expect(output.last.replaySessionId, isNot(firstId));
      async.elapse(package.duration);
      expect(output.length, 3);
      expect(controller.holding, isTrue);
      async.elapse(const Duration(seconds: 30));
      expect(controller.active, isFalse);
      expect(async.nonPeriodicTimerCount, 0);
      controller.dispose();
    });
  });

  test(
    'provider playback displays old reports without writing history or alerting',
    () async {
      final event = recordedEew();
      final saved = group([event]);
      SharedPreferences.setMockInitialValues({
        'unified_eew_history': jsonEncode([saved.toMap()]),
      });
      final provider = QuakeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      var notifications = 0;
      provider.onUnifiedEventNotified = (_, _) => notifications++;
      final before = jsonEncode(
        provider.eewHistory.map((g) => g.toMap()).toList(),
      );
      final replay = provider.historyReplay;
      replay.load(HistoryReplayPackage.fromGroup(saved));
      replay.play();
      expect(provider.unifiedEvents.length, 1);
      final active = provider.unifiedEvents.single;
      expect(active.isReplay, isTrue);
      expect(active.apiTypeLabel, '本地注入 · 回放');
      expect(active.originTime, event.originTime);
      expect(active.sourcePayload, event.sourcePayload);
      expect(
        QuakeTime.calcPassedSecondsUnified(active),
        closeTo(
          HistoryReplayPackage.reportInstant(
            event,
          )!.difference(QuakeTime.unifiedInstantUtc(event)).inSeconds,
          1,
        ),
      );
      expect(
        provider.unifiedMapEvents.single.originTime,
        event.originTime!.add(active.replayClockOffset),
      );
      expect(
        jsonEncode(provider.eewHistory.map((g) => g.toMap()).toList()),
        before,
      );
      expect(notifications, 0);
      replay.stop();
      expect(provider.unifiedEvents, isEmpty);
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('unified_eew_history'), before);
    },
  );
}
