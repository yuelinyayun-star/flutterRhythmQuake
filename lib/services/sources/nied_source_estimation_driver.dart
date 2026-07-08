import 'dart:math' as math;

import '../../core/event_detection/event_detection_models.dart';
import '../../core/event_detection/robust_station_trigger_detector.dart';
import '../../core/event_detection/spatiotemporal_event_detector.dart';
import '../../core/nied_replay_logger.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/source_estimation_trigger.dart';
import '../../core/source_estimation/source_trigger_continuity_gate.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import 'package:flutter/foundation.dart';
import 'jp_shindo_scale.dart';
import 'nied_gif_observation.dart';
import 'nied_monitor.dart';
import 'nied_station_observation_adapter.dart';

class NiedSourceEstimationDriver {
  static const sourceEventDetectorId =
      'spatiotemporal_event_detector_v1_source_trigger';
  static const _debugGifSourceTriggerLogs = false;
  static const sourceEventDetectorConfig = SpatiotemporalEventDetectorConfig(
    candidateMinStations: 4,
    confirmedMinStations: 5,
    maxInitialConfirmationDiameterKm: 120,
    confirmationPersistenceFrames: 2,
    quarantineRejectedMembersUntilClear: true,
  );

  final StationTriggerDetector stationTriggerDetector;
  final EventDetector eventDetector;
  final NiedStationObservationAdapter observationAdapter;
  final SourceEstimationTriggerGate sourceTriggerGate;
  final SourceTriggerContinuityGate sourceContinuityGate;
  final StationEventTracker stationEventTracker;
  final String sourceId;

  EventDetection? _lastEventDetection;
  String? _gifReceiverEventId;
  DateTime? _gifReceiverLastObservedAt;
  Set<String> _dartHypActiveStationCodes = <String>{};
  String? _dartHypAdjStationIdsKey;
  Map<String, List<int>> _dartHypAdjStationIds = const <String, List<int>>{};
  String? _dartHypAdjStationCodesKey;
  Map<String, List<String>> _dartHypAdjStationCodes =
      const <String, List<String>>{};

  NiedSourceEstimationDriver({
    StationTriggerDetector? stationTriggerDetector,
    EventDetector? eventDetector,
    this.observationAdapter = const NiedStationObservationAdapter(),
    this.sourceTriggerGate = const SourceEstimationTriggerGate(),
    SourceTriggerContinuityGate? sourceContinuityGate,
    StationEventTracker? stationEventTracker,
    this.sourceId = StationEventTracker.niedSourceId,
  }) : stationTriggerDetector =
           stationTriggerDetector ?? RobustStationTriggerDetector(),
       eventDetector =
           eventDetector ??
           SpatiotemporalEventDetector(
             detectorId: sourceEventDetectorId,
             config: sourceEventDetectorConfig,
           ),
       sourceContinuityGate =
           sourceContinuityGate ?? SourceTriggerContinuityGate(),
       stationEventTracker =
           stationEventTracker ?? StationEventTracker.instance;

  EventDetection? get lastEventDetection => _lastEventDetection;

  void reset() {
    stationTriggerDetector.reset();
    eventDetector.reset();
    sourceContinuityGate.reset();
    _lastEventDetection = null;
    _gifReceiverEventId = null;
    _gifReceiverLastObservedAt = null;
    _dartHypActiveStationCodes = <String>{};
    _dartHypAdjStationIdsKey = null;
    _dartHypAdjStationIds = const <String, List<int>>{};
    _dartHypAdjStationCodesKey = null;
    _dartHypAdjStationCodes = const <String, List<String>>{};
  }

