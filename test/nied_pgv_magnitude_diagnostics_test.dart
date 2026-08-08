import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/nied_pgv_magnitude_diagnostics.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/jshis_surface_structure_api.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_observation_history.dart';
import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';

void main() {
  const pgvProvenance = ObservationProvenance(
    origin: ObservationOrigin.niedGifLayer,
    quantity: StationValueType.pgv,
    layerId: 'vcmap',
    isIndependentPhysicalMeasurement: true,
  );

  SeismicStationEventRecord record({
    required String code,
    required double latitude,
    required double pgv,
    required double colorPosition,
    double? intensity,
    bool triggered = true,
    List<({DateTime time, double pgv, double colorPosition})> pgvHistory =
        const [],
  }) {
    final timestamp = DateTime(2026, 8, 2, 12, 0, 3);
    final record = SeismicStationEventRecord(
      descriptor: SeismicStationDescriptor(
        stationId: code,
        code: code,
        sourceId: 'nied',
        network: 'K-NET',
        coordinate: LatLng(latitude, 140.0),
        sensorRole: StationSensorRole.surface,
      ),
      firstObservedAt: timestamp,
      firstTriggerAt: triggered ? timestamp : null,
      peakValue: intensity,
      lastValue: intensity,
    );
    record.provenance[StationValueType.pgv] = pgvProvenance;
    record.eventPhysicalPeaks[StationValueType.pgv] =
        SeismicPhysicalObservation(
          quantity: StationValueType.pgv,
          layerId: 'vcmap',
          value: pgv,
          colorPosition: colorPosition,
          dataTime: timestamp,
          receivedAt: timestamp.add(const Duration(milliseconds: 200)),
        );
    for (final item in pgvHistory) {
      final observation = SeismicPhysicalObservation(
        quantity: StationValueType.pgv,
        layerId: 'vcmap',
        value: item.pgv,
        colorPosition: item.colorPosition,
        dataTime: item.time,
        receivedAt: item.time,
      );
      record.observationHistory.add(
        SeismicStationObservationFrame(
          dataTime: item.time,
          receivedAt: item.time,
          value: null,
          rawLevel: null,
          detectLevel: null,
          isTriggered: triggered,
          qualityFlags: const {},
          physicalObservations: {StationValueType.pgv: observation},
        ),
      );
    }
    return record;
  }

  DateTime sArrival(DateTime origin) {
    final seconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: 10,
      depthKm: 10,
      pWave: false,
    );
    return origin.add(Duration(milliseconds: (seconds * 1000).round()));
  }

  test('keeps monotonic raw PGV observations as a blocked diagnostic', () {
    final diagnostics = niedGifPgvMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.10, pgv: 0.72, colorPosition: 0.57),
        record(code: 'B', latitude: 35.20, pgv: 0.34, colorPosition: 0.51),
        record(code: 'C', latitude: 35.30, pgv: 0.22, colorPosition: 0.47),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
    );

    expect(
      diagnostics['nied_gif_pgv_magnitude_model'],
      'si_midorikawa_1999_pgv600_hypocentral_placeholder_diagnostic_v2',
    );
    expect(diagnostics['nied_gif_pgv_magnitude_supported'], isFalse);
    expect(
      diagnostics['nied_gif_pgv_measurement_contract'],
      'per_second_maximum_integrated_acceleration_velocity_three_component_vector_synthesis',
    );
    expect(
      diagnostics['nied_gif_pgv_measurement_equivalent_to_si_midorikawa_1999_pgv600'],
      isFalse,
    );
    expect(
      diagnostics['nied_gif_pgv_measurement_contract_status'],
      'not_equivalent_to_si_midorikawa_1999_filtered_horizontal_pgv600',
    );
    expect(diagnostics['nied_gif_pgv_dispersion_acceptable'], isTrue);
    expect(diagnostics['nied_gif_pgv_station_count'], 3);
    expect(diagnostics['nied_gif_pgv_median'], isA<double>());
    expect(
      diagnostics['nied_gif_pgv_median'] as double,
      inInclusiveRange(3.7, 4.3),
    );
    expect(diagnostics['nied_gif_pgv_distance_min_km'], isA<double>());
    expect(diagnostics['nied_gif_pgv_distance_max_km'], isA<double>());
  });

  test('rejects censored final-color PGV observations', () {
    final diagnostics = niedGifPgvMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.10, pgv: 0.72, colorPosition: 0.57),
        record(code: 'B', latitude: 35.20, pgv: 0.34, colorPosition: 0.51),
        record(code: 'C', latitude: 35.30, pgv: 100, colorPosition: 1.0),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
    );

    expect(diagnostics['nied_gif_pgv_magnitude_supported'], isFalse);
    expect(diagnostics['nied_gif_pgv_station_count'], 2);
    expect(diagnostics['nied_gif_pgv_saturated_station_count'], 1);
  });

  test('uses only exact J-SHIS ARV terms for the ARV diagnostic', () {
    final baseline = niedGifPgvMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.10, pgv: 0.72, colorPosition: 0.57),
        record(code: 'B', latitude: 35.20, pgv: 0.34, colorPosition: 0.51),
        record(code: 'C', latitude: 35.30, pgv: 0.22, colorPosition: 0.47),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
    );
    final diagnostics = niedGifPgvJshisArvMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.10, pgv: 0.72, colorPosition: 0.57),
        record(code: 'B', latitude: 35.20, pgv: 0.34, colorPosition: 0.51),
        record(code: 'C', latitude: 35.30, pgv: 0.22, colorPosition: 0.47),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
      jshisArvTerms: const [
        NiedJshisArvDiagnosticTerm(
          stationCode: 'A',
          latitude: 35.10,
          longitude: 140.0,
          arv: 1.5,
          meshCode: 'mesh-a',
          datasetVersion: 'V4',
          rawResponsePath: 'raw/A.geojson',
        ),
        NiedJshisArvDiagnosticTerm(
          stationCode: 'B',
          latitude: 35.20,
          longitude: 140.0,
          arv: 1.5,
          meshCode: 'mesh-b',
          datasetVersion: 'V4',
          rawResponsePath: 'raw/B.geojson',
        ),
        NiedJshisArvDiagnosticTerm(
          stationCode: 'C',
          latitude: 35.30,
          longitude: 140.0,
          arv: 1.5,
          meshCode: 'mesh-c',
          datasetVersion: 'V4',
          rawResponsePath: 'raw/C.geojson',
        ),
      ],
    );

    expect(
      diagnostics['nied_gif_pgv_jshis_arv_magnitude_model'],
      'nied_gif_pgv_si_midorikawa_1999_jshis_arv_sensitivity_diagnostic_v2',
    );
    expect(diagnostics['nied_gif_pgv_jshis_arv_magnitude_supported'], isFalse);
    expect(diagnostics['nied_gif_pgv_jshis_arv_dispersion_acceptable'], isTrue);
    expect(diagnostics['nied_gif_pgv_jshis_arv_station_count'], 3);
    expect(
      diagnostics['nied_gif_pgv_jshis_arv_median'] as double,
      lessThan(baseline['nied_gif_pgv_median'] as double),
    );
  });

  test('does not use an ARV term from a different station coordinate', () {
    final diagnostics = niedGifPgvJshisArvMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.10, pgv: 0.72, colorPosition: 0.57),
        record(code: 'B', latitude: 35.20, pgv: 0.34, colorPosition: 0.51),
        record(code: 'C', latitude: 35.30, pgv: 0.22, colorPosition: 0.47),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
      jshisArvTerms: const [
        NiedJshisArvDiagnosticTerm(
          stationCode: 'A',
          latitude: 35.10,
          longitude: 140.0,
          arv: 1.5,
          meshCode: 'mesh-a',
          datasetVersion: 'V4',
          rawResponsePath: 'raw/A.geojson',
        ),
        NiedJshisArvDiagnosticTerm(
          stationCode: 'B',
          latitude: 35.20,
          longitude: 140.0,
          arv: 1.5,
          meshCode: 'mesh-b',
          datasetVersion: 'V4',
          rawResponsePath: 'raw/B.geojson',
        ),
        NiedJshisArvDiagnosticTerm(
          stationCode: 'C',
          latitude: 35.31,
          longitude: 140.0,
          arv: 1.5,
          meshCode: 'mesh-c',
          datasetVersion: 'V4',
          rawResponsePath: 'raw/C.geojson',
        ),
      ],
    );

    expect(diagnostics['nied_gif_pgv_jshis_arv_magnitude_supported'], isFalse);
    expect(diagnostics['nied_gif_pgv_jshis_arv_station_count'], 2);
    expect(
      diagnostics['nied_gif_pgv_jshis_arv_missing_exact_station_count'],
      1,
    );
  });

  test(
    'uses the PGV event-participant gate for the same-geometry comparator',
    () {
      final diagnostics = niedGifJmaStyleIntensityMagnitudeDiagnostics(
        stations: [
          record(
            code: 'A',
            latitude: 35.10,
            pgv: 0.72,
            colorPosition: 0.57,
            intensity: 2.1,
          ),
          record(
            code: 'B',
            latitude: 35.20,
            pgv: 0.34,
            colorPosition: 0.51,
            intensity: 1.5,
          ),
          record(
            code: 'C',
            latitude: 35.30,
            pgv: 0.22,
            colorPosition: 0.47,
            intensity: 0.8,
          ),
          record(
            code: 'outside-event',
            latitude: 35.40,
            pgv: 20,
            colorPosition: 0.9,
            intensity: 6.8,
            triggered: false,
          ),
        ],
        sourceLatitude: 35.0,
        sourceLongitude: 140.0,
        depthKm: 10.0,
      );

      expect(
        diagnostics['nied_gif_jma_style_magnitude_model'],
        'si_midorikawa_1999_pgv_derived_intensity_hypocentral_placeholder_v2',
      );
      expect(diagnostics['nied_gif_jma_style_magnitude_supported'], isFalse);
      expect(diagnostics['nied_gif_jma_style_dispersion_acceptable'], isTrue);
      expect(diagnostics['nied_gif_jma_style_station_count'], 3);
      expect(diagnostics['nied_gif_jma_style_nonparticipant_station_count'], 1);
      expect(diagnostics['nied_gif_jma_style_minimum_station_intensity'], -0.8);
      expect(diagnostics['nied_gif_jma_style_median'], isA<double>());
      expect(
        diagnostics['nied_gif_jma_style_median'] as double,
        inInclusiveRange(3.4, 4.4),
      );
    },
  );

  test('keeps the distance-weighted PGV sensitivity experiment blocked', () {
    final diagnostics = niedGifPgvDistanceWeightedMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.01, pgv: 0.20, colorPosition: 0.4),
        record(code: 'B', latitude: 35.02, pgv: 0.24, colorPosition: 0.4),
        record(code: 'C', latitude: 35.03, pgv: 0.30, colorPosition: 0.4),
        record(code: 'D', latitude: 35.04, pgv: 0.34, colorPosition: 0.4),
        record(code: 'E', latitude: 35.05, pgv: 0.38, colorPosition: 0.4),
        record(code: 'F', latitude: 35.06, pgv: 0.42, colorPosition: 0.4),
        record(code: 'G', latitude: 35.07, pgv: 0.46, colorPosition: 0.4),
        record(code: 'H', latitude: 35.08, pgv: 0.50, colorPosition: 0.4),
        record(code: 'I', latitude: 35.09, pgv: 4.00, colorPosition: 0.4),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
    );

    expect(
      diagnostics['nied_gif_pgv_distance_weighted_magnitude_model'],
      'nied_gif_pgv_distance_weighted_si_midorikawa_1999_sensitivity_v2',
    );
    expect(
      diagnostics['nied_gif_pgv_distance_weighted_magnitude_supported'],
      isFalse,
    );
    expect(
      diagnostics['nied_gif_pgv_distance_weighted_dispersion_acceptable'],
      isTrue,
    );
    expect(diagnostics['nied_gif_pgv_distance_weighted_candidate_count'], 9);
    expect(diagnostics['nied_gif_pgv_distance_weighted_station_count'], 8);
    expect(
      diagnostics['nied_gif_pgv_distance_weighted_source_quality'],
      'diagnostic_only_blocked_nied_vcmap_measurement_contract_unknown',
    );
  });

  test('permits a non-production nearest-station diagnostic sweep', () {
    final diagnostics = niedGifPgvDistanceWeightedMagnitudeDiagnostics(
      stations: [
        record(code: 'A', latitude: 35.01, pgv: 0.20, colorPosition: 0.4),
        record(code: 'B', latitude: 35.02, pgv: 0.24, colorPosition: 0.4),
        record(code: 'C', latitude: 35.03, pgv: 0.30, colorPosition: 0.4),
        record(code: 'D', latitude: 35.04, pgv: 0.34, colorPosition: 0.4),
        record(code: 'E', latitude: 35.05, pgv: 0.38, colorPosition: 0.4),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10.0,
      nearestStationCount: 3,
    );

    expect(
      diagnostics['nied_gif_pgv_distance_weighted_nearest_station_limit'],
      3,
    );
    expect(diagnostics['nied_gif_pgv_distance_weighted_station_count'], 3);
  });

  test('rejects raw PGV peaks that only occur before the S-wave window', () {
    final origin = DateTime.utc(2026, 8, 2, 12);
    final diagnostics = niedGifPgvSArrivalWindowMagnitudeDiagnostics(
      stations: [
        for (final code in ['A', 'B', 'C'])
          record(
            code: code,
            latitude: 35.0,
            pgv: 0.4,
            colorPosition: 0.4,
            pgvHistory: [
              (
                time: origin.add(const Duration(seconds: 1)),
                pgv: 0.4,
                colorPosition: 0.4,
              ),
            ],
          ),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10,
      sourceOriginTime: origin,
    );

    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_magnitude_supported'],
      isFalse,
    );
    expect(diagnostics['nied_gif_pgv_s_arrival_window_station_count'], 0);
    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_pre_s_peak_excluded_station_count'],
      3,
    );
  });

  test('uses the largest uncensored raw PGV inside the S-wave window', () {
    final origin = DateTime.utc(2026, 8, 2, 12);
    final arrival = sArrival(origin);
    final diagnostics = niedGifPgvSArrivalWindowMagnitudeDiagnostics(
      stations: [
        for (final (code, pgv) in [('A', 0.20), ('B', 0.28), ('C', 0.36)])
          record(
            code: code,
            latitude: 35.0,
            pgv: pgv,
            colorPosition: 0.4,
            pgvHistory: [
              (
                time: arrival.subtract(const Duration(seconds: 3)),
                pgv: 2.0,
                colorPosition: 0.4,
              ),
              (
                time: arrival.add(const Duration(seconds: 4)),
                pgv: pgv,
                colorPosition: 0.4,
              ),
            ],
          ),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10,
      sourceOriginTime: origin,
    );

    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_magnitude_model'],
      'nied_gif_pgv_s_arrival_window_diagnostic_v1',
    );
    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_magnitude_supported'],
      isFalse,
    );
    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_dispersion_acceptable'],
      isTrue,
    );
    expect(diagnostics['nied_gif_pgv_s_arrival_window_station_count'], 3);
    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_pre_s_peak_excluded_station_count'],
      3,
    );
  });

  test('rejects raw PGV peaks that only occur after the S-wave window', () {
    final origin = DateTime.utc(2026, 8, 2, 12);
    final arrival = sArrival(origin);
    final diagnostics = niedGifPgvSArrivalWindowMagnitudeDiagnostics(
      stations: [
        for (final code in ['A', 'B', 'C'])
          record(
            code: code,
            latitude: 35.0,
            pgv: 0.4,
            colorPosition: 0.4,
            pgvHistory: [
              (
                time: arrival.add(const Duration(seconds: 21)),
                pgv: 0.4,
                colorPosition: 0.4,
              ),
            ],
          ),
      ],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10,
      sourceOriginTime: origin,
    );

    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_magnitude_supported'],
      isFalse,
    );
    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_post_s_peak_excluded_station_count'],
      3,
    );
  });

  test(
    'does not fall back when fewer than three stations have S-window PGV',
    () {
      final origin = DateTime.utc(2026, 8, 2, 12);
      final arrival = sArrival(origin);
      final diagnostics = niedGifPgvSArrivalWindowMagnitudeDiagnostics(
        stations: [
          for (final code in ['A', 'B'])
            record(
              code: code,
              latitude: 35.0,
              pgv: 0.4,
              colorPosition: 0.4,
              pgvHistory: [(time: arrival, pgv: 0.4, colorPosition: 0.4)],
            ),
        ],
        sourceLatitude: 35.0,
        sourceLongitude: 140.0,
        depthKm: 10,
        sourceOriginTime: origin,
      );

      expect(
        diagnostics['nied_gif_pgv_s_arrival_window_magnitude_supported'],
        isFalse,
      );
      expect(diagnostics['nied_gif_pgv_s_arrival_window_station_count'], 2);
    },
  );

  test('rejects an S-wave window diagnostic without an origin time', () {
    final diagnostics = niedGifPgvSArrivalWindowMagnitudeDiagnostics(
      stations: const [],
      sourceLatitude: 35.0,
      sourceLongitude: 140.0,
      depthKm: 10,
      sourceOriginTime: null,
    );

    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_magnitude_supported'],
      isFalse,
    );
    expect(
      diagnostics['nied_gif_pgv_s_arrival_window_source_quality'],
      'missing_or_invalid_source_geometry_or_origin_time',
    );
  });
}
