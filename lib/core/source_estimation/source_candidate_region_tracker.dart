import 'dart:math' as math;

import 'source_estimation_models.dart';

class SourceCandidateResidualGateConfig {
  final double rankSupportDelta;
  final double attenuationSupportDelta;
  final double rankRegressionDelta;
  final double attenuationRegressionRatio;
  final double attenuationLogDistanceCoefficient;
  final double attenuationNearDistanceKm;

  const SourceCandidateResidualGateConfig({
    this.rankSupportDelta = -0.05,
    this.attenuationSupportDelta = -0.05,
    this.rankRegressionDelta = 0.10,
    this.attenuationRegressionRatio = 1.25,
    this.attenuationLogDistanceCoefficient = 2.0,
    this.attenuationNearDistanceKm = 5.0,
  });
}

class SourceCandidateResidualGateResult {
  final bool residualSupported;
  final bool rankSupportsCandidate;
  final bool attenuationSupportsCandidate;
  final bool dualResidualRegression;
  final double? rankDelta;
  final double? attenuationDelta;
  final double? attenuationRatio;

  const SourceCandidateResidualGateResult({
    required this.residualSupported,
    required this.rankSupportsCandidate,
    required this.attenuationSupportsCandidate,
    required this.dualResidualRegression,
    required this.rankDelta,
    required this.attenuationDelta,
    required this.attenuationRatio,
  });

  Map<String, Object?> toDiagnostics() => {
    'residual_supported': residualSupported,
    'rank_supports_candidate': rankSupportsCandidate,
    'attenuation_supports_candidate': attenuationSupportsCandidate,
    'dual_residual_regression': dualResidualRegression,
    'rank_delta': rankDelta,
    'attenuation_delta': attenuationDelta,
    'attenuation_ratio': attenuationRatio,
  };
}

class SourceCandidateResidualGate {
  const SourceCandidateResidualGate({
    this.config = const SourceCandidateResidualGateConfig(),
  });

  final SourceCandidateResidualGateConfig config;

  SourceCandidateResidualGateResult? evaluate(SourceEstimate estimate) {
    final candidate = _candidateCorrection(estimate.diagnostics);
    if (candidate == null) return null;
    final picks = _diagnosticPicks(estimate.diagnostics);
    if (picks.length < 2) return null;

    final baseline = _ResidualLocationDiagnostics.forLocation(
      latitude: estimate.latitude,
      longitude: estimate.longitude,
      picks: picks,
      config: config,
    );
    final candidateDiagnostics = _ResidualLocationDiagnostics.forLocation(
      latitude: candidate.latitude,
      longitude: candidate.longitude,
      picks: picks,
      config: config,
    );
    final rankDelta =
        candidateDiagnostics.rankInversionRate - baseline.rankInversionRate;
    final attenuationDelta = _delta(
      candidateDiagnostics.attenuationRms,
      baseline.attenuationRms,
    );
    final attenuationRatio = _ratio(
      candidateDiagnostics.attenuationRms,
      baseline.attenuationRms,
    );
    final rankSupportsCandidate = rankDelta <= config.rankSupportDelta;
    final attenuationSupportsCandidate =
        attenuationDelta != null &&
        attenuationDelta <= config.attenuationSupportDelta;
    final dualResidualRegression =
        rankDelta >= config.rankRegressionDelta &&
        attenuationRatio != null &&
        attenuationRatio >= config.attenuationRegressionRatio;

    return SourceCandidateResidualGateResult(
      residualSupported:
          (rankSupportsCandidate || attenuationSupportsCandidate) &&
          !dualResidualRegression,
      rankSupportsCandidate: rankSupportsCandidate,
      attenuationSupportsCandidate: attenuationSupportsCandidate,
      dualResidualRegression: dualResidualRegression,
      rankDelta: rankDelta,
      attenuationDelta: attenuationDelta,
      attenuationRatio: attenuationRatio,
    );
  }

  SourceCandidateRegionObservation? observationForEstimate({
    required String eventId,
    required DateTime observedAt,
    required SourceEstimate estimate,
    SourceCandidateLocalSupportSnapshot? localSupportSnapshot,
  }) {
    final candidate = _candidateCorrection(estimate.diagnostics);
    final result = evaluate(estimate);
    if (candidate == null || result == null) return null;
    return SourceCandidateRegionObservation(
      eventId: eventId,
      observedAt: observedAt,
      latitude: candidate.latitude,
      longitude: candidate.longitude,
      residualSupported: result.residualSupported,
      reason: 'candidate_residual_gate_v1',
      localSupportSnapshot: localSupportSnapshot,
    );
  }
}

