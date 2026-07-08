import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/event_detection/robust_station_trigger_detector.dart';

void main() {
  StationObservationFrame observation(DateTime time, int? level) {
    return StationObservationFrame(
      stationId: 'STA001',
      code: 'STA001',
      sourceId: 'test',
      observedAt: time,
      intensity: level == null ? null : (level - 7) / 2.0,
      rawLevel: level,
      detectLevel: level,
    );
  }

  test('detects sustained station rise without an external active flag', () {
    final detector = RobustStationTriggerDetector();
    final t0 = DateTime(2026, 6, 20, 12);

    StationTriggerSnapshot? snapshot;
    for (var second = 0; second < 5; second++) {
      snapshot = detector.update(
        observation(t0.add(Duration(seconds: second)), 5),
      );
      expect(snapshot.state, StationTriggerState.idle);
    }

    snapshot = detector.update(
      observation(t0.add(const Duration(seconds: 5)), 7),
    );
    expect(snapshot.state, StationTriggerState.idle);

    snapshot = detector.update(
      observation(t0.add(const Duration(seconds: 6)), 7),
    );
    expect(snapshot.state, StationTriggerState.rising);
    expect(
      snapshot.firstRiseInterval?.start,
      t0.add(const Duration(seconds: 5)),
    );
    expect(snapshot.firstRiseInterval?.end, t0.add(const Duration(seconds: 6)));

    for (var second = 7; second <= 9; second++) {
      snapshot = detector.update(
        observation(t0.add(Duration(seconds: second)), 8),
      );
    }
    expect(snapshot!.state, StationTriggerState.triggered);
    expect(snapshot.firstTriggerInterval, isNotNull);
    expect(snapshot.activity, greaterThanOrEqualTo(2));
  });

  test('emits strong, decaying, and ended station states', () {
    final detector = RobustStationTriggerDetector();
    final t0 = DateTime(2026, 6, 20, 12);

    for (var second = 0; second < 5; second++) {
      detector.update(observation(t0.add(Duration(seconds: second)), 5));
    }

    StationTriggerSnapshot? snapshot;
    for (var second = 5; second <= 7; second++) {
      snapshot = detector.update(
        observation(t0.add(Duration(seconds: second)), 14),
      );
    }
    expect(snapshot!.state, StationTriggerState.strong);

    snapshot = detector.update(
      observation(t0.add(const Duration(seconds: 8)), 5),
    );
    expect(snapshot.state, StationTriggerState.decaying);
    detector.update(observation(t0.add(const Duration(seconds: 9)), 5));
    snapshot = detector.update(
      observation(t0.add(const Duration(seconds: 10)), 5),
    );
    expect(snapshot.state, StationTriggerState.ended);

    snapshot = detector.update(
      observation(t0.add(const Duration(seconds: 11)), 5),
    );
    expect(snapshot.state, StationTriggerState.idle);
  });

  test('missing observations end an active station trigger', () {
    final detector = RobustStationTriggerDetector();
    final t0 = DateTime(2026, 6, 20, 12);

    for (var second = 0; second < 5; second++) {
      detector.update(observation(t0.add(Duration(seconds: second)), 5));
    }
    for (var second = 5; second <= 7; second++) {
      detector.update(observation(t0.add(Duration(seconds: second)), 8));
    }

    detector.update(observation(t0.add(const Duration(seconds: 8)), null));
    detector.update(observation(t0.add(const Duration(seconds: 9)), null));
    final ended = detector.update(
      observation(t0.add(const Duration(seconds: 10)), null),
    );

    expect(ended.state, StationTriggerState.ended);
    expect(ended.reasonCodes, contains('missing_observation_end'));
  });
}
