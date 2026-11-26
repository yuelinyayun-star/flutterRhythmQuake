import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/domestic_eew_effects.dart';
import 'package:flutterrhythmquake/services/native_unified_event_owner.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

UnifiedQuakeData _savedReport(String name, String digest) {
  final bytes = File(
    'test/fixtures/delingha_20261121/$name.original.json',
  ).readAsBytesSync();
  expect(sha256.convert(bytes).toString(), digest);
  return UnifiedQuakeData.fromMap(
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UnifiedQuakeData wolfx;
  late UnifiedQuakeData jian;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().enabled = false;
    wolfx = _savedReport(
      'wolfx-report-1',
      'f8687dd5afd303b4035c5e8cb1acc86574b4f999f24a618a04a1a0e3279ed427',
    );
    jian = _savedReport(
      'jian-report-2',
      'd0b3785e41fb7574dc2817e9e620cb4664b12075ee8b9129811d9eed3dac80a1',
    );
  });
  tearDown(() {
    SoundEffectService().enabled = true;
    TtsService().enabled = true;
  });

  test('Delingha continuation keeps fill and threshold sound ownership', () {
    final effects = DomesticEewEffects()..observe(wolfx);
    expect(effects.claimThresholdSound(wolfx, warn: true), isTrue);
    effects.observe(jian);
    effects.retainActive([jian]);
    expect(effects.shouldDrawFill(jian), isTrue);
    expect(effects.claimThresholdSound(jian, warn: true), isFalse);
  });

  test(
    'Windows worker publishes one active Delingha event',
    () async {
      final published = Completer<(List<int>, UnifiedQuakeData)>();
      final owner = NativeUnifiedEventOwner(
        manualClock: false,
        onBatch: (batch, pool) {
          final active = (batch['active'] as List).cast<int>();
          if (!published.isCompleted &&
              active.any((token) => pool[token]?.reportNumText == '第2報')) {
            published.complete((
              List.of(active),
              pool[active.firstWhere(
                (token) => pool[token]?.reportNumText == '第2報',
              )]!,
            ));
          }
        },
      );
      try {
        owner.send({'op': 'ready'});
        final local = jian.arrivedAt!;
        final context = <String, dynamic>{
          'nowUs': local.microsecondsSinceEpoch,
          'nowIso': local.toIso8601String(),
          'sourceNowUs': local.microsecondsSinceEpoch,
          'eewNowUs': local.microsecondsSinceEpoch,
          'localOffsetMinutes': local.timeZoneOffset.inMinutes,
          'historyLoaded': true,
          'historyKeepForever': true,
        };
        owner.admit(wolfx, context, suppressEffects: true);
        owner.admit(jian, context, suppressEffects: true);
        final (active, latest) = await published.future.timeout(
          const Duration(seconds: 5),
        );
        expect(active, hasLength(1));
        expect(latest.sourcePayload, jian.sourcePayload);
        expect(owner.query('sameEew', event: jian, previous: wolfx), isTrue);
      } finally {
        owner.dispose();
      }
    },
    skip: !NativeUnifiedEventOwner.supported,
  );

  for (final native in [false, if (NativeUnifiedEventOwner.supported) true]) {
    for (final reverse in [false, true]) {
      test('Delingha live admission native=$native reverse=$reverse', () async {
        final first = QuakeEventAdapter.convert(
          'ceaEew',
          wolfx.sourcePayload!,
          wolfx.origin,
        )!;
        final second = QuakeEventAdapter.convertJian(
          'cea',
          jian.sourcePayload!,
        )!;
        final moment = jian.arrivedAt!.toUtc();
        final provider = QuakeProvider(
          startCatalogServices: false,
          nativeUnifiedEvents: native,
          eewClock: () => moment,
        );
        try {
          await provider.eewHistoryReadyForTest;
          expect(second.eventId, jian.sourcePayload!['id']);
          expect(second.reportNumText, '第2報');
          expect(
            provider.unifiedEventKeyForTest(first),
            provider.unifiedEventKeyForTest(second),
          );
          final reports = reverse ? [second, first] : [first, second];
          final background = BackgroundEventProcessor(
            sourceInfoMagFilters: {},
            eewClock: () => moment,
          );
          final notifications = <bool>[];
          provider.onUnifiedEventNotified = (_, update) {
            notifications.add(update);
          };
          for (final report in reports) {
            provider.handleUnifiedEventForTest(report);
          }
          expect(provider.unifiedEvents.single.reportNumText, '第2報');
          final history = provider.eewHistory.single.reports;
          expect(history.map((report) => report.reportNumText), [
            '第2報',
            if (!reverse) '第1報',
          ]);
          expect(history.first.sourcePayload, jian.sourcePayload);
          if (!reverse) {
            expect(history.last.sourcePayload, wolfx.sourcePayload);
          }
          expect(
            background.process(reports.first).type,
            BackgroundEventResultType.newEvent,
          );
          expect(
            background.process(reports.last).type,
            reverse
                ? BackgroundEventResultType.dropped
                : BackgroundEventResultType.update,
          );
          expect(background.acceptedEewReportNums.values.single, 2);
          expect(notifications.where((update) => !update), hasLength(1));
        } finally {
          provider.dispose();
        }
      });
    }

    test('Delingha linked saved replay native=$native', () async {
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: native,
        eewClock: () => clock.now(),
      );
      try {
        await provider.eewHistoryReadyForTest;
        fakeAsync((async) {
          EewEventGroup savedGroup(UnifiedQuakeData report) => EewEventGroup(
            eventId: report.eventId,
            reports: [report],
            firstArrivedAt: report.arrivedAt!,
          );
          final firstGroup = savedGroup(wolfx);
          final secondGroup = savedGroup(jian);
          final firstPackage = HistoryReplayPackage.fromGroup(firstGroup);
          final secondPackage = HistoryReplayPackage.fromGroup(secondGroup);
          final jianDelay = secondPackage.times.first.difference(
            firstPackage.times.first,
          );
          final jianExpiry = jianDelay + secondPackage.playbackDuration;
          expect(jianExpiry, greaterThan(firstPackage.playbackDuration));
          final replay = provider.historyReplay
            ..importPackages([firstPackage, secondPackage])
            ..restoreTimelineLinked(true)
            ..play();
          try {
            expect(replay.totalReports, 2);
            expect(provider.unifiedEvents.single.reportNumText, '第1報');
            async.elapse(jianDelay);
            expect(provider.unifiedEvents.single.reportNumText, '第2報');
            expect(
              provider.unifiedEvents.single.sourcePayload,
              jian.sourcePayload,
            );
            async.elapse(firstPackage.playbackDuration - jianDelay);
            expect(provider.unifiedEvents.single.reportNumText, '第2報');
            async.elapse(jianExpiry - firstPackage.playbackDuration);
            expect(provider.unifiedEvents, isEmpty);
          } finally {
            replay.stop();
          }
        });
      } finally {
        provider.dispose();
      }
    });
  }
}
