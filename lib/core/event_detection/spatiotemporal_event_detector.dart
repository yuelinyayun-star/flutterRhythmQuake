import 'dart:math' as math;

import 'event_detection_models.dart';

class SpatiotemporalEventDetectorConfig {
  final int candidateMinStations;
  final int confirmedMinStations;
  final double maxLinkDistanceKm;
  final double? temporalBridgeDistanceKm;
  final Duration temporalBridgeMaxGap;
  final Duration candidateTimeout;
  final Duration endDelay;
  final double? maxInitialConfirmationDiameterKm;
  final int confirmationPersistenceFrames;
  final bool quarantineRejectedMembersUntilClear;

  const SpatiotemporalEventDetectorConfig({
    this.candidateMinStations = 4,
    this.confirmedMinStations = 6,
    this.maxLinkDistanceKm = 80,
    this.temporalBridgeDistanceKm,
    this.temporalBridgeMaxGap = const Duration(seconds: 8),
    this.candidateTimeout = const Duration(seconds: 8),
    this.endDelay = const Duration(seconds: 6),
    this.maxInitialConfirmationDiameterKm,
    this.confirmationPersistenceFrames = 1,
    this.quarantineRejectedMembersUntilClear = false,
  }) : assert(
         temporalBridgeDistanceKm == null ||
             temporalBridgeDistanceKm >= maxLinkDistanceKm,
       ),
       assert(
         maxInitialConfirmationDiameterKm == null ||
             maxInitialConfirmationDiameterKm > 0,
       ),
       assert(confirmationPersistenceFrames > 0);
}

class NetworkAssociationDiagnostics {
  final int triggeredStationCount;
  final int componentCount;
  final List<int> componentSizes;
  final int largestComponentSize;
  final double largestComponentDiameterKm;
  final double largestComponentQualityWeightedSupport;
  final double? largestComponentTriggerTimeSpanSeconds;
  final List<String> largestComponentStationIds;
  final Map<String, ObservationTimeInterval> largestComponentTriggerIntervals;
  final int largestComponentStrongEdgeCount;
  final int largestComponentWeakEdgeCount;
  final double? largestComponentCentroidLatitude;
  final double? largestComponentCentroidLongitude;

  const NetworkAssociationDiagnostics({
    required this.triggeredStationCount,
    required this.componentCount,
    required this.componentSizes,
    required this.largestComponentSize,
    required this.largestComponentDiameterKm,
    required this.largestComponentQualityWeightedSupport,
    required this.largestComponentTriggerTimeSpanSeconds,
    required this.largestComponentStationIds,
    required this.largestComponentTriggerIntervals,
    required this.largestComponentStrongEdgeCount,
    required this.largestComponentWeakEdgeCount,
    required this.largestComponentCentroidLatitude,
    required this.largestComponentCentroidLongitude,
  });

  Map<String, Object?> toJson() => {
    'triggeredStationCount': triggeredStationCount,
    'componentCount': componentCount,
    'componentSizes': componentSizes,
    'largestComponentSize': largestComponentSize,
    'largestComponentDiameterKm': largestComponentDiameterKm,
    'largestComponentQualityWeightedSupport':
        largestComponentQualityWeightedSupport,
    'largestComponentTriggerTimeSpanSeconds':
        largestComponentTriggerTimeSpanSeconds,
    'largestComponentStationIds': largestComponentStationIds,
    'largestComponentTriggerIntervals': {
      for (final entry in largestComponentTriggerIntervals.entries)
        entry.key: {
          'start': entry.value.start.toIso8601String(),
          'end': entry.value.end.toIso8601String(),
        },
    },
    'largestComponentStrongEdgeCount': largestComponentStrongEdgeCount,
    'largestComponentWeakEdgeCount': largestComponentWeakEdgeCount,
    'largestComponentCentroidLatitude': largestComponentCentroidLatitude,
    'largestComponentCentroidLongitude': largestComponentCentroidLongitude,
  };
}

