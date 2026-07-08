import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';

void main() {
  test('retains a chronological 60-second observation window', () {
    final history = StationObservationHistory();
    final start = DateTime.utc(2026, 6, 21);
    for (var second = 0; second <= 61; second++) {
      history.add(_frame(start.add(Duration(seconds: second))));
    }

    expect(history.length, 61);
    expect(
      history.frames.first.dataTime,
      start.add(const Duration(seconds: 1)),
    );
    expect(history.latest?.dataTime, start.add(const Duration(seconds: 61)));
  });

  test('rejects out-of-order observations', () {
    final history = StationObservationHistory();
    final now = DateTime.utc(2026, 6, 21);
    history.add(_frame(now));

    expect(
      () => history.add(_frame(now.subtract(const Duration(seconds: 1)))),
      throwsArgumentError,
    );
  });
}

SeismicStationObservationFrame _frame(DateTime time) =>
    SeismicStationObservationFrame(
      dataTime: time,
      receivedAt: time.add(const Duration(milliseconds: 100)),
      value: 1,
      rawLevel: 10,
      detectLevel: 10,
      isTriggered: true,
      qualityFlags: const {},
    );