class SourceCandidateLocalSupportGateConfig {
  final int minMemberCount;
  final int minMemberGrowth;
  final double maxEstimateMemberCentroidDistanceKm;
  final double minConvergenceKm;

  const SourceCandidateLocalSupportGateConfig({
    this.minMemberCount = 8,
    this.minMemberGrowth = 4,
    this.maxEstimateMemberCentroidDistanceKm = 50,
    this.minConvergenceKm = 80,
  });
}

class SourceCandidateLocalSupportSnapshot {
  final int memberCount;
  final double memberCentroidLatitude;
  final double memberCentroidLongitude;
  final double estimateMemberCentroidDistanceKm;
  final String? stationGeometry;

  const SourceCandidateLocalSupportSnapshot({
    required this.memberCount,
    required this.memberCentroidLatitude,
    required this.memberCentroidLongitude,
    required this.estimateMemberCentroidDistanceKm,
    required this.stationGeometry,
  });

  Map<String, Object?> toDiagnostics() => {
    'member_count': memberCount,
    'member_centroid_latitude': memberCentroidLatitude,
    'member_centroid_longitude': memberCentroidLongitude,
    'estimate_member_centroid_distance_km': estimateMemberCentroidDistanceKm,
    'station_geometry': stationGeometry,
  };
}

class SourceCandidateLocalSupportGateResult {
  final bool localSupportConfirmed;
  final bool memberCountSupported;
  final bool memberGrowthSupported;
  final bool estimateMemberDistanceSupported;
  final bool convergenceSupported;
  final bool geometrySupported;
  final int? memberCount;
  final int? initialMemberCount;
  final int? memberCountGrowth;
  final double? memberCentroidLatitude;
  final double? memberCentroidLongitude;
  final double? estimateMemberCentroidDistanceKm;
  final double? initialEstimateMemberCentroidDistanceKm;
  final double? convergenceKm;
  final String? stationGeometry;
  final String reason;

  const SourceCandidateLocalSupportGateResult({
    required this.localSupportConfirmed,
    required this.memberCountSupported,
    required this.memberGrowthSupported,
    required this.estimateMemberDistanceSupported,
    required this.convergenceSupported,
    required this.geometrySupported,
    required this.memberCount,
    required this.initialMemberCount,
    required this.memberCountGrowth,
    required this.memberCentroidLatitude,
    required this.memberCentroidLongitude,
    required this.estimateMemberCentroidDistanceKm,
    required this.initialEstimateMemberCentroidDistanceKm,
    required this.convergenceKm,
    required this.stationGeometry,
    required this.reason,
  });

  Map<String, Object?> toDiagnostics() => {
    'local_support_confirmed': localSupportConfirmed,
    'member_count_supported': memberCountSupported,
    'member_growth_supported': memberGrowthSupported,
    'estimate_member_distance_supported': estimateMemberDistanceSupported,
    'convergence_supported': convergenceSupported,
    'geometry_supported': geometrySupported,
    'member_count': memberCount,
    'initial_member_count': initialMemberCount,
    'member_count_growth': memberCountGrowth,
    'member_centroid_latitude': memberCentroidLatitude,
    'member_centroid_longitude': memberCentroidLongitude,
    'estimate_member_centroid_distance_km': estimateMemberCentroidDistanceKm,
    'initial_estimate_member_centroid_distance_km':
        initialEstimateMemberCentroidDistanceKm,
    'convergence_km': convergenceKm,
    'station_geometry': stationGeometry,
    'reason': reason,
  };
}

class SourceCandidateLocalSupportGate {
  const SourceCandidateLocalSupportGate({
    this.config = const SourceCandidateLocalSupportGateConfig(),
  });

  final SourceCandidateLocalSupportGateConfig config;

