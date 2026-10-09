import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/core/utils/information_report_order.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/models/unified_event_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final frame =
      jsonDecode(
            File(
              'test/fixtures/whews_early_est_documented_20261008.json',
            ).readAsStringSync(encoding: utf8),
          )
          as Map<String, dynamic>;
  final raw = Map<String, dynamic>.from(frame['Data'] as Map);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'report precedence uses counters without manufacturing source frames',
    () {
      final jian =
          jsonDecode(
                File(
                  'test/fixtures/jian/all.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map;
      final smaller = jian['source：early-est']['Data']['number'] as int;
      final larger = raw['updates'] as int;
      final earlierClock = DateTime.parse(raw['createTime'] as String);
      final laterClock = DateTime.parse(raw['shockTime'] as String);
      // Pure ordering inputs; these captures are different earthquakes. This
      // does not claim that they are two reports of the same real event.
      expect(smaller, lessThan(larger));
      expect(
        compareInformationReportOrder(
          currentNumber: larger,
          incomingNumber: smaller,
          currentTime: earlierClock,
          incomingTime: laterClock,
        ),
        -1,
      );
      expect(
        compareInformationReportOrder(
          currentNumber: smaller,
          incomingNumber: larger,
          currentTime: laterClock,
          incomingTime: earlierClock,
        ),
        1,
      );
      expect(
        compareInformationReportOrder(
          currentNumber: larger,
          incomingNumber: larger,
          currentTime: laterClock,
          incomingTime: earlierClock,
        ),
        -1,
      );
      expect(
        compareInformationReportOrder(
          currentNumber: larger,
          incomingNumber: larger,
          currentTime: earlierClock,
          incomingTime: earlierClock,
        ),
        0,
      );
      expect(
        compareInformationReportOrder(
          currentNumber: larger,
          incomingNumber: null,
          currentTime: earlierClock,
          incomingTime: laterClock,
        ),
        -1,
      );
      expect(
        compareInformationReportOrder(
          currentNumber: larger,
          incomingNumber: larger,
        ),
        isNull,
      );
      expect(informationReportNumber('第$larger報'), larger);
      expect(informationReportNumber('自动定位'), isNull);
    },
  );

  test('unchanged documented Early-est uses the existing information UI', () {
    final before = jsonEncode(raw);
    final event = QuakeEventAdapter.convertWhews('early_est', raw)!;
    expect(event.source, 'earlyEst');
    expect(event.isEew, isFalse);
    expect(event.isWarn, isFalse);
    expect(event.apiTypeLabel, 'WHEWS');
    expect(event.eventId, '1790292626641');
    expect(event.reportNumText, '第11報');
    expect(event.hasReportSequence, isTrue);
    expect(event.timeZone, 8);
    expect(event.originTime, DateTime(2026, 9, 25, 7, 30, 28));
    expect(event.reportTime, DateTime(2026, 1, 1, 12));
    expect(
      QuakeTime.unifiedInstantUtc(event),
      DateTime.utc(2026, 9, 24, 23, 30, 28),
    );
    expect(event.lat, -6.03);
    expect(event.lng, 147.4);
    expect(event.depth, 46);
    expect(event.magnitude, 5.1);
    expect(event.sourcePayload, raw);
    expect(jsonEncode(raw), before);
    final presentation = UnifiedEventPresentation.fromEvent(event);
    expect(presentation.title, 'INGV Early-est 快速定位地震信息 第11報');
    expect(presentation.secondaryText, contains('M5.1'));
    expect(presentation.apiTypeLabel, 'WHEWS');
    expect(event.hypocenter, matches(RegExp(r'[\u4e00-\u9fff]')));
  });

  test(
    'aggregate dispatch marks information snapshots and deduplicates',
    () async {
      final service = WhewsService(apiToken: 'test-only');
      addTearDown(service.dispose);
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);
      addTearDown(subscription.cancel);
      service.handleMessageForTesting([frame]);
      service.handleMessageForTesting(frame);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.source, 'earlyEst');
      expect(events.single.isEew, isFalse);
      expect(events.single.isSnapshot, isTrue);
      expect(events.single.sourcePayload, raw);
    },
  );

  test(
    'default unadapted-source blocking does not block Early-est history',
    () async {
      final provider = QuakeProvider();
      addTearDown(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.dispose();
      });
      final event = QuakeEventAdapter.convertWhews('early_est', raw)!;
      expect(
        provider.unifiedSourceTypeForTest(event),
        QuakeSourceType.earlyEst,
      );
      expect(provider.sourceInfoMagFilters[QuakeSourceType.unadapted], -1);
      provider.handleUnifiedEventForTest(event.copyWith(isSnapshot: true));
      expect(
        provider.unifiedEvents.where((e) => e.source == 'earlyEst'),
        isEmpty,
      );
      expect(provider.historyBySource['earlyEst'], isNotNull);
      expect(
        provider.historyBySource['earlyEst']!.single.eventId,
        event.eventId,
      );
    },
  );
}
