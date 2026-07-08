import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_candidate_region_tracker.dart';

void main() {
  test('confirms a pending candidate after same-region residual support', () {
    final tracker = SourceCandidateRegionTracker();
    final start = DateTime(2026, 6, 22, 16, 38, 23);

    final pending = tracker.observe(
      SourceCandidateRegionObservation(
        eventId: 'kushiro',
        observedAt: start,
        latitude: 42.993,
        longitude: 144.10,
        residualSupported: false,
      ),
    );
    expect(pending.status, SourceCandidateRegionStatus.pending);
    expect(pending.productionCoordinateSwitchAllowed, isFalse);

    final confirmed = tracker.observe(
      SourceCandidateRegionObservation(
        eventId: 'kushiro',
        observedAt: start.add(const Duration(seconds: 4)),
        latitude: 43.071,
        longitude: 144.22,
        residualSupported: true,
      ),
    );

    expect(confirmed.status, SourceCandidateRegionStatus.confirmedDelayed);
    expect(confirmed.confirmationDelaySeconds, 4);
    expect(confirmed.clusterDistanceKm, lessThan(30));
    expect(confirmed.productionCoordinateSwitchAllowed, isFalse);
    expect(
      confirmed.toDiagnostics()['reason'],
      'same_region_residual_confirmation',
    );
  });

  test('keeps unsupported Fukushima-like candidates pending only', () {
    final tracker = SourceCandidateRegionTracker();
    final start = DateTime(2026, 6, 21, 23, 41, 50);

    SourceCandidateRegionDecision? latest;
    for (var i = 0; i < 5; i++) {
      latest = tracker.observe(
        SourceCandidateRegionObservation(
          eventId: 'fukushima',
          observedAt: start.add(Duration(seconds: i)),
          latitude: 38.35 + i * 0.002,
          longitude: 141.02 + i * 0.002,
          residualSupported: false,
        ),
      );
    }

    expect(latest!.status, SourceCandidateRegionStatus.pending);
    expect(latest.isConfirmed, isFalse);
    expect(latest.productionCoordinateSwitchAllowed, isFalse);
  });

  test('confirms pending candidate with local member support growth', () {
    final tracker = SourceCandidateRegionTracker();
    const gate = SourceCandidateLocalSupportGate();
    final start = DateTime(2026, 6, 25, 19, 21, 43);
    const initialSnapshot = SourceCandidateLocalSupportSnapshot(
      memberCount: 5,
      memberCentroidLatitude: 39.7,
      memberCentroidLongitude: 142.1,
      estimateMemberCentroidDistanceKm: 154,
      stationGeometry: 'one_sided',
    );

    tracker.observe(
      SourceCandidateRegionObservation(
        eventId: 'iwate',
        observedAt: start,
        latitude: 39.65,
        longitude: 142.08,
        residualSupported: false,
        localSupportSnapshot: initialSnapshot,
      ),
    );

    const currentSnapshot = SourceCandidateLocalSupportSnapshot(
      memberCount: 10,
      memberCentroidLatitude: 39.7,
      memberCentroidLongitude: 142.1,
      estimateMemberCentroidDistanceKm: 16,
      stationGeometry: 'surrounded',
    );
    final gateResult = gate.evaluate(
      initialSnapshot: tracker.pendingLocalSupportSnapshot('iwate'),
      currentSnapshot: currentSnapshot,
    );
    final confirmed = tracker.confirmPendingWithLocalSupport(
      eventId: 'iwate',
      observedAt: start.add(const Duration(seconds: 3)),
      result: gateResult,
      currentSnapshot: currentSnapshot,
    );

    expect(gateResult.localSupportConfirmed, isTrue);
    expect(gateResult.memberCountGrowth, 5);
    expect(gateResult.convergenceKm, 138);
    expect(confirmed.status, SourceCandidateRegionStatus.confirmedDelayed);
    expect(confirmed.reason, 'same_region_local_support_confirmation');
    expect(confirmed.productionCoordinateSwitchAllowed, isFalse);
  });

  test('keeps Fukushima-like local support pending without convergence', () {
    final tracker = SourceCandidateRegionTracker();
    const gate = SourceCandidateLocalSupportGate();
    final start = DateTime(2026, 6, 21, 23, 41, 50);

    tracker.observe(
      SourceCandidateRegionObservation(
        eventId: 'fukushima',
        observedAt: start,
        latitude: 38.35,
        longitude: 141.02,
        residualSupported: false,
        localSupportSnapshot: const SourceCandidateLocalSupportSnapshot(
          memberCount: 5,
          memberCentroidLatitude: 37.6,
          memberCentroidLongitude: 142.2,
          estimateMemberCentroidDistanceKm: 154,
          stationGeometry: 'one_sided',
        ),
      ),
    );

    const currentSnapshot = SourceCandidateLocalSupportSnapshot(
      memberCount: 12,
      memberCentroidLatitude: 38.2,
      memberCentroidLongitude: 141.0,
      estimateMemberCentroidDistanceKm: 160,
      stationGeometry: 'one_sided',
    );
    final gateResult = gate.evaluate(
      initialSnapshot: tracker.pendingLocalSupportSnapshot('fukushima'),
      currentSnapshot: currentSnapshot,
    );
    final pending = tracker.confirmPendingWithLocalSupport(
      eventId: 'fukushima',
      observedAt: start.add(const Duration(seconds: 3)),
      result: gateResult,
      currentSnapshot: currentSnapshot,
    );

    expect(gateResult.localSupportConfirmed, isFalse);
    expect(gateResult.convergenceSupported, isFalse);
    expect(gateResult.geometrySupported, isFalse);
    expect(pending.status, SourceCandidateRegionStatus.pending);
    expect(pending.productionCoordinateSwitchAllowed, isFalse);
  });

  test(
    'local support can confirm after growth from an already valid count',
    () {
      const gate = SourceCandidateLocalSupportGate();
      final result = gate.evaluate(
        initialSnapshot: const SourceCandidateLocalSupportSnapshot(
          memberCount: 8,
          memberCentroidLatitude: 39.7,
          memberCentroidLongitude: 142.1,
          estimateMemberCentroidDistanceKm: 140,
          stationGeometry: 'surrounded',
        ),
        currentSnapshot: const SourceCandidateLocalSupportSnapshot(
          memberCount: 12,
          memberCentroidLatitude: 39.7,
          memberCentroidLongitude: 142.1,
          estimateMemberCentroidDistanceKm: 40,
          stationGeometry: 'surrounded',
        ),
      );

      expect(result.localSupportConfirmed, isTrue);
      expect(result.memberCountSupported, isTrue);
      expect(result.memberGrowthSupported, isTrue);
      expect(result.convergenceKm, 100);
    },
  );

  test('local support does not create a candidate region without pending', () {
    final tracker = SourceCandidateRegionTracker();
    const gate = SourceCandidateLocalSupportGate();
    final gateResult = gate.evaluate(
      initialSnapshot: null,
      currentSnapshot: const SourceCandidateLocalSupportSnapshot(
        memberCount: 10,
        memberCentroidLatitude: 39.7,
        memberCentroidLongitude: 142.1,
        estimateMemberCentroidDistanceKm: 16,
        stationGeometry: 'surrounded',
      ),
    );

    final decision = tracker.confirmPendingWithLocalSupport(
      eventId: 'none',
      observedAt: DateTime(2026, 6, 25, 19, 21, 46),
      result: gateResult,
    );

    expect(gateResult.localSupportConfirmed, isFalse);
    expect(decision.status, SourceCandidateRegionStatus.none);
    expect(decision.productionCoordinateSwitchAllowed, isFalse);
  });

  test('local support requires substantial member growth', () {
    const gate = SourceCandidateLocalSupportGate();
    final result = gate.evaluate(
      initialSnapshot: const SourceCandidateLocalSupportSnapshot(
        memberCount: 16,
        memberCentroidLatitude: 38.2,
        memberCentroidLongitude: 141.0,
        estimateMemberCentroidDistanceKm: 187,
        stationGeometry: 'one_sided',
      ),
      currentSnapshot: const SourceCandidateLocalSupportSnapshot(
        memberCount: 17,
        memberCentroidLatitude: 38.2,
        memberCentroidLongitude: 141.0,
        estimateMemberCentroidDistanceKm: 5,
        stationGeometry: 'surrounded',
      ),
    );

    expect(result.memberCountSupported, isTrue);
    expect(result.memberGrowthSupported, isFalse);
    expect(result.estimateMemberDistanceSupported, isTrue);
    expect(result.convergenceSupported, isTrue);
    expect(result.geometrySupported, isTrue);
    expect(result.localSupportConfirmed, isFalse);
  });

  test('does not confirm against an expired pending candidate', () {
    final tracker = SourceCandidateRegionTracker(
      config: const SourceCandidateRegionTrackerConfig(
        confirmationWindow: Duration(seconds: 5),
        clusterDistanceKm: 30,
      ),
    );
    final start = DateTime(2026, 6, 22, 16, 38, 23);

    tracker.observe(
      SourceCandidateRegionObservation(
        eventId: 'expired',
        observedAt: start,
        latitude: 42.993,
        longitude: 144.10,
        residualSupported: false,
      ),
    );

    final confirmed = tracker.observe(
      SourceCandidateRegionObservation(
        eventId: 'expired',
        observedAt: start.add(const Duration(seconds: 7)),
        latitude: 43.0,
        longitude: 144.11,
        residualSupported: true,
      ),
    );

    expect(confirmed.status, SourceCandidateRegionStatus.confirmedImmediate);
    expect(confirmed.confirmationDelaySeconds, 0);
    expect(confirmed.reason, 'residual_supported_candidate');
  });

  test(
    'builds candidate observations from production estimate diagnostics',
    () {
      final gate = SourceCandidateResidualGate();
      final estimate = SourceEstimate(
        latitude: 0,
        longitude: 1,
        confidence: 0.3,
        method: 'test',
        supportingStationCount: 2,
        diagnostics: {
          'candidate_corrections': {
            'one_sided_boundary_centroid_guard': {
              'latitude': 0.0,
              'longitude': 0.0,
            },
          },
          'top_timing_picks': const [
            {
              'code': 'A',
              'latitude': 0.0,
              'longitude': 0.0,
              'delay_s': 0.0,
              'value': 2.0,
            },
            {
              'code': 'B',
              'latitude': 0.0,
              'longitude': 1.0,
              'delay_s': 1.0,
              'value': 0.0,
            },
          ],
        },
      );

      final result = gate.evaluate(estimate);
      expect(result, isNotNull);
      expect(result!.residualSupported, isTrue);
      expect(result.rankSupportsCandidate, isTrue);

      final observedAt = DateTime(2026, 6, 22, 16, 38, 27);
      final observation = gate.observationForEstimate(
        eventId: 'synthetic',
        observedAt: observedAt,
        estimate: estimate,
      );

      expect(observation, isNotNull);
      expect(observation!.residualSupported, isTrue);
      expect(observation.latitude, 0);
      expect(observation.longitude, 0);
    },
  );
}