  SourceCandidateLocalSupportSnapshot? snapshotForEstimate({
    required SourceEstimate estimate,
    required Iterable<String> memberIds,
    required Iterable<SeismicStationEventRecord> stationRecords,
  }) {
    final accepted = memberIds.toSet();
    if (accepted.isEmpty) return null;
    final members = [
      for (final record in stationRecords)
        if (accepted.contains(record.descriptor.code)) record,
    ];
    if (members.isEmpty) return null;

    final lat =
        members.fold<double>(
          0,
          (total, record) => total + record.descriptor.coordinate.latitude,
        ) /
        members.length;
    final lng =
        members.fold<double>(
          0,
          (total, record) => total + record.descriptor.coordinate.longitude,
        ) /
        members.length;
    return SourceCandidateLocalSupportSnapshot(
      memberCount: members.length,
      memberCentroidLatitude: lat,
      memberCentroidLongitude: lng,
      estimateMemberCentroidDistanceKm: _distanceKm(
        estimate.latitude,
        estimate.longitude,
        lat,
        lng,
      ),
      stationGeometry: estimate.diagnostics['station_geometry']?.toString(),
    );
  }

  SourceCandidateLocalSupportGateResult evaluate({
    required SourceCandidateLocalSupportSnapshot? initialSnapshot,
    required SourceCandidateLocalSupportSnapshot? currentSnapshot,
  }) {
    if (initialSnapshot == null || currentSnapshot == null) {
      return SourceCandidateLocalSupportGateResult(
        localSupportConfirmed: false,
        memberCountSupported: false,
        memberGrowthSupported: false,
        estimateMemberDistanceSupported: false,
        convergenceSupported: false,
        geometrySupported: false,
        memberCount: currentSnapshot?.memberCount,
        initialMemberCount: initialSnapshot?.memberCount,
        memberCountGrowth: null,
        memberCentroidLatitude: currentSnapshot?.memberCentroidLatitude,
        memberCentroidLongitude: currentSnapshot?.memberCentroidLongitude,
        estimateMemberCentroidDistanceKm:
            currentSnapshot?.estimateMemberCentroidDistanceKm,
        initialEstimateMemberCentroidDistanceKm:
            initialSnapshot?.estimateMemberCentroidDistanceKm,
        convergenceKm: null,
        stationGeometry: currentSnapshot?.stationGeometry,
        reason: 'missing_pending_or_current_local_support_snapshot',
      );
    }

    final memberCountGrowth =
        currentSnapshot.memberCount - initialSnapshot.memberCount;
    final convergenceKm =
        initialSnapshot.estimateMemberCentroidDistanceKm -
        currentSnapshot.estimateMemberCentroidDistanceKm;
    final memberCountSupported =
        currentSnapshot.memberCount >= config.minMemberCount;
    final memberGrowthSupported = memberCountGrowth >= config.minMemberGrowth;
    final estimateMemberDistanceSupported =
        currentSnapshot.estimateMemberCentroidDistanceKm <=
        config.maxEstimateMemberCentroidDistanceKm;
    final convergenceSupported = convergenceKm >= config.minConvergenceKm;
    final geometrySupported = currentSnapshot.stationGeometry != 'one_sided';
    final supported =
        memberCountSupported &&
        memberGrowthSupported &&
        estimateMemberDistanceSupported &&
        convergenceSupported &&
        geometrySupported;

    return SourceCandidateLocalSupportGateResult(
      localSupportConfirmed: supported,
      memberCountSupported: memberCountSupported,
      memberGrowthSupported: memberGrowthSupported,
      estimateMemberDistanceSupported: estimateMemberDistanceSupported,
      convergenceSupported: convergenceSupported,
      geometrySupported: geometrySupported,
      memberCount: currentSnapshot.memberCount,
      initialMemberCount: initialSnapshot.memberCount,
      memberCountGrowth: memberCountGrowth,
      memberCentroidLatitude: currentSnapshot.memberCentroidLatitude,
      memberCentroidLongitude: currentSnapshot.memberCentroidLongitude,
      estimateMemberCentroidDistanceKm:
          currentSnapshot.estimateMemberCentroidDistanceKm,
      initialEstimateMemberCentroidDistanceKm:
          initialSnapshot.estimateMemberCentroidDistanceKm,
      convergenceKm: convergenceKm,
      stationGeometry: currentSnapshot.stationGeometry,
      reason: supported
          ? 'local_member_support_confirmed'
          : 'local_member_support_below_threshold',
    );
  }
}

