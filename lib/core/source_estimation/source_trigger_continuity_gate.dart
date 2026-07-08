import 'dart:math' as math;

import '../event_detection/event_detection_models.dart';
import 'jma2001_travel_time_approximation.dart';
import 'source_estimation_models.dart';

class SourceTriggerContinuityConfig {
  final Duration retentionWindow;
  final double maxReplacementCentroidDistanceKm;
  final double maxNearbyReplacementCentroidDistanceKm;
  final double maxDetectionIdAssignmentResidualSeconds;
  final double maxDetectionIdAssignmentNeighborDistanceKm;
  final int minPreviousMembers;
  final int minReplacementMemberOverlap;

  const SourceTriggerContinuityConfig({
    this.retentionWindow = const Duration(seconds: 120),
    this.maxReplacementCentroidDistanceKm = 180,
    this.maxNearbyReplacementCentroidDistanceKm = 60,
    this.maxDetectionIdAssignmentResidualSeconds = 6,
    this.maxDetectionIdAssignmentNeighborDistanceKm = 35,
    this.minPreviousMembers = 3,
    this.minReplacementMemberOverlap = 2,
  });
}

class SourceTriggerContinuityDecision {
  final String? effectiveEventId;
  final List<String> effectiveMemberStationIds;
  final List<String> currentMemberStationIds;
  final bool heldReplacement;
  final Map<String, Object?> metadata;

  const SourceTriggerContinuityDecision({
    required this.effectiveEventId,
    required this.effectiveMemberStationIds,
    required this.currentMemberStationIds,
    required this.heldReplacement,
    required this.metadata,
  });
}

class SourceTriggerContinuityGate {
  final SourceTriggerContinuityConfig config;

  String? _acceptedEventId;
  final Set<String> _acceptedMemberStationIds = <String>{};
  DateTime? _lastAcceptedAt;
  double? _anchorLatitude;
  double? _anchorLongitude;

  SourceTriggerContinuityGate({
    this.config = const SourceTriggerContinuityConfig(),
  });

  void reset() {
    _acceptedEventId = null;
    _acceptedMemberStationIds.clear();
    _lastAcceptedAt = null;
    _anchorLatitude = null;
    _anchorLongitude = null;
  }

