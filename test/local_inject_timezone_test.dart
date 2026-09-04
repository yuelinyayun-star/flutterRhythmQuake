import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/services/debug/local_inject_server.dart';

void main() {
  group('inject wall-clock timezone', () {
    test('JMA / KMA use UTC+9 like production', () {
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.wolfx), 9);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.jma_fan), 9);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.p2p), 9);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.kma_eew_fan), 9);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.kma_eq), 9);
    });

    test('CEA / CENC / USGS / CWA use UTC+8 like production', () {
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.cea), 8);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.cenc), 8);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.usgs), 8);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.cwa_eew), 8);
      expect(QuakeTime.wallClockOffsetHours(QuakeSourceType.sc_eew), 8);
    });

    test('freshOrigin rewrite uses source wall clock', () {
      final nowUtc = DateTime.utc(2026, 8, 11, 14, 0, 0);

      final jma = LocalInjectServer.rewriteInjectOriginTimes(
        jsonEncode({
          'type': 'jma_eew',
          'EventID': '1',
          'OriginTime': '2020-01-01 00:00:00',
          'AnnouncedTime': '2020-01-01 00:00:01',
        }),
        15,
        nowUtc: nowUtc,
      );
      expect(jma.wallClockOffsetHours, 9);
      final jmaJson = jsonDecode(jma.payload) as Map<String, dynamic>;
      // 14:00 UTC → 23:00 JST, minus 15s → 22:59:45
      expect(jmaJson['OriginTime'], '2026-08-11 22:59:45');

      final cea = LocalInjectServer.rewriteInjectOriginTimes(
        jsonEncode({
          'source': 'cea',
          'eventId': '2',
          'shockTime': '2020-01-01 00:00:00',
          'createTime': '2020-01-01 00:00:01',
        }),
        15,
        nowUtc: nowUtc,
      );
      expect(cea.wallClockOffsetHours, 8);
      final ceaJson = jsonDecode(cea.payload) as Map<String, dynamic>;
      // 14:00 UTC → 22:00 CST, minus 15s → 21:59:45
      expect(ceaJson['shockTime'], '2026-08-11 21:59:45');
    });

    test('infers fixture sources', () {
      expect(
        LocalInjectServer.inferInjectWallClockOffsetHours(
          jsonDecode('{"type":"jma_eew","OriginTime":"2026-01-01 00:00:00"}'),
        ),
        9,
      );
      expect(
        LocalInjectServer.inferInjectWallClockOffsetHours(
          jsonDecode('{"source":"cea","shockTime":"2026-01-01 00:00:00"}'),
        ),
        8,
      );
      expect(
        LocalInjectServer.inferInjectWallClockOffsetHours(
          jsonDecode('{"source":"usgs","shockTime":"2026-01-01 00:00:00"}'),
        ),
        8,
      );
    });
  });
}