  EventDetection processStations(
    List<NiedStation> stations, {
    DateTime? observedAt,
    Map<String, Object?> metadata = const {},
  }) {
    final inputKind = _detectNiedInputKind(stations);
    final rawObservedAt =
        observedAt ?? _latestObservedAt(stations) ?? DateTime.now();
    final resolvedObservedAt = inputKind == 'gif'
        ? _truncateToGifSecond(rawObservedAt)
        : rawObservedAt;
    final stationTriggers = observationAdapter
        .fromStations(stations, observedAt: resolvedObservedAt)
        .map(stationTriggerDetector.update)
        .toList(growable: false);
    final rawEventDetection = eventDetector.update(
      observedAt: resolvedObservedAt,
      stations: stationTriggers,
    );
    final continuity = sourceContinuityGate.update(
      detection: rawEventDetection,
      stations: stationTriggers,
      observedAt: resolvedObservedAt,
      activeEstimate: stationEventTracker.currentNiedEvent.value?.estimate,
    );
    final eventDetection = _continuityAwareDetection(
      rawEventDetection,
      continuity,
    );
    _lastEventDetection = eventDetection;

    final isGifInput = inputKind == 'gif';
    final sourceTrigger = sourceTriggerGate.evaluate(eventDetection);
    final shouldIngestFrame = isGifInput || sourceTrigger.shouldIngestFrame;
    final trackerStageName = isGifInput ? 'confirmed' : sourceTrigger.stageName;
    final trackerEventId = isGifInput
        ? _resolveGifReceiverEventId(resolvedObservedAt)
        : continuity.effectiveEventId ?? sourceTrigger.eventId;
    _debugLogGifSourceTrigger(
      observedAt: resolvedObservedAt,
      stations: stations,
      stationTriggers: stationTriggers,
      eventDetection: eventDetection,
      sourceTrigger: sourceTrigger,
      effectiveShouldIngestFrame: shouldIngestFrame,
      effectiveStageName: trackerStageName,
    );
    if (shouldIngestFrame) {
      final dartHypocenterInput = _dartHypocenterInput(
        stations: stations,
        stationTriggers: stationTriggers,
        eventDetection: eventDetection,
        observedAt: resolvedObservedAt,
      );
      final triggersByCode = {
        for (final trigger in stationTriggers) trigger.code: trigger,
      };
      final replayLogger = NiedReplayLogger.instance;
      if (trackerStageName != 'idle') {
        replayLogger.startForSourceTrigger(
          eventId: trackerEventId,
          observedAt: resolvedObservedAt,
          stageName: trackerStageName,
          metadata: {
            'source_family': 'nied',
            'source_id': sourceId,
            'nied_input_kind': inputKind,
            'source_estimation_entry': isGifInput
                ? 'dart_nied_hypocenter_direct'
                : 'flutter_source_trigger_gate',
            'nied_hypocenter_input_format':
                'nied_station_hypocenter_snapshot_v1',
            'source_trigger_state': eventDetection.state.name,
            'source_trigger_detector_id': eventDetection.detectorId,
            'source_trigger_score': eventDetection.detectionScore,
            'source_trigger_member_count':
                eventDetection.memberStationIds.length,
            'station_trigger_active_count': stationTriggers
                .where((trigger) => trigger.isActiveLike)
                .length,
            'station_trigger_confirmed_count': stationTriggers
                .where(_isConfirmedStationTrigger)
                .length,
            'source_trigger_member_ids': List<String>.unmodifiable(
              eventDetection.memberStationIds,
            ),
            'source_trigger_continuity_member_ids': List<String>.unmodifiable(
              continuity.effectiveMemberStationIds,
            ),
            ...sourceTrigger.metadata,
            ...continuity.metadata,
            ...metadata,
          },
        );
      }
      stationEventTracker.ingestSamples(
        sourceId: sourceId,
        observedAt: resolvedObservedAt,
        stageName: trackerStageName,
        maxShindo: _maxJmaShindo(stations),
        samples: [
          for (final station in stations)
            _sampleFromStation(
              station,
              trigger: triggersByCode[station.code],
              observedAt: resolvedObservedAt,
            ),
        ],
        eventId: trackerEventId,
        metadata: {
          'source_family': 'nied',
          'nied_input_kind': inputKind,
          'source_estimation_entry': isGifInput
              ? 'dart_nied_hypocenter_direct'
              : 'flutter_source_trigger_gate',
          'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
          'nied_hypocenter_frame_key': resolvedObservedAt
              .toUtc()
              .toIso8601String(),
          'nied_hypocenter_new_active_stations':
              dartHypocenterInput['newActiveStations'],
          'nied_hypocenter_active_stations':
              dartHypocenterInput['activeStations'],
          'nied_hypocenter_inactive_stations':
              dartHypocenterInput['inactiveStations'],
          'nied_hypocenter_adj_station_ids':
              dartHypocenterInput['adjStationIds'],
          'station_trigger_detector_id': stationTriggerDetector.detectorId,
          'station_trigger_active_count': stationTriggers
              .where((trigger) => trigger.isActiveLike)
              .length,
          'station_trigger_confirmed_count': stationTriggers
              .where(_isConfirmedStationTrigger)
              .length,
          'source_trigger_member_ids': List<String>.unmodifiable(
            eventDetection.memberStationIds,
          ),
          'source_trigger_continuity_member_ids': List<String>.unmodifiable(
            continuity.effectiveMemberStationIds,
          ),
          ...sourceTrigger.metadata,
          ...continuity.metadata,
          ...metadata,
        },
      );
      final estimate = stationEventTracker.currentNiedEvent.value?.estimate;
      if (estimate != null && replayLogger.isEnabled) {
        replayLogger.logEpicenter(
          lat: estimate.latitude,
          lng: estimate.longitude,
          confidence: estimate.confidence,
          activeStationCount: estimate.supportingStationCount,
        );
      }
    }

    return eventDetection;
  }

