import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/replay_event_name.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';

void main() {
  final package = HistoryReplayPackage.decode(
    File(
      'test/fixtures/history_replay/cwa_1150074.rqreplay',
    ).readAsStringSync(),
  );

  test('saved name identifies latest recorded event without changing data', () {
    final event = package.reports.last;
    final original = event.toMap();
    expect(
      replayEventName(event),
      startsWith('2026-09-29_02-20-47_UTC+8_花蓮縣近海_M5.0_cwaEew_1150074_'),
    );
    expect(event.toMap(), original);
    expect(replayEventName(event), replayEventName(event));
  });

  test('name uses the earthquake instant in UTC+8 across source zones', () {
    final event = package.reports.last;
    expect(
      replayEventName(
        event.copyWith(
          originTime: event.originTime!.add(const Duration(hours: 1)),
          timeZone: 9,
        ),
      ),
      replayEventName(event),
    );
  });

  test(
    'filename encoding preserves Chinese and Japanese and bounds length',
    () {
      expect(replayNameComponent('台湾東方沖'), '台湾東方沖');
      expect(replayNameComponent('a<>:"/\\|?*\n. '), 'a__________');
      expect(replayNameComponent('CON.txt'), '_CON.txt');
      expect(replayNameComponent('COM¹'), '_COM¹');
      expect(replayNameComponent('😀😀', maxLength: 3), '😀');
      final event = package.reports.last;
      final left = replayEventName(event.copyWith(eventId: '${'長' * 100}/a'));
      final right = replayEventName(event.copyWith(eventId: '${'長' * 100}/b'));
      expect(left, isNot(right));
      expect(left.length, lessThan(160));
      expect(left, isNot(matches(RegExp(r'[<>:"/\\|?*\x00-\x1f]'))));
      final longest = replayEventName(
        event.copyWith(
          hypocenter: '地' * 60,
          source: '源' * 40,
          eventId: '号' * 60,
        ),
      );
      expect(
        utf8.encode('${longest}_${'f' * 64}.rqreplay').length,
        lessThanOrEqualTo(255),
      );
    },
  );

  test('unknown origin and magnitude do not acquire invented values', () {
    final name = replayEventName(UnifiedQuakeData.empty);
    expect(name, isNot(contains('1970')));
    expect(name, isNot(contains('M-1')));
    expect(name, isNot(contains('UTC+8')));
  });
}
