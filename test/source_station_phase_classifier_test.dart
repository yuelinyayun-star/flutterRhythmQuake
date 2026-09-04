import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_station_phase_classifier.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('classifies station phases from kotoho7 JS phase stations', () {
    final origin = DateTime.utc(2026, 6, 20, 12);
    final event = SeismicActiveEvent(
      eventId: 'test-event',
      sourceId: 'nied',
      startedAt: origin,
      updatedAt: origin.add(const Duration(seconds: 40)),
      stageName: 'confirmed',
      maxShindo: 2,
      estimate: SourceEstimate(
        latitude: 0,
        longitude: 0,
        depthKm: 0,
        originTime: origin,
        confidence: 0.8,
        method: 'test',
        supportingStationCount: 3,
        diagnostics: {
          'best_source_phase_stations': [
            {'code': 'p', 'phase': 'p', 'lat': 0.1, 'lng': 140.1},
            {'code': 's', 'phase': 's', 'lat': 0.2, 'lng': 140.2},
            {'code': 'o', 'phase': 'other', 'lat': 0.3, 'lng': 140.3},
          ],
        },
      ),
      metadata: {
        'source_trigger_member_ids': ['p', 's', 'o'],
      },
    );
    final result = const SourceStationPhaseClassifier().classify(event);

    expect(result.stations, hasLength(3));
    expect(result.count(EstimatedStationPhase.p), 1);
    expect(result.count(EstimatedStationPhase.s), 1);
    expect(result.count(EstimatedStationPhase.other), 1);
    expect(result.stations.map((item) => item.station), everyElement(isNull));
    expect(result.stations.first.coordinate.latitude, 0.1);
  });

  test('falls back to station coordinate when kotoho7 JS lat/lng are zero', () {
    final origin = DateTime.utc(2026, 6, 20, 12);
    final event = SeismicActiveEvent(
      eventId: 'test-event',
      sourceId: 'nied',
      startedAt: origin,
      updatedAt: origin.add(const Duration(seconds: 40)),
      stageName: 'confirmed',
      maxShindo: 2,
      estimate: SourceEstimate(
        latitude: 35.5,
        longitude: 139.5,
        depthKm: 10,
        originTime: origin,
        confidence: 0.8,
        method: 'test',
        supportingStationCount: 1,
        diagnostics: {
          'best_source_phase_stations': [
            {'code': 'p', 'phase': 'p', 'lat': 0, 'lng': 0},
          ],
        },
      ),
      metadata: const {},
    );
    event.stationRecords.addAll({
      'p': _record(
        'p',
        origin.add(const Duration(seconds: 10)),
        coordinate: const LatLng(35.6, 139.6),
      ),
    });

    final result = const SourceStationPhaseClassifier().classify(event);

    expect(result.stations, hasLength(1));
    expect(result.stations.first.coordinate, const LatLng(35.6, 139.6));
  });

  test('does not fall back to local Flutter phase inference', () {
    final origin = DateTime.utc(2026, 6, 20, 12);
    final event = SeismicActiveEvent(
      eventId: 'test-event',
      sourceId: 'nied',
      startedAt: origin,
      updatedAt: origin.add(const Duration(seconds: 40)),
      stageName: 'confirmed',
      maxShindo: 2,
      estimate: SourceEstimate(
        latitude: 0,
        longitude: 0,
        depthKm: 0,
        originTime: origin,
        confidence: 0.8,
        method: 'test',
        supportingStationCount: 3,
      ),
      metadata: {
        'source_trigger_member_ids': ['p', 's', 'o'],
      },
    );
    event.stationRecords.addAll({
      'p': _record('p', origin.add(const Duration(seconds: 10))),
      's': _record('s', origin.add(const Duration(seconds: 17))),
      'o': _record('o', origin.add(const Duration(seconds: 40))),
    });

    final result = const SourceStationPhaseClassifier().classify(event);

    expect(result.stations, isEmpty);
  });
}

SeismicStationEventRecord _record(
  String code,
  DateTime triggerTime, {
  LatLng coordinate = const LatLng(0, 0.54),
}) {
  return SeismicStationEventRecord(
    descriptor: SeismicStationDescriptor(
      stationId: code,
      code: code,
      sourceId: 'nied',
      network: 'test',
      coordinate: coordinate,
    ),
    firstObservedAt: triggerTime,
    firstRiseAt: triggerTime,
    firstTriggerAt: triggerTime,
    state: StationLifecycleState.triggered,
  );
}