  EventDetection _continuityAwareDetection(
    EventDetection detection,
    SourceTriggerContinuityDecision continuity,
  ) {
    final effectiveEventId = continuity.effectiveEventId ?? detection.eventId;
    final memberStationIds = continuity.currentMemberStationIds;
    return EventDetection(
      detectorId: detection.detectorId,
      sourceId: detection.sourceId,
      eventId: effectiveEventId,
      state: detection.state,
      observedAt: detection.observedAt,
      startedAt: detection.startedAt,
      updatedAt: detection.updatedAt,
      endedAt: detection.endedAt,
      memberStationIds: memberStationIds,
      detectionScore: detection.detectionScore,
      maxIntensity: detection.maxIntensity,
      reasonCodes: {
        ...detection.reasonCodes,
        if (continuity.heldReplacement) 'source_trigger_replacement_held',
      },
      metadata: {...detection.metadata, ...continuity.metadata},
    );
  }

  DateTime? _latestObservedAt(List<NiedStation> stations) {
    DateTime? latest;
    for (final station in stations) {
      final observedAt = station.lastDataTime ?? station.lastUpdate;
      if (observedAt == null) continue;
      if (latest == null || observedAt.isAfter(latest)) {
        latest = observedAt;
      }
    }
    return latest;
  }

  SeismicStationSample _sampleFromStation(
    NiedStation station, {
    required StationTriggerSnapshot? trigger,
    required DateTime observedAt,
  }) {
    final dataTime = station.lastDataTime ?? station.lastUpdate ?? observedAt;
    return SeismicStationSample(
      descriptor: _descriptorFromNiedStation(station),
      observedAt: dataTime,
      receivedAt: station.lastReceivedAt ?? observedAt,
      valueType: StationValueType.jmaShindo,
      value: _stationComparableValue(station),
      observedPga: station.pgaObservation?.pga,
      observedPgv: station.pgvObservation?.pgv,
      observedPgd: station.pgdObservation?.pgd,
      rawLevel: station.level >= 0 ? station.level : null,
      detectLevel: station.detectLevel >= 0 ? station.detectLevel : null,
      activity: trigger?.activity ?? 0,
      ascend: trigger?.ascend ?? 0,
      isTriggered:
          trigger?.state == StationTriggerState.triggered ||
          trigger?.state == StationTriggerState.strong,
      firstRiseInterval: trigger?.firstRiseInterval,
      firstTriggerInterval: trigger?.firstTriggerInterval,
      provenance: _provenanceFromNiedStation(station),
      qualityFlags: {
        ..._qualityFlagsFromNiedStation(station, frameDataTime: observedAt),
        ...?trigger?.qualityFlags,
        ...?trigger?.reasonCodes.map((reason) => 'trigger_reason:$reason'),
      },
    );
  }