class SpatiotemporalEventDetector implements EventDetector {
  @override
  final String detectorId;
  final String sourceId;
  final SpatiotemporalEventDetectorConfig config;

  String? _eventId;
  DateTime? _startedAt;
  DateTime? _lastSupportedAt;
  EventDetectionState _state = EventDetectionState.idle;
  bool _resetAfterTerminal = false;
  int _confirmationStreak = 0;
  final Set<String> _rejectedMemberStationIds = <String>{};
  final Set<String> _pendingConfirmationMemberIds = <String>{};
  bool _candidateHadCoherenceRejection = false;

  SpatiotemporalEventDetector({
    this.detectorId = 'spatiotemporal_event_detector_v0',
    this.sourceId = 'nied_gif',
    this.config = const SpatiotemporalEventDetectorConfig(),
  });

  @override
  EventDetection update({
    required DateTime observedAt,
    required List<StationTriggerSnapshot> stations,
  }) {
    if (_resetAfterTerminal) {
      final rejectedMembers = config.quarantineRejectedMembersUntilClear
          ? Set<String>.from(_rejectedMemberStationIds)
          : const <String>{};
      reset();
      _rejectedMemberStationIds.addAll(rejectedMembers);
    }

    final triggered = stations
        .where(
          (station) =>
              station.state == StationTriggerState.triggered ||
              station.state == StationTriggerState.strong,
        )
        .where(
          (station) =>
              station.latitude != null &&
              station.longitude != null &&
              station.latitude!.isFinite &&
              station.longitude!.isFinite,
        )
        .toList(growable: false);
    final analysis = _analyzeTriggeredStations(triggered);
    final cluster = analysis.largestComponent;
    final diagnostics = analysis.diagnostics;
    final supportCount = cluster.length;
    final rejectedMembersStillActive =
        config.quarantineRejectedMembersUntilClear
        ? triggered
              .where(
                (station) =>
                    _rejectedMemberStationIds.contains(station.stationId),
              )
              .length
        : 0;
    if (rejectedMembersStillActive > 0) {
      return EventDetection(
        detectorId: detectorId,
        sourceId: sourceId,
        eventId: null,
        state: EventDetectionState.idle,
        observedAt: observedAt,
        memberStationIds: const [],
        reasonCodes: const {'rejected_cluster_members_still_active'},
        metadata: {
          'network_support_count': supportCount,
          'rejected_member_active_count': rejectedMembersStillActive,
          ...diagnostics.toJson(),
        },
      );
    }
    _rejectedMemberStationIds.clear();
    final hasStrong = cluster.any(
      (station) => station.state == StationTriggerState.strong,
    );

    if (supportCount >= config.confirmedMinStations) {
      _ensureEvent(observedAt);
      final alreadyConfirmed =
          _state == EventDetectionState.confirmed ||
          _state == EventDetectionState.strong;
      final compactCore = alreadyConfirmed
          ? cluster
          : _findCompactCore(
              cluster,
              requiredSize: config.confirmedMinStations,
              maxDiameterKm: config.maxInitialConfirmationDiameterKm,
              preferredStationIds: _pendingConfirmationMemberIds,
            );
      final coherentForInitialConfirmation =
          alreadyConfirmed ||
          (compactCore != null && !_candidateHadCoherenceRejection);
      final confirmationCluster = compactCore ?? cluster;
      if (alreadyConfirmed || coherentForInitialConfirmation) {
        final confirmationIds = confirmationCluster
            .map((station) => station.stationId)
            .toSet();
        final stableOverlap =
            _pendingConfirmationMemberIds.isEmpty ||
            _pendingConfirmationMemberIds
                    .intersection(confirmationIds)
                    .length >=
                config.candidateMinStations;
        _confirmationStreak = alreadyConfirmed
            ? _confirmationStreak + 1
            : stableOverlap
            ? _confirmationStreak + 1
            : 1;
        _pendingConfirmationMemberIds
          ..clear()
          ..addAll(confirmationIds);
        if (alreadyConfirmed ||
            _confirmationStreak >= config.confirmationPersistenceFrames) {
          _lastSupportedAt = observedAt;
          _state = hasStrong
              ? EventDetectionState.strong
              : EventDetectionState.confirmed;
          return _detection(
            observedAt,
            confirmationCluster,
            diagnostics: diagnostics,
            reasonCodes: const {'network_cluster_confirmed'},
          );
        }
        _state = EventDetectionState.candidate;
        return _candidateDetection(
          observedAt,
          confirmationCluster,
          diagnostics: diagnostics,
          reasonCodes: const {'confirmation_persistence_pending'},
        );
      }
      _confirmationStreak = 0;
      _pendingConfirmationMemberIds.clear();
      _candidateHadCoherenceRejection = true;
      _state = EventDetectionState.candidate;
      return _candidateDetection(
        observedAt,
        cluster,
        diagnostics: diagnostics,
        reasonCodes: const {'initial_confirmation_diameter_rejected'},
      );
    }

    if (supportCount >= config.candidateMinStations) {
      _ensureEvent(observedAt);
      _confirmationStreak = 0;
      _pendingConfirmationMemberIds.clear();
      _lastSupportedAt = observedAt;
      if (_state != EventDetectionState.confirmed &&
          _state != EventDetectionState.strong) {
        _state = EventDetectionState.candidate;
      }
      return _candidateDetection(
        observedAt,
        cluster,
        diagnostics: diagnostics,
        reasonCodes: const {'network_cluster_candidate'},
      );
    }

    if (_state == EventDetectionState.candidate) {
      final startedAt = _startedAt!;
      if (observedAt.difference(startedAt) >= config.candidateTimeout) {
        _state = EventDetectionState.rejected;
        _resetAfterTerminal = true;
        return _detection(
          observedAt,
          cluster,
          diagnostics: diagnostics,
          endedAt: observedAt,
          reasonCodes: const {'candidate_timeout'},
        );
      }
      return _detection(
        observedAt,
        cluster,
        diagnostics: diagnostics,
        reasonCodes: const {'candidate_waiting_for_support'},
      );
    }

    if (_state == EventDetectionState.confirmed ||
        _state == EventDetectionState.strong) {
      final lastSupportedAt = _lastSupportedAt ?? _startedAt!;
      if (observedAt.difference(lastSupportedAt) >= config.endDelay) {
        _state = EventDetectionState.ended;
        _resetAfterTerminal = true;
        return _detection(
          observedAt,
          cluster,
          diagnostics: diagnostics,
          endedAt: observedAt,
          reasonCodes: const {'network_support_ended'},
        );
      }
      return _detection(
        observedAt,
        cluster,
        diagnostics: diagnostics,
        reasonCodes: const {'confirmed_event_coasting'},
      );
    }

    return EventDetection(
      detectorId: detectorId,
      sourceId: sourceId,
      eventId: null,
      state: EventDetectionState.idle,
      observedAt: observedAt,
      memberStationIds: const [],
      reasonCodes: const {'insufficient_network_support'},
      metadata: {
        'network_support_count': supportCount,
        ...diagnostics.toJson(),
      },
    );
  }

