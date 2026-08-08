import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/kanameishi_jma2001_travel_time_table.dart';

void main() {
  test(
    'matches fixed samples from kanameishi TravelTimes.js interpolation',
    () {
      for (final sample in const [
        (depthKm: 10.0, distanceKm: 100.0, p: 17.037, s: 29.054),
        (depthKm: 110.0, distanceKm: 250.0, p: 36.632, s: 64.498),
        (depthKm: 30.0, distanceKm: 45.0, p: 8.7095, s: 14.9075),
        (depthKm: 0.0, distanceKm: 2000.0, p: 252.705, s: 451.912),
      ]) {
        expect(
          KanameishiJma2001TravelTimeTable.travelTimeSeconds(
            surfaceDistanceKm: sample.distanceKm,
            depthKm: sample.depthKm,
            pWave: true,
          ),
          closeTo(sample.p, 1e-9),
        );
        expect(
          KanameishiJma2001TravelTimeTable.travelTimeSeconds(
            surfaceDistanceKm: sample.distanceKm,
            depthKm: sample.depthKm,
            pWave: false,
          ),
          closeTo(sample.s, 1e-9),
        );
      }
    },
  );
}