class SourceCandidateRegionTrackerConfig {
  final Duration confirmationWindow;
  final double clusterDistanceKm;

  const SourceCandidateRegionTrackerConfig({
    this.confirmationWindow = const Duration(seconds: 5),
    this.clusterDistanceKm = 30,
  });
}

enum SourceCandidateRegionStatus {
  none,
  pending,
  confirmedImmediate,
  confirmedDelayed,
  expired,
}

class SourceCandidateRegionObservation {
  final String eventId;
  final DateTime observedAt;
  final double latitude;
  final double longitude;
  final bool residualSupported;
  final String reason;
  final SourceCandidateLocalSupportSnapshot? localSupportSnapshot;

  const SourceCandidateRegionObservation({
    required this.eventId,
    required this.observedAt,
    required this.latitude,
    required this.longitude,
    required this.residualSupported,
    this.reason = 'one_sided_boundary_centroid_guard',
    this.localSupportSnapshot,
  });
}

class SourceCandidateRegionDecision {
  final SourceCandidateRegionStatus status;
  final String eventId;
  final DateTime observedAt;
  final double? latitude;
  final double? longitude;
  final DateTime? firstObservedAt;
  final DateTime? confirmedAt;
  final double? confirmationDelaySeconds;
  final double? clusterDistanceKm;
  final bool productionCoordinateSwitchAllowed;
  final String reason;

  const SourceCandidateRegionDecision({
    required this.status,
    required this.eventId,
    required this.observedAt,
    required this.latitude,
    required this.longitude,
    required this.firstObservedAt,
    required this.confirmedAt,
    required this.confirmationDelaySeconds,
    required this.clusterDistanceKm,
    required this.productionCoordinateSwitchAllowed,
    required this.reason,
  });

  bool get isConfirmed =>
      status == SourceCandidateRegionStatus.confirmedImmediate ||
      status == SourceCandidateRegionStatus.confirmedDelayed;

  Map<String, Object?> toDiagnostics() => {
    'status': status.name,
    'event_id': eventId,
    'observed_at': observedAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'first_observed_at': firstObservedAt?.toIso8601String(),
    'confirmed_at': confirmedAt?.toIso8601String(),
    'confirmation_delay_seconds': confirmationDelaySeconds,
    'cluster_distance_km': clusterDistanceKm,
    'production_coordinate_switch_allowed': productionCoordinateSwitchAllowed,
    'reason': reason,
  };
}

class SourceCandidateRegionTracker {
  SourceCandidateRegionTracker({
    this.config = const SourceCandidateRegionTrackerConfig(),
  });

  final SourceCandidateRegionTrackerConfig config;
  final Map<String, _PendingRegion> _pendingByEvent = {};

  SourceCandidateRegionDecision observe(
    SourceCandidateRegionObservation observation,
  ) {
    final pending = _pendingByEvent[observation.eventId];
    if (pending != null && _isExpired(pending, observation.observedAt)) {
      _pendingByEvent.remove(observation.eventId);
      if (observation.residualSupported) {
        return _confirmIfClustered(null, observation);
      }
      if (!observation.residualSupported) {
        _pendingByEvent[observation.eventId] = _PendingRegion.fromObservation(
          observation,
        );
      }
      return SourceCandidateRegionDecision(
        status: SourceCandidateRegionStatus.expired,
        eventId: observation.eventId,
        observedAt: observation.observedAt,
        latitude: pending.latitude,
        longitude: pending.longitude,
        firstObservedAt: pending.firstObservedAt,
        confirmedAt: null,
        confirmationDelaySeconds: null,
        clusterDistanceKm: _distanceKm(
          pending.latitude,
          pending.longitude,
          observation.latitude,
          observation.longitude,
        ),
        productionCoordinateSwitchAllowed: false,
        reason: 'pending_candidate_expired',
      );
    }

    if (observation.residualSupported) {
      final confirmed = _confirmIfClustered(pending, observation);
      _pendingByEvent.remove(observation.eventId);
      return confirmed;
    }

    if (pending == null ||
        _distanceKm(
              pending.latitude,
              pending.longitude,
              observation.latitude,
              observation.longitude,
            ) >
            config.clusterDistanceKm) {
      final next = _PendingRegion.fromObservation(observation);
      _pendingByEvent[observation.eventId] = next;
      return _pendingDecision(observation, next, 0);
    }

    pending.lastObservedAt = observation.observedAt;
    pending.latestLocalSupportSnapshot = observation.localSupportSnapshot;
    return _pendingDecision(
      observation,
      pending,
      _distanceKm(
        pending.latitude,
        pending.longitude,
        observation.latitude,
        observation.longitude,
      ),
    );
  }

