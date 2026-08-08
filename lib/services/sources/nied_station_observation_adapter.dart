import '../../core/event_detection/event_detection_models.dart';
import 'nied_monitor.dart';

class NiedStationObservationAdapter {
  final String sourceId;

  const NiedStationObservationAdapter({this.sourceId = 'nied_gif'});

  StationObservationFrame fromStation(
    NiedStation station, {
    required DateTime observedAt,
  }) {
    final isKik = station.network.toLowerCase().contains('kik');
    final qualityFlags = <String>{
      if (station.gifObservation != null) 'gif_observation',
      if (station.lastDataTime != null) 'has_data_timestamp',
      if (station.lastReceivedAt != null) 'has_receive_timestamp',
      if (!station.scanReliable) 'scan_unreliable',
    };

    return StationObservationFrame(
      stationId: station.code,
      code: station.code,
      sourceId: sourceId,
      observedAt: observedAt,
      latitude: station.coordinate.latitude,
      longitude: station.coordinate.longitude,
      intensity: station.gifObservation?.shindo,
      rawLevel: station.kaLevel >= 0 ? station.kaLevel : null,
      detectLevel: station.kaLevel >= 0 ? station.kaLevel : null,
      sensorRole: ObservationSensorRole.surface,
      qualityFlags: qualityFlags,
      metadata: {
        'network': station.network,
        'prefecture': station.prefecture,
        'pixel_cluster_id': station.pixelClusterId,
        'gif_display_primary_layer': 'jma_s',
        'physical_sensor_role': isKik ? 'kik_surface_or_borehole' : 'surface',
      },
    );
  }

  List<StationObservationFrame> fromStations(
    List<NiedStation> stations, {
    required DateTime observedAt,
  }) {
    return stations
        .map((station) => fromStation(station, observedAt: observedAt))
        .toList(growable: false);
  }
}
