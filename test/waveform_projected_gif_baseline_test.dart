import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/waveform_projected_gif_baseline.dart';

void main() {
  test('weighted station field locates an event and survives masking', () {
    final event = _event('event-a', 35, 140);
    const config = ProjectedGifBaselineConfig(
      minimumIntensity: 0,
      intensityWeightExponent: 0.5,
    );
    const baseline = ProjectedGifSpatialBaseline();
    final full = baseline.evaluate(event, config);
    final masked = baseline.evaluate(event, config, dropRate: 0.2, maskSeed: 1);

    expect(full.eligibleFrameCount, 2);
    expect(full.firstEstimateDelaySeconds, 1);
    expect(full.medianErrorKm, lessThan(10));
    expect(full.quantizationMae, greaterThanOrEqualTo(0));
    expect(
      masked.eligibleFrameCount,
      lessThanOrEqualTo(full.eligibleFrameCount),
    );
  });

  test('trainer keeps complete events in leave-one-event-out folds', () {
    final events = [_event('event-a', 35, 140), _event('event-b', 36, 141)];
    const trainer = ProjectedGifBaselineTrainer(
      minimumIntensityGrid: [0],
      weightExponentGrid: [0.5],
      dropRates: [0],
    );
    final folds = trainer.leaveOneEventOut(events);

    expect(folds, hasLength(2));
    expect(
      folds.map((fold) => fold.heldOutEventId),
      containsAll(['event-a', 'event-b']),
    );
    expect(folds.every((fold) => fold.evaluations.length == 1), isTrue);
  });

  test('arrival-weighted running peaks reduce late wavefield drift', () {
    final event = _driftingEvent();
    const spatial = ProjectedGifBaselineConfig(
      minimumIntensity: 1,
      intensityWeightExponent: 0.5,
    );
    const temporal = ProjectedGifBaselineConfig(
      minimumIntensity: 1,
      intensityWeightExponent: 0.5,
      useRunningPeak: true,
      arrivalDecaySeconds: 0.2,
    );
    const baseline = ProjectedGifSpatialBaseline();

    final spatialResult = baseline.evaluate(event, spatial);
    final temporalResult = baseline.evaluate(event, temporal);

    expect(temporalResult.eligibleFrameCount, 2);
    expect(
      temporalResult.medianErrorKm,
      lessThan(spatialResult.medianErrorKm!),
    );
  });
}

ProjectedGifFieldEvent _event(String id, double latitude, double longitude) {
  final origin = DateTime.utc(2026, 6, 21);
  final stations = <String, ProjectedGifStation>{};
  final points = <ProjectedGifPoint>[];
  for (var index = 0; index < 6; index++) {
    final key = 'S$index:surface';
    stations[key] = ProjectedGifStation(
      key: key,
      sensorRole: 'surface',
      latitude: latitude + (index - 2.5) * 0.02,
      longitude: longitude + (index - 2.5) * 0.02,
    );
    for (var second = 1; second <= 2; second++) {
      points.add(
        ProjectedGifPoint(
          stationKey: key,
          observedAtUtc: origin.add(Duration(seconds: second)),
          intensity: 2.0 - index * 0.05,
          projectedLevel: 13,
        ),
      );
    }
  }
  return ProjectedGifFieldEvent(
    eventId: id,
    originTimeUtc: origin,
    latitude: latitude,
    longitude: longitude,
    stations: stations,
    points: points,
  );
}

ProjectedGifFieldEvent _driftingEvent() {
  final origin = DateTime.utc(2026, 6, 21);
  final stations = <String, ProjectedGifStation>{};
  final points = <ProjectedGifPoint>[];
  for (var index = 0; index < 4; index++) {
    final nearKey = 'N$index:surface';
    final farKey = 'F$index:surface';
    stations[nearKey] = ProjectedGifStation(
      key: nearKey,
      sensorRole: 'surface',
      latitude: 35 + index * 0.01,
      longitude: 140 + index * 0.01,
    );
    stations[farKey] = ProjectedGifStation(
      key: farKey,
      sensorRole: 'surface',
      latitude: 37 + index * 0.01,
      longitude: 142 + index * 0.01,
    );
    points.add(
      ProjectedGifPoint(
        stationKey: nearKey,
        observedAtUtc: origin.add(const Duration(seconds: 1)),
        intensity: 2,
        projectedLevel: 13,
      ),
    );
    points.addAll([
      ProjectedGifPoint(
        stationKey: nearKey,
        observedAtUtc: origin.add(const Duration(seconds: 2)),
        intensity: 0,
        projectedLevel: 8,
      ),
      ProjectedGifPoint(
        stationKey: farKey,
        observedAtUtc: origin.add(const Duration(seconds: 2)),
        intensity: 3,
        projectedLevel: 16,
      ),
    ]);
  }
  return ProjectedGifFieldEvent(
    eventId: 'drifting-event',
    originTimeUtc: origin,
    latitude: 35,
    longitude: 140,
    stations: stations,
    points: points,
  );
}
