import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';

void main() {
  test(
    'four station frame clocks survive the JSON isolate boundary unchanged',
    () {
      for (final time in [
        DateTime.utc(2026, 9, 7, 12, 34, 56, 789),
        DateTime(2026, 9, 7, 21, 34, 56),
      ]) {
        final payloads = [
          ForegroundStationPayload.kma([], dataTime: time),
          ForegroundStationPayload.cwa([], dataTime: time),
          ForegroundStationPayload.seisjs([], dataTime: time),
          ForegroundStationPayload.palert(
            [],
            dataTime: time,
            receivedTime: time.add(const Duration(seconds: 2)),
          ),
        ];
        for (final payload in payloads) {
          final decoded =
              jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
          final actual = ForegroundStationPayload.frameTime(decoded);
          expect(actual, time);
          expect(actual!.isUtc, time.isUtc);
        }
        expect(
          DateTime.parse(payloads.last['receivedTime'] as String),
          time.add(const Duration(seconds: 2)),
        );
      }
    },
  );
  test(
    'unknown frame time stays unknown without receipt-time substitution',
    () {
      for (final payload in [
        ForegroundStationPayload.kma([]),
        ForegroundStationPayload.cwa([]),
        ForegroundStationPayload.seisjs([]),
        ForegroundStationPayload.palert([]),
      ]) {
        expect(ForegroundStationPayload.frameTime(payload), isNull);
      }
    },
  );
}