  bool hasPending(String eventId) => _pendingByEvent.containsKey(eventId);

  SourceCandidateLocalSupportSnapshot? pendingLocalSupportSnapshot(
    String eventId,
  ) {
    return _pendingByEvent[eventId]?.initialLocalSupportSnapshot;
  }

  SourceCandidateRegionDecision confirmPendingWithLocalSupport({
    required String eventId,
    required DateTime observedAt,
    required SourceCandidateLocalSupportGateResult result,
    SourceCandidateLocalSupportSnapshot? currentSnapshot,
  }) {
    final pending = _pendingByEvent[eventId];
    if (pending == null) {
      return SourceCandidateRegionDecision(
        status: SourceCandidateRegionStatus.none,
        eventId: eventId,
        observedAt: observedAt,
        latitude: null,
        longitude: null,
        firstObservedAt: null,
        confirmedAt: null,
        confirmationDelaySeconds: null,
        clusterDistanceKm: null,
        productionCoordinateSwitchAllowed: false,
        reason: 'no_pending_candidate_region',
      );
    }

    if (_isExpired(pending, observedAt)) {
      _pendingByEvent.remove(eventId);
      return SourceCandidateRegionDecision(
        status: SourceCandidateRegionStatus.expired,
        eventId: eventId,
        observedAt: observedAt,
        latitude: pending.latitude,
        longitude: pending.longitude,
        firstObservedAt: pending.firstObservedAt,
        confirmedAt: null,
        confirmationDelaySeconds: null,
        clusterDistanceKm: null,
        productionCoordinateSwitchAllowed: false,
        reason: 'pending_candidate_expired',
      );
    }

    pending
      ..lastObservedAt = observedAt
      ..latestLocalSupportSnapshot = currentSnapshot;
    if (!result.localSupportConfirmed) {
      return SourceCandidateRegionDecision(
        status: SourceCandidateRegionStatus.pending,
        eventId: eventId,
        observedAt: observedAt,
        latitude: pending.latitude,
        longitude: pending.longitude,
        firstObservedAt: pending.firstObservedAt,
        confirmedAt: null,
        confirmationDelaySeconds: null,
        clusterDistanceKm: null,
        productionCoordinateSwitchAllowed: false,
        reason: 'awaiting_local_member_support',
      );
    }

    _pendingByEvent.remove(eventId);
    return SourceCandidateRegionDecision(
      status: SourceCandidateRegionStatus.confirmedDelayed,
      eventId: eventId,
      observedAt: observedAt,
      latitude: pending.latitude,
      longitude: pending.longitude,
      firstObservedAt: pending.firstObservedAt,
      confirmedAt: observedAt,
      confirmationDelaySeconds:
          observedAt.difference(pending.firstObservedAt).inMilliseconds /
          Duration.millisecondsPerSecond,
      clusterDistanceKm: null,
      productionCoordinateSwitchAllowed: false,
      reason: 'same_region_local_support_confirmation',
    );
  }

  SourceCandidateRegionDecision clear(String eventId, DateTime observedAt) {
    final pending = _pendingByEvent.remove(eventId);
    return SourceCandidateRegionDecision(
      status: SourceCandidateRegionStatus.none,
      eventId: eventId,
      observedAt: observedAt,
      latitude: pending?.latitude,
      longitude: pending?.longitude,
      firstObservedAt: pending?.firstObservedAt,
      confirmedAt: null,
      confirmationDelaySeconds: null,
      clusterDistanceKm: null,
      productionCoordinateSwitchAllowed: false,
      reason: 'candidate_region_cleared',
    );
  }

  void reset() {
    _pendingByEvent.clear();
  }

  bool _isExpired(_PendingRegion pending, DateTime observedAt) =>
      observedAt.difference(pending.firstObservedAt) >
      config.confirmationWindow;

