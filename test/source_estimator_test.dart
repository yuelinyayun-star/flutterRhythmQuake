import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/core/source_estimation/kanameishi_jma2001_travel_time_table.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/screens/main_screen.dart';

void main() {
  test(
    'NIED curve display extent uses only real station distance and time',
    () {
      final fukushima = niedHypCurveDisplayExtent(
        distanceMaxKm: 43.016,
        observedMinSeconds: 0,
        observedMaxSeconds: 3,
      );
      expect(fukushima.minX, 0);
      expect(fukushima.maxX, 43.016);
      expect(fukushima.minY, 0);
      expect(fukushima.maxY, 3);

      final iwate = niedHypCurveDisplayExtent(
        distanceMaxKm: 135.328,
        observedMinSeconds: 0,
        observedMaxSeconds: 20,
      );
      expect(iwate.minX, 0);
      expect(iwate.maxX, 135.328);
      expect(iwate.minY, 0);
      expect(iwate.maxY, 20);

      final zeroSpan = niedHypCurveDisplayExtent(
        distanceMaxKm: 0,
        observedMinSeconds: 0,
        observedMaxSeconds: 0,
      );
      expect(zeroSpan.maxX, 1);
      expect(zeroSpan.minY, 0);
      expect(zeroSpan.maxY, 1);
    },
  );

  test('trigger time grid estimator converges near synthetic epicenter', () {
    const estimator = TriggerTimeGridSearchEstimator();
    const epicenter = LatLng(35.50, 140.50);
    final origin = DateTime(2026, 6, 10, 12, 0, 0);
    final distance = const Distance();
    const speedKmps = 3.8;

    SeismicStationEventRecord buildRecord(
      String code,
      double lat,
      double lng,
      double shindo,
    ) {
      final station = LatLng(lat, lng);
      final distanceKm = distance.as(LengthUnit.Kilometer, epicenter, station);
      final triggerAt = origin.add(
        Duration(milliseconds: (distanceKm / speedKmps * 1000).round()),
      );
      return SeismicStationEventRecord(
        descriptor: SeismicStationDescriptor(
          stationId: code,
          code: code,
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: station,
        ),
        firstObservedAt: triggerAt,
        firstRiseAt: triggerAt,
        firstTriggerAt: triggerAt,
        lastObservedAt: triggerAt,
        peakAt: triggerAt,
        peakValue: shindo,
        lastValue: shindo,
        state: StationLifecycleState.triggered,
      );
    }

    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'synthetic-1',
      observedAt: origin.add(const Duration(seconds: 5)),
      stageName: 'detected',
      maxShindo: 2,
      stations: [
        buildRecord('A', 35.30, 140.30, 0.6),
        buildRecord('B', 35.75, 140.35, 0.4),
        buildRecord('C', 35.42, 140.84, 0.5),
        buildRecord('D', 35.68, 140.72, 0.3),
      ],
    );

    final result = estimator.estimate(request);
    expect(result, isNotNull);
    expect((result!.latitude - epicenter.latitude).abs(), lessThan(0.18));
    expect((result.longitude - epicenter.longitude).abs(), lessThan(0.18));
    expect(result.method, 'trigger_time_grid_v2');
  });

  test('trigger time grid estimator falls back when timing data is sparse', () {
    const estimator = TriggerTimeGridSearchEstimator(
      fallback: WeightedCentroidSourceEstimator(),
    );
    final now = DateTime(2026, 6, 10, 12, 0, 0);
    final records = [
      SeismicStationEventRecord(
        descriptor: const SeismicStationDescriptor(
          stationId: 'A',
          code: 'A',
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: LatLng(35.0, 140.0),
        ),
        firstObservedAt: now,
        lastObservedAt: now,
        peakValue: 0.4,
        lastValue: 0.4,
        state: StationLifecycleState.triggered,
      ),
      SeismicStationEventRecord(
        descriptor: const SeismicStationDescriptor(
          stationId: 'B',
          code: 'B',
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: LatLng(35.2, 140.2),
        ),
        firstObservedAt: now,
        lastObservedAt: now,
        peakValue: 0.6,
        lastValue: 0.6,
        state: StationLifecycleState.triggered,
      ),
    ];
    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'synthetic-2',
      observedAt: now,
      stageName: 'detected',
      maxShindo: 1,
      stations: records,
    );

    final result = estimator.estimate(request);
    expect(result, isNotNull);
    expect(result!.method, 'weighted_centroid_baseline');
  });

  test(
    'trigger time depth grid estimator recovers a shallow synthetic depth',
    () {
      const estimator = TriggerTimeDepthGridSearchEstimator(
        depthCandidatesKm: [0, 10, 20, 30, 40, 60],
        coarseStepDeg: 0.15,
        fineStepDeg: 0.05,
        refineStepDeg: 0.02,
      );
      const epicenter = LatLng(36.20, 141.10);
      const depthKm = 30.0;
      const speedKmps = 4.0;
      final origin = DateTime(2026, 6, 10, 13, 0, 0);
      final distance = const Distance();

      SeismicStationEventRecord buildRecord(
        String code,
        double lat,
        double lng,
        double shindo,
      ) {
        final station = LatLng(lat, lng);
        final surfaceDistanceKm = distance.as(
          LengthUnit.Kilometer,
          epicenter,
          station,
        );
        final travelDistanceKm = math.sqrt(
          surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
        );
        final triggerAt = origin.add(
          Duration(milliseconds: (travelDistanceKm / speedKmps * 1000).round()),
        );
        return SeismicStationEventRecord(
          descriptor: SeismicStationDescriptor(
            stationId: code,
            code: code,
            sourceId: 'global',
            network: 'TEST',
            coordinate: station,
          ),
          firstObservedAt: triggerAt,
          firstRiseAt: triggerAt,
          firstTriggerAt: triggerAt,
          lastObservedAt: triggerAt,
          peakAt: triggerAt,
          peakValue: shindo,
          lastValue: shindo,
          state: StationLifecycleState.triggered,
        );
      }

      final request = SourceEstimationRequest(
        sourceId: 'global',
        eventId: 'synthetic-3',
        observedAt: origin.add(const Duration(seconds: 10)),
        stageName: 'detected',
        maxShindo: 3,
        stations: [
          buildRecord('A', 36.05, 140.90, 1.2),
          buildRecord('B', 36.45, 140.95, 0.9),
          buildRecord('C', 36.12, 141.42, 1.0),
          buildRecord('D', 36.40, 141.28, 0.8),
          buildRecord('E', 35.98, 141.05, 1.1),
        ],
      );

      final result = estimator.estimate(request);
      expect(result, isNotNull);
      expect((result!.latitude - epicenter.latitude).abs(), lessThan(0.15));
      expect((result.longitude - epicenter.longitude).abs(), lessThan(0.15));
      expect(result.depthKm, isNotNull);
      expect((result.depthKm! - depthKm).abs(), lessThanOrEqualTo(15));
      if (result.diagnostics['diagnostic_magnitude_supported'] == true) {
        expect(result.magnitude, isA<double>());
        expect(
          result.magnitude,
          result.diagnostics['diagnostic_magnitude_jma_style'],
        );
      }
      expect(result.method, 'trigger_time_depth_grid_v3');
    },
  );

  test('NIED hybrid reports one-sided station geometry', () {
    const estimator = NiedGifHybridSourceEstimator(bboxPaddingDeg: 2.0);
    const epicenter = LatLng(36.20, 142.00);
    const speedKmps = 3.8;
    final origin = DateTime(2026, 6, 22, 12);
    final distance = const Distance();

    SeismicStationEventRecord record(String code, double lat, double lng) {
      final station = LatLng(lat, lng);
      final distanceKm = distance.as(LengthUnit.Kilometer, epicenter, station);
      final triggerAt = origin.add(
        Duration(milliseconds: (distanceKm / speedKmps * 1000).round()),
      );
      return SeismicStationEventRecord(
        descriptor: SeismicStationDescriptor(
          stationId: code,
          code: code,
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: station,
        ),
        firstObservedAt: triggerAt,
        firstRiseAt: triggerAt,
        firstTriggerAt: triggerAt,
        lastObservedAt: triggerAt,
        peakAt: triggerAt,
        peakValue: 0.5,
        lastValue: 0.5,
        state: StationLifecycleState.triggered,
      );
    }

    final records = [
      record('A', 35.80, 140.90),
      record('B', 36.10, 140.80),
      record('C', 36.40, 140.85),
      record('D', 36.65, 140.95),
      record('E', 36.25, 141.05),
    ];
    final result = estimator.estimate(
      SourceEstimationRequest(
        sourceId: 'nied',
        eventId: 'synthetic-offshore',
        observedAt: origin.add(const Duration(seconds: 40)),
        stageName: 'confirmed',
        maxShindo: 1,
        stations: records,
        metadata: {
          'nied_input_kind': 'gif',
          'source_trigger_member_ids': records
              .map((entry) => entry.descriptor.code)
              .toList(),
        },
      ),
    );

    expect(result, isNotNull);
    expect(result!.diagnostics['station_geometry'], 'one_sided');
    expect(
      result.diagnostics['station_azimuthal_gap_deg'] as double,
      greaterThan(180),
    );
    expect(
      result.diagnostics['nearest_station_distance_km'] as double,
      greaterThan(20),
    );
    expect(result.diagnostics['search_boundary_margin_deg'], isA<double>());
    expect(result.diagnostics['search_boundary_hit'], isA<bool>());
    expect(result.diagnostics['geometry_penalty'], isA<double>());
    expect(result.diagnostics['phase_line_score'], isA<double>());
    expect(result.diagnostics['grouped_phase_line_score'], isA<double>());
    expect(
      result.diagnostics['grouped_phase_line_mean_residual_s'],
      isA<double>(),
    );
    expect(result.diagnostics['grouped_phase_best_depth_km'], isA<double>());
    expect(
      result.diagnostics['grouped_phase_depth_mean_residual_s'],
      isA<double>(),
    );
    expect(result.diagnostics['grouped_phase_line_p_count'], isA<int>());
    expect(result.diagnostics['grouped_phase_line_s_count'], isA<int>());
    expect(result.diagnostics['grouped_phase_line_other_count'], isA<int>());
    expect(result.diagnostics['diagnostic_magnitude_supported'], isA<bool>());
    expect(
      result.diagnostics['diagnostic_magnitude_station_count'],
      isA<int>(),
    );
    expect(result.diagnostics['diagnostic_magnitude_depth_km'], isA<double>());
    expect(
      result.diagnostics['diagnostic_magnitude_depth_source'],
      isA<String>(),
    );
    expect(result.diagnostics['diagnostic_magnitude_model'], isA<String>());
    if (result.diagnostics['diagnostic_magnitude_supported'] == true) {
      expect(result.magnitude, isA<double>());
      expect(
        result.magnitude,
        result.diagnostics['diagnostic_magnitude_jma_style'],
      );
    }
    expect(result.diagnostics['p_only_line_mean_residual_s'], isA<double>());
    expect(result.diagnostics['p_only_line_residual_p90_s'], isA<double>());
    expect(result.diagnostics['p_only_best_depth_km'], isA<double>());
    expect(result.diagnostics['p_only_depth_mean_residual_s'], isA<double>());
    expect(result.diagnostics['s_only_line_mean_residual_s'], isA<double>());
    expect(result.diagnostics['s_only_line_residual_p90_s'], isA<double>());
    expect(result.diagnostics['phase_difference_score'], isA<double>());
    expect(
      result.diagnostics['phase_difference_mean_residual_s'],
      isA<double>(),
    );
    expect(result.diagnostics['phase_difference_pair_count'], isA<int>());
    expect(result.diagnostics['phase_line_p_count'], isA<int>());
    expect(result.diagnostics['phase_line_s_count'], isA<int>());
    expect(result.diagnostics['phase_line_other_count'], isA<int>());
    expect(result.diagnostics['phase_line_mean_residual_s'], isA<double>());
    expect(result.diagnostics['horizontal_uncertainty_p50_km'], isA<double>());
    expect(result.diagnostics['horizontal_uncertainty_p90_km'], isA<double>());
    final hyp = result.diagnostics['nied_gif_hyp_v1'] as Map<String, Object?>;
    expect(hyp['method'], 'nied_gif_hyp_v1');
    expect(hyp['supported'], isA<bool>());
    expect(hyp['latitude'], isA<double>());
    expect(hyp['longitude'], isA<double>());
    expect(hyp['depth_km'], isA<double>());
    expect(hyp['origin_time'], isA<String>());
    expect(hyp['phase_mean_residual_s'], isA<double>());
    expect(hyp['pair_mean_residual_s'], isA<double>());
    expect(hyp['unarrived_penalty'], isA<double>());
  });

  test('NIED HYP diagnostic recovers synthetic P and S phase source', () {
    const estimator = NiedGifHybridSourceEstimator(
      bboxPaddingDeg: 0.7,
      coarseStepDeg: 0.18,
      fineStepDeg: 0.05,
      emitJma2001HypExperiment: true,
      emitJqScoringHypExperiment: true,
      emitKotoho7HypExperiment: true,
    );
    const epicenter = LatLng(36.20, 141.10);
    const depthKm = 60.0;
    final origin = DateTime(2026, 6, 22, 13);
    final distance = const Distance();

    SeismicStationEventRecord record(
      String code,
      double lat,
      double lng, {
      required bool sPhase,
    }) {
      final station = LatLng(lat, lng);
      final surfaceDistanceKm = distance.as(
        LengthUnit.Kilometer,
        epicenter,
        station,
      );
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      final speedKmps = sPhase ? 3.5 : 6.0;
      final triggerAt = origin.add(
        Duration(
          milliseconds: (hypocentralDistanceKm / speedKmps * 1000).round(),
        ),
      );
      return SeismicStationEventRecord(
        descriptor: SeismicStationDescriptor(
          stationId: code,
          code: code,
          sourceId: 'nied',
          network: 'K-NET',
          coordinate: station,
        ),
        firstObservedAt: triggerAt,
        firstRiseAt: triggerAt,
        firstTriggerAt: triggerAt,
        lastObservedAt: triggerAt,
        peakAt: triggerAt,
        peakValue: sPhase ? 0.7 : 0.9,
        lastValue: sPhase ? 0.7 : 0.9,
        state: StationLifecycleState.triggered,
      );
    }

    final records = [
      record('P1', 36.05, 140.95, sPhase: false),
      record('P2', 36.35, 140.95, sPhase: false),
      record('P3', 36.05, 141.25, sPhase: false),
      record('P4', 36.35, 141.25, sPhase: false),
      record('S1', 35.95, 141.10, sPhase: true),
      record('S2', 36.45, 141.10, sPhase: true),
      record('S3', 36.20, 140.75, sPhase: true),
      record('S4', 36.20, 141.45, sPhase: true),
    ];
    final result = estimator.estimate(
      SourceEstimationRequest(
        sourceId: 'nied',
        eventId: 'synthetic-hyp',
        observedAt: origin.add(const Duration(seconds: 45)),
        stageName: 'confirmed',
        maxShindo: 2,
        stations: records,
        metadata: {
          'nied_input_kind': 'gif',
          'source_trigger_member_ids': records
              .map((entry) => entry.descriptor.code)
              .toList(),
        },
      ),
    );

    expect(result, isNotNull);
    final hyp = result!.diagnostics['nied_gif_hyp_v1'] as Map<String, Object?>;
    expect(hyp['supported'], isTrue);
    expect(hyp['depth_supported'], isTrue);
    expect(result.depthKm, isA<double>());
    expect(result.depthKm, hyp['depth_km']);
    expect(
      ((hyp['latitude']! as double) - epicenter.latitude).abs(),
      lessThan(0.25),
    );
    expect(
      ((hyp['longitude']! as double) - epicenter.longitude).abs(),
      lessThan(0.25),
    );
    expect(
      ((hyp['depth_km']! as double) - depthKm).abs(),
      lessThanOrEqualTo(30),
    );
    expect(hyp['phase_p_count'], greaterThanOrEqualTo(3));
    expect(hyp['phase_s_count'], greaterThanOrEqualTo(3));
    final jmaHyp =
        result.diagnostics['nied_gif_hyp_jma2001_experiment']
            as Map<String, Object?>;
    expect(jmaHyp['method'], 'nied_gif_hyp_jma2001_experiment');
    expect(
      jmaHyp['travel_time_model'],
      'jma2001_polynomial_from_jq_reference_js',
    );
    expect(jmaHyp['latitude'], isA<double>());
    expect(jmaHyp['longitude'], isA<double>());
    final jqHyp =
        result.diagnostics['nied_gif_hyp_jq_scoring_experiment']
            as Map<String, Object?>;
    expect(jqHyp['method'], 'nied_gif_hyp_jq_scoring_experiment');
    expect(
      jqHyp['travel_time_model'],
      'jma2001_polynomial_from_jq_reference_js',
    );
    expect(
      jqHyp['scoring_model'],
      'jq_reference_candidate_s_flag_origin_variance_v1',
    );
    expect(jqHyp['latitude'], isA<double>());
    expect(jqHyp['longitude'], isA<double>());
    expect(jqHyp['origin_offset_s'], isA<double>());
    expect(jqHyp['phase_mean_residual_s'], isA<double>());
    expect(jqHyp['phase_balance_penalty'], isA<double>());
    expect(jqHyp['phase_origin_model'], 'diagnostic_phase_origin_clusters_v1');
    expect(
      jqHyp['station_s_flag_model'],
      'candidate_predicted_s_closer_than_p_after_15s_v1',
    );
    expect(jqHyp['s_phase_gate_elapsed_s'], isA<double>());
    expect(jqHyp['s_phase_gate_open'], isA<bool>());
    final referenceState =
        jqHyp['jq_reference_state_proxy'] as Map<String, Object?>;
    expect(referenceState['model'], 'jq_reference_state_proxy_v1');
    expect(referenceState['status'], 'proxy_not_full_state_machine');
    expect(referenceState['current_cloud_time_s'], isA<double>());
    expect(referenceState['s_gate_open'], isA<bool>());
    final sourceCache =
        referenceState['source_cache_4_4_proxy'] as Map<String, Object?>;
    expect(sourceCache['plus_2_longitude'], isA<double>());
    expect(sourceCache['plus_3_latitude'], isA<double>());
    expect(sourceCache['plus_4_depth_km'], isA<double>());
    expect(sourceCache['plus_5_origin_time_s'], isA<double>());
    final stationCounts =
        referenceState['station_state_counts'] as Map<String, Object?>;
    expect(stationCounts['ten_plus_6_s_closer_than_p_count'], isA<int>());
    expect(
      stationCounts['reference_like_ten_plus_6_s_closer_than_p_count'],
      isA<int>(),
    );
    expect(
      stationCounts['ten_plus_5_pretrigger_cache_proxy_count'],
      isA<int>(),
    );
    expect(
      stationCounts['nearest_7_old_trigger_fallback_proxy_count'],
      isA<int>(),
    );
    final stationRows = referenceState['stations'] as List<Object?>;
    expect(stationRows, isNotEmpty);
    final stationRow = stationRows.first as Map<String, Object?>;
    expect(stationRow['ten_plus_1_observed_time_s'], isA<double>());
    expect(stationRow['ten_plus_1_reference_like_time_s'], isA<double>());
    expect(stationRow['ten_plus_1_reference_like_source'], isA<String>());
    expect(stationRow['ten_plus_3_detection_id_proxy'], 1);
    expect(
      stationRow['nearest_7_old_trigger_station_codes'],
      isA<List<Object?>>(),
    );
    expect(
      stationRow['ten_plus_5_pretrigger_cache_model'],
      'stateful_rising_frame_write_clear_proxy_v1',
    );
    expect(stationRow['ten_plus_6_s_closer_than_p'], isA<bool>());
    expect(
      stationRow['reference_like_ten_plus_6_s_closer_than_p'],
      isA<bool>(),
    );
    expect(stationRow['ten_plus_7_predicted_p_arrival_s'], isA<double>());
    expect(stationRow['ten_plus_8_predicted_s_arrival_s'], isA<double>());
    expect(jqHyp['p_origin_cluster_count'], isA<int>());
    expect(jqHyp['s_origin_cluster_count'], isA<int>());
    expect(jqHyp['phase_origin_mean_gap_s'], anyOf(isA<double>(), isNull));
    final jqSearch = jqHyp['search'] as Map<String, Object?>;
    final jqStages = jqSearch['stages'] as List<Object?>;
    expect(
      jqStages
          .map((entry) => (entry as Map<String, Object?>)['stage'])
          .toList(),
      containsAllInOrder(['coarse', 'fine', 'jq_refine']),
    );
    final kotoho7Hyp =
        result.diagnostics['nied_gif_hyp_kotoho7_reference_replay_v1']
            as Map<String, Object?>;
    expect(kotoho7Hyp['method'], 'nied_gif_hyp_kotoho7_reference_replay_v1');
    expect(kotoho7Hyp['reference_title'], '揺れ検知から震央を検出してみる');
    expect(
      kotoho7Hyp['scoring_model'],
      'kotoho7_article_error_level_with_s_flag_proxy_v2',
    );
    expect(kotoho7Hyp['latitude'], isA<double>());
    expect(kotoho7Hyp['longitude'], isA<double>());
    expect(kotoho7Hyp['depth_km'], isA<double>());
    expect(kotoho7Hyp['origin_offset_s'], isA<double>());
    expect(kotoho7Hyp['phase_mean_residual_s'], isA<double>());
    expect(kotoho7Hyp['unarrived_penalty'], isA<double>());
    final kotoho7Search = kotoho7Hyp['search'] as Map<String, Object?>;
    final kotoho7Stages = kotoho7Search['stages'] as List<Object?>;
    expect(
      kotoho7Stages
          .map((entry) => (entry as Map<String, Object?>)['stage'])
          .toList(),
      containsAllInOrder([
        'start-h2',
        'start-h10',
        'start-h10-v50',
        'start-h10-v10',
      ]),
    );
  });

  test('kotoho7 replay reuses an existing detection-id source cache', () {
    final estimator = Kotoho7ReferenceHypSourceEstimator();
    const epicenter = LatLng(39.95, 142.20);
    const depthKm = 30.0;
    final origin = DateTime(2026, 6, 22, 11, 27, 0);
    final distance = const Distance();

    SeismicStationEventRecord record(String code) {
      final stationEntry = NiedStationDb.stations.firstWhere(
        (station) => station['code'] == code,
      );
      final lat = (stationEntry['lat'] as num).toDouble();
      final lon = (stationEntry['lng'] as num).toDouble();
      final station = LatLng(lat, lon);
      final surfaceDistanceKm = distance.as(
        LengthUnit.Kilometer,
        epicenter,
        station,
      );
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: true,
      );
      final triggerAt = origin.add(
        Duration(milliseconds: (travelSeconds * 1000).round()),
      );
      return SeismicStationEventRecord(
        descriptor: SeismicStationDescriptor(
          stationId: code,
          code: code,
          sourceId: 'nied',
          network: stationEntry['network'] as String,
          coordinate: station,
        ),
        firstObservedAt: triggerAt,
        firstRiseAt: triggerAt,
        firstTriggerAt: triggerAt,
        lastObservedAt: triggerAt,
        peakAt: triggerAt,
        peakValue: 0.8,
        lastValue: 0.8,
        state: StationLifecycleState.triggered,
      );
    }

    final records = [
      record('IWT004'),
      record('IWT003'),
      record('IWTH14'),
      record('IWT005'),
      record('IWT002'),
      record('IWTH09'),
    ];

    SourceEstimationRequest request(String eventId) => SourceEstimationRequest(
      sourceId: 'nied',
      eventId: eventId,
      observedAt: origin.add(const Duration(seconds: 25)),
      stageName: 'confirmed',
      maxShindo: 1,
      stations: records,
      metadata: {
        'nied_input_kind': 'gif',
        'kotoho7_assignment_candidate_mode': 'uncapped',
        'source_trigger_member_ids': records
            .map((record) => record.descriptor.code)
            .toList(),
      },
    );

    final first = estimator.estimate(request('event-a'));
    expect(first, isNotNull);
    final firstCache =
        first!.diagnostics['stateful_source_cache'] as Map<String, Object?>;
    expect(
      firstCache['source_selection_model'],
      'new_source_cache_from_first_station',
    );

    final second = estimator.estimate(request('event-b'));
    expect(second, isNotNull);
    final secondCache =
        second!.diagnostics['stateful_source_cache'] as Map<String, Object?>;
    expect(
      secondCache['source_selection_model'],
      'scratch_detection_id_4_2_existing_source_cache_candidate_v1',
    );
    expect(secondCache['source_selection_selected_key'], 'nied:event-a');
    expect(
      secondCache['source_keys'],
      containsAll(['nied:event-a', 'nied:event-b']),
    );
    final scratch43 = secondCache['scratch_4_3_proxy'] as Map<String, Object?>;
    expect(
      scratch43['model'],
      'dart_kotoho7_detection_id_metadata_proxy_v1_from_ten_plus_3',
    );
    expect(scratch43['assigned_count'], records.length);
    expect(scratch43['max_first_station_distance_km'], isA<double>());
    expect(scratch43['best_score'], isA<double>());
    expect(
      scratch43['merge_metadata_model'],
      'copy_earliest_latest_max_distance_min_score_v1',
    );
  });

  test('NIED Dart HYP estimates directly from worker snapshot input', () {
    final estimator = NiedDartHypSourceEstimator(
      searchSchedule: NiedHypSearchSchedule.scratchViewerFiveStage,
    );
    const epicenter = LatLng(39.95, 142.20);
    const depthKm = 30.0;
    final origin = DateTime(2026, 6, 22, 11, 27);
    final distance = const Distance();
    double algorithmDistanceKm(LatLng from, LatLng to) {
      const earthRadiusKm = 6371.0;
      double radians(double degrees) => degrees * math.pi / 180.0;
      final dLat = radians(to.latitude - from.latitude);
      final dLng = radians(to.longitude - from.longitude);
      final a =
          math.pow(math.sin(dLat / 2), 2) +
          math.cos(radians(from.latitude)) *
              math.cos(radians(to.latitude)) *
              math.pow(math.sin(dLng / 2), 2);
      return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    }

    Map<String, Object?> snapshot(String code) {
      final stationEntry = NiedStationDb.stations.firstWhere(
        (station) => station['code'] == code,
      );
      final lat = (stationEntry['lat'] as num).toDouble();
      final lon = (stationEntry['lng'] as num).toDouble();
      final station = LatLng(lat, lon);
      final surfaceDistanceKm = distance.as(
        LengthUnit.Kilometer,
        epicenter,
        station,
      );
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: true,
      );
      final triggerAt = origin.add(
        Duration(milliseconds: (travelSeconds * 1000).round()),
      );
      return {
        'id': code,
        'code': code,
        'latLng': [lat, lon],
        'triggerStamp': triggerAt.millisecondsSinceEpoch,
        'updateStamp': triggerAt.millisecondsSinceEpoch,
        'ascend': 4,
        'level': 12,
        'isActive': true,
      };
    }

    final activeStations = [
      snapshot('IWT004'),
      snapshot('IWT003'),
      snapshot('IWTH14'),
      snapshot('IWT005'),
      snapshot('IWT002'),
      snapshot('IWTH09'),
    ];
    const farStationCode = 'SYNTHETIC_FAR';
    const farStationPoint = LatLng(40.70, 143.10);
    final farSurfaceDistanceKm = distance.as(
      LengthUnit.Kilometer,
      epicenter,
      farStationPoint,
    );
    final farTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: math.sqrt(
        farSurfaceDistanceKm * farSurfaceDistanceKm + depthKm * depthKm,
      ),
      depthKm: depthKm,
      pWave: true,
    );
    final farTriggerAt = origin.add(
      Duration(milliseconds: (farTravelSeconds * 1000).round()),
    );
    activeStations.add({
      'id': farStationCode,
      'code': farStationCode,
      'latLng': [farStationPoint.latitude, farStationPoint.longitude],
      'triggerStamp': farTriggerAt.millisecondsSinceEpoch,
      'updateStamp': farTriggerAt.millisecondsSinceEpoch,
      'ascend': 4,
      'level': 12,
      'isActive': true,
    });
    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'worker-input-event',
      observedAt: origin.add(const Duration(seconds: 25)),
      stageName: 'confirmed',
      maxShindo: 1,
      stations: const [],
      metadata: {
        'nied_input_kind': 'gif',
        'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
        'nied_hypocenter_new_active_stations': activeStations,
        'nied_hypocenter_active_stations': activeStations,
        'nied_hypocenter_inactive_stations': const [],
        'nied_hypocenter_adj_station_ids': const <String, List<int>>{},
        'kotoho7_scratch_runtime_timer_s': 0.0,
      },
    );

    expect(estimator.supports(request), isTrue);
    final estimate = estimator.estimate(request);
    expect(estimate, isNotNull);
    expect(estimate!.method, 'nied_dart_hyp_v1');
    expect(estimate.supportingStationCount, activeStations.length);
    expect(estimate.diagnostics['input_format'], 'ka_nied_station_snapshot_v1');
    expect(
      estimate.diagnostics['score_model'],
      'scratch_hyp_weighted_variance_station_scale_inactive_plus_s_multiplier',
    );
    expect(estimate.diagnostics['error_level'], isA<double>());
    expect(
      estimate.diagnostics['score'],
      closeTo(
        (estimate.diagnostics['error_level']! as num).toDouble() *
            (estimate.diagnostics['wave_count_penalty_multiplier']! as num)
                .toDouble(),
        1e-9,
      ),
    );
    final expectedSeedStation = activeStations.first;
    final expectedSeedLatLng = expectedSeedStation['latLng']! as List<double>;
    final expectedTriggerAt = DateTime.fromMillisecondsSinceEpoch(
      expectedSeedStation['triggerStamp']! as int,
    );
    final seed =
        estimate.diagnostics['temporary_epicenter_seed']
            as Map<String, Object?>;
    expect(
      request.metadata['nied_dart_hyp_input_station_order_model'],
      'ka_active_station_table_order_matching_scratch_point_index',
    );
    expect(
      request.metadata['nied_dart_hyp_input_station_order'],
      activeStations.map((station) => station['code']).toList(),
    );
    expect(
      estimate.diagnostics['temporary_epicenter_seed_model'],
      'scratch_hyp_first_station_round_to_1_60_degree_origin_minus_2s',
    );
    expect(
      seed['station_code'],
      expectedSeedStation['code'],
      reason: request.metadata['nied_dart_hyp_detection_ids'].toString(),
    );
    expect(
      seed['latitude'],
      closeTo((expectedSeedLatLng[0] * 60).round() / 60.0, 1e-9),
    );
    expect(
      seed['longitude'],
      closeTo((expectedSeedLatLng[1] * 60).round() / 60.0, 1e-9),
    );
    expect(seed['depth_km'], 10.0);
    expect(seed['trigger_at'], expectedTriggerAt.toIso8601String());
    expect(
      estimate.diagnostics['elapsed_since_first_trigger_s'],
      closeTo(
        request.observedAt.difference(expectedTriggerAt).inMilliseconds /
            1000.0,
        1e-9,
      ),
      reason: 'elapsed time must stay anchored to the fixed first station',
    );
    expect(estimate.diagnostics['elapsed_since_detection_id_created_s'], 0.0);
    expect(
      seed['origin_time'],
      expectedTriggerAt.subtract(const Duration(seconds: 2)).toIso8601String(),
    );
    final constraints =
        estimate.diagnostics['candidate_constraints'] as Map<String, Object?>;
    double mercatorLatitudeDegrees(double latitude) {
      final radians = latitude * math.pi / 180.0;
      return math.log(math.tan(math.pi / 4.0 + radians / 2.0)) *
          180.0 /
          math.pi;
    }

    final firstLatitude = expectedSeedLatLng[0];
    final firstLongitude = expectedSeedLatLng[1];
    final expectedMaxDetectedDistanceKm = activeStations
        .map((station) {
          final coordinate = station['latLng']! as List<double>;
          final xDifference = (coordinate[1] - firstLongitude) * 10.0;
          final yDifference =
              (mercatorLatitudeDegrees(coordinate[0]) -
                  mercatorLatitudeDegrees(firstLatitude)) *
              10.0;
          return math.sqrt(
                xDifference * xDifference + yDifference * yDifference,
              ) *
              11.0;
        })
        .reduce(math.max);
    expect(
      constraints['max_detected_distance_km'],
      closeTo(expectedMaxDetectedDistanceKm, 1e-9),
    );
    final estimatedDepthKm = estimate.depthKm!;
    expect(estimatedDepthKm, greaterThanOrEqualTo(10.0));
    expect(estimatedDepthKm, lessThanOrEqualTo(700.0));
    final search = estimate.diagnostics['search'] as Map<String, Object?>;
    final stages = (search['stages'] as List).cast<Map<String, Object?>>();
    expect(stages, hasLength(5));
    expect(
      estimate.diagnostics['map_candidate_model'],
      'published_result_only',
    );
    var previousTotalIterations = 0;
    for (final stage in stages) {
      final iterations = stage['iterations']! as int;
      final totalIterations = stage['total_iterations']! as int;
      expect(totalIterations, previousTotalIterations + iterations);
      previousTotalIterations = totalIterations;
      final moves = (stage['moves'] as List).cast<Map<String, Object?>>();
      final terminalCenter = stage['terminal_center']! as Map<String, Object?>;
      final terminalCandidates = (stage['terminal_candidates'] as List)
          .cast<Map<String, Object?>>();
      final terminationReason = stage['termination_reason'];
      if (terminationReason == 'skipped_station_count') {
        expect(iterations, 0);
        expect(moves, isEmpty);
        expect(terminalCandidates, isEmpty);
        continue;
      }
      expect(iterations, greaterThanOrEqualTo(1));
      expect(
        moves,
        hasLength(
          terminationReason == 'move_limit' ? iterations : iterations - 1,
        ),
      );
      expect(
        terminalCandidates,
        hasLength(stage['depth_step_km'] == null ? 4 : 6),
      );
      expect(
        terminalCandidates.where((candidate) => candidate['evaluated'] == true),
        isNotEmpty,
      );
      final centerScore = (terminalCenter['score']! as num).toDouble();
      for (final candidate in terminalCandidates.where(
        (candidate) => candidate['evaluated'] == true,
      )) {
        expect(
          (candidate['score']! as num).toDouble(),
          greaterThanOrEqualTo(centerScore - 1e-9),
        );
      }
      for (final move in moves) {
        final to = move['to']! as Map<String, Object?>;
        expect((to['depth_km']! as num).toDouble(), greaterThanOrEqualTo(10.0));
        expect((to['depth_km']! as num).toDouble(), lessThanOrEqualTo(700.0));
      }
    }
    final panels = (estimate.diagnostics['travel_time_curve_panels'] as List)
        .cast<Map<String, Object?>>();
    expect(panels, hasLength(1));
    final selectedPanel = panels.singleWhere(
      (panel) => panel['selected'] == true,
    );
    expect(selectedPanel['label'], 'current');
    expect(selectedPanel['latitude'], closeTo(estimate.latitude, 1e-9));
    expect(selectedPanel['longitude'], closeTo(estimate.longitude, 1e-9));
    expect(selectedPanel['depth_km'], closeTo(estimate.depthKm!, 1e-9));
    expect(
      selectedPanel['origin_time'],
      estimate.originTime!.toIso8601String(),
    );
    final expectedTimeReference = activeStations
        .map(
          (station) => DateTime.fromMillisecondsSinceEpoch(
            station['triggerStamp']! as int,
          ),
        )
        .reduce((left, right) => left.isBefore(right) ? left : right);
    expect(
      selectedPanel['time_reference'],
      expectedTimeReference.toIso8601String(),
    );
    expect(
      selectedPanel['time_reference_model'],
      'earliest_effective_scoring_station_trigger',
    );
    expect(
      selectedPanel['distance_axis_model'],
      'epicentral_surface_distance_haversine_6371_km',
    );
    expect(
      selectedPanel['travel_time_model'],
      'jma2001_scratch_polynomial_hypocentral_distance_input',
    );
    for (final key in const [
      'score',
      'error_level',
      'rmse',
      'weight_sum',
      'station_scale',
      'wave_count_penalty_multiplier',
      'p_wave_count',
      's_wave_count',
      'effective_station_count',
    ]) {
      final diagnosticsKey = switch (key) {
        'p_wave_count' || 's_wave_count' => null,
        _ => key,
      };
      if (diagnosticsKey != null) {
        expect(
          selectedPanel[key],
          estimate.diagnostics[diagnosticsKey],
          reason: '$key must come from the same published scoring result',
        );
      }
    }
    final selectedSamples = (selectedPanel['samples'] as List)
        .cast<Map<String, Object?>>();
    final selectedPoint = LatLng(
      (selectedPanel['latitude']! as num).toDouble(),
      (selectedPanel['longitude']! as num).toDouble(),
    );
    final firstStationPoint = LatLng(
      expectedSeedLatLng[0],
      expectedSeedLatLng[1],
    );
    final firstDetectedWeightDistanceKm = math.max(
      50.0,
      algorithmDistanceKm(selectedPoint, firstStationPoint),
    );
    final stationByCode = {
      for (final station in activeStations) station['code'] as String: station,
    };
    final panelOriginOffset = (selectedPanel['origin_offset_s']! as num)
        .toDouble();
    var expectedPCount = 0;
    var expectedSCount = 0;
    for (final sample in selectedSamples) {
      final code = sample['code']! as String;
      final station = stationByCode[code]!;
      final coordinate = station['latLng']! as List<double>;
      final expectedDistanceKm = algorithmDistanceKm(
        selectedPoint,
        LatLng(coordinate[0], coordinate[1]),
      );
      final sampleDistanceKm = (sample['distance_km']! as num).toDouble();
      expect(sampleDistanceKm, closeTo(expectedDistanceKm, 1e-6));
      expect(
        sample['epicentral_distance_km'],
        closeTo(expectedDistanceKm, 1e-6),
      );
      final expectedHypocentralDistanceKm = math.sqrt(
        expectedDistanceKm * expectedDistanceKm +
            estimatedDepthKm * estimatedDepthKm,
      );
      expect(
        sample['hypocentral_distance_km'],
        closeTo(expectedHypocentralDistanceKm, 1e-6),
      );
      final triggerAt = DateTime.fromMillisecondsSinceEpoch(
        station['triggerStamp']! as int,
      );
      final expectedObservedSeconds =
          triggerAt.difference(expectedTimeReference).inMilliseconds / 1000.0;
      expect(sample['observed_s'], closeTo(expectedObservedSeconds, 1e-9));
      final useS = sample['wave'] == 'S';
      if (useS) {
        expectedSCount += 1;
      } else {
        expectedPCount += 1;
      }
      final expectedTravelSeconds =
          Jma2001TravelTimeApproximation.travelTimeSeconds(
            hypocentralDistanceKm: expectedHypocentralDistanceKm,
            depthKm: estimatedDepthKm,
            pWave: !useS,
          );
      expect(
        sample['predicted_s'],
        closeTo(panelOriginOffset + expectedTravelSeconds, 1e-9),
      );
      expect(sample['level'], station['level']);
      expect(sample['ascend'], station['ascend']);
    }
    for (final sample in selectedSamples) {
      final sampleDistanceKm = (sample['distance_km']! as num).toDouble();
      expect(
        sample['weight'],
        closeTo(
          firstDetectedWeightDistanceKm / math.max(50.0, sampleDistanceKm),
          1e-6,
        ),
        reason: 'Scratch floors both distance-weight operands at 50 km',
      );
    }
    final sampleDistances = selectedSamples
        .map((sample) => (sample['distance_km']! as num).toDouble())
        .toList(growable: false);
    final observedSeconds = selectedSamples
        .map((sample) => (sample['observed_s']! as num).toDouble())
        .toList(growable: false);
    final distanceMaxKm = sampleDistances.reduce(math.max);
    expect(selectedPanel['distance_max_km'], closeTo(distanceMaxKm, 1e-9));
    expect(
      selectedPanel['observed_min_s'],
      closeTo(observedSeconds.reduce(math.min), 1e-9),
    );
    expect(
      selectedPanel['observed_max_s'],
      closeTo(observedSeconds.reduce(math.max), 1e-9),
    );
    final pCurve = (selectedPanel['p_curve'] as List)
        .cast<Map<String, Object?>>();
    final sCurve = (selectedPanel['s_curve'] as List)
        .cast<Map<String, Object?>>();
    expect(pCurve, hasLength(33));
    expect(sCurve, hasLength(33));
    expect(
      pCurve.last['distance_km'],
      closeTo(distanceMaxKm, 1e-9),
      reason: 'JMA2001 curve must stop at the farthest real active station',
    );
    for (var index = 0; index < pCurve.length; index++) {
      final expectedDistanceKm = distanceMaxKm * index / 32.0;
      final hypocentralDistanceKm = math.sqrt(
        expectedDistanceKm * expectedDistanceKm +
            estimatedDepthKm * estimatedDepthKm,
      );
      expect(pCurve[index]['distance_km'], closeTo(expectedDistanceKm, 1e-9));
      expect(
        pCurve[index]['arrival_s'],
        closeTo(
          panelOriginOffset +
              Jma2001TravelTimeApproximation.travelTimeSeconds(
                hypocentralDistanceKm: hypocentralDistanceKm,
                depthKm: estimatedDepthKm,
                pWave: true,
              ),
          1e-9,
        ),
      );
      expect(sCurve[index]['distance_km'], closeTo(expectedDistanceKm, 1e-9));
      expect(
        sCurve[index]['arrival_s'],
        closeTo(
          panelOriginOffset +
              Jma2001TravelTimeApproximation.travelTimeSeconds(
                hypocentralDistanceKm: hypocentralDistanceKm,
                depthKm: estimatedDepthKm,
                pWave: false,
              ),
          1e-9,
        ),
      );
    }

    var weightedResidualSquares = 0.0;
    var weightSum = 0.0;
    for (final sample in selectedSamples) {
      final observed = (sample['observed_s']! as num).toDouble();
      final predicted = (sample['predicted_s']! as num).toDouble();
      final residual = (sample['residual_s']! as num).toDouble();
      final weight = (sample['weight']! as num).toDouble();
      expect(residual, closeTo(observed - predicted, 1e-9));
      weightedResidualSquares += residual * residual * weight;
      weightSum += weight;
    }
    expect(
      selectedPanel['active_timing_rmse'],
      closeTo(math.sqrt(weightedResidualSquares / weightSum), 1e-9),
      reason: 'point-fit RMSE must not include inactive-station penalty',
    );
    final inactivePenalty = (selectedPanel['inactive_penalty']! as num)
        .toDouble();
    final stationScale = (selectedPanel['station_scale']! as num).toDouble();
    final waveMultiplier =
        (selectedPanel['wave_count_penalty_multiplier']! as num).toDouble();
    final expectedStationScale =
        30.0 +
        20000.0 / (1.0 + selectedSamples.length * selectedSamples.length) +
        2000.0 / (50.0 + selectedSamples.length);
    final expectedWaveMultiplier = math.max(
      0.25,
      1.0 - expectedSCount * 3.0 / selectedSamples.length,
    );
    final expectedErrorLevel =
        (weightedResidualSquares + inactivePenalty) /
        weightSum *
        expectedStationScale;
    expect(selectedPanel['weight_sum'], closeTo(weightSum, 1e-9));
    expect(stationScale, closeTo(expectedStationScale, 1e-9));
    expect(waveMultiplier, closeTo(expectedWaveMultiplier, 1e-9));
    expect(selectedPanel['p_wave_count'], expectedPCount);
    expect(selectedPanel['s_wave_count'], expectedSCount);
    expect(selectedPanel['effective_station_count'], selectedSamples.length);
    expect(selectedPanel['error_level'], closeTo(expectedErrorLevel, 1e-9));
    expect(
      selectedPanel['rmse'],
      closeTo(
        math.sqrt((weightedResidualSquares + inactivePenalty) / weightSum),
        1e-9,
      ),
    );
    expect(
      selectedPanel['score'],
      closeTo(expectedErrorLevel * expectedWaveMultiplier, 1e-9),
    );
    expect(
      panels.map((panel) => (panel['depth_km']! as num).toDouble()),
      everyElement(allOf(greaterThanOrEqualTo(10.0), lessThanOrEqualTo(700.0))),
    );
    expect(panels.map((panel) => panel['label']), ['current']);
  });

  test('NIED Dart HYP never falls back when KA has fewer than five times', () {
    final estimator = NiedDartHypSourceEstimator();
    final observedAt = DateTime(2026, 6, 22, 11, 27, 10);
    final activeStations = List.generate(4, (index) {
      return <String, Object?>{
        'id': 'KA$index',
        'code': 'KA$index',
        'latLng': [35.0 + index * 0.01, 140.0 + index * 0.01],
        'triggerStamp': observedAt
            .subtract(Duration(seconds: 4 - index))
            .millisecondsSinceEpoch,
        'updateStamp': observedAt.millisecondsSinceEpoch,
        'ascend': 4,
        'level': 12,
        'isActive': true,
      };
    });
    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'below-ka-minimum',
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 1,
      stations: const [],
      metadata: {
        'nied_hypocenter_active_stations': activeStations,
        'nied_hypocenter_inactive_stations': const [],
      },
    );

    expect(estimator.supports(request), isFalse);
    expect(estimator.estimate(request), isNull);
  });

  test(
    'NIED Dart HYP freezes the published curve when a later search is rejected',
    () {
      final estimator = NiedDartHypSourceEstimator(
        searchSchedule: NiedHypSearchSchedule.scratchViewerFiveStage,
      );
      const source = LatLng(35.5, 139.7);
      const sourceDepthKm = 20.0;
      final origin = DateTime(2026, 7, 18, 4);
      final distance = const Distance();

      final active = <Map<String, Object?>>[];
      for (var index = 0; index < 8; index++) {
        final station = LatLng(
          source.latitude + (index.isEven ? 1 : -1) * (0.08 + index * 0.01),
          source.longitude + (index % 3 - 1) * 0.09,
        );
        final surfaceDistanceKm = distance.as(
          LengthUnit.Kilometer,
          source,
          station,
        );
        final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
          hypocentralDistanceKm: math.sqrt(
            surfaceDistanceKm * surfaceDistanceKm +
                sourceDepthKm * sourceDepthKm,
          ),
          depthKm: sourceDepthKm,
          pWave: true,
        );
        final triggerAt = origin.add(
          Duration(milliseconds: (travelSeconds * 1000).round()),
        );
        active.add({
          'id': 'FIT$index',
          'code': 'FIT$index',
          'latLng': [station.latitude, station.longitude],
          'triggerStamp': triggerAt.millisecondsSinceEpoch,
          'updateStamp': triggerAt.millisecondsSinceEpoch,
          'ascend': 4,
          'level': 10,
          'isActive': true,
        });
      }

      SourceEstimationRequest request(
        DateTime observedAt, {
        List<Map<String, Object?>> inactive = const [],
      }) {
        return SourceEstimationRequest(
          sourceId: 'nied',
          eventId: 'published-curve-freeze',
          observedAt: observedAt,
          stageName: 'confirmed',
          maxShindo: 2,
          stations: const [],
          metadata: {
            'nied_hypocenter_active_stations': active,
            'nied_hypocenter_inactive_stations': inactive,
            'nied_hypocenter_inactive_scope':
                'ka_level_present_all_network_scratch_dynamic_radius',
          },
        );
      }

      final first = estimator.estimate(
        request(
          DateTime.fromMillisecondsSinceEpoch(
            active.first['triggerStamp']! as int,
          ),
        ),
      );
      expect(first, isNotNull);
      final firstPanels =
          first!.diagnostics['travel_time_curve_panels']
              as List<Map<String, Object?>>;
      expect(firstPanels, hasLength(1));
      expect(first.diagnostics['travel_time_curve_frozen'], isFalse);
      expect(first.diagnostics['travel_time_curve_revision'], 1);

      final inactive = [
        for (var index = 0; index < 600; index++)
          <String, Object?>{
            'id': 'INACTIVE$index',
            'code': 'INACTIVE$index',
            'latLng': [
              source.latitude + (index % 10 - 5) * 0.001,
              source.longitude + (index % 12 - 6) * 0.001,
            ],
            'updateStamp': origin
                .add(const Duration(seconds: 41))
                .millisecondsSinceEpoch,
            'ascend': 0,
            'level': 0,
            'isActive': false,
          },
      ];
      final second = estimator.estimate(
        request(
          DateTime.fromMillisecondsSinceEpoch(
            (active.first['triggerStamp']! as int) +
                const Duration(seconds: 10).inMilliseconds,
          ),
          inactive: inactive,
        ),
      );
      expect(second, isNotNull);
      expect(second!.diagnostics['search_result_accepted'], isFalse);
      expect(second.diagnostics['travel_time_curve_frozen'], isTrue);
      expect(
        second.diagnostics['travel_time_curve_revision'],
        first.diagnostics['travel_time_curve_revision'],
      );
      expect(second.latitude, first.latitude);
      expect(second.longitude, first.longitude);
      expect(second.depthKm, first.depthKm);
      expect(second.originTime, first.originTime);
      expect(second.diagnostics['score'], first.diagnostics['score']);

      final secondPanels =
          second.diagnostics['travel_time_curve_panels']
              as List<Map<String, Object?>>;
      expect(identical(secondPanels, firstPanels), isTrue);
      final firstSamples = firstPanels.single['samples'] as List;
      final secondSamples = secondPanels.single['samples'] as List;
      expect(identical(secondSamples, firstSamples), isTrue);
      expect(
        secondSamples.map((sample) => (sample as Map)['code']),
        everyElement(startsWith('FIT')),
      );
      expect(
        secondPanels.single['origin_time'],
        second.originTime!.toIso8601String(),
      );
    },
  );

  test('NIED Dart HYP applies the article inactive-station time gate', () {
    const source = LatLng(35.5, 139.7);
    final firstTrigger = DateTime(2026, 7, 18, 4, 0, 10);

    List<Map<String, Object?>> activeStations(int count) {
      return [
        for (var index = 0; index < count; index++)
          <String, Object?>{
            'id': 'ACTIVE$index',
            'code': 'ACTIVE$index',
            'latLng': [
              source.latitude + (index % 6 - 3) * 0.01,
              source.longitude + (index % 5 - 2) * 0.01,
            ],
            'triggerStamp': firstTrigger.millisecondsSinceEpoch,
            'updateStamp': firstTrigger.millisecondsSinceEpoch,
            'ascend': 4,
            'level': 10,
            'isActive': true,
          },
      ];
    }

    final inactive = [
      for (var index = 0; index < 80; index++)
        <String, Object?>{
          'id': 'INACTIVE$index',
          'code': 'INACTIVE$index',
          'latLng': [
            source.latitude + (index % 8 - 4) * 0.002,
            source.longitude + (index % 10 - 5) * 0.002,
          ],
          'updateStamp': firstTrigger.millisecondsSinceEpoch,
          'ascend': 0,
          'level': 0,
          'isActive': false,
        },
    ];

    SourceEstimate estimateAt({
      required String eventId,
      required int activeCount,
      required Duration elapsed,
    }) {
      final estimator = NiedDartHypSourceEstimator(
        searchSchedule: NiedHypSearchSchedule.scratchViewerFiveStage,
      );
      SourceEstimationRequest request(DateTime observedAt) {
        return SourceEstimationRequest(
          sourceId: 'nied',
          eventId: eventId,
          observedAt: observedAt,
          stageName: 'confirmed',
          maxShindo: 2,
          stations: const [],
          metadata: {
            'nied_hypocenter_active_stations': activeStations(activeCount),
            'nied_hypocenter_inactive_stations': inactive,
            'nied_hypocenter_inactive_scope':
                'ka_level_present_all_network_scratch_dynamic_radius',
          },
        );
      }

      expect(estimator.estimate(request(firstTrigger)), isNotNull);
      return estimator.estimate(request(firstTrigger.add(elapsed)))!;
    }

    final early = estimateAt(
      eventId: 'article-inactive-gate-early',
      activeCount: 5,
      elapsed: const Duration(seconds: 3),
    );
    final lowCount = estimateAt(
      eventId: 'article-inactive-gate-low-count',
      activeCount: 5,
      elapsed: const Duration(seconds: 10),
    );
    final late = estimateAt(
      eventId: 'article-inactive-gate-late',
      activeCount: 5,
      elapsed: const Duration(seconds: 11),
    );
    final highCount = estimateAt(
      eventId: 'article-inactive-gate-high-count',
      activeCount: 30,
      elapsed: const Duration(seconds: 5),
    );

    for (final estimate in [early, lowCount]) {
      expect(estimate.diagnostics['inactive_penalty_gate_open'], isTrue);
    }
    for (final estimate in [late, highCount]) {
      expect(estimate.diagnostics['inactive_penalty_gate_open'], isFalse);
      expect(estimate.diagnostics['inactive_penalty'], 0.0);
      expect(estimate.diagnostics['inactive_p_radius_km'], 0.0);
      expect(estimate.diagnostics['inactive_reference_distance_km'], 0.0);
    }
    expect(
      late.diagnostics['inactive_penalty_gate_model'],
      'kotoho7_article_elapsed_le_3_or_elapsed_le_10_and_active_lt_30',
    );
  });

  test('NIED Dart HYP keeps KA event history and uses its cached S phase', () {
    final estimator = NiedDartHypSourceEstimator();
    const epicenter = LatLng(39.95, 142.20);
    const depthKm = 30.0;
    final origin = DateTime(2026, 6, 22, 11, 27);
    final distance = const Distance();

    Map<String, Object?> stationSnapshot(
      String code, {
      required bool pWave,
      SourceEstimate? reference,
    }) {
      final stationEntry = NiedStationDb.stations.firstWhere(
        (station) => station['code'] == code,
      );
      final lat = (stationEntry['lat'] as num).toDouble();
      final lon = (stationEntry['lng'] as num).toDouble();
      final source = reference == null
          ? epicenter
          : LatLng(reference.latitude, reference.longitude);
      final sourceDepthKm = reference?.depthKm ?? depthKm;
      final sourceOrigin = reference?.originTime ?? origin;
      final surfaceDistanceKm = distance.as(
        LengthUnit.Kilometer,
        source,
        LatLng(lat, lon),
      );
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + sourceDepthKm * sourceDepthKm,
      );
      final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: sourceDepthKm,
        pWave: pWave,
      );
      final triggerAt = sourceOrigin.add(
        Duration(milliseconds: (travelSeconds * 1000).round()),
      );
      return {
        'id': code,
        'code': code,
        'latLng': [lat, lon],
        'triggerStamp': triggerAt.millisecondsSinceEpoch,
        'updateStamp': triggerAt.millisecondsSinceEpoch,
        'ascend': 4,
        'level': 12,
        'isActive': true,
      };
    }

    SourceEstimationRequest request(
      DateTime observedAt,
      List<Map<String, Object?>> active,
    ) {
      return SourceEstimationRequest(
        sourceId: 'nied',
        eventId: 'stateful-worker-input-event',
        observedAt: observedAt,
        stageName: 'confirmed',
        maxShindo: 1,
        stations: const [],
        metadata: {
          'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
          'nied_hypocenter_active_stations': active,
          'nied_hypocenter_inactive_stations': const [],
        },
      );
    }

    final firstActive = [
      for (final code in const [
        'IWT004',
        'IWT003',
        'IWTH14',
        'IWT005',
        'IWT002',
        'IWTH09',
        'IWT001',
        'IWT006',
        'IWT007',
        'IWT008',
      ])
        stationSnapshot(code, pWave: true),
    ];
    final firstRequest = request(
      origin.add(const Duration(seconds: 12)),
      firstActive,
    );
    final firstEstimate = estimator.estimate(firstRequest);
    expect(firstEstimate, isNotNull);

    final emptyFrameRequest = request(
      origin.add(const Duration(seconds: 18)),
      const [],
    );
    expect(estimator.supports(emptyFrameRequest), isTrue);
    final continuedEstimate = estimator.estimate(emptyFrameRequest);
    expect(continuedEstimate, isNotNull);
    expect(continuedEstimate!.supportingStationCount, firstActive.length);
    expect(
      continuedEstimate.diagnostics['historical_active_count'],
      firstActive.length,
    );

    final lateFrameRequest = request(
      origin.add(const Duration(seconds: 30)),
      const [],
    );
    final lateEstimate = estimator.estimate(lateFrameRequest);
    expect(lateEstimate, isNotNull);
    expect(lateFrameRequest.metadata['nied_dart_hyp_worker_reused'], isFalse);
    final repeatedLateFrameRequest = request(
      origin.add(const Duration(seconds: 31)),
      const [],
    );
    final repeatedLateEstimate = estimator.estimate(repeatedLateFrameRequest);
    expect(repeatedLateEstimate, isNotNull);
    expect(repeatedLateEstimate, isNot(same(lateEstimate)));
    expect(
      repeatedLateFrameRequest.metadata['nied_dart_hyp_worker_reused'],
      isFalse,
    );
    expect(
      repeatedLateEstimate!.diagnostics['elapsed_since_first_trigger_s'],
      greaterThan(
        lateEstimate!.diagnostics['elapsed_since_first_trigger_s']! as num,
      ),
    );
    expect(repeatedLateEstimate.diagnostics['search_cycle_ran'], isTrue);

    final tooEarlyStation = stationSnapshot(
      'AOMH03',
      pWave: true,
      reference: lateEstimate,
    );
    tooEarlyStation['triggerStamp'] =
        (tooEarlyStation['triggerStamp']! as int) - 20000;
    final rejectedFrameRequest = request(
      origin.add(const Duration(seconds: 32)),
      [tooEarlyStation],
    );
    final rejectedEstimate = estimator.estimate(rejectedFrameRequest);
    expect(rejectedEstimate, isNotNull);
    final splitAssignments =
        rejectedFrameRequest.metadata['nied_dart_hyp_assignment_accepted']
            as Map<String, String>;
    expect(splitAssignments['AOMH03'], 'scratch_id3_new_detection_id');
    expect(
      rejectedFrameRequest.metadata['nied_dart_hyp_station_detection_ids'],
      containsPair('AOMH03', 2),
    );

    final sStation = stationSnapshot(
      'IWTH04',
      pWave: false,
      reference: lateEstimate,
    );
    final sFrameRequest = request(origin.add(const Duration(seconds: 35)), [
      sStation,
    ]);
    final sEstimate = estimator.estimate(sFrameRequest);
    expect(sEstimate, isNotNull);
    final waveCounts =
        sEstimate!.diagnostics['wave_counts'] as Map<String, Object?>;
    expect((waveCounts['S']! as num).toInt(), greaterThanOrEqualTo(1));
    expect(
      sEstimate.diagnostics['phase_cache_reference_model'],
      'scratch_4_4_quantized_assignment_only_lat_lng_1_60_depth_origin_integer',
    );
    expect(
      sEstimate.diagnostics['station_assignment_model'],
      'scratch_4_2_previous_source_p_window_then_s_range',
    );
    final acceptedAssignments =
        sFrameRequest.metadata['nied_dart_hyp_assignment_accepted']
            as Map<String, String>;
    expect(acceptedAssignments['IWTH04'], 'scratch_4_2_accept_s_range');

    final panels = (sEstimate.diagnostics['travel_time_curve_panels'] as List)
        .cast<Map<String, Object?>>();
    final selectedPanel = panels.singleWhere(
      (panel) => panel['selected'] == true,
    );
    final samples = (selectedPanel['samples'] as List)
        .cast<Map<String, Object?>>();
    final sSample = samples.singleWhere((sample) => sample['code'] == 'IWTH04');
    expect(sSample['wave'], 'S');
    final sampleDistanceKm = (sSample['distance_km']! as num).toDouble();
    final selectedDepthKm = (selectedPanel['depth_km']! as num).toDouble();
    final selectedOriginOffset = (selectedPanel['origin_offset_s']! as num)
        .toDouble();
    final expectedSTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: math.sqrt(
        sampleDistanceKm * sampleDistanceKm + selectedDepthKm * selectedDepthKm,
      ),
      depthKm: selectedDepthKm,
      pWave: false,
    );
    expect(
      (sSample['predicted_s']! as num).toDouble(),
      closeTo(selectedOriginOffset + expectedSTravel, 1e-9),
    );

    final expiredRequest = request(
      origin.add(const Duration(seconds: 41)),
      const [],
    );
    expect(estimator.supports(expiredRequest), isTrue);
    expect(estimator.estimate(expiredRequest), isNull);
    expect(
      expiredRequest.metadata['nied_dart_hyp_clear_published_source'],
      isTrue,
    );
    expect(
      expiredRequest.metadata['nied_dart_hyp_source_clear_reason'],
      anyOf(
        'scratch_no_active_detection_id',
        'scratch_grid_carrier_id_set_empty',
      ),
    );
  });

  test(
    'NIED Dart HYP keeps incompatible KA station groups in separate IDs',
    () {
      final estimator = NiedDartHypSourceEstimator();
      final base = DateTime(2026, 7, 17, 12);

      Map<String, Object?> snapshot(
        String code,
        double latitude,
        double longitude,
        DateTime triggerAt,
      ) => <String, Object?>{
        'id': code,
        'code': code,
        'latLng': [latitude, longitude],
        'triggerStamp': triggerAt.millisecondsSinceEpoch,
        'updateStamp': triggerAt.millisecondsSinceEpoch,
        'ascend': 4,
        'level': 12,
        'isActive': true,
      };

      SourceEstimationRequest request(
        DateTime observedAt,
        List<Map<String, Object?>> active,
      ) => SourceEstimationRequest(
        sourceId: 'nied',
        eventId: 'two-ka-detection-ids',
        observedAt: observedAt,
        stageName: 'confirmed',
        maxShindo: 2,
        stations: const [],
        metadata: {
          'nied_hypocenter_active_stations': active,
          'nied_hypocenter_inactive_stations': const [],
          'nied_detection_adj_station_codes': const <String, List<String>>{},
          'nied_hypocenter_detection_grid': const {
            'decimal': <double>[0.0, 0.0],
          },
        },
      );

      final firstGroup = <Map<String, Object?>>[
        for (var index = 0; index < 5; index++)
          snapshot(
            'OLD$index',
            35.0 + index * 0.02,
            140.0 + index * 0.02,
            base.add(Duration(milliseconds: 300 * index)),
          ),
      ];
      final firstRequest = request(
        base.add(const Duration(seconds: 5)),
        firstGroup,
      );
      final firstEstimate = estimator.estimate(firstRequest);
      expect(firstEstimate, isNotNull);
      expect(firstEstimate!.diagnostics['selected_detection_id'], 1);

      final secondOrigin = base.add(const Duration(seconds: 50));
      final secondGroup = <Map<String, Object?>>[
        for (var index = 0; index < 5; index++)
          snapshot(
            'NEW$index',
            40.0 + index * 0.02,
            145.0 + index * 0.02,
            secondOrigin.add(Duration(milliseconds: 300 * index)),
          ),
      ];
      final secondRequest = request(
        secondOrigin.add(const Duration(seconds: 5)),
        secondGroup,
      );
      final secondEstimate = estimator.estimate(secondRequest);
      expect(secondEstimate, isNotNull);
      expect(secondEstimate!.diagnostics['selected_detection_id'], 2);
      final stationIds =
          secondRequest.metadata['nied_dart_hyp_station_detection_ids']
              as Map<String, int>;
      expect(
        {
          for (final code in firstGroup.map((item) => item['code']))
            stationIds[code],
        },
        {1},
      );
      expect(
        {
          for (final code in secondGroup.map((item) => item['code']))
            stationIds[code],
        },
        {2},
      );
      final ids = (secondEstimate.diagnostics['detection_ids'] as List)
          .cast<Map<String, Object?>>();
      expect(ids.map((item) => item['id']), containsAll(<int>[1, 2]));
      expect(
        ids.singleWhere((item) => item['id'] == 2)['assigned_station_count'],
        5,
      );

      final thirdRowRequest = request(
        secondOrigin.add(const Duration(seconds: 30)),
        [
          snapshot(
            'THIRD',
            30.0,
            130.0,
            secondOrigin.add(const Duration(seconds: 30)),
          ),
        ],
      );
      estimator.estimate(thirdRowRequest);
      expect(
        thirdRowRequest.metadata['nied_dart_hyp_assignment_rejected'],
        containsPair('THIRD', 'scratch_id3_reject_no_candidate_max_two_ids'),
      );
      expect(
        (thirdRowRequest.metadata['nied_dart_hyp_detection_ids'] as List)
            .length,
        2,
      );
    },
  );

  test('NIED Dart HYP KA grid carriers use real frame ages', () {
    final estimator = NiedDartHypSourceEstimator();
    final base = DateTime(2026, 7, 17, 13);

    Map<String, Object?> snapshot(
      String code,
      double latitude,
      double longitude,
      Duration offset,
    ) => <String, Object?>{
      'id': code,
      'code': code,
      'latLng': [latitude, longitude],
      'triggerStamp': base.add(offset).millisecondsSinceEpoch,
      'updateStamp': base.add(offset).millisecondsSinceEpoch,
      'ascend': 4,
      'level': 12,
      'isActive': true,
    };

    SourceEstimationRequest request(
      Duration frameOffset,
      List<Map<String, Object?>> active,
    ) => SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'ka-grid-carrier-times',
      observedAt: base.add(frameOffset),
      stageName: 'confirmed',
      maxShindo: 1,
      stations: const [],
      metadata: {
        'nied_hypocenter_active_stations': active,
        'nied_hypocenter_inactive_stations': const [],
        'nied_detection_adj_station_codes': <String, List<String>>{
          for (final station in active) station['code']! as String: const [],
        },
        'nied_hypocenter_detection_grid': const {
          'decimal': <double>[0.2, 0.2],
        },
      },
    );

    estimator.estimate(
      request(const Duration(seconds: 1), [
        snapshot('A0', 35.20, 140.20, Duration.zero),
        snapshot('A1', 35.22, 140.22, const Duration(milliseconds: 200)),
      ]),
    );
    final newIdRequest = request(const Duration(seconds: 9), [
      snapshot('B0', 40.20, 145.20, const Duration(seconds: 9)),
      snapshot('B0A', 40.22, 145.22, const Duration(milliseconds: 9100)),
    ]);
    estimator.estimate(newIdRequest);
    expect(
      newIdRequest.metadata['nied_dart_hyp_assignment_accepted'],
      containsPair('B0', 'scratch_id3_new_detection_id'),
    );
    expect(
      newIdRequest.metadata['nied_dart_hyp_station_detection_ids'],
      containsPair('B0A', 2),
    );

    final currentGridRequest = request(const Duration(milliseconds: 9500), [
      snapshot('B1', 40.25, 145.25, const Duration(milliseconds: 9200)),
    ]);
    estimator.estimate(currentGridRequest);
    expect(
      currentGridRequest.metadata['nied_dart_hyp_assignment_accepted'],
      containsPair('B1', 'scratch_grid_current'),
    );

    final aroundGridRequest = request(const Duration(seconds: 13), [
      snapshot('B2', 41.20, 145.20, const Duration(milliseconds: 12500)),
    ]);
    estimator.estimate(aroundGridRequest);
    expect(
      aroundGridRequest.metadata['nied_dart_hyp_assignment_accepted'],
      containsPair('B2', 'scratch_grid_around_9'),
    );
    expect(
      aroundGridRequest.metadata['nied_dart_hyp_station_detection_ids'],
      containsPair('B2', 2),
    );
  });

  test(
    'NIED Dart HYP registers only KA new-active stations after bootstrap',
    () {
      final estimator = NiedDartHypSourceEstimator();
      final base = DateTime(2026, 7, 18, 12);

      Map<String, Object?> snapshot(String code, int index) =>
          <String, Object?>{
            'id': code,
            'code': code,
            'latLng': [35.0 + index * 0.01, 140.0 + index * 0.01],
            'triggerStamp': base
                .add(Duration(milliseconds: index * 200))
                .millisecondsSinceEpoch,
            'updateStamp': base
                .add(const Duration(seconds: 5))
                .millisecondsSinceEpoch,
            'ascend': 4,
            'level': 12,
            'isActive': true,
          };

      SourceEstimationRequest request({
        required DateTime observedAt,
        required List<Map<String, Object?>> active,
        required List<Map<String, Object?>> newlyActive,
      }) => SourceEstimationRequest(
        sourceId: 'nied',
        eventId: 'ka-new-active-registration',
        observedAt: observedAt,
        stageName: 'confirmed',
        maxShindo: 2,
        stations: const [],
        metadata: {
          'nied_hypocenter_new_active_stations': newlyActive,
          'nied_hypocenter_active_stations': active,
          'nied_hypocenter_inactive_stations': const [],
          'nied_detection_adj_station_codes': const <String, List<String>>{},
          'nied_hypocenter_detection_grid': const {
            'decimal': <double>[0.0, 0.0],
          },
        },
      );

      final initial = <Map<String, Object?>>[
        for (var index = 0; index < 5; index++)
          snapshot('INITIAL$index', index),
      ];
      final firstRequest = request(
        observedAt: base.add(const Duration(seconds: 5)),
        active: initial,
        newlyActive: initial,
      );
      expect(estimator.estimate(firstRequest), isNotNull);

      final late = snapshot('LATE', 5);
      final allActive = <Map<String, Object?>>[...initial, late];
      final updateOnlyRequest = request(
        observedAt: base.add(const Duration(seconds: 6)),
        active: allActive,
        newlyActive: const [],
      );
      final updateOnlyEstimate = estimator.estimate(updateOnlyRequest);
      expect(updateOnlyEstimate, isNotNull);
      expect(
        updateOnlyRequest.metadata['nied_dart_hyp_station_detection_ids'],
        isNot(contains('LATE')),
      );
      expect(updateOnlyEstimate!.supportingStationCount, initial.length);

      final registrationRequest = request(
        observedAt: base.add(const Duration(seconds: 7)),
        active: allActive,
        newlyActive: [late],
      );
      final registeredEstimate = estimator.estimate(registrationRequest);
      expect(registeredEstimate, isNotNull);
      expect(
        registrationRequest.metadata['nied_dart_hyp_station_detection_ids'],
        containsPair('LATE', 1),
      );
      expect(registeredEstimate!.supportingStationCount, allActive.length);
    },
  );

  test('reference NIED HYP resets its cluster after an empty active frame', () {
    final estimator = NiedDartHypSourceEstimator(
      searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
    );
    final base = DateTime(2026, 7, 18, 12);

    Map<String, Object?> snapshot(String code, int index) => <String, Object?>{
      'id': code,
      'code': code,
      'latLng': [35.0 + index * 0.01, 140.0 + index * 0.01],
      'triggerStamp': base
          .add(Duration(milliseconds: index * 200))
          .millisecondsSinceEpoch,
      'updateStamp': base
          .add(const Duration(seconds: 5))
          .millisecondsSinceEpoch,
      'ascend': 4,
      'level': 12,
      'isActive': true,
    };

    SourceEstimationRequest request({
      required DateTime observedAt,
      required List<Map<String, Object?>> active,
    }) => SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'reference-empty-active-reset',
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 2,
      stations: const [],
      metadata: {
        'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
        'nied_hypocenter_new_active_stations': active,
        'nied_hypocenter_active_stations': active,
        'nied_hypocenter_inactive_stations': const [],
        'nied_hypocenter_adj_station_ids': const <String, List<int>>{},
      },
    );

    final initial = <Map<String, Object?>>[
      for (var index = 0; index < 5; index++) snapshot('INITIAL$index', index),
    ];
    final initialRequest = request(
      observedAt: base.add(const Duration(seconds: 5)),
      active: initial,
    );
    expect(estimator.supports(initialRequest), isTrue);
    estimator.estimate(initialRequest);

    final emptyRequest = request(
      observedAt: base.add(const Duration(seconds: 6)),
      active: const [],
    );
    expect(estimator.supports(emptyRequest), isTrue);
    expect(estimator.estimate(emptyRequest), isNull);
    expect(
      emptyRequest.metadata['nied_dart_hyp_source_clear_reason'],
      'kanameishi_reference_active_station_set_empty',
    );

    final laterSegment = <Map<String, Object?>>[
      for (var index = 0; index < 4; index++) snapshot('LATER$index', index),
    ];
    final laterRequest = request(
      observedAt: base.add(const Duration(seconds: 7)),
      active: laterSegment,
    );
    expect(estimator.supports(laterRequest), isFalse);
  });

  test('reference NIED HYP does not publish a zero-support candidate', () {
    final estimator = NiedDartHypSourceEstimator(
      searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
    );
    final base = DateTime(2026, 8, 4, 12);
    final active = <Map<String, Object?>>[
      for (var index = 0; index < 5; index++)
        {
          'id': 'ZERO$index',
          'code': 'ZERO$index',
          'latLng': [35.0 + index * 0.01, 140.0 + index * 0.01],
          'triggerStamp': base
              .add(Duration(milliseconds: index * 200))
              .millisecondsSinceEpoch,
          'updateStamp': base
              .add(const Duration(seconds: 5))
              .millisecondsSinceEpoch,
          // This can form a KA active cluster but has no positive scoring
          // contribution, which the reference scorer marks with 1e12.
          'ascend': 1,
          'level': 1,
          'isActive': true,
        },
    ];
    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'reference-zero-support',
      observedAt: base.add(const Duration(seconds: 5)),
      stageName: 'confirmed',
      maxShindo: 0,
      stations: const [],
      metadata: {
        'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
        'nied_hypocenter_new_active_stations': active,
        'nied_hypocenter_active_stations': active,
        'nied_hypocenter_inactive_stations': const [],
        'nied_hypocenter_adj_station_ids': const <String, List<int>>{},
      },
    );

    expect(estimator.supports(request), isTrue);
    expect(estimator.estimate(request), isNull);
    expect(
      request.metadata['nied_dart_hyp_source_clear_reason'],
      'scratch_active_detection_id_has_no_published_source',
    );
  });

  test(
    'reference NIED HYP merges an adjacent and residual-matched cluster',
    () {
      final estimator = NiedDartHypSourceEstimator(
        searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
      );
      final base = DateTime(2026, 8, 4, 12);

      Map<String, Object?> snapshot({
        required String code,
        required double latitude,
        required double longitude,
        required Duration triggerOffset,
      }) => <String, Object?>{
        'id': code,
        'code': code,
        'latLng': [latitude, longitude],
        'triggerStamp': base.add(triggerOffset).millisecondsSinceEpoch,
        'updateStamp': base
            .add(const Duration(seconds: 6))
            .millisecondsSinceEpoch,
        'ascend': 4,
        'level': 12,
        'isActive': true,
      };

      SourceEstimationRequest request({
        required DateTime observedAt,
        required List<Map<String, Object?>> active,
        required List<Map<String, Object?>> newlyActive,
        required Map<String, List<String>> adjacency,
      }) => SourceEstimationRequest(
        sourceId: 'nied',
        eventId: 'reference-adjacent-residual-bridge',
        observedAt: observedAt,
        stageName: 'confirmed',
        maxShindo: 2,
        stations: const [],
        metadata: {
          'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
          'nied_hypocenter_new_active_stations': newlyActive,
          'nied_hypocenter_active_stations': active,
          'nied_hypocenter_inactive_stations': const [],
          'nied_hypocenter_adj_station_ids': adjacency,
        },
      );

      final clusterA = <Map<String, Object?>>[
        for (var index = 0; index < 5; index++)
          snapshot(
            code: 'A$index',
            latitude: 35.0 + index * 0.01,
            longitude: 140.0 + index * 0.01,
            triggerOffset: Duration(milliseconds: index * 200),
          ),
      ];
      final clusterB = <Map<String, Object?>>[
        for (var index = 0; index < 5; index++)
          snapshot(
            code: 'B$index',
            latitude: 38.0 + index * 0.01,
            longitude: 143.0 + index * 0.01,
            triggerOffset: Duration(milliseconds: index * 200),
          ),
      ];
      final initialAdjacency = <String, List<String>>{
        for (final group in [clusterA, clusterB])
          for (final station in group)
            station['id']! as String: [
              for (final neighbor in group)
                if (neighbor['id'] != station['id']) neighbor['id']! as String,
            ],
      };
      final initial = request(
        observedAt: base.add(const Duration(seconds: 5)),
        active: [...clusterA, ...clusterB],
        newlyActive: [...clusterA, ...clusterB],
        adjacency: initialAdjacency,
      );
      expect(estimator.estimate(initial), isNotNull);

      final bridge = snapshot(
        code: 'BRIDGE',
        latitude: 35.02,
        longitude: 140.02,
        triggerOffset: const Duration(milliseconds: 400),
      );
      final bridgeAdjacency = <String, List<String>>{
        ...initialAdjacency,
        // The physical location and trigger match cluster A's current result,
        // while the adjacency graph deliberately links only to cluster B.
        'BRIDGE': ['B0'],
        'B0': [...initialAdjacency['B0']!, 'BRIDGE'],
      };
      final bridged = request(
        observedAt: base.add(const Duration(seconds: 6)),
        active: [...clusterA, ...clusterB, bridge],
        newlyActive: [bridge],
        adjacency: bridgeAdjacency,
      );
      expect(estimator.estimate(bridged), isNotNull);

      final states = (bridged.metadata['nied_dart_hyp_detection_ids'] as List)
          .cast<Map<String, Object?>>();
      final activeStates = states
          .where((state) => state['active'] == true)
          .toList();
      expect(activeStates, hasLength(1));
      expect(activeStates.single['assigned_station_count'], 11);
      expect(
        (activeStates.single['assigned_station_codes'] as List),
        containsAll(<String>[
          ...clusterA.map((station) => station['code']! as String),
          ...clusterB.map((station) => station['code']! as String),
          'BRIDGE',
        ]),
      );
    },
  );

  test('reference NIED HYP rejects an 8-second large-cluster residual', () {
    final estimator = NiedDartHypSourceEstimator(
      searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
    );
    final base = DateTime(2026, 8, 4, 13);

    Map<String, Object?> snapshot({
      required String code,
      required double latitude,
      required double longitude,
      required DateTime triggerAt,
    }) => <String, Object?>{
      'id': code,
      'code': code,
      'latLng': [latitude, longitude],
      'triggerStamp': triggerAt.millisecondsSinceEpoch,
      'updateStamp': triggerAt.millisecondsSinceEpoch,
      'ascend': 4,
      'level': 12,
      'isActive': true,
    };

    SourceEstimationRequest request({
      required DateTime observedAt,
      required List<Map<String, Object?>> active,
      required List<Map<String, Object?>> newlyActive,
      required Map<String, List<String>> adjacency,
    }) => SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'reference-large-cluster-residual-limit',
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 2,
      stations: const [],
      metadata: {
        'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
        'nied_hypocenter_new_active_stations': newlyActive,
        'nied_hypocenter_active_stations': active,
        'nied_hypocenter_inactive_stations': const [],
        'nied_hypocenter_adj_station_ids': adjacency,
      },
    );

    final initialStations = <Map<String, Object?>>[
      for (var index = 0; index < 50; index++)
        snapshot(
          code: 'INITIAL$index',
          latitude: 35.0 + index * 0.001,
          longitude: 140.0 + index * 0.001,
          triggerAt: base.add(Duration(milliseconds: index * 40)),
        ),
    ];
    final initialAdjacency = <String, List<String>>{
      for (final station in initialStations)
        station['id']! as String: [
          for (final neighbor in initialStations)
            if (neighbor['id'] != station['id']) neighbor['id']! as String,
        ],
    };
    final initialRequest = request(
      observedAt: base.add(const Duration(seconds: 5)),
      active: initialStations,
      newlyActive: initialStations,
      adjacency: initialAdjacency,
    );
    final initialEstimate = estimator.estimate(initialRequest);
    expect(initialEstimate, isNotNull);
    final initialResult = initialEstimate!;
    expect(initialResult.originTime, isNotNull);

    final predictedPSeconds =
        KanameishiJma2001TravelTimeTable.travelTimeSeconds(
          surfaceDistanceKm: 0,
          depthKm: initialResult.depthKm!,
          pWave: true,
        );
    final delayedTriggerAt = initialResult.originTime!.add(
      Duration(milliseconds: ((predictedPSeconds + 8.0) * 1000).round()),
    );
    final delayed = snapshot(
      code: 'DELAYED',
      latitude: initialResult.latitude,
      longitude: initialResult.longitude,
      triggerAt: delayedTriggerAt,
    );
    final delayedRequest = request(
      observedAt: delayedTriggerAt.add(const Duration(seconds: 1)),
      active: [...initialStations, delayed],
      newlyActive: [delayed],
      adjacency: initialAdjacency,
    );
    expect(estimator.estimate(delayedRequest), isNotNull);

    final states =
        (delayedRequest.metadata['nied_dart_hyp_detection_ids'] as List)
            .cast<Map<String, Object?>>();
    final delayedState = states.singleWhere(
      (state) =>
          state['assigned_station_codes'] is List &&
          (state['assigned_station_codes'] as List).contains('DELAYED'),
    );
    expect(delayedState['assigned_station_count'], 1);
  });

  test('NIED Dart HYP excludes KA zero-contribution ascend stations', () {
    final estimator = NiedDartHypSourceEstimator();
    final base = DateTime(2026, 7, 18, 13);

    Map<String, Object?> snapshot(String code, int index, int ascend) =>
        <String, Object?>{
          'id': code,
          'code': code,
          'latLng': [35.0 + index * 0.01, 140.0 + index * 0.01],
          'triggerStamp': base
              .add(Duration(milliseconds: index * 200))
              .millisecondsSinceEpoch,
          'updateStamp': base
              .add(const Duration(seconds: 5))
              .millisecondsSinceEpoch,
          'ascend': ascend,
          'level': 12,
          'isActive': true,
        };

    final stations = <Map<String, Object?>>[
      snapshot('ZERO', 0, 1),
      for (var index = 1; index <= 4; index++)
        snapshot('EFFECTIVE${index - 1}', index, 4),
    ];
    final request = SourceEstimationRequest(
      sourceId: 'nied',
      eventId: 'ka-zero-contribution-gate',
      observedAt: base.add(const Duration(seconds: 5)),
      stageName: 'confirmed',
      maxShindo: 2,
      stations: const [],
      metadata: {
        'nied_hypocenter_new_active_stations': stations,
        'nied_hypocenter_active_stations': stations,
        'nied_hypocenter_inactive_stations': const [],
        'nied_detection_adj_station_codes': const <String, List<String>>{},
        'nied_hypocenter_detection_grid': const {
          'decimal': <double>[0.0, 0.0],
        },
      },
    );

    final estimate = estimator.estimate(request);
    expect(estimate, isNotNull);
    expect(estimate!.supportingStationCount, 4);
    expect(request.metadata['nied_dart_hyp_worker_active_count'], 5);
    expect(request.metadata['nied_dart_hyp_worker_effective_active_count'], 4);
    expect(request.metadata['nied_dart_hyp_worker_zero_contribution_count'], 1);
    expect(estimate.diagnostics['cluster_station_count'], 5);
    expect(estimate.diagnostics['effective_input_station_count'], 4);
    expect(estimate.diagnostics['zero_contribution_station_count'], 1);
    expect(
      estimate.diagnostics['station_contribution_model'],
      'ka_zero_weight_gate_max_ascend_below_2_then_scratch_distance_weight',
    );
    final panels = (estimate.diagnostics['travel_time_curve_panels'] as List)
        .cast<Map<String, Object?>>();
    final selected = panels.singleWhere((panel) => panel['selected'] == true);
    final samples = (selected['samples'] as List).cast<Map<String, Object?>>();
    expect(samples.map((sample) => sample['code']), isNot(contains('ZERO')));
    expect(
      selected['time_reference_model'],
      'earliest_effective_scoring_station_trigger',
    );
    expect(
      selected['time_reference'],
      base.add(const Duration(milliseconds: 200)).toIso8601String(),
    );
    expect(selected['observed_min_s'], 0.0);
  });
}
