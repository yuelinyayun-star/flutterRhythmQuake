import 'package:flutter/foundation.dart';

import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/nied_gif_observation.dart';
import '../../services/sources/nied_monitor.dart';
import 'seismic_source_tracker.dart';
import 'source_estimation_models.dart';
import 'source_estimator.dart';
import '../event_detection/event_detection_models.dart';

class StationEventTracker {
  static final StationEventTracker instance = StationEventTracker._internal();

  static const String niedSourceId = 'nied';
  static const SourceEstimateStabilityConfig niedStabilityConfig =
      SourceEstimateStabilityConfig();

  StationEventTracker._internal() {
    useDefaultNiedEstimator();
  }

  final SeismicSourceTracker _tracker = SeismicSourceTracker();

  late final ValueNotifier<SeismicActiveEvent?> currentNiedEvent = _tracker
      .currentEventNotifier(niedSourceId);
  late final ValueNotifier<List<SeismicActiveEvent>> niedEventHistory = _tracker
      .historyNotifier(niedSourceId);

  void setNiedEstimator(SourceEstimator estimator) {
    _tracker.setEstimator(niedSourceId, estimator);
  }

  void useDefaultNiedEstimator() {
    _tracker
      ..setEstimator(niedSourceId, NiedDartHypSourceEstimator())
      ..setStabilityConfig(niedSourceId, niedStabilityConfig);
  }

  void useDepthSearchNiedEstimator() {
    _tracker
      ..setEstimator(
        niedSourceId,
        const TriggerTimeDepthGridSearchEstimator(
          fallback: TriggerTimeGridSearchEstimator(
            fallback: WeightedCentroidSourceEstimator(),
          ),
        ),
      )
      ..setStabilityConfig(niedSourceId, niedStabilityConfig);
  }

  ValueNotifier<SeismicActiveEvent?> currentEventNotifier(String sourceId) =>
      _tracker.currentEventNotifier(sourceId);

  ValueNotifier<List<SeismicActiveEvent>> historyNotifier(String sourceId) =>
      _tracker.historyNotifier(sourceId);

  void resetNied() {
    _tracker.resetSource(niedSourceId);
    useDefaultNiedEstimator();
  }

  void resetAll() {
    _tracker.resetAll();
    useDefaultNiedEstimator();
  }

  void ingestSamples({
    required String sourceId,
    required DateTime observedAt,
    required String stageName,
    required int maxShindo,
    required List<SeismicStationSample> samples,
    String? eventId,
    Map<String, Object?> metadata = const {},
  }) {
    _tracker.ingestFrame(
      sourceId: sourceId,
      observedAt: observedAt,
      stageName: stageName,
      maxShindo: maxShindo,
      samples: samples,
      eventId: eventId,
      metadata: metadata,
    );
  }

  void ingestNiedFrame({
    required List<NiedStation> stations,
    required DateTime observedAt,
    required String stageName,
    required int maxShindo,
    String sourceId = niedSourceId,
    String? eventId,
    Map<String, Object?> metadata = const {},
  }) {
    final samples = stations
        .map((station) {
          final dataTime =
              station.lastDataTime ?? station.lastUpdate ?? observedAt;
          return SeismicStationSample(
            descriptor: _descriptorFromNiedStation(station, sourceId: sourceId),
            observedAt: dataTime,
            receivedAt: station.lastReceivedAt ?? observedAt,
            valueType: StationValueType.jmaShindo,
            value: _stationComparableValue(station),
            observedPga: station.pgaObservation?.pga,
            observedPgv: station.pgvObservation?.pgv,
            observedPgd: station.pgdObservation?.pgd,
            rawLevel: station.level >= 0 ? station.level : null,
            detectLevel: station.detectLevel >= 0 ? station.detectLevel : null,
            activity: station.activity,
            ascend: station.ascend,
            isTriggered: station.isActive,
            firstTriggerInterval: station.triggerStamp > 0
                ? ObservationTimeInterval(
                    start: DateTime.fromMillisecondsSinceEpoch(
                      station.triggerStamp,
                      isUtc: false,
                    ),
                    end: DateTime.fromMillisecondsSinceEpoch(
                      station.triggerStamp,
                      isUtc: false,
                    ),
                  )
                : null,
            qualityFlags: _qualityFlagsFromNiedStation(
              station,
              frameDataTime: observedAt,
            ),
            provenance: _provenanceFromNiedStation(station),
          );
        })
        .toList(growable: false);

    ingestSamples(
      sourceId: sourceId,
      observedAt: observedAt,
      stageName: stageName,
      maxShindo: maxShindo,
      samples: samples,
      eventId: eventId,
      metadata: {
        'source_family': 'nied',
        'nied_input_kind': _detectNiedInputKind(stations),
        ...metadata,
      },
    );
  }

  String _detectNiedInputKind(List<NiedStation> stations) {
    if (stations.any((s) => s.gifObservation != null)) {
      return 'gif';
    }
    return 'yahoo';
  }

  SeismicStationDescriptor _descriptorFromNiedStation(
    NiedStation station, {
    required String sourceId,
  }) {
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
    final flags = <String>{};
    final stationDataTime = station.lastDataTime ?? station.lastUpdate;
    if (station.lastUpdate != null) {
      flags.add('has_station_timestamp');
    }
    if (station.lastDataTime != null) {
      flags.add('has_data_timestamp');
    }
    if (station.lastReceivedAt != null) {
      flags.add('has_receive_timestamp');
    }
    if (station.network.toLowerCase().contains('kik')) {
      flags.add('kik');
    }
    for (final entry in station.gifLayerQualityFlags.entries) {
      flags.addAll(
        entry.value.map((flag) => 'gif_layer:${entry.key.id}:$flag'),
      );
    }
    if (stationDataTime != null &&
        frameDataTime.difference(stationDataTime) >
            const Duration(seconds: 2)) {
      flags.add('stale_observation');
    }
    return flags;
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
    final gifObservation = station.gifObservation;
    final gifShindo = gifObservation?.shindo;
    if (gifShindo != null && gifShindo.isFinite) {
      return gifShindo;
    }
    if (station.detectLevel >= 0) {
      return JpShindoScale.rawShindoFromKanameishiLevel(station.detectLevel);
    }
    return null;
  }
}