  SeismicStationDescriptor _descriptorFromNiedStation(NiedStation station) {
    final isKik = station.network.toLowerCase().contains('kik');
    return SeismicStationDescriptor(
      stationId: station.code,
      code: station.code,
      sourceId: sourceId,
      network: station.network,
      coordinate: station.coordinate,
      sensorRole: StationSensorRole.surface,
      tags: {
        'prefecture': station.prefecture,
        'scratch_station_index': '${station.id + 1}',
        'threshold_code': '${station.thresholdCode}',
        'pixel_x': '${station.pixelX}',
        'pixel_y': '${station.pixelY}',
        'gif_display_primary_layer': 'jma_s',
        'physical_sensor_role': isKik ? 'kik_surface_or_borehole' : 'surface',
      },
    );
  }

  Set<String> _qualityFlagsFromNiedStation(
    NiedStation station, {
    required DateTime frameDataTime,
  }) {
    final stationDataTime = station.lastDataTime ?? station.lastUpdate;
    return {
      if (station.gifObservation != null) 'gif_observation',
      if (station.lastUpdate != null) 'has_station_timestamp',
      if (station.lastDataTime != null) 'has_data_timestamp',
      if (station.lastReceivedAt != null) 'has_receive_timestamp',
      if (!station.scanReliable) 'scan_unreliable',
      for (final entry in station.gifLayerQualityFlags.entries)
        for (final flag in entry.value) 'gif_layer:${entry.key.id}:$flag',
      if (stationDataTime != null &&
          frameDataTime.difference(stationDataTime) >
              const Duration(seconds: 2))
        'stale_observation',
      if (station.network.toLowerCase().contains('kik')) 'kik',
    };
  }

  Map<StationValueType, ObservationProvenance> _provenanceFromNiedStation(
    NiedStation station,
  ) {
    return {
      for (final observation in station.gifObservations.values)
        _quantityForLayer(observation.layer): ObservationProvenance(
          origin: ObservationOrigin.niedGifLayer,
          quantity: _quantityForLayer(observation.layer),
          layerId: observation.layer.id,
          isIndependentPhysicalMeasurement: true,
          qualityFlags:
              station.gifLayerQualityFlags[observation.layer] ?? const {},
        ),
    };
  }

  StationValueType _quantityForLayer(NiedGifLayer layer) => switch (layer) {
    NiedGifLayer.realtimeShindo => StationValueType.jmaShindo,
    NiedGifLayer.peakAcceleration => StationValueType.pga,
    NiedGifLayer.peakVelocity => StationValueType.pgv,
    NiedGifLayer.peakDisplacement => StationValueType.pgd,
    _ => StationValueType.custom,
  };

  double? _stationComparableValue(NiedStation station) {
    final gifShindo = station.gifObservation?.shindo;
    if (gifShindo != null && gifShindo.isFinite) {
      return gifShindo;
    }
    if (station.detectLevel >= 0) {
      return JpShindoScale.rawShindoFromKanameishiLevel(station.detectLevel);
    }
    return null;
  }

  int _maxJmaShindo(List<NiedStation> stations) {
    var maxDetectLevel = -1;
    for (final station in stations) {
      if (station.detectLevel > maxDetectLevel) {
        maxDetectLevel = station.detectLevel;
      }
    }
    return maxDetectLevel >= 0
        ? JpShindoScale.jmaNumberFromKanameishiLevel(maxDetectLevel)
        : -1;
  }