  NetworkAssociationDiagnostics diagnose(
    List<StationTriggerSnapshot> stations,
  ) {
    final triggered = stations
        .where(
          (station) =>
              station.state == StationTriggerState.triggered ||
              station.state == StationTriggerState.strong,
        )
        .where(
          (station) =>
              station.latitude != null &&
              station.longitude != null &&
              station.latitude!.isFinite &&
              station.longitude!.isFinite,
        )
        .toList(growable: false);
    return _analyzeTriggeredStations(triggered).diagnostics;
  }

  @override
  void reset() {
    _eventId = null;
    _startedAt = null;
    _lastSupportedAt = null;
    _state = EventDetectionState.idle;
    _resetAfterTerminal = false;
    _confirmationStreak = 0;
    _rejectedMemberStationIds.clear();
    _pendingConfirmationMemberIds.clear();
    _candidateHadCoherenceRejection = false;
  }

  void _ensureEvent(DateTime observedAt) {
    _eventId ??= '$sourceId-${observedAt.toIso8601String()}';
    _startedAt ??= observedAt;
  }

  EventDetection _detection(
    DateTime observedAt,
    List<StationTriggerSnapshot> cluster, {
    required NetworkAssociationDiagnostics diagnostics,
    DateTime? endedAt,
    required Set<String> reasonCodes,
  }) {
    final maxIntensity = cluster
        .map((station) => station.intensity)
        .whereType<double>()
        .fold<double?>(null, (current, value) {
          if (current == null || value > current) return value;
          return current;
        });
    return EventDetection(
      detectorId: detectorId,
      sourceId: sourceId,
      eventId: _eventId,
      state: _state,
      observedAt: observedAt,
      startedAt: _startedAt,
      updatedAt: observedAt,
      endedAt: endedAt,
      memberStationIds: cluster
          .map((station) => station.stationId)
          .toList(growable: false),
      detectionScore: cluster.length.toDouble(),
      maxIntensity: maxIntensity?.round() ?? -1,
      reasonCodes: reasonCodes,
      metadata: {
        'network_support_count': cluster.length,
        'max_link_distance_km': config.maxLinkDistanceKm,
        'max_initial_confirmation_diameter_km':
            config.maxInitialConfirmationDiameterKm,
        'confirmation_persistence_frames': config.confirmationPersistenceFrames,
        'confirmation_streak': _confirmationStreak,
        'candidate_had_coherence_rejection': _candidateHadCoherenceRejection,
        'temporal_bridge_distance_km': config.temporalBridgeDistanceKm,
        'temporal_bridge_max_gap_seconds':
            config.temporalBridgeMaxGap.inMilliseconds / 1000.0,
        ...diagnostics.toJson(),
      },
    );
  }