  SourceTriggerContinuityDecision update({
    required EventDetection detection,
    required Iterable<StationTriggerSnapshot> stations,
    required DateTime observedAt,
    SourceEstimate? activeEstimate,
  }) {
    final expired = _expireIfNeeded(observedAt);
    if (detection.state == EventDetectionState.ended ||
        detection.state == EventDetectionState.rejected ||
        detection.state == EventDetectionState.idle) {
      return SourceTriggerContinuityDecision(
        effectiveEventId: _acceptedEventId,
        effectiveMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        currentMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        heldReplacement: false,
        metadata: _metadata(
          rawEventId: detection.eventId,
          effectiveEventId: _acceptedEventId,
          heldReplacement: false,
          retentionExpired: expired,
        ),
      );
    }

    final rawEventId = detection.eventId;
    final rawMembers = detection.memberStationIds.toSet();
    final rawCentroid = _centroid(rawMembers, stations);
    final anchor = _anchor(activeEstimate);

    if (_acceptedEventId != null &&
        rawEventId != null &&
        rawEventId != _acceptedEventId &&
        _shouldHoldReplacement(
          observedAt: observedAt,
          rawMembers: rawMembers,
          rawCentroid: rawCentroid,
          anchor: anchor,
        )) {
      final distanceKm = rawCentroid == null || anchor == null
          ? null
          : _haversineKm(
              rawCentroid.latitude,
              rawCentroid.longitude,
              anchor.latitude,
              anchor.longitude,
            );
      return SourceTriggerContinuityDecision(
        effectiveEventId: _acceptedEventId,
        effectiveMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        currentMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        heldReplacement: true,
        metadata: _metadata(
          rawEventId: rawEventId,
          effectiveEventId: _acceptedEventId,
          heldReplacement: true,
          replacementDistanceKm: distanceKm,
          rawMemberCount: rawMembers.length,
          replacementMemberOverlap: _replacementOverlap(rawMembers),
        ),
      );
    }

    if (_acceptedEventId != null &&
        rawEventId != null &&
        rawEventId == _acceptedEventId &&
        _shouldHoldReplacement(
          observedAt: observedAt,
          rawMembers: rawMembers,
          rawCentroid: rawCentroid,
          anchor: anchor,
        )) {
      final distanceKm = rawCentroid == null || anchor == null
          ? null
          : _haversineKm(
              rawCentroid.latitude,
              rawCentroid.longitude,
              anchor.latitude,
              anchor.longitude,
            );
      return SourceTriggerContinuityDecision(
        effectiveEventId: _acceptedEventId,
        effectiveMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        currentMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        heldReplacement: true,
        metadata: _metadata(
          rawEventId: rawEventId,
          effectiveEventId: _acceptedEventId,
          heldReplacement: true,
          replacementDistanceKm: distanceKm,
          rawMemberCount: rawMembers.length,
          replacementMemberOverlap: _replacementOverlap(rawMembers),
          holdReason: 'same_event_member_replacement',
        ),
      );
    }

    final assignment = _assignCurrentDetectionIdMembers(
      rawMembers: rawMembers,
      stations: stations,
      activeEstimate: activeEstimate,
    );
    if (_acceptedEventId != null &&
        rawEventId == _acceptedEventId &&
        rawMembers.isNotEmpty &&
        assignment.memberStationIds.isEmpty) {
      return SourceTriggerContinuityDecision(
        effectiveEventId: _acceptedEventId,
        effectiveMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        currentMemberStationIds: List<String>.unmodifiable(
          _acceptedMemberStationIds.toList()..sort(),
        ),
        heldReplacement: true,
        metadata: _metadata(
          rawEventId: rawEventId,
          effectiveEventId: _acceptedEventId,
          heldReplacement: true,
          rawMemberCount: rawMembers.length,
          replacementMemberOverlap: _replacementOverlap(rawMembers),
          holdReason: 'same_event_detection_id_assignment_rejected',
          detectionIdAssignedCount: assignment.memberStationIds.length,
          detectionIdRejectedCount: assignment.rejectedStationIds.length,
          detectionIdRejectedStationIds: assignment.rejectedStationIds,
          detectionIdAssignmentModel: assignment.model,
        ),
      );
    }

    if (rawEventId != null && rawEventId != _acceptedEventId) {
      _acceptedEventId = rawEventId;
      _acceptedMemberStationIds.clear();
    }
    _acceptedMemberStationIds.addAll(assignment.memberStationIds);
    _lastAcceptedAt = observedAt;
    _updateAnchor(
      _centroid(assignment.memberStationIds, stations),
      activeEstimate,
    );

    return SourceTriggerContinuityDecision(
      effectiveEventId: _acceptedEventId,
      effectiveMemberStationIds: List<String>.unmodifiable(
        _acceptedMemberStationIds.toList()..sort(),
      ),
      currentMemberStationIds: List<String>.unmodifiable(
        assignment.memberStationIds.toList()..sort(),
      ),
      heldReplacement: false,
      metadata: _metadata(
        rawEventId: rawEventId,
        effectiveEventId: _acceptedEventId,
        heldReplacement: false,
        rawMemberCount: rawMembers.length,
        replacementMemberOverlap: _replacementOverlap(rawMembers),
        detectionIdAssignedCount: assignment.memberStationIds.length,
        detectionIdRejectedCount: assignment.rejectedStationIds.length,
        detectionIdRejectedStationIds: assignment.rejectedStationIds,
        detectionIdAssignmentModel: assignment.model,
      ),
    );
  }

  bool _expireIfNeeded(DateTime observedAt) {
    final lastAcceptedAt = _lastAcceptedAt;
    if (lastAcceptedAt == null ||
        !observedAt.isAfter(lastAcceptedAt) ||
        observedAt.difference(lastAcceptedAt) <= config.retentionWindow) {
      return false;
    }
    reset();
    return true;
  }

  bool _shouldHoldReplacement({
    required DateTime observedAt,
    required Set<String> rawMembers,
    required _Centroid? rawCentroid,
    required _Centroid? anchor,
  }) {
    if (_acceptedMemberStationIds.length < config.minPreviousMembers) {
      return false;
    }
    final lastAcceptedAt = _lastAcceptedAt;
    if (lastAcceptedAt == null ||
        observedAt.difference(lastAcceptedAt) > config.retentionWindow) {
      return false;
    }
    if (rawCentroid == null || anchor == null) return false;
    final distanceKm = _haversineKm(
      rawCentroid.latitude,
      rawCentroid.longitude,
      anchor.latitude,
      anchor.longitude,
    );
    if (distanceKm > config.maxReplacementCentroidDistanceKm) {
      return true;
    }
    final overlap = _replacementOverlap(rawMembers);
    return overlap < config.minReplacementMemberOverlap &&
        distanceKm > config.maxNearbyReplacementCentroidDistanceKm;
  }

  int _replacementOverlap(Set<String> rawMembers) =>
      rawMembers.intersection(_acceptedMemberStationIds).length;