  SourceCandidateRegionDecision _confirmIfClustered(
    _PendingRegion? pending,
    SourceCandidateRegionObservation observation,
  ) {
    if (pending == null) {
      return SourceCandidateRegionDecision(
        status: SourceCandidateRegionStatus.confirmedImmediate,
        eventId: observation.eventId,
        observedAt: observation.observedAt,
        latitude: observation.latitude,
        longitude: observation.longitude,
        firstObservedAt: observation.observedAt,
        confirmedAt: observation.observedAt,
        confirmationDelaySeconds: 0,
        clusterDistanceKm: 0,
        productionCoordinateSwitchAllowed: false,
        reason: 'residual_supported_candidate',
      );
    }

    final distanceKm = _distanceKm(
      pending.latitude,
      pending.longitude,
      observation.latitude,
      observation.longitude,
    );
    if (distanceKm <= config.clusterDistanceKm) {
      return SourceCandidateRegionDecision(
        status: SourceCandidateRegionStatus.confirmedDelayed,
        eventId: observation.eventId,
        observedAt: observation.observedAt,
        latitude: observation.latitude,
        longitude: observation.longitude,
        firstObservedAt: pending.firstObservedAt,
        confirmedAt: observation.observedAt,
        confirmationDelaySeconds:
            observation.observedAt
                .difference(pending.firstObservedAt)
                .inMilliseconds /
            Duration.millisecondsPerSecond,
        clusterDistanceKm: distanceKm,
        productionCoordinateSwitchAllowed: false,
        reason: 'same_region_residual_confirmation',
      );
    }

    return SourceCandidateRegionDecision(
      status: SourceCandidateRegionStatus.confirmedImmediate,
      eventId: observation.eventId,
      observedAt: observation.observedAt,
      latitude: observation.latitude,
      longitude: observation.longitude,
      firstObservedAt: observation.observedAt,
      confirmedAt: observation.observedAt,
      confirmationDelaySeconds: 0,
      clusterDistanceKm: distanceKm,
      productionCoordinateSwitchAllowed: false,
      reason: 'new_region_residual_supported_candidate',
    );
  }

  SourceCandidateRegionDecision _pendingDecision(
    SourceCandidateRegionObservation observation,
    _PendingRegion pending,
    double clusterDistanceKm,
  ) {
    return SourceCandidateRegionDecision(
      status: SourceCandidateRegionStatus.pending,
      eventId: observation.eventId,
      observedAt: observation.observedAt,
      latitude: pending.latitude,
      longitude: pending.longitude,
      firstObservedAt: pending.firstObservedAt,
      confirmedAt: null,
      confirmationDelaySeconds: null,
      clusterDistanceKm: clusterDistanceKm,
      productionCoordinateSwitchAllowed: false,
      reason: 'awaiting_same_region_residual_support',
    );
  }
}

class _PendingRegion {
  final String eventId;
  final DateTime firstObservedAt;
  DateTime lastObservedAt;
  final double latitude;
  final double longitude;
  final SourceCandidateLocalSupportSnapshot? initialLocalSupportSnapshot;
  SourceCandidateLocalSupportSnapshot? latestLocalSupportSnapshot;

  _PendingRegion({
    required this.eventId,
    required this.firstObservedAt,
    required this.lastObservedAt,
    required this.latitude,
    required this.longitude,
    required this.initialLocalSupportSnapshot,
    required this.latestLocalSupportSnapshot,
  });

  factory _PendingRegion.fromObservation(
    SourceCandidateRegionObservation observation,
  ) {
    return _PendingRegion(
      eventId: observation.eventId,
      firstObservedAt: observation.observedAt,
      lastObservedAt: observation.observedAt,
      latitude: observation.latitude,
      longitude: observation.longitude,
      initialLocalSupportSnapshot: observation.localSupportSnapshot,
      latestLocalSupportSnapshot: observation.localSupportSnapshot,
    );
  }
}

class _CandidateCorrection {
  final double latitude;
  final double longitude;

  const _CandidateCorrection({required this.latitude, required this.longitude});
}

class _DiagnosticPick {
  final double latitude;
  final double longitude;
  final double? value;

  const _DiagnosticPick({
    required this.latitude,
    required this.longitude,
    required this.value,
  });
}

