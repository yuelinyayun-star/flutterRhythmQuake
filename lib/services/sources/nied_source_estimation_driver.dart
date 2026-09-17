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
import 'nied_detection_rules.dart';
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
  final void Function(String?, DateTime, String, Map<String, Object?>)?
  onSourceTrigger;

  EventDetection? _lastEventDetection;
  String? _directReceiverEventId;
  DateTime? _directReceiverLastObservedAt;
  Set<String> _dartHypActiveStationCodes = <String>{};
  final Map<String, DateTime> _dartHypActiveTriggerAtByCode =
      <String, DateTime>{};
  String? _dartHypAdjStationIdsKey;
  Map<String, List<int>> _dartHypAdjStationIds = const <String, List<int>>{};
  String? _dartDetectionAdjStationCodesKey;
  Map<String, List<String>> _dartDetectionAdjStationCodes =
      const <String, List<String>>{};
  List<double> _dartHypGridDecimal = const <double>[0.0, 0.0];
  bool _dartHypGridInitialized = false;
  int _sensitivity = 2;
  final Map<
    String,
    ({
      int id,
      String network,
      String prefecture,
      double latitude,
      double longitude,
      int thresholdCode,
      int pixelX,
      int pixelY,
      bool isKik,
      SeismicStationDescriptor descriptor,
    })
  >
  _descriptorCache = {};

  NiedSourceEstimationDriver({
    StationTriggerDetector? stationTriggerDetector,
    EventDetector? eventDetector,
    this.observationAdapter = const NiedStationObservationAdapter(),
    this.sourceTriggerGate = const SourceEstimationTriggerGate(),
    SourceTriggerContinuityGate? sourceContinuityGate,
    StationEventTracker? stationEventTracker,
    this.sourceId = StationEventTracker.niedSourceId,
    this.onSourceTrigger,
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

  void setSensitivity(int level) {
    _sensitivity = level.clamp(1, 3);
  }

  void reset() {
    stationTriggerDetector.reset();
    eventDetector.reset();
    sourceContinuityGate.reset();
    _lastEventDetection = null;
    _directReceiverEventId = null;
    _directReceiverLastObservedAt = null;
    _resetDartHypocenterEventState();
    _dartHypAdjStationIdsKey = null;
    _dartHypAdjStationIds = const <String, List<int>>{};
    _dartDetectionAdjStationCodesKey = null;
    _dartDetectionAdjStationCodes = const <String, List<String>>{};
    _descriptorCache.clear();
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
    _prepareDartHypocenterEventState(resolvedObservedAt);
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

    final sourceTrigger = sourceTriggerGate.evaluate(eventDetection);
    final dartHypocenterInput = _dartHypocenterInput(
      stations: stations,
      observedAt: resolvedObservedAt,
    );
    final activeSnapshots =
        dartHypocenterInput['activeStations']! as List<Map<String, Object?>>;
    final hasKaActiveStations = activeSnapshots.isNotEmpty;
    final currentEvent = stationEventTracker.currentNiedEvent.value;
    // Keep the NIED HYP entry condition identical to Kanameishi: only the
    // KA active-station chain may create or advance an inference event.  The
    // generic detector remains diagnostic metadata; it must not bypass that
    // chain merely because a GIF frame or a generic candidate is present.
    // An existing event receives one idle frame after the active window ends
    // so SeismicSourceTracker can close it and clear the map/UI state.
    final shouldIngestFrame = hasKaActiveStations || currentEvent != null;
    final trackerStageName = hasKaActiveStations ? 'confirmed' : 'idle';
    final trackerEventId = hasKaActiveStations
        ? _resolveDirectReceiverEventId(inputKind, resolvedObservedAt)
        : currentEvent?.eventId;
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
      final replayLogger = NiedReplayLogger.instance;
      if (trackerStageName != 'idle') {
        _startForSourceTrigger(
          eventId: trackerEventId,
          observedAt: resolvedObservedAt,
          stageName: trackerStageName,
          metadata: {
            'source_family': 'nied',
            'source_id': sourceId,
            'nied_input_kind': inputKind,
            'source_estimation_entry': 'ka_nied_hypocenter_direct',
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
            _sampleFromStation(station, observedAt: resolvedObservedAt),
        ],
        eventId: trackerEventId,
        metadata: {
          'source_family': 'nied',
          'nied_input_kind': inputKind,
          'source_estimation_entry': 'ka_nied_hypocenter_direct',
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
          'nied_hypocenter_inactive_scope':
              dartHypocenterInput['inactiveScope'],
          'nied_hypocenter_detection_grid':
              dartHypocenterInput['detectionGrid'],
          'nied_hypocenter_adj_station_ids':
              dartHypocenterInput['adjStationIds'],
          'nied_detection_adj_station_codes':
              dartHypocenterInput['detectionAdjStationCodes'],
          'nied_hypocenter_input_diagnostics':
              dartHypocenterInput['diagnostics'],
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
          'nied_max_jma_shindo_index': _maxJmaShindoIndex(stations),
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

  void _startForSourceTrigger({
    required String? eventId,
    required DateTime observedAt,
    required String stageName,
    required Map<String, Object?> metadata,
  }) {
    final callback = onSourceTrigger;
    if (callback != null) {
      callback(eventId, observedAt, stageName, metadata);
    } else {
      NiedReplayLogger.instance.startForSourceTrigger(
        eventId: eventId,
        observedAt: observedAt,
        stageName: stageName,
        metadata: metadata,
      );
    }
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
    required DateTime observedAt,
  }) {
    final dataTime = station.lastDataTime ?? station.lastUpdate ?? observedAt;
    final triggerAt = station.triggerStamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            station.triggerStamp,
            isUtc: false,
          )
        : null;
    return SeismicStationSample(
      descriptor: _descriptorFromNiedStation(station),
      observedAt: dataTime,
      receivedAt: station.lastReceivedAt ?? observedAt,
      valueType: StationValueType.jmaShindo,
      value: _stationComparableValue(station),
      observedPga: station.pgaObservation?.pga,
      observedPgv: station.pgvObservation?.pgv,
      observedPgd: station.pgdObservation?.pgd,
      physicalObservations: _physicalObservationsFromNiedStation(
        station,
        dataTime: dataTime,
        receivedAt: station.lastReceivedAt ?? observedAt,
      ),
      rawLevel: station.kaLevel >= 0 ? station.kaLevel : null,
      detectLevel: station.kaLevel >= 0 ? station.kaLevel : null,
      activity: station.activity,
      ascend: station.ascend,
      isTriggered: station.isActive,
      firstTriggerInterval: triggerAt == null
          ? null
          : ObservationTimeInterval(start: triggerAt, end: triggerAt),
      provenance: _provenanceFromNiedStation(station),
      qualityFlags: _qualityFlagsFromNiedStation(
        station,
        frameDataTime: observedAt,
      ),
    );
  }

  SeismicStationDescriptor _descriptorFromNiedStation(NiedStation station) {
    final isKik = station.network.toLowerCase().contains('kik');
    final cached = _descriptorCache[station.code];
    if (cached != null &&
        cached.id == station.id &&
        cached.network == station.network &&
        cached.prefecture == station.prefecture &&
        cached.latitude == station.coordinate.latitude &&
        cached.longitude == station.coordinate.longitude &&
        cached.thresholdCode == station.thresholdCode &&
        cached.pixelX == station.pixelX &&
        cached.pixelY == station.pixelY &&
        cached.isKik == isKik) {
      return cached.descriptor;
    }
    final descriptor = SeismicStationDescriptor(
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
    _descriptorCache[station.code] = (
      id: station.id,
      network: station.network,
      prefecture: station.prefecture,
      latitude: station.coordinate.latitude,
      longitude: station.coordinate.longitude,
      thresholdCode: station.thresholdCode,
      pixelX: station.pixelX,
      pixelY: station.pixelY,
      isKik: isKik,
      descriptor: descriptor,
    );
    return descriptor;
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

  Map<StationValueType, SeismicPhysicalObservation>
  _physicalObservationsFromNiedStation(
    NiedStation station, {
    required DateTime dataTime,
    required DateTime receivedAt,
  }) {
    final observations = <StationValueType, SeismicPhysicalObservation>{};
    for (final observation in station.gifObservations.values) {
      final quantity = _quantityForLayer(observation.layer);
      final value = switch (quantity) {
        StationValueType.pga => observation.pga,
        StationValueType.pgv => observation.pgv,
        StationValueType.pgd => observation.pgd,
        _ => null,
      };
      if (value == null || !value.isFinite) continue;
      observations[quantity] = SeismicPhysicalObservation(
        quantity: quantity,
        layerId: observation.layer.id,
        value: value,
        colorPosition: observation.colorPosition,
        dataTime: dataTime,
        receivedAt: receivedAt,
        qualityFlags: Set.unmodifiable(
          station.gifLayerQualityFlags[observation.layer] ?? const <String>{},
        ),
      );
    }
    return Map.unmodifiable(observations);
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
    if (station.kaLevel >= 0) {
      return JpShindoScale.rawShindoFromKanameishiLevel(station.kaLevel);
    }
    return null;
  }

  int _maxJmaShindo(List<NiedStation> stations) {
    final maxDetectLevel = _maxKanameishiLevel(stations);
    return maxDetectLevel >= 0
        ? JpShindoScale.jmaNumberFromKanameishiLevel(maxDetectLevel)
        : -1;
  }

  int _maxJmaShindoIndex(List<NiedStation> stations) {
    final maxDetectLevel = _maxKanameishiLevel(stations);
    return maxDetectLevel >= 0
        ? JpShindoScale.jmaIndexFromKanameishiLevel(maxDetectLevel)
        : -1;
  }

  int _maxKanameishiLevel(List<NiedStation> stations) {
    var maxDetectLevel = -1;
    for (final station in stations) {
      if (station.kaLevel > maxDetectLevel) {
        maxDetectLevel = station.kaLevel;
      }
    }
    return maxDetectLevel;
  }

  Map<String, Object?> _dartHypocenterInput({
    required List<NiedStation> stations,
    required DateTime observedAt,
  }) {
    final stationByCode = {
      for (final station in stations) station.code: station,
    };

    final adjStationIds = _dartHypocenterAdjStationIds(stations);
    final adjByCode = _dartDetectionAdjacencyByCode(stations);
    final preexistingActiveCount = stations
        .where((station) => station.isActive)
        .length;

    // possibleStations: activity > 0
    final possibleStations = stations.where((s) => s.activity > 0).toList();

    // Active selection with neighbor scoring (equivalent to reference chainActivate)
    final activeStationsSet = <String>{};
    final checkedStations = <String>{};
    final newActiveStations = <Map<String, Object?>>[];
    final activeStations = <Map<String, Object?>>[];
    final inactiveCandidates = <NiedStation>[];
    final stationPairAbnormalCache = <String, bool>{};

    Map<String, Object?> snapshot(NiedStation station, {required bool active}) {
      return _dartHypocenterStationSnapshot(
        station,
        observedAt: observedAt,
        active: active,
        preservedTriggerAt: active
            ? _dartHypActiveTriggerAtByCode[station.code]
            : null,
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

    bool hasAbnormalStationPair(List<NiedStation> candidates) {
      for (var i = 0; i < candidates.length - 1; i++) {
        for (var j = i + 1; j < candidates.length; j++) {
          final first = candidates[i];
          final second = candidates[j];
          final lowId = math.min(first.id, second.id);
          final highId = math.max(first.id, second.id);
          final key = '$lowId-$highId';
          final isAbnormal = stationPairAbnormalCache.putIfAbsent(
            key,
            () => isNiedAbnormalStationPair(
              firstTriggerStamp: first.triggerStamp,
              secondTriggerStamp: second.triggerStamp,
              distanceKm: _haversineKm(
                first.coordinate.latitude,
                first.coordinate.longitude,
                second.coordinate.latitude,
                second.coordinate.longitude,
              ),
            ),
          );
          if (isAbnormal) return true;
        }
      }
      return false;
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
          .where((s) => s != null && s.kaLevel > -1)
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

      final nearbyCount = nearbyStations.length.clamp(
        0,
        niedNearbyStationLimit,
      );
      final numThres = niedStationCountThreshold(_sensitivity, nearbyCount);
      var activityThres = niedActivityThreshold(_sensitivity, nearbyCount);

      if (nearbyActiveNum >= numThres) {
        final abnormalCandidates = nearbyStations
            .where((station) => !station.isActive && station.ascend > 2)
            .toList(growable: false);
        if (hasAbnormalStationPair(abnormalCandidates)) {
          activityThres *= 2;
        }
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

    // Build active/inactive/newActive lists
    for (final station in stations) {
      if (activeStationsSet.contains(station.code)) {
        final wasWorkerActive = _dartHypActiveStationCodes.contains(
          station.code,
        );
        final triggerAt =
            _dartHypocenterStationTriggerAt(station) ??
            _dartHypActiveTriggerAtByCode[station.code];
        if (triggerAt != null) {
          _dartHypActiveTriggerAtByCode[station.code] = triggerAt;
        }
        station.setActive();
        final snap = snapshot(station, active: true);
        activeStations.add(snap);
        if (!wasWorkerActive) {
          newActiveStations.add(snap);
        }
      } else if (station.isActive) {
        final triggerAt =
            _dartHypocenterStationTriggerAt(station) ??
            _dartHypActiveTriggerAtByCode[station.code];
        if (triggerAt != null) {
          _dartHypActiveTriggerAtByCode[station.code] = triggerAt;
        }
        activeStations.add(snapshot(station, active: true));
      } else if (station.kaLevel > -1 &&
          station.kaLevel < 6 &&
          station.activity <= 0 &&
          !station.isActive) {
        inactiveCandidates.add(station);
      }
    }

    final activeGridStations = stations
        .where((station) => station.isActive)
        .toList(growable: false);
    if (!_dartHypGridInitialized && activeGridStations.isNotEmpty) {
      final strongest = activeGridStations.reduce(
        (left, right) => left.kaLevel >= right.kaLevel ? left : right,
      );
      _dartHypGridDecimal = [
        niedDetectionGridDecimalPart(strongest.coordinate.latitude),
        niedDetectionGridDecimalPart(strongest.coordinate.longitude),
      ];
      _dartHypGridInitialized = true;
    }

    final activeGridLevels = <String, int>{};
    for (final station in activeGridStations) {
      final latitudeIndex = niedDetectionGridAxisIndex(
        station.coordinate.latitude,
        _dartHypGridDecimal[0],
      );
      final longitudeIndex = niedDetectionGridAxisIndex(
        station.coordinate.longitude,
        _dartHypGridDecimal[1],
      );
      final key = niedDetectionGridKey(latitudeIndex, longitudeIndex);
      final previousLevel = activeGridLevels[key];
      if (previousLevel == null || station.kaLevel > previousLevel) {
        activeGridLevels[key] = station.kaLevel;
      }
    }
    final surroundingGridKeys = niedDetectionSurroundingGridKeys(
      activeGridLevels.keys,
    );
    final inactiveStations = <Map<String, Object?>>[
      for (final station in inactiveCandidates)
        snapshot(station, active: false),
    ];
    final activeGridCells =
        [
          for (final entry in activeGridLevels.entries)
            () {
              final parts = entry.key.split(',');
              final latitudeIndex = int.parse(parts[0]);
              final longitudeIndex = int.parse(parts[1]);
              return <String, Object?>{
                'key': entry.key,
                'latitudeIndex': latitudeIndex,
                'longitudeIndex': longitudeIndex,
                'latitude': niedDetectionGridAxisCenter(
                  latitudeIndex,
                  _dartHypGridDecimal[0],
                ),
                'longitude': niedDetectionGridAxisCenter(
                  longitudeIndex,
                  _dartHypGridDecimal[1],
                ),
                'level': entry.value,
              };
            }(),
        ]..sort(
          (left, right) =>
              (left['key']! as String).compareTo(right['key']! as String),
        );
    if (activeGridCells.isEmpty) {
      _dartHypGridDecimal = const <double>[0.0, 0.0];
      _dartHypGridInitialized = false;
    }
    _dartHypActiveStationCodes = activeStations
        .map((snapshot) => snapshot['code']!.toString())
        .toSet();

    return {
      'newActiveStations': List<Map<String, Object?>>.unmodifiable(
        newActiveStations,
      ),
      'activeStations': List<Map<String, Object?>>.unmodifiable(activeStations),
      'inactiveStations': List<Map<String, Object?>>.unmodifiable(
        inactiveStations,
      ),
      'inactiveScope': 'ka_level_present_all_network_scratch_dynamic_radius',
      'detectionGrid': {
        'model': 'ka_detection_1deg_event_offset_surrounding_9_grid',
        'decimal': List<double>.unmodifiable(_dartHypGridDecimal),
        'activeCells': List<Map<String, Object?>>.unmodifiable(activeGridCells),
        'surroundingCellCount': surroundingGridKeys.length,
      },
      'adjStationIds': adjStationIds,
      'detectionAdjStationCodes': Map<String, List<String>>.unmodifiable({
        for (final entry in adjByCode.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      'diagnostics': {
        'level_present_count': stations
            .where((station) => station.kaLevel >= 0)
            .length,
        'ascend_positive_count': stations
            .where((station) => station.ascend > 0)
            .length,
        'activity_positive_count': possibleStations.length,
        'preexisting_active_count': preexistingActiveCount,
        'selected_active_count': activeStations.length,
        'selected_timed_active_count': activeStations
            .where((snapshot) => snapshot['triggerStamp'] != null)
            .length,
        'new_active_count': newActiveStations.length,
        'inactive_before_grid_count': inactiveCandidates.length,
        'inactive_count': inactiveStations.length,
        'active_grid_count': activeGridCells.length,
        'surrounding_grid_count': surroundingGridKeys.length,
        'max_level': stations.fold<int>(
          -1,
          (value, station) => math.max(value, station.kaLevel),
        ),
        'max_ascend': stations.fold<int>(
          0,
          (value, station) => math.max(value, station.ascend),
        ),
        'max_activity': stations.fold<double>(
          0,
          (value, station) => math.max(value, station.activity),
        ),
      },
    };
  }

  void _prepareDartHypocenterEventState(DateTime observedAt) {
    final previous = _directReceiverLastObservedAt;
    if (previous == null) return;
    if (observedAt.isBefore(previous) ||
        observedAt.difference(previous) > const Duration(seconds: 120)) {
      _resetDartHypocenterEventState();
    }
  }

  void _resetDartHypocenterEventState() {
    _dartHypActiveStationCodes = <String>{};
    _dartHypActiveTriggerAtByCode.clear();
    _dartHypGridDecimal = const <double>[0.0, 0.0];
    _dartHypGridInitialized = false;
  }

  Map<String, Object?> _dartHypocenterStationSnapshot(
    NiedStation station, {
    required DateTime observedAt,
    required bool active,
    DateTime? preservedTriggerAt,
  }) {
    final triggerAt =
        _dartHypocenterStationTriggerAt(station) ?? preservedTriggerAt;
    final updateAt = station.lastDataTime ?? station.lastUpdate ?? observedAt;
    return {
      'id': station.id,
      'code': station.code,
      'latLng': [station.coordinate.latitude, station.coordinate.longitude],
      'triggerStamp': triggerAt?.millisecondsSinceEpoch,
      'updateStamp': updateAt.millisecondsSinceEpoch,
      'ascend': station.ascend,
      'level': station.kaLevel,
      'shindo': _stationComparableValue(station),
      'isActive': active,
    };
  }

  DateTime? _dartHypocenterStationTriggerAt(NiedStation station) {
    if (station.triggerStamp > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        station.triggerStamp,
        isUtc: false,
      );
    }
    return null;
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
        if (coveredDirections.length >= 4) break;
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

  Map<String, List<String>> _dartDetectionAdjacencyByCode(
    List<NiedStation> stations,
  ) {
    final key = stations.map((station) => station.code).join('|');
    if (_dartDetectionAdjStationCodesKey == key) {
      return _dartDetectionAdjStationCodes;
    }
    final result = <String, List<String>>{};
    for (final station in stations) {
      final distances =
          <({NiedStation station, double distanceKm})>[
            for (final other in stations)
              (
                station: other,
                distanceKm: _haversineKm(
                  station.coordinate.latitude,
                  station.coordinate.longitude,
                  other.coordinate.latitude,
                  other.coordinate.longitude,
                ),
              ),
          ]..sort((left, right) {
            final byDistance = left.distanceKm.compareTo(right.distanceKm);
            return byDistance != 0
                ? byDistance
                : left.station.id.compareTo(right.station.id);
          });
      final nearby = distances
          .where((item) => item.distanceKm <= 30.0)
          .toList();
      if (nearby.length <= 1) {
        for (final candidate in distances) {
          if (candidate.distanceKm > 30.0 && candidate.distanceKm <= 40.0) {
            nearby.add(candidate);
            break;
          }
        }
      }
      result[station.code] = List<String>.unmodifiable(
        nearby.take(niedNearbyStationLimit).map((item) => item.station.code),
      );
    }
    _dartDetectionAdjStationCodesKey = key;
    _dartDetectionAdjStationCodes = Map<String, List<String>>.unmodifiable(
      result,
    );
    return _dartDetectionAdjStationCodes;
  }

  int _bearingDirection(double bearingDeg) {
    return (((bearingDeg + 45.0) % 360.0) ~/ 90) % 4;
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

  String _resolveDirectReceiverEventId(String inputKind, DateTime observedAt) {
    final previous = _directReceiverLastObservedAt;
    if (_directReceiverEventId == null ||
        previous == null ||
        observedAt.isBefore(previous) ||
        observedAt.difference(previous) > const Duration(seconds: 120)) {
      _directReceiverEventId =
          'nied-$inputKind-dart-${observedAt.toIso8601String()}';
    }
    _directReceiverLastObservedAt = observedAt;
    return _directReceiverEventId!;
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