  _DetectionIdAssignment _assignCurrentDetectionIdMembers({
    required Set<String> rawMembers,
    required Iterable<StationTriggerSnapshot> stations,
    required SourceEstimate? activeEstimate,
  }) {
    if (rawMembers.isEmpty) {
      return const _DetectionIdAssignment(
        memberStationIds: <String>{},
        rejectedStationIds: <String>[],
        model: 'empty_raw_detection_members',
      );
    }
    if (_acceptedEventId == null || _acceptedMemberStationIds.isEmpty) {
      return _DetectionIdAssignment(
        memberStationIds: rawMembers,
        rejectedStationIds: const <String>[],
        model: 'initial_detection_id_members_from_event_detector',
      );
    }
    final estimate = activeEstimate;
    if (estimate == null ||
        estimate.originTime == null ||
        estimate.depthKm == null ||
        !estimate.latitude.isFinite ||
        !estimate.longitude.isFinite ||
        !estimate.depthKm!.isFinite) {
      return _DetectionIdAssignment(
        memberStationIds: rawMembers,
        rejectedStationIds: const <String>[],
        model: 'no_source_cache_for_detection_id_assignment',
      );
    }

    final byCode = {for (final station in stations) station.code: station};
    final acceptedStations = _acceptedMemberStationIds
        .map((id) => byCode[id])
        .whereType<StationTriggerSnapshot>()
        .toList(growable: false);
    final assigned = <String>{};
    final rejected = <String>[];
    for (final id in rawMembers) {
      if (_acceptedMemberStationIds.contains(id)) {
        assigned.add(id);
        continue;
      }
      final station = byCode[id];
      if (station == null ||
          station.latitude == null ||
          station.longitude == null ||
          !station.latitude!.isFinite ||
          !station.longitude!.isFinite) {
        rejected.add(id);
        continue;
      }
      if (_nearestAcceptedDistanceKm(station, acceptedStations) <=
          config.maxDetectionIdAssignmentNeighborDistanceKm) {
        assigned.add(id);
        continue;
      }
      final residual = _sourceCachePhaseResidualSeconds(station, estimate);
      if (residual != null &&
          residual <= config.maxDetectionIdAssignmentResidualSeconds) {
        assigned.add(id);
        continue;
      }
      rejected.add(id);
    }

    return _DetectionIdAssignment(
      memberStationIds: assigned,
      rejectedStationIds: List<String>.unmodifiable(rejected..sort()),
      model:
          'kotoho7_detection_id_assignment_proxy_source_cache_phase_or_neighbor_v1',
    );
  }

  double _nearestAcceptedDistanceKm(
    StationTriggerSnapshot station,
    List<StationTriggerSnapshot> acceptedStations,
  ) {
    if (acceptedStations.isEmpty ||
        station.latitude == null ||
        station.longitude == null) {
      return double.infinity;
    }
    var best = double.infinity;
    for (final accepted in acceptedStations) {
      final latitude = accepted.latitude;
      final longitude = accepted.longitude;
      if (latitude == null || longitude == null) continue;
      final distance = _haversineKm(
        station.latitude!,
        station.longitude!,
        latitude,
        longitude,
      );
      if (distance < best) best = distance;
    }
    return best;
  }