class _ResidualLocationDiagnostics {
  final double rankInversionRate;
  final double? attenuationRms;

  const _ResidualLocationDiagnostics({
    required this.rankInversionRate,
    required this.attenuationRms,
  });

  factory _ResidualLocationDiagnostics.forLocation({
    required double latitude,
    required double longitude,
    required List<_DiagnosticPick> picks,
    required SourceCandidateResidualGateConfig config,
  }) {
    final distances = [
      for (final pick in picks)
        _distanceKm(latitude, longitude, pick.latitude, pick.longitude),
    ];
    return _ResidualLocationDiagnostics(
      rankInversionRate: _rankInversionRate(picks, distances),
      attenuationRms: _attenuationRms(picks, distances, config),
    );
  }
}

_CandidateCorrection? _candidateCorrection(Map<String, Object?> diagnostics) {
  final corrections = _map(diagnostics['candidate_corrections']);
  final guard = _map(corrections['one_sided_boundary_centroid_guard']);
  final latitude = _number(guard['latitude']);
  final longitude = _number(guard['longitude']);
  if (latitude == null || longitude == null) return null;
  return _CandidateCorrection(latitude: latitude, longitude: longitude);
}

List<_DiagnosticPick> _diagnosticPicks(Map<String, Object?> diagnostics) {
  final result = <_DiagnosticPick>[];
  for (final rawPick in _list(diagnostics['top_timing_picks'])) {
    final pick = _map(rawPick);
    final latitude = _number(pick['latitude']);
    final longitude = _number(pick['longitude']);
    if (latitude == null || longitude == null) continue;
    result.add(
      _DiagnosticPick(
        latitude: latitude,
        longitude: longitude,
        value: _number(pick['value']),
      ),
    );
  }
  return result;
}

double _rankInversionRate(List<_DiagnosticPick> picks, List<double> distances) {
  var comparable = 0;
  var inversions = 0;
  for (var i = 0; i < picks.length; i++) {
    final leftValue = picks[i].value;
    if (leftValue == null || !leftValue.isFinite) continue;
    for (var j = i + 1; j < picks.length; j++) {
      final rightValue = picks[j].value;
      if (rightValue == null || !rightValue.isFinite) continue;
      final valueDiff = leftValue - rightValue;
      if (valueDiff.abs() < 0.05) continue;
      comparable++;
      final distanceDiff = distances[i] - distances[j];
      if ((valueDiff > 0 && distanceDiff > 0) ||
          (valueDiff < 0 && distanceDiff < 0)) {
        inversions++;
      }
    }
  }
  return comparable == 0 ? 0 : inversions / comparable;
}

double? _attenuationRms(
  List<_DiagnosticPick> picks,
  List<double> distances,
  SourceCandidateResidualGateConfig config,
) {
  final terms = <double>[];
  for (var i = 0; i < picks.length; i++) {
    final value = picks[i].value;
    if (value == null || !value.isFinite) continue;
    terms.add(
      value +
          config.attenuationLogDistanceCoefficient *
              _log10(distances[i] + config.attenuationNearDistanceKm),
    );
  }
  if (terms.isEmpty) return null;
  final center = _median(terms);
  final square = terms.fold<double>(
    0,
    (total, value) => total + math.pow(value - center, 2).toDouble(),
  );
  return math.sqrt(square / terms.length);
}

double _median(List<double> values) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) return double.nan;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _log10(double value) => math.log(value) / math.ln10;

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double? _delta(double? candidate, double? baseline) {
  if (candidate == null || baseline == null) return null;
  return candidate - baseline;
}

double? _ratio(double? candidate, double? baseline) {
  if (candidate == null || baseline == null || baseline == 0) return null;
  return candidate / baseline;
}

double _distanceKm(double latA, double lngA, double latB, double lngB) {
  const radiusKm = 6371.0;
  final lat1 = _radians(latA);
  final lat2 = _radians(latB);
  final deltaLat = lat2 - lat1;
  final deltaLng = _radians(lngB - lngA);
  final sinLat = math.sin(deltaLat / 2);
  final sinLng = math.sin(deltaLng / 2);
  final h = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
  return 2 * radiusKm * math.asin(math.sqrt(h.clamp(0, 1)));
}

double _radians(double degrees) => degrees * math.pi / 180.0;
