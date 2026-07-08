import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/event_detection/spatiotemporal_event_detector.dart';

void main() {
  StationTriggerSnapshot station(
    int id,
    DateTime observedAt, {
    double latitude = 35,
    double longitude = 135,
    StationTriggerState state = StationTriggerState.triggered,
    DateTime? firstTriggeredAt,
    Set<String> qualityFlags = const {},
  }) {
    return StationTriggerSnapshot(
      stationId: 'STA$id',
      code: 'STA$id',
      sourceId: 'test',
      observedAt: observedAt,
      state: state,
      latitude: latitude + id * 0.02,
      longitude: longitude + id * 0.02,
      intensity: 0.5,
      detectLevel: 8,
      firstTriggerInterval: firstTriggeredAt == null
          ? null
          : ObservationTimeInterval(
              start: firstTriggeredAt.subtract(const Duration(seconds: 1)),
              end: firstTriggeredAt,
            ),
      qualityFlags: qualityFlags,
    );
  }

  test('confirms a spatially connected multi-station cluster', () {
    final detector = SpatiotemporalEventDetector();
    final t0 = DateTime(2026, 6, 20, 12);

    final candidate = detector.update(
      observedAt: t0,
      stations: [for (var id = 0; id < 4; id++) station(id, t0)],
    );
    expect(candidate.state, EventDetectionState.candidate);
    expect(candidate.memberStationIds, hasLength(4));
    expect(candidate.eventId, isNotNull);

    final confirmed = detector.update(
      observedAt: t0.add(const Duration(seconds: 1)),
      stations: [
        for (var id = 0; id < 6; id++)
          station(id, t0.add(const Duration(seconds: 1))),
      ],
    );
    expect(confirmed.state, EventDetectionState.confirmed);
    expect(confirmed.memberStationIds, hasLength(6));
    expect(confirmed.eventId, candidate.eventId);
  });

  test('does not combine distant station groups', () {
    final detector = SpatiotemporalEventDetector();
    final t0 = DateTime(2026, 6, 20, 12);
    final stations = [
      station(0, t0),
      station(1, t0),
      station(2, t0),
      station(10, t0, latitude: 42, longitude: 142),
      station(11, t0, latitude: 42, longitude: 142),
      station(12, t0, latitude: 42, longitude: 142),
    ];

    final detection = detector.update(observedAt: t0, stations: stations);
    expect(detection.state, EventDetectionState.idle);
    expect(detection.metadata['network_support_count'], 3);
    expect(detection.metadata['triggeredStationCount'], 6);
    expect(detection.metadata['componentCount'], 2);
    expect(detection.metadata['componentSizes'], [3, 3]);
  });

  test('reports component diameter, trigger span, and quality weight', () {
    final detector = SpatiotemporalEventDetector(
      config: const SpatiotemporalEventDetectorConfig(
        candidateMinStations: 2,
        confirmedMinStations: 4,
        maxLinkDistanceKm: 200,
      ),
    );
    final t0 = DateTime(2026, 6, 20, 12);
    final diagnostics = detector.diagnose([
      station(0, t0, firstTriggeredAt: t0),
      station(
        1,
        t0,
        firstTriggeredAt: t0.add(const Duration(seconds: 3)),
        qualityFlags: const {'scan_unreliable'},
      ),
      station(2, t0, firstTriggeredAt: t0.add(const Duration(seconds: 7))),
    ]);

    expect(diagnostics.triggeredStationCount, 3);
    expect(diagnostics.componentCount, 1);
    expect(diagnostics.componentSizes, [3]);
    expect(diagnostics.largestComponentSize, 3);
    expect(diagnostics.largestComponentDiameterKm, greaterThan(5));
    expect(diagnostics.largestComponentQualityWeightedSupport, 2.5);
    expect(diagnostics.largestComponentTriggerTimeSpanSeconds, 7);
    expect(diagnostics.largestComponentStationIds, ['STA0', 'STA1', 'STA2']);
    expect(diagnostics.largestComponentTriggerIntervals, hasLength(3));
    expect(diagnostics.largestComponentStrongEdgeCount, 3);
    expect(diagnostics.largestComponentWeakEdgeCount, 0);
    expect(diagnostics.largestComponentCentroidLatitude, isNotNull);
    expect(diagnostics.largestComponentCentroidLongitude, isNotNull);
  });

  test('bridges distant stations only when trigger intervals are close', () {
    final detector = SpatiotemporalEventDetector(
      config: const SpatiotemporalEventDetectorConfig(
        temporalBridgeDistanceKm: 160,
        temporalBridgeMaxGap: Duration(seconds: 8),
      ),
    );
    final t0 = DateTime(2026, 6, 20, 12);
    final closeInTime = detector.diagnose([
      station(0, t0, firstTriggeredAt: t0),
      station(
        1,
        t0,
        longitude: 136,
        firstTriggeredAt: t0.add(const Duration(seconds: 8)),
      ),
    ]);
    expect(closeInTime.largestComponentSize, 2);
    expect(closeInTime.largestComponentStrongEdgeCount, 0);
    expect(closeInTime.largestComponentWeakEdgeCount, 1);

    final farInTime = detector.diagnose([
      station(0, t0, firstTriggeredAt: t0),
      station(
        1,
        t0,
        longitude: 136,
        firstTriggeredAt: t0.add(const Duration(seconds: 10)),
      ),
    ]);
    expect(farInTime.largestComponentSize, 1);

    final missingTime = detector.diagnose([
      station(0, t0),
      station(1, t0, longitude: 136),
    ]);
    expect(missingTime.largestComponentSize, 1);
  });

  test('requires persistent compact support before source confirmation', () {
    final detector = SpatiotemporalEventDetector(
      config: const SpatiotemporalEventDetectorConfig(
        candidateMinStations: 4,
        confirmedMinStations: 5,
        maxInitialConfirmationDiameterKm: 120,
        confirmationPersistenceFrames: 2,
      ),
    );
    final t0 = DateTime(2026, 6, 20, 12);
    final stations = [for (var id = 0; id < 5; id++) station(id, t0)];

    final pending = detector.update(observedAt: t0, stations: stations);
    expect(pending.state, EventDetectionState.candidate);
    expect(pending.reasonCodes, contains('confirmation_persistence_pending'));
    expect(pending.metadata['confirmation_streak'], 1);

    final confirmed = detector.update(
      observedAt: t0.add(const Duration(seconds: 1)),
      stations: stations,
    );
    expect(confirmed.state, EventDetectionState.confirmed);
    expect(confirmed.reasonCodes, contains('network_cluster_confirmed'));
    expect(confirmed.metadata['confirmation_streak'], 2);
  });

  test('keeps a stable compact core when the full component expands', () {
    final detector = SpatiotemporalEventDetector(
      config: const SpatiotemporalEventDetectorConfig(
        candidateMinStations: 4,
        confirmedMinStations: 5,
        maxInitialConfirmationDiameterKm: 120,
        confirmationPersistenceFrames: 2,
      ),
    );
    final t0 = DateTime(2026, 6, 20, 12);
    final compact = [for (var id = 0; id < 5; id++) station(id, t0)];

    final pending = detector.update(observedAt: t0, stations: compact);
    expect(pending.state, EventDetectionState.candidate);

    final expanded = [
      ...compact,
      station(20, t0, latitude: 34.6, longitude: 135.3),
      station(21, t0, latitude: 34.6, longitude: 135.85),
      station(22, t0, latitude: 34.6, longitude: 136.4),
    ];
    final confirmed = detector.update(
      observedAt: t0.add(const Duration(seconds: 1)),
      stations: expanded,
    );

    expect(confirmed.state, EventDetectionState.confirmed);
    expect(confirmed.memberStationIds, hasLength(5));
    expect(confirmed.metadata['largestComponentDiameterKm'], greaterThan(120));
  });

  test(
    'rejects a persistent chain that is too wide for initial confirmation',
    () {
      final detector = SpatiotemporalEventDetector(
        config: const SpatiotemporalEventDetectorConfig(
          candidateMinStations: 4,
          confirmedMinStations: 5,
          maxInitialConfirmationDiameterKm: 120,
          candidateTimeout: Duration(seconds: 8),
          quarantineRejectedMembersUntilClear: true,
        ),
      );
      final t0 = DateTime(2026, 6, 20, 12);
      final stations = [
        for (var id = 0; id < 5; id++)
          station(
            id,
            t0,
            longitude: 135 + id * 0.55,
            firstTriggeredAt: t0.add(Duration(seconds: id * 2)),
          ),
      ];

      final candidate = detector.update(observedAt: t0, stations: stations);
      expect(candidate.state, EventDetectionState.candidate);
      expect(
        candidate.reasonCodes,
        contains('initial_confirmation_diameter_rejected'),
      );
      expect(
        candidate.metadata['largestComponentDiameterKm'],
        greaterThan(120),
      );

      final rejected = detector.update(
        observedAt: t0.add(const Duration(seconds: 8)),
        stations: stations,
      );
      expect(rejected.state, EventDetectionState.rejected);
      expect(rejected.reasonCodes, contains('candidate_timeout'));

      final blocked = detector.update(
        observedAt: t0.add(const Duration(seconds: 9)),
        stations: stations.sublist(1),
      );
      expect(blocked.state, EventDetectionState.idle);
      expect(
        blocked.reasonCodes,
        contains('rejected_cluster_members_still_active'),
      );

      final rearmed = detector.update(
        observedAt: t0.add(const Duration(seconds: 10)),
        stations: [
          for (var id = 10; id < 15; id++)
            station(id, t0, latitude: 42, longitude: 142),
        ],
      );
      expect(rearmed.state, EventDetectionState.confirmed);
    },
  );

  test('ends a confirmed event after network support disappears', () {
    final detector = SpatiotemporalEventDetector();
    final t0 = DateTime(2026, 6, 20, 12);
    final confirmed = detector.update(
      observedAt: t0,
      stations: [for (var id = 0; id < 6; id++) station(id, t0)],
    );
    expect(confirmed.state, EventDetectionState.confirmed);

    final coasting = detector.update(
      observedAt: t0.add(const Duration(seconds: 5)),
      stations: const [],
    );
    expect(coasting.state, EventDetectionState.confirmed);

    final ended = detector.update(
      observedAt: t0.add(const Duration(seconds: 6)),
      stations: const [],
    );
    expect(ended.state, EventDetectionState.ended);
    expect(ended.eventId, confirmed.eventId);

    final idle = detector.update(
      observedAt: t0.add(const Duration(seconds: 7)),
      stations: const [],
    );
    expect(idle.state, EventDetectionState.idle);
    expect(idle.eventId, isNull);
  });
}