  double? _sourceCachePhaseResidualSeconds(
    StationTriggerSnapshot station,
    SourceEstimate estimate,
  ) {
    final originTime = estimate.originTime;
    final depthKm = estimate.depthKm;
    final stationTime =
        station.firstTriggerInterval?.end ?? station.firstRiseInterval?.end;
    final latitude = station.latitude;
    final longitude = station.longitude;
    if (originTime == null ||
        depthKm == null ||
        stationTime == null ||
        latitude == null ||
        longitude == null) {
      return null;
    }
    final observedTravelSeconds =
        stationTime.difference(originTime).inMilliseconds / 1000.0;
    if (!observedTravelSeconds.isFinite || observedTravelSeconds < 0) {
      return null;
    }
    final epicentralDistanceKm = _haversineKm(
      estimate.latitude,
      estimate.longitude,
      latitude,
      longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      epicentralDistanceKm * epicentralDistanceKm + depthKm * depthKm,
    );
    final pTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: true,
    );
    final sTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: false,
    );
    return math.min(
      (observedTravelSeconds - pTravel).abs(),
      (observedTravelSeconds - sTravel).abs(),
    );
  }

  _Centroid? _anchor(SourceEstimate? activeEstimate) {
    if (activeEstimate != null) {
      return _Centroid(activeEstimate.latitude, activeEstimate.longitude);
    }
    final latitude = _anchorLatitude;
    final longitude = _anchorLongitude;
    if (latitude == null || longitude == null) return null;
    return _Centroid(latitude, longitude);
  }

  void _updateAnchor(_Centroid? rawCentroid, SourceEstimate? activeEstimate) {
    if (activeEstimate != null) {
      _anchorLatitude = activeEstimate.latitude;
      _anchorLongitude = activeEstimate.longitude;
      return;
    }
    if (rawCentroid != null) {
      _anchorLatitude = rawCentroid.latitude;
      _anchorLongitude = rawCentroid.longitude;
    }
  }

  Map<String, Object?> _metadata({
    required String? rawEventId,
    required String? effectiveEventId,
    required bool heldReplacement,
    double? replacementDistanceKm,
    int? rawMemberCount,
    int? replacementMemberOverlap,
    bool retentionExpired = false,
    String? holdReason,
    int? detectionIdAssignedCount,
    int? detectionIdRejectedCount,
    List<String>? detectionIdRejectedStationIds,
    String? detectionIdAssignmentModel,
  }) {
    return {
      'source_trigger_continuity_effective_event_id': effectiveEventId,
      'source_trigger_continuity_raw_event_id': rawEventId,
      'source_trigger_continuity_held_replacement': heldReplacement,
      'source_trigger_continuity_hold_reason': holdReason,
      'source_trigger_continuity_member_count':
          _acceptedMemberStationIds.length,
      'source_trigger_continuity_raw_member_count': rawMemberCount,
      'source_trigger_continuity_replacement_member_overlap':
          replacementMemberOverlap,
      'source_trigger_continuity_replacement_distance_km':
          replacementDistanceKm,
      'source_trigger_continuity_retention_expired': retentionExpired,
      'source_trigger_continuity_anchor_latitude': _anchorLatitude,
      'source_trigger_continuity_anchor_longitude': _anchorLongitude,
      'source_trigger_continuity_max_replacement_distance_km':
          config.maxReplacementCentroidDistanceKm,
      'source_trigger_continuity_max_nearby_replacement_distance_km':
          config.maxNearbyReplacementCentroidDistanceKm,
      'source_trigger_continuity_min_replacement_member_overlap':
          config.minReplacementMemberOverlap,
      'source_trigger_continuity_retention_seconds':
          config.retentionWindow.inSeconds,
      'source_trigger_detection_id_assignment_model':
          detectionIdAssignmentModel,
      'source_trigger_detection_id_assigned_count': detectionIdAssignedCount,
      'source_trigger_detection_id_rejected_count': detectionIdRejectedCount,
      'source_trigger_detection_id_rejected_station_ids':
          detectionIdRejectedStationIds,
      'source_trigger_detection_id_max_phase_residual_s':
          config.maxDetectionIdAssignmentResidualSeconds,
      'source_trigger_detection_id_max_neighbor_distance_km':
          config.maxDetectionIdAssignmentNeighborDistanceKm,
    };
  }
}

_Centroid? _centroid(
  Set<String> stationIds,
  Iterable<StationTriggerSnapshot> stations,
) {
  final byCode = {for (final station in stations) station.code: station};
  var latitudeSum = 0.0;
  var longitudeSum = 0.0;
  var count = 0;
  for (final id in stationIds) {
    final station = byCode[id];
    final latitude = station?.latitude;
    final longitude = station?.longitude;
    if (latitude == null || longitude == null) continue;
    latitudeSum += latitude;
    longitudeSum += longitude;
    count++;
  }
  if (count == 0) return null;
  return _Centroid(latitudeSum / count, longitudeSum / count);
}

double _haversineKm(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusKm = 6371.0;
  final latA = latitudeA * math.pi / 180;
  final latB = latitudeB * math.pi / 180;
  final deltaLat = latB - latA;
  final deltaLng = (longitudeB - longitudeA) * math.pi / 180;
  final sinLat = math.sin(deltaLat / 2);
  final sinLng = math.sin(deltaLng / 2);
  final h = sinLat * sinLat + math.cos(latA) * math.cos(latB) * sinLng * sinLng;
  return 2 * earthRadiusKm * math.asin(math.sqrt(h.clamp(0, 1)));
}

class _Centroid {
  final double latitude;
  final double longitude;

  const _Centroid(this.latitude, this.longitude);
}

class _DetectionIdAssignment {
  final Set<String> memberStationIds;
  final List<String> rejectedStationIds;
  final String model;

  const _DetectionIdAssignment({
    required this.memberStationIds,
    required this.rejectedStationIds,
    required this.model,
  });
}
