import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_trigger_continuity_gate.dart';

void main() {
  StationTriggerSnapshot station(String code, double lat, double lng) {
    return StationTriggerSnapshot(
      stationId: code,
      code: code,
      sourceId: 'nied',
      observedAt: DateTime(2026, 6, 21, 23, 41),
      state: StationTriggerState.triggered,
      latitude: lat,
      longitude: lng,
    );
  }

  StationTriggerSnapshot timedStation(
    String code,
    double lat,
    double lng,
    DateTime observedAt,
  ) {
    return StationTriggerSnapshot(
      stationId: code,
      code: code,
      sourceId: 'nied',
      observedAt: observedAt,
      state: StationTriggerState.triggered,
      latitude: lat,
      longitude: lng,
      firstTriggerInterval: ObservationTimeInterval(
        start: observedAt,
        end: observedAt,
      ),
    );
  }

  EventDetection detection({
    required String eventId,
    required List<String> members,
    EventDetectionState state = EventDetectionState.confirmed,
    DateTime? observedAt,
  }) {
    return EventDetection(
      detectorId: 'source',
      sourceId: 'nied',
      eventId: eventId,
      state: state,
      observedAt: observedAt ?? DateTime(2026, 6, 21, 23, 41),
      memberStationIds: members,
      detectionScore: members.length.toDouble(),
    );
  }

  test('holds far replacement event inside retention window', () {
    final gate = SourceTriggerContinuityGate(
      config: const SourceTriggerContinuityConfig(
        maxReplacementCentroidDistanceKm: 180,
      ),
    );
    final firstStations = [
      station('A', 38.4, 141.0),
      station('B', 38.5, 141.1),
      station('C', 38.3, 141.2),
    ];
    final secondStations = [
      station('X', 35.7, 139.4),
      station('Y', 35.8, 139.5),
      station('Z', 35.9, 139.6),
    ];

    final first = gate.update(
      detection: detection(eventId: 'event-a', members: const ['A', 'B', 'C']),
      stations: firstStations,
      observedAt: DateTime(2026, 6, 21, 23, 41),
      activeEstimate: const SourceEstimate(
        latitude: 38.4,
        longitude: 141.1,
        confidence: 0.7,
        method: 'test',
        supportingStationCount: 3,
      ),
    );
    expect(first.effectiveEventId, 'event-a');
    expect(first.effectiveMemberStationIds, ['A', 'B', 'C']);

    final held = gate.update(
      detection: detection(
        eventId: 'event-b',
        members: const ['X', 'Y', 'Z'],
        observedAt: DateTime(2026, 6, 21, 23, 42),
      ),
      stations: secondStations,
      observedAt: DateTime(2026, 6, 21, 23, 42),
      activeEstimate: const SourceEstimate(
        latitude: 38.4,
        longitude: 141.1,
        confidence: 0.7,
        method: 'test',
        supportingStationCount: 3,
      ),
    );

    expect(held.heldReplacement, isTrue);
    expect(held.effectiveEventId, 'event-a');
    expect(held.effectiveMemberStationIds, ['A', 'B', 'C']);
    expect(held.metadata['source_trigger_continuity_raw_event_id'], 'event-b');
  });

  test('keeps ended event anchor through retention window', () {
    final gate = SourceTriggerContinuityGate(
      config: const SourceTriggerContinuityConfig(
        retentionWindow: Duration(seconds: 120),
        maxReplacementCentroidDistanceKm: 180,
      ),
    );
    final firstStations = [
      station('A', 38.4, 141.0),
      station('B', 38.5, 141.1),
      station('C', 38.3, 141.2),
    ];
    final secondStations = [
      station('X', 35.7, 139.4),
      station('Y', 35.8, 139.5),
      station('Z', 35.9, 139.6),
    ];
    gate.update(
      detection: detection(eventId: 'event-a', members: const ['A', 'B', 'C']),
      stations: firstStations,
      observedAt: DateTime(2026, 6, 21, 23, 41, 50),
    );

    final ended = gate.update(
      detection: detection(
        eventId: 'event-a',
        members: const ['A', 'B', 'C'],
        state: EventDetectionState.ended,
        observedAt: DateTime(2026, 6, 21, 23, 42, 22),
      ),
      stations: firstStations,
      observedAt: DateTime(2026, 6, 21, 23, 42, 22),
    );
    expect(ended.effectiveEventId, 'event-a');
    expect(ended.effectiveMemberStationIds, ['A', 'B', 'C']);

    final held = gate.update(
      detection: detection(
        eventId: 'event-b',
        members: const ['X', 'Y', 'Z'],
        observedAt: DateTime(2026, 6, 21, 23, 42, 49),
      ),
      stations: secondStations,
      observedAt: DateTime(2026, 6, 21, 23, 42, 49),
    );

    expect(held.heldReplacement, isTrue);
    expect(held.effectiveEventId, 'event-a');
    expect(held.effectiveMemberStationIds, ['A', 'B', 'C']);
  });

  test('accepts nearby replacement event', () {
    final gate = SourceTriggerContinuityGate();
    final stations = [
      station('A', 38.4, 141.0),
      station('B', 38.5, 141.1),
      station('C', 38.3, 141.2),
      station('D', 38.45, 141.08),
    ];
    gate.update(
      detection: detection(eventId: 'event-a', members: const ['A', 'B', 'C']),
      stations: stations,
      observedAt: DateTime(2026, 6, 21, 23, 41),
    );

    final accepted = gate.update(
      detection: detection(eventId: 'event-b', members: const ['B', 'C', 'D']),
      stations: stations,
      observedAt: DateTime(2026, 6, 21, 23, 42),
    );

    expect(accepted.heldReplacement, isFalse);
    expect(accepted.effectiveEventId, 'event-b');
    expect(accepted.effectiveMemberStationIds, ['B', 'C', 'D']);
  });

  test('holds mid-distance replacement without member overlap', () {
    final gate = SourceTriggerContinuityGate(
      config: const SourceTriggerContinuityConfig(
        maxNearbyReplacementCentroidDistanceKm: 60,
        maxReplacementCentroidDistanceKm: 180,
        minReplacementMemberOverlap: 2,
      ),
    );
    final firstStations = [
      station('A', 37.1, 139.4),
      station('B', 37.2, 139.4),
      station('C', 37.1, 139.5),
      station('D', 37.2, 139.5),
    ];
    final secondStations = [
      station('X', 36.2, 139.8),
      station('Y', 36.3, 139.8),
      station('Z', 36.2, 139.9),
      station('W', 36.3, 139.9),
    ];

    gate.update(
      detection: detection(
        eventId: 'event-a',
        members: const ['A', 'B', 'C', 'D'],
      ),
      stations: firstStations,
      observedAt: DateTime(2026, 6, 24, 13, 24, 54),
      activeEstimate: const SourceEstimate(
        latitude: 37.1,
        longitude: 139.4,
        confidence: 0.8,
        method: 'test',
        supportingStationCount: 4,
      ),
    );

    final held = gate.update(
      detection: detection(
        eventId: 'event-b',
        members: const ['X', 'Y', 'Z', 'W'],
        observedAt: DateTime(2026, 6, 24, 13, 26, 20),
      ),
      stations: secondStations,
      observedAt: DateTime(2026, 6, 24, 13, 26, 20),
      activeEstimate: const SourceEstimate(
        latitude: 37.1,
        longitude: 139.4,
        confidence: 0.8,
        method: 'test',
        supportingStationCount: 4,
      ),
    );

    expect(held.heldReplacement, isTrue);
    expect(held.effectiveEventId, 'event-a');
    expect(held.effectiveMemberStationIds, ['A', 'B', 'C', 'D']);
    expect(
      held.metadata['source_trigger_continuity_replacement_member_overlap'],
      0,
    );
  });

  test('filters same-event members that do not fit current source cache', () {
    final start = DateTime(2026, 6, 24, 13, 24, 54);
    final gate = SourceTriggerContinuityGate(
      config: const SourceTriggerContinuityConfig(
        maxNearbyReplacementCentroidDistanceKm: 1000,
        maxReplacementCentroidDistanceKm: 1000,
        maxDetectionIdAssignmentNeighborDistanceKm: 20,
        maxDetectionIdAssignmentResidualSeconds: 3,
      ),
    );
    final firstStations = [
      timedStation('A', 37.10, 139.40, start),
      timedStation('B', 37.12, 139.42, start),
      timedStation('C', 37.08, 139.38, start),
    ];
    gate.update(
      detection: detection(
        eventId: 'event-a',
        members: const ['A', 'B', 'C'],
        observedAt: start,
      ),
      stations: firstStations,
      observedAt: start,
    );

    final currentStations = [
      timedStation('A', 37.10, 139.40, start.add(const Duration(seconds: 1))),
      timedStation('X', 39.00, 142.00, start.add(const Duration(seconds: 1))),
    ];
    final filtered = gate.update(
      detection: detection(
        eventId: 'event-a',
        members: const ['A', 'X'],
        observedAt: start.add(const Duration(seconds: 1)),
      ),
      stations: currentStations,
      observedAt: start.add(const Duration(seconds: 1)),
      activeEstimate: SourceEstimate(
        latitude: 37.10,
        longitude: 139.40,
        depthKm: 10,
        originTime: start,
        confidence: 0.8,
        method: 'test',
        supportingStationCount: 3,
      ),
    );

    expect(filtered.heldReplacement, isFalse);
    expect(filtered.currentMemberStationIds, ['A']);
    expect(filtered.effectiveMemberStationIds, ['A', 'B', 'C']);
    expect(
      filtered.metadata['source_trigger_detection_id_assignment_model'],
      'kotoho7_detection_id_assignment_proxy_source_cache_phase_or_neighbor_v1',
    );
    expect(
      filtered.metadata['source_trigger_detection_id_rejected_station_ids'],
      ['X'],
    );
  });
}
