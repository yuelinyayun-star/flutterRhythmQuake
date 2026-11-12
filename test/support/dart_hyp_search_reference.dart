// Search loop mechanically frozen from before-hyp-search.zip; the fixed
// reference schedule and independent original Dart scorer are supplied here.
// ignore_for_file: dead_code
part of 'dart_hyp_score_reference.dart';

enum _ReferenceSchedule {
  referenceBroadFourStage,
  scratchFiveStageJointNeighborhood,
}

Map<String, Object?> referenceHypSearch(
  List<double> coordinates,
  Int64List info,
  Int64List observedMilliseconds,
  int inactiveCount,
  double latitude,
  double longitude,
  double depth,
) {
  const referenceAlignedSearch = true;
  const searchSchedule = _ReferenceSchedule.referenceBroadFourStage;
  var candidateScoreCallCount = 1;
  var current = _referenceHypScoreResult(
    coordinates,
    info,
    observedMilliseconds,
    inactiveCount,
    latitude,
    longitude,
    depth,
  );
  final stages = <Map<String, Object?>>[];
  final steps = <({double degree, double? depth, bool enabled, int moveLimit})>[
    (degree: 3.0, depth: 100.0, enabled: true, moveLimit: 1000),
    (degree: 1.0, depth: 50.0, enabled: true, moveLimit: 1000),
    (degree: 0.3, depth: 20.0, enabled: true, moveLimit: 1000),
    (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 1000),
  ];
  var totalIteration = 0;
  var stageIteration = 0;
  var stageEvaluatedCandidateCount = 0;
  var stageRejectedCandidateCount = 0;
  var stageRejectedReasonCounts = <String, int>{};
  var stageMoves = <Map<String, Object?>>[];
  var stepIndex = 0;
  while (stepIndex < steps.length && totalIteration < 1000) {
    final step = steps[stepIndex];
    if (!step.enabled) {
      stages.add({
        'step_index': stepIndex,
        'degree_step': step.degree,
        'depth_step_km': step.depth,
        'move_limit': step.moveLimit,
        'termination_reason': 'skipped_station_count',
        'iterations': 0,
        'total_iterations': totalIteration,
        'evaluated_candidate_count': 0,
        'rejected_candidate_count': 0,
        'rejected_reason_counts': const <String, int>{},
        'moves': const <Map<String, Object?>>[],
        'best_score': current.score,
        'best_latitude': current.latitude,
        'best_longitude': current.longitude,
        'best_depth_km': current.depthKm,
        'terminal_center': {
          'latitude': current.latitude,
          'longitude': current.longitude,
          'depth_km': current.depthKm,
          'score': current.score,
          'error_level': current.errorLevel,
          'inactive_penalty': current.inactivePenalty,
        },
        'terminal_candidates': const <Map<String, Object?>>[],
      });
      stepIndex += 1;
      continue;
    }
    totalIteration += 1;
    stageIteration += 1;
    _NiedHypWorkerResult? bestCandidate;
    String? bestDirection;
    final iterationCandidates = <Map<String, Object?>>[];
    void scoreCandidate(
      String direction,
      double lat,
      double lng,
      double depthKm,
    ) {
      final rejectReason = _referenceSearchReject(lat, lng, depthKm);
      if (rejectReason != null) {
        stageRejectedCandidateCount += 1;
        stageRejectedReasonCounts[rejectReason] =
            (stageRejectedReasonCounts[rejectReason] ?? 0) + 1;
        iterationCandidates.add({
          'direction': direction,
          'latitude': lat,
          'longitude': lng,
          'depth_km': depthKm,
          'evaluated': false,
          'reject_reason': rejectReason,
        });
        return;
      }
      stageEvaluatedCandidateCount += 1;
      candidateScoreCallCount += 1;
      final candidate = _referenceHypScoreResult(
        coordinates,
        info,
        observedMilliseconds,
        inactiveCount,
        lat,
        lng,
        depthKm,
      );
      iterationCandidates.add({
        'direction': direction,
        'latitude': candidate.latitude,
        'longitude': candidate.longitude,
        'depth_km': candidate.depthKm,
        'score': candidate.score,
        'error_level': candidate.errorLevel,
        'inactive_penalty': candidate.inactivePenalty,
        'evaluated': true,
      });
      if (bestCandidate == null || candidate.score < bestCandidate!.score) {
        bestCandidate = candidate;
        bestDirection = direction;
      }
    }

    // NiedHypoInf.js searches this exact neighbor order. Its score surface is
    // discrete because phase assignment changes per candidate, so preserving
    // the order preserves the reference implementation's tie-breaking path.
    final lateralDirections = referenceAlignedSearch
        ? <(String, double, double)>[
            ('lng+${step.degree}', 0.0, step.degree),
            ('lat-${step.degree}', -step.degree, 0.0),
            ('lng-${step.degree}', 0.0, -step.degree),
            ('lat+${step.degree}', step.degree, 0.0),
          ]
        : <(String, double, double)>[
            ('lng+${step.degree}', 0.0, step.degree),
            ('lng-${step.degree}', 0.0, -step.degree),
            ('lat+${step.degree}', step.degree, 0.0),
            ('lat-${step.degree}', -step.degree, 0.0),
          ];
    for (final direction in lateralDirections) {
      scoreCandidate(
        direction.$1,
        current.latitude + direction.$2,
        current.longitude + direction.$3,
        current.depthKm,
      );
    }
    final depthStep = step.depth;
    if (depthStep != null) {
      scoreCandidate(
        'depth-${depthStep.toInt()}',
        current.latitude,
        current.longitude,
        current.depthKm - depthStep,
      );
      scoreCandidate(
        'depth+${depthStep.toInt()}',
        current.latitude,
        current.longitude,
        current.depthKm + depthStep,
      );
      if (searchSchedule ==
          _ReferenceSchedule.scratchFiveStageJointNeighborhood) {
        for (final latDirection in const [-1, 0, 1]) {
          for (final lngDirection in const [-1, 0, 1]) {
            for (final depthDirection in const [-1, 0, 1]) {
              final changedAxisCount =
                  (latDirection == 0 ? 0 : 1) +
                  (lngDirection == 0 ? 0 : 1) +
                  (depthDirection == 0 ? 0 : 1);
              if (changedAxisCount < 2) continue;
              scoreCandidate(
                'joint_lat${latDirection >= 0 ? '+' : ''}$latDirection'
                '_lng${lngDirection >= 0 ? '+' : ''}$lngDirection'
                '_depth${depthDirection >= 0 ? '+' : ''}$depthDirection',
                current.latitude + latDirection * step.degree,
                current.longitude + lngDirection * step.degree,
                current.depthKm + depthDirection * depthStep,
              );
            }
          }
        }
      }
    }
    final selectedCandidate = bestCandidate;
    if (selectedCandidate != null &&
        selectedCandidate.score + 1e-9 < current.score) {
      stageMoves.add({
        'stage_iteration': stageIteration,
        'total_iteration': totalIteration,
        'direction': bestDirection,
        'from': {
          'latitude': current.latitude,
          'longitude': current.longitude,
          'depth_km': current.depthKm,
          'score': current.score,
          'weighted_residual_squares': current.weightedResidualSquares,
          'weight_sum': current.weightSum,
          'inactive_penalty': current.inactivePenalty,
          'inactive_p_radius_km': current.inactivePRadiusKm,
          'station_scale': current.stationScale,
          'wave_count_penalty_multiplier': current.waveCountPenaltyMultiplier,
        },
        'to': {
          'latitude': selectedCandidate.latitude,
          'longitude': selectedCandidate.longitude,
          'depth_km': selectedCandidate.depthKm,
          'score': selectedCandidate.score,
          'weighted_residual_squares':
              selectedCandidate.weightedResidualSquares,
          'weight_sum': selectedCandidate.weightSum,
          'inactive_penalty': selectedCandidate.inactivePenalty,
          'inactive_p_radius_km': selectedCandidate.inactivePRadiusKm,
          'station_scale': selectedCandidate.stationScale,
          'wave_count_penalty_multiplier':
              selectedCandidate.waveCountPenaltyMultiplier,
        },
      });
      current = selectedCandidate;
      // Scratch exits after the move counter exceeds the stage limit.
      if (stageMoves.length > step.moveLimit) {
        stages.add({
          'step_index': stepIndex,
          'degree_step': step.degree,
          'depth_step_km': step.depth,
          'move_limit': step.moveLimit,
          'termination_reason': 'move_limit',
          'iterations': stageIteration,
          'total_iterations': totalIteration,
          'evaluated_candidate_count': stageEvaluatedCandidateCount,
          'rejected_candidate_count': stageRejectedCandidateCount,
          'rejected_reason_counts': stageRejectedReasonCounts,
          'moves': stageMoves,
          'best_score': current.score,
          'best_latitude': current.latitude,
          'best_longitude': current.longitude,
          'best_depth_km': current.depthKm,
          'terminal_center': {
            'latitude': current.latitude,
            'longitude': current.longitude,
            'depth_km': current.depthKm,
            'score': current.score,
            'error_level': current.errorLevel,
            'inactive_penalty': current.inactivePenalty,
          },
          'terminal_candidates': iterationCandidates,
        });
        stepIndex += 1;
        stageIteration = 0;
        stageEvaluatedCandidateCount = 0;
        stageRejectedCandidateCount = 0;
        stageRejectedReasonCounts = <String, int>{};
        stageMoves = <Map<String, Object?>>[];
      }
    } else {
      stages.add({
        'step_index': stepIndex,
        'degree_step': step.degree,
        'depth_step_km': step.depth,
        'move_limit': step.moveLimit,
        'termination_reason': 'local_minimum',
        'iterations': stageIteration,
        'total_iterations': totalIteration,
        'evaluated_candidate_count': stageEvaluatedCandidateCount,
        'rejected_candidate_count': stageRejectedCandidateCount,
        'rejected_reason_counts': stageRejectedReasonCounts,
        'moves': stageMoves,
        'best_score': current.score,
        'best_latitude': current.latitude,
        'best_longitude': current.longitude,
        'best_depth_km': current.depthKm,
        'terminal_center': {
          'latitude': current.latitude,
          'longitude': current.longitude,
          'depth_km': current.depthKm,
          'score': current.score,
          'error_level': current.errorLevel,
          'inactive_penalty': current.inactivePenalty,
        },
        'terminal_candidates': iterationCandidates,
      });
      stepIndex += 1;
      stageIteration = 0;
      stageEvaluatedCandidateCount = 0;
      stageRejectedCandidateCount = 0;
      stageRejectedReasonCounts = <String, int>{};
      stageMoves = <Map<String, Object?>>[];
    }
  }
  final searchedResult = current.copyWith(searchStages: stages);
  return {
    'summary': [
      searchedResult.latitude,
      searchedResult.longitude,
      searchedResult.depthKm,
      candidateScoreCallCount.toDouble(),
    ],
    'stages': stages,
    'score': referenceHypScore(
      coordinates,
      info,
      observedMilliseconds,
      inactiveCount,
      searchedResult.latitude,
      searchedResult.longitude,
      searchedResult.depthKm,
    ),
  };
}

String? _referenceSearchReject(
  double latitude,
  double longitude,
  double depthKm,
) {
  if (!depthKm.isFinite) return 'non_finite_depth';
  if (depthKm < 0.0) return 'depth_below_0_km';
  if (depthKm > 700.0) return 'depth_above_700_km';
  if (!longitude.isFinite || !latitude.isFinite) return 'non_finite_coordinate';
  if (latitude < -90.0 || latitude > 90.0) {
    return 'latitude_outside_scratch_bounds';
  }
  return null;
}