  Map<String, Object?> _dartHypocenterInput({
    required List<NiedStation> stations,
    required List<StationTriggerSnapshot> stationTriggers,
    required EventDetection eventDetection,
    required DateTime observedAt,
  }) {
    final triggerByCode = {
      for (final trigger in stationTriggers) trigger.code: trigger,
    };
    final stationByCode = {
      for (final station in stations) station.code: station,
    };

    final adjStationIds = _dartHypocenterAdjStationIds(stations);
    final adjByCode = _dartHypocenterAdjStationCodes(stations, adjStationIds);

    // possibleStations: activity > 0
    final possibleStations = stations.where((s) => s.activity > 0).toList();

    // Active selection with neighbor scoring (equivalent to reference chainActivate)
    final activeStationsSet = <String>{};
    final checkedStations = <String>{};
    final newActiveStations = <Map<String, Object?>>[];
    final activeStations = <Map<String, Object?>>[];
    final inactiveStations = <Map<String, Object?>>[];

    // Helper: build snapshot
    Map<String, Object?> snapshot(NiedStation station) {
      final trigger = triggerByCode[station.code];
      final active = activeStationsSet.contains(station.code);
      return _dartHypocenterStationSnapshot(
        station,
        trigger: trigger,
        observedAt: observedAt,
        active: active,
      );
    }

    // chainActivate: flood-fill through adjacency
    void chainActivate(NiedStation start) {
      final pending = <String>[start.code];
      while (pending.isNotEmpty) {
        final code = pending.removeLast();
        if (checkedStations.contains(code)) continue;
        checkedStations.add(code);
        final station = stationByCode[code];
        if (station == null) continue;
        if (station.activity > 0) {
          activeStationsSet.add(code);
          final neighbors = adjByCode[code] ?? <String>[];
          for (final neighborCode in neighbors) {
            if (!checkedStations.contains(neighborCode) &&
                stationByCode.containsKey(neighborCode)) {
              pending.add(neighborCode);
            }
          }
        }
      }
    }

    if (eventDetection.hasActiveEvent) {
      final memberIds = eventDetection.memberStationIds.toSet();
      for (final trigger in stationTriggers) {
        if (!trigger.isActiveLike ||
            (!memberIds.contains(trigger.stationId) &&
                !memberIds.contains(trigger.code))) {
          continue;
        }
        final station = stationByCode[trigger.code];
        if (station == null) continue;
        if (station.activity > 0) {
          chainActivate(station);
        } else {
          activeStationsSet.add(station.code);
        }
      }

      for (final station in possibleStations) {
        if (checkedStations.contains(station.code)) continue;

        if (station.isActive && station.ascend > 0) {
          chainActivate(station);
          continue;
        }

        // Neighbor scoring
        final neighborCodes = adjByCode[station.code] ?? <String>[];
        final nearbyStations = neighborCodes
            .map((code) => stationByCode[code])
            .where((s) => s != null && s.level > -1)
            .cast<NiedStation>()
            .toList();

        if (nearbyStations.isEmpty) continue;

        // nearbyActiveNum: active station = 1, non-active with ascend > 1 = 1, ascend <= 1 = 0.5
        double nearbyActiveNum = 0;
        for (final nearby in nearbyStations) {
          if (nearby.activity <= 0) continue;
          if (nearby.isActive) {
            nearbyActiveNum += 1;
          } else if (nearby.ascend <= 1) {
            nearbyActiveNum += 0.5;
          } else {
            nearbyActiveNum += 1;
          }
        }

        // numThres and activityThres (default sensitivity = 2, medium)
        final n = nearbyStations.length;
        final numThres = n <= 2 ? (n + 1) / 2 : n / 2;
        // activityThresArr2 = [Infinity, 8, 11, 13, 14, 15, 16]
        final activityThresArr = <double>[
          double.infinity,
          8,
          11,
          13,
          14,
          15,
          16,
        ];
        final activityThres = n < activityThresArr.length
            ? activityThresArr[n]
            : activityThresArr.last;

        if (nearbyActiveNum >= numThres) {
          // nearbyActivity = sum(activity) + nearbyActiveNum * (nearbyActiveNum + 1) / 2
          double nearbyActivity = 0;
          for (final nearby in nearbyStations) {
            nearbyActivity += nearby.activity;
          }
          nearbyActivity += nearbyActiveNum * (nearbyActiveNum + 1) / 2;

          if (nearbyActivity >= activityThres) {
            chainActivate(station);
          }
        }
      }
    }

    // Build active/inactive/newActive lists
    for (final station in stations) {
      if (activeStationsSet.contains(station.code)) {
        final wasActive = station.isActive;
        station.setActive();
        final snap = snapshot(station);
        activeStations.add(snap);
        if (!wasActive && !_dartHypActiveStationCodes.contains(station.code)) {
          newActiveStations.add(snap);
        }
      } else if (station.level > -1 &&
          station.level < 6 &&
          station.activity <= 0 &&
          !station.isActive) {
        inactiveStations.add(snapshot(station));
      }
    }
    _dartHypActiveStationCodes = activeStationsSet;

    return {
      'newActiveStations': List<Map<String, Object?>>.unmodifiable(
        newActiveStations,
      ),
      'activeStations': List<Map<String, Object?>>.unmodifiable(activeStations),
      'inactiveStations': List<Map<String, Object?>>.unmodifiable(
        inactiveStations,
      ),
      'adjStationIds': adjStationIds,
    };
  }

