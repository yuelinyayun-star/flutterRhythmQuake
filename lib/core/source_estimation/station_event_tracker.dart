import 'package:flutter/foundation.dart';

import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/nied_monitor.dart';
import 'seismic_source_tracker.dart';
import 'source_estimation_models.dart';
import 'source_estimator.dart';

class StationEventTracker {
  static final StationEventTracker instance = StationEventTracker._internal();

  static const String niedSourceId = 'nied';

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
    _tracker.setEstimator(
      niedSourceId,
      const NiedGifHybridSourceEstimator(
        fallback: WeightedCentroidSourceEstimator(),
      ),
    );
  }

  void useDepthSearchNiedEstimator() {
    _tracker.setEstimator(
      niedSourceId,
      const TriggerTimeDepthGridSearchEstimator(
        fallback: TriggerTimeGridSearchEstimator(
          fallback: WeightedCentroidSourceEstimator(),
        ),
      ),
    );
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
    Map<String, Object?> metadata = const {},
  }) {
    _tracker.ingestFrame(
      sourceId: sourceId,
      observedAt: observedAt,
      stageName: stageName,
      maxShindo: maxShindo,
      samples: samples,
      metadata: metadata,
    );
  }

  void ingestNiedFrame({
    required List<NiedStation> stations,
    required DateTime observedAt,
    required String stageName,
    required int maxShindo,
    String sourceId = niedSourceId,
    Map<String, Object?> metadata = const {},
  }) {
    final samples = stations
        .map((station) {
          return SeismicStationSample(
            descriptor: _descriptorFromNiedStation(station, sourceId: sourceId),
            observedAt: observedAt,
            valueType: StationValueType.jmaShindo,
            value: _stationComparableValue(station),
            observedPga: station.gifObservation?.pga,
            observedPgv: station.gifObservation?.pgv,
            observedPgd: station.gifObservation?.pgd,
            rawLevel: station.level >= 0 ? station.level : null,
            detectLevel: station.detectLevel >= 0 ? station.detectLevel : null,
            activity: station.activity,
            ascend: station.ascend,
            isTriggered: station.isActive,
            qualityFlags: _qualityFlagsFromNiedStation(station),
          );
        })
        .toList(growable: false);

    ingestSamples(
      sourceId: sourceId,
      observedAt: observedAt,
      stageName: stageName,
      maxShindo: maxShindo,
      samples: samples,
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
      sensorRole: isKik
          ? StationSensorRole.borehole
          : StationSensorRole.surface,
      tags: {
        'prefecture': station.prefecture,
        'pixel_x': '${station.pixelX}',
        'pixel_y': '${station.pixelY}',
      },
    );
  }

  Set<String> _qualityFlagsFromNiedStation(NiedStation station) {
    final flags = <String>{};
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
    return flags;
  }

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
