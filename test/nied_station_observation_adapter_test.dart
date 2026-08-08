import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_station_observation_adapter.dart';

void main() {
  test('NIED observation adapter does not consume station isActive', () {
    final observedAt = DateTime(2026, 6, 20, 12);
    final station =
        NiedStation(
            id: 1,
            code: 'KIK001',
            name: 'KIK001',
            coordinate: const LatLng(35, 135),
            network: 'KiK-net',
            prefecture: 'Test',
            expireSeconds: 10,
          )
          ..level = 8
          ..activity = 12.5
          ..ascend = 3
          ..isActive = false
          ..updateGifObservation(const NiedGifObservation(shindo: 0.5));

    const adapter = NiedStationObservationAdapter();
    final inactive = adapter.fromStation(station, observedAt: observedAt);
    station.isActive = true;
    final active = adapter.fromStation(station, observedAt: observedAt);

    expect(inactive.detectLevel, 8);
    expect(inactive.rawLevel, 8);
    expect(inactive.intensity, 0.5);
    expect(inactive.sensorRole, ObservationSensorRole.surface);
    expect(inactive.metadata['gif_display_primary_layer'], 'jma_s');
    expect(active.detectLevel, inactive.detectLevel);
    expect(active.intensity, inactive.intensity);
    expect(active.metadata, inactive.metadata);
  });
}
