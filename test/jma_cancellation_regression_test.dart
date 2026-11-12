import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutterrhythmquake/core/utils/eew_cancellation.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixture = 'test/fixtures/jma_cancellation_20261016';

// Reference mapping of the supplied official telegram schema, NOT a claim that
// this is a Wolfx/Jian/WHEWS wire body. Every source field and raw body is kept.
UnifiedQuakeData officialReference(Map<String, dynamic> raw) {
  final body = raw['body'] as Map;
  final earthquake = body['earthquake'] as Map?;
  final hypocenter = earthquake?['hypocenter'] as Map?;
  final coordinate = hypocenter?['coordinate'] as Map?;
  final canceled = body['isCanceled'] == true;
  DateTime sourceClock(String value) {
    final utc = DateTime.parse(value).toUtc().add(const Duration(hours: 9));
    return DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
  }

  return UnifiedQuakeData(
    source: 'jmaEew',
    origin: 4,
    eventId: raw['eventId'],
    isEew: true,
    timeZone: 9,
    titleText: canceled ? '緊急地震速報（キャンセル）' : raw['title'],
    reportNumText: '第${raw['serialNo']}報',
    useShindo: true,
    maxIntensity: canceled
        ? 'なし'
        : '${body['intensity']?['forecastMaxInt']?['from'] ?? '-'}',
    className: canceled ? 'dark-gray' : 'purple',
    hypocenter: canceled ? '取り消されました' : '${hypocenter?['name'] ?? ''}',
    originTime: earthquake?['originTime'] == null
        ? null
        : sourceClock(earthquake!['originTime']),
    reportTime: sourceClock(raw['reportDateTime']),
    magnitude: double.tryParse('${earthquake?['magnitude']?['value']}') ?? -1,
    depth: double.tryParse('${hypocenter?['depth']?['value']}') ?? -1,
    lat: double.tryParse('${coordinate?['latitude']?['value']}'),
    lng: double.tryParse('${coordinate?['longitude']?['value']}'),
    isWarn: body['isWarning'] == true,
    isFinal: body['isLastInfo'] == true,
    isCanceled: canceled,
    apiTypeLabel: 'JMA 原始电文参考',
    sourcePayload: raw,
  );
}