  Map<String, Object?> _dartHypocenterStationSnapshot(
    NiedStation station, {
    required StationTriggerSnapshot? trigger,
    required DateTime observedAt,
    required bool active,
  }) {
    final triggerAt = station.triggerStamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            station.triggerStamp,
            isUtc: false,
          )
        : (trigger?.firstTriggerInterval?.end ??
              trigger?.firstRiseInterval?.end);
    final updateAt = station.lastDataTime ?? station.lastUpdate ?? observedAt;
    return {
      'id': station.id,
      'code': station.code,
      'latLng': [station.coordinate.latitude, station.coordinate.longitude],
      'triggerStamp': triggerAt?.millisecondsSinceEpoch,
      'updateStamp': updateAt.millisecondsSinceEpoch,
      'ascend': station.ascend,
      'level': station.level,
      'detectLevel': station.detectLevel,
      'activity': station.activity,
      'isActive': active,
    };
  }

  Map<String, List<int>> _dartHypocenterAdjStationIds(
    List<NiedStation> stations,
  ) {
    final key = stations.map((station) => station.code).join('|');
    if (_dartHypAdjStationIdsKey == key) return _dartHypAdjStationIds;
    final result = <String, List<int>>{};
    for (final station in stations) {
      final distances = <({int id, double distanceKm, double bearingDeg})>[];
      for (final other in stations) {
        final distanceKm = _haversineKm(
          station.coordinate.latitude,
          station.coordinate.longitude,
          other.coordinate.latitude,
          other.coordinate.longitude,
        );
        distances.add((
          id: other.id,
          distanceKm: distanceKm,
          bearingDeg: _bearingDeg(
            station.coordinate.latitude,
            station.coordinate.longitude,
            other.coordinate.latitude,
            other.coordinate.longitude,
          ),
        ));
      }
      distances.sort((a, b) {
        final distanceCompare = a.distanceKm.compareTo(b.distanceKm);
        return distanceCompare != 0 ? distanceCompare : a.id.compareTo(b.id);
      });
      final selected = <int>{};
      final coveredDirections = <int>{};
      for (final item in distances) {
        if (item.distanceKm <= 30.0) {
          selected.add(item.id);
          if (item.id != station.id) {
            coveredDirections.add(_bearingDirection(item.bearingDeg));
          }
        }
      }
      for (final item in distances) {
        if (coveredDirections.length >= 8) break;
        if (item.id == station.id ||
            item.distanceKm <= 30.0 ||
            item.distanceKm > 300.0) {
          continue;
        }
        final direction = _bearingDirection(item.bearingDeg);
        if (coveredDirections.add(direction)) {
          selected.add(item.id);
        }
      }
      result['${station.id}'] = List<int>.unmodifiable(selected);
    }
    _dartHypAdjStationIdsKey = key;
    _dartHypAdjStationIds = Map<String, List<int>>.unmodifiable(result);
    return _dartHypAdjStationIds;
  }

  Map<String, List<String>> _dartHypocenterAdjStationCodes(
    List<NiedStation> stations,
    Map<String, List<int>> adjStationIds,
  ) {
    final key = stations.map((station) => station.code).join('|');
    if (_dartHypAdjStationCodesKey == key) return _dartHypAdjStationCodes;
    final idToCode = {for (final station in stations) station.id: station.code};
    final result = <String, List<String>>{};
    for (final entry in adjStationIds.entries) {
      result[entry.key] = List<String>.unmodifiable(
        entry.value
            .map((id) => idToCode[id] ?? '')
            .where((code) => code.isNotEmpty),
      );
    }
    _dartHypAdjStationCodesKey = key;
    _dartHypAdjStationCodes = Map<String, List<String>>.unmodifiable(result);
    return _dartHypAdjStationCodes;
  }

  int _bearingDirection(double bearingDeg) {
    return (((bearingDeg % 360.0) + 22.5) ~/ 45) % 8;
  }

  double _bearingDeg(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaLambda = (lon2 - lon1) * math.pi / 180.0;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final rLat1 = lat1 * math.pi / 180.0;
    final rLat2 = lat2 * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final clamped = a.clamp(0.0, 1.0);
    return earthRadiusKm *
        2.0 *
        math.atan2(math.sqrt(clamped), math.sqrt(1.0 - clamped));
  }

  bool _isConfirmedStationTrigger(StationTriggerSnapshot trigger) {
    return trigger.state == StationTriggerState.triggered ||
        trigger.state == StationTriggerState.strong;
  }

  String _detectNiedInputKind(List<NiedStation> stations) {
    if (stations.any((station) => station.gifObservation != null)) {
      return 'gif';
    }
    return 'yahoo';
  }

  DateTime _truncateToGifSecond(DateTime observedAt) {
    final milliseconds = (observedAt.millisecondsSinceEpoch ~/ 1000) * 1000;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: observedAt.isUtc,
    );
  }

  String _resolveGifReceiverEventId(DateTime observedAt) {
    final previous = _gifReceiverLastObservedAt;
    if (_gifReceiverEventId == null ||
        previous == null ||
        observedAt.isBefore(previous) ||
        observedAt.difference(previous) > const Duration(seconds: 120)) {
      _gifReceiverEventId = 'nied-gif-dart-${observedAt.toIso8601String()}';
    }
    _gifReceiverLastObservedAt = observedAt;
    return _gifReceiverEventId!;
  }

  void _debugLogGifSourceTrigger({
    required DateTime observedAt,
    required List<NiedStation> stations,
    required List<StationTriggerSnapshot> stationTriggers,
    required EventDetection eventDetection,
    required SourceEstimationTriggerDecision sourceTrigger,
    required bool effectiveShouldIngestFrame,
    required String effectiveStageName,
  }) {
    if (!_debugGifSourceTriggerLogs ||
        !kDebugMode ||
        _detectNiedInputKind(stations) != 'gif') {
      return;
    }
    final activeCount = stationTriggers
        .where((trigger) => trigger.isActiveLike)
        .length;
    final triggeredCount = stationTriggers
        .where(
          (trigger) =>
              trigger.state == StationTriggerState.triggered ||
              trigger.state == StationTriggerState.strong,
        )
        .length;
    final risingCount = stationTriggers
        .where((trigger) => trigger.state == StationTriggerState.rising)
        .length;
    final usableCount = stationTriggers
        .where(
          (trigger) =>
              trigger.intensity != null ||
              trigger.rawLevel != null ||
              trigger.detectLevel != null,
        )
        .length;
    final maxShindo = stations.fold<double>(0, (maxValue, station) {
      final value = station.gifObservation?.shindo;
      if (value == null || !value.isFinite) return maxValue;
      return value > maxValue ? value : maxValue;
    });
    debugPrint(
      '[NIED GIF SourceTrigger] '
      '${observedAt.toIso8601String()} '
      'usable=$usableCount active=$activeCount rising=$risingCount '
      'triggered=$triggeredCount members=${eventDetection.memberStationIds.length} '
      'state=${eventDetection.state.name} flutterStage=${sourceTrigger.stageName} '
      'effectiveStage=$effectiveStageName ingest=$effectiveShouldIngestFrame '
      'maxShindo=${maxShindo.toStringAsFixed(2)} '
      'reasons=${eventDetection.reasonCodes.join(",")}',
    );
  }
}
