import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';

void main() {
  test(
    'NIED wave display uses algorithm radii for historical replay frames',
    () {
      final estimate = SourceEstimate(
        latitude: 39.0,
        longitude: 142.0,
        depthKm: 40,
        originTime: DateTime(2026, 6, 30, 12),
        confidence: 0.5,
        method: 'nied_dart_hyp_v1',
        supportingStationCount: 12,
        diagnostics: const {
          'best_source_p_radius_km': 123.5,
          'best_source_s_radius_km': 67.25,
        },
      );

      final radii = niedWaveRadiiFromEstimate(estimate);

      expect(radii.pRadiusKm, 123.5);
      expect(radii.sRadiusKm, 67.25);
    },
  );

  test('NIED wave display preserves the algorithm hidden-radius sentinel', () {
    const estimate = SourceEstimate(
      latitude: 39.0,
      longitude: 142.0,
      depthKm: 40,
      confidence: 0.5,
      method: 'nied_dart_hyp_v1',
      supportingStationCount: 12,
      diagnostics: {
        'best_source': {'pRadiusKm': 999999.0, 'sRadiusKm': 999999.0},
      },
    );

    final radii = niedWaveRadiiFromEstimate(estimate);

    expect(radii.pRadiusKm, 999999.0);
    expect(radii.sRadiusKm, 999999.0);
  });

  test(
    'NIED wave display continues from the last real algorithm elapsed time',
    () {
      final estimate = SourceEstimate(
        latitude: 35.783,
        longitude: 141.317,
        depthKm: 10,
        originTime: DateTime(2026, 7, 18, 4, 45, 14),
        confidence: 0.37,
        method: 'nied_dart_hyp_v1',
        supportingStationCount: 209,
        diagnostics: const {
          'wave_elapsed_s': 127.0,
          'wave_radius_cap_km': 1200.0,
          'best_source_p_radius_km': 950.0,
          'best_source_s_radius_km': 520.0,
        },
      );

      final radii = niedWaveRadiiFromEstimate(
        estimate,
        algorithmElapsedSeconds: 141.0,
      );

      expect(
        radii.pRadiusKm,
        closeTo(
          Jma2001TravelTimeApproximation.epicentralRadiusKm(
            elapsedSeconds: 141,
            depthKm: 10,
            pWave: true,
          ),
          1e-9,
        ),
      );
      expect(
        radii.sRadiusKm,
        closeTo(
          Jma2001TravelTimeApproximation.epicentralRadiusKm(
            elapsedSeconds: 141,
            depthKm: 10,
            pWave: false,
          ),
          1e-9,
        ),
      );
      expect(radii.pRadiusKm, isNot(950.0));
      expect(radii.sRadiusKm, isNot(520.0));
    },
  );

  test('continued NIED wave display keeps the algorithm cap and 300s hide', () {
    final estimate = SourceEstimate(
      latitude: 35.783,
      longitude: 141.317,
      depthKm: 10,
      confidence: 0.37,
      method: 'nied_dart_hyp_v1',
      supportingStationCount: 209,
      diagnostics: const {
        'wave_radius_cap_km': 600.0,
        'best_source_p_radius_km': 500.0,
        'best_source_s_radius_km': 300.0,
      },
    );

    final capped = niedWaveRadiiFromEstimate(
      estimate,
      algorithmElapsedSeconds: 200.0,
    );
    expect(capped.pRadiusKm, 600.0);
    expect(capped.sRadiusKm, greaterThan(0));
    expect(capped.sRadiusKm, lessThanOrEqualTo(600.0));

    final hidden = niedWaveRadiiFromEstimate(
      estimate,
      algorithmElapsedSeconds: 300.0,
    );
    expect(hidden.pRadiusKm, 999999.0);
    expect(hidden.sRadiusKm, 999999.0);
  });
}
