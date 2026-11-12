import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';

/// Locks the default-off L2/L3 start-point shadow knobs used by
/// `tmp/capture_survey/run_start_shadow.py`. These flags must stay invisible to
/// production and must only add diagnostics when actively enabled.
void main() {
  final base = DateTime(2026, 10, 14, 12);

  Map<String, Object?> station(String code, int index) => <String, Object?>{
    'id': code,
    'code': code,
    'latLng': [35.0 + index * 0.1, 140.0 + index * 0.1],
    'triggerStamp': base
        .add(Duration(milliseconds: index * 200))
        .millisecondsSinceEpoch,
    'updateStamp': base.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
    'ascend': 4,
    'level': 12,
    // J3 amplitude channel reads the per-station observed intensity; supply a
    // finite value so the shadow term is non-vacuous in these tests.
    'shindo': 3.0 + index * 0.2,
    'isActive': true,
  };

  final active = <Map<String, Object?>>[
    for (var index = 0; index < 6; index++) station('SHADOW$index', index),
  ];
  final adjacency = <String, List<String>>{
    for (final current in active)
      current['id']! as String: [
        for (final neighbor in active)
          if (neighbor['id'] != current['id']) neighbor['id']! as String,
      ],
  };
  final ignoredInactive = <String, Object?>{
    'id': 'IGNORED_INACTIVE',
    'code': 'IGNORED_INACTIVE',
    'latLng': const [34.0, 139.0],
    'updateStamp': base.millisecondsSinceEpoch,
    'ascend': 0,
    'level': 12,
    'isActive': false,
  };

  SourceEstimationRequest frame(int index) => SourceEstimationRequest(
    sourceId: 'nied',
    eventId: 'shadow-start',
    observedAt: base.add(Duration(milliseconds: 5000 + index * 100)),
    stageName: 'confirmed',
    maxShindo: 2,
    stations: const [],
    metadata: {
      'nied_hypocenter_input_format': 'nied_station_hypocenter_snapshot_v1',
      'nied_hypocenter_new_active_stations': index == 0
          ? active
          : const <Map<String, Object?>>[],
      'nied_hypocenter_active_stations': active,
      'nied_hypocenter_inactive_stations': index.isOdd
          ? [ignoredInactive]
          : const <Map<String, Object?>>[],
      'nied_hypocenter_adj_station_ids': adjacency,
    },
  );

  NiedDartHypSourceEstimator newEstimator() => NiedDartHypSourceEstimator(
    searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
  );

  setUp(NiedHypStartShadow.reset);
  tearDown(NiedHypStartShadow.reset);

  test('defaults are off and add no shadow diagnostics', () {
    expect(NiedHypStartShadow.forceColdStart, isFalse);
    expect(NiedHypStartShadow.useAllTriggeredCentroidSeed, isFalse);
    expect(NiedHypStartShadow.forceDartSearch, isFalse);
    expect(NiedHypStartShadow.pinnedDepthKm, isNull);
    expect(NiedHypStartShadow.nyadNegativeEvidence, isFalse);
    expect(NiedHypStartShadow.amplitudeConsistency, isFalse);
    expect(NiedHypStartShadow.amplitudeWeight, 1.5);
    expect(NiedHypStartShadow.amplitudeMinStations, 0);
    expect(NiedHypStartShadow.depthPriorKm, isNull);
    expect(NiedHypStartShadow.depthPriorSigmaKm, 25.0);
    expect(NiedHypStartShadow.depthPriorWeight, 0.5);
    expect(NiedHypStartShadow.searchForm, 'greedy');
    expect(NiedHypStartShadow.gridTopK, 4);
    expect(NiedHypStartShadow.curvePanelPhaseFromResidual, isFalse);

    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    expect(first.diagnostics.containsKey('search_start_shadow'), isFalse);
    expect(first.diagnostics.containsKey('search_depth_shadow'), isFalse);
    expect(first.diagnostics.containsKey('search_nyad_shadow'), isFalse);
    expect(first.diagnostics.containsKey('search_amp_shadow'), isFalse);
    expect(first.diagnostics.containsKey('search_depthprior_shadow'), isFalse);
    expect(first.diagnostics.containsKey('search_grid_shadow'), isFalse);
    expect(first.diagnostics.containsKey('search_panelphase_shadow'), isFalse);
    expect(
      first.diagnostics['search_start_model'],
      'kanameishi_initial_hypocenter_before_first_result',
    );

    // Second frame is dirty (odd index) with a previous result available, so the
    // production path hot-starts from the published hypocentre.
    final second = estimator.estimate(frame(1))!;
    expect(second.diagnostics.containsKey('search_start_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_depth_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_nyad_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_amp_shadow'), isFalse);
    expect(
      second.diagnostics['search_start_model'],
      'kanameishi_previous_cluster_hypocenter',
    );
  });

  test('forceColdStart re-seeds every frame and only then reports shadow', () {
    NiedHypStartShadow.forceColdStart = true;
    final estimator = newEstimator();
    estimator.estimate(frame(0))!;
    final second = estimator.estimate(frame(1))!;
    expect(
      second.diagnostics['search_start_model'],
      'kanameishi_initial_hypocenter_before_first_result',
    );
    final shadow =
        second.diagnostics['search_start_shadow']! as Map<String, Object?>;
    expect(shadow['force_cold_start'], isTrue);
    expect(shadow['all_triggered_centroid_seed'], isFalse);
    // Earliest-only seed: just the single earliest-triggered station.
    expect(shadow['seed_station_count'], 1);
  });

  test('useAllTriggeredCentroidSeed widens the seed to every active station', () {
    NiedHypStartShadow.useAllTriggeredCentroidSeed = true;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_start_shadow']! as Map<String, Object?>;
    expect(shadow['force_cold_start'], isFalse);
    expect(shadow['all_triggered_centroid_seed'], isTrue);
    expect(shadow['seed_station_count'], active.length);
  });

  test('cold + all-triggered seed combines both levers', () {
    NiedHypStartShadow.forceColdStart = true;
    NiedHypStartShadow.useAllTriggeredCentroidSeed = true;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_start_shadow']! as Map<String, Object?>;
    expect(shadow['force_cold_start'], isTrue);
    expect(shadow['all_triggered_centroid_seed'], isTrue);
    expect(shadow['seed_station_count'], active.length);
    // The widened centroid must differ from the single earliest station seed.
    expect(shadow['seed_latitude'], isNot(closeTo(35.0, 1e-9)));
    expect(shadow['seed_longitude'], isNot(closeTo(140.0, 1e-9)));
  });

  test('reset restores production behaviour', () {
    NiedHypStartShadow.forceColdStart = true;
    NiedHypStartShadow.useAllTriggeredCentroidSeed = true;
    NiedHypStartShadow.forceDartSearch = true;
    NiedHypStartShadow.pinnedDepthKm = 30;
    NiedHypStartShadow.nyadNegativeEvidence = true;
    NiedHypStartShadow.amplitudeConsistency = true;
    NiedHypStartShadow.amplitudeWeight = 4.0;
    NiedHypStartShadow.amplitudeMinStations = 50;
    NiedHypStartShadow.depthPriorKm = 40;
    NiedHypStartShadow.depthPriorSigmaKm = 30;
    NiedHypStartShadow.depthPriorWeight = 2.0;
    NiedHypStartShadow.searchForm = 'grid';
    NiedHypStartShadow.gridTopK = 9;
    NiedHypStartShadow.curvePanelPhaseFromResidual = true;
    NiedHypStartShadow.reset();
    expect(NiedHypStartShadow.forceDartSearch, isFalse);
    expect(NiedHypStartShadow.pinnedDepthKm, isNull);
    expect(NiedHypStartShadow.nyadNegativeEvidence, isFalse);
    expect(NiedHypStartShadow.amplitudeConsistency, isFalse);
    expect(NiedHypStartShadow.amplitudeWeight, 1.5);
    expect(NiedHypStartShadow.amplitudeMinStations, 0);
    expect(NiedHypStartShadow.depthPriorKm, isNull);
    expect(NiedHypStartShadow.depthPriorSigmaKm, 25.0);
    expect(NiedHypStartShadow.depthPriorWeight, 0.5);
    expect(NiedHypStartShadow.searchForm, 'greedy');
    expect(NiedHypStartShadow.gridTopK, 4);
    expect(NiedHypStartShadow.curvePanelPhaseFromResidual, isFalse);
    final estimator = newEstimator();
    estimator.estimate(frame(0))!;
    final second = estimator.estimate(frame(1))!;
    expect(second.diagnostics.containsKey('search_start_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_depth_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_nyad_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_amp_shadow'), isFalse);
    expect(second.diagnostics.containsKey('search_grid_shadow'), isFalse);
    expect(
      second.diagnostics['search_start_model'],
      'kanameishi_previous_cluster_hypocenter',
    );
  });

  test('pinnedDepthKm forces the Dart path and fixes the focal depth', () {
    NiedHypStartShadow.pinnedDepthKm = 30;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_depth_shadow']! as Map<String, Object?>;
    expect(shadow['force_dart_search'], isTrue);
    expect(shadow['pinned_depth_km'], 30.0);
    expect(shadow['start_depth_km'], 30.0);
    // Every candidate ran on the pinned depth plane, so the result sits there.
    expect(first.depthKm, closeTo(30.0, 1e-9));
    expect(
      (first.diagnostics['searched_result']! as Map<String, Object?>)['depth_km'],
      closeTo(30.0, 1e-9),
    );

    // The depth pin must survive into the next (dirty) frame too.
    final second = estimator.estimate(frame(1))!;
    expect(second.depthKm, closeTo(30.0, 1e-9));
  });

  test('forceDartSearch alone is a free-depth path control', () {
    NiedHypStartShadow.forceDartSearch = true;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_depth_shadow']! as Map<String, Object?>;
    expect(shadow['force_dart_search'], isTrue);
    expect(shadow['pinned_depth_km'], isNull);
    // Free depth: the search may move the depth axis away from the 10 km seed.
    expect(first.depthKm, isNotNull);
  });

  test('nyadNegativeEvidence forces the Dart path and reports its shadow', () {
    NiedHypStartShadow.nyadNegativeEvidence = true;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_nyad_shadow']! as Map<String, Object?>;
    expect(shadow['nyad_negative_evidence'], isTrue);
    // NYAD needs a wall-clock "now", so it must run on the Dart scorer.
    expect(shadow['force_dart_search'], isTrue);
    expect(first.depthKm, isNotNull);

    // The depth shadow is emitted too because the Dart path is forced.
    expect(first.diagnostics.containsKey('search_depth_shadow'), isTrue);

    // And the knob must survive into the next (dirty) frame.
    final second = estimator.estimate(frame(1))!;
    expect(second.diagnostics.containsKey('search_nyad_shadow'), isTrue);
  });

  test('amplitudeConsistency forces the Dart path and reports its shadow', () {
    NiedHypStartShadow.amplitudeConsistency = true;
    NiedHypStartShadow.amplitudeWeight = 2.5;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_amp_shadow']! as Map<String, Object?>;
    expect(shadow['amplitude_consistency'], isTrue);
    expect(shadow['amplitude_weight'], 2.5);
    // The native scorer carries no amplitude words, so it must run on Dart.
    expect(shadow['force_dart_search'], isTrue);
    expect(first.depthKm, isNotNull);

    // Non-vacuous: every active station carries a finite intensity, so the
    // amplitude channel must actually see stations (not silently inert).
    expect(shadow['amplitude_station_count'], active.length);
    expect(shadow['amplitude_residual'], isA<double>());

    // The depth shadow is emitted too because the Dart path is forced.
    expect(first.diagnostics.containsKey('search_depth_shadow'), isTrue);

    // And the knob must survive into the next (dirty) frame.
    final second = estimator.estimate(frame(1))!;
    expect(second.diagnostics.containsKey('search_amp_shadow'), isTrue);
  });

  test('amplitudeMinStations gates the term below the station threshold', () {
    NiedHypStartShadow.amplitudeConsistency = true;
    NiedHypStartShadow.amplitudeWeight = 3.0;
    // Six active stations: a gate above that suppresses the term entirely.
    NiedHypStartShadow.amplitudeMinStations = 10;
    final gated = newEstimator().estimate(frame(0))!;
    final gatedShadow =
        gated.diagnostics['search_amp_shadow']! as Map<String, Object?>;
    expect(gatedShadow['amplitude_min_stations'], 10);
    expect(gatedShadow['amplitude_station_count'], active.length);
    expect(gatedShadow['amplitude_residual'], 0.0);

    // A gate at or below the station count lets the term through.
    NiedHypStartShadow.reset();
    NiedHypStartShadow.amplitudeConsistency = true;
    NiedHypStartShadow.amplitudeWeight = 3.0;
    NiedHypStartShadow.amplitudeMinStations = 3;
    final ungated = newEstimator().estimate(frame(0))!;
    final ungatedShadow =
        ungated.diagnostics['search_amp_shadow']! as Map<String, Object?>;
    expect(ungatedShadow['amplitude_min_stations'], 3);
    expect(ungatedShadow['amplitude_station_count'], active.length);
    expect(ungatedShadow['amplitude_residual'], isA<double>());
  });

  test('grid search form forces the Dart path and reports its shadow', () {
    NiedHypStartShadow.searchForm = 'grid';
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_grid_shadow']! as Map<String, Object?>;
    expect(shadow['search_form'], 'grid');
    expect(shadow['grid_spacing_deg'], 0.25);
    // Non-vacuous: the grid must actually have evaluated nodes and kept modes.
    final evaluations = shadow['grid_evaluation_count']! as int;
    expect(evaluations, greaterThan(0));
    expect(shadow['grid_node_count'], isA<int>());
    expect(shadow['grid_modes'], isA<List<Object?>>());
    expect((shadow['grid_modes']! as List<Object?>).isNotEmpty, isTrue);

    // The native scorer carries no grid search, so the Dart path is forced.
    expect(first.diagnostics.containsKey('search_depth_shadow'), isTrue);
    expect(first.depthKm, isNotNull);

    // And the knob must survive into the next (dirty) frame.
    final second = estimator.estimate(frame(1))!;
    expect(second.diagnostics.containsKey('search_grid_shadow'), isTrue);
  });

  test('grid search form composes with the J3 amplitude channel', () {
    NiedHypStartShadow.searchForm = 'grid';
    NiedHypStartShadow.amplitudeConsistency = true;
    NiedHypStartShadow.amplitudeWeight = 3.0;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    expect(first.diagnostics.containsKey('search_grid_shadow'), isTrue);
    final ampShadow =
        first.diagnostics['search_amp_shadow']! as Map<String, Object?>;
    expect(ampShadow['amplitude_station_count'], active.length);
    expect(ampShadow['amplitude_residual'], isA<double>());
  });

  test('panel phase shadow is display-only and reports its shadow', () {
    // Default off: the inspection view keeps the historic global-gate label
    // and the shadow key is absent (production runs stay byte-identical).
    final production = newEstimator().estimate(frame(0))!;
    expect(
      production.diagnostics.containsKey('search_panelphase_shadow'),
      isFalse,
    );

    NiedHypStartShadow.curvePanelPhaseFromResidual = true;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_panelphase_shadow']! as Map<String, Object?>;
    expect(shadow['curve_panel_phase_from_residual'], isTrue);
    expect(shadow['s_wave_gate_open'], isA<bool>());

    // The knob must survive into the next (dirty) frame.
    final second = estimator.estimate(frame(1))!;
    expect(second.diagnostics.containsKey('search_panelphase_shadow'), isTrue);
  });

  test('depth prior reports its shadow and composes with the grid form', () {
    NiedHypStartShadow.depthPriorKm = 20.0;
    NiedHypStartShadow.depthPriorSigmaKm = 25.0;
    NiedHypStartShadow.depthPriorWeight = 0.5;
    final estimator = newEstimator();
    final first = estimator.estimate(frame(0))!;
    final shadow =
        first.diagnostics['search_depthprior_shadow']!
            as Map<String, Object?>;
    expect(shadow['depth_prior_km'], 20.0);
    expect(shadow['depth_prior_sigma_km'], 25.0);
    expect(shadow['depth_prior_weight'], 0.5);
    expect(shadow['force_dart_search'], isTrue);
    expect(shadow['depth_prior_residual'], isA<double>());

    // Joint likelihood: grid form + amplitude + depth prior all together.
    NiedHypStartShadow.searchForm = 'grid';
    NiedHypStartShadow.amplitudeConsistency = true;
    final joint = newEstimator().estimate(frame(0))!;
    expect(joint.diagnostics.containsKey('search_grid_shadow'), isTrue);
    expect(joint.diagnostics.containsKey('search_amp_shadow'), isTrue);
    expect(joint.diagnostics.containsKey('search_depthprior_shadow'), isTrue);
  });
}
