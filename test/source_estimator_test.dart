import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

void main() {
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
    final estimator = NiedDartHypSourceEstimator();
    const epicenter = LatLng(39.95, 142.20);
    const depthKm = 30.0;
    final origin = DateTime(2026, 6, 22, 11, 27);
    final distance = const Distance();

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
        'detectLevel': 12,
        'activity': 12.0,
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
      },
    );

    expect(estimator.supports(request), isTrue);
    final estimate = estimator.estimate(request);
    expect(estimate, isNotNull);
    expect(estimate!.method, 'nied_dart_hyp_v1');
    expect(estimate.supportingStationCount, activeStations.length);
    expect(
      estimate.diagnostics['input_format'],
      'find_nied_hypocenter_worker_update_v1',
    );
    expect(
      estimate.diagnostics['score_model'],
      'article_step3_weighted_origin_rmse_plus_inactive_penalty',
    );
  });
}