  EventDetection _candidateDetection(
    DateTime observedAt,
    List<StationTriggerSnapshot> cluster, {
    required NetworkAssociationDiagnostics diagnostics,
    required Set<String> reasonCodes,
  }) {
    final startedAt = _startedAt!;
    if (_state == EventDetectionState.candidate &&
        observedAt.difference(startedAt) >= config.candidateTimeout) {
      if (config.quarantineRejectedMembersUntilClear) {
        _rejectedMemberStationIds
          ..clear()
          ..addAll(cluster.map((station) => station.stationId));
      }
      _state = EventDetectionState.rejected;
      _resetAfterTerminal = true;
      return _detection(
        observedAt,
        cluster,
        diagnostics: diagnostics,
        endedAt: observedAt,
        reasonCodes: {...reasonCodes, 'candidate_timeout'},
      );
    }
    return _detection(
      observedAt,
      cluster,
      diagnostics: diagnostics,
      reasonCodes: reasonCodes,
    );
  }

  _NetworkAssociationAnalysis _analyzeTriggeredStations(
    List<StationTriggerSnapshot> stations,
  ) {
    if (stations.isEmpty) {
      return const _NetworkAssociationAnalysis(
        largestComponent: [],
        diagnostics: NetworkAssociationDiagnostics(
          triggeredStationCount: 0,
          componentCount: 0,
          componentSizes: [],
          largestComponentSize: 0,
          largestComponentDiameterKm: 0,
          largestComponentQualityWeightedSupport: 0,
          largestComponentTriggerTimeSpanSeconds: null,
          largestComponentStationIds: [],
          largestComponentTriggerIntervals: {},
          largestComponentStrongEdgeCount: 0,
          largestComponentWeakEdgeCount: 0,
          largestComponentCentroidLatitude: null,
          largestComponentCentroidLongitude: null,
        ),
      );
    }
    final visited = <int>{};
    var largest = <StationTriggerSnapshot>[];
    final componentSizes = <int>[];

    for (var start = 0; start < stations.length; start++) {
      if (!visited.add(start)) continue;
      final queue = <int>[start];
      final component = <StationTriggerSnapshot>[];
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        component.add(stations[current]);
        for (var next = 0; next < stations.length; next++) {
          if (visited.contains(next)) continue;
          if (_stationsAreLinked(stations[current], stations[next])) {
            visited.add(next);
            queue.add(next);
          }
        }
      }
      componentSizes.add(component.length);
      if (component.length > largest.length) {
        largest = component;
      }
    }
    componentSizes.sort((a, b) => b.compareTo(a));
    final largestComponent = List<StationTriggerSnapshot>.unmodifiable(largest);
    final stationIds =
        largestComponent.map((station) => station.stationId).toList()..sort();
    final triggerIntervals = <String, ObservationTimeInterval>{
      for (final station in largestComponent)
        if (station.firstTriggerInterval != null)
          station.stationId: station.firstTriggerInterval!,
    };
    final edgeCounts = _componentEdgeCounts(largestComponent);
    final centroid = _componentCentroid(largestComponent);
    return _NetworkAssociationAnalysis(
      largestComponent: largestComponent,
      diagnostics: NetworkAssociationDiagnostics(
        triggeredStationCount: stations.length,
        componentCount: componentSizes.length,
        componentSizes: List.unmodifiable(componentSizes),
        largestComponentSize: largestComponent.length,
        largestComponentDiameterKm: _componentDiameterKm(largestComponent),
        largestComponentQualityWeightedSupport: largestComponent.fold<double>(
          0,
          (total, station) => total + _qualityWeight(station),
        ),
        largestComponentTriggerTimeSpanSeconds: _triggerTimeSpanSeconds(
          largestComponent,
        ),
        largestComponentStationIds: List.unmodifiable(stationIds),
        largestComponentTriggerIntervals: Map.unmodifiable(triggerIntervals),
        largestComponentStrongEdgeCount: edgeCounts.$1,
        largestComponentWeakEdgeCount: edgeCounts.$2,
        largestComponentCentroidLatitude: centroid?.$1,
        largestComponentCentroidLongitude: centroid?.$2,
      ),
    );
  }

  (double, double)? _componentCentroid(List<StationTriggerSnapshot> stations) {
    if (stations.isEmpty) return null;
    final latitude =
        stations.fold<double>(0, (sum, station) => sum + station.latitude!) /
        stations.length;
    final longitude =
        stations.fold<double>(0, (sum, station) => sum + station.longitude!) /
        stations.length;
    return (latitude, longitude);
  }

  (int, int) _componentEdgeCounts(List<StationTriggerSnapshot> stations) {
    var strongEdges = 0;
    var weakEdges = 0;
    for (var i = 0; i < stations.length; i++) {
      for (var j = i + 1; j < stations.length; j++) {
        switch (_linkType(stations[i], stations[j])) {
          case _StationLinkType.strong:
            strongEdges++;
          case _StationLinkType.weak:
            weakEdges++;
          case _StationLinkType.none:
            break;
        }
      }
    }
    return (strongEdges, weakEdges);
  }

  bool _stationsAreLinked(StationTriggerSnapshot a, StationTriggerSnapshot b) {
    return _linkType(a, b) != _StationLinkType.none;
  }

  _StationLinkType _linkType(
    StationTriggerSnapshot a,
    StationTriggerSnapshot b,
  ) {
    final distance = _distanceKm(a, b);
    if (distance <= config.maxLinkDistanceKm) {
      return _StationLinkType.strong;
    }
    final bridgeDistance = config.temporalBridgeDistanceKm;
    if (bridgeDistance == null || distance > bridgeDistance) {
      return _StationLinkType.none;
    }
    final intervalA = a.firstTriggerInterval;
    final intervalB = b.firstTriggerInterval;
    if (intervalA == null || intervalB == null) {
      return _StationLinkType.none;
    }
    return _intervalGap(intervalA, intervalB) <= config.temporalBridgeMaxGap
        ? _StationLinkType.weak
        : _StationLinkType.none;
  }

  Duration _intervalGap(ObservationTimeInterval a, ObservationTimeInterval b) {
    if (a.end.isBefore(b.start)) return b.start.difference(a.end);
    if (b.end.isBefore(a.start)) return a.start.difference(b.end);
    return Duration.zero;
  }

  double _componentDiameterKm(List<StationTriggerSnapshot> stations) {
    var diameter = 0.0;
    for (var i = 0; i < stations.length; i++) {
      for (var j = i + 1; j < stations.length; j++) {
        final distance = _distanceKm(stations[i], stations[j]);
        if (distance > diameter) diameter = distance;
      }
    }
    return diameter;
  }

  double _qualityWeight(StationTriggerSnapshot station) {
    return station.qualityFlags.contains('scan_unreliable') ? 0.5 : 1.0;
  }

  List<StationTriggerSnapshot>? _findCompactCore(
    List<StationTriggerSnapshot> stations, {
    required int requiredSize,
    required double? maxDiameterKm,
    Set<String> preferredStationIds = const {},
  }) {
    if (stations.length < requiredSize) return null;
    if (maxDiameterKm == null) {
      return stations.take(requiredSize).toList(growable: false);
    }
    final orderedStations = [...stations]
      ..sort((a, b) {
        final aPreferred = preferredStationIds.contains(a.stationId);
        final bPreferred = preferredStationIds.contains(b.stationId);
        if (aPreferred == bPreferred) return 0;
        return aPreferred ? -1 : 1;
      });

    List<StationTriggerSnapshot>? search(
      List<StationTriggerSnapshot> chosen,
      List<StationTriggerSnapshot> candidates,
    ) {
      if (chosen.length >= requiredSize) {
        return List<StationTriggerSnapshot>.unmodifiable(chosen);
      }
      if (chosen.length + candidates.length < requiredSize) return null;

      for (var index = 0; index < candidates.length; index++) {
        final station = candidates[index];
        if (chosen.any(
          (selected) => _distanceKm(selected, station) > maxDiameterKm,
        )) {
          continue;
        }
        final remaining = candidates
            .skip(index + 1)
            .where(
              (candidate) =>
                  _distanceKm(station, candidate) <= maxDiameterKm &&
                  chosen.every(
                    (selected) =>
                        _distanceKm(selected, candidate) <= maxDiameterKm,
                  ),
            )
            .toList(growable: false);
        final result = search([...chosen, station], remaining);
        if (result != null) return result;
      }
      return null;
    }

    return search(const [], orderedStations);
  }

  double? _triggerTimeSpanSeconds(List<StationTriggerSnapshot> stations) {
    final triggerTimes = stations
        .map((station) => station.firstTriggerInterval?.end)
        .whereType<DateTime>()
        .toList(growable: false);
    if (triggerTimes.length < 2) return null;
    triggerTimes.sort();
    return triggerTimes.last.difference(triggerTimes.first).inMilliseconds /
        1000.0;
  }

  double _distanceKm(StationTriggerSnapshot a, StationTriggerSnapshot b) {
    const earthRadiusKm = 6371.0;
    final lat1 = _radians(a.latitude!);
    final lat2 = _radians(b.latitude!);
    final deltaLat = lat2 - lat1;
    final deltaLng = _radians(b.longitude! - a.longitude!);
    final sinLat = math.sin(deltaLat / 2);
    final sinLng = math.sin(deltaLng / 2);
    final haversine =
        sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
    return 2 * earthRadiusKm * math.asin(math.sqrt(haversine.clamp(0, 1)));
  }

  double _radians(double degrees) => degrees * math.pi / 180.0;
}

enum _StationLinkType { none, strong, weak }

class _NetworkAssociationAnalysis {
  final List<StationTriggerSnapshot> largestComponent;
  final NetworkAssociationDiagnostics diagnostics;

  const _NetworkAssociationAnalysis({
    required this.largestComponent,
    required this.diagnostics,
  });
}