void main() {
  setUp(() => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore());
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = File('$fixture/original_telegrams.zip').readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final reports = archive.files.where((file) => file.isFile).map((file) {
    return officialReference(
      jsonDecode(utf8.decode(file.content as List<int>))
          as Map<String, dynamic>,
    );
  }).toList()..sort((a, b) => a.reportTime!.compareTo(b.reportTime!));
  final cancellation = reports.singleWhere((report) => report.isCanceled);
  UnifiedQuakeData report(int number) => reports.firstWhere(
    (report) => !report.isCanceled && report.reportNumText == '第$number報',
  );
  final wolfxRaw =
      jsonDecode(
            File(
              '$fixture/wolfx_original.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map<String, dynamic>;
  final wolfx = QuakeEventAdapter.convert('jmaEew', wolfxRaw, 0)!;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
  });
  tearDown(() => SoundEffectService().enabled = true);

  test('FAN conversion emits JMA cancellation instead of returning early', () {
    // Schema projection from the original telegram, not a captured FAN frame.
    final raw = cancellation.sourcePayload!;
    final payload = <String, dynamic>{
      'eventId': raw['eventId'],
      'updates': int.parse(raw['serialNo']),
      'cancel': raw['body']['isCanceled'],
      'final': raw['body']['isLastInfo'],
      'createTime': reports.first.sourcePayload!['reportDateTime'],
      'updateTime': raw['reportDateTime'],
    };
    final before = jsonEncode(payload);
    final event = FanService.decodeEventPayload(payload, sourceHint: 'jma');
    expect(event, isNotNull);
    expect(event!.source, 'jmaEew');
    expect(event.isCanceled, isTrue);
    expect(event.reportNumText, '第37報');
    expect(event.originTime, isNull);
    expect(
      QuakeTime.unifiedInstantUtc(event, value: event.reportTime),
      QuakeTime.unifiedInstantUtc(cancellation, value: cancellation.reportTime),
    );
    expect(jsonEncode(payload), before);
  });

  test(
    'WHEWS dedupe distinguishes cancellation with unchanged serial and missing times',
    () async {
      // Minimal transport projections use only actual identity/serial/status
      // values from original ordinary 37 and cancellation 37 telegrams.
      final service = WhewsService(apiToken: '');
      addTearDown(service.dispose);
      final output = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(output.add);
      addTearDown(subscription.cancel);
      Map<String, dynamic> frame(UnifiedQuakeData event) => {
        'source': 'jma_eew',
        'Data': {
          'eventId': event.sourcePayload!['eventId'],
          'updates': int.parse(event.sourcePayload!['serialNo']),
          'cancel': event.sourcePayload!['body']['isCanceled'],
        },
      };
      service.handleMessageForTesting(frame(report(37)));
      service.handleMessageForTesting(frame(cancellation));
      service.handleMessageForTesting(frame(cancellation));
      await Future<void>.delayed(Duration.zero);
      expect(output, hasLength(2));
      expect(output.last.isCanceled, isTrue);
    },
  );

  test(
    'uses the unchanged original archive and confirms 42 -> cancellation 37',
    () {
      expect(
        sha256.convert(bytes).toString(),
        'e53fae54ff4c02dfd011290932bc2a272b73cbf535b7f7a340d464cc3ece56b1',
      );
      expect(reports, hasLength(43));
      expect(reports[41].reportNumText, '第42報');
      expect(reports.last.reportNumText, '第37報');
      expect(cancellation.originTime, isNull);
      expect(cancellation.lat, isNull);
      expect(isEewCancellationTransition(report(42), cancellation), isTrue);
      expect(
        canAcceptEewCancellation(
          cancellation,
          previous: report(42),
          now: QuakeTime.unifiedInstantUtc(
            cancellation,
            value: cancellation.reportTime,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'real Wolfx keeps serial 42 and previous announcement time on cancellation',
    () {
      expect(
        sha256
            .convert(File('$fixture/wolfx_original.json').readAsBytesSync())
            .toString(),
        '43683f6954d40ea83bffb7f9bead452c6032812a41288149842ae5b9beefab11',
      );
      expect(wolfx.isCanceled, isTrue);
      expect(wolfx.reportNumText, '第42報');
      expect(
        QuakeTime.unifiedInstantUtc(wolfx, value: wolfx.reportTime),
        DateTime.parse('2026-10-16T03:48:10Z'),
      );
      expect(isEewCancellationTransition(report(42), wolfx), isTrue);
      expect(
        canAcceptEewCancellation(
          wolfx,
          now: QuakeTime.unifiedInstantUtc(
            cancellation,
            value: cancellation.reportTime,
          ),
        ),
        isFalse,
      );
      expect(
        canAcceptEewCancellation(
          wolfx,
          previous: report(
            35,
          ).copyWith(arrivedAt: DateTime.parse('2026-10-16T03:46:02Z')),
          now: QuakeTime.unifiedInstantUtc(
            cancellation,
            value: cancellation.reportTime,
          ),
          localNow: QuakeTime.unifiedInstantUtc(
            cancellation,
            value: cancellation.reportTime,
          ),
        ),
        isTrue,
      );
      expect(wolfx.sourcePayload, wolfxRaw);
    },
  );

  test(
    'history retains both ordinary 37 and cancel 37, terminal status and max serial',
    () {
      var group = EewEventGroup(
        eventId: reports.first.eventId,
        reports: [reports.first],
        firstArrivedAt: reports.first.reportTime!,
      );
      for (final event in reports.skip(1)) {
        group = group.addReport(event);
      }
      expect(group.reportCount, 43);
      expect(group.isCanceled, isTrue);
      expect(group.latest, same(cancellation));
      expect(group.latestReportNumber, 42);
      expect(
        group.reports.where((r) => r.reportNumText == '第37報'),
        hasLength(2),
      );
      final restored = EewEventGroup.fromMap(group.toMap());
      expect(restored.isCanceled, isTrue);
      final package = HistoryReplayPackage.fromGroup(restored);
      expect(package.timing, HistoryReplayTiming.report);
      expect(package.reports.last.isCanceled, isTrue);
      expect(
        package.times.last,
        QuakeTime.unifiedInstantUtc(
          cancellation,
          value: cancellation.reportTime,
        ),
      );
    },
  );

  test(
    'foreground and background accept the original complete incident in source time',
    () async {
      var sourceNow = QuakeTime.unifiedInstantUtc(
        reports.first,
        value: reports.first.reportTime,
      );
      final provider = QuakeProvider(
        startCatalogServices: false,
        eewClock: () => sourceNow,
      );
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final background = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        eewClock: () => sourceNow,
      );
      for (final event in reports) {
        sourceNow = QuakeTime.unifiedInstantUtc(event, value: event.reportTime);
        provider.handleUnifiedEventForTest(event, suppressEffects: true);
        final accepted = background.process(event);
        if (event.isCanceled) {
          expect(accepted.type, BackgroundEventResultType.update);
          expect(accepted.event!.isCanceled, isTrue);
        }
      }
      final current = provider.unifiedEvents.single;
      expect(current.isCanceled, isTrue);
      expect(current.reportNumText, '第37報');
      expect(current.className, 'dark-gray');
      expect(
        UnifiedEventPresentation.fromEvent(current).title,
        contains('キャンセル'),
      );
      expect(provider.eewHistory.single.isCanceled, isTrue);
      final arrival = current.arrivedAt;
      provider.handleUnifiedEventForTest(wolfx, suppressEffects: true);
      provider.handleUnifiedEventForTest(report(42), suppressEffects: true);
      expect(provider.unifiedEvents.single.arrivedAt, arrival);
      expect(provider.unifiedEvents.single.isCanceled, isTrue);
      expect(background.process(wolfx).type, BackgroundEventResultType.dropped);
      final restarted = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        eewClock: () => sourceNow,
        acceptedEewReportNums: background.acceptedEewReportNums,
        canceledEewEvents: background.canceledEewEvents,
      );
      expect(
        restarted.process(report(42)).type,
        BackgroundEventResultType.dropped,
      );
      expect(
        restarted.process(cancellation).type,
        BackgroundEventResultType.dropped,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final prefs = await SharedPreferences.getInstance();
      final persisted = decodeCanceledEewEvents(
        prefs.getStringList(
          BackgroundEventProcessor.canceledEewEventsPreferenceKey,
        )!,
      );
      expect(persisted.containsKey('jmaEew|20261016123810'), isTrue);
    },
  );

  testWidgets(
    'expired/dismissed ordinary event still displays cancellation for 20 seconds once',
    (tester) async {
      var sourceNow = QuakeTime.unifiedInstantUtc(
        report(35),
        value: report(35).reportTime,
      );
      final provider = QuakeProvider(
        startCatalogServices: false,
        eewClock: () => sourceNow,
      );
      await tester.pump(const Duration(milliseconds: 100));
      provider.handleUnifiedEventForTest(report(35), suppressEffects: true);
      provider.dismissUnifiedEventForTest(provider.unifiedEvents.single);
      sourceNow = QuakeTime.unifiedInstantUtc(
        cancellation,
        value: cancellation.reportTime,
      );
      provider.handleUnifiedEventForTest(cancellation, suppressEffects: true);
      expect(provider.unifiedEvents.single.isCanceled, isTrue);
      final mapState = MapStateProvider()..setShowEstimatedEpicenter(false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<QuakeProvider>.value(value: provider),
            ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
          ],
          child: const MaterialApp(home: Scaffold(body: AlertModule())),
        ),
      );
      expect(find.textContaining('キャンセル'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(provider.unifiedEvents.single.isCanceled, isTrue);
      await tester.pump(const Duration(seconds: 18));
      provider.handleUnifiedEventForTest(wolfx, suppressEffects: true);
      expect(provider.unifiedEvents, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(provider.unifiedEvents, isEmpty);
      provider.handleUnifiedEventForTest(cancellation, suppressEffects: true);
      provider.handleUnifiedEventForTest(report(42), suppressEffects: true);
      expect(provider.unifiedEvents, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      mapState.dispose();
      provider.dispose();
      await tester.pump();
    },
  );

  testWidgets('background cancellation restores only its remaining window', (
    tester,
  ) async {
    final arrival = DateTime.now().subtract(const Duration(seconds: 10));
    SharedPreferences.setMockInitialValues({
      BackgroundEventProcessor.canceledEewEventsPreferenceKey:
          encodeCanceledEewEvents({'jmaEew|20261016123810': arrival}),
    });
    final provider = QuakeProvider(
      startCatalogServices: false,
      eewClock: () => QuakeTime.unifiedInstantUtc(
        cancellation,
        value: cancellation.reportTime,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final handoff = cancellation.copyWith(arrivedAt: arrival);
    provider.handleUnifiedEventForTest(
      handoff,
      alreadyAccepted: true,
      suppressEffects: true,
    );
    expect(provider.unifiedEvents.single.isCanceled, isTrue);
    await tester.pump(const Duration(seconds: 9));
    expect(provider.unifiedEvents, hasLength(1));
    provider.handleUnifiedEventForTest(
      handoff,
      alreadyAccepted: true,
      suppressEffects: true,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(provider.unifiedEvents, isEmpty);
    provider.handleUnifiedEventForTest(
      handoff,
      alreadyAccepted: true,
      suppressEffects: true,
    );
    expect(provider.unifiedEvents, isEmpty);
    provider.dispose();
    await tester.pump();
  });

  testWidgets(
    'original 43-telegram timed replay reaches the terminal UI report',
    (tester) async {
      var sourceNow = QuakeTime.unifiedInstantUtc(
        reports.first,
        value: reports.first.reportTime,
      );
      final provider = QuakeProvider(
        startCatalogServices: false,
        eewClock: () => sourceNow,
      );
      await tester.pump();
      final package = HistoryReplayPackage.fromGroup(
        EewEventGroup(
          eventId: reports.first.eventId,
          reports: reports,
          firstArrivedAt: sourceNow,
        ),
      );
      final notified = <UnifiedQuakeData>[];
      provider.onUnifiedEventNotified = (event, _) => notified.add(event);
      provider.historyReplay.load(package);
      provider.historyReplay.play();
      for (var i = 1; i < package.times.length; i++) {
        sourceNow = package.times[i];
        await tester.pump(package.times[i].difference(package.times[i - 1]));
      }
      expect(provider.historyReplay.played, 43);
      expect(notified, hasLength(43));
      for (var i = 0; i < package.reports.length; i++) {
        final original = package.reports[i];
        final played = notified[i];
        expect(played.source, original.source);
        expect(played.eventId, '${played.replaySessionId}:${original.eventId}');
        expect(played.reportNumText, original.reportNumText);
        expect(played.reportTime, original.reportTime);
        expect(played.originTime, original.originTime);
        expect(played.isCanceled, original.isCanceled);
        expect(played.sourcePayload, original.sourcePayload);
      }
      expect(provider.unifiedEvents.single.isCanceled, isTrue);
      expect(provider.unifiedEvents.single.reportNumText, '第37報');
      expect(
        provider.unifiedEvents.single.sourcePayload,
        cancellation.sourcePayload,
      );
      expect(provider.eewHistory, isEmpty);
      provider.historyReplay.stop();
      provider.dispose();
      await tester.pump();
    },
  );

  test('unknown stale cancellation and nonterminal inputs are rejected', () {
    final later = QuakeTime.unifiedInstantUtc(
      cancellation,
      value: cancellation.reportTime,
    ).add(const Duration(minutes: 1));
    expect(canAcceptEewCancellation(cancellation, now: later), isFalse);
    expect(canAcceptEewCancellation(report(42), now: later), isFalse);
    expect(isEewCancellationTransition(cancellation, report(42)), isFalse);
    expect(
      canAcceptEewCancellation(
        cancellation.copyWith(isHistory: true),
        now: QuakeTime.unifiedInstantUtc(
          cancellation,
          value: cancellation.reportTime,
        ),
      ),
      isFalse,
    );
  });
}
