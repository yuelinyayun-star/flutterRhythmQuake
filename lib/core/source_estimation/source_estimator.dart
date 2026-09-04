import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nied_calibration.dart';
import '../../models/nied_station_db.dart';
import '../calculator.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/nied_detection_rules.dart';
import 'jma2001_travel_time_approximation.dart';
import 'kanameishi_jma2001_travel_time_table.dart';
import 'kotoho7_js_eew_bridge.dart';
import 'kotoho7_js_receiver_bridge.dart' as kotoho7_js;
import 'nied_pgv_magnitude_diagnostics.dart';
import 'source_estimation_models.dart';
import 'srev_kaizou_magnitude.dart';
import 'station_observation_history.dart';

part 'kotoho7_scratch_reference_tables.dart';

const int _kotoho7ScratchStationCount = 1748;

final Map<String, int> _kotoho7NiedStationIndexByCode = <String, int>{
  for (var index = 0; index < _kotoho7ScratchStationCount; index++)
    NiedStationDb.stations[index]['code'] as String: index,
};

final List<String> _kotoho7NiedStationCodeByScratchIndex = <String>[
  for (var index = 0; index < _kotoho7ScratchStationCount; index++)
    NiedStationDb.stations[index]['code'] as String,
];

final List<List<({double distanceKm, int stationIndex})>>
_kotoho7Nearest7ByStationIndex =
    _kotoho7ScratchNearest7ByStationIndex.length == _kotoho7ScratchStationCount
    ? _kotoho7ScratchNearest7ByStationIndex
    : _buildKotoho7GeneratedNearest7();

final Map<int, List<int>> _kotoho7ScratchStationIndicesByGridNumber =
    _buildKotoho7ScratchStationIndicesByGridNumber();

final List<int> _kotoho7ScratchPopulatedGridNumbers =
    _kotoho7ScratchStationIndicesByGridNumber.keys.toList(growable: false)
      ..sort();

final List<List<int>> _kotoho7ScratchGridStationIndicesBySerialIndex =
    _buildKotoho7ScratchGridStationIndicesBySerialIndex();

abstract class SourceEstimator {
  String get methodId;

  bool supports(SourceEstimationRequest request);

  SourceEstimate? estimate(SourceEstimationRequest request);
}

abstract interface class SourceEstimatorLifecycleOwner {
  bool get requiresEveryFrame;

  bool get ownsOutputLifecycle;
}

class WeightedCentroidSourceEstimator implements SourceEstimator {
  const WeightedCentroidSourceEstimator();

  @override
  String get methodId => 'weighted_centroid_baseline';

  @override
  bool supports(SourceEstimationRequest request) =>
      request.stations.where((s) => s.isActiveLike).length >= 2;

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final usable = request.stations
        .where((record) {
          return request.sensorSelection.accepts(record.descriptor) &&
              _isAssociatedRecord(request, record) &&
              record.isActiveLike &&
              record.lastValue != null &&
              record.lastValue!.isFinite;
        })
        .toList(growable: false);
    if (usable.length < 2) {
      return null;
    }

    double weightedLat = 0;
    double weightedLng = 0;
    double weightSum = 0;
    DateTime? earliestTrigger;

    for (final record in usable) {
      final valueWeight = math.max(record.lastValue ?? 0, -2.5) + 3.5;
      final activityWeight = math.max(record.lastActivity, 0) / 8.0;
      final triggerBonus = record.hasTriggered ? 1.0 : 0.35;
      final weight = math.max(0.2, valueWeight + activityWeight) * triggerBonus;
      weightedLat += record.descriptor.coordinate.latitude * weight;
      weightedLng += record.descriptor.coordinate.longitude * weight;
      weightSum += weight;
      final trigger = record.firstTriggerAt ?? record.firstRiseAt;
      if (trigger != null &&
          (earliestTrigger == null || trigger.isBefore(earliestTrigger))) {
        earliestTrigger = trigger;
      }
    }

    if (weightSum <= 0) {
      return null;
    }

    final latitude = weightedLat / weightSum;
    final longitude = weightedLng / weightSum;
    final confidence = math.min(0.85, 0.25 + usable.length * 0.06);

    return SourceEstimate(
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: usable.length,
      originTime: earliestTrigger,
      diagnostics: {
        'weight_sum': weightSum,
        'usable_station_count': usable.length,
        'event_stage': request.stageName,
      },
    );
  }
}

class TriggerTimeGridSearchEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;

  const TriggerTimeGridSearchEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 3.8,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
  });

  @override
  String get methodId => 'trigger_time_grid_v2';

  @override
  bool supports(SourceEstimationRequest request) {
    final triggeredCount = _usableTimingRecords(request).length;
    if (triggeredCount >= 3) {
      return true;
    }
    return fallback?.supports(request) ?? false;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final usable = _usableTimingRecords(request);
    if (usable.length < 3) {
      return fallback?.estimate(request);
    }

    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);

    _Candidate best = _Candidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      score: double.infinity,
    );

    best = _searchGrid(
      usable,
      earliestObserved,
      minLat: bounds.$1,
      maxLat: bounds.$2,
      minLng: bounds.$3,
      maxLng: bounds.$4,
      stepDeg: coarseStepDeg,
      currentBest: best,
      searchBounds: bounds,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - coarseStepDeg * 1.5,
      maxLat: best.latitude + coarseStepDeg * 1.5,
      minLng: best.longitude - coarseStepDeg * 1.5,
      maxLng: best.longitude + coarseStepDeg * 1.5,
      stepDeg: fineStepDeg,
      currentBest: best,
      searchBounds: bounds,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - fineStepDeg * 1.5,
      maxLat: best.latitude + fineStepDeg * 1.5,
      minLng: best.longitude - fineStepDeg * 1.5,
      maxLng: best.longitude + fineStepDeg * 1.5,
      stepDeg: refineStepDeg,
      currentBest: best,
      searchBounds: bounds,
    );

    if (!best.score.isFinite) {
      return fallback?.estimate(request);
    }

    final supportCount = usable.length;
    final geometry = _stationGeometryAt(
      usable,
      latitude: best.latitude,
      longitude: best.longitude,
    );
    final searchBoundaryMarginDeg = _searchBoundaryMarginDeg(best, bounds);
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore);
    final confidence =
        (0.15 +
                timeFit * 0.45 +
                rankFit * 0.20 +
                math.min(0.20, supportCount * 0.025))
            .clamp(0.0, 0.95);

    final originTime = earliestObserved.subtract(
      Duration(
        milliseconds:
            (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                .round(),
      ),
    );
    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: supportCount,
      originTime: originTime,
      diagnostics: {
        'wave_speed_kmps': assumedWaveSpeedKmPerSec,
        'time_score': best.timeScore,
        'rank_score': best.rankScore,
        'final_score': best.score,
        'reference_distance_km': best.referenceDistanceKm,
        'usable_station_count': supportCount,
        'search_bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        'search_boundary_margin_deg': searchBoundaryMarginDeg,
        'search_boundary_hit': searchBoundaryMarginDeg <= coarseStepDeg * 0.5,
        'station_azimuthal_gap_deg': geometry.azimuthalGapDeg,
        'nearest_station_distance_km': geometry.nearestDistanceKm,
        'station_geometry': geometry.isOneSided ? 'one_sided' : 'surrounded',
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _Candidate _searchGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved, {
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double stepDeg,
    required _Candidate currentBest,
    required (double, double, double, double) searchBounds,
  }) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        final scored = _scoreCandidate(
          usable,
          earliestObserved,
          lat,
          lng,
          assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
        );
        if (scored.score < best.score) {
          best = scored;
        }
      }
    }
    return best;
  }
}

class NiedGifHybridSourceEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;
  final double centerDistancePenaltyPerKm;
  final double singleWaveTimeScoreWeight;
  final double phaseLineScoreWeight;
  final double groupedPhaseLineScoreWeight;
  final double phaseDifferenceScoreWeight;
  final bool useOneSidedBoundaryCentroidGuard;
  final bool emitOneSidedBoundaryCentroidGuardCandidate;
  final double oneSidedBoundaryCentroidGuardMinUncertaintyP90Km;
  final double oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm;
  final double oneSidedBoundaryPenaltyPerKm;
  final double oneSidedBoundarySupportedDistanceKm;
  final double hypUnarrivedPenaltyScoreWeight;
  final double hypDepthRegularizationWeight;
  final double hypSSupportBonusPerStation;
  final double hypMaxSSupportBonus;
  final bool emitJma2001HypExperiment;
  final bool emitJqScoringHypExperiment;
  final bool emitKotoho7HypExperiment;

  const NiedGifHybridSourceEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 3.8,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
    this.centerDistancePenaltyPerKm = 0.015,
    this.singleWaveTimeScoreWeight = 0.85,
    this.phaseLineScoreWeight = 0.45,
    this.groupedPhaseLineScoreWeight = 0.0,
    this.phaseDifferenceScoreWeight = 0.0,
    this.useOneSidedBoundaryCentroidGuard = false,
    this.emitOneSidedBoundaryCentroidGuardCandidate = false,
    this.oneSidedBoundaryCentroidGuardMinUncertaintyP90Km = 0.0,
    this.oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm = 0.0,
    this.oneSidedBoundaryPenaltyPerKm = 0.0,
    this.oneSidedBoundarySupportedDistanceKm = 60.0,
    this.hypUnarrivedPenaltyScoreWeight = 1.0,
    this.hypDepthRegularizationWeight = 0.003,
    this.hypSSupportBonusPerStation = 0.2,
    this.hypMaxSSupportBonus = 1.2,
    this.emitJma2001HypExperiment = false,
    this.emitJqScoringHypExperiment = false,
    this.emitKotoho7HypExperiment = false,
  });

  @override
  String get methodId => 'nied_gif_hybrid_v1';

  bool _isGifRequest(SourceEstimationRequest request) {
    return request.metadata['nied_input_kind'] == 'gif';
  }

  @override
  bool supports(SourceEstimationRequest request) {
    if (!_isGifRequest(request)) return false;
    final triggeredCount = _usableTimingRecords(request).length;
    if (triggeredCount >= 3) return true;
    return fallback?.supports(request) ?? false;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    if (!_isGifRequest(request)) {
      request.metadata['kotoho7_null_reason'] = 'not_gif_request';
      return null;
    }
    final usable = _usableTimingRecords(request);
    if (usable.length < 3) {
      return fallback?.estimate(request);
    }

    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);

    _Candidate best = _Candidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      score: double.infinity,
    );

    best = _searchGifGrid(
      usable,
      earliestObserved,
      weightedCenter: weightedCenter,
      minLat: bounds.$1,
      maxLat: bounds.$2,
      minLng: bounds.$3,
      maxLng: bounds.$4,
      stepDeg: coarseStepDeg,
      currentBest: best,
      searchBounds: bounds,
    );
    best = _searchGifGrid(
      usable,
      earliestObserved,
      weightedCenter: weightedCenter,
      minLat: best.latitude - coarseStepDeg * 1.5,
      maxLat: best.latitude + coarseStepDeg * 1.5,
      minLng: best.longitude - coarseStepDeg * 1.5,
      maxLng: best.longitude + coarseStepDeg * 1.5,
      stepDeg: fineStepDeg,
      currentBest: best,
      searchBounds: bounds,
    );
    best = _searchGifGrid(
      usable,
      earliestObserved,
      weightedCenter: weightedCenter,
      minLat: best.latitude - fineStepDeg * 1.5,
      maxLat: best.latitude + fineStepDeg * 1.5,
      minLng: best.longitude - fineStepDeg * 1.5,
      maxLng: best.longitude + fineStepDeg * 1.5,
      stepDeg: refineStepDeg,
      currentBest: best,
      searchBounds: bounds,
    );

    if (!best.score.isFinite) {
      return fallback?.estimate(request);
    }

    final unconstrainedBest = best;
    var centroidGuardApplied = false;
    double? unconstrainedHorizontalUncertaintyP90Km;
    double? unconstrainedNearestStationDistanceKm;
    _Candidate? centroidGuardCandidate;
    if (useOneSidedBoundaryCentroidGuard ||
        emitOneSidedBoundaryCentroidGuardCandidate) {
      final unconstrainedGeometry = _stationGeometryAt(
        usable,
        latitude: best.latitude,
        longitude: best.longitude,
      );
      final unconstrainedBoundaryMarginDeg = _searchBoundaryMarginDeg(
        best,
        bounds,
      );
      final unconstrainedUncertainty = _horizontalUncertaintyKm(
        geometry: unconstrainedGeometry,
        searchBoundaryMarginDeg: unconstrainedBoundaryMarginDeg,
        supportCount: usable.length,
      );
      unconstrainedHorizontalUncertaintyP90Km = unconstrainedUncertainty.$2;
      unconstrainedNearestStationDistanceKm =
          unconstrainedGeometry.nearestDistanceKm;
      if (unconstrainedGeometry.isOneSided &&
          unconstrainedBoundaryMarginDeg <= coarseStepDeg * 0.5 &&
          unconstrainedUncertainty.$2 >=
              oneSidedBoundaryCentroidGuardMinUncertaintyP90Km &&
          unconstrainedGeometry.nearestDistanceKm >=
              oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm) {
        centroidGuardCandidate = _scoreNiedGifCandidate(
          usable,
          earliestObserved,
          weightedCenter.$1,
          weightedCenter.$2,
          weightedCenter: weightedCenter,
          assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
          centerDistancePenaltyPerKm: centerDistancePenaltyPerKm,
          singleWaveTimeScoreWeight: singleWaveTimeScoreWeight,
          phaseLineScoreWeight: phaseLineScoreWeight,
          groupedPhaseLineScoreWeight: groupedPhaseLineScoreWeight,
          phaseDifferenceScoreWeight: phaseDifferenceScoreWeight,
          searchBounds: bounds,
          boundaryHitThresholdDeg: coarseStepDeg * 0.5,
          oneSidedBoundaryPenaltyPerKm: oneSidedBoundaryPenaltyPerKm,
          oneSidedBoundarySupportedDistanceKm:
              oneSidedBoundarySupportedDistanceKm,
        );
        if (useOneSidedBoundaryCentroidGuard) {
          best = centroidGuardCandidate;
          centroidGuardApplied = true;
        }
      }
    }

    final supportCount = usable.length;
    final geometry = _stationGeometryAt(
      usable,
      latitude: best.latitude,
      longitude: best.longitude,
    );
    final searchBoundaryMarginDeg = _searchBoundaryMarginDeg(best, bounds);
    final uncertainty = _horizontalUncertaintyKm(
      geometry: geometry,
      searchBoundaryMarginDeg: searchBoundaryMarginDeg,
      supportCount: supportCount,
    );
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore / math.max(1, supportCount));
    final confidence =
        (0.18 +
                timeFit * 0.42 +
                rankFit * 0.28 +
                math.min(0.18, supportCount * 0.02))
            .clamp(0.0, 0.95);

    final originTime = earliestObserved.subtract(
      Duration(
        milliseconds:
            (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                .round(),
      ),
    );
    final hypDiagnostics = _niedGifHypDiagnostics(
      request,
      usable,
      earliestObserved: earliestObserved,
      seed: best,
      searchBounds: bounds,
      coarseStepDeg: math.max(0.24, coarseStepDeg),
      fineStepDeg: math.max(0.08, fineStepDeg),
      unarrivedPenaltyScoreWeight: hypUnarrivedPenaltyScoreWeight,
      depthRegularizationWeight: hypDepthRegularizationWeight,
      sSupportBonusPerStation: hypSSupportBonusPerStation,
      maxSSupportBonus: hypMaxSSupportBonus,
    );
    final jma2001HypDiagnostics = emitJma2001HypExperiment
        ? _niedGifHypDiagnostics(
            request,
            usable,
            earliestObserved: earliestObserved,
            seed: best,
            searchBounds: bounds,
            coarseStepDeg: math.max(0.24, coarseStepDeg),
            fineStepDeg: math.max(0.08, fineStepDeg),
            unarrivedPenaltyScoreWeight: hypUnarrivedPenaltyScoreWeight,
            depthRegularizationWeight: hypDepthRegularizationWeight,
            sSupportBonusPerStation: hypSSupportBonusPerStation,
            maxSSupportBonus: hypMaxSSupportBonus,
            methodId: 'nied_gif_hyp_jma2001_experiment',
            useJma2001TravelTime: true,
          )
        : null;
    final jqScoringHypDiagnostics = emitJqScoringHypExperiment
        ? _niedGifHypDiagnostics(
            request,
            usable,
            earliestObserved: earliestObserved,
            seed: best,
            searchBounds: bounds,
            coarseStepDeg: math.max(0.24, coarseStepDeg),
            fineStepDeg: math.max(0.08, fineStepDeg),
            unarrivedPenaltyScoreWeight: hypUnarrivedPenaltyScoreWeight,
            depthRegularizationWeight: hypDepthRegularizationWeight,
            sSupportBonusPerStation: hypSSupportBonusPerStation,
            maxSSupportBonus: hypMaxSSupportBonus,
            methodId: 'nied_gif_hyp_jq_scoring_experiment',
            useJma2001TravelTime: true,
            useJqStyleScoring: true,
          )
        : null;
    final kotoho7HypDiagnostics = emitKotoho7HypExperiment
        ? _niedGifHypKotoho7ReferenceDiagnostics(
            request,
            usable,
            earliestObserved: earliestObserved,
            searchBounds: bounds,
          )
        : null;
    final estimateDepthKm =
        _supportedDiagnosticDepthKm(hypDiagnostics) ??
        (best.groupedPhaseDepthSupported ? best.groupedPhaseBestDepthKm : null);
    final magnitudeDiagnostics = _niedGifMagnitudeDiagnostics(
      usable,
      sourceLatitude: best.latitude,
      sourceLongitude: best.longitude,
      depthKm: estimateDepthKm ?? 40.0,
      depthSource: estimateDepthKm == null
          ? 'default_40km_until_depth_supported'
          : _supportedDiagnosticDepthKm(hypDiagnostics) != null
          ? 'nied_gif_hyp_depth_supported'
          : 'grouped_phase_supported',
    );
    final diagnosticMagnitude = _supportedDiagnosticMagnitude(
      magnitudeDiagnostics,
    );

    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      depthKm: estimateDepthKm,
      magnitude: diagnosticMagnitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: supportCount,
      originTime: originTime,
      diagnostics: {
        'wave_speed_kmps': assumedWaveSpeedKmPerSec,
        'time_score': best.timeScore,
        'phase_line_score': best.phaseLineScore,
        'grouped_phase_line_score': best.groupedPhaseLineScore,
        'grouped_phase_line_mean_residual_s':
            best.groupedPhaseLineMeanResidualSeconds,
        'grouped_phase_best_depth_km': best.groupedPhaseBestDepthKm,
        'grouped_phase_depth_mean_residual_s':
            best.groupedPhaseDepthMeanResidualSeconds,
        'grouped_phase_depth_supported': best.groupedPhaseDepthSupported,
        'grouped_phase_line_p_count': best.groupedPhaseLinePCount,
        'grouped_phase_line_s_count': best.groupedPhaseLineSCount,
        'grouped_phase_line_other_count': best.groupedPhaseLineOtherCount,
        ...magnitudeDiagnostics,
        'nied_gif_hyp_v1': hypDiagnostics,
        ...jma2001HypDiagnostics == null
            ? const <String, Object?>{}
            : {'nied_gif_hyp_jma2001_experiment': jma2001HypDiagnostics},
        ...jqScoringHypDiagnostics == null
            ? const <String, Object?>{}
            : {'nied_gif_hyp_jq_scoring_experiment': jqScoringHypDiagnostics},
        ...kotoho7HypDiagnostics == null
            ? const <String, Object?>{}
            : {
                'nied_gif_hyp_kotoho7_reference_replay_v1':
                    kotoho7HypDiagnostics,
              },
        'p_only_line_mean_residual_s': best.pOnlyLineMeanResidualSeconds,
        'p_only_line_residual_p90_s': best.pOnlyLineResidualP90Seconds,
        'p_only_best_depth_km': best.pOnlyBestDepthKm,
        'p_only_depth_mean_residual_s': best.pOnlyDepthMeanResidualSeconds,
        'p_only_depth_supported': best.pOnlyDepthSupported,
        's_only_line_mean_residual_s': best.sOnlyLineMeanResidualSeconds,
        's_only_line_residual_p90_s': best.sOnlyLineResidualP90Seconds,
        'phase_difference_score': best.phaseDifferenceScore,
        'phase_difference_mean_residual_s':
            best.phaseDifferenceMeanResidualSeconds,
        'phase_difference_pair_count': best.phaseDifferencePairCount,
        'phase_line_p_count': best.phaseLinePCount,
        'phase_line_s_count': best.phaseLineSCount,
        'phase_line_other_count': best.phaseLineOtherCount,
        'phase_line_mean_residual_s': best.phaseLineMeanResidualSeconds,
        'rank_score': best.rankScore,
        'geometry_penalty': best.geometryPenalty,
        'one_sided_score_mode': best.oneSidedScoreMode,
        'final_score': best.score,
        'reference_distance_km': best.referenceDistanceKm,
        'usable_station_count': supportCount,
        'search_bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        'search_boundary_margin_deg': searchBoundaryMarginDeg,
        'search_boundary_hit': searchBoundaryMarginDeg <= coarseStepDeg * 0.5,
        'station_azimuthal_gap_deg': geometry.azimuthalGapDeg,
        'nearest_station_distance_km': geometry.nearestDistanceKm,
        'station_geometry': geometry.isOneSided ? 'one_sided' : 'surrounded',
        'horizontal_uncertainty_p50_km': uncertainty.$1,
        'horizontal_uncertainty_p90_km': uncertainty.$2,
        'horizontal_uncertainty_model': 'geometry_diagnostic_v1',
        'one_sided_boundary_centroid_guard_applied': centroidGuardApplied,
        if (centroidGuardCandidate != null)
          'candidate_corrections': {
            'one_sided_boundary_centroid_guard': {
              'latitude': centroidGuardCandidate.latitude,
              'longitude': centroidGuardCandidate.longitude,
              'score': centroidGuardCandidate.score,
              'time_score': centroidGuardCandidate.timeScore,
              'phase_line_score': centroidGuardCandidate.phaseLineScore,
              'grouped_phase_line_score':
                  centroidGuardCandidate.groupedPhaseLineScore,
              'grouped_phase_line_mean_residual_s':
                  centroidGuardCandidate.groupedPhaseLineMeanResidualSeconds,
              'grouped_phase_best_depth_km':
                  centroidGuardCandidate.groupedPhaseBestDepthKm,
              'grouped_phase_depth_mean_residual_s':
                  centroidGuardCandidate.groupedPhaseDepthMeanResidualSeconds,
              'grouped_phase_depth_supported':
                  centroidGuardCandidate.groupedPhaseDepthSupported,
              'grouped_phase_line_p_count':
                  centroidGuardCandidate.groupedPhaseLinePCount,
              'grouped_phase_line_s_count':
                  centroidGuardCandidate.groupedPhaseLineSCount,
              'grouped_phase_line_other_count':
                  centroidGuardCandidate.groupedPhaseLineOtherCount,
              'p_only_line_mean_residual_s':
                  centroidGuardCandidate.pOnlyLineMeanResidualSeconds,
              'p_only_line_residual_p90_s':
                  centroidGuardCandidate.pOnlyLineResidualP90Seconds,
              'p_only_best_depth_km': centroidGuardCandidate.pOnlyBestDepthKm,
              'p_only_depth_mean_residual_s':
                  centroidGuardCandidate.pOnlyDepthMeanResidualSeconds,
              'p_only_depth_supported':
                  centroidGuardCandidate.pOnlyDepthSupported,
              's_only_line_mean_residual_s':
                  centroidGuardCandidate.sOnlyLineMeanResidualSeconds,
              's_only_line_residual_p90_s':
                  centroidGuardCandidate.sOnlyLineResidualP90Seconds,
              'phase_difference_score':
                  centroidGuardCandidate.phaseDifferenceScore,
              'phase_difference_mean_residual_s':
                  centroidGuardCandidate.phaseDifferenceMeanResidualSeconds,
              'phase_difference_pair_count':
                  centroidGuardCandidate.phaseDifferencePairCount,
              'phase_line_p_count': centroidGuardCandidate.phaseLinePCount,
              'phase_line_s_count': centroidGuardCandidate.phaseLineSCount,
              'phase_line_other_count':
                  centroidGuardCandidate.phaseLineOtherCount,
              'phase_line_mean_residual_s':
                  centroidGuardCandidate.phaseLineMeanResidualSeconds,
              'rank_score': centroidGuardCandidate.rankScore,
              'geometry_penalty': centroidGuardCandidate.geometryPenalty,
              'one_sided_score_mode': centroidGuardCandidate.oneSidedScoreMode,
              'reference_distance_km':
                  centroidGuardCandidate.referenceDistanceKm,
              'applied': centroidGuardApplied,
              'trigger': {
                'station_geometry': 'one_sided',
                'search_boundary_hit': true,
                'min_horizontal_uncertainty_p90_km':
                    oneSidedBoundaryCentroidGuardMinUncertaintyP90Km,
                'min_nearest_station_distance_km':
                    oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm,
                'horizontal_uncertainty_p90_km':
                    unconstrainedHorizontalUncertaintyP90Km,
                'nearest_station_distance_km':
                    unconstrainedNearestStationDistanceKm,
              },
            },
          },
        if (centroidGuardApplied)
          'unconstrained_candidate': {
            'latitude': unconstrainedBest.latitude,
            'longitude': unconstrainedBest.longitude,
            'score': unconstrainedBest.score,
            'search_boundary_margin_deg': _searchBoundaryMarginDeg(
              unconstrainedBest,
              bounds,
            ),
            'station_azimuthal_gap_deg': _stationGeometryAt(
              usable,
              latitude: unconstrainedBest.latitude,
              longitude: unconstrainedBest.longitude,
            ).azimuthalGapDeg,
            'horizontal_uncertainty_p90_km':
                unconstrainedHorizontalUncertaintyP90Km,
            'nearest_station_distance_km':
                unconstrainedNearestStationDistanceKm,
          },
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _Candidate _searchGifGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved, {
    required (double, double) weightedCenter,
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double stepDeg,
    required _Candidate currentBest,
    required (double, double, double, double) searchBounds,
  }) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        final scored = _scoreNiedGifCandidate(
          usable,
          earliestObserved,
          lat,
          lng,
          weightedCenter: weightedCenter,
          assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
          centerDistancePenaltyPerKm: centerDistancePenaltyPerKm,
          singleWaveTimeScoreWeight: singleWaveTimeScoreWeight,
          phaseLineScoreWeight: phaseLineScoreWeight,
          groupedPhaseLineScoreWeight: groupedPhaseLineScoreWeight,
          phaseDifferenceScoreWeight: phaseDifferenceScoreWeight,
          searchBounds: searchBounds,
          boundaryHitThresholdDeg: coarseStepDeg * 0.5,
          oneSidedBoundaryPenaltyPerKm: oneSidedBoundaryPenaltyPerKm,
          oneSidedBoundarySupportedDistanceKm:
              oneSidedBoundarySupportedDistanceKm,
        );
        if (scored.score < best.score) {
          best = scored;
        }
      }
    }
    return best;
  }
}

class NiedGifPhysicalFusionExperimentalEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;

  const NiedGifPhysicalFusionExperimentalEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 3.8,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
  });

  @override
  String get methodId => 'nied_gif_physical_fusion_experimental_v1';

  @override
  bool supports(SourceEstimationRequest request) {
    if (request.metadata['nied_input_kind'] != 'gif') return false;
    final usable = _usableTimingRecords(request);
    return usable.length >= 3 || (fallback?.supports(request) ?? false);
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    if (request.metadata['nied_input_kind'] != 'gif') return null;
    final usable = _usableTimingRecords(request);
    if (usable.length < 3) return fallback?.estimate(request);
    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);
    var best = _Candidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      score: double.infinity,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      weightedCenter,
      bounds.$1,
      bounds.$2,
      bounds.$3,
      bounds.$4,
      coarseStepDeg,
      best,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      weightedCenter,
      best.latitude - coarseStepDeg * 1.5,
      best.latitude + coarseStepDeg * 1.5,
      best.longitude - coarseStepDeg * 1.5,
      best.longitude + coarseStepDeg * 1.5,
      fineStepDeg,
      best,
    );
    best = _searchGrid(
      usable,
      earliestObserved,
      weightedCenter,
      best.latitude - fineStepDeg * 1.5,
      best.latitude + fineStepDeg * 1.5,
      best.longitude - fineStepDeg * 1.5,
      best.longitude + fineStepDeg * 1.5,
      refineStepDeg,
      best,
    );
    if (!best.score.isFinite) return fallback?.estimate(request);

    final supportCount = usable.length;
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore / math.max(1, supportCount));
    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      confidence:
          (0.18 +
                  timeFit * 0.42 +
                  rankFit * 0.28 +
                  math.min(0.18, supportCount * 0.02))
              .clamp(0.0, 0.95),
      method: methodId,
      supportingStationCount: supportCount,
      originTime: earliestObserved.subtract(
        Duration(
          milliseconds:
              (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                  .round(),
        ),
      ),
      diagnostics: {
        'experimental': true,
        'physical_rank_weights': const {'pga': 0.35, 'pgv': 0.20, 'pgd': 0.10},
        'time_score': best.timeScore,
        'rank_score': best.rankScore,
        'final_score': best.score,
        'usable_station_count': supportCount,
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _Candidate _searchGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved,
    (double, double) weightedCenter,
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
    double stepDeg,
    _Candidate currentBest,
  ) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        final scored = _scoreNiedPhysicalCandidate(
          usable,
          earliestObserved,
          lat,
          lng,
          weightedCenter: weightedCenter,
          assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
        );
        if (scored.score < best.score) best = scored;
      }
    }
    return best;
  }
}

class Kotoho7JsReceiverSourceEstimator implements SourceEstimator {
  Kotoho7JsReceiverSourceEstimator({
    this.maxCachedEvents = 6,
    this.maxHistoryFrames = 90,
    this.scriptPath = 'tools/kotoho7_receiver_bridge_runner.js',
    this.serverScriptPath = 'tools/kotoho7_receiver_bridge_server.js',
  });

  final int maxCachedEvents;
  final int maxHistoryFrames;
  final String scriptPath;
  final String serverScriptPath;
  final Map<String, _Kotoho7JsReceiverFrameHistory> _historyByEvent =
      <String, _Kotoho7JsReceiverFrameHistory>{};
  final Map<String, SourceEstimate> _lastEstimateByEvent =
      <String, SourceEstimate>{};
  final Map<String, String> _lastDebugStatusByEvent = <String, String>{};

  @override
  String get methodId => 'nied_gif_kotoho7_js_receiver_v1';

  bool _isKotoho7ReceiverRequest(SourceEstimationRequest request) {
    if (request.metadata['source_family'] != 'nied') return false;
    return request.metadata.containsKey(
      'kotoho7_receiver_current_frame_observations',
    );
  }

  @override
  bool supports(SourceEstimationRequest request) {
    return _isKotoho7ReceiverRequest(request) &&
        _currentFrameObservations(request).isNotEmpty;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    if (!_isKotoho7ReceiverRequest(request)) {
      request.metadata['kotoho7_js_receiver_null_reason'] =
          'not_kotoho7_receiver_request';
      return null;
    }
    final currentFrame = _currentFrameObservations(request);
    if (currentFrame.isEmpty) {
      request.metadata['kotoho7_js_receiver_null_reason'] =
          'current_frame_observations_empty';
      return null;
    }

    final key = '${request.sourceId}:${request.eventId}';
    final history = _historyByEvent.putIfAbsent(
      key,
      () => _Kotoho7JsReceiverFrameHistory(),
    );
    _evictOldHistories(keepKey: key);
    final frameAdded = history.addFrame(
      request.observedAt,
      currentFrame,
      maxFrames: maxHistoryFrames,
    );
    request.metadata['kotoho7_js_receiver_frame_count'] = history.frameCount;
    request.metadata['kotoho7_js_receiver_observation_count'] =
        history.observationCount;
    request.metadata['kotoho7_js_receiver_input_frame_count'] =
        history.frameCount;
    request.metadata['kotoho7_js_receiver_frame_added'] = frameAdded;
    _debugKotoho7ReceiverStatus(
      key,
      'request kind=${request.metadata['nied_input_kind']} '
      'frame=${history.frameCount} current=${currentFrame.length} '
      'history=${history.observationCount} '
      'stage=${request.stageName}',
    );

    final previousEstimate = _lastEstimateByEvent[key];
    final bridgeResult = frameAdded
        ? kotoho7_js.Kotoho7JsReceiverBridge.run(
            kotoho7_js.Kotoho7ReceiverBridgeInput(
              observations: currentFrame,
              scriptPath: scriptPath,
              serverScriptPath: serverScriptPath,
              sessionKey: key,
              persistent: true,
              cloudRt: true,
              traceStations: false,
              runHyp: true,
            ),
          )
        : kotoho7_js.Kotoho7JsReceiverBridge.latest(key);
    if (bridgeResult == null) {
      request.metadata['kotoho7_js_receiver_null_reason'] =
          'duplicate_frame_waiting_for_bridge';
      _debugKotoho7ReceiverStatus(
        key,
        'duplicate_frame_waiting frame=${history.frameCount} '
        'current=${currentFrame.length}',
      );
      return previousEstimate;
    }

    request.metadata['kotoho7_js_receiver_available'] = bridgeResult.available;
    request.metadata['kotoho7_js_receiver_ok'] = bridgeResult.ok;
    request.metadata['kotoho7_js_receiver_elapsed_ms'] =
        bridgeResult.elapsedMilliseconds;
    request.metadata['kotoho7_js_receiver_peak_detection_id_count'] =
        bridgeResult.peakDetectionIdCount;
    request.metadata['kotoho7_js_receiver_peak_estimated_station_count'] =
        bridgeResult.peakEstimatedStations;
    final finalState = bridgeResult.finalState;
    request.metadata['kotoho7_js_receiver_js_applied_count'] = _intFromObject(
      finalState['applied'],
    );
    request.metadata['kotoho7_js_receiver_js_skipped_count'] = _intFromObject(
      finalState['skipped'],
    );
    request.metadata['kotoho7_js_receiver_js_frame'] = finalState['frame'];
    if (!bridgeResult.ok) {
      request.metadata['kotoho7_js_receiver_error'] = bridgeResult.error;
      request.metadata['kotoho7_js_receiver_null_reason'] = 'bridge_not_ok';
      _debugKotoho7ReceiverStatus(
        key,
        'bridge_not_ok error=${bridgeResult.error} '
        'frame=${history.frameCount} current=${currentFrame.length}',
      );
      return previousEstimate;
    }

    final best = bridgeResult.bestSourceByError;
    final source = kotoho7_js.objectMap(best['source']);
    final latitude = kotoho7_js.doubleValue(source['lat']);
    final longitude = kotoho7_js.doubleValue(source['lon']);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        !QuakeCalculator.isUsableMapCoordinate(latitude, longitude)) {
      request.metadata['kotoho7_js_receiver_null_reason'] =
          'best_source_missing_or_invalid';
      _debugKotoho7ReceiverStatus(
        key,
        'best_source_missing frame=${history.frameCount} '
        'processed=${bridgeResult.processedFrameCount} '
        'peakIds=${bridgeResult.peakDetectionIdCount} '
        'peakEstimated=${bridgeResult.peakEstimatedStations} '
        'finalIds=${finalState['detectionIdCount']} '
        'finalEstimated=${finalState['estimatedStations']} '
        'finalPermitted=${finalState['permittedStations']}',
      );
      return previousEstimate;
    }

    final error = kotoho7_js.doubleValue(best['error']);
    final appliedCount =
        _intFromObject(best['appliedCount']) ??
        bridgeResult.peakEstimatedStations;
    final depthKm = kotoho7_js.doubleValue(source['depthKm']);
    final magnitude = kotoho7_js.doubleValue(source['magnitude']);
    final originSecondsSince2000 = kotoho7_js.doubleValue(source['originTime']);
    final originTime = originSecondsSince2000 == null
        ? null
        : DateTime.utc(2000, 1, 1).add(
            Duration(milliseconds: (originSecondsSince2000 * 1000).round()),
          );
    final confidence = _confidenceFromKotoho7Bridge(
      error: error,
      supportCount: appliedCount,
      detectionIdCount: bridgeResult.peakDetectionIdCount,
      processedFrameCount: bridgeResult.processedFrameCount,
    );

    final estimate = SourceEstimate(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      magnitude: magnitude,
      originTime: originTime,
      confidence: confidence,
      method: methodId,
      supportingStationCount: appliedCount,
      diagnostics: {
        'method': methodId,
        'upstream': 'kotoho7_scratch_realtime_earthquake_viewer_js',
        'input_format': 'scratch_cloud_rt_c2b0_compatible',
        'input_content': request.metadata['nied_input_kind'] == 'gif'
            ? 'nied_gif_decoded_shindo_current_frame'
            : 'nied_realtime_station_shindo_current_frame',
        'runtime': 'in_app_webview2_js_state_machine',
        'script_asset': 'assets/kotoho7/kotoho7_receiver_compiled_core.js',
        'legacy_script_path': scriptPath,
        'bridge_elapsed_ms': bridgeResult.elapsedMilliseconds,
        'history_frame_count': history.frameCount,
        'history_observation_count': history.observationCount,
        'js_input_observation_count': currentFrame.length,
        'js_applied_count': _intFromObject(finalState['applied']),
        'js_skipped_count': _intFromObject(finalState['skipped']),
        'js_frame': finalState['frame'],
        'processed_frame_count': bridgeResult.processedFrameCount,
        'peak_detection_id_count': bridgeResult.peakDetectionIdCount,
        'peak_estimated_station_count': bridgeResult.peakEstimatedStations,
        'js_max_shindo': kotoho7_js.doubleValue(
          bridgeResult.finalState['maxScratchShindo'],
        ),
        'js_max_shindo_index': kotoho7_js.doubleValue(
          bridgeResult.finalState['maxScratchShindoIndex'],
        ),
        'js_map_max_shindo_raw':
            bridgeResult.finalState['mapDisplayedMaxShindoRaw'],
        'js_map_max_shindo_mode': kotoho7_js.doubleValue(
          bridgeResult.finalState['mapDisplayedMaxShindoMode'],
        ),
        'js_map_max_scratch_level': kotoho7_js.doubleValue(
          bridgeResult.finalState['mapDisplayedMaxScratchLevel'],
        ),
        'js_map_max_shindo_class': kotoho7_js.doubleValue(
          bridgeResult.finalState['mapDisplayedMaxShindoClass'],
        ),
        'js_map_max_shindo_index': kotoho7_js.doubleValue(
          bridgeResult.finalState['mapDisplayedMaxShindoIndex'],
        ),
        'best_source_frame': best['frame'],
        'best_source_error': error,
        'best_source_applied_count': appliedCount,
        'best_source_p_radius_km': kotoho7_js.doubleValue(source['pRadiusKm']),
        'best_source_s_radius_km': kotoho7_js.doubleValue(source['sRadiusKm']),
        'best_source_depth_km': depthKm,
        'best_source_magnitude': magnitude,
        'best_source_origin_time': originTime?.toIso8601String(),
        'best_source_phase_stations': best['phaseStations'],
        'best_source': source,
      },
    );
    _lastEstimateByEvent[key] = estimate;
    _debugKotoho7ReceiverStatus(
      key,
      'estimate lat=${latitude.toStringAsFixed(3)} '
      'lon=${longitude.toStringAsFixed(3)} '
      'depth=${depthKm?.toStringAsFixed(0) ?? 'null'} '
      'support=$appliedCount error=${error?.toStringAsFixed(3) ?? 'null'} '
      'processed=${bridgeResult.processedFrameCount}',
    );
    return estimate;
  }

  void _debugKotoho7ReceiverStatus(String key, String status) {
    if (!kDebugMode) return;
    if (_lastDebugStatusByEvent[key] == status) return;
    _lastDebugStatusByEvent[key] = status;
    debugPrint('[Kotoho7ReceiverEstimator] $key: $status');
  }

  List<kotoho7_js.Kotoho7ReceiverObservation> _currentFrameObservations(
    SourceEstimationRequest request,
  ) {
    final raw = request.metadata['kotoho7_receiver_current_frame_observations'];
    if (raw is Iterable) {
      final observations = <kotoho7_js.Kotoho7ReceiverObservation>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final code = item['stationCode']?.toString();
        final shindo = kotoho7_js.doubleValue(item['gifDecodedShindo']);
        final observedAtRaw = item['observedAtUtc'];
        final observedAt = observedAtRaw == null
            ? request.observedAt
            : DateTime.tryParse(observedAtRaw.toString()) ?? request.observedAt;
        if (code == null ||
            code.isEmpty ||
            shindo == null ||
            !shindo.isFinite) {
          continue;
        }
        observations.add(
          kotoho7_js.Kotoho7ReceiverObservation(
            stationCode: code,
            observedAtUtc: observedAt.toUtc(),
            gifDecodedShindo: shindo,
            scratchTenIndex: _kotoho7NiedStationIndexByCode[code] == null
                ? null
                : _kotoho7NiedStationIndexByCode[code]! + 1,
          ),
        );
      }
      if (observations.isNotEmpty) return observations;
    }

    return [
      for (final record in request.stations)
        if (record.lastValue != null && record.lastValue!.isFinite)
          kotoho7_js.Kotoho7ReceiverObservation(
            stationCode: record.descriptor.code,
            observedAtUtc: request.observedAt.toUtc(),
            gifDecodedShindo: record.lastValue!,
            scratchTenIndex:
                _kotoho7NiedStationIndexByCode[record.descriptor.code] == null
                ? null
                : _kotoho7NiedStationIndexByCode[record.descriptor.code]! + 1,
          ),
    ];
  }

  void _evictOldHistories({required String keepKey}) {
    if (_historyByEvent.length <= maxCachedEvents) return;
    final keys = _historyByEvent.keys.where((key) => key != keepKey).toList();
    while (_historyByEvent.length > maxCachedEvents && keys.isNotEmpty) {
      final removed = keys.removeAt(0);
      _historyByEvent.remove(removed);
      _lastEstimateByEvent.remove(removed);
    }
  }

  double _confidenceFromKotoho7Bridge({
    required double? error,
    required int supportCount,
    required int detectionIdCount,
    required int processedFrameCount,
  }) {
    final supportTerm = math.min(0.28, supportCount * 0.012);
    final idTerm = detectionIdCount > 0 ? 0.18 : 0.0;
    final frameTerm = math.min(0.12, processedFrameCount * 0.004);
    final errorTerm = error == null || !error.isFinite
        ? 0.0
        : (0.42 / (1.0 + error / 900.0));
    return (0.12 + supportTerm + idTerm + frameTerm + errorTerm).clamp(
      0.0,
      0.92,
    );
  }
}

class _Kotoho7JsReceiverFrameHistory {
  final List<int> _frameObservationCounts = <int>[];
  DateTime? _lastObservedAt;
  int _observationCount = 0;

  int get frameCount => _frameObservationCounts.length;
  int get observationCount => _observationCount;

  bool addFrame(
    DateTime observedAt,
    List<kotoho7_js.Kotoho7ReceiverObservation> observations, {
    int maxFrames = 90,
  }) {
    if (_lastObservedAt != null && !_lastObservedAt!.isBefore(observedAt)) {
      return false;
    }
    _lastObservedAt = observedAt;
    final count = observations.length;
    _frameObservationCounts.add(count);
    _observationCount += count;
    if (_frameObservationCounts.length > maxFrames) {
      final removeCount = _frameObservationCounts.length - maxFrames;
      for (var i = 0; i < removeCount; i++) {
        _observationCount -= _frameObservationCounts[i];
      }
      _frameObservationCounts.removeRange(0, removeCount);
    }
    return true;
  }
}

int? _intFromObject(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _doubleFromObject(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

enum NiedHypWritebackPolicy {
  historicalMinimumMultiplier,
  nonIncreasingCurrent,
}

enum NiedHypSearchSchedule {
  scratchViewerFiveStage,
  referenceBroadFourStage,
  scratchFiveStageWithBroadRescue,
  scratchFiveStageJointNeighborhood,
}

class NiedDartHypSourceEstimator
    implements SourceEstimator, SourceEstimatorLifecycleOwner {
  static const int stableHypocenterUpdateThreshold = 15;
  static const double _stableHypocenterEpsilon = 1e-9;

  NiedDartHypSourceEstimator({
    this.maxCachedEvents = 8,
    this.bboxPaddingDeg = 0.60,
    this.writebackPolicy = NiedHypWritebackPolicy.historicalMinimumMultiplier,
    this.historicalMinimumMultiplier = 1.7,
    this.searchSchedule = NiedHypSearchSchedule.scratchViewerFiveStage,
  }) : assert(historicalMinimumMultiplier > 0);
  final int maxCachedEvents;
  final double bboxPaddingDeg;
  final NiedHypWritebackPolicy writebackPolicy;
  final double historicalMinimumMultiplier;
  final NiedHypSearchSchedule searchSchedule;
  final Expando<_NiedHypWorkerFrame> _workerFrameByRequest =
      Expando<_NiedHypWorkerFrame>('nied_dart_hyp_worker_frame');
  final Map<String, _NiedHypEventState> _states =
      <String, _NiedHypEventState>{};

  @override
  String get methodId => 'nied_dart_hyp_v1';

  @override
  bool get requiresEveryFrame => true;

  @override
  bool get ownsOutputLifecycle => true;

  @override
  bool supports(SourceEstimationRequest request) {
    final workerFrame = _cachedNiedHypWorkerFrame(request);
    if (workerFrame == null) return false;
    final state = _states[_stateKey(request)];
    if (state != null && state.hasLifecycleState) return true;
    // KA invokes FindNiedHypocenter for every non-empty active-station frame.
    // The five-station condition belongs to the cluster's publishable-result
    // check, not to the estimator dispatch gate. Keeping this gate open lets
    // the reference cluster retain its early stations until later arrivals.
    return workerFrame.activeStations.isNotEmpty;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final workerFrame = _cachedNiedHypWorkerFrame(request);
    if (workerFrame == null) return null;
    request.metadata
      ..['source_estimator_owns_output_lifecycle'] = true
      ..remove('nied_dart_hyp_clear_published_source')
      ..remove('nied_dart_hyp_source_clear_reason');
    final eventState = _stateFor(request);
    var effectiveFrames = eventState.mergeFrame(
      workerFrame,
      observedAt: request.observedAt,
      scratchRuntimeTimerSeconds: _doubleFromObject(
        request.metadata['kotoho7_scratch_runtime_timer_s'],
      ),
      referenceAligned:
          searchSchedule == NiedHypSearchSchedule.referenceBroadFourStage,
    );
    eventState.magnitudeIntensityState.updateFrame(<String, double?>{
      for (final station in workerFrame.activeStations)
        station.code: station.currentShindo,
    }, observedAt: request.observedAt);
    request.metadata
      ..['nied_dart_hyp_assignment_accepted'] = Map<String, String>.from(
        eventState.lastAssignmentAcceptedByCode,
      )
      ..['nied_dart_hyp_assignment_rejected'] = Map<String, String>.from(
        eventState.lastAssignmentRejectedByCode,
      )
      ..['nied_dart_hyp_station_detection_ids'] =
          eventState.stationDetectionIds;

    final estimatesById = <int, SourceEstimate>{};
    final metadataById = <int, Map<String, Object?>>{};
    final referenceAligned =
        searchSchedule == NiedHypSearchSchedule.referenceBroadFourStage;
    void evaluateFrames(Map<int, _NiedHypWorkerFrame> frames) {
      for (final entry in frames.entries) {
        final detectionState = eventState.detectionIds[entry.key];
        if (detectionState == null || !detectionState.active) continue;
        if (referenceAligned &&
            detectionState.referenceEvaluated &&
            !detectionState.referenceDirty) {
          final cached = detectionState.worker.previousEstimate;
          if (cached != null) estimatesById[entry.key] = cached;
          continue;
        }
        final childMetadata = Map<String, Object?>.from(request.metadata);
        final childRequest = SourceEstimationRequest(
          sourceId: request.sourceId,
          eventId: '${request.eventId}:detection:${entry.key}',
          observedAt: request.observedAt,
          stageName: request.stageName,
          maxShindo: request.maxShindo,
          stations: request.stations,
          metadata: childMetadata,
          sensorSelection: request.sensorSelection,
        );
        final estimate = _estimateNiedHypWorkerFrame(
          childRequest,
          entry.value,
          detectionState.worker,
          firstStationCode: detectionState.firstStationCode,
          detectionCreatedAt: detectionState.createdAt,
          methodId: methodId,
          writebackPolicy: writebackPolicy,
          historicalMinimumMultiplier: historicalMinimumMultiplier,
          searchSchedule: searchSchedule,
        );
        if (referenceAligned) {
          detectionState.refreshPublishedHypocenterState(
            estimate,
            stableThreshold: stableHypocenterUpdateThreshold,
            epsilon: _stableHypocenterEpsilon,
          );
        }
        metadataById[entry.key] = childMetadata;
        if (estimate != null) estimatesById[entry.key] = estimate;
        if (referenceAligned) {
          detectionState
            ..referenceEvaluated = true
            ..referenceDirty = false;
        }
      }
    }

    evaluateFrames(effectiveFrames);
    if (searchSchedule == NiedHypSearchSchedule.referenceBroadFourStage) {
      while (eventState.mergeReferenceCloseClusters(
        observedAt: request.observedAt,
      )) {
        estimatesById.clear();
        metadataById.clear();
        effectiveFrames = eventState._referenceWorkerFrames(workerFrame);
        evaluateFrames(effectiveFrames);
      }
    } else {
      eventState.mergeSameSourceDetectionIds(observedAt: request.observedAt);
    }
    final selectedId = eventState.selectOutputDetectionId(
      currentActiveCodes: {
        for (final station in workerFrame.activeStations) station.code,
      },
      estimatedIds: estimatesById.keys.toSet(),
    );
    final idDiagnostics = eventState.diagnostics(
      estimatesById: estimatesById,
      selectedId: selectedId,
      observedAt: request.observedAt,
    );
    request.metadata
      ..['nied_dart_hyp_detection_ids'] = idDiagnostics
      ..['nied_dart_hyp_sources'] = eventState.sourceSnapshots(
        estimatesById: estimatesById,
        selectedId: selectedId,
      );
    final hasActiveDetectionId = eventState.hasActiveDetectionId;
    request.metadata['nied_dart_hyp_has_active_detection_id'] =
        hasActiveDetectionId;
    if (selectedId == null) {
      final clearReason =
          eventState.lastSourceClearReason ??
          (hasActiveDetectionId
              ? 'scratch_active_detection_id_has_no_published_source'
              : 'scratch_no_active_detection_id');
      request.metadata
        ..['nied_dart_hyp_clear_published_source'] = true
        ..['nied_dart_hyp_source_clear_reason'] = clearReason;
      return null;
    }
    final selected = estimatesById[selectedId];
    if (selected == null) {
      request.metadata
        ..['nied_dart_hyp_clear_published_source'] = true
        ..['nied_dart_hyp_source_clear_reason'] =
            'scratch_selected_detection_id_has_no_published_source';
      return null;
    }
    final selectedMetadata = metadataById[selectedId];
    if (selectedMetadata != null) {
      for (final key in const <String>[
        'nied_dart_hyp_worker_input',
        'nied_dart_hyp_worker_active_count',
        'nied_dart_hyp_worker_effective_active_count',
        'nied_dart_hyp_worker_zero_contribution_count',
        'nied_dart_hyp_worker_inactive_count',
        'nied_dart_hyp_worker_reused',
        'nied_dart_hyp_worker_null_reason',
      ]) {
        if (selectedMetadata.containsKey(key)) {
          request.metadata[key] = selectedMetadata[key];
        } else {
          request.metadata.remove(key);
        }
      }
    }
    final selectedState = eventState.detectionIds[selectedId]!;
    final activeDetectionCount = eventState.activeDetectionCount;
    final multipleSources = activeDetectionCount > 1;
    final magnitudeStationCodes = multipleSources
        ? selectedState.worker.activeStationsByCode.keys
        : workerFrame.activeStations.map((station) => station.code);
    final magnitudeInputIntensity = eventState.magnitudeIntensityState
        .maximumFor(magnitudeStationCodes);
    SrevKaizouMagnitudeResult? calculateCurrentSrevMagnitude() =>
        magnitudeInputIntensity == null
        ? null
        : calculateSrevKaizouMagnitude(
            sourceLatitude: selected.latitude,
            sourceLongitude: selected.longitude,
            inputIntensity: magnitudeInputIntensity,
            multipleSources: multipleSources,
          );
    final srevMagnitudeResult = referenceAligned
        ? selectedState.srevMagnitudePublicationState.update(
            reportNumber: selectedState.referenceReportNum,
            stable: selectedState.referenceStable,
            calculate: calculateCurrentSrevMagnitude,
          )
        : calculateCurrentSrevMagnitude();
    final srevMagnitudeDiagnostics =
        srevMagnitudeResult?.toDiagnostics() ??
        <String, Object?>{
          'srev_kaizou_magnitude_model': srevKaizouMagnitudeModelId,
          'srev_kaizou_magnitude_source_revision':
              srevKaizouMagnitudeSourceRevision,
          'srev_kaizou_magnitude_source_project_sha256':
              srevKaizouMagnitudeSourceProjectSha256,
          'srev_kaizou_magnitude_supported': false,
          'srev_kaizou_magnitude_unavailable_reason':
              magnitudeInputIntensity == null
              ? 'no_current_or_held_detection_intensity'
              : 'invalid_source_or_station_distance',
          'srev_kaizou_magnitude_branch': multipleSources
              ? 'multiple_sources_detection_max'
              : 'single_source_global_max',
        };
    srevMagnitudeDiagnostics['srev_kaizou_magnitude_active_detection_count'] =
        activeDetectionCount;
    if (referenceAligned) {
      srevMagnitudeDiagnostics.addAll(
        selectedState.srevMagnitudePublicationState.toDiagnostics(),
      );
    }
    final pgvMagnitudeDiagnostics = niedGifPgvMagnitudeDiagnostics(
      stations: request.stations,
      sourceLatitude: selected.latitude,
      sourceLongitude: selected.longitude,
      depthKm: selected.depthKm,
      sourceTriggerMemberIds: _sourceTriggerMemberIdsForMagnitude(
        request.metadata,
      ),
    );
    final jmaStyleMagnitudeDiagnostics =
        niedGifJmaStyleIntensityMagnitudeDiagnostics(
          stations: request.stations,
          sourceLatitude: selected.latitude,
          sourceLongitude: selected.longitude,
          depthKm: selected.depthKm,
          sourceTriggerMemberIds: _sourceTriggerMemberIdsForMagnitude(
            request.metadata,
          ),
        );
    final distanceWeightedPgvMagnitudeDiagnostics =
        niedGifPgvDistanceWeightedMagnitudeDiagnostics(
          stations: request.stations,
          sourceLatitude: selected.latitude,
          sourceLongitude: selected.longitude,
          depthKm: selected.depthKm,
          sourceTriggerMemberIds: _sourceTriggerMemberIdsForMagnitude(
            request.metadata,
          ),
        );
    final realtimeMagnitudeDiagnostics = <String, Object?>{
      ...pgvMagnitudeDiagnostics,
      ...jmaStyleMagnitudeDiagnostics,
      ...distanceWeightedPgvMagnitudeDiagnostics,
      ...srevMagnitudeDiagnostics,
    };
    final referencePublishedStateDiagnostics = <String, Object?>{
      if (referenceAligned) ...{
        'nied_dart_hyp_report_num': selectedState.referenceReportNum,
        'nied_dart_hyp_stable': selectedState.referenceStable,
        'nied_dart_hyp_stable_update_count':
            selectedState.referenceStableHypocenterUpdateCount,
        'nied_dart_hyp_stable_update_threshold':
            stableHypocenterUpdateThreshold,
        'nied_dart_hyp_calculation_complete': true,
        'nied_dart_hyp_calculation_state': 'complete',
      },
    };
    final realtimeOutputDiagnostics = <String, Object?>{
      ...realtimeMagnitudeDiagnostics,
      ...referencePublishedStateDiagnostics,
    };
    if (identical(selectedState.lastOutputBaseEstimate, selected) &&
        selectedState.lastOutputEstimate != null &&
        _sameNiedRealtimeMagnitudeDiagnostics(
          selectedState.lastOutputEstimate!.diagnostics,
          realtimeOutputDiagnostics,
        )) {
      return selectedState.lastOutputEstimate;
    }
    final output = SourceEstimate(
      latitude: selected.latitude,
      longitude: selected.longitude,
      depthKm: selected.depthKm,
      magnitude: srevMagnitudeResult?.magnitude,
      originTime: selected.originTime,
      confidence: selected.confidence,
      method: selected.method,
      supportingStationCount: selected.supportingStationCount,
      diagnostics: {
        ...selected.diagnostics,
        ...realtimeOutputDiagnostics,
        'detection_id_model':
            'scratch_id3_id4_assignment_with_ka_detection_grid_v1',
        'selected_detection_id': selectedId,
        'nied_dart_hyp_selected': true,
        'detection_ids': idDiagnostics,
        'detection_id_active': selectedState.active,
        'detection_id_expire_at': selectedState.expireAt.toIso8601String(),
        'source_visible': true,
        'source_clear_reason': null,
      },
    );
    selectedState
      ..lastOutputBaseEstimate = selected
      ..lastOutputEstimate = output;
    return output;
  }

  String _stateKey(SourceEstimationRequest request) {
    return '${request.sourceId}:${request.eventId}';
  }

  _NiedHypEventState _stateFor(SourceEstimationRequest request) {
    final key = _stateKey(request);
    final existing = _states[key];
    if (existing != null) return existing;
    if (_states.length >= maxCachedEvents && _states.isNotEmpty) {
      _states.remove(_states.keys.first);
    }
    final state = _NiedHypEventState();
    _states[key] = state;
    return state;
  }

  _NiedHypWorkerFrame? _cachedNiedHypWorkerFrame(
    SourceEstimationRequest request,
  ) {
    final cached = _workerFrameByRequest[request];
    if (cached != null) return cached;
    final parsed = _niedHypWorkerFrame(request);
    if (parsed != null) _workerFrameByRequest[request] = parsed;
    return parsed;
  }
}

bool _sameNiedRealtimeMagnitudeDiagnostics(
  Map<String, Object?> previous,
  Map<String, Object?> current,
) {
  for (final entry in current.entries) {
    if (previous[entry.key] != entry.value) return false;
  }
  return true;
}

Set<String> _sourceTriggerMemberIdsForMagnitude(Map<String, Object?> metadata) {
  final raw = metadata['source_trigger_member_ids'];
  return raw is Iterable ? raw.whereType<String>().toSet() : const <String>{};
}

class Kotoho7ReferenceHypSourceEstimator implements SourceEstimator {
  final int maxCachedEvents;
  final double bboxPaddingDeg;

  Kotoho7ReferenceHypSourceEstimator({
    this.maxCachedEvents = 8,
    this.bboxPaddingDeg = 0.60,
  });

  final Map<String, _Kotoho7HypState> _states = <String, _Kotoho7HypState>{};
  final Map<String, int> _scratchDetectionPermissionState = <String, int>{};
  final Map<String, DateTime> _scratchDetectionTriggerAt = <String, DateTime>{};
  final Map<String, String> _scratchDetectionPermissionReason =
      <String, String>{};
  final Map<String, double> _scratchDetectionAccelerationScore =
      <String, double>{};
  final Map<String, int> _scratchDetectionAccelerationTimeAreaCount =
      <String, int>{};
  final Map<String, String> _scratchDetectionAccelerationReason =
      <String, String>{};
  final Map<String, double> _scratchDetectionPermittedShindo =
      <String, double>{};
  final Map<String, double> _scratchStationMaxShindoValue = <String, double>{};
  final Map<String, DateTime> _scratchStationMaxShindoUpdatedAt =
      <String, DateTime>{};
  final Map<int, double> _scratchGridDetectionMax = <int, double>{};
  final Map<int, double> _scratchGridDetectionMaxKeep = <int, double>{};
  final Map<int, _Kotoho7GridCarrierEntry> _scratchGridByNumber =
      <int, _Kotoho7GridCarrierEntry>{};
  int _nextScratch43Serial = 1;

  @override
  String get methodId => 'nied_gif_hyp_kotoho7_reference_replay_v1';

  bool _isGifRequest(SourceEstimationRequest request) {
    return request.metadata['nied_input_kind'] == 'gif';
  }

  double _kotoho7ScratchRuntimeTimerSeconds(SourceEstimationRequest request) {
    final value = request.metadata['kotoho7_scratch_runtime_timer_s'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? double.infinity;
    return double.infinity;
  }

  @override
  bool supports(SourceEstimationRequest request) =>
      _isGifRequest(request) &&
      _usableTimingRecords(request, requireActiveLike: false).length >= 3;

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    if (!_isGifRequest(request)) return null;
    final currentDetectionActive = _usableTimingRecords(request);
    final currentDetectionCandidates = _usableTimingRecords(
      request,
      requireActiveLike: false,
    );
    final currentDetectionCandidatePool = _usableTimingRecords(
      request,
      requireActiveLike: false,
      maxRecords: null,
    );
    final allTimingUsable = _usableTimingRecords(
      request,
      requireAssociation: false,
      requireActiveLike: false,
      maxRecords: null,
    );
    final requestedAssignmentCandidateMode =
        request.metadata['kotoho7_assignment_candidate_mode'];
    final assignmentCandidateMode =
        requestedAssignmentCandidateMode == 'uncapped' ||
            requestedAssignmentCandidateMode == 'uncapped_id2_gate'
        ? requestedAssignmentCandidateMode as String
        : 'scratch_full_point_id2_gate';
    final currentKey = '${request.sourceId}:${request.eventId}';
    final existingState = _states[currentKey];
    if (currentDetectionCandidates.length < 3 &&
        existingState == null &&
        allTimingUsable.length < 3) {
      request.metadata['kotoho7_null_reason'] =
          'scratch_full_point_candidates_below_3';
      request.metadata['kotoho7_current_detection_candidate_count'] =
          currentDetectionCandidates.length;
      request.metadata['kotoho7_full_point_candidate_count'] =
          allTimingUsable.length;
      return null;
    }
    final seedUsable = currentDetectionActive.length >= 3
        ? currentDetectionActive
        : currentDetectionCandidates.length >= 3
        ? currentDetectionCandidates
        : existingState == null
        ? allTimingUsable
        : _assignedTimingRecords(existingState, allTimingUsable);
    if (seedUsable.isEmpty) {
      request.metadata['kotoho7_null_reason'] =
          'scratch_full_point_seed_candidates_empty';
      request.metadata['kotoho7_full_point_candidate_count'] =
          allTimingUsable.length;
      return null;
    }
    final sourceMemberIds = _sourceMemberIds(request);
    final associatedRecordCount = request.stations
        .where((record) => sourceMemberIds.contains(record.descriptor.code))
        .length;
    final associatedWithoutTimingCount = request.stations
        .where(
          (record) =>
              sourceMemberIds.contains(record.descriptor.code) &&
              (record.firstTriggerAt ?? record.firstRiseAt) == null,
        )
        .length;

    final state = _stateFor(
      request,
      seedUsable,
      earliestObserved: _earliestObserved(seedUsable),
      observedAt: request.observedAt,
    );
    _updateKotoho7DetectionPermissionCache(
      state,
      request.stations,
      observedAt: request.observedAt,
      requestMetadata: request.metadata,
    );
    _rebuildKotoho7GridCarrierFromAssignedStates(
      request.stations,
      observedAt: request.observedAt,
    );
    _mergeSameSourceStates(state, request, allTimingUsable: allTimingUsable);
    final entryPipelineDiagnostics = _kotoho7EntryPipelineDiagnostics(
      state,
      currentDetectionCandidates,
      uncappedCandidatePool: currentDetectionCandidatePool,
      observedAt: request.observedAt,
    );
    final assignmentCandidates = switch (assignmentCandidateMode) {
      'uncapped' => currentDetectionCandidatePool,
      'uncapped_id2_gate' => _kotoho7Id2GatedAssignmentCandidates(
        state,
        currentDetectionCandidatePool,
        observedAt: request.observedAt,
      ),
      _ => _kotoho7Id2GatedAssignmentCandidates(
        state,
        allTimingUsable,
        observedAt: request.observedAt,
      ),
    };
    _updateAssignedStationCodes(
      state,
      assignmentCandidates,
      allTimingUsable: allTimingUsable,
      observedAt: request.observedAt,
      scratchRuntimeTimerSeconds: _kotoho7ScratchRuntimeTimerSeconds(request),
    );
    _rebuildKotoho7GridCarrierFromAssignedStates(
      request.stations,
      observedAt: request.observedAt,
    );
    _updateScratch43ActiveState(
      state,
      allTimingUsable: allTimingUsable,
      observedAt: request.observedAt,
    );
    if (!state.scratch43Active) {
      request.metadata['kotoho7_null_reason'] =
          'scratch_4_3_detection_id_inactive';
      request.metadata['kotoho7_assigned_station_count'] =
          state.assignedStationCodes.length;
      return null;
    }
    final usable = _assignedTimingRecords(state, allTimingUsable);
    if (usable.length < 3) {
      request.metadata['kotoho7_null_reason'] = 'assigned_timing_below_3';
      request.metadata['kotoho7_assigned_timing_count'] = usable.length;
      request.metadata['kotoho7_assigned_station_count'] =
          state.assignedStationCodes.length;
      return null;
    }

    final bounds = _kotoho7SearchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final unarrived = _kotoho7UnarrivedRecords(request, usable);
    final candidateConstraints = _kotoho7CandidateConstraints(
      _kotoho7SortedTimingRecords(usable),
    );

    final stages = <Map<String, Object?>>[];
    final elapsedSinceFirstDetectionSeconds =
        request.observedAt.difference(state.earliestObserved).inMilliseconds /
        1000.0;
    final psCacheRefreshMode =
        request.metadata['kotoho7_ps_cache_refresh_mode'] ==
            'member_wide_bridge'
        ? 'member_wide_bridge'
        : 'assignment_only';
    final observedTimeMode =
        request.metadata['kotoho7_observed_time_mode'] == 'scratch_ten_plus_1'
        ? 'scratch_ten_plus_1'
        : 'record_first_trigger_or_rise';
    final scratch44HadReusableSource = state.sourceCache.score.isFinite;
    String scratch44SeedMode;
    if (!scratch44HadReusableSource) {
      scratch44SeedMode = 'scratch_4_4_slot_plus_2_empty';
    } else if (elapsedSinceFirstDetectionSeconds < 10.0) {
      scratch44SeedMode = 'scratch_age_lt_10_reseed_first_station';
    } else {
      scratch44SeedMode = 'scratch_4_4_reuse_previous_source';
    }
    if (!scratch44HadReusableSource ||
        elapsedSinceFirstDetectionSeconds < 10.0) {
      state.sourceCache = _scoreKotoho7HypCandidate(
        usable,
        unarrived,
        earliestObserved: state.earliestObserved,
        observedAt: request.observedAt,
        latitude: state.initialLatitude,
        longitude: state.initialLongitude,
        depthKm: 10.0,
        originSeedSeconds: -2.0,
        stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
            ? state.scratchStationFirstUseAt
            : null,
      );
    }
    if (psCacheRefreshMode == 'member_wide_bridge') {
      _refreshKotoho7StationPsCache(state, allTimingUsable: allTimingUsable);
    }
    final phaseReference = state.sourceCache;
    var best = _scoreKotoho7HypCandidate(
      usable,
      unarrived,
      earliestObserved: state.earliestObserved,
      observedAt: request.observedAt,
      latitude: state.sourceCache.latitude,
      longitude: state.sourceCache.longitude,
      depthKm: state.sourceCache.depthKm,
      originSeedSeconds: state.sourceCache.originOffsetSeconds,
      phaseReferenceLatitude: phaseReference.latitude,
      phaseReferenceLongitude: phaseReference.longitude,
      phaseReferenceDepthKm: phaseReference.depthKm,
      phaseReferenceOriginOffsetSeconds: phaseReference.originOffsetSeconds,
      stationSFlagByCode: state.scratchStationSFlag,
      stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
          ? state.scratchStationFirstUseAt
          : null,
    );
    final earlyLowCountPenalty =
        elapsedSinceFirstDetectionSeconds < 5.0 && usable.length < 10;
    final earlyHighCountPenalty =
        elapsedSinceFirstDetectionSeconds < 5.0 && usable.length >= 10;
    final h2MaxIterations = earlyLowCountPenalty
        ? 1
        : earlyHighCountPenalty
        ? 15
        : 30;
    final h10MaxIterations = earlyLowCountPenalty
        ? 6
        : earlyHighCountPenalty
        ? 40
        : 80;

    if (usable.length > 10) {
      best = _kotoho7LocalSearchStage(
        usable,
        unarrived,
        earliestObserved: state.earliestObserved,
        observedAt: request.observedAt,
        searchBounds: bounds,
        currentBest: best,
        phaseReference: phaseReference,
        horizontalStepDeg: 0.5,
        depthStepKm: null,
        stageName: 'start-h2',
        stages: stages,
        maxIterations: h2MaxIterations,
        stationSFlagByCode: state.scratchStationSFlag,
        stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
            ? state.scratchStationFirstUseAt
            : null,
      );
    } else {
      stages.add({
        'stage': 'start-h2',
        'horizontal_step_deg': 0.5,
        'depth_step_km': null,
        'max_iterations': h2MaxIterations,
        'iterations': 0,
        'moved': false,
        'skipped': true,
        'skip_reason': 'scratch_requires_4_3_plus_4_gt_10',
        'best_latitude': best.latitude,
        'best_longitude': best.longitude,
        'best_depth_km': best.depthKm,
        'best_origin_offset_s': best.originOffsetSeconds,
        'best_score': best.score,
      });
    }
    best = _kotoho7LocalSearchStage(
      usable,
      unarrived,
      earliestObserved: state.earliestObserved,
      observedAt: request.observedAt,
      searchBounds: bounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 0.1,
      depthStepKm: null,
      stageName: 'start-h10',
      stages: stages,
      maxIterations: h10MaxIterations,
      stationSFlagByCode: state.scratchStationSFlag,
      stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
          ? state.scratchStationFirstUseAt
          : null,
    );
    best = _kotoho7LocalSearchStage(
      usable,
      unarrived,
      earliestObserved: state.earliestObserved,
      observedAt: request.observedAt,
      searchBounds: bounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 0.1,
      depthStepKm: 50.0,
      stageName: 'start-h10-v50',
      stages: stages,
      maxIterations: 100,
      stationSFlagByCode: state.scratchStationSFlag,
      stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
          ? state.scratchStationFirstUseAt
          : null,
    );
    best = _kotoho7LocalSearchStage(
      usable,
      unarrived,
      earliestObserved: state.earliestObserved,
      observedAt: request.observedAt,
      searchBounds: bounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 0.1,
      depthStepKm: 10.0,
      stageName: 'start-h10-v10',
      stages: stages,
      maxIterations: 100,
      stationSFlagByCode: state.scratchStationSFlag,
      stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
          ? state.scratchStationFirstUseAt
          : null,
    );
    best = _kotoho7LocalSearchStage(
      usable,
      unarrived,
      earliestObserved: state.earliestObserved,
      observedAt: request.observedAt,
      searchBounds: bounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 1.0 / 60.0,
      depthStepKm: null,
      stageName: 'start-h60',
      stages: stages,
      maxIterations: 10,
      stationSFlagByCode: state.scratchStationSFlag,
      stationObservedAtByCode: observedTimeMode == 'scratch_ten_plus_1'
          ? state.scratchStationFirstUseAt
          : null,
    );
    if (!best.score.isFinite) {
      request.metadata['kotoho7_null_reason'] = 'no_finite_best_candidate';
      request.metadata['kotoho7_assigned_timing_count'] = usable.length;
      request.metadata['kotoho7_best_score'] = best.score;
      return null;
    }

    final sourceUpdateAccepted =
        best.score < state.scratch43BestRawScore * 1.7 ||
        elapsedSinceFirstDetectionSeconds < 10.0;
    final scratch44CandidateBest = _kotoho7Scratch44QuantizedCandidate(best);
    if (sourceUpdateAccepted) {
      state
        ..sourceCache = scratch44CandidateBest
        ..scratch43LastSourceCacheUpdatedAt = request.observedAt;
      best = state.sourceCache;
    } else if (state.sourceCache.score.isFinite) {
      best = state.sourceCache;
    }
    state
      ..lastUpdatedAt = request.observedAt
      ..revision += 1;
    if (sourceUpdateAccepted && psCacheRefreshMode == 'member_wide_bridge') {
      _refreshKotoho7StationPsCache(state, allTimingUsable: allTimingUsable);
    }
    _refreshScratch43Metadata(
      state,
      allTimingUsable: allTimingUsable,
      best: scratch44CandidateBest,
      observedAt: request.observedAt,
      updateBestScore: sourceUpdateAccepted,
    );
    request.metadata
      ..remove('kotoho7_null_reason')
      ..remove('kotoho7_current_detection_candidate_count')
      ..remove('kotoho7_assigned_timing_count')
      ..remove('kotoho7_assigned_station_count')
      ..remove('kotoho7_best_score')
      ..['kotoho7_source_update_accepted'] = sourceUpdateAccepted;

    final phaseSupportCount = best.phasePCount + best.phaseSCount;
    final supported =
        phaseSupportCount >= 3 && best.phaseMeanResidualSeconds <= 2.8;
    final depthSupported = supported && best.depthKm > 10.0;
    final pOnlySupported = supported && best.phaseSCount == 0;
    final residualFit = best.phaseMeanResidualSeconds.isFinite
        ? 1.0 / (1.0 + best.phaseMeanResidualSeconds)
        : 0.0;
    final confidence =
        (0.12 +
                (supported ? 0.24 : 0.0) +
                (depthSupported ? 0.08 : 0.0) +
                residualFit * 0.24 +
                math.min(0.18, phaseSupportCount * 0.015))
            .clamp(0.0, 0.92);
    final originTime = state.earliestObserved.add(
      Duration(milliseconds: (best.originOffsetSeconds * 1000).round()),
    );
    final magnitudeDiagnostics = _niedGifMagnitudeDiagnostics(
      usable,
      sourceLatitude: best.latitude,
      sourceLongitude: best.longitude,
      depthKm: best.depthKm,
      depthSource: 'kotoho7_reference_hyp_supported',
    );
    final diagnosticMagnitude = _supportedDiagnosticMagnitude(
      magnitudeDiagnostics,
    );
    final gridScanProxy = _kotoho7GridScanProxyDiagnostics(
      request,
      state,
      best,
      assignedTimingRecords: usable,
      unarrivedRecords: unarrived,
      observedAt: request.observedAt,
    );
    final gridScanScoreComparison = gridScanProxy.detectedRecords.length < 3
        ? <String, Object?>{
            'model':
                'scratch_grid_scan_deterministic_proxy_score_comparison_v1',
            'status': 'insufficient_detected_records',
            'detected_count': gridScanProxy.detectedRecords.length,
            'unarrived_count': gridScanProxy.unarrivedRecords.length,
          }
        : _kotoho7GridScanScoreComparison(
            gridScanProxy.detectedRecords,
            gridScanProxy.unarrivedRecords,
            best,
            earliestObserved: state.earliestObserved,
            observedAt: request.observedAt,
            phaseReference: phaseReference,
            stationSFlagByCode: state.scratchStationSFlag,
          );
    final gridScanSearchComparison = gridScanProxy.detectedRecords.length < 3
        ? <String, Object?>{
            'model':
                'scratch_grid_scan_deterministic_proxy_search_comparison_v1',
            'status': 'insufficient_detected_records',
            'detected_count': gridScanProxy.detectedRecords.length,
            'unarrived_count': gridScanProxy.unarrivedRecords.length,
          }
        : _kotoho7GridScanSearchComparison(
            request,
            state,
            best,
            assignedTimingRecords: usable,
            unarrivedRecords: unarrived,
            earliestObserved: state.earliestObserved,
            observedAt: request.observedAt,
            searchBounds: bounds,
            phaseReference: phaseReference,
            stationSFlagByCode: state.scratchStationSFlag,
            enableH2: usable.length > 10,
            h2MaxIterations: h2MaxIterations,
            h10MaxIterations: h10MaxIterations,
          );
    final fullPointId2TimingGapAudit = _kotoho7FullPointId2TimingGapAudit(
      state,
      request,
      observedAt: request.observedAt,
    );
    final sourceTriggerMemberGapAudit = _kotoho7SourceTriggerMemberGapAudit(
      state,
      request,
      observedAt: request.observedAt,
    );

    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      depthKm: best.depthKm,
      magnitude: diagnosticMagnitude,
      originTime: originTime,
      confidence: confidence,
      method: methodId,
      supportingStationCount: best.weightedCount.round(),
      diagnostics: {
        'method': methodId,
        'reference_url': 'https://note.com/kotoho7/n/n59e423877b1b',
        'reference_title': '揺れ検知から震央を検出してみる',
        'reference_scope':
            'literal replay of kotoho7/Scratch-style source cache',
        'travel_time_model': 'jma2001_polynomial_from_jq_reference_js',
        'scoring_model': 'kotoho7_article_error_level_with_s_flag_proxy_v2',
        'supported': supported,
        'p_only_supported': pOnlySupported,
        'depth_supported': depthSupported,
        'latitude': best.latitude,
        'longitude': best.longitude,
        'depth_km': best.depthKm,
        ...magnitudeDiagnostics,
        'origin_time': originTime.toIso8601String(),
        'origin_offset_s': best.originOffsetSeconds,
        'score': best.score,
        'phase_score': best.phaseScore,
        'phase_mean_residual_s': best.phaseMeanResidualSeconds,
        'phase_residual_p90_s': best.phaseResidualP90Seconds,
        'phase_p_count': best.phasePCount,
        'phase_s_count': best.phaseSCount,
        'phase_other_count': best.phaseOtherCount,
        'unarrived_penalty': best.unarrivedPenalty,
        'unarrived_penalty_count': best.unarrivedPenaltyCount,
        'weighted_count': best.weightedCount,
        'scratch_error_level_components': {
          'model':
              'scratch_hyp_error_level_s_factor_weighted_variance_unarrived_v1',
          's_factor': best.scratchSFactor,
          's_flag_count': best.scratchSFlagCount,
          'weighted_residual_squares': best.scratchWeightedResidualSquares,
          'weight_sum': best.scratchWeightSum,
          'station_count_scale': best.scratchStationCountScale,
          'unarrived_gate_open': best.scratchUnarrivedGateOpen,
          'unarrived_input_count': best.scratchUnarrivedInputCount,
          'unarrived_within_radius_count':
              best.scratchUnarrivedWithinRadiusCount,
          'distance_from_first_detected_km':
              best.scratchDistanceFromFirstDetectedKm,
          'max_allowed_depth_km': best.scratchMaxAllowedDepthKm,
          'max_allowed_distance_km': best.scratchMaxAllowedDistanceKm,
          'reject_reason': best.scratchRejectReason,
          'grid_scan_proxy_diagnostics': gridScanProxy.diagnostics,
          'grid_scan_score_comparison': gridScanScoreComparison,
          'grid_scan_search_comparison': gridScanSearchComparison,
          'grid_scan_proxy':
              'deterministic_assigned_records_plus_unarrived_records; Scratch scans grid cells and uses random sampling for non-target points',
          'formula':
              'sFactor * ((weightedResidualSquares + unarrivedCount) / weightSum) * stationCountScale',
        },
        'candidate_constraints': {
          'model':
              'scratch_4_3_offset4_count_offset5_distance_proxy_from_current_usable_v1',
          'max_detected_distance_km':
              candidateConstraints.maxDetectedDistanceKm,
          'max_allowed_depth_km': candidateConstraints.maxAllowedDepthKm,
          'max_allowed_distance_km': candidateConstraints.maxAllowedDistanceKm,
        },
        'stateful_source_cache': {
          'event_id': request.eventId,
          'revision': state.revision,
          'first_station_code': state.firstStationCode,
          'assigned_station_count': state.assignedStationCodes.length,
          'assigned_station_codes': (state.assignedStationCodes.toList()
            ..sort()),
          'assigned_station_observed_times': {
            for (final record in usable)
              record.descriptor.code: {
                'scratch_ten_plus_1_at': state
                    .scratchStationFirstUseAt[record.descriptor.code]
                    ?.toIso8601String(),
                'first_trigger_at': record.firstTriggerAt?.toIso8601String(),
                'first_rise_at': record.firstRiseAt?.toIso8601String(),
                'observed_time_source': observedTimeMode == 'scratch_ten_plus_1'
                    ? 'scratch_ten_plus_1_at'
                    : record.firstTriggerAt != null
                    ? 'first_trigger_at'
                    : 'first_rise_at',
              },
          },
          'observed_time_mode': observedTimeMode,
          'source_keys': (state.sourceKeys.toList()..sort()),
          'source_selection_model': state.lastSourceSelectionModel,
          'source_selection_selected_key': state.lastSourceSelectionSelectedKey,
          'source_selection_candidate_count':
              state.lastSourceSelectionCandidateCount,
          'source_selection_fit_count': state.lastSourceSelectionFitCount,
          'source_selection_mean_residual_s':
              state.lastSourceSelectionMeanResidualSeconds,
          'same_source_merge_count': state.lastSameSourceMergeCount,
          'same_source_merge_keys': state.lastSameSourceMergeKeys,
          'same_source_merge_added_station_count':
              state.lastSameSourceMergeAddedStationCount,
          'scratch_4_4_source_cache': {
            'model': 'scratch_4_4_detection_id_source_elements_slots_2_to_5_v1',
            'slot_stride': 10,
            'slot_plus_2_longitude': best.longitude,
            'slot_plus_3_latitude': best.latitude,
            'slot_plus_4_depth_km': best.depthKm.round(),
            'slot_plus_5_origin_offset_s': best.originOffsetSeconds.round(),
            'seed_mode': scratch44SeedMode,
            'had_reusable_source_before_hyp': scratch44HadReusableSource,
            'age_lt_10_reseed_window_active':
                elapsedSinceFirstDetectionSeconds < 10.0,
            'initial_seed_longitude': state.initialLongitude,
            'initial_seed_latitude': state.initialLatitude,
            'initial_seed_depth_km': 10.0,
            'initial_seed_origin_offset_s': -2.0,
            'scratch_stage_h2_enabled': usable.length > 10,
            'scratch_h2_limit': h2MaxIterations,
            'scratch_h10_limit': h10MaxIterations,
            'scratch_v50_limit': 100,
            'scratch_v10_limit': 100,
            'scratch_h60_limit': 10,
          },
          'scratch_4_3_proxy': {
            'model':
                'dart_kotoho7_detection_id_metadata_proxy_v1_from_ten_plus_3',
            'serial': state.scratch43Serial,
            'created_by_mid_frame_new_id':
                state.scratch43CreatedByMidFrameNewId,
            'single_station_grace_until': state.scratch43SingleStationGraceUntil
                ?.toIso8601String(),
            'first_detection_at': state.scratch43FirstDetectionAt
                .toIso8601String(),
            'last_source_cache_updated_at': state
                .scratch43LastSourceCacheUpdatedAt
                ?.toIso8601String(),
            'last_detection_at': state.scratch43LastDetectionAt
                .toIso8601String(),
            'stale_age_ms': request.observedAt
                .difference(state.scratch43LastDetectionAt)
                .inMilliseconds,
            'assigned_count': state.scratch43AssignedCount,
            'active': state.scratch43Active,
            'inactive_reason': state.scratch43InactiveReason,
            'inactive_at': state.scratch43InactiveAt?.toIso8601String(),
            'expire_at': state.scratch43ExpireAt?.toIso8601String(),
            'expire_window_s': state.scratch43LastExpireWindowSeconds,
            'grid_presence_count': state.scratch43LastGridPresenceCount,
            'grid_presence_disappeared_age_s':
                state.scratch43LastGridPresenceDisappearedAgeSeconds,
            'slot_plus_6_current_max_shindo':
                state.scratch43LastMaxCurrentShindoIndex,
            'slot_plus_7_previous_max_shindo':
                state.scratch43PreviousMaxCurrentShindoIndex,
            'max_first_station_distance_km':
                state.scratch43MaxFirstStationDistanceKm,
            'max_source_distance_km': state.scratch43MaxSourceDistanceKm,
            'best_score': state.scratch43BestScore,
            'best_raw_score_plus_19': state.scratch43BestRawScore,
            'best_phase_mean_residual_s':
                state.scratch43BestPhaseMeanResidualSeconds,
            'best_source_keys': state.scratch43BestSourceKeys,
            'merge_metadata_model':
                'copy_earliest_latest_max_distance_min_score_v1',
          },
          'current_detection_active_station_count':
              currentDetectionActive.length,
          'current_detection_station_count': currentDetectionCandidates.length,
          'current_detection_uncapped_station_count':
              currentDetectionCandidatePool.length,
          'assignment_candidate_mode': assignmentCandidateMode,
          'assignment_candidate_count': assignmentCandidates.length,
          'station_record_count': request.stations.length,
          'associated_station_record_count': associatedRecordCount,
          'associated_without_timing_count': associatedWithoutTimingCount,
          'full_point_id2_timing_gap_audit': fullPointId2TimingGapAudit,
          'source_trigger_member_gap_audit': sourceTriggerMemberGapAudit,
          'detection_permission_cache': {
            'model':
                'scratch_global_ten_c_yure_detection_permission_cache_from_gif_history_v2',
            'source':
                'shared_global_station_cache_for_tandoku_trigger_and_fukusu_trigger_state',
            'state_counts': _kotoho7DetectionPermissionStateCounts(state),
            'last_promoted_count': state.lastDetectionPermissionPromotedCount,
            'last_demoted_count': state.lastDetectionPermissionDemotedCount,
            'last_refreshed_count': state.lastDetectionPermissionRefreshedCount,
            'last_reason_counts': state.lastDetectionPermissionReasonCounts,
            'sample': _kotoho7DetectionPermissionDiagnostics(
              state,
              observedAt: request.observedAt,
            ).take(16).toList(growable: false),
          },
          'last_assignment_added_count': state.lastAssignmentAddedCount,
          'last_assignment_rejected_count': state.lastAssignmentRejectedCount,
          'last_assignment_recovery_added_count':
              state.lastAssignmentRecoveryAddedCount,
          'last_assignment_rerise_refresh_count':
              state.lastAssignmentReriseRefreshCount,
          'last_assignment_mid_frame_new_id_count':
              state.lastAssignmentMidFrameNewIdCount,
          'last_assignment_removed_count': state.lastAssignmentRemovedCount,
          'last_assignment_reset_reason_counts':
              state.lastAssignmentResetReasonCounts,
          'last_assignment_negative_count_delta':
              state.lastAssignmentNegativeCountDelta,
          'last_assignment_reset_cleared_plus3_count':
              state.lastAssignmentResetClearedPlus3Count,
          'last_assignment_reset_cleared_ps_cache_count':
              state.lastAssignmentResetClearedPsCacheCount,
          'last_assignment_reset_cleared_distance_count':
              state.lastAssignmentResetClearedDistanceCount,
          'last_assignment_would_switch_other_id_count':
              state.lastAssignmentWouldSwitchOtherIdCount,
          'last_assignment_would_switch_other_id_source_counts':
              state.lastAssignmentWouldSwitchOtherIdSourceCounts,
          'last_assignment_would_switch_other_id_samples':
              state.lastAssignmentWouldSwitchOtherIdSamples,
          'last_assignment_added_station_codes':
              state.lastAssignmentAddedStationCodes,
          'last_assignment_rejected_station_codes':
              state.lastAssignmentRejectedStationCodes,
          'last_assignment_recovery_added_station_codes':
              state.lastAssignmentRecoveryAddedStationCodes,
          'last_assignment_rerise_refresh_station_codes':
              state.lastAssignmentReriseRefreshStationCodes,
          'last_assignment_mid_frame_new_id_station_codes':
              state.lastAssignmentMidFrameNewIdStationCodes,
          'last_assignment_removed_station_codes':
              state.lastAssignmentRemovedStationCodes,
          'assignment_model':
              'scratch_detection_id_4_grid_carrier_selection_v9',
          'station_assignment_selection': {
            'model':
                'scratch_detection_id4_order_current_grid_4_2_around_9_grid_guard_v3',
            'grid_model': 'grid_number_23_column_025deg_latlon_proxy_v2',
            'around_grid_guard_model':
                'scratch_surrounding_9_grid_max_shindo_or_rise_proxy_v1',
            'source_cache_gate_model':
                'scratch_exact_age_gt_5s_score_lt_500_and_source_present_v1',
            'first_point_fallback_gate_model':
                'scratch_exact_assigned_count_gt_4_v1',
            'timing_window_model':
                'scratch_exact_p_abs_le_5_plus_distance_over_120_else_s_between_p_minus_tol_and_s_plus_8_plus_distance_over_120_v1',
            'wide_distance_gate_model':
                'scratch_exact_distance_gt_900_and_age100_1p5_plus10_or_age15_1p4_plus5_v1',
            'entry_pipeline': entryPipelineDiagnostics,
            'added_source_counts': state.lastAssignmentAddedSourceCounts,
            'rejected_source_counts': state.lastAssignmentRejectedSourceCounts,
            'candidate_reason_counts':
                state.lastAssignmentCandidateReasonCounts,
            'added_sources_sample': state.lastAssignmentAddedSourceSamples,
            'accepted_same_id_reason_counts':
                state.lastAssignmentAcceptedSameIdReasonCounts,
            'accepted_same_id_samples':
                state.lastAssignmentAcceptedSameIdSamples,
            'grid_carrier_size': _scratchGridByNumber.length,
            'grid_presence_active_id_count':
                _kotoho7GridPresenceActiveIdCount(),
            'grid_presence_count_for_state': _kotoho7GridPresenceCountForState(
              state,
            ),
          },
          'station_lifecycle': {
            'model':
                'scratch_ten_plus_1_2_permission_state_5_6_from_gif_record_v1',
            'ten_estimated_slot_layout': {
              'stride': 10,
              'plus_1': 'scratch ten:推定用 slot +1; first/current use time',
              'plus_2': 'scratch ten:推定用 slot +2; last update time',
              'plus_3': 'scratch ten:推定用 slot +3; detection id',
              'plus_4': 'scratch ten:推定用 slot +4; distance from first station',
              'plus_5':
                  'scratch ten:推定用 slot +5; pending/latest cloud time candidate',
              'plus_6': 'scratch ten:推定用 slot +6; S flag',
              'plus_7': 'scratch ten:推定用 slot +7; predicted P arrival',
              'plus_8': 'scratch ten:推定用 slot +8; predicted S arrival',
            },
            'current_shindo_mapping':
                'NIED input is current-frame KA level -1..20 in rawLevel/detectLevel; value retains continuous shindo',
            'change_speed_mapping': 'lastAscend>0',
            'state_counts': _kotoho7StationPermissionStateCounts(state),
            'plus_5_pending_cloud_time_count':
                state.scratchStationPendingCloudAt.length,
            'estimated_slot_write_reason_counts':
                state.lastEstimatedSlotWriteReasonCounts,
            'estimated_slot_write_samples': state.lastEstimatedSlotWriteSamples,
            'max_ten_plus_2_age_s': _kotoho7MaxStationLastUpdateAgeSeconds(
              state,
              observedAt: request.observedAt,
            ),
            'sample': _kotoho7StationLifecycleDiagnostics(
              state,
              observedAt: request.observedAt,
            ).take(12).toList(growable: false),
          },
          'station_ps_cache': {
            'model': 'scratch_suiteitenten_ps_time_recompute_stateful_v1',
            'refresh_mode': psCacheRefreshMode,
            'scratch_reference_formula':
                '推定用tenPS時間計算: +7=origin+P走時, +8=origin+S走時, +6=abs(+1-+8)<abs(+1-+7)',
            'scratch_execution_order':
                'main frame runs 検出id1_全点へ適用 before broadcasting 推定震源計算/HYP',
            'production_refresh_semantics':
                psCacheRefreshMode == 'member_wide_bridge'
                ? 'explicit diagnostic bridge: refresh after HYP source-cache update so the next frame has member-wide +6/+7/+8; not the default Scratch path'
                : 'Scratch-default path: only station assignment/rerise registration calls 推定用tenPS時間計算; no member-wide refresh after HYP',
            'p_arrival_count': state.scratchStationPArrivalSeconds.length,
            's_arrival_count': state.scratchStationSArrivalSeconds.length,
            's_flag_count': state.scratchStationSFlag.values
                .where((flag) => flag)
                .length,
            's_flag_station_codes':
                state.scratchStationSFlag.entries
                    .where((entry) => entry.value)
                    .map((entry) => entry.key)
                    .toList(growable: false)
                  ..sort(),
            ..._kotoho7StationPsCacheMissingSummary(state),
            'last_assignment_immediate_ps_recompute_count':
                state.lastAssignmentImmediatePsRecomputeCount,
            'sample': _kotoho7StationPsCacheDiagnostics(state),
          },
          'station_ps_cache_shadow': _kotoho7ShadowStationPsCacheDiagnostics(
            state,
            usable: usable,
            unarrived: unarrived,
            observedAt: request.observedAt,
          ),
          'station_distance_cache': {
            'model':
                'scratch_ten_plus_4_first_station_distance_immediate_set_v1',
            'distance_count': state.scratchStationFirstDistanceKm.length,
            'max_first_station_distance_km':
                state.scratch43MaxFirstStationDistanceKm,
            'last_assignment_immediate_distance_update_count':
                state.lastAssignmentImmediateDistanceUpdateCount,
          },
          'initialized_at': state.initializedAt.toIso8601String(),
          'last_updated_at': state.lastUpdatedAt.toIso8601String(),
          'earliest_observed_at': state.earliestObserved.toIso8601String(),
          'early_reseed_window_active':
              elapsedSinceFirstDetectionSeconds < 10.0,
        },
        'initial_source_cache': {
          'latitude': state.initialLatitude,
          'longitude': state.initialLongitude,
          'depth_km': 10.0,
          'origin_offset_s': -2.0,
          'source': 'first_detected_station_rounded_0_01deg',
          'station_code': state.firstStationCode,
        },
        'search': {
          'type': 'kotoho7_literal_staged_neighbor_descent',
          'max_iterations_per_stage':
              'Scratch-derived dynamic: h2/h10 depend on early age/count; v50=100, v10=100, h60=10',
          'neighbor_set':
              'current, lon +/- step, lat +/- step, optional depth +/- step',
          'stages': stages,
          'bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        },
        'scoring_config': const {
          'origin_mean':
              'plain arithmetic mean of detected-station selected P/S origins',
          'origin_scatter':
              'scratch-style normalized weighted squared origin scatter',
          'station_weight':
              'first_detected_station_distance / station_distance, fixed to 1 within 50km',
          'phase_model':
              'P until 15s gate; after gate use S when cached ten:+6 is true',
          'station_s_flag_model':
              'scratch_stateful_ten_plus_6_from_cached_plus_7_plus_8_v3',
          'scratch_error_scale':
              'S-factor * ((weightedResidualSquares + unarrivedCount) / weightSum) * (30 + 20000/(1+n^2) + 2000/(50+n))',
          'unarrived_gate':
              'elapsed <= 3s or elapsed <= 10s with detectedCount < 30',
          'unarrived_penalty': '+1 per predicted-arrived undetected station',
        },
      },
    );
  }

  _Kotoho7HypState _stateFor(
    SourceEstimationRequest request,
    List<SeismicStationEventRecord> usable, {
    required DateTime earliestObserved,
    required DateTime observedAt,
  }) {
    final key = '${request.sourceId}:${request.eventId}';
    final current = _states[key];
    if (current != null &&
        !earliestObserved.isBefore(
          current.earliestObserved.subtract(const Duration(milliseconds: 500)),
        )) {
      current
        ..sourceKeys.add(key)
        ..lastSourceSelectionModel = 'current_key_existing_state'
        ..lastSourceSelectionSelectedKey = key
        ..lastSourceSelectionCandidateCount = 1
        ..lastSourceSelectionFitCount = usable.length
        ..lastSourceSelectionMeanResidualSeconds = 0;
      return current;
    }

    final selected = _selectExistingKotoho7SourceState(
      request,
      usable,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      currentKey: key,
    );
    if (selected != null) {
      selected.state
        ..sourceKeys.add(key)
        ..lastSourceSelectionModel =
            'scratch_detection_id_4_2_existing_source_cache_candidate_v1'
        ..lastSourceSelectionSelectedKey = selected.key
        ..lastSourceSelectionCandidateCount = selected.candidateCount
        ..lastSourceSelectionFitCount = selected.fitCount
        ..lastSourceSelectionMeanResidualSeconds = selected.meanResidualSeconds;
      _states[key] = selected.state;
      return selected.state;
    }

    final sortedUsable = [...usable]
      ..sort((left, right) {
        final leftAt = left.firstTriggerAt ?? left.firstRiseAt;
        final rightAt = right.firstTriggerAt ?? right.firstRiseAt;
        if (leftAt == null && rightAt == null) return 0;
        if (leftAt == null) return 1;
        if (rightAt == null) return -1;
        return leftAt.compareTo(rightAt);
      });
    final first = sortedUsable.first;
    final seedLatitude =
        (first.descriptor.coordinate.latitude * 100).round() / 100.0;
    final seedLongitude =
        (first.descriptor.coordinate.longitude * 100).round() / 100.0;
    final sourceCache = _scoreKotoho7HypCandidate(
      <SeismicStationEventRecord>[first],
      const <SeismicStationEventRecord>[],
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      latitude: seedLatitude,
      longitude: seedLongitude,
      depthKm: 10.0,
      originSeedSeconds: -2.0,
    );
    final next = _Kotoho7HypState(
      earliestObserved: earliestObserved,
      initializedAt: observedAt,
      lastUpdatedAt: observedAt,
      firstStationCode: first.descriptor.code,
      initialLatitude: seedLatitude,
      initialLongitude: seedLongitude,
      sourceCache: sourceCache,
      sourceKeys: <String>{key},
      scratch43Serial: _nextKotoho7Scratch43Serial(),
      assignedStationCodes: <String>{first.descriptor.code},
      scratchDetectionPermissionState: _scratchDetectionPermissionState,
      scratchDetectionTriggerAt: _scratchDetectionTriggerAt,
      scratchDetectionPermissionReason: _scratchDetectionPermissionReason,
      scratchDetectionAccelerationScore: _scratchDetectionAccelerationScore,
      scratchDetectionAccelerationTimeAreaCount:
          _scratchDetectionAccelerationTimeAreaCount,
      scratchDetectionAccelerationReason: _scratchDetectionAccelerationReason,
      scratchDetectionPermittedShindo: _scratchDetectionPermittedShindo,
      scratchStationMaxShindoValue: _scratchStationMaxShindoValue,
      scratchStationMaxShindoUpdatedAt: _scratchStationMaxShindoUpdatedAt,
      scratchGridDetectionMax: _scratchGridDetectionMax,
      scratchGridDetectionMaxKeep: _scratchGridDetectionMaxKeep,
    );
    next.scratch43FirstDetectionAt = observedAt;
    final initialRecordsByCode = <String, SeismicStationEventRecord>{
      first.descriptor.code: first,
    };
    _initializeKotoho7StationLifecycle(next, first, observedAt: observedAt);
    _refreshKotoho7StationPsCacheForRecord(next, first);
    _refreshKotoho7StationDistanceCacheForRecord(
      next,
      first,
      recordsByCode: initialRecordsByCode,
    );
    _setKotoho7GridCarrier(
      next,
      first,
      observedAt: observedAt,
      selectionSource: 'scratch_new_id_initial',
    );
    next
      ..lastSourceSelectionModel = 'new_source_cache_from_first_station'
      ..lastSourceSelectionSelectedKey = key
      ..lastSourceSelectionCandidateCount = 0
      ..lastSourceSelectionFitCount = 1
      ..lastSourceSelectionMeanResidualSeconds = 0;
    _states[key] = next;
    if (_states.length > maxCachedEvents) {
      final oldest = _states.entries.reduce((a, b) {
        return a.value.lastUpdatedAt.isBefore(b.value.lastUpdatedAt) ? a : b;
      }).key;
      _states.remove(oldest);
    }
    return next;
  }

  _Kotoho7SourceSelection? _selectExistingKotoho7SourceState(
    SourceEstimationRequest request,
    List<SeismicStationEventRecord> usable, {
    required DateTime earliestObserved,
    required DateTime observedAt,
    required String currentKey,
  }) {
    if (_states.isEmpty || usable.length < 3) return null;
    final sourceMemberIds = _sourceMemberIds(request);
    final uniqueStates = <_Kotoho7HypState, String>{};
    for (final entry in _states.entries) {
      if (entry.key == currentKey) continue;
      uniqueStates.putIfAbsent(entry.value, () => entry.key);
    }
    _Kotoho7SourceSelection? best;
    for (final entry in uniqueStates.entries) {
      final key = entry.value;
      final state = entry.key;
      if (!state.sourceCache.score.isFinite) continue;
      final ageSeconds =
          observedAt.difference(state.lastUpdatedAt).inMilliseconds / 1000.0;
      if (ageSeconds < -1.0 || ageSeconds > 120.0) continue;
      final firstTimeDeltaSeconds =
          earliestObserved
              .difference(state.earliestObserved)
              .inMilliseconds
              .abs() /
          1000.0;
      if (firstTimeDeltaSeconds > 45.0) continue;

      final fitResiduals = <double>[];
      var memberFitCount = 0;
      for (final record in usable) {
        final residual = _kotoho7SourceCachePhaseResidualSeconds(record, state);
        if (residual == null) continue;
        fitResiduals.add(residual);
        if (sourceMemberIds.contains(record.descriptor.code)) {
          memberFitCount += 1;
        }
      }
      if (fitResiduals.length < 3) continue;
      final requiredFitCount = math.max(3, (usable.length * 0.45).ceil());
      if (fitResiduals.length < requiredFitCount && memberFitCount < 3) {
        continue;
      }
      fitResiduals.sort();
      final meanResidual =
          fitResiduals.reduce((a, b) => a + b) / fitResiduals.length;
      final p90Residual =
          fitResiduals[math.min(
            fitResiduals.length - 1,
            (fitResiduals.length * 0.9).floor(),
          )];
      if (meanResidual > 6.0 || p90Residual > 10.0) continue;

      final selection = _Kotoho7SourceSelection(
        key: key,
        state: state,
        fitCount: fitResiduals.length,
        candidateCount: uniqueStates.length,
        meanResidualSeconds: meanResidual,
        p90ResidualSeconds: p90Residual,
      );
      if (best == null ||
          selection.meanResidualSeconds < best.meanResidualSeconds ||
          (selection.meanResidualSeconds == best.meanResidualSeconds &&
              selection.fitCount > best.fitCount)) {
        best = selection;
      }
    }
    return best;
  }

  void _mergeSameSourceStates(
    _Kotoho7HypState state,
    SourceEstimationRequest request, {
    required List<SeismicStationEventRecord> allTimingUsable,
  }) {
    state
      ..lastSameSourceMergeCount = 0
      ..lastSameSourceMergeKeys = const <String>[]
      ..lastSameSourceMergeAddedStationCount = 0;
    final currentKey = '${request.sourceId}:${request.eventId}';
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in allTimingUsable) record.descriptor.code: record,
    };
    final mergedKeys = <String>[];
    var addedStationCount = 0;
    for (final entry in _states.entries.toList(growable: false)) {
      final otherKey = entry.key;
      final other = entry.value;
      if (otherKey == currentKey || identical(other, state)) continue;
      if (!other.sourceCache.score.isFinite ||
          !state.sourceCache.score.isFinite) {
        continue;
      }
      final firstTimeDeltaSeconds =
          state.earliestObserved
              .difference(other.earliestObserved)
              .inMilliseconds
              .abs() /
          1000.0;
      if (firstTimeDeltaSeconds > 20.0) continue;
      final distanceKm = _haversineKm(
        state.sourceCache.latitude,
        state.sourceCache.longitude,
        other.sourceCache.latitude,
        other.sourceCache.longitude,
      );
      final stateRadius = _kotoho7AssignedRadiusKm(state, recordsByCode);
      final otherRadius = _kotoho7AssignedRadiusKm(other, recordsByCode);
      final averageRadius =
          ((stateRadius.isFinite ? stateRadius : 0) +
              (otherRadius.isFinite ? otherRadius : 0)) /
          2.0;
      final mergeDistanceKm = 50.0 + averageRadius / 2.0;
      if (distanceKm > mergeDistanceKm) continue;

      final before = state.assignedStationCodes.length;
      state.assignedStationCodes.addAll(other.assignedStationCodes);
      _copyKotoho7StationLifecycleMetadata(target: state, source: other);
      state.sourceKeys.addAll(other.sourceKeys);
      state.sourceKeys.add(otherKey);
      _copyScratch43MetadataForSameSourceMerge(
        target: state,
        source: other,
        sourceKey: otherKey,
      );
      addedStationCount += state.assignedStationCodes.length - before;
      mergedKeys.add(otherKey);
      _states.remove(otherKey);
    }
    if (mergedKeys.isEmpty) return;
    mergedKeys.sort();
    state
      ..lastSameSourceMergeCount = mergedKeys.length
      ..lastSameSourceMergeKeys = List<String>.unmodifiable(mergedKeys)
      ..lastSameSourceMergeAddedStationCount = addedStationCount;
  }

  double _kotoho7AssignedRadiusKm(
    _Kotoho7HypState state,
    Map<String, SeismicStationEventRecord> recordsByCode,
  ) {
    var maxDistanceKm = 0.0;
    var hasRecord = false;
    for (final code in state.assignedStationCodes) {
      final record = recordsByCode[code];
      if (record == null) continue;
      final distanceKm = _haversineKm(
        state.sourceCache.latitude,
        state.sourceCache.longitude,
        record.descriptor.coordinate.latitude,
        record.descriptor.coordinate.longitude,
      );
      if (distanceKm > maxDistanceKm) maxDistanceKm = distanceKm;
      hasRecord = true;
    }
    return hasRecord ? maxDistanceKm : double.infinity;
  }

  _HypCandidate _kotoho7Scratch44QuantizedCandidate(_HypCandidate candidate) {
    if (!candidate.score.isFinite) return candidate;
    return candidate.copyWith(
      longitude: (candidate.longitude * 60.0).round() / 60.0,
      latitude: (candidate.latitude * 60.0).round() / 60.0,
      depthKm: candidate.depthKm.roundToDouble(),
      originOffsetSeconds: candidate.originOffsetSeconds.roundToDouble(),
    );
  }

  void _refreshKotoho7StationPsCache(
    _Kotoho7HypState state, {
    required List<SeismicStationEventRecord> allTimingUsable,
  }) {
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in allTimingUsable) record.descriptor.code: record,
    };
    state.scratchStationPArrivalSeconds.removeWhere(
      (code, _) => !state.assignedStationCodes.contains(code),
    );
    state.scratchStationSArrivalSeconds.removeWhere(
      (code, _) => !state.assignedStationCodes.contains(code),
    );
    state.scratchStationSFlag.removeWhere(
      (code, _) => !state.assignedStationCodes.contains(code),
    );

    if (_kotoho7ScratchPsCacheInvalid(state)) {
      state.scratchStationPArrivalSeconds.clear();
      state.scratchStationSArrivalSeconds.clear();
      return;
    }

    for (final code in state.assignedStationCodes) {
      final record = recordsByCode[code];
      if (record == null) continue;
      _refreshKotoho7StationPsCacheForRecord(state, record);
    }
  }

  void _refreshKotoho7StationPsCacheForRecord(
    _Kotoho7HypState state,
    SeismicStationEventRecord record,
  ) {
    _refreshKotoho7StationPsCacheForRecordInto(
      state,
      record,
      pArrivalSecondsByCode: state.scratchStationPArrivalSeconds,
      sArrivalSecondsByCode: state.scratchStationSArrivalSeconds,
      sFlagByCode: state.scratchStationSFlag,
    );
  }

  bool _kotoho7ScratchPsCacheInvalid(_Kotoho7HypState state) {
    // Scratch `推定用tenPS時間計算` does not read the transient candidate score.
    // It gates on `4-3 検出id別情報[id + 11]` and whether the corresponding
    // `4-4 検出id震源要素` source cache is present. Scratch treats an empty
    // `4-3 +11` item as numeric zero for the `> 3000` comparison, so a missing
    // best-score proxy is not itself invalid.
    return !state.sourceCache.score.isFinite ||
        (state.scratch43BestScore.isFinite &&
            state.scratch43BestScore > 3000.0);
  }

  void _refreshKotoho7ShadowStationPsCacheForRecord(
    _Kotoho7HypState state,
    SeismicStationEventRecord record,
  ) {
    _refreshKotoho7StationPsCacheForRecordInto(
      state,
      record,
      pArrivalSecondsByCode: state.scratchShadowStationPArrivalSeconds,
      sArrivalSecondsByCode: state.scratchShadowStationSArrivalSeconds,
      sFlagByCode: state.scratchShadowStationSFlag,
    );
  }

  void _refreshKotoho7StationPsCacheForRecordInto(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required Map<String, double> pArrivalSecondsByCode,
    required Map<String, double> sArrivalSecondsByCode,
    required Map<String, bool> sFlagByCode,
  }) {
    final source = state.sourceCache;
    final code = record.descriptor.code;
    if (_kotoho7ScratchPsCacheInvalid(state)) {
      pArrivalSecondsByCode.remove(code);
      sArrivalSecondsByCode.remove(code);
      return;
    }
    final observedAt =
        state.scratchStationFirstUseAt[code] ??
        record.firstTriggerAt ??
        record.firstRiseAt;
    if (observedAt == null) return;
    final observedSeconds =
        observedAt.difference(state.earliestObserved).inMilliseconds / 1000.0;
    final surfaceDistanceKm = _haversineKm(
      source.latitude,
      source.longitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + source.depthKm * source.depthKm,
    );
    final pArrivalSeconds =
        source.originOffsetSeconds +
        Jma2001TravelTimeApproximation.travelTimeSeconds(
          hypocentralDistanceKm: hypocentralDistanceKm,
          depthKm: source.depthKm,
          pWave: true,
        );
    final sArrivalSeconds =
        source.originOffsetSeconds +
        Jma2001TravelTimeApproximation.travelTimeSeconds(
          hypocentralDistanceKm: hypocentralDistanceKm,
          depthKm: source.depthKm,
          pWave: false,
        );
    pArrivalSecondsByCode[code] = pArrivalSeconds;
    sArrivalSecondsByCode[code] = sArrivalSeconds;
    sFlagByCode[code] =
        (observedSeconds - sArrivalSeconds).abs() <
        (observedSeconds - pArrivalSeconds).abs();
  }

  void _refreshKotoho7StationDistanceCacheForRecord(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required Map<String, SeismicStationEventRecord> recordsByCode,
  }) {
    final firstRecord = recordsByCode[state.firstStationCode];
    if (firstRecord == null) return;
    final code = record.descriptor.code;
    final distanceKm = _kotoho7ScratchFirstStationDistanceKm(
      firstRecord,
      record,
    );
    state.scratchStationFirstDistanceKm[code] = distanceKm;
    state.scratch43MaxFirstStationDistanceKm = math.max(
      state.scratch43MaxFirstStationDistanceKm,
      distanceKm,
    );
  }

  void _refreshKotoho7StationDistanceCache(
    _Kotoho7HypState state, {
    required Map<String, SeismicStationEventRecord> recordsByCode,
  }) {
    state.scratchStationFirstDistanceKm.removeWhere(
      (code, _) => !state.assignedStationCodes.contains(code),
    );
    for (final code in state.assignedStationCodes) {
      final record = recordsByCode[code];
      if (record == null) continue;
      _refreshKotoho7StationDistanceCacheForRecord(
        state,
        record,
        recordsByCode: recordsByCode,
      );
    }
  }

  List<Map<String, Object?>> _kotoho7StationPsCacheDiagnostics(
    _Kotoho7HypState state,
  ) {
    final codes = state.assignedStationCodes.toList(growable: false)..sort();
    final rows = <Map<String, Object?>>[];
    for (final code in codes.take(12)) {
      final hasP = state.scratchStationPArrivalSeconds.containsKey(code);
      final hasS = state.scratchStationSArrivalSeconds.containsKey(code);
      final missingReason = _kotoho7StationPsCacheMissingReason(
        state,
        code,
        hasP: hasP,
        hasS: hasS,
      );
      rows.add({
        'station_code': code,
        'ten_plus_7_p_arrival_s': state.scratchStationPArrivalSeconds[code],
        'ten_plus_8_s_arrival_s': state.scratchStationSArrivalSeconds[code],
        'ten_plus_6_s_flag': state.scratchStationSFlag[code],
        'ten_plus_4_first_station_distance_km':
            state.scratchStationFirstDistanceKm[code],
        'has_ten_plus_7': hasP,
        'has_ten_plus_8': hasS,
        'missing_ps_reason': missingReason,
        'scratch_4_3_plus_11_score_proxy': state.scratch43BestScore,
        'source_cache_score': state.sourceCache.score,
        'scratch_4_4_source_cache_available': state.sourceCache.score.isFinite,
        'scratch_ten_plus_1_at': state.scratchStationFirstUseAt[code]
            ?.toIso8601String(),
        'scratch_ten_plus_2_at': state.scratchStationLastUpdateAt[code]
            ?.toIso8601String(),
      });
    }
    return rows;
  }

  Map<String, Object?> _kotoho7StationPsCacheMissingSummary(
    _Kotoho7HypState state,
  ) {
    final missingCodes = <String>[];
    final missingReasonCounts = <String, int>{};
    for (final code in state.assignedStationCodes) {
      final hasP = state.scratchStationPArrivalSeconds.containsKey(code);
      final hasS = state.scratchStationSArrivalSeconds.containsKey(code);
      if (hasP && hasS) continue;
      missingCodes.add(code);
      final reason =
          _kotoho7StationPsCacheMissingReason(
            state,
            code,
            hasP: hasP,
            hasS: hasS,
          ) ??
          'not_missing';
      missingReasonCounts[reason] = (missingReasonCounts[reason] ?? 0) + 1;
    }
    missingCodes.sort();
    return {
      'missing_ps_cache_count': missingCodes.length,
      'missing_ps_cache_station_codes': missingCodes,
      'missing_ps_cache_reason_counts': Map<String, int>.unmodifiable(
        missingReasonCounts,
      ),
    };
  }

  String? _kotoho7StationPsCacheMissingReason(
    _Kotoho7HypState state,
    String code, {
    required bool hasP,
    required bool hasS,
  }) {
    if (hasP && hasS) return null;
    if (!state.sourceCache.score.isFinite) {
      return 'scratch_4_4_source_cache_missing_or_nonfinite';
    }
    if (state.scratch43BestScore.isFinite &&
        state.scratch43BestScore > 3000.0) {
      return 'scratch_4_3_plus_11_score_over_3000_proxy';
    }
    return 'not_recomputed_since_source_cache_became_valid';
  }

  Map<String, Object?> _kotoho7ShadowStationPsCacheDiagnostics(
    _Kotoho7HypState state, {
    required List<SeismicStationEventRecord> usable,
    required List<SeismicStationEventRecord> unarrived,
    required DateTime observedAt,
  }) {
    final assignedCodes = state.assignedStationCodes.toList(growable: false)
      ..sort();
    var missingShadowFlagCount = 0;
    var sFlagDisagreementCount = 0;
    var pArrivalDeltaSum = 0.0;
    var pArrivalDeltaCount = 0;
    var sArrivalDeltaSum = 0.0;
    var sArrivalDeltaCount = 0;
    final samples = <Map<String, Object?>>[];
    for (final code in assignedCodes) {
      final productionSFlag = state.scratchStationSFlag[code];
      final shadowSFlag = state.scratchShadowStationSFlag[code];
      final productionP = state.scratchStationPArrivalSeconds[code];
      final shadowP = state.scratchShadowStationPArrivalSeconds[code];
      final productionS = state.scratchStationSArrivalSeconds[code];
      final shadowS = state.scratchShadowStationSArrivalSeconds[code];
      if (shadowSFlag == null) {
        missingShadowFlagCount += 1;
      } else if (productionSFlag != null && productionSFlag != shadowSFlag) {
        sFlagDisagreementCount += 1;
      }
      final pDelta = productionP != null && shadowP != null
          ? (productionP - shadowP).abs()
          : null;
      if (pDelta != null) {
        pArrivalDeltaSum += pDelta;
        pArrivalDeltaCount += 1;
      }
      final sDelta = productionS != null && shadowS != null
          ? (productionS - shadowS).abs()
          : null;
      if (sDelta != null) {
        sArrivalDeltaSum += sDelta;
        sArrivalDeltaCount += 1;
      }
      if (samples.length < 16 &&
          (shadowSFlag == null ||
              (productionSFlag != null && productionSFlag != shadowSFlag) ||
              (pDelta != null && pDelta > 0.25) ||
              (sDelta != null && sDelta > 0.25))) {
        samples.add({
          'station_code': code,
          'production_s_flag': productionSFlag,
          'shadow_s_flag': shadowSFlag,
          'production_p_arrival_s': productionP,
          'shadow_p_arrival_s': shadowP,
          'production_s_arrival_s': productionS,
          'shadow_s_arrival_s': shadowS,
          'p_arrival_abs_delta_s': pDelta,
          's_arrival_abs_delta_s': sDelta,
        });
      }
    }
    final source = state.sourceCache;
    final shadowRescore = source.score.isFinite
        ? _scoreKotoho7HypCandidate(
            usable,
            unarrived,
            earliestObserved: state.earliestObserved,
            observedAt: observedAt,
            latitude: source.latitude,
            longitude: source.longitude,
            depthKm: source.depthKm,
            originSeedSeconds: source.originOffsetSeconds,
            phaseReferenceLatitude: source.latitude,
            phaseReferenceLongitude: source.longitude,
            phaseReferenceDepthKm: source.depthKm,
            phaseReferenceOriginOffsetSeconds: source.originOffsetSeconds,
            stationSFlagByCode: state.scratchShadowStationSFlag,
          )
        : null;
    return {
      'model':
          'diagnostic_event_driven_shadow_for_ten_plus_6_7_8_not_production_v1',
      'production_model': 'scratch_suiteitenten_ps_time_recompute_stateful_v1',
      'scratch_formula':
          '推定用tenPS時間計算: +7=origin+P走時, +8=origin+S走時, +6=abs(+1-+8)<abs(+1-+7)',
      'scratch_bulk_recompute_reference':
          '検出id_推定PS時間id別再計算 exists in sb3 and iterates ten:+3 members, but no direct call block is present in the current project extraction',
      'update_sources':
          'assignment/distance-set path and state6 rerise re-register path only; state5 +2 update does not call 推定用tenPS時間計算',
      'assigned_count': assignedCodes.length,
      'p_arrival_count': state.scratchShadowStationPArrivalSeconds.length,
      's_arrival_count': state.scratchShadowStationSArrivalSeconds.length,
      's_flag_count': state.scratchShadowStationSFlag.values
          .where((flag) => flag)
          .length,
      'missing_shadow_s_flag_count': missingShadowFlagCount,
      's_flag_disagreement_count': sFlagDisagreementCount,
      'mean_p_arrival_abs_delta_s': pArrivalDeltaCount == 0
          ? null
          : pArrivalDeltaSum / pArrivalDeltaCount,
      'mean_s_arrival_abs_delta_s': sArrivalDeltaCount == 0
          ? null
          : sArrivalDeltaSum / sArrivalDeltaCount,
      'shadow_rescore': shadowRescore == null
          ? null
          : {
              'score': shadowRescore.score,
              'score_delta_vs_current': shadowRescore.score - source.score,
              'phase_mean_residual_s': shadowRescore.phaseMeanResidualSeconds,
              'phase_p_count': shadowRescore.phasePCount,
              'phase_s_count': shadowRescore.phaseSCount,
              'phase_other_count': shadowRescore.phaseOtherCount,
              's_flag_count': shadowRescore.scratchSFlagCount,
              'weighted_residual_squares':
                  shadowRescore.scratchWeightedResidualSquares,
              'weight_sum': shadowRescore.scratchWeightSum,
            },
      'sample': samples,
    };
  }

  void _refreshScratch43Metadata(
    _Kotoho7HypState state, {
    required List<SeismicStationEventRecord> allTimingUsable,
    required _HypCandidate best,
    required DateTime observedAt,
    bool updateBestScore = true,
  }) {
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in allTimingUsable) record.descriptor.code: record,
    };
    var assignedCount = 0;
    var maxFirstDistanceKm = 0.0;
    DateTime? latestDetectionAt;
    final firstRecord = recordsByCode[state.firstStationCode];
    _refreshKotoho7StationDistanceCache(state, recordsByCode: recordsByCode);
    for (final code in state.assignedStationCodes) {
      final record = recordsByCode[code];
      if (record == null) continue;
      assignedCount += 1;
      final at = record.firstTriggerAt ?? record.firstRiseAt;
      if (at != null &&
          (latestDetectionAt == null || at.isAfter(latestDetectionAt))) {
        latestDetectionAt = at;
      }
      if (firstRecord != null) {
        final distanceKm = _kotoho7ScratchFirstStationDistanceKm(
          firstRecord,
          record,
        );
        if (distanceKm > maxFirstDistanceKm) {
          maxFirstDistanceKm = distanceKm;
        }
      }
    }
    state
      ..scratch43AssignedCount = assignedCount
      ..scratch43MaxFirstStationDistanceKm = math.max(
        state.scratch43MaxFirstStationDistanceKm,
        maxFirstDistanceKm,
      )
      ..scratch43LastDetectionAt = latestDetectionAt ?? observedAt;
    if (updateBestScore && best.score.isFinite) {
      final ageSeconds =
          observedAt
              .difference(state.scratch43FirstDetectionAt)
              .inMilliseconds /
          1000.0;
      final displayScore = best.score < 250.0 && ageSeconds < 10.0
          ? 250.0
          : best.score;
      state
        ..scratch43BestScore = displayScore
        ..scratch43BestPhaseMeanResidualSeconds = best.phaseMeanResidualSeconds
        ..scratch43BestSourceKeys = List<String>.unmodifiable(
          state.sourceKeys.toList()..sort(),
        );
      if (best.score < state.scratch43BestRawScore) {
        state.scratch43BestRawScore = best.score;
      }
    }
  }

  void _copyScratch43MetadataForSameSourceMerge({
    required _Kotoho7HypState target,
    required _Kotoho7HypState source,
    required String sourceKey,
  }) {
    if (source.scratch43FirstDetectionAt.isBefore(
      target.scratch43FirstDetectionAt,
    )) {
      target
        ..firstStationCode = source.firstStationCode
        ..initialLatitude = source.initialLatitude
        ..initialLongitude = source.initialLongitude;
      target.scratch43FirstDetectionAt = source.scratch43FirstDetectionAt;
    }
    if (source.scratch43LastDetectionAt.isAfter(
      target.scratch43LastDetectionAt,
    )) {
      target.scratch43LastDetectionAt = source.scratch43LastDetectionAt;
    }
    final targetSlotPlus6 =
        target.scratch43LastMaxCurrentShindoIndex ?? double.infinity;
    final sourceSlotPlus6 =
        source.scratch43LastMaxCurrentShindoIndex ?? double.infinity;
    if (sourceSlotPlus6 < targetSlotPlus6) {
      target
        ..scratch43LastMaxCurrentShindoIndex =
            source.scratch43LastMaxCurrentShindoIndex
        ..scratch43PreviousMaxCurrentShindoIndex =
            source.scratch43PreviousMaxCurrentShindoIndex;
    }
    if (source.scratch43BestScore.isFinite &&
        (!target.scratch43BestScore.isFinite ||
            source.scratch43BestScore < target.scratch43BestScore)) {
      target
        ..scratch43AssignedCount = source.scratch43AssignedCount
        ..scratch43MaxFirstStationDistanceKm =
            source.scratch43MaxFirstStationDistanceKm
        ..scratch43MaxSourceDistanceKm = source.scratch43MaxSourceDistanceKm
        ..scratch43ExpireAt = source.scratch43ExpireAt
        ..scratch43LastSourceCacheUpdatedAt =
            source.scratch43LastSourceCacheUpdatedAt
        ..scratch43BestScore = source.scratch43BestScore
        ..scratch43BestPhaseMeanResidualSeconds =
            source.scratch43BestPhaseMeanResidualSeconds
        ..scratch43BestSourceKeys =
            source.scratch43BestSourceKeys ?? <String>[sourceKey];
      if (source.sourceCache.score.isFinite) {
        target.sourceCache = source.sourceCache;
      }
    }
    if (source.scratch43BestRawScore > target.scratch43BestRawScore) {
      target.scratch43BestRawScore = source.scratch43BestRawScore;
    }
  }

  void _updateAssignedStationCodes(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> currentDetectionUsable, {
    required List<SeismicStationEventRecord> allTimingUsable,
    required DateTime observedAt,
    required double scratchRuntimeTimerSeconds,
  }) {
    state
      ..lastAssignmentAddedCount = 0
      ..lastAssignmentRejectedCount = 0
      ..lastAssignmentAddedStationCodes = const <String>[]
      ..lastAssignmentRejectedStationCodes = const <String>[]
      ..lastAssignmentRecoveryAddedCount = 0
      ..lastAssignmentRecoveryAddedStationCodes = const <String>[]
      ..lastAssignmentRemovedCount = 0
      ..lastAssignmentRemovedStationCodes = const <String>[]
      ..lastAssignmentCandidateReasonCounts = const <String, int>{}
      ..lastAssignmentResetReasonCounts = const <String, int>{}
      ..lastAssignmentNegativeCountDelta = 0
      ..lastAssignmentResetClearedPlus3Count = 0
      ..lastAssignmentResetClearedPsCacheCount = 0
      ..lastAssignmentResetClearedDistanceCount = 0
      ..lastAssignmentWouldSwitchOtherIdCount = 0
      ..lastAssignmentWouldSwitchOtherIdSourceCounts = const <String, int>{}
      ..lastAssignmentWouldSwitchOtherIdSamples = const <Map<String, Object?>>[]
      ..lastAssignmentAcceptedSameIdReasonCounts = const <String, int>{}
      ..lastAssignmentAcceptedSameIdSamples = const <Map<String, Object?>>[]
      ..lastEstimatedSlotWriteReasonCounts = const <String, int>{}
      ..lastEstimatedSlotWriteSamples = const <Map<String, Object?>>[]
      ..lastAssignmentImmediatePsRecomputeCount = 0
      ..lastAssignmentImmediateDistanceUpdateCount = 0
      ..lastAssignmentReriseRefreshCount = 0
      ..lastAssignmentReriseRefreshStationCodes = const <String>[]
      ..lastAssignmentMidFrameNewIdCount = 0
      ..lastAssignmentMidFrameNewIdStationCodes = const <String>[];
    if (currentDetectionUsable.isEmpty) return;
    if (!state.scratch43Active) {
      _invalidateKotoho7SourceState(
        state,
        reason: state.scratch43InactiveReason ?? 'scratch_4_3_inactive',
        observedAt: observedAt,
      );
      return;
    }
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in allTimingUsable) record.descriptor.code: record,
    };
    final removed = <String>[];
    final resetReasonCounts = <String, int>{};
    var negativeCountDelta = 0;
    var resetClearedPlus3Count = 0;
    var resetClearedPsCacheCount = 0;
    var resetClearedDistanceCount = 0;
    final reriseRefreshCodes = <String>{};
    final estimatedSlotWriteReasonCounts = <String, int>{};
    final estimatedSlotWriteSamples = <Map<String, Object?>>[];
    final stationPlus3SerialByCode = _kotoho7StationPlus3SerialByCode();
    for (final code in state.assignedStationCodes.toList(growable: false)) {
      final record = recordsByCode[code];
      final resetReason = record == null
          ? 'scratch_reset_missing_record'
          : _kotoho7AssignedStationResetReason(
              state,
              record,
              observedAt: observedAt,
              allTimingUsable: allTimingUsable,
              recordsByCode: recordsByCode,
              stationPlus3SerialByCode: stationPlus3SerialByCode,
              reriseRefreshCodes: reriseRefreshCodes,
              estimatedSlotWriteReasonCounts: estimatedSlotWriteReasonCounts,
              estimatedSlotWriteSamples: estimatedSlotWriteSamples,
            );
      if (resetReason != null) {
        final reset = _resetKotoho7AssignedStation(
          state,
          code,
          reason: resetReason,
        );
        resetReasonCounts[resetReason] =
            (resetReasonCounts[resetReason] ?? 0) + 1;
        negativeCountDelta += reset.negativeCountDelta;
        if (reset.clearedPlus3) resetClearedPlus3Count += 1;
        if (reset.clearedPsCache) resetClearedPsCacheCount += 1;
        if (reset.clearedDistance) resetClearedDistanceCount += 1;
        removed.add(code);
      }
    }
    final added = <String>[];
    final rejected = <String>[];
    final addedSourceCounts = <String, int>{};
    final rejectedSourceCounts = <String, int>{};
    final candidateReasonCounts = <String, int>{};
    final addedSourceSamples = <Map<String, Object?>>[];
    final acceptedSameIdReasonCounts = <String, int>{};
    final acceptedSameIdSamples = <Map<String, Object?>>[];
    final wouldSwitchSourceCounts = <String, int>{};
    final wouldSwitchSamples = <Map<String, Object?>>[];
    final midFrameNewIdStationCodes = <String>[];
    final reriseRefreshStationCodes = <String>[];
    final reriseProcessedCodes = <String>{};
    var wouldSwitchOtherIdCount = 0;
    var immediatePsRecomputeCount = 0;
    var immediateDistanceUpdateCount = 0;
    for (final code in reriseRefreshCodes) {
      if (!state.assignedStationCodes.contains(code)) continue;
      final record = recordsByCode[code];
      if (record == null) continue;
      final refreshedAt = state.scratchStationFirstUseAt[code] ?? observedAt;
      final removedForReregister =
          _removeKotoho7StationMembershipForId3Reregister(state, code);
      if (!removedForReregister) continue;
      reriseProcessedCodes.add(code);
      final selected = _selectKotoho7StationSourceState(
        record,
        currentState: state,
        observedAt: observedAt,
        allTimingUsable: allTimingUsable,
        scratchRuntimeTimerSeconds: scratchRuntimeTimerSeconds,
        isRerise: true,
        candidateReasonCounts: candidateReasonCounts,
      );
      if (identical(selected?.state, state)) {
        final assigned = _assignKotoho7StationToState(
          state,
          record,
          observedAt: observedAt,
          recordsByCode: recordsByCode,
          selectionSource: '${selected!.source}_rerise_reregister',
          stationUseAtOverride: refreshedAt,
        );
        if (assigned) {
          reriseRefreshStationCodes.add(code);
          immediatePsRecomputeCount += 1;
          if (state.scratchStationFirstDistanceKm.containsKey(code)) {
            immediateDistanceUpdateCount += 1;
          }
        }
      } else if (selected != null) {
        _assignKotoho7StationToState(
          selected.state,
          record,
          observedAt: observedAt,
          recordsByCode: recordsByCode,
          selectionSource: '${selected.source}_rerise_reregister',
          stationUseAtOverride: refreshedAt,
        );
        wouldSwitchOtherIdCount += 1;
        wouldSwitchSourceCounts[selected.source] =
            (wouldSwitchSourceCounts[selected.source] ?? 0) + 1;
        if (wouldSwitchSamples.length < 16) {
          wouldSwitchSamples.add({
            'station_code': code,
            'source': '${selected.source}_rerise_reregister',
            'residual_s': selected.residualSeconds,
            'from_source_keys': state.sourceKeys.toList()..sort(),
            'to_source_keys': selected.state.sourceKeys.toList()..sort(),
            'to_assigned_count': selected.state.assignedStationCodes.length,
            'to_active': selected.state.scratch43Active,
          });
        }
      } else {
        if (_kotoho7ScratchId4NoCandidateShouldReset()) {
          _clearKotoho7StationLifecycle(state, code);
          rejectedSourceCounts['scratch_id4_no_candidate_reset_existing_ids'] =
              (rejectedSourceCounts['scratch_id4_no_candidate_reset_existing_ids'] ??
                  0) +
              1;
          _incrementKotoho7Reason(
            candidateReasonCounts,
            'scratch_id4_count2_minus1_existing_id_rows_rerise',
          );
          continue;
        }
        final newState = _createKotoho7MidFrameNewIdState(
          parentState: state,
          record: record,
          observedAt: observedAt,
          recordsByCode: recordsByCode,
          stationUseAtOverride: refreshedAt,
        );
        midFrameNewIdStationCodes.add(code);
        rejectedSourceCounts['scratch_id3_new_id_mid_frame_rerise'] =
            (rejectedSourceCounts['scratch_id3_new_id_mid_frame_rerise'] ?? 0) +
            1;
        _incrementKotoho7Reason(
          candidateReasonCounts,
          'created_mid_frame_new_id_for_rerise_count2_zero',
        );
        if (wouldSwitchSamples.length < 16) {
          wouldSwitchSamples.add({
            'station_code': code,
            'source': 'scratch_id3_new_id_mid_frame_rerise',
            'from_source_keys': state.sourceKeys.toList()..sort(),
            'to_source_keys': newState.sourceKeys.toList()..sort(),
            'to_assigned_count': newState.assignedStationCodes.length,
            'to_active': newState.scratch43Active,
          });
        }
      }
    }
    for (final record in currentDetectionUsable) {
      final code = record.descriptor.code;
      if (reriseProcessedCodes.contains(code)) continue;
      if (state.assignedStationCodes.contains(code)) continue;
      final selected = _selectKotoho7StationSourceState(
        record,
        currentState: state,
        observedAt: observedAt,
        allTimingUsable: allTimingUsable,
        scratchRuntimeTimerSeconds: scratchRuntimeTimerSeconds,
        isRerise: false,
        candidateReasonCounts: candidateReasonCounts,
      );
      if (identical(selected?.state, state)) {
        final acceptanceDetail = _kotoho7StationAcceptanceDetail(
          state,
          record,
          selected: selected!,
          observedAt: observedAt,
          recordsByCode: recordsByCode,
        );
        final acceptReason =
            acceptanceDetail['accept_reason'] as String? ?? selected.source;
        acceptedSameIdReasonCounts[acceptReason] =
            (acceptedSameIdReasonCounts[acceptReason] ?? 0) + 1;
        if (acceptedSameIdSamples.length < 24) {
          acceptedSameIdSamples.add(acceptanceDetail);
        }
        final assigned = _assignKotoho7StationToState(
          state,
          record,
          observedAt: observedAt,
          recordsByCode: recordsByCode,
          selectionSource: selected.source,
        );
        if (!assigned) continue;
        immediatePsRecomputeCount += 1;
        if (state.scratchStationFirstDistanceKm.containsKey(code)) {
          immediateDistanceUpdateCount += 1;
        }
        added.add(code);
        final source = selected.source;
        addedSourceCounts[source] = (addedSourceCounts[source] ?? 0) + 1;
        if (addedSourceSamples.length < 16) {
          addedSourceSamples.add({
            'station_code': code,
            'source': source,
            'residual_s': selected.residualSeconds,
          });
        }
      } else {
        rejected.add(code);
        final source = selected?.source ?? 'no_candidate';
        rejectedSourceCounts[source] = (rejectedSourceCounts[source] ?? 0) + 1;
        if (selected != null && !identical(selected.state, state)) {
          _assignKotoho7StationToState(
            selected.state,
            record,
            observedAt: observedAt,
            recordsByCode: recordsByCode,
            selectionSource: selected.source,
          );
          wouldSwitchOtherIdCount += 1;
          wouldSwitchSourceCounts[source] =
              (wouldSwitchSourceCounts[source] ?? 0) + 1;
          if (wouldSwitchSamples.length < 16) {
            wouldSwitchSamples.add({
              'station_code': code,
              'source': source,
              'residual_s': selected.residualSeconds,
              'from_source_keys': state.sourceKeys.toList()..sort(),
              'to_source_keys': selected.state.sourceKeys.toList()..sort(),
              'to_assigned_count': selected.state.assignedStationCodes.length,
              'to_active': selected.state.scratch43Active,
            });
          }
        } else if (selected == null) {
          if (_kotoho7ScratchId4NoCandidateShouldReset()) {
            _clearKotoho7StationLifecycle(state, code);
            rejectedSourceCounts['scratch_id4_no_candidate_reset_existing_ids'] =
                (rejectedSourceCounts['scratch_id4_no_candidate_reset_existing_ids'] ??
                    0) +
                1;
            _incrementKotoho7Reason(
              candidateReasonCounts,
              'scratch_id4_count2_minus1_existing_id_rows',
            );
            continue;
          }
          final newState = _createKotoho7MidFrameNewIdState(
            parentState: state,
            record: record,
            observedAt: observedAt,
            recordsByCode: recordsByCode,
          );
          midFrameNewIdStationCodes.add(code);
          rejectedSourceCounts['scratch_id3_new_id_mid_frame'] =
              (rejectedSourceCounts['scratch_id3_new_id_mid_frame'] ?? 0) + 1;
          _incrementKotoho7Reason(
            candidateReasonCounts,
            'created_mid_frame_new_id_for_count2_zero',
          );
          if (wouldSwitchSamples.length < 16) {
            wouldSwitchSamples.add({
              'station_code': code,
              'source': 'scratch_id3_new_id_mid_frame',
              'from_source_keys': state.sourceKeys.toList()..sort(),
              'to_source_keys': newState.sourceKeys.toList()..sort(),
              'to_assigned_count': newState.assignedStationCodes.length,
              'to_active': newState.scratch43Active,
            });
          }
        }
      }
    }
    removed.sort();
    added.sort();
    rejected.sort();
    state
      ..lastAssignmentAddedCount = added.length
      ..lastAssignmentRejectedCount = rejected.length
      ..lastAssignmentAddedStationCodes = List<String>.unmodifiable(added)
      ..lastAssignmentRejectedStationCodes = List<String>.unmodifiable(rejected)
      ..lastAssignmentRecoveryAddedCount = 0
      ..lastAssignmentRecoveryAddedStationCodes = const <String>[]
      ..lastAssignmentRemovedCount = removed.length
      ..lastAssignmentRemovedStationCodes = List<String>.unmodifiable(removed)
      ..lastAssignmentAddedSourceCounts = Map<String, int>.unmodifiable(
        addedSourceCounts,
      )
      ..lastAssignmentRejectedSourceCounts = Map<String, int>.unmodifiable(
        rejectedSourceCounts,
      )
      ..lastAssignmentCandidateReasonCounts = Map<String, int>.unmodifiable(
        candidateReasonCounts,
      )
      ..lastAssignmentResetReasonCounts = Map<String, int>.unmodifiable(
        resetReasonCounts,
      )
      ..lastAssignmentNegativeCountDelta = negativeCountDelta
      ..lastAssignmentResetClearedPlus3Count = resetClearedPlus3Count
      ..lastAssignmentResetClearedPsCacheCount = resetClearedPsCacheCount
      ..lastAssignmentResetClearedDistanceCount = resetClearedDistanceCount
      ..lastAssignmentWouldSwitchOtherIdCount = wouldSwitchOtherIdCount
      ..lastAssignmentWouldSwitchOtherIdSourceCounts =
          Map<String, int>.unmodifiable(wouldSwitchSourceCounts)
      ..lastAssignmentWouldSwitchOtherIdSamples =
          List<Map<String, Object?>>.unmodifiable(wouldSwitchSamples)
      ..lastAssignmentAcceptedSameIdReasonCounts =
          Map<String, int>.unmodifiable(acceptedSameIdReasonCounts)
      ..lastAssignmentAcceptedSameIdSamples =
          List<Map<String, Object?>>.unmodifiable(acceptedSameIdSamples)
      ..lastEstimatedSlotWriteReasonCounts = Map<String, int>.unmodifiable(
        estimatedSlotWriteReasonCounts,
      )
      ..lastEstimatedSlotWriteSamples = List<Map<String, Object?>>.unmodifiable(
        estimatedSlotWriteSamples,
      )
      ..lastAssignmentAddedSourceSamples =
          List<Map<String, Object?>>.unmodifiable(addedSourceSamples)
      ..lastAssignmentImmediatePsRecomputeCount = immediatePsRecomputeCount
      ..lastAssignmentImmediateDistanceUpdateCount =
          immediateDistanceUpdateCount
      ..lastAssignmentReriseRefreshCount = reriseRefreshStationCodes.length
      ..lastAssignmentReriseRefreshStationCodes = List<String>.unmodifiable(
        reriseRefreshStationCodes..sort(),
      )
      ..lastAssignmentMidFrameNewIdCount = midFrameNewIdStationCodes.length
      ..lastAssignmentMidFrameNewIdStationCodes = List<String>.unmodifiable(
        midFrameNewIdStationCodes..sort(),
      );
  }

  bool _assignKotoho7StationToState(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required Map<String, SeismicStationEventRecord> recordsByCode,
    required String selectionSource,
    DateTime? stationUseAtOverride,
  }) {
    final code = record.descriptor.code;
    if (!state.assignedStationCodes.add(code)) return false;
    state.scratch43AssignedCount += 1;
    _initializeKotoho7StationLifecycle(
      state,
      record,
      observedAt: observedAt,
      stationUseAtOverride: stationUseAtOverride,
    );
    _refreshKotoho7StationPsCacheForRecord(state, record);
    _refreshKotoho7ShadowStationPsCacheForRecord(state, record);
    _refreshKotoho7StationDistanceCacheForRecord(
      state,
      record,
      recordsByCode: recordsByCode,
    );
    _setKotoho7GridCarrier(
      state,
      record,
      observedAt: observedAt,
      selectionSource: selectionSource,
    );
    if (observedAt.isAfter(state.scratch43LastDetectionAt)) {
      state.scratch43LastDetectionAt = observedAt;
    }
    return true;
  }

  _Kotoho7HypState _createKotoho7MidFrameNewIdState({
    required _Kotoho7HypState parentState,
    required SeismicStationEventRecord record,
    required DateTime observedAt,
    required Map<String, SeismicStationEventRecord> recordsByCode,
    DateTime? stationUseAtOverride,
  }) {
    final code = record.descriptor.code;
    final useAt =
        stationUseAtOverride ??
        parentState.scratchStationPendingCloudAt[code] ??
        _kotoho7StationUseTime(record, observedAt: observedAt);
    final seedLatitude =
        (record.descriptor.coordinate.latitude * 100).round() / 100.0;
    final seedLongitude =
        (record.descriptor.coordinate.longitude * 100).round() / 100.0;
    final sourceCache = _scoreKotoho7HypCandidate(
      <SeismicStationEventRecord>[record],
      const <SeismicStationEventRecord>[],
      earliestObserved: useAt,
      observedAt: observedAt,
      latitude: seedLatitude,
      longitude: seedLongitude,
      depthKm: 10.0,
      originSeedSeconds: -2.0,
    );
    final baseKey =
        '${parentState.sourceKeys.isEmpty ? 'kotoho7' : parentState.sourceKeys.first}:mid:$code';
    var key = baseKey;
    var suffix = 0;
    while (_states.containsKey(key)) {
      suffix += 1;
      key = '$baseKey:$suffix';
    }
    final next = _Kotoho7HypState(
      earliestObserved: useAt,
      initializedAt: observedAt,
      lastUpdatedAt: observedAt,
      firstStationCode: code,
      initialLatitude: seedLatitude,
      initialLongitude: seedLongitude,
      sourceCache: sourceCache,
      sourceKeys: <String>{key},
      scratch43Serial: _nextKotoho7Scratch43Serial(),
      scratch43CreatedByMidFrameNewId: true,
      scratch43SingleStationGraceUntil: observedAt.add(
        const Duration(seconds: 2),
      ),
      assignedStationCodes: <String>{},
      scratchDetectionPermissionState: _scratchDetectionPermissionState,
      scratchDetectionTriggerAt: _scratchDetectionTriggerAt,
      scratchDetectionPermissionReason: _scratchDetectionPermissionReason,
      scratchDetectionAccelerationScore: _scratchDetectionAccelerationScore,
      scratchDetectionAccelerationTimeAreaCount:
          _scratchDetectionAccelerationTimeAreaCount,
      scratchDetectionAccelerationReason: _scratchDetectionAccelerationReason,
      scratchDetectionPermittedShindo: _scratchDetectionPermittedShindo,
      scratchStationMaxShindoValue: _scratchStationMaxShindoValue,
      scratchStationMaxShindoUpdatedAt: _scratchStationMaxShindoUpdatedAt,
      scratchGridDetectionMax: _scratchGridDetectionMax,
      scratchGridDetectionMaxKeep: _scratchGridDetectionMaxKeep,
    );
    next.scratch43FirstDetectionAt = observedAt;
    next
      ..lastSourceSelectionModel = 'scratch_id3_new_id_mid_frame'
      ..lastSourceSelectionSelectedKey = key
      ..lastSourceSelectionCandidateCount = 0
      ..lastSourceSelectionFitCount = 1
      ..lastSourceSelectionMeanResidualSeconds = 0;
    _states[key] = next;
    _assignKotoho7StationToState(
      next,
      record,
      observedAt: observedAt,
      recordsByCode: recordsByCode,
      selectionSource: 'scratch_id3_new_id_mid_frame',
      stationUseAtOverride: useAt,
    );
    _trimKotoho7StateCache(
      protectedStates: <_Kotoho7HypState>{parentState, next},
    );
    return next;
  }

  void _trimKotoho7StateCache({
    Set<_Kotoho7HypState> protectedStates = const <_Kotoho7HypState>{},
  }) {
    while (_states.length > maxCachedEvents) {
      final candidates = _states.entries
          .where((entry) => !protectedStates.contains(entry.value))
          .toList(growable: false);
      if (candidates.isEmpty) return;
      final oldest = candidates.reduce((a, b) {
        return a.value.lastUpdatedAt.isBefore(b.value.lastUpdatedAt) ? a : b;
      }).key;
      _states.remove(oldest);
    }
  }

  int _nextKotoho7Scratch43Serial() {
    final serial = _nextScratch43Serial;
    _nextScratch43Serial += 1;
    return serial;
  }

  void _updateScratch43ActiveState(
    _Kotoho7HypState state, {
    required List<SeismicStationEventRecord> allTimingUsable,
    required DateTime observedAt,
  }) {
    if (!state.scratch43Active) return;
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in allTimingUsable) record.descriptor.code: record,
    };
    final assignedCount = state.assignedStationCodes.length;
    final ageSeconds =
        observedAt.difference(state.scratch43FirstDetectionAt).inMilliseconds /
        1000.0;
    final hasCurrentFrameEvidence = _kotoho7HasCurrentFrameEvidence(
      state,
      recordsByCode: recordsByCode,
      observedAt: observedAt,
    );
    if (!hasCurrentFrameEvidence) return;

    final gridPresenceCount = _kotoho7GridPresenceCountForState(state);
    state.scratch43LastGridPresenceCount = gridPresenceCount;
    final gridPresence = gridPresenceCount > 0;
    if (!gridPresence && ageSeconds > 2.0) {
      state.scratch43LastGridPresenceDisappearedAgeSeconds = ageSeconds;
      _invalidateKotoho7SourceState(
        state,
        reason: 'scratch_4_3_active_false_grid_id_disappeared',
        observedAt: observedAt,
      );
      return;
    }
    state.scratch43LastGridPresenceDisappearedAgeSeconds = null;

    final expireWindowSeconds = assignedCount < 200
        ? (3.0 + assignedCount) * 2.0
        : 400.0;
    state.scratch43LastExpireWindowSeconds = expireWindowSeconds;
    final candidateExpireAt = state.scratch43FirstDetectionAt.add(
      Duration(milliseconds: (expireWindowSeconds * 1000).round()),
    );
    if (state.scratch43ExpireAt == null ||
        candidateExpireAt.isAfter(state.scratch43ExpireAt!)) {
      state.scratch43ExpireAt = candidateExpireAt;
    }
    final maxCurrentShindo = _kotoho7MaxAssignedPermittedConvertedShindo(
      state,
      recordsByCode: recordsByCode,
      observedAt: observedAt,
    );
    state.scratch43LastMaxCurrentShindoIndex = maxCurrentShindo;
    final expireAt = state.scratch43ExpireAt;
    if (expireAt != null && observedAt.isAfter(expireAt)) {
      _invalidateKotoho7SourceState(
        state,
        reason: 'scratch_4_3_active_false_expired_plus9',
        observedAt: observedAt,
      );
      return;
    }
    state.scratch43PreviousMaxCurrentShindoIndex = maxCurrentShindo;

    if (ageSeconds > 150.0 && assignedCount < 50) {
      _invalidateKotoho7SourceState(
        state,
        reason: 'scratch_4_3_active_false_old_small_detection',
        observedAt: observedAt,
      );
      return;
    }

    if (assignedCount < 5 &&
        state.scratch43MaxFirstStationDistanceKm < 80.0 &&
        state.scratch43BestScore > 3000.0 &&
        maxCurrentShindo < 3.0 &&
        ageSeconds > 10.0) {
      _invalidateKotoho7SourceState(
        state,
        reason: 'scratch_4_3_active_false_small_weak_bad_score',
        observedAt: observedAt,
      );
    }
  }

  bool _kotoho7HasCurrentFrameEvidence(
    _Kotoho7HypState state, {
    required Map<String, SeismicStationEventRecord> recordsByCode,
    required DateTime observedAt,
  }) {
    for (final code in state.assignedStationCodes) {
      final latest = recordsByCode[code]?.observationHistory.latest;
      if (latest == null) continue;
      final ageSeconds =
          observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
      if (ageSeconds <= 1.5) return true;
    }
    return false;
  }

  void _updateKotoho7DetectionPermissionCache(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
    required Map<String, Object?> requestMetadata,
  }) {
    state
      ..lastDetectionPermissionPromotedCount = 0
      ..lastDetectionPermissionDemotedCount = 0
      ..lastDetectionPermissionRefreshedCount = 0
      ..lastDetectionPermissionReasonCounts = const <String, int>{};
    if (records.isEmpty) return;

    final reasonCounts = <String, int>{};
    var promotedCount = 0;
    var demotedCount = 0;
    var refreshedCount = 0;
    final scratchRealtimeDetectedMaxShindo =
        _kotoho7ScratchRealtimeDetectedMaxShindo100(
          state,
          records,
          observedAt: observedAt,
        );
    for (final record in records) {
      final code = record.descriptor.code;
      final previousState = state.scratchDetectionPermissionState[code] ?? 0;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      final triggerAt = state.scratchDetectionTriggerAt[code];
      final triggerAgeSeconds = triggerAt == null
          ? double.infinity
          : observedAt.difference(triggerAt).inMilliseconds / 1000.0;

      if (currentShindo == null) {
        const pointMissingState = 1;
        if (previousState != pointMissingState) {
          _setKotoho7DetectionPermissionState(
            state,
            code,
            pointMissingState,
            reason: 'scratch_permission_point_missing_release',
            observedAt: observedAt,
            forced: false,
          );
          if (pointMissingState > previousState) {
            promotedCount += 1;
          } else {
            demotedCount += 1;
          }
        }
        _incrementKotoho7Reason(
          reasonCounts,
          'scratch_permission_point_missing_release',
        );
        continue;
      }
      _updateKotoho7MaxShindoCaches(
        state,
        code,
        currentShindo: currentShindo,
        permissionState: previousState,
        observedAt: observedAt,
      );

      final rising = _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      );
      final changeSpeed = _kotoho7ChangeSpeedValue(
        record,
        observedAt: observedAt,
      );
      final oneSecondHistoryRise = _kotoho7HistoryChangeValue(
        record,
        observedAt: observedAt,
        targetSeconds: 1.0,
      );
      final convertedShindo =
          _kotoho7CurrentConvertedShindo(record, observedAt: observedAt) ??
          currentShindo;
      final support = _kotoho7Nearest7CurrentSupportCount(
        record,
        records,
        observedAt: observedAt,
      );
      final nearestConvertedAverage = _kotoho7NearestConvertedAverageShindo(
        record,
        records,
        observedAt: observedAt,
        maxCount: 3,
      );
      final nearest5MultiTriggerSummary = _kotoho7Nearest5MultiTriggerSummary(
        state,
        record,
        records,
        observedAt: observedAt,
      );
      final acceleration = _kotoho7DetectionAccelerationProxy(
        state,
        record,
        records,
        observedAt: observedAt,
        currentShindo: currentShindo,
        convertedShindo: convertedShindo,
        rising: rising,
      );
      state.scratchDetectionAccelerationScore[code] = acceleration.score;
      state.scratchDetectionAccelerationTimeAreaCount[code] =
          acceleration.timeAreaCount;
      state.scratchDetectionAccelerationReason[code] = acceleration.reason;
      final fastRiseEnergyExceeded = _kotoho7ScratchFastRiseEnergyExceedsLimit(
        record,
        observedAt: observedAt,
        upwardLimitDigit: _kotoho7ScratchThresholdDigit(
          acceleration.scratchThresholdCode,
          3,
        ),
      );
      final circleEewPermission = _kotoho7JsCircleEewPermission(
        requestMetadata,
        record,
        records,
        observedAt: observedAt,
        previousState: previousState,
        currentShindo: currentShindo,
        convertedShindo: convertedShindo,
        triggerAgeSeconds: triggerAgeSeconds,
        thresholdDigit: acceleration.scratchThresholdDigit,
        nearest7CurrentSupport: support,
      );
      if (circleEewPermission != null) {
        if (circleEewPermission.state == previousState) {
          _incrementKotoho7Reason(reasonCounts, circleEewPermission.reason);
        } else {
          _setKotoho7DetectionPermissionState(
            state,
            code,
            circleEewPermission.state,
            reason: circleEewPermission.reason,
            observedAt: observedAt,
            forced: circleEewPermission.refreshTriggerTime,
          );
          if (circleEewPermission.state > previousState) {
            promotedCount += 1;
          } else {
            demotedCount += 1;
          }
          _incrementKotoho7Reason(reasonCounts, circleEewPermission.reason);
        }
        _updateKotoho7MaxShindoCaches(
          state,
          code,
          currentShindo: currentShindo,
          permissionState:
              state.scratchDetectionPermissionState[code] ??
              circleEewPermission.state,
          observedAt: observedAt,
        );
        continue;
      }
      final next = _kotoho7NextDetectionPermissionState(
        previousState: previousState,
        currentShindo: currentShindo,
        convertedShindo: convertedShindo,
        rising: rising,
        changeSpeed: changeSpeed,
        fastRiseEnergyExceeded: fastRiseEnergyExceeded,
        oneSecondHistoryRise: oneSecondHistoryRise,
        nearest7CurrentSupport: support,
        nearest7AverageConvertedShindo: nearestConvertedAverage,
        nearest5PermissionCount:
            nearest5MultiTriggerSummary.permissionState5Count,
        nearest5HighShindoCount: nearest5MultiTriggerSummary.highShindoCount,
        nearest5AverageConvertedShindo:
            nearest5MultiTriggerSummary.averageConvertedShindo,
        acceleration: acceleration,
        triggerAgeSeconds: triggerAgeSeconds,
        scratchRealtimeDetectedMaxShindo: scratchRealtimeDetectedMaxShindo,
      );
      if (next.state == previousState) {
        if (next.reason == 'scratch_permission_rise_too_fast') {
          _setKotoho7DetectionPermissionState(
            state,
            code,
            next.state,
            reason: next.reason,
            observedAt: observedAt,
            forced: next.refreshTriggerTime,
          );
          _incrementKotoho7Reason(reasonCounts, next.reason);
        } else if (next.refreshTriggerTime) {
          state.scratchDetectionTriggerAt[code] = observedAt;
          refreshedCount += 1;
          _incrementKotoho7Reason(reasonCounts, next.reason);
        }
      } else {
        _setKotoho7DetectionPermissionState(
          state,
          code,
          next.state,
          reason: next.reason,
          observedAt: observedAt,
          forced: next.refreshTriggerTime,
        );
        if (next.state > previousState) {
          promotedCount += 1;
        } else {
          demotedCount += 1;
        }
        _incrementKotoho7Reason(reasonCounts, next.reason);
      }
      _updateKotoho7MaxShindoCaches(
        state,
        code,
        currentShindo: currentShindo,
        permissionState:
            state.scratchDetectionPermissionState[code] ?? next.state,
        observedAt: observedAt,
      );
    }

    final gridTrigger = _applyKotoho7GridTriggerPermissionProxy(
      state,
      records,
      observedAt: observedAt,
      reasonCounts: reasonCounts,
    );
    promotedCount += gridTrigger.promotedCount;
    demotedCount += gridTrigger.demotedCount;
    refreshedCount += gridTrigger.refreshedCount;

    state
      ..lastDetectionPermissionPromotedCount = promotedCount
      ..lastDetectionPermissionDemotedCount = demotedCount
      ..lastDetectionPermissionRefreshedCount = refreshedCount
      ..lastDetectionPermissionReasonCounts = Map<String, int>.unmodifiable(
        reasonCounts,
      );
  }

  ({int promotedCount, int demotedCount, int refreshedCount})
  _applyKotoho7GridTriggerPermissionProxy(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
    required Map<String, int> reasonCounts,
  }) {
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in records) record.descriptor.code: record,
    };
    final gridDetectionMax = _kotoho7GridDetectionMaxProxy(
      state,
      records,
      observedAt: observedAt,
    );

    var promotedCount = 0;
    var demotedCount = 0;
    var refreshedCount = 0;

    for (
      var serialIndex = 0;
      serialIndex < _kotoho7ScratchPopulatedGridNumbers.length;
      serialIndex++
    ) {
      final gridNumber = _kotoho7ScratchPopulatedGridNumbers[serialIndex];
      final gridRecords = _kotoho7ScratchGridRecordsBySerialIndex(
        serialIndex,
        recordsByCode,
      );
      final longRise = _kotoho7GridLongRiseProxy(
        gridRecords,
        observedAt: observedAt,
      );
      if (!longRise.qualifies) continue;

      final currentGridMax = gridDetectionMax[gridNumber] ?? -3.0;
      if (currentGridMax > -3.0) continue;
      const cardinalOffsets = <int>[-26, 26, -1, 1];
      var isolatedLowGrid = true;
      for (final offset in cardinalOffsets) {
        final neighborMax = gridDetectionMax[gridNumber + offset] ?? -3.0;
        if (neighborMax >= -2.0) {
          isolatedLowGrid = false;
          break;
        }
      }
      if (!isolatedLowGrid) continue;

      for (final record in gridRecords) {
        final code = record.descriptor.code;
        final previousState = state.scratchDetectionPermissionState[code] ?? 0;
        if (previousState <= 0) continue;
        if (previousState == 5) continue;
        if (_kotoho7GridLongRiseChangeValue(record, observedAt: observedAt) <=
            0.0) {
          continue;
        }
        final minimumPointCount = _kotoho7ScratchThresholdDigit(
          _kotoho7ScratchThresholdCode(record),
          3,
        );
        if (minimumPointCount >= 4) continue;
        final ownConverted = _kotoho7KaLevelToContinuousShindo(
          state.scratchDetectionPermittedShindo[code],
        );
        if (ownConverted == null) continue;
        var neighborPermittedSum = 3.0;
        var inspectedNeighborCount = 0;
        for (final neighbor in _kotoho7Nearest7Records(record, records)) {
          final converted = _kotoho7KaLevelToContinuousShindo(
            state.scratchDetectionPermittedShindo[neighbor
                .record
                .descriptor
                .code],
          );
          if (converted != null) neighborPermittedSum += converted;
          inspectedNeighborCount += 1;
          if (inspectedNeighborCount >= 3) break;
        }
        if (ownConverted * 3.0 >= neighborPermittedSum) continue;

        _setKotoho7DetectionPermissionState(
          state,
          code,
          5,
          reason: 'scratch_permission_grid_permission',
          observedAt: observedAt,
          forced: false,
        );
        if (5 > previousState) {
          promotedCount += 1;
        } else if (5 < previousState) {
          demotedCount += 1;
        } else {
          refreshedCount += 1;
        }
        _incrementKotoho7Reason(
          reasonCounts,
          'scratch_permission_grid_permission',
        );
      }
    }

    return (
      promotedCount: promotedCount,
      demotedCount: demotedCount,
      refreshedCount: refreshedCount,
    );
  }

  Map<int, double> _kotoho7GridDetectionMaxProxy(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
  }) {
    state.scratchGridDetectionMaxKeep
      ..clear()
      ..addEntries(
        _kotoho7ScratchPopulatedGridNumbers.map((gridNumber) {
          return MapEntry(
            gridNumber,
            state.scratchGridDetectionMax[gridNumber] ?? -3.0,
          );
        }),
      );
    state.scratchGridDetectionMax.removeWhere(
      (gridNumber, _) =>
          !_kotoho7ScratchStationIndicesByGridNumber.containsKey(gridNumber),
    );
    for (final gridNumber in _kotoho7ScratchPopulatedGridNumbers) {
      state.scratchGridDetectionMax[gridNumber] = -3.0;
    }

    for (final record in records) {
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      if (currentShindo == null || currentShindo <= 0.0) continue;
      final permissionState =
          state.scratchDetectionPermissionState[record.descriptor.code] ?? 0;
      if (permissionState < 4) continue;

      final triggerAt =
          state.scratchDetectionTriggerAt[record.descriptor.code] ??
          record.firstTriggerAt ??
          record.firstRiseAt;
      final triggerAgeSeconds = triggerAt == null
          ? double.infinity
          : observedAt.difference(triggerAt).inMilliseconds / 1000.0;
      final gridNumber = _kotoho7GridNumber(record);
      final previous = state.scratchGridDetectionMax[gridNumber] ?? -3.0;

      if (currentShindo > 6.0) {
        final isFreshEnough =
            (currentShindo > 9.0 && triggerAgeSeconds < 400.0) ||
            triggerAgeSeconds < 30.0;
        if (!isFreshEnough) continue;
        final converted = _kotoho7KaLevelToGridDetectionMax(currentShindo);
        if (converted == null) continue;
        if (previous < converted) {
          state.scratchGridDetectionMax[gridNumber] = converted;
        }
      } else {
        final candidate = -2.0 + (triggerAgeSeconds < 15.0 ? 1.0 : 0.0);
        if (previous < candidate) {
          final keep = state.scratchGridDetectionMaxKeep[gridNumber] ?? -3.0;
          if (keep == -3.0) {
            state.scratchGridDetectionMax[gridNumber] = -1.0;
          } else if (keep == -2.0) {
            state.scratchGridDetectionMax[gridNumber] = -2.0;
          } else {
            state.scratchGridDetectionMax[gridNumber] = candidate;
          }
        }
      }
    }
    return state.scratchGridDetectionMax;
  }

  ({bool qualifies, int currentPointCount, int risingPointCount, double score})
  _kotoho7GridLongRiseProxy(
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
  }) {
    var currentPointCount = 0;
    var risingPointCount = 0;
    var scoreNumerator = 0.0;
    for (final record in records) {
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      if (currentShindo == null || currentShindo <= 0.0) continue;
      currentPointCount += 1;
      final longRise = _kotoho7GridLongRiseChangeValue(
        record,
        observedAt: observedAt,
      );
      if (longRise <= 0.0) continue;
      risingPointCount += 1;
      if (_kotoho7ImmediateChangeSpeedValue(record, observedAt: observedAt) >
          0.0) {
        scoreNumerator += 0.5;
      }
      final thresholdCode = _kotoho7ScratchThresholdCode(record);
      final upwardLimitDigit = _kotoho7ScratchThresholdDigit(thresholdCode, 1);
      final thresholdDigit = _kotoho7ScratchThresholdDigit(thresholdCode, 2);
      scoreNumerator += upwardLimitDigit > 3
          ? 5.0 / (upwardLimitDigit + 6.0)
          : 0.56;
      scoreNumerator += thresholdDigit > 2 ? 1.0 / (thresholdDigit + 3.0) : 0.4;
    }
    final score = currentPointCount == 0
        ? 0.0
        : scoreNumerator / currentPointCount;
    return (
      qualifies: risingPointCount > 5 && score > 0.3,
      currentPointCount: currentPointCount,
      risingPointCount: risingPointCount,
      score: score,
    );
  }

  ({int state, String reason, bool refreshTriggerTime})
  _kotoho7NextDetectionPermissionState({
    required int previousState,
    required double currentShindo,
    required double convertedShindo,
    required bool rising,
    required double changeSpeed,
    required bool fastRiseEnergyExceeded,
    required double oneSecondHistoryRise,
    required int nearest7CurrentSupport,
    required double? nearest7AverageConvertedShindo,
    required int nearest5PermissionCount,
    required int nearest5HighShindoCount,
    required double? nearest5AverageConvertedShindo,
    required _Kotoho7DetectionAcceleration acceleration,
    required double triggerAgeSeconds,
    required double scratchRealtimeDetectedMaxShindo,
  }) {
    final multiTriggerThresholdDigit = acceleration.scratchThresholdDigit;
    final singleTriggerThresholdDigit = _kotoho7ScratchThresholdDigit(
      acceleration.scratchThresholdCode,
      1,
    );
    final multiTriggerUpwardLimitDigit = _kotoho7ScratchThresholdDigit(
      acceleration.scratchThresholdCode,
      1,
    );
    final singleTriggerUpwardLimitDigit = _kotoho7ScratchThresholdDigit(
      acceleration.scratchThresholdCode,
      3,
    );
    final accelerationQualified = acceleration.qualifiesNormalPermission;
    final riseLimitAllowsMultiTrigger =
        multiTriggerUpwardLimitDigit < 4 || convertedShindo < 1.5;
    final riseLimitAllowsSingleTrigger =
        singleTriggerUpwardLimitDigit < 4 || convertedShindo < 1.5;
    final singleTriggerThreshold =
        convertedShindo > singleTriggerThresholdDigit / 20.0 ||
        changeSpeed > 0.9 + (singleTriggerThresholdDigit - 3.0) / 30.0;

    if (fastRiseEnergyExceeded) {
      return (
        state: 0,
        reason: 'scratch_permission_rise_too_fast',
        refreshTriggerTime: false,
      );
    }

    if (previousState == 0) {
      final localMean = nearest7AverageConvertedShindo;
      if (localMean != null && convertedShindo - localMean < 0.5) {
        return (
          state: 1,
          reason: 'scratch_permission_not_much_higher_than_neighbors',
          refreshTriggerTime: true,
        );
      }
      if (singleTriggerThreshold) {
        return (
          state: 1,
          reason: 'scratch_permission_initial_point_seen',
          refreshTriggerTime: true,
        );
      }
      return (
        state: previousState,
        reason: 'scratch_permission_initial_low_keep',
        refreshTriggerTime: false,
      );
    }

    if (previousState == 1 || previousState == 2) {
      if (convertedShindo > singleTriggerThresholdDigit / 20.0 ||
          (rising && riseLimitAllowsSingleTrigger)) {
        return (
          state: 3,
          reason: 'scratch_permission_single_normal_trigger',
          refreshTriggerTime: true,
        );
      }
      if (rising && previousState == 1) {
        return (
          state: 2,
          reason: 'scratch_permission_single_auxiliary_trigger',
          refreshTriggerTime: false,
        );
      }
      if (!rising && previousState == 2) {
        return (
          state: 1,
          reason: 'scratch_permission_single_auxiliary_release',
          refreshTriggerTime: false,
        );
      }
      return (
        state: previousState,
        reason: 'scratch_permission_low_keep',
        refreshTriggerTime: false,
      );
    }

    if (previousState > 4 &&
        triggerAgeSeconds > 400.0 &&
        convertedShindo > 0.45 &&
        rising) {
      return (
        state: 5,
        reason: 'scratch_permission_time_over_rising',
        refreshTriggerTime: true,
      );
    }

    if (previousState >= 4) {
      final maxShindoForTimeout = scratchRealtimeDetectedMaxShindo.isFinite
          ? scratchRealtimeDetectedMaxShindo
          : -3.0;
      final timeoutSeconds =
          120.0 + math.pow(10.0, 1.0 + maxShindoForTimeout / 1.2).toDouble();
      if (triggerAgeSeconds > timeoutSeconds) {
        return (
          state: 1,
          reason: 'scratch_permission_max_shindo_elapsed',
          refreshTriggerTime: false,
        );
      }
    }

    if (previousState == 6 &&
        rising &&
        riseLimitAllowsMultiTrigger &&
        (acceleration.recentPermittedCount > 0 || accelerationQualified)) {
      return (
        state: 5,
        reason: 'scratch_permission_state6_rerise_supported',
        refreshTriggerTime: true,
      );
    }
    if (previousState >= 5) {
      if (triggerAgeSeconds > 10.0 &&
          !rising &&
          convertedShindo < -1.75 + singleTriggerThresholdDigit / 18.0) {
        return (
          state: 1,
          reason: 'scratch_permission_high_state_low_after_10s',
          refreshTriggerTime: false,
        );
      }
      if (rising) {
        return (
          state: previousState,
          reason: 'scratch_permission_existing_high_rise_refresh',
          refreshTriggerTime: previousState != 6,
        );
      }
      return (
        state: previousState,
        reason: 'scratch_permission_existing_high_keep',
        refreshTriggerTime: false,
      );
    }

    if (previousState < 5 &&
        previousState > 0 &&
        rising &&
        riseLimitAllowsMultiTrigger) {
      if (acceleration.recentPermittedCount > 2) {
        return (
          state: 5,
          reason: 'scratch_permission_many_recent_triggers',
          refreshTriggerTime: true,
        );
      }
      if (acceleration.recentPermittedCount > 0 &&
          acceleration.highNeighborCount > 0) {
        return (
          state: 5,
          reason: 'scratch_permission_accelerating_near_detected_point',
          refreshTriggerTime: true,
        );
      }
    }
    if (previousState == 4 &&
        nearest5PermissionCount > 0 &&
        riseLimitAllowsMultiTrigger) {
      return (
        state: 5,
        reason: 'scratch_permission_state4_near_permission',
        refreshTriggerTime: true,
      );
    }
    if (previousState < 5 &&
        convertedShindo > -1.0 &&
        riseLimitAllowsMultiTrigger &&
        nearest5AverageConvertedShindo != null &&
        convertedShindo < nearest5AverageConvertedShindo + 1.6 &&
        (nearest5PermissionCount > 2 ||
            (nearest5PermissionCount > 0 && nearest5HighShindoCount > 4))) {
      return (
        state: 5,
        reason: 'scratch_permission_many_neighbors_permitted_or_shaking',
        refreshTriggerTime: true,
      );
    }
    if ((previousState == 3 || previousState == 4) &&
        triggerAgeSeconds > 20.0 + 0.25 * acceleration.thirdNearestDistanceKm) {
      final stillAboveThreshold =
          convertedShindo > multiTriggerThresholdDigit / 20.0 ||
          changeSpeed > 0.8 + multiTriggerThresholdDigit / 20.0;
      return (
        state: stillAboveThreshold ? 0 : 1,
        reason: stillAboveThreshold
            ? 'scratch_permission_first_trigger_timeout_forbid'
            : 'scratch_permission_first_trigger_timeout',
        refreshTriggerTime: false,
      );
    }
    if ((previousState == 3 || previousState == 4) && accelerationQualified) {
      return (
        state: 5,
        reason: 'scratch_permission_normal_permission',
        refreshTriggerTime: true,
      );
    }
    if ((previousState == 3 || previousState == 4) &&
        !acceleration.hasEnoughObservedPoints) {
      return (
        state: 0,
        reason: 'scratch_permission_no_time_area_points',
        refreshTriggerTime: false,
      );
    }
    if (previousState == 4 && acceleration.timeAreaCount < 7) {
      return (
        state: 0,
        reason: 'scratch_permission_one_point_detection_timeout',
        refreshTriggerTime: false,
      );
    }
    if (previousState == 3 &&
        singleTriggerThresholdDigit < 4 &&
        (acceleration.thirdNearestDistanceKm < 40.0 ||
            triggerAgeSeconds > 10.0) &&
        oneSecondHistoryRise > 0.3) {
      return (
        state: 3,
        reason: 'scratch_permission_single_normal_trigger_refresh',
        refreshTriggerTime: true,
      );
    }
    if (previousState < 4 &&
        nearest7CurrentSupport <= 1 &&
        changeSpeed > 1.5 &&
        convertedShindo >= 1.5 &&
        convertedShindo < 5.5) {
      return (
        state: 4,
        reason: 'scratch_permission_one_point_provisional',
        refreshTriggerTime: true,
      );
    }
    return (
      state: previousState,
      reason: 'scratch_permission_low_keep',
      refreshTriggerTime: false,
    );
  }

  ({int state, String reason, bool refreshTriggerTime})?
  _kotoho7JsCircleEewPermission(
    Map<String, Object?> requestMetadata,
    SeismicStationEventRecord record,
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
    required int previousState,
    required double currentShindo,
    required double convertedShindo,
    required double triggerAgeSeconds,
    required int thresholdDigit,
    required int nearest7CurrentSupport,
  }) {
    if (requestMetadata['kotoho7_use_js_eew_bridge'] != true) return null;
    if (previousState != 3) return null;
    if (!_kotoho7JsEewMetadataPresent(requestMetadata)) {
      requestMetadata['kotoho7_js_eew_bridge_last_error'] =
          'missing_eew_metadata';
      return null;
    }
    final stationIndex = _kotoho7NiedStationIndexByCode[record.descriptor.code];
    if (stationIndex == null) {
      requestMetadata['kotoho7_js_eew_bridge_last_error'] =
          'station_not_in_scratch_table:${record.descriptor.code}';
      return null;
    }
    final bridgeMetadata = _kotoho7JsEewBridgeMetadata(requestMetadata);
    final stationDistances = _kotoho7JsEewStationDistances(
      bridgeMetadata,
      record,
    );
    final result = Kotoho7JsEewBridge.circleTrigger(
      Kotoho7JsCircleTriggerInput(
        metadata: bridgeMetadata,
        scriptPath: requestMetadata['kotoho7_js_eew_bridge_script_path']
            ?.toString(),
        stationIndex1: stationIndex + 1,
        currentState: previousState,
        threshold: thresholdDigit,
        pointCount: nearest7CurrentSupport,
        shindo: convertedShindo,
        triggerAgeSeconds: triggerAgeSeconds,
        stationDistances: stationDistances,
      ),
    );
    requestMetadata['kotoho7_js_eew_bridge_available'] = result.available;
    requestMetadata['kotoho7_js_eew_bridge_last_result'] = result.result;
    if (result.error != null) {
      requestMetadata['kotoho7_js_eew_bridge_last_error'] = result.error;
    } else {
      requestMetadata.remove('kotoho7_js_eew_bridge_last_error');
    }
    if (!result.ok || !result.promoted) return null;
    return (
      state: 5,
      reason: 'scratch_permission_circle_eew_trigger_js',
      refreshTriggerTime: false,
    );
  }

  bool _kotoho7JsEewMetadataPresent(Map<String, Object?> metadata) {
    return metadata['kotoho7_eew_slots'] is List &&
        metadata['kotoho7_eew_active_flags'] is List &&
        metadata['kotoho7_eew_extra_info'] is List;
  }

  Map<String, Object?> _kotoho7JsEewBridgeMetadata(
    Map<String, Object?> metadata,
  ) {
    return <String, Object?>{
      'kotoho7_eew_slots': _listObject(metadata['kotoho7_eew_slots']),
      'kotoho7_eew_active_flags': _listObject(
        metadata['kotoho7_eew_active_flags'],
      ),
      'kotoho7_eew_extra_info': _listObject(metadata['kotoho7_eew_extra_info']),
      'kotoho7_eew_global_active':
          metadata['kotoho7_eew_global_active'] ??
          metadata['kotoho7_eew_active_global'] ??
          0,
    };
  }

  List<Map<String, Object?>> _kotoho7JsEewStationDistances(
    Map<String, Object?> bridgeMetadata,
    SeismicStationEventRecord record,
  ) {
    final slots = _listObject(bridgeMetadata['kotoho7_eew_slots']);
    final result = <Map<String, Object?>>[];
    for (var slot = 0; slot < 10; slot++) {
      final base = slot * 14;
      final active = _numberAt(slots, base);
      if (active <= 0) continue;
      final longitude = _numberAt(slots, base + 5);
      final latitude = _numberAt(slots, base + 6);
      if (!latitude.isFinite || !longitude.isFinite) continue;
      final distanceKm = _haversineKm(
        record.descriptor.coordinate.latitude,
        record.descriptor.coordinate.longitude,
        latitude,
        longitude,
      );
      result.add({
        'stationIndex1':
            (_kotoho7NiedStationIndexByCode[record.descriptor.code] ?? -1) + 1,
        'slotIndex1': slot + 1,
        'distanceKm': distanceKm,
      });
    }
    return result;
  }

  List<Object?> _listObject(Object? value) {
    if (value is List) return value.cast<Object?>();
    return const <Object?>[];
  }

  double _numberAt(List<Object?> values, int zeroBasedIndex) {
    if (zeroBasedIndex < 0 || zeroBasedIndex >= values.length) {
      return double.nan;
    }
    final value = values[zeroBasedIndex];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? double.nan;
    return double.nan;
  }

  void _updateKotoho7MaxShindoCaches(
    _Kotoho7HypState state,
    String stationCode, {
    required double currentShindo,
    required int permissionState,
    required DateTime observedAt,
  }) {
    final previousStationMax = state.scratchStationMaxShindoValue[stationCode];
    if (previousStationMax == null || currentShindo > previousStationMax) {
      state.scratchStationMaxShindoValue[stationCode] = currentShindo;
      state.scratchStationMaxShindoUpdatedAt[stationCode] = observedAt;
    }
    state.scratchDetectionPermittedShindo[stationCode] =
        currentShindo > 0.0 && permissionState >= 4
        ? currentShindo
        : currentShindo < 7.0
        ? currentShindo
        : 6.0;
  }

  double _kotoho7ScratchRealtimeDetectedMaxShindo100(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
  }) {
    var maxShindo = -3.0;
    for (final record in records) {
      final permissionState =
          state.scratchDetectionPermissionState[record.descriptor.code] ?? 0;
      if (permissionState < 4) continue;
      final value = _kotoho7CurrentConvertedShindo(
        record,
        observedAt: observedAt,
      );
      if (value == null) continue;
      if (value > maxShindo) maxShindo = value;
    }
    return maxShindo;
  }

  void _setKotoho7DetectionPermissionState(
    _Kotoho7HypState state,
    String stationCode,
    int nextState, {
    required String reason,
    required DateTime observedAt,
    required bool forced,
  }) {
    final previous = state.scratchDetectionPermissionState[stationCode] ?? 0;
    state.scratchDetectionPermissionState[stationCode] = nextState;
    state.scratchDetectionPermissionReason[stationCode] = reason;
    // Scratch `点許可状態更新` refreshes `ten c:揺れ検出トリガー時間`
    // when `強制更新`, or when `内容 > 1 && 内容 != 6`, or when the previous
    // trigger time is empty/zero.
    if (forced ||
        (nextState > 1 && nextState != 6) ||
        !state.scratchDetectionTriggerAt.containsKey(stationCode)) {
      state.scratchDetectionTriggerAt[stationCode] = observedAt;
    }
    if (nextState == 0 && previous > 0) {
      state.scratchDetectionPermissionReason[stationCode] = reason;
    }
  }

  int _kotoho7Nearest7CurrentSupportCount(
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool, {
    required DateTime observedAt,
  }) {
    var supportCount = 0;
    for (final neighbor in _kotoho7Nearest7Records(center, pool)) {
      if (_kotoho7CurrentShindoIndex(neighbor.record, observedAt: observedAt) !=
          null) {
        supportCount += 1;
      }
    }
    return supportCount;
  }

  double? _kotoho7NearestConvertedAverageShindo(
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool, {
    required DateTime observedAt,
    required int maxCount,
  }) {
    var sum = 0.0;
    var count = 0;
    for (final neighbor in _kotoho7Nearest7Records(center, pool)) {
      final value = _kotoho7CurrentConvertedShindo(
        neighbor.record,
        observedAt: observedAt,
      );
      if (value == null) continue;
      sum += value;
      count += 1;
      if (count >= maxCount) break;
    }
    if (count == 0) return null;
    return sum / count;
  }

  ({
    int permissionState5Count,
    int highShindoCount,
    double? averageConvertedShindo,
  })
  _kotoho7Nearest5MultiTriggerSummary(
    _Kotoho7HypState state,
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool, {
    required DateTime observedAt,
  }) {
    var permissionState5Count = 0;
    var highShindoCount = 0;
    var convertedSum = 0.0;
    var convertedCount = 0;
    var inspectedCount = 0;
    for (final neighbor in _kotoho7Nearest7Records(center, pool)) {
      final record = neighbor.record;
      final code = record.descriptor.code;
      final permissionState = state.scratchDetectionPermissionState[code] ?? 0;
      if (permissionState > 4) permissionState5Count += 1;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      if (currentShindo != null && currentShindo > 5.0) {
        highShindoCount += 1;
      }
      final converted = _kotoho7CurrentConvertedShindo(
        record,
        observedAt: observedAt,
      );
      if (converted != null) {
        convertedSum += converted;
        convertedCount += 1;
      }
      inspectedCount += 1;
      if (inspectedCount >= 5) break;
    }
    return (
      permissionState5Count: permissionState5Count,
      highShindoCount: highShindoCount,
      averageConvertedShindo: convertedCount == 0
          ? null
          : convertedSum / convertedCount,
    );
  }

  _Kotoho7DetectionAcceleration _kotoho7DetectionAccelerationProxy(
    _Kotoho7HypState state,
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool, {
    required DateTime observedAt,
    required double currentShindo,
    required double convertedShindo,
    required bool rising,
  }) {
    final centerThresholdCode = _kotoho7ScratchThresholdCode(center);
    final minimumPointCount = _kotoho7ScratchThresholdDigit(
      centerThresholdCode,
      3,
    );
    final thresholdDigit = _kotoho7ScratchThresholdDigit(
      centerThresholdCode,
      2,
    );
    final thirdNearestDistanceKm = _kotoho7ThirdNearestDistanceKm(center, pool);
    final triggerAt =
        state.scratchDetectionTriggerAt[center.descriptor.code] ??
        center.firstTriggerAt ??
        center.firstRiseAt ??
        observedAt;
    final elapsedSeconds = math.max(
      0.0,
      observedAt.difference(triggerAt).inMilliseconds / 1000.0,
    );
    final upperDistanceKm = 12.0 * (elapsedSeconds + 4.0);
    final lowerDistanceKm = math.max(0.0, 5.0 * elapsedSeconds - 2.0);
    var timeAreaCount = 0;
    var closeTimeAreaCount = 0;
    var permittedCount = 0;
    var recentPermittedCount = 0;
    var highNeighborCount = 0;
    var risingNeighborCount = 0;
    var ngRejectedCount = 0;
    var score = 0.0;
    var contributionCount = 0;
    var line1Slope = 0.0;
    var line1UpperSide = false;
    double? line1BaseX;
    double? line1BaseY;
    var line2Slope = 0.0;
    var line2UpperSide = false;
    double? line2BaseX;
    double? line2BaseY;

    void addAcceleration(double value) {
      // Scratch `加速追加 %s %s` is intentionally just:
      // `@1 c:揺れ検出用[4] += 値`.
      if (value.isFinite && value > 0.0) {
        score += value;
        contributionCount += 1;
      }
    }

    var neighborOffset = 0;
    for (final neighbor in _kotoho7Nearest7Records(center, pool)) {
      neighborOffset += 1;
      final neighborRecord = neighbor.record;
      final neighborCode = neighborRecord.descriptor.code;
      final neighborDistanceKm = neighbor.distanceKm;
      if (neighborDistanceKm <= lowerDistanceKm) {
        continue;
      }
      timeAreaCount += 1;
      if (neighborDistanceKm >= upperDistanceKm) {
        continue;
      }
      closeTimeAreaCount += 1;

      final neighborPermission =
          state.scratchDetectionPermissionState[neighborCode] ?? 0;
      if (neighborPermission > 1) permittedCount += 1;
      final neighborTriggerAt =
          state.scratchDetectionTriggerAt[neighborCode] ??
          neighborRecord.firstTriggerAt ??
          neighborRecord.firstRiseAt;
      final neighborTriggerAgeSeconds = neighborTriggerAt == null
          ? double.infinity
          : observedAt.difference(neighborTriggerAt).inMilliseconds / 1000.0;
      final recentPermitted =
          neighborPermission > 2 &&
          neighborTriggerAgeSeconds >= 0.0 &&
          neighborTriggerAgeSeconds < 4.0;
      if (recentPermitted) recentPermittedCount += 1;

      final neighborShindo = _kotoho7CurrentShindoIndex(
        neighborRecord,
        observedAt: observedAt,
      );
      if (neighborShindo == null) continue;
      if (neighborShindo > 5.0) highNeighborCount += 1;

      final neighborRising = _kotoho7ChangeSpeedPositive(
        neighborRecord,
        observedAt: observedAt,
      );
      if (neighborRising) risingNeighborCount += 1;

      var geometryAccepted = neighborPermission != 0;
      final forceAcceptGeometry =
          line1BaseX == null ||
          (neighborShindo > 8.0 && neighborTriggerAgeSeconds < 1.5) ||
          neighborShindo > 12.0;
      if (geometryAccepted && !forceAcceptGeometry) {
        geometryAccepted = _kotoho7ScratchNgAccelerationAccepted(
          neighborRecord,
          slope: line1Slope,
          upperSide: line1UpperSide,
          baseX: line1BaseX,
          baseY: line1BaseY,
        );
        if (geometryAccepted && line2BaseX != null) {
          geometryAccepted = _kotoho7ScratchNgAccelerationAccepted(
            neighborRecord,
            slope: line2Slope,
            upperSide: line2UpperSide,
            baseX: line2BaseX,
            baseY: line2BaseY,
          );
        }
      }
      if (!geometryAccepted) {
        ngRejectedCount += 1;
      }

      if (geometryAccepted) {
        final neighborChangeSpeed = _kotoho7ChangeSpeedValue(
          neighborRecord,
          observedAt: observedAt,
        );
        if (neighborChangeSpeed > 0.0) {
          final atanDegrees =
              math.atan((neighborDistanceKm - 10.0) / 10.0) * 180.0 / math.pi;
          addAcceleration(
            0.07 +
                (1.0 + (convertedShindo > 0.4 ? 1.0 / 3.0 : 0.0)) *
                    ((1.05 - ((thresholdDigit - 3.0) / 15.0)) *
                        ((neighborChangeSpeed / 9.0) *
                            ((atanDegrees + 45.0) / 80.0))),
          );
          final neighborConverted = _kotoho7CurrentConvertedShindo(
            neighborRecord,
            observedAt: observedAt,
          );
          if (neighborConverted != null) {
            final extra = math.sqrt(
              math.sqrt(math.max(0.0, neighborConverted + 3.0)),
            );
            if (extra > 1.25) addAcceleration(extra / 20.0);
          }
        }

        if (elapsedSeconds < 2.0 && neighborTriggerAgeSeconds < 4.0) {
          if (neighborOffset < 3 &&
              neighborPermission > 2 &&
              neighborShindo < currentShindo + 2.0 &&
              (neighborRising || neighborShindo > 8.0) &&
              neighborShindo > 5.0) {
            addAcceleration(0.25);
            if (neighborShindo > 9.0) addAcceleration(0.2);
          } else if (neighborOffset < 5 &&
              neighborPermission > 2 &&
              convertedShindo > -0.9 &&
              neighborShindo > 5.0) {
            addAcceleration(0.15);
          }
        } else if (elapsedSeconds < 4.0 &&
            neighborTriggerAgeSeconds < 4.0 &&
            neighborOffset < 5 &&
            neighborPermission > 2 &&
            convertedShindo > -0.9 &&
            neighborShindo > 5.0) {
          addAcceleration(0.1);
        }

        if (line1BaseX == null && elapsedSeconds < 5.0) {
          final permittedShindo =
              state.scratchDetectionPermittedShindo[neighborCode] ??
              double.negativeInfinity;
          final maxUpdatedAt =
              state.scratchStationMaxShindoUpdatedAt[neighborCode];
          final maxUpdateAgeSeconds = maxUpdatedAt == null
              ? double.infinity
              : observedAt.difference(maxUpdatedAt).inMilliseconds / 1000.0;
          if (permittedShindo > 7.0) {
            addAcceleration(0.5);
          } else {
            final neighborThreshold = _kotoho7ScratchThresholdDigit(
              _kotoho7ScratchThresholdCode(neighborRecord),
              1,
            );
            if (neighborThreshold < 6 && maxUpdateAgeSeconds < 6.0) {
              if (neighborShindo > 9.0) {
                addAcceleration(0.15);
              } else if (neighborShindo > 5.0) {
                addAcceleration(0.05);
              }
            }
          }
        }
      }

      if (neighborDistanceKm < 50.0 && !neighborRising) {
        final line = _kotoho7ScratchNgLine(center, neighborRecord);
        if (line != null) {
          if (line1BaseX == null) {
            line1Slope = line.slope;
            line1UpperSide = line.upperSide;
            line1BaseX = line.baseX;
            line1BaseY = line.baseY;
          } else if (line2BaseX == null) {
            line2Slope = line.slope;
            line2UpperSide = line.upperSide;
            line2BaseX = line.baseX;
            line2BaseY = line.baseY;
          }
        }
      }
    }

    final threshold = 0.3 + closeTimeAreaCount / 22.5;
    final enoughAcceleration = score > threshold && contributionCount >= 1;
    final enoughObservedPoints =
        !((timeAreaCount < 5 &&
                _kotoho7ThirdNearestDistanceKm(center, pool) < 60.0) ||
            timeAreaCount < 2);
    final enoughPermittedPoints = (minimumPointCount - 2) < permittedCount;
    final qualifiesNormalPermission =
        enoughObservedPoints &&
        enoughPermittedPoints &&
        enoughAcceleration &&
        (rising || convertedShindo >= -0.35 || currentShindo >= 8.0);
    final reason = qualifiesNormalPermission
        ? 'scratch_c_yure_detection_normal_permission'
        : !enoughObservedPoints
        ? 'scratch_c_yure_detection_no_time_area_points'
        : !enoughPermittedPoints
        ? 'scratch_c_yure_detection_not_enough_permitted_points'
        : 'scratch_c_yure_detection_acceleration_below_threshold';
    return _Kotoho7DetectionAcceleration(
      score: score,
      threshold: threshold,
      timeAreaCount: timeAreaCount,
      closeTimeAreaCount: closeTimeAreaCount,
      permittedCount: permittedCount,
      minimumPointCount: minimumPointCount,
      scratchThresholdDigit: thresholdDigit,
      scratchThresholdCode: centerThresholdCode,
      thirdNearestDistanceKm: thirdNearestDistanceKm,
      recentPermittedCount: recentPermittedCount,
      highNeighborCount: highNeighborCount,
      risingNeighborCount: risingNeighborCount,
      ngRejectedCount: ngRejectedCount,
      contributionCount: contributionCount,
      hasEnoughObservedPoints: enoughObservedPoints,
      qualifiesNormalPermission: qualifiesNormalPermission,
      reason: reason,
    );
  }

  ({double slope, bool upperSide, double baseX, double baseY})?
  _kotoho7ScratchNgLine(
    SeismicStationEventRecord center,
    SeismicStationEventRecord base,
  ) {
    final centerX = _kotoho7ScratchPixelX(center);
    final centerY = _kotoho7ScratchPixelY(center);
    final baseX = _kotoho7ScratchPixelX(base);
    final baseY = _kotoho7ScratchPixelY(base);
    if (centerX == null || centerY == null || baseX == null || baseY == null) {
      return null;
    }
    final dy = baseY - centerY;
    if (dy.abs() < 1e-6) return null;
    return (
      slope: (centerX - baseX) / dy,
      upperSide: centerY < baseY,
      baseX: baseX,
      baseY: baseY,
    );
  }

  bool _kotoho7ScratchNgAccelerationAccepted(
    SeismicStationEventRecord neighbor, {
    required double slope,
    required bool upperSide,
    required double? baseX,
    required double? baseY,
  }) {
    final neighborX = _kotoho7ScratchPixelX(neighbor);
    final neighborY = _kotoho7ScratchPixelY(neighbor);
    if (baseX == null ||
        baseY == null ||
        neighborX == null ||
        neighborY == null) {
      return true;
    }
    final lineY = baseY + slope * (neighborX - baseX);
    // Scratch `NG加速` sets `多目的0 = 1` on this side of the line, and the
    // caller only adds acceleration when `多目的0 == 1`. The procedure name is
    // misleading; this predicate returns the caller's accepted/continue state.
    return upperSide ? neighborY < lineY : lineY < neighborY;
  }

  Map<String, int> _kotoho7StationPlus3SerialByCode() {
    final result = <String, int>{};
    for (final state in _states.values.toSet()) {
      if (!state.scratch43Active) continue;
      for (final code in state.assignedStationCodes) {
        final previous = result[code];
        if (previous == null || state.scratch43Serial > previous) {
          result[code] = state.scratch43Serial;
        }
      }
    }
    return result;
  }

  ({
    double multiPurpose0,
    bool shouldKeepWaitingState6,
    bool shouldPromoteToState5AndCallId3,
  })
  _kotoho7Id2ReriseScore(
    _Kotoho7HypState state,
    SeismicStationEventRecord record,
    List<SeismicStationEventRecord> pool, {
    required DateTime observedAt,
    required int currentState,
    required Map<String, int> stationPlus3SerialByCode,
    required Map<String, SeismicStationEventRecord> recordsByCode,
  }) {
    var multiPurpose0 = 0.0;
    var newerNeighborId = false;
    final currentSerial = stationPlus3SerialByCode[record.descriptor.code] ?? 0;
    for (final neighbor in _kotoho7Nearest7StationCodes(record, pool)) {
      final neighborCode = neighbor.stationCode;
      final permissionState =
          state.scratchDetectionPermissionState[neighborCode] ?? 0;
      final triggerAt = state.scratchDetectionTriggerAt[neighborCode];
      final triggerAgeSeconds = triggerAt == null
          ? double.infinity
          : observedAt.difference(triggerAt).inMilliseconds / 1000.0;
      if (triggerAgeSeconds < 5.0 &&
          (permissionState == 5 || permissionState == 6)) {
        multiPurpose0 += 10000000.0;
        if (permissionState == 5) {
          multiPurpose0 += 20000.0;
        }
      }
      final neighborRecord = recordsByCode[neighborCode];
      final neighborChangeSpeed = neighborRecord == null
          ? 0.0
          : _kotoho7ChangeSpeedValue(neighborRecord, observedAt: observedAt);
      if (neighborChangeSpeed > 0.0 && permissionState > 4) {
        multiPurpose0 += 10000.0 + neighborChangeSpeed;
        final neighborSerial = stationPlus3SerialByCode[neighborCode] ?? 0;
        if (currentSerial < neighborSerial) {
          newerNeighborId = true;
        }
      }
    }
    if (newerNeighborId) {
      return (
        multiPurpose0: double.infinity,
        shouldKeepWaitingState6: false,
        shouldPromoteToState5AndCallId3: true,
      );
    }
    final risingRemainder = multiPurpose0 % 10000.0;
    final risingBucket = ((multiPurpose0 % 100000.0) / 10000.0).floor();
    final shouldKeepWaitingState6 =
        currentState == 6 && risingRemainder > 0.5 && risingBucket > 0;
    return (
      multiPurpose0: multiPurpose0,
      shouldKeepWaitingState6: shouldKeepWaitingState6,
      shouldPromoteToState5AndCallId3:
          newerNeighborId ||
          (shouldKeepWaitingState6 && multiPurpose0 > 10000000.0),
    );
  }

  String? _kotoho7AssignedStationResetReason(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required List<SeismicStationEventRecord> allTimingUsable,
    required Map<String, SeismicStationEventRecord> recordsByCode,
    required Map<String, int> stationPlus3SerialByCode,
    required Set<String> reriseRefreshCodes,
    required Map<String, int> estimatedSlotWriteReasonCounts,
    required List<Map<String, Object?>> estimatedSlotWriteSamples,
  }) {
    final code = record.descriptor.code;
    if (!_kotoho7HasCurrentShindo(record, observedAt: observedAt)) {
      return 'scratch_reset_current_shindo_zero';
    }
    final plus1 =
        state.scratchStationFirstUseAt[code] ??
        _kotoho7StationUseTime(record, observedAt: observedAt);
    final plus2 = state.scratchStationLastUpdateAt[code] ?? plus1;
    state.scratchStationFirstUseAt[code] = plus1;
    state.scratchStationLastUpdateAt[code] = plus2;

    final currentState = _kotoho7Id2CurrentPermissionState(state, code);
    final changeSpeedPositive = _kotoho7ChangeSpeedPositive(
      record,
      observedAt: observedAt,
    );
    if (changeSpeedPositive) {
      state.scratchStationPendingCloudAt.putIfAbsent(code, () => observedAt);
      _recordKotoho7EstimatedSlotWrite(
        estimatedSlotWriteReasonCounts,
        estimatedSlotWriteSamples,
        stationCode: code,
        reason: 'scratch_id2_positive_change_set_plus5_if_empty',
        slots: const [5],
        observedAt: observedAt,
        stationState: currentState,
      );
    } else if (state.scratchStationPendingCloudAt.remove(code) != null) {
      _recordKotoho7EstimatedSlotWrite(
        estimatedSlotWriteReasonCounts,
        estimatedSlotWriteSamples,
        stationCode: code,
        reason: 'scratch_id2_no_positive_change_clear_plus5',
        slots: const [5],
        observedAt: observedAt,
        stationState: currentState,
      );
    }
    if (currentState > 3.5 && changeSpeedPositive) {
      final rerise = _kotoho7Id2ReriseScore(
        state,
        record,
        allTimingUsable,
        observedAt: observedAt,
        currentState: currentState,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      if (rerise.shouldPromoteToState5AndCallId3) {
        final refreshed =
            state.scratchStationPendingCloudAt[code] ?? observedAt;
        _setKotoho7DetectionPermissionState(
          state,
          code,
          5,
          reason: 'scratch_id2_rerise_permission_5',
          observedAt: observedAt,
          forced: false,
        );
        state.scratchStationFirstUseAt[code] = refreshed;
        state.scratchStationLastUpdateAt[code] = refreshed;
        _refreshKotoho7ShadowStationPsCacheForRecord(state, record);
        _recordKotoho7EstimatedSlotWrite(
          estimatedSlotWriteReasonCounts,
          estimatedSlotWriteSamples,
          stationCode: code,
          reason: currentState == 6
              ? 'scratch_id2_state6_rerise_refresh_plus1_plus2'
              : 'scratch_id2_state5_rerise_refresh_plus1_plus2',
          slots: const [1, 2],
          observedAt: observedAt,
          stationState: currentState,
        );
        reriseRefreshCodes.add(code);
      } else if (currentState == 6 && rerise.shouldKeepWaitingState6) {
        _setKotoho7DetectionPermissionState(
          state,
          code,
          6,
          reason: 'scratch_id2_rerise_permission_6_wait',
          observedAt: observedAt,
          forced: false,
        );
      } else if (currentState == 5) {
        state.scratchStationLastUpdateAt[code] = observedAt;
        _recordKotoho7EstimatedSlotWrite(
          estimatedSlotWriteReasonCounts,
          estimatedSlotWriteSamples,
          stationCode: code,
          reason: 'scratch_id2_state5_positive_change_update_plus2',
          slots: const [2],
          observedAt: observedAt,
          stationState: currentState,
        );
      }
    } else {
      final staleSeconds = observedAt.difference(plus2).inMilliseconds / 1000.0;
      if (staleSeconds > 200.0) return 'scratch_reset_plus2_stale_200s';
      final firstTriggerAt = record.firstTriggerAt ?? record.firstRiseAt;
      final firstTriggerAgeSeconds = firstTriggerAt == null
          ? 0.0
          : observedAt.difference(firstTriggerAt).inMilliseconds / 1000.0;
      final firstUseAgeSeconds =
          observedAt.difference(plus1).inMilliseconds / 1000.0;
      if (staleSeconds > 90.0 &&
          currentState < 2 &&
          !changeSpeedPositive &&
          firstUseAgeSeconds > 10.0 &&
          firstTriggerAgeSeconds > 10.0) {
        return 'scratch_reset_plus2_stale_90s_state_low';
      }
    }

    if (_kotoho7Id2CurrentPermissionState(state, code) == 5) {
      final updateAgeSeconds =
          observedAt
              .difference(state.scratchStationLastUpdateAt[code] ?? plus2)
              .inMilliseconds /
          1000.0;
      final distanceKm = _kotoho7StationSourceDistanceKm(state, record);
      if (updateAgeSeconds > 25.0 &&
          (updateAgeSeconds > 55.0 ||
              updateAgeSeconds > 20.0 + distanceKm / 5.0)) {
        _setKotoho7DetectionPermissionState(
          state,
          code,
          6,
          reason: 'scratch_id2_no_rise_wait_permission_6',
          observedAt: observedAt,
          forced: false,
        );
      }
    }
    return null;
  }

  _Kotoho7StationResetResult _resetKotoho7AssignedStation(
    _Kotoho7HypState state,
    String stationCode, {
    required String reason,
  }) {
    final hadPlus3 = state.assignedStationCodes.remove(stationCode);
    final hadP = state.scratchStationPArrivalSeconds.containsKey(stationCode);
    final hadS = state.scratchStationSArrivalSeconds.containsKey(stationCode);
    final hadSFlag = state.scratchStationSFlag.containsKey(stationCode);
    final hadShadowP = state.scratchShadowStationPArrivalSeconds.containsKey(
      stationCode,
    );
    final hadShadowS = state.scratchShadowStationSArrivalSeconds.containsKey(
      stationCode,
    );
    final hadShadowSFlag = state.scratchShadowStationSFlag.containsKey(
      stationCode,
    );
    final hadDistance = state.scratchStationFirstDistanceKm.containsKey(
      stationCode,
    );
    _clearKotoho7StationLifecycle(state, stationCode);
    if (hadPlus3) {
      state.scratch43AssignedCount = math.max(
        0,
        state.scratch43AssignedCount - 1,
      );
    }
    return _Kotoho7StationResetResult(
      reason: reason,
      negativeCountDelta: hadPlus3 ? -1 : 0,
      clearedPlus3: hadPlus3,
      clearedPsCache:
          hadP ||
          hadS ||
          hadSFlag ||
          hadShadowP ||
          hadShadowS ||
          hadShadowSFlag,
      clearedDistance: hadDistance,
    );
  }

  bool _removeKotoho7StationMembershipForId3Reregister(
    _Kotoho7HypState state,
    String stationCode,
  ) {
    final removed = state.assignedStationCodes.remove(stationCode);
    if (!removed) return false;
    state.scratch43AssignedCount = math.max(
      0,
      state.scratch43AssignedCount - 1,
    );
    state.scratchStationPArrivalSeconds.remove(stationCode);
    state.scratchStationSArrivalSeconds.remove(stationCode);
    state.scratchStationSFlag.remove(stationCode);
    state.scratchShadowStationPArrivalSeconds.remove(stationCode);
    state.scratchShadowStationSArrivalSeconds.remove(stationCode);
    state.scratchShadowStationSFlag.remove(stationCode);
    state.scratchStationFirstDistanceKm.remove(stationCode);
    _scratchGridByNumber.removeWhere(
      (_, entry) => entry.stationCode == stationCode,
    );
    return true;
  }

  void _initializeKotoho7StationLifecycle(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    DateTime? stationUseAtOverride,
  }) {
    final code = record.descriptor.code;
    final useAt =
        stationUseAtOverride ??
        _kotoho7StationUseTime(record, observedAt: observedAt);
    state.scratchStationFirstUseAt[code] = useAt;
    state.scratchStationLastUpdateAt[code] = useAt;
    state.scratchStationPermissionState[code] =
        state.scratchDetectionPermissionState[code] ?? 0;
  }

  void _clearKotoho7StationLifecycle(
    _Kotoho7HypState state,
    String stationCode,
  ) {
    state.scratchStationFirstUseAt.remove(stationCode);
    state.scratchStationLastUpdateAt.remove(stationCode);
    state.scratchStationPermissionState.remove(stationCode);
    state.scratchStationPArrivalSeconds.remove(stationCode);
    state.scratchStationSArrivalSeconds.remove(stationCode);
    state.scratchStationSFlag.remove(stationCode);
    state.scratchShadowStationPArrivalSeconds.remove(stationCode);
    state.scratchShadowStationSArrivalSeconds.remove(stationCode);
    state.scratchShadowStationSFlag.remove(stationCode);
    state.scratchStationFirstDistanceKm.remove(stationCode);
    _scratchGridByNumber.removeWhere(
      (_, entry) => entry.stationCode == stationCode,
    );
  }

  void _invalidateKotoho7SourceState(
    _Kotoho7HypState state, {
    required String reason,
    required DateTime observedAt,
  }) {
    state
      ..scratch43Active = false
      ..scratch43InactiveReason = reason
      ..scratch43InactiveAt = observedAt
      ..scratch43SingleStationGraceUntil = null
      ..assignedStationCodes.clear()
      ..scratchStationFirstUseAt.clear()
      ..scratchStationLastUpdateAt.clear()
      ..scratchStationPendingCloudAt.clear()
      ..scratchStationPermissionState.clear()
      ..scratchStationPArrivalSeconds.clear()
      ..scratchStationSArrivalSeconds.clear()
      ..scratchStationSFlag.clear()
      ..scratchShadowStationPArrivalSeconds.clear()
      ..scratchShadowStationSArrivalSeconds.clear()
      ..scratchShadowStationSFlag.clear()
      ..scratchStationFirstDistanceKm.clear()
      ..scratch43LastExpireWindowSeconds = null
      ..scratch43LastGridPresenceCount = 0
      ..scratch43LastGridPresenceDisappearedAgeSeconds = null
      ..scratch43LastMaxCurrentShindoIndex = null
      ..scratch43PreviousMaxCurrentShindoIndex = null
      ..scratch43AssignedCount = 0
      ..scratch43MaxFirstStationDistanceKm = 0
      ..scratch43MaxSourceDistanceKm = 0.0;
    _scratchGridByNumber.removeWhere(
      (_, entry) => identical(entry.state, state),
    );
  }

  void _copyKotoho7StationLifecycleMetadata({
    required _Kotoho7HypState target,
    required _Kotoho7HypState source,
  }) {
    for (final entry in source.scratchStationFirstUseAt.entries) {
      target.scratchStationFirstUseAt.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in source.scratchStationLastUpdateAt.entries) {
      final current = target.scratchStationLastUpdateAt[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        target.scratchStationLastUpdateAt[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchStationPendingCloudAt.entries) {
      final current = target.scratchStationPendingCloudAt[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        target.scratchStationPendingCloudAt[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchStationPermissionState.entries) {
      target.scratchStationPermissionState.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchDetectionPermissionState.entries) {
      target.scratchDetectionPermissionState.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchDetectionTriggerAt.entries) {
      final current = target.scratchDetectionTriggerAt[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        target.scratchDetectionTriggerAt[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchDetectionPermissionReason.entries) {
      target.scratchDetectionPermissionReason.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchDetectionAccelerationScore.entries) {
      target.scratchDetectionAccelerationScore.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry
        in source.scratchDetectionAccelerationTimeAreaCount.entries) {
      target.scratchDetectionAccelerationTimeAreaCount.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchDetectionAccelerationReason.entries) {
      target.scratchDetectionAccelerationReason.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchDetectionPermittedShindo.entries) {
      target.scratchDetectionPermittedShindo.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchStationMaxShindoValue.entries) {
      final current = target.scratchStationMaxShindoValue[entry.key];
      if (current == null || entry.value > current) {
        target.scratchStationMaxShindoValue[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchStationMaxShindoUpdatedAt.entries) {
      final current = target.scratchStationMaxShindoUpdatedAt[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        target.scratchStationMaxShindoUpdatedAt[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchGridDetectionMax.entries) {
      final current = target.scratchGridDetectionMax[entry.key];
      if (current == null || entry.value > current) {
        target.scratchGridDetectionMax[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchGridDetectionMaxKeep.entries) {
      final current = target.scratchGridDetectionMaxKeep[entry.key];
      if (current == null || entry.value > current) {
        target.scratchGridDetectionMaxKeep[entry.key] = entry.value;
      }
    }
    for (final entry in source.scratchStationPArrivalSeconds.entries) {
      target.scratchStationPArrivalSeconds.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchStationSArrivalSeconds.entries) {
      target.scratchStationSArrivalSeconds.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchStationSFlag.entries) {
      target.scratchStationSFlag.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in source.scratchShadowStationPArrivalSeconds.entries) {
      target.scratchShadowStationPArrivalSeconds.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchShadowStationSArrivalSeconds.entries) {
      target.scratchShadowStationSArrivalSeconds.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchShadowStationSFlag.entries) {
      target.scratchShadowStationSFlag.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    for (final entry in source.scratchStationFirstDistanceKm.entries) {
      target.scratchStationFirstDistanceKm.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
  }

  DateTime _kotoho7StationUseTime(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    return record.firstTriggerAt ??
        record.firstRiseAt ??
        record.firstObservedAt;
  }

  bool _kotoho7HasCurrentShindo(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    return _kotoho7CurrentShindoIndex(record, observedAt: observedAt) != null;
  }

  double? _kotoho7CurrentShindoIndex(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    final latest = record.observationHistory.latest;
    if (latest != null) {
      final ageSeconds =
          observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
      if (ageSeconds <= 1.5) {
        if (latest.isMissing || latest.isStale || !latest.isDecodable) {
          return null;
        }
        return _kotoho7FrameCurrentShindoIndex(
          rawLevel: latest.rawLevel,
          detectLevel: latest.detectLevel,
          value: latest.value,
        );
      }
      return null;
    }
    return _kotoho7FrameCurrentShindoIndex(
      rawLevel: record.lastRawLevel,
      detectLevel: record.lastDetectLevel,
      value: record.lastValue,
    );
  }

  double? _kotoho7CurrentConvertedShindo(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    final latest = record.observationHistory.latest;
    if (latest != null) {
      final ageSeconds =
          observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
      if (ageSeconds > 1.5 ||
          latest.isMissing ||
          latest.isStale ||
          !latest.isDecodable) {
        return null;
      }
      return _kotoho7FrameConvertedShindo(latest);
    }
    final value = record.lastValue;
    if (value != null && value.isFinite) return value;
    final kaLevel = record.lastRawLevel ?? record.lastDetectLevel;
    return kaLevel == null
        ? null
        : JpShindoScale.rawShindoFromKanameishiLevel(kaLevel);
  }

  bool _kotoho7HasCurrentFrameEvidenceRecord(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    final latest = record.observationHistory.latest;
    if (latest == null) return false;
    final ageSeconds =
        observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
    return ageSeconds <= 1.5 &&
        !latest.isMissing &&
        !latest.isStale &&
        latest.isDecodable;
  }

  double? _kotoho7FrameCurrentShindoIndex({
    required int? rawLevel,
    required int? detectLevel,
    required double? value,
  }) {
    if (rawLevel != null && rawLevel >= 0) return rawLevel.toDouble();
    if (detectLevel != null && detectLevel >= 0) {
      return detectLevel.toDouble();
    }
    if (value != null && value.isFinite) {
      final kaLevel = JpShindoScale.kanameishiLevelFromShindo(value);
      if (kaLevel >= 0) return kaLevel.toDouble();
    }
    return null;
  }

  double _kotoho7MaxAssignedCurrentShindoIndex(
    _Kotoho7HypState state, {
    required Map<String, SeismicStationEventRecord> recordsByCode,
    required DateTime observedAt,
  }) {
    var maxShindo = 0.0;
    for (final code in state.assignedStationCodes) {
      final record = recordsByCode[code];
      if (record == null) continue;
      final latest = record.observationHistory.latest;
      if (latest == null) continue;
      final ageSeconds =
          observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
      if (ageSeconds > 1.5 ||
          latest.isMissing ||
          latest.isStale ||
          !latest.isDecodable) {
        continue;
      }
      final rawLevel = latest.rawLevel;
      if (rawLevel != null) {
        maxShindo = math.max(maxShindo, rawLevel.toDouble());
        continue;
      }
      final detectLevel = latest.detectLevel;
      if (detectLevel != null) {
        maxShindo = math.max(maxShindo, detectLevel.toDouble());
        continue;
      }
      final value = latest.value;
      if (value != null && value.isFinite) {
        maxShindo = math.max(maxShindo, value);
      }
    }
    return maxShindo;
  }

  double _kotoho7MaxAssignedPermittedConvertedShindo(
    _Kotoho7HypState state, {
    required Map<String, SeismicStationEventRecord> recordsByCode,
    required DateTime observedAt,
  }) {
    var maxConverted = double.negativeInfinity;
    for (final code in state.assignedStationCodes) {
      final permitted = state.scratchDetectionPermittedShindo[code];
      final converted = _kotoho7KaLevelToContinuousShindo(permitted);
      if (converted == null) continue;
      if (converted > maxConverted) maxConverted = converted;
    }
    if (maxConverted.isFinite) return maxConverted;
    return _kotoho7MaxAssignedCurrentShindoIndex(
      state,
      recordsByCode: recordsByCode,
      observedAt: observedAt,
    );
  }

  bool _kotoho7ChangeSpeedPositive(
    SeismicStationEventRecord record, {
    DateTime? observedAt,
  }) {
    return _kotoho7ChangeSpeedValue(record, observedAt: observedAt) > 0.0;
  }

  double _kotoho7ChangeSpeedValue(
    SeismicStationEventRecord record, {
    DateTime? observedAt,
  }) {
    return _kotoho7HistoryChangeValue(
      record,
      observedAt: observedAt,
      targetSeconds: 4.0,
    );
  }

  double _kotoho7GridLongRiseChangeValue(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    // Scratch `gridトリガ` does not read the generic `ten:震度変化速度` cache.
    // It computes:
    //
    //   ten:震度履歴[+1] - ten:震度履歴[+ ten:震度履歴時間2000s[12]]
    //
    // and the decoded `震度履歴時間管理(9, 12)` call maps slot 12 to the
    // approximately 9-second history point.
    return _kotoho7HistoryChangeValue(
      record,
      observedAt: observedAt,
      targetSeconds: 9.0,
    );
  }

  double _kotoho7HistoryChangeValue(
    SeismicStationEventRecord record, {
    DateTime? observedAt,
    required double targetSeconds,
  }) {
    final frames = record.observationHistory.frames;
    if (frames.isNotEmpty) {
      final latest = frames.last;
      if (observedAt != null) {
        final ageSeconds =
            observedAt.difference(latest.dataTime).inMilliseconds.abs() /
            1000.0;
        if (ageSeconds > 1.5) return 0.0;
      }
      if (latest.isMissing || latest.isStale || !latest.isDecodable) {
        return 0.0;
      }
      final currentValue = _kotoho7FrameConvertedShindo(latest);
      if (currentValue == null) return 0.0;
      final targetTime = latest.dataTime.subtract(
        Duration(milliseconds: (targetSeconds * 1000).round()),
      );
      SeismicStationObservationFrame? reference;
      SeismicStationObservationFrame? oldestDecodable;
      for (var index = frames.length - 2; index >= 0; index--) {
        final candidate = frames[index];
        if (!candidate.isMissing &&
            !candidate.isStale &&
            candidate.isDecodable) {
          oldestDecodable = candidate;
          if (!candidate.dataTime.isAfter(targetTime)) {
            reference = candidate;
            break;
          }
        }
      }
      reference ??= oldestDecodable;
      if (reference == null) return record.lastAscend.toDouble();
      final referenceValue = _kotoho7FrameConvertedShindo(reference);
      if (referenceValue == null) return 0.0;
      return currentValue - referenceValue;
    }
    return record.lastAscend.toDouble();
  }

  double _kotoho7ImmediateChangeSpeedValue(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
  }) {
    final frames = record.observationHistory.frames;
    if (frames.length >= 2) {
      final latest = frames.last;
      final ageSeconds =
          observedAt.difference(latest.dataTime).inMilliseconds.abs() / 1000.0;
      if (ageSeconds > 1.5 ||
          latest.isMissing ||
          latest.isStale ||
          !latest.isDecodable) {
        return 0.0;
      }
      final currentValue = _kotoho7FrameConvertedShindo(latest);
      if (currentValue == null) return 0.0;
      for (var index = frames.length - 2; index >= 0; index--) {
        final previous = frames[index];
        if (previous.isMissing || previous.isStale || !previous.isDecodable) {
          continue;
        }
        final previousValue = _kotoho7FrameConvertedShindo(previous);
        if (previousValue == null) return 0.0;
        return currentValue - previousValue;
      }
    }
    return record.lastAscend.toDouble();
  }

  bool _kotoho7ScratchFastRiseEnergyExceedsLimit(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required int upwardLimitDigit,
  }) {
    final slots = _kotoho7ScratchRecentHistoryConvertedSlots(
      record,
      observedAt: observedAt,
      count: 3,
    );
    if (slots.length < 3) return false;
    final limit = upwardLimitDigit == 0
        ? 75.0
        : upwardLimitDigit * upwardLimitDigit.toDouble();
    final currentEnergy = math.pow(3.0 + slots[0], 2).toDouble();
    final previousEnergy = math.pow(3.0 + slots[2], 2).toDouble();
    return limit < currentEnergy - previousEnergy;
  }

  List<double> _kotoho7ScratchRecentHistoryConvertedSlots(
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required int count,
  }) {
    final frames = record.observationHistory.frames;
    if (frames.isEmpty) return const <double>[];
    final slots = <double>[];
    for (var index = frames.length - 1; index >= 0; index--) {
      final frame = frames[index];
      if (frame.dataTime.isAfter(
        observedAt.add(const Duration(milliseconds: 1500)),
      )) {
        continue;
      }
      final value = _kotoho7FrameConvertedShindo(frame);
      if (value == null) continue;
      slots.add(value);
      if (slots.length >= count) break;
    }
    return slots;
  }

  double? _kotoho7FrameConvertedShindo(SeismicStationObservationFrame frame) {
    final value = frame.value;
    if (value != null && value.isFinite) return value;
    final kaLevel = frame.rawLevel ?? frame.detectLevel;
    return kaLevel == null
        ? null
        : JpShindoScale.rawShindoFromKanameishiLevel(kaLevel);
  }

  double? _kotoho7KaLevelToContinuousShindo(double? level) {
    if (level == null || !level.isFinite) return null;
    final rounded = level.round();
    if ((level - rounded).abs() >= 1e-6 || rounded < 0 || rounded > 20) {
      return null;
    }
    return JpShindoScale.rawShindoFromKanameishiLevel(rounded);
  }

  double? _kotoho7KaLevelToGridDetectionMax(double? level) {
    if (level == null || !level.isFinite) return null;
    final rounded = level.round();
    if ((level - rounded).abs() >= 1e-6 || rounded < 0 || rounded > 20) {
      return null;
    }
    if (rounded < 6) return -1.0;
    return JpShindoScale.jmaIndexFromKanameishiLevel(rounded).toDouble();
  }

  int _kotoho7ScratchThresholdCode(SeismicStationEventRecord record) {
    final tagValue = int.tryParse(
      record.descriptor.tags['threshold_code'] ?? '',
    );
    if (tagValue != null) return tagValue;
    return NiedCalibration.thresholdCodes[record.descriptor.code] ??
        NiedCalibration.defaultThresholdCode;
  }

  int _kotoho7ScratchThresholdDigit(int thresholdCode, int position) {
    final text = thresholdCode.toString().padLeft(3, '0');
    final index = (position - 1).clamp(0, text.length - 1);
    return int.tryParse(text[index]) ?? 0;
  }

  double? _kotoho7ScratchPixelX(SeismicStationEventRecord record) {
    return double.tryParse(record.descriptor.tags['pixel_x'] ?? '');
  }

  double? _kotoho7ScratchPixelY(SeismicStationEventRecord record) {
    return double.tryParse(record.descriptor.tags['pixel_y'] ?? '');
  }

  double _kotoho7ScratchFirstStationDistanceKm(
    SeismicStationEventRecord first,
    SeismicStationEventRecord record,
  ) {
    final firstPixel = _kotoho7ScratchProjectedPixel(first);
    final recordPixel = _kotoho7ScratchProjectedPixel(record);
    final dx = (firstPixel.$1 - recordPixel.$1) * 11.0;
    final dy = (firstPixel.$2 - recordPixel.$2) * 11.0;
    return math.sqrt(dx * dx + dy * dy);
  }

  (double, double) _kotoho7ScratchProjectedPixel(
    SeismicStationEventRecord record,
  ) {
    // Scratch builds `dtc:Xpix/Ypix` during the map initialization step:
    //
    //   xy3 = (((longitude + 44) mod 360) - 180) * 10
    //   xy4 = ln(tan(45 + latitude / 2)) * 572.9577951308232
    //         - 374.04780730560344
    //   screenX/Y = 1カメラ系[3] * (xy3/xy4 - 1カメラ系[1/2])
    //   dtc:Xpix/Ypix = round(screenX/Y * 100000) / 100000
    //
    // `検出id距離計算` then uses the pixel delta multiplied by 11. This is
    // deliberately separate from `緯度経度で距離km`, which other branches still
    // use directly.
    const cameraX = 16.0;
    const cameraY = 41.0;
    const cameraScale = 1.8;
    const fixedPointScale = 100000.0;
    final coordinate = record.descriptor.coordinate;
    final longitudeWrapped = (coordinate.longitude + 44.0) % 360.0;
    final projectedX = (longitudeWrapped - 180.0) * 10.0;
    final tanArgumentRadians =
        (45.0 + coordinate.latitude / 2.0) * math.pi / 180.0;
    final projectedY =
        math.log(math.tan(tanArgumentRadians)) * 572.9577951308232 -
        374.04780730560344;
    final screenX = cameraScale * (projectedX - cameraX);
    final screenY = cameraScale * (projectedY - cameraY);
    return (
      (screenX * fixedPointScale).roundToDouble() / fixedPointScale,
      (screenY * fixedPointScale).roundToDouble() / fixedPointScale,
    );
  }

  double _kotoho7ThirdNearestDistanceKm(
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool,
  ) {
    final scratchIndex = _kotoho7NiedStationIndexByCode[center.descriptor.code];
    if (scratchIndex != null &&
        scratchIndex >= 0 &&
        scratchIndex < _kotoho7Nearest7ByStationIndex.length) {
      final nearest = _kotoho7Nearest7ByStationIndex[scratchIndex];
      if (nearest.length >= 3) return nearest[2].distanceKm;
    }
    final nearest = _kotoho7Nearest7Records(center, pool);
    if (nearest.length < 3) return double.infinity;
    return nearest[2].distanceKm;
  }

  double _kotoho7StationSourceDistanceKm(
    _Kotoho7HypState state,
    SeismicStationEventRecord record,
  ) {
    if (!state.sourceCache.score.isFinite) return 0.0;
    return _haversineKm(
      state.sourceCache.latitude,
      state.sourceCache.longitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
  }

  List<Map<String, Object?>> _kotoho7DetectionPermissionDiagnostics(
    _Kotoho7HypState state, {
    required DateTime observedAt,
  }) {
    final codes = state.scratchDetectionPermissionState.keys.toList()..sort();
    final rows = <Map<String, Object?>>[];
    for (final code in codes) {
      final triggerAt = state.scratchDetectionTriggerAt[code];
      rows.add({
        'station_code': code,
        'scratch_station_index': (_kotoho7NiedStationIndexByCode[code] == null)
            ? null
            : _kotoho7NiedStationIndexByCode[code]! + 1,
        'state': state.scratchDetectionPermissionState[code],
        'reason': state.scratchDetectionPermissionReason[code],
        'acceleration_score': state.scratchDetectionAccelerationScore[code],
        'acceleration_time_area_count':
            state.scratchDetectionAccelerationTimeAreaCount[code],
        'acceleration_reason': state.scratchDetectionAccelerationReason[code],
        'permitted_shindo': state.scratchDetectionPermittedShindo[code],
        'station_max_shindo': state.scratchStationMaxShindoValue[code],
        'station_max_shindo_updated_at': state
            .scratchStationMaxShindoUpdatedAt[code]
            ?.toIso8601String(),
        'trigger_at': triggerAt?.toIso8601String(),
        'trigger_age_s': triggerAt == null
            ? null
            : observedAt.difference(triggerAt).inMilliseconds / 1000.0,
        'assigned': state.assignedStationCodes.contains(code),
      });
    }
    return rows;
  }

  Map<String, int> _kotoho7DetectionPermissionStateCounts(
    _Kotoho7HypState state,
  ) {
    final counts = <String, int>{};
    for (final stationState in state.scratchDetectionPermissionState.values) {
      final key = stationState.toString();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  List<Map<String, Object?>> _kotoho7StationLifecycleDiagnostics(
    _Kotoho7HypState state, {
    required DateTime observedAt,
  }) {
    final rows = <Map<String, Object?>>[];
    final codes = state.assignedStationCodes.toList()..sort();
    for (final code in codes) {
      final plus1 = state.scratchStationFirstUseAt[code];
      final plus2 = state.scratchStationLastUpdateAt[code];
      final plus5 = state.scratchStationPendingCloudAt[code];
      rows.add({
        'station_code': code,
        'state': state.scratchStationPermissionState[code],
        'ten_plus_1': plus1?.toIso8601String(),
        'ten_plus_2': plus2?.toIso8601String(),
        'ten_plus_5_pending_cloud_time': plus5?.toIso8601String(),
        'ten_plus_5_age_s': plus5 == null
            ? null
            : observedAt.difference(plus5).inMilliseconds / 1000.0,
        'ten_plus_2_age_s': plus2 == null
            ? null
            : observedAt.difference(plus2).inMilliseconds / 1000.0,
      });
    }
    return rows;
  }

  Map<String, int> _kotoho7StationPermissionStateCounts(
    _Kotoho7HypState state,
  ) {
    final counts = <String, int>{};
    for (final code in state.assignedStationCodes) {
      final stationState = state.scratchStationPermissionState[code];
      final key = stationState == null ? 'unknown' : stationState.toString();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  double _kotoho7MaxStationLastUpdateAgeSeconds(
    _Kotoho7HypState state, {
    required DateTime observedAt,
  }) {
    var maxAgeSeconds = 0.0;
    for (final code in state.assignedStationCodes) {
      final plus2 = state.scratchStationLastUpdateAt[code];
      if (plus2 == null) continue;
      final ageSeconds = observedAt.difference(plus2).inMilliseconds / 1000.0;
      if (ageSeconds > maxAgeSeconds) maxAgeSeconds = ageSeconds;
    }
    return maxAgeSeconds;
  }

  _Kotoho7StationSourceSelection? _selectKotoho7StationSourceState(
    SeismicStationEventRecord record, {
    required _Kotoho7HypState currentState,
    required DateTime observedAt,
    required List<SeismicStationEventRecord> allTimingUsable,
    required double scratchRuntimeTimerSeconds,
    required bool isRerise,
    Map<String, int>? candidateReasonCounts,
  }) {
    final latestIdShortcut = _selectKotoho7LatestIdShortcutState(
      record,
      currentState: currentState,
      observedAt: observedAt,
      scratchRuntimeTimerSeconds: scratchRuntimeTimerSeconds,
      candidateReasonCounts: candidateReasonCounts,
    );
    if (latestIdShortcut != null) return latestIdShortcut;

    final nearest7ExistingId = _selectKotoho7Nearest7ExistingIdState(
      record,
      currentState: currentState,
      allTimingUsable: allTimingUsable,
      observedAt: observedAt,
      candidateReasonCounts: candidateReasonCounts,
    );
    if (nearest7ExistingId != null) return nearest7ExistingId;

    final id4LatestId = _selectKotoho7Id4LatestIdDistanceState(
      record,
      currentState: currentState,
      observedAt: observedAt,
      candidateReasonCounts: candidateReasonCounts,
    );
    if (id4LatestId != null) return id4LatestId;

    if (!isRerise) {
      final currentGridSelection = _selectKotoho7CurrentGridCarrierState(
        record,
        currentState: currentState,
        observedAt: observedAt,
      );
      if (currentGridSelection != null) return currentGridSelection;
    } else {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'scratch_id4_current_grid_skipped_for_rerise',
      );
    }

    final uniqueStates = <_Kotoho7HypState>{currentState};
    uniqueStates.addAll(_states.values);
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final item in allTimingUsable) item.descriptor.code: item,
    };
    _Kotoho7HypState? selected;
    double? selectedResidual;
    for (final candidateState in uniqueStates) {
      if (!candidateState.scratch43Active) continue;
      final residual = _kotoho7StationCandidateResidualSeconds(
        record,
        candidateState,
        observedAt: observedAt,
        recordsByCode: recordsByCode,
        reasonCounts: candidateReasonCounts,
      );
      if (residual == null) continue;
      if (selectedResidual == null ||
          residual < selectedResidual - 1e-9 ||
          (residual <= selectedResidual + 1e-9 &&
              identical(candidateState, currentState))) {
        selected = candidateState;
        selectedResidual = residual;
      }
    }
    if (selected != null) {
      return _Kotoho7StationSourceSelection(
        state: selected,
        source: 'scratch_4_2_source_cache',
        residualSeconds: selectedResidual,
      );
    }
    return _selectKotoho7AroundGridCarrierState(
      record,
      currentState: currentState,
      observedAt: observedAt,
      allTimingUsable: allTimingUsable,
      candidateReasonCounts: candidateReasonCounts,
    );
  }

  bool _kotoho7ScratchId4NoCandidateShouldReset() =>
      _states.values.toSet().length > 1;

  Map<String, _Kotoho7HypState> _kotoho7StationPlus3StateByCode() {
    final result = <String, _Kotoho7HypState>{};
    for (final state in _states.values.toSet()) {
      if (!state.scratch43Active) continue;
      for (final code in state.assignedStationCodes) {
        final previous = result[code];
        if (previous == null ||
            state.scratch43Serial > previous.scratch43Serial) {
          result[code] = state;
        }
      }
    }
    return result;
  }

  _Kotoho7StationSourceSelection? _selectKotoho7Nearest7ExistingIdState(
    SeismicStationEventRecord record, {
    required _Kotoho7HypState currentState,
    required List<SeismicStationEventRecord> allTimingUsable,
    required DateTime observedAt,
    Map<String, int>? candidateReasonCounts,
  }) {
    final currentPlus1 = _kotoho7StationUseTime(record, observedAt: observedAt);
    final stationPlus3StateByCode = _kotoho7StationPlus3StateByCode();
    _Kotoho7HypState? selected;
    var selectedDeltaSeconds = 10.0;
    for (final neighbor in _kotoho7Nearest7StationCodes(
      record,
      allTimingUsable,
    )) {
      if (neighbor.distanceKm > 40.0) break;
      final neighborCode = neighbor.stationCode;
      final permissionState =
          currentState.scratchDetectionPermissionState[neighborCode] ?? 0;
      if (permissionState != 4 && permissionState != 5) continue;
      final candidateState = stationPlus3StateByCode[neighborCode];
      if (candidateState == null || !candidateState.scratch43Active) continue;
      final neighborPlus1 =
          candidateState.scratchStationFirstUseAt[neighborCode];
      if (neighborPlus1 == null) continue;
      final deltaSeconds =
          (currentPlus1.difference(neighborPlus1).inMilliseconds).abs() /
          1000.0;
      if (deltaSeconds < selectedDeltaSeconds) {
        selected = candidateState;
        selectedDeltaSeconds = deltaSeconds;
      }
    }
    if (selected == null) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'nearest7_existing_id_no_permission4_5_plus3_within_10s_all_station_table',
      );
      return null;
    }
    _incrementKotoho7Reason(
      candidateReasonCounts,
      'accept_nearest7_existing_id_permission4_5_plus3_time_delta_all_station_table',
    );
    return _Kotoho7StationSourceSelection(
      state: selected,
      source: identical(selected, currentState)
          ? 'scratch_id4_1_nearest7_existing_id'
          : 'scratch_id4_1_nearest7_existing_id_other_state',
      residualSeconds: selectedDeltaSeconds,
    );
  }

  _Kotoho7StationSourceSelection? _selectKotoho7LatestIdShortcutState(
    SeismicStationEventRecord record, {
    required _Kotoho7HypState currentState,
    required DateTime observedAt,
    required double scratchRuntimeTimerSeconds,
    Map<String, int>? candidateReasonCounts,
  }) {
    if (scratchRuntimeTimerSeconds < 0.0 ||
        scratchRuntimeTimerSeconds >= 10.0) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'latest_id_shortcut_scratch_timer_not_under_10s',
      );
      return null;
    }
    _Kotoho7HypState? latest;
    for (final candidate in _states.values.toSet()) {
      if (!candidate.scratch43Active) continue;
      if (latest == null ||
          candidate.scratch43Serial > latest.scratch43Serial ||
          (candidate.scratch43Serial == latest.scratch43Serial &&
              candidate.initializedAt.isAfter(latest.initializedAt))) {
        latest = candidate;
      }
    }
    if (latest == null) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'latest_id_shortcut_no_young_active_id',
      );
      return null;
    }
    _incrementKotoho7Reason(
      candidateReasonCounts,
      'accept_latest_id_shortcut_scratch_timer_under_10s',
    );
    return _Kotoho7StationSourceSelection(
      state: latest,
      source: identical(latest, currentState)
          ? 'scratch_id3_latest_id_shortcut'
          : 'scratch_id3_latest_id_shortcut_other_state',
      residualSeconds: scratchRuntimeTimerSeconds,
    );
  }

  _Kotoho7StationSourceSelection? _selectKotoho7Id4LatestIdDistanceState(
    SeismicStationEventRecord record, {
    required _Kotoho7HypState currentState,
    required DateTime observedAt,
    Map<String, int>? candidateReasonCounts,
  }) {
    final statesByAppendOrder = _states.values.toSet().toList(growable: false)
      ..sort((a, b) {
        final serialCompare = a.scratch43Serial.compareTo(b.scratch43Serial);
        if (serialCompare != 0) return serialCompare;
        return a.scratch43FirstDetectionAt.compareTo(
          b.scratch43FirstDetectionAt,
        );
      });
    if (statesByAppendOrder.isEmpty) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'id4_latest_id_no_active_id',
      );
      return null;
    }
    final latest = statesByAppendOrder.last;
    if (!latest.scratch43Active) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'id4_latest_id_latest_row_inactive',
      );
      return null;
    }
    if (statesByAppendOrder.length >= 2) {
      final previous = statesByAppendOrder[statesByAppendOrder.length - 2];
      final previousAgeSeconds =
          observedAt
              .difference(previous.scratch43FirstDetectionAt)
              .inMilliseconds /
          1000.0;
      if (previous.scratch43AssignedCount <= 2 || previousAgeSeconds <= 40.0) {
        _incrementKotoho7Reason(
          candidateReasonCounts,
          'id4_latest_id_previous_row_guard_not_satisfied',
        );
        return null;
      }
    }
    final latestAgeSeconds =
        observedAt.difference(latest.scratch43FirstDetectionAt).inMilliseconds /
        1000.0;
    if (latestAgeSeconds < 0.0 || latestAgeSeconds >= 10.0) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'id4_latest_id_creation_not_under_10s',
      );
      return null;
    }
    final distanceKm = _haversineKm(
      latest.initialLatitude,
      latest.initialLongitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    if (distanceKm >= 400.0) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'id4_latest_id_first_station_distance_gte_400km',
      );
      return null;
    }
    _incrementKotoho7Reason(
      candidateReasonCounts,
      'accept_id4_latest_id_creation_under_10s_distance_lt_400km',
    );
    return _Kotoho7StationSourceSelection(
      state: latest,
      source: identical(latest, currentState)
          ? 'scratch_id4_latest_id_distance'
          : 'scratch_id4_latest_id_distance_other_state',
      residualSeconds: distanceKm,
    );
  }

  _Kotoho7StationSourceSelection? _selectKotoho7CurrentGridCarrierState(
    SeismicStationEventRecord record, {
    required _Kotoho7HypState currentState,
    required DateTime observedAt,
  }) {
    final gridNumber = _kotoho7GridNumber(record);
    final entry = _scratchGridByNumber[gridNumber];
    if (entry == null || !entry.state.scratch43Active) return null;
    final ageSeconds =
        observedAt.difference(entry.updatedAt).inMilliseconds / 1000.0;
    if (ageSeconds < 0.0 || ageSeconds >= 2.0) return null;
    return _Kotoho7StationSourceSelection(
      state: entry.state,
      source: identical(entry.state, currentState)
          ? 'scratch_grid_current'
          : 'scratch_grid_current_other_state',
      residualSeconds: 0.0,
    );
  }

  _Kotoho7StationSourceSelection? _selectKotoho7AroundGridCarrierState(
    SeismicStationEventRecord record, {
    required _Kotoho7HypState currentState,
    required DateTime observedAt,
    required List<SeismicStationEventRecord> allTimingUsable,
    Map<String, int>? candidateReasonCounts,
  }) {
    if (_kotoho7AroundGridActivityBlocksBorrow(
      record,
      allTimingUsable: allTimingUsable,
      observedAt: observedAt,
    )) {
      _incrementKotoho7Reason(
        candidateReasonCounts,
        'around_9_grid_guard_current_activity',
      );
      return null;
    }
    _Kotoho7GridCarrierEntry? best;
    var bestAgeSeconds = double.infinity;
    for (final gridNumber in _kotoho7AroundGridNumbers(record)) {
      final entry = _scratchGridByNumber[gridNumber];
      if (entry == null) continue;
      if (!entry.state.scratch43Active) continue;
      final ageSeconds =
          observedAt.difference(entry.updatedAt).inMilliseconds / 1000.0;
      if (ageSeconds < 0.0 || ageSeconds > 5.0) continue;
      if (best == null ||
          entry.updatedAt.isAfter(best.updatedAt) ||
          (entry.updatedAt.isAtSameMomentAs(best.updatedAt) &&
              ageSeconds < bestAgeSeconds)) {
        best = entry;
        bestAgeSeconds = ageSeconds;
      }
    }
    if (best == null) return null;
    return _Kotoho7StationSourceSelection(
      state: best.state,
      source: identical(best.state, currentState)
          ? 'scratch_grid_around_9'
          : 'scratch_grid_around_9_other_state',
      residualSeconds: bestAgeSeconds,
    );
  }

  bool _kotoho7AroundGridActivityBlocksBorrow(
    SeismicStationEventRecord record, {
    required List<SeismicStationEventRecord> allTimingUsable,
    required DateTime observedAt,
  }) {
    final currentLevel =
        _kotoho7CurrentShindoIndex(record, observedAt: observedAt) ?? 0.0;
    if (currentLevel < 1.5) return false;

    final aroundGridNumbers = _kotoho7AroundGridNumbers(record).toSet();
    var maxAroundLevel = double.negativeInfinity;
    var risingAroundCount = 0;
    for (final other in allTimingUsable) {
      if (!aroundGridNumbers.contains(_kotoho7GridNumber(other))) continue;
      final level = _kotoho7CurrentShindoIndex(other, observedAt: observedAt);
      if (level != null) {
        maxAroundLevel = math.max(maxAroundLevel, level);
      }
      if (_kotoho7HasCurrentFrameEvidenceRecord(
            other,
            observedAt: observedAt,
          ) &&
          _kotoho7ChangeSpeedPositive(other, observedAt: observedAt)) {
        risingAroundCount += 1;
      }
    }

    if (!maxAroundLevel.isFinite) return false;
    final currentIsNotWeakerThanAround = currentLevel >= maxAroundLevel - 1e-9;
    return currentIsNotWeakerThanAround && risingAroundCount < 10;
  }

  Map<String, Object?> _kotoho7EntryPipelineDiagnostics(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> candidates, {
    required List<SeismicStationEventRecord> uncappedCandidatePool,
    required DateTime observedAt,
  }) {
    var uncappedCurrentShindoPositiveCount = 0;
    var uncappedCurrentFrameEvidenceCount = 0;
    var uncappedRisePositiveCount = 0;
    for (final record in uncappedCandidatePool) {
      if (_kotoho7CurrentShindoIndex(record, observedAt: observedAt) != null) {
        uncappedCurrentShindoPositiveCount += 1;
      }
      if (_kotoho7HasCurrentFrameEvidenceRecord(
        record,
        observedAt: observedAt,
      )) {
        uncappedCurrentFrameEvidenceCount += 1;
      }
      if (_kotoho7ChangeSpeedPositive(record, observedAt: observedAt)) {
        uncappedRisePositiveCount += 1;
      }
    }

    var currentShindoPositiveCount = 0;
    var currentShindoMissingCount = 0;
    var currentFrameEvidenceCount = 0;
    var risePositiveCount = 0;
    var activeLikeCount = 0;
    var alreadyAssignedCount = 0;
    var currentGridHitCount = 0;
    var currentGridSameStateHitCount = 0;
    var currentGridOtherStateHitCount = 0;
    var aroundGridRecentHitCount = 0;
    var aroundGridSameStateHitCount = 0;
    var aroundGridOtherStateHitCount = 0;
    final currentShindoBuckets = <String, int>{};
    final samples = <Map<String, Object?>>[];

    for (final record in candidates) {
      final code = record.descriptor.code;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      if (currentShindo == null) {
        currentShindoMissingCount += 1;
      } else {
        currentShindoPositiveCount += 1;
        final bucket = currentShindo.floor().toString();
        currentShindoBuckets[bucket] = (currentShindoBuckets[bucket] ?? 0) + 1;
      }
      final hasCurrentEvidence = _kotoho7HasCurrentFrameEvidenceRecord(
        record,
        observedAt: observedAt,
      );
      if (hasCurrentEvidence) currentFrameEvidenceCount += 1;
      final risePositive = _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      );
      if (risePositive) risePositiveCount += 1;
      if (record.isActiveLike) activeLikeCount += 1;
      final alreadyAssigned = state.assignedStationCodes.contains(code);
      if (alreadyAssigned) alreadyAssignedCount += 1;

      final gridNumber = _kotoho7GridNumber(record);
      final currentGridEntry = _scratchGridByNumber[gridNumber];
      double? currentGridAgeSeconds;
      String? currentGridRelation;
      if (currentGridEntry != null && currentGridEntry.state.scratch43Active) {
        currentGridAgeSeconds =
            observedAt.difference(currentGridEntry.updatedAt).inMilliseconds /
            1000.0;
        if (currentGridAgeSeconds >= 0.0 && currentGridAgeSeconds < 2.0) {
          currentGridHitCount += 1;
          if (identical(currentGridEntry.state, state)) {
            currentGridSameStateHitCount += 1;
            currentGridRelation = 'same_state';
          } else {
            currentGridOtherStateHitCount += 1;
            currentGridRelation = 'other_state';
          }
        }
      }

      _Kotoho7GridCarrierEntry? aroundEntry;
      double? aroundGridAgeSeconds;
      String? aroundGridRelation;
      for (final aroundGridNumber in _kotoho7AroundGridNumbers(record)) {
        final entry = _scratchGridByNumber[aroundGridNumber];
        if (entry == null || !entry.state.scratch43Active) continue;
        final ageSeconds =
            observedAt.difference(entry.updatedAt).inMilliseconds / 1000.0;
        if (ageSeconds < 0.0 || ageSeconds > 5.0) continue;
        if (aroundEntry == null ||
            entry.updatedAt.isAfter(aroundEntry.updatedAt)) {
          aroundEntry = entry;
          aroundGridAgeSeconds = ageSeconds;
        }
      }
      if (aroundEntry != null) {
        aroundGridRecentHitCount += 1;
        if (identical(aroundEntry.state, state)) {
          aroundGridSameStateHitCount += 1;
          aroundGridRelation = 'same_state';
        } else {
          aroundGridOtherStateHitCount += 1;
          aroundGridRelation = 'other_state';
        }
      }

      if (samples.length < 20) {
        samples.add({
          'station_code': code,
          'already_assigned': alreadyAssigned,
          'is_active_like': record.isActiveLike,
          'current_shindo_index': currentShindo,
          'has_current_frame_evidence': hasCurrentEvidence,
          'change_speed_positive': risePositive,
          'grid_number': gridNumber,
          'current_grid_age_s': currentGridAgeSeconds,
          'current_grid_relation': currentGridRelation,
          'around_grid_age_s': aroundGridAgeSeconds,
          'around_grid_relation': aroundGridRelation,
          'first_trigger_at': record.firstTriggerAt?.toIso8601String(),
          'first_rise_at': record.firstRiseAt?.toIso8601String(),
          'last_value': record.lastValue,
          'last_raw_level': record.lastRawLevel,
          'last_detect_level': record.lastDetectLevel,
          'last_ascend': record.lastAscend,
        });
      }
    }

    return {
      'model': 'kotoho7_pre_4_2_entry_pipeline_current_frame_audit_v1',
      'candidate_count': candidates.length,
      'uncapped_candidate_pool_count': uncappedCandidatePool.length,
      'uncapped_current_shindo_positive_count':
          uncappedCurrentShindoPositiveCount,
      'uncapped_current_frame_evidence_count':
          uncappedCurrentFrameEvidenceCount,
      'uncapped_rise_positive_count': uncappedRisePositiveCount,
      'candidate_scope':
          'current_detection_candidates_for_pre_4_2_comparison_only',
      'assignment_default_model': 'scratch_full_point_id2_gate',
      'historical_candidate_cap_model':
          'usable_timing_records_default_cap_24_earliest16_plus_strongest16_no_longer_default_assignment',
      'scratch_reference_point_loop_model':
          'scratch_detection_id1_repeats_all_points_len_d_ten_x_without_24_cap',
      'scratch_id2_registration_gate_model':
          'ten_shindo_positive_then_station_state_neighbor_support_or_rerise_before_id3',
      'scratch_id2_full_loop_simulation': _kotoho7Id2FullLoopSimulation(
        state,
        uncappedCandidatePool,
        observedAt: observedAt,
      ),
      'active_like_count': activeLikeCount,
      'already_assigned_count': alreadyAssignedCount,
      'current_shindo_positive_count': currentShindoPositiveCount,
      'current_shindo_missing_count': currentShindoMissingCount,
      'current_shindo_buckets': Map<String, int>.unmodifiable(
        currentShindoBuckets,
      ),
      'current_frame_evidence_count': currentFrameEvidenceCount,
      'rise_positive_count': risePositiveCount,
      'current_grid_hit_count': currentGridHitCount,
      'current_grid_same_state_hit_count': currentGridSameStateHitCount,
      'current_grid_other_state_hit_count': currentGridOtherStateHitCount,
      'around_grid_recent_hit_count': aroundGridRecentHitCount,
      'around_grid_same_state_hit_count': aroundGridSameStateHitCount,
      'around_grid_other_state_hit_count': aroundGridOtherStateHitCount,
      'sample': List<Map<String, Object?>>.unmodifiable(samples),
    };
  }

  Map<String, Object?> _kotoho7Id2FullLoopSimulation(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> uncappedCandidatePool, {
    required DateTime observedAt,
  }) {
    var positiveShindoCount = 0;
    var plus1MissingCount = 0;
    var plus1PresentCount = 0;
    var wouldCallId3Count = 0;
    var initialState5DirectCount = 0;
    var initialRiseNearest7SupportedCount = 0;
    var initialRiseNearest7BlockedCount = 0;
    var initialState6BlockedCount = 0;
    var existingReriseCandidateCount = 0;
    var existingRefreshPlus2OnlyCount = 0;
    var existingNoId3Count = 0;
    var resetIfNoShindoWithPlus1Count = 0;
    var strictUnknown0WouldCallId3Count = 0;
    var strictUnknown0SuppressedProxyId3Count = 0;
    var strictUnknown0InitialRiseNearest7SupportedCount = 0;
    var strictUnknown0InitialState5DirectCount = 0;
    var permissionCacheWouldCallId3Count = 0;
    var permissionCacheSuppressedProxyId3Count = 0;
    var permissionCacheInitialRiseNearest7SupportedCount = 0;
    var permissionCacheInitialState5DirectCount = 0;
    final currentStateCounts = <String, int>{};
    final strictUnknown0StateCounts = <String, int>{};
    final permissionCacheStateCounts = <String, int>{};
    final nearest7SupportBuckets = <String, int>{};
    final samples = <Map<String, Object?>>[];
    final stationPlus3SerialByCode = _kotoho7StationPlus3SerialByCode();
    final recordsByCode = {
      for (final record in uncappedCandidatePool)
        record.descriptor.code: record,
    };

    for (final record in uncappedCandidatePool) {
      final code = record.descriptor.code;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      final hasPlus1 = state.scratchStationFirstUseAt.containsKey(code);
      final currentState = _kotoho7Id2CurrentPermissionState(state, code);
      final currentStateKey = currentState.toString();
      currentStateCounts[currentStateKey] =
          (currentStateCounts[currentStateKey] ?? 0) + 1;
      final changeSpeedPositive = _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      );
      final nearest7Support = _kotoho7Nearest7Permission5SupportCount(
        state,
        record,
        uncappedCandidatePool,
      );
      final nearest7SupportKey = nearest7Support.toString();
      nearest7SupportBuckets[nearest7SupportKey] =
          (nearest7SupportBuckets[nearest7SupportKey] ?? 0) + 1;
      final strictUnknown0State =
          state.scratchStationPermissionState[code] ?? 0;
      final strictUnknown0StateKey = strictUnknown0State.toString();
      strictUnknown0StateCounts[strictUnknown0StateKey] =
          (strictUnknown0StateCounts[strictUnknown0StateKey] ?? 0) + 1;
      final permissionCacheState = _kotoho7Id2CurrentPermissionState(
        state,
        code,
      );
      final permissionCacheStateKey = permissionCacheState.toString();
      permissionCacheStateCounts[permissionCacheStateKey] =
          (permissionCacheStateCounts[permissionCacheStateKey] ?? 0) + 1;

      String decision;
      var wouldCallId3 = false;
      if (currentShindo == null) {
        decision = hasPlus1
            ? 'reset_no_current_shindo'
            : 'skip_no_current_shindo';
        if (hasPlus1) resetIfNoShindoWithPlus1Count += 1;
      } else {
        positiveShindoCount += 1;
        if (!hasPlus1 && currentState != 6) {
          plus1MissingCount += 1;
          if (changeSpeedPositive) {
            if (currentState == 5) {
              decision = 'would_id3_initial_state5_direct';
              initialState5DirectCount += 1;
              wouldCallId3 = true;
            } else if (currentState < 4) {
              if (nearest7Support > 0) {
                decision = 'would_id3_initial_rise_nearest7_supported';
                initialRiseNearest7SupportedCount += 1;
                wouldCallId3 = true;
              } else {
                decision = 'blocked_initial_rise_nearest7_support_zero';
                initialRiseNearest7BlockedCount += 1;
              }
            } else {
              decision = 'blocked_initial_rise_state_not_under4';
              initialRiseNearest7BlockedCount += 1;
            }
          } else if (currentState == 5) {
            decision = 'would_id3_initial_state5_direct';
            initialState5DirectCount += 1;
            wouldCallId3 = true;
          } else {
            decision = 'blocked_initial_state_not5_no_rise';
          }
        } else if (!hasPlus1 && currentState == 6) {
          plus1MissingCount += 1;
          initialState6BlockedCount += 1;
          decision = 'blocked_initial_state6_waiting';
        } else {
          plus1PresentCount += 1;
          if (currentState > 3.5 && changeSpeedPositive) {
            if (currentState == 6 && nearest7Support > 0) {
              decision = 'would_id3_existing_rerise_state6_supported';
              existingReriseCandidateCount += 1;
              wouldCallId3 = true;
            } else if (currentState == 5) {
              decision = 'refresh_plus2_existing_state5_rise';
              existingRefreshPlus2OnlyCount += 1;
            } else {
              decision = 'existing_rise_no_id3';
              existingNoId3Count += 1;
            }
          } else {
            decision = 'existing_no_id3_until_stale_or_rerise';
            existingNoId3Count += 1;
          }
        }
      }

      if (wouldCallId3) wouldCallId3Count += 1;
      final strictUnknown0WouldCallId3 = _kotoho7Id2WouldCallId3(
        state,
        record,
        uncappedCandidatePool,
        currentShindo: currentShindo,
        hasPlus1: hasPlus1,
        currentState: strictUnknown0State,
        changeSpeedPositive: changeSpeedPositive,
        nearest7Support: nearest7Support,
        observedAt: observedAt,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      if (strictUnknown0WouldCallId3) {
        strictUnknown0WouldCallId3Count += 1;
        if (!hasPlus1 && strictUnknown0State == 5 && currentShindo != null) {
          strictUnknown0InitialState5DirectCount += 1;
        } else if (!hasPlus1 &&
            strictUnknown0State < 4 &&
            changeSpeedPositive &&
            nearest7Support > 0 &&
            currentShindo != null) {
          strictUnknown0InitialRiseNearest7SupportedCount += 1;
        }
      } else if (wouldCallId3) {
        strictUnknown0SuppressedProxyId3Count += 1;
      }
      final permissionCacheWouldCallId3 = _kotoho7Id2WouldCallId3(
        state,
        record,
        uncappedCandidatePool,
        currentShindo: currentShindo,
        hasPlus1: hasPlus1,
        currentState: permissionCacheState,
        changeSpeedPositive: changeSpeedPositive,
        nearest7Support: nearest7Support,
        observedAt: observedAt,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      if (permissionCacheWouldCallId3) {
        permissionCacheWouldCallId3Count += 1;
        if (!hasPlus1 && permissionCacheState == 5 && currentShindo != null) {
          permissionCacheInitialState5DirectCount += 1;
        } else if (!hasPlus1 &&
            permissionCacheState < 4 &&
            changeSpeedPositive &&
            nearest7Support > 0 &&
            currentShindo != null) {
          permissionCacheInitialRiseNearest7SupportedCount += 1;
        }
      } else if (wouldCallId3) {
        permissionCacheSuppressedProxyId3Count += 1;
      }
      if (samples.length < 24) {
        samples.add({
          'station_code': code,
          'decision': decision,
          'would_call_id3': wouldCallId3,
          'strict_unknown0_would_call_id3': strictUnknown0WouldCallId3,
          'permission_cache_would_call_id3': permissionCacheWouldCallId3,
          'has_plus1': hasPlus1,
          'current_state': currentState,
          'strict_unknown0_state': strictUnknown0State,
          'permission_cache_state': permissionCacheState,
          'permission_cache_reason':
              state.scratchDetectionPermissionReason[code],
          'current_shindo_index': currentShindo,
          'change_speed_positive': changeSpeedPositive,
          'nearest7_permission5_support_count': nearest7Support,
          'is_active_like': record.isActiveLike,
          'already_assigned': state.assignedStationCodes.contains(code),
          'last_raw_level': record.lastRawLevel,
          'last_detect_level': record.lastDetectLevel,
          'last_value': record.lastValue,
          'last_ascend': record.lastAscend,
        });
      }
    }

    return {
      'model': 'scratch_id2_full_loop_gate_simulation_with_ten_c_permission_v2',
      'scope': 'uncapped_positive_timing_pool_not_production_assignment',
      'nearest7_model':
          'scratch_dc_ten_shortest7_all_station_table_with_generated_fallback_v1',
      'permission_state_model':
          'scratch_ten_c_yure_detection_permission_state_else_0',
      'pool_count': uncappedCandidatePool.length,
      'positive_shindo_count': positiveShindoCount,
      'plus1_missing_count': plus1MissingCount,
      'plus1_present_count': plus1PresentCount,
      'would_call_id3_count': wouldCallId3Count,
      'initial_state5_direct_count': initialState5DirectCount,
      'initial_rise_nearest7_supported_count':
          initialRiseNearest7SupportedCount,
      'initial_rise_nearest7_blocked_count': initialRiseNearest7BlockedCount,
      'initial_state6_blocked_count': initialState6BlockedCount,
      'existing_rerise_candidate_count': existingReriseCandidateCount,
      'existing_refresh_plus2_only_count': existingRefreshPlus2OnlyCount,
      'existing_no_id3_count': existingNoId3Count,
      'reset_if_no_shindo_with_plus1_count': resetIfNoShindoWithPlus1Count,
      'strict_unknown0_comparison_model':
          'legacy_scratchStationPermissionState_else_unknown_station_state_0',
      'strict_unknown0_would_call_id3_count': strictUnknown0WouldCallId3Count,
      'strict_unknown0_suppressed_proxy_id3_count':
          strictUnknown0SuppressedProxyId3Count,
      'strict_unknown0_initial_rise_nearest7_supported_count':
          strictUnknown0InitialRiseNearest7SupportedCount,
      'strict_unknown0_initial_state5_direct_count':
          strictUnknown0InitialState5DirectCount,
      'permission_cache_model':
          'scratch_ten_c_yure_detection_permission_cache_used_as_id2_current_state',
      'permission_cache_would_call_id3_count': permissionCacheWouldCallId3Count,
      'permission_cache_suppressed_proxy_id3_count':
          permissionCacheSuppressedProxyId3Count,
      'permission_cache_initial_rise_nearest7_supported_count':
          permissionCacheInitialRiseNearest7SupportedCount,
      'permission_cache_initial_state5_direct_count':
          permissionCacheInitialState5DirectCount,
      'current_state_counts': Map<String, int>.unmodifiable(currentStateCounts),
      'strict_unknown0_state_counts': Map<String, int>.unmodifiable(
        strictUnknown0StateCounts,
      ),
      'permission_cache_state_counts': Map<String, int>.unmodifiable(
        permissionCacheStateCounts,
      ),
      'nearest7_permission5_support_buckets': Map<String, int>.unmodifiable(
        nearest7SupportBuckets,
      ),
      'sample': List<Map<String, Object?>>.unmodifiable(samples),
    };
  }

  Map<String, Object?> _kotoho7FullPointId2TimingGapAudit(
    _Kotoho7HypState state,
    SourceEstimationRequest request, {
    required DateTime observedAt,
  }) {
    final fullPointPool = request.stations
        .where((record) => request.sensorSelection.accepts(record.descriptor))
        .toList(growable: false);
    final recordsByCode = {
      for (final record in fullPointPool) record.descriptor.code: record,
    };
    final stationPlus3SerialByCode = _kotoho7StationPlus3SerialByCode();
    var noTimingCount = 0;
    var noTimingCurrentShindoPositiveCount = 0;
    var noTimingWouldCallId3Count = 0;
    var noTimingAlreadyAssignedCount = 0;
    var noTimingState5Count = 0;
    var noTimingRisePositiveCount = 0;
    final noTimingCurrentStateCounts = <String, int>{};
    final noTimingDecisionCounts = <String, int>{};
    final noTimingNearest7SupportBuckets = <String, int>{};
    final wouldCallId3Samples = <Map<String, Object?>>[];
    final samples = <Map<String, Object?>>[];

    for (final record in fullPointPool) {
      final code = record.descriptor.code;
      final hasTiming = (record.firstTriggerAt ?? record.firstRiseAt) != null;
      if (hasTiming) continue;
      noTimingCount += 1;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      final currentState = _kotoho7Id2CurrentPermissionState(state, code);
      final currentStateKey = currentState.toString();
      noTimingCurrentStateCounts[currentStateKey] =
          (noTimingCurrentStateCounts[currentStateKey] ?? 0) + 1;
      if (currentState == 5) noTimingState5Count += 1;
      final changeSpeedPositive = _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      );
      if (changeSpeedPositive) noTimingRisePositiveCount += 1;
      final convertedShindo = currentShindo == null
          ? null
          : _kotoho7CurrentConvertedShindo(record, observedAt: observedAt) ??
                currentShindo;
      final acceleration = currentShindo == null
          ? null
          : _kotoho7DetectionAccelerationProxy(
              state,
              record,
              fullPointPool,
              observedAt: observedAt,
              currentShindo: currentShindo,
              convertedShindo: convertedShindo!,
              rising: changeSpeedPositive,
            );
      final nearest7Support = _kotoho7Nearest7Permission5SupportCount(
        state,
        record,
        fullPointPool,
      );
      final nearest7SupportKey = nearest7Support.toString();
      noTimingNearest7SupportBuckets[nearest7SupportKey] =
          (noTimingNearest7SupportBuckets[nearest7SupportKey] ?? 0) + 1;
      final hasPlus1 = state.scratchStationFirstUseAt.containsKey(code);
      final wouldCallId3 = _kotoho7Id2WouldCallId3(
        state,
        record,
        fullPointPool,
        currentShindo: currentShindo,
        hasPlus1: hasPlus1,
        currentState: currentState,
        changeSpeedPositive: changeSpeedPositive,
        nearest7Support: nearest7Support,
        observedAt: observedAt,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      if (currentShindo != null) noTimingCurrentShindoPositiveCount += 1;
      if (wouldCallId3) noTimingWouldCallId3Count += 1;
      final alreadyAssigned = state.assignedStationCodes.contains(code);
      if (alreadyAssigned) noTimingAlreadyAssignedCount += 1;
      final decision = currentShindo == null
          ? 'skip_no_current_shindo'
          : wouldCallId3
          ? 'would_call_id3_but_missing_timing'
          : hasPlus1
          ? 'plus1_present_no_id3'
          : currentState == 6
          ? 'blocked_initial_state6_waiting'
          : currentState == 5
          ? 'state5_but_id2_false'
          : changeSpeedPositive
          ? nearest7Support > 0
                ? 'rise_support_but_id2_false'
                : 'blocked_initial_rise_nearest7_support_zero'
          : 'blocked_initial_state_not5_no_rise';
      noTimingDecisionCounts[decision] =
          (noTimingDecisionCounts[decision] ?? 0) + 1;
      if (samples.length < 24 &&
          (wouldCallId3 || currentState >= 5 || currentShindo != null)) {
        final sample = {
          'station_code': code,
          'decision': decision,
          'would_call_id3': wouldCallId3,
          'already_assigned': alreadyAssigned,
          'has_plus1': hasPlus1,
          'current_state': currentState,
          'permission_reason': state.scratchDetectionPermissionReason[code],
          'current_shindo_index': currentShindo,
          'converted_shindo': convertedShindo,
          'change_speed_positive': changeSpeedPositive,
          'nearest7_permission5_support_count': nearest7Support,
          'time_area_count': acceleration?.timeAreaCount,
          'close_time_area_count': acceleration?.closeTimeAreaCount,
          'permitted_count': acceleration?.permittedCount,
          'recent_permitted_count': acceleration?.recentPermittedCount,
          'high_neighbor_count': acceleration?.highNeighborCount,
          'rising_neighbor_count': acceleration?.risingNeighborCount,
          'third_nearest_distance_km': acceleration?.thirdNearestDistanceKm,
          'acceleration_score': acceleration?.score,
          'acceleration_threshold': acceleration?.threshold,
          'acceleration_has_enough_observed_points':
              acceleration?.hasEnoughObservedPoints,
          'acceleration_qualifies_normal_permission':
              acceleration?.qualifiesNormalPermission,
          'acceleration_reason': acceleration?.reason,
          'has_current_frame_evidence': _kotoho7HasCurrentFrameEvidenceRecord(
            record,
            observedAt: observedAt,
          ),
          'is_active_like': record.isActiveLike,
          'last_value': record.lastValue,
          'last_raw_level': record.lastRawLevel,
          'last_detect_level': record.lastDetectLevel,
          'last_ascend': record.lastAscend,
        };
        samples.add(sample);
        if (wouldCallId3 && wouldCallId3Samples.length < 24) {
          wouldCallId3Samples.add(sample);
        }
      } else if (wouldCallId3 && wouldCallId3Samples.length < 24) {
        wouldCallId3Samples.add({
          'station_code': code,
          'decision': decision,
          'would_call_id3': wouldCallId3,
          'already_assigned': alreadyAssigned,
          'has_plus1': hasPlus1,
          'current_state': currentState,
          'permission_reason': state.scratchDetectionPermissionReason[code],
          'current_shindo_index': currentShindo,
          'change_speed_positive': changeSpeedPositive,
          'nearest7_permission5_support_count': nearest7Support,
          'has_current_frame_evidence': _kotoho7HasCurrentFrameEvidenceRecord(
            record,
            observedAt: observedAt,
          ),
          'is_active_like': record.isActiveLike,
          'last_value': record.lastValue,
          'last_raw_level': record.lastRawLevel,
          'last_detect_level': record.lastDetectLevel,
          'last_ascend': record.lastAscend,
        });
      }
    }

    return {
      'model':
          'scratch_detection_id1_full_point_loop_vs_dart_timing_pool_audit_v1',
      'scope':
          'diagnostic_only; does not change assignment or HYP input records',
      'full_point_pool_count': fullPointPool.length,
      'no_timing_count': noTimingCount,
      'no_timing_current_shindo_positive_count':
          noTimingCurrentShindoPositiveCount,
      'no_timing_would_call_id3_count': noTimingWouldCallId3Count,
      'no_timing_already_assigned_count': noTimingAlreadyAssignedCount,
      'no_timing_state5_count': noTimingState5Count,
      'no_timing_rise_positive_count': noTimingRisePositiveCount,
      'no_timing_current_state_counts': Map<String, int>.unmodifiable(
        noTimingCurrentStateCounts,
      ),
      'no_timing_nearest7_permission5_support_buckets':
          Map<String, int>.unmodifiable(noTimingNearest7SupportBuckets),
      'no_timing_decision_counts': Map<String, int>.unmodifiable(
        noTimingDecisionCounts,
      ),
      'no_timing_would_call_id3_samples':
          List<Map<String, Object?>>.unmodifiable(wouldCallId3Samples),
      'sample': List<Map<String, Object?>>.unmodifiable(samples),
    };
  }

  Map<String, Object?> _kotoho7SourceTriggerMemberGapAudit(
    _Kotoho7HypState state,
    SourceEstimationRequest request, {
    required DateTime observedAt,
  }) {
    final fullPointPool = request.stations
        .where((record) => request.sensorSelection.accepts(record.descriptor))
        .toList(growable: false);
    final recordsByCode = {
      for (final record in fullPointPool) record.descriptor.code: record,
    };
    final continuityIds = _stringSetFromMetadata(
      request.metadata['source_trigger_continuity_member_ids'],
    );
    final memberIds = _stringSetFromMetadata(
      request.metadata['source_trigger_member_ids'],
    );
    final rawMemberIds = _stringSetFromMetadata(
      request.metadata['source_trigger_raw_member_ids'],
    );
    final watchIds = <String>{
      ...continuityIds,
      ...memberIds,
      ...rawMemberIds,
    }.toList()..sort();
    final stationPlus3SerialByCode = _kotoho7StationPlus3SerialByCode();
    var assignedWatchCount = 0;
    var missingWatchCount = 0;
    var missingWithTimingCount = 0;
    var missingWouldCallId3Count = 0;
    var missingCurrentShindoPositiveCount = 0;
    final missingDecisionCounts = <String, int>{};
    final missingPermissionStateCounts = <String, int>{};
    final missingSamples = <Map<String, Object?>>[];

    for (final code in watchIds) {
      final record = recordsByCode[code];
      final assigned = state.assignedStationCodes.contains(code);
      if (assigned) {
        assignedWatchCount += 1;
        continue;
      }
      missingWatchCount += 1;
      if (record == null) {
        missingDecisionCounts['missing_station_record'] =
            (missingDecisionCounts['missing_station_record'] ?? 0) + 1;
        if (missingSamples.length < 32) {
          missingSamples.add({
            'station_code': code,
            'decision': 'missing_station_record',
            'in_continuity_members': continuityIds.contains(code),
            'in_source_members': memberIds.contains(code),
            'in_raw_members': rawMemberIds.contains(code),
          });
        }
        continue;
      }
      final hasTiming = (record.firstTriggerAt ?? record.firstRiseAt) != null;
      if (hasTiming) missingWithTimingCount += 1;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      if (currentShindo != null) missingCurrentShindoPositiveCount += 1;
      final currentState = _kotoho7Id2CurrentPermissionState(state, code);
      final currentStateKey = currentState.toString();
      missingPermissionStateCounts[currentStateKey] =
          (missingPermissionStateCounts[currentStateKey] ?? 0) + 1;
      final changeSpeedPositive = _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      );
      final convertedShindo = currentShindo == null
          ? null
          : _kotoho7CurrentConvertedShindo(record, observedAt: observedAt) ??
                currentShindo;
      final acceleration = currentShindo == null
          ? null
          : _kotoho7DetectionAccelerationProxy(
              state,
              record,
              fullPointPool,
              observedAt: observedAt,
              currentShindo: currentShindo,
              convertedShindo: convertedShindo!,
              rising: changeSpeedPositive,
            );
      final nearest7Support = _kotoho7Nearest7Permission5SupportCount(
        state,
        record,
        fullPointPool,
      );
      final hasPlus1 = state.scratchStationFirstUseAt.containsKey(code);
      final wouldCallId3 = _kotoho7Id2WouldCallId3(
        state,
        record,
        fullPointPool,
        currentShindo: currentShindo,
        hasPlus1: hasPlus1,
        currentState: currentState,
        changeSpeedPositive: changeSpeedPositive,
        nearest7Support: nearest7Support,
        observedAt: observedAt,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      if (wouldCallId3) missingWouldCallId3Count += 1;
      final decision = currentShindo == null
          ? 'skip_no_current_shindo'
          : wouldCallId3
          ? hasTiming
                ? 'would_call_id3_with_timing'
                : 'would_call_id3_but_missing_timing'
          : hasPlus1
          ? 'plus1_present_no_id3'
          : currentState == 6
          ? 'blocked_initial_state6_waiting'
          : currentState == 5
          ? 'state5_but_id2_false'
          : changeSpeedPositive
          ? nearest7Support > 0
                ? 'rise_support_but_id2_false'
                : 'blocked_initial_rise_nearest7_support_zero'
          : 'blocked_initial_state_not5_no_rise';
      missingDecisionCounts[decision] =
          (missingDecisionCounts[decision] ?? 0) + 1;
      if (missingSamples.length < 32) {
        missingSamples.add({
          'station_code': code,
          'decision': decision,
          'in_continuity_members': continuityIds.contains(code),
          'in_source_members': memberIds.contains(code),
          'in_raw_members': rawMemberIds.contains(code),
          'has_timing': hasTiming,
          'first_trigger_at': record.firstTriggerAt?.toIso8601String(),
          'first_rise_at': record.firstRiseAt?.toIso8601String(),
          'would_call_id3': wouldCallId3,
          'has_plus1': hasPlus1,
          'current_state': currentState,
          'permission_reason': state.scratchDetectionPermissionReason[code],
          'current_shindo_index': currentShindo,
          'converted_shindo': convertedShindo,
          'change_speed_positive': changeSpeedPositive,
          'nearest7_permission5_support_count': nearest7Support,
          'time_area_count': acceleration?.timeAreaCount,
          'close_time_area_count': acceleration?.closeTimeAreaCount,
          'permitted_count': acceleration?.permittedCount,
          'recent_permitted_count': acceleration?.recentPermittedCount,
          'high_neighbor_count': acceleration?.highNeighborCount,
          'rising_neighbor_count': acceleration?.risingNeighborCount,
          'third_nearest_distance_km': acceleration?.thirdNearestDistanceKm,
          'acceleration_score': acceleration?.score,
          'acceleration_threshold': acceleration?.threshold,
          'acceleration_has_enough_observed_points':
              acceleration?.hasEnoughObservedPoints,
          'acceleration_qualifies_normal_permission':
              acceleration?.qualifiesNormalPermission,
          'acceleration_reason': acceleration?.reason,
          'has_current_frame_evidence': _kotoho7HasCurrentFrameEvidenceRecord(
            record,
            observedAt: observedAt,
          ),
          'is_active_like': record.isActiveLike,
          'last_value': record.lastValue,
          'last_raw_level': record.lastRawLevel,
          'last_detect_level': record.lastDetectLevel,
          'last_ascend': record.lastAscend,
        });
      }
    }

    return {
      'model':
          'source_trigger_watchlist_vs_scratch_detection_id_assignment_audit_v1',
      'scope':
          'diagnostic_only; source-trigger members are not treated as Scratch ground truth',
      'continuity_member_count': continuityIds.length,
      'source_member_count': memberIds.length,
      'raw_member_count': rawMemberIds.length,
      'watch_member_count': watchIds.length,
      'assigned_watch_member_count': assignedWatchCount,
      'missing_watch_member_count': missingWatchCount,
      'missing_with_timing_count': missingWithTimingCount,
      'missing_current_shindo_positive_count':
          missingCurrentShindoPositiveCount,
      'missing_would_call_id3_count': missingWouldCallId3Count,
      'missing_permission_state_counts': Map<String, int>.unmodifiable(
        missingPermissionStateCounts,
      ),
      'missing_decision_counts': Map<String, int>.unmodifiable(
        missingDecisionCounts,
      ),
      'missing_samples': List<Map<String, Object?>>.unmodifiable(
        missingSamples,
      ),
    };
  }

  Set<String> _stringSetFromMetadata(Object? value) {
    if (value is! Iterable) return const <String>{};
    return value.whereType<String>().toSet();
  }

  List<SeismicStationEventRecord> _kotoho7Id2GatedAssignmentCandidates(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> uncappedCandidatePool, {
    required DateTime observedAt,
  }) {
    final selected = <SeismicStationEventRecord>[];
    final stationPlus3SerialByCode = _kotoho7StationPlus3SerialByCode();
    final recordsByCode = {
      for (final record in uncappedCandidatePool)
        record.descriptor.code: record,
    };
    for (final record in uncappedCandidatePool) {
      final code = record.descriptor.code;
      final currentShindo = _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      );
      final hasPlus1 = state.scratchStationFirstUseAt.containsKey(code);
      final currentState = _kotoho7Id2CurrentPermissionState(state, code);
      final changeSpeedPositive = _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      );
      if (currentShindo != null) {
        if (changeSpeedPositive) {
          state.scratchStationPendingCloudAt.putIfAbsent(
            code,
            () => observedAt,
          );
        } else {
          state.scratchStationPendingCloudAt.remove(code);
        }
      }
      final nearest7Support = _kotoho7Nearest7Permission5SupportCount(
        state,
        record,
        uncappedCandidatePool,
      );
      final wouldCallId3 = _kotoho7Id2WouldCallId3(
        state,
        record,
        uncappedCandidatePool,
        currentShindo: currentShindo,
        hasPlus1: hasPlus1,
        currentState: currentState,
        changeSpeedPositive: changeSpeedPositive,
        nearest7Support: nearest7Support,
        observedAt: observedAt,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      if (wouldCallId3) {
        selected.add(record);
      }
    }
    return selected;
  }

  bool _kotoho7Id2WouldCallId3(
    _Kotoho7HypState state,
    SeismicStationEventRecord record,
    List<SeismicStationEventRecord> pool, {
    required double? currentShindo,
    required bool hasPlus1,
    required int currentState,
    required bool changeSpeedPositive,
    required int nearest7Support,
    required DateTime observedAt,
    required Map<String, int> stationPlus3SerialByCode,
    required Map<String, SeismicStationEventRecord> recordsByCode,
  }) {
    if (currentShindo == null) return false;
    if (!hasPlus1 && currentState != 6) {
      if (changeSpeedPositive) {
        return currentState == 5 || (currentState < 4 && nearest7Support > 0);
      }
      return currentState == 5;
    }
    if (!hasPlus1 && currentState == 6) return false;
    if (currentState > 3.5 && changeSpeedPositive) {
      final rerise = _kotoho7Id2ReriseScore(
        state,
        record,
        pool,
        observedAt: observedAt,
        currentState: currentState,
        stationPlus3SerialByCode: stationPlus3SerialByCode,
        recordsByCode: recordsByCode,
      );
      return rerise.shouldPromoteToState5AndCallId3;
    }
    return false;
  }

  int _kotoho7Id2CurrentPermissionState(
    _Kotoho7HypState state,
    String stationCode,
  ) {
    // Scratch `検出id1_全点へ適用` passes
    // `ten c:揺れ検出許可[番号]` as the `現在状態` argument to
    // `検出id2_各点の許可idと推定用をセット`. Unknown/not-yet-promoted points
    // therefore start at 0; `ten:推定用` slot caches (+1/+2/+3/+5/PS) do
    // not substitute for this permission state.
    return state.scratchDetectionPermissionState[stationCode] ?? 0;
  }

  int _kotoho7Nearest7Permission5SupportCount(
    _Kotoho7HypState state,
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool,
  ) {
    var supportCount = 0;
    for (final neighbor in _kotoho7Nearest7StationCodes(center, pool)) {
      final code = neighbor.stationCode;
      final permissionState = state.scratchDetectionPermissionState[code] ?? 0;
      if (permissionState == 5) supportCount += 1;
    }
    return supportCount;
  }

  List<({double distanceKm, String stationCode})> _kotoho7Nearest7StationCodes(
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool,
  ) {
    final scratchIndex = _kotoho7NiedStationIndexByCode[center.descriptor.code];
    if (scratchIndex != null &&
        scratchIndex >= 0 &&
        scratchIndex < _kotoho7Nearest7ByStationIndex.length) {
      return _kotoho7Nearest7ByStationIndex[scratchIndex]
          .map((neighbor) {
            return (
              distanceKm: neighbor.distanceKm,
              stationCode:
                  _kotoho7NiedStationCodeByScratchIndex[neighbor.stationIndex -
                      1],
            );
          })
          .toList(growable: false);
    }
    return _kotoho7Nearest7Records(center, pool)
        .map(
          (neighbor) => (
            distanceKm: neighbor.distanceKm,
            stationCode: neighbor.record.descriptor.code,
          ),
        )
        .toList(growable: false);
  }

  List<({double distanceKm, SeismicStationEventRecord record})>
  _kotoho7Nearest7Records(
    SeismicStationEventRecord center,
    List<SeismicStationEventRecord> pool,
  ) {
    final scratchIndex = _kotoho7NiedStationIndexByCode[center.descriptor.code];
    if (scratchIndex != null &&
        scratchIndex >= 0 &&
        scratchIndex < _kotoho7Nearest7ByStationIndex.length) {
      final recordsByCode = <String, SeismicStationEventRecord>{
        for (final record in pool) record.descriptor.code: record,
      };
      final scratchNeighbors =
          <({double distanceKm, SeismicStationEventRecord record})>[];
      for (final neighbor in _kotoho7Nearest7ByStationIndex[scratchIndex]) {
        final code =
            _kotoho7NiedStationCodeByScratchIndex[neighbor.stationIndex - 1];
        final record = recordsByCode[code];
        if (record == null) continue;
        scratchNeighbors.add((distanceKm: neighbor.distanceKm, record: record));
      }
      if (scratchNeighbors.isNotEmpty) {
        return scratchNeighbors;
      }
    }

    final centerCoordinate = center.descriptor.coordinate;
    final neighbors =
        <({double distanceKm, SeismicStationEventRecord record})>[];
    for (final candidate in pool) {
      if (candidate.descriptor.code == center.descriptor.code) continue;
      final coordinate = candidate.descriptor.coordinate;
      neighbors.add((
        distanceKm: _haversineKm(
          centerCoordinate.latitude,
          centerCoordinate.longitude,
          coordinate.latitude,
          coordinate.longitude,
        ),
        record: candidate,
      ));
    }
    neighbors.sort((left, right) {
      final distanceCompare = left.distanceKm.compareTo(right.distanceKm);
      if (distanceCompare != 0) return distanceCompare;
      return left.record.descriptor.code.compareTo(
        right.record.descriptor.code,
      );
    });
    return neighbors.take(7).toList(growable: false);
  }

  void _setKotoho7GridCarrier(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required DateTime observedAt,
    required String selectionSource,
  }) {
    final gridNumber = _kotoho7GridNumber(record);
    _scratchGridByNumber[gridNumber] = _Kotoho7GridCarrierEntry(
      state: state,
      updatedAt: observedAt,
      latitude: record.descriptor.coordinate.latitude,
      longitude: record.descriptor.coordinate.longitude,
      gridNumber: gridNumber,
      stationCode: record.descriptor.code,
      selectionSource: selectionSource,
    );
  }

  void _rebuildKotoho7GridCarrierFromAssignedStates(
    List<SeismicStationEventRecord> records, {
    required DateTime observedAt,
  }) {
    final recordsByCode = <String, SeismicStationEventRecord>{
      for (final record in records) record.descriptor.code: record,
    };
    final previousByGrid = Map<int, _Kotoho7GridCarrierEntry>.of(
      _scratchGridByNumber,
    );
    final activeStates = _states.values
        .where((state) => state.scratch43Active)
        .toSet();
    final assignedEntries =
        <({_Kotoho7HypState state, SeismicStationEventRecord record})>[];
    for (final state in activeStates) {
      for (final code in state.assignedStationCodes) {
        final record = recordsByCode[code];
        if (record == null) continue;
        assignedEntries.add((state: state, record: record));
      }
    }
    assignedEntries.sort((left, right) {
      final leftIndex = _kotoho7StationScratchIndex(left.record);
      final rightIndex = _kotoho7StationScratchIndex(right.record);
      final indexCompare = leftIndex.compareTo(rightIndex);
      if (indexCompare != 0) return indexCompare;
      return left.record.descriptor.code.compareTo(
        right.record.descriptor.code,
      );
    });

    _scratchGridByNumber.clear();
    for (final entry in assignedEntries) {
      final state = entry.state;
      final record = entry.record;
      final gridNumber = _kotoho7GridNumber(record);
      final previous = previousByGrid[gridNumber];
      final previousStillSameId =
          previous != null && identical(previous.state, state);
      final registeredAt =
          state.scratchStationFirstUseAt[record.descriptor.code] ??
          state.scratchStationLastUpdateAt[record.descriptor.code] ??
          state.initializedAt;
      final updatedAt = previousStillSameId ? previous.updatedAt : registeredAt;
      _scratchGridByNumber[gridNumber] = _Kotoho7GridCarrierEntry(
        state: state,
        updatedAt: updatedAt.isAfter(observedAt) ? observedAt : updatedAt,
        latitude: record.descriptor.coordinate.latitude,
        longitude: record.descriptor.coordinate.longitude,
        gridNumber: gridNumber,
        stationCode: record.descriptor.code,
        selectionSource: 'scratch_grid_presence_rebuild',
      );
    }
  }

  int _kotoho7GridPresenceActiveIdCount() {
    return _scratchGridByNumber.values
        .where((entry) => entry.state.scratch43Active)
        .map((entry) => entry.state)
        .toSet()
        .length;
  }

  int _kotoho7GridPresenceCountForState(_Kotoho7HypState state) {
    var count = 0;
    for (final entry in _scratchGridByNumber.values) {
      if (identical(entry.state, state) && entry.state.scratch43Active) {
        count += 1;
      }
    }
    return count;
  }

  int _kotoho7StationScratchIndex(SeismicStationEventRecord record) {
    return _kotoho7NiedStationIndexByCode[record.descriptor.code] ??
        _kotoho7ScratchStationCount;
  }

  int _kotoho7GridNumber(SeismicStationEventRecord record) {
    // Scratch `リセット %b` generates `dc ten:点からグリッド番号` as:
    //
    //   ((floor(d ten:y[point]) - 23) * 23) + (floor(d ten:x[point]) - 122)
    //
    // `d ten:x/y` are longitude/latitude in the 1-based station order mirrored
    // by `NiedStationDb.stations`, so we compute the same table value lazily
    // from the record coordinate instead of using the old geographic proxy.
    final coordinate = record.descriptor.coordinate;
    return _kotoho7ScratchGridNumberFromCoordinate(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    );
  }

  List<SeismicStationEventRecord> _kotoho7ScratchGridRecordsBySerialIndex(
    int serialIndex,
    Map<String, SeismicStationEventRecord> recordsByCode,
  ) {
    if (serialIndex < 0 ||
        serialIndex >= _kotoho7ScratchGridStationIndicesBySerialIndex.length) {
      return const <SeismicStationEventRecord>[];
    }
    final stationIndices =
        _kotoho7ScratchGridStationIndicesBySerialIndex[serialIndex];
    if (stationIndices.isEmpty) {
      return const <SeismicStationEventRecord>[];
    }
    final result = <SeismicStationEventRecord>[];
    for (final stationIndex in stationIndices) {
      if (stationIndex <= 0 ||
          stationIndex > _kotoho7NiedStationCodeByScratchIndex.length) {
        continue;
      }
      final code = _kotoho7NiedStationCodeByScratchIndex[stationIndex - 1];
      final record = recordsByCode[code];
      if (record != null) result.add(record);
    }
    return result;
  }

  Iterable<int> _kotoho7AroundGridNumbers(SeismicStationEventRecord record) {
    final center = _kotoho7GridNumber(record);
    const offsets = <int>[-24, -23, -22, -1, 0, 1, 22, 23, 24];
    return offsets.map((offset) => center + offset).where((number) {
      if (number <= 0) return false;
      final centerColumn = (center - 1) % 23;
      final column = (number - 1) % 23;
      return (column - centerColumn).abs() <= 1;
    });
  }

  double? _kotoho7StationCandidateResidualSeconds(
    SeismicStationEventRecord record,
    _Kotoho7HypState state, {
    required DateTime observedAt,
    required Map<String, SeismicStationEventRecord> recordsByCode,
    Map<String, int>? reasonCounts,
  }) {
    final stationObservedAt = record.firstTriggerAt ?? record.firstRiseAt;
    if (stationObservedAt == null) {
      _incrementKotoho7Reason(reasonCounts, '4_2_reject_no_station_time');
      return null;
    }
    final stationObservedSeconds =
        stationObservedAt.difference(state.earliestObserved).inMilliseconds /
        1000.0;
    if (!stationObservedSeconds.isFinite) {
      _incrementKotoho7Reason(reasonCounts, '4_2_reject_nonfinite_time');
      return null;
    }

    final detectionIdAgeSeconds =
        observedAt.difference(state.scratch43FirstDetectionAt).inMilliseconds /
        1000.0;
    final useSourceCache =
        state.sourceCache.score.isFinite &&
        detectionIdAgeSeconds > 5.0 &&
        state.sourceCache.score < 500.0;

    double latitude;
    double longitude;
    double depthKm;
    double originOffsetSeconds;
    if (useSourceCache) {
      latitude = state.sourceCache.latitude;
      longitude = state.sourceCache.longitude;
      depthKm = state.sourceCache.depthKm;
      originOffsetSeconds = state.sourceCache.originOffsetSeconds;
    } else if (state.scratch43AssignedCount > 4) {
      _incrementKotoho7Reason(reasonCounts, '4_2_branch_first_point_fallback');
      latitude = state.initialLatitude;
      longitude = state.initialLongitude;
      depthKm = 10.0;
      originOffsetSeconds = -3.0;
    } else {
      _incrementKotoho7Reason(reasonCounts, '4_2_reject_no_source_or_fallback');
      return null;
    }
    if (useSourceCache) {
      _incrementKotoho7Reason(reasonCounts, '4_2_branch_source_cache');
    }

    final coordinate = record.descriptor.coordinate;
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      coordinate.latitude,
      coordinate.longitude,
    );

    final firstDistanceLimitKm = _kotoho7FirstStationRadiusKm(
      state,
      recordsByCode,
    );
    final sourceDistanceLimitKm = state.scratch43MaxSourceDistanceKm;
    if (surfaceDistanceKm > 900.0) {
      final tooOldWide =
          detectionIdAgeSeconds > 100.0 &&
          1.5 * sourceDistanceLimitKm < surfaceDistanceKm;
      final wideAfter15Seconds =
          detectionIdAgeSeconds > 15.0 &&
          firstDistanceLimitKm > 0.0 &&
          1.4 * firstDistanceLimitKm < surfaceDistanceKm;
      if (tooOldWide) {
        _incrementKotoho7Reason(reasonCounts, '4_2_reject_wide_old_plus10');
        return null;
      }
      if (wideAfter15Seconds) {
        _incrementKotoho7Reason(reasonCounts, '4_2_reject_wide_after15_plus5');
        return null;
      }
    }

    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: true,
    );
    final pArrivalSeconds = originOffsetSeconds + pTravelSeconds;
    final pToleranceSeconds = 5.0 + surfaceDistanceKm / 120.0;
    final pResidualSeconds = (pArrivalSeconds - stationObservedSeconds).abs();
    if (pResidualSeconds <= pToleranceSeconds) {
      _incrementKotoho7Reason(reasonCounts, '4_2_accept_p_window');
      return pResidualSeconds;
    }

    final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: false,
    );
    final sArrivalSeconds = originOffsetSeconds + sTravelSeconds;
    final sToleranceSeconds = 8.0 + surfaceDistanceKm / 120.0;
    if (stationObservedSeconds < pArrivalSeconds - pToleranceSeconds) {
      _incrementKotoho7Reason(reasonCounts, '4_2_reject_before_p_window');
      return null;
    }
    if (stationObservedSeconds > sArrivalSeconds + sToleranceSeconds) {
      _incrementKotoho7Reason(reasonCounts, '4_2_reject_after_s_window');
      return null;
    }
    _incrementKotoho7Reason(reasonCounts, '4_2_accept_s_range');
    return (sArrivalSeconds - stationObservedSeconds).abs();
  }

  Map<String, Object?> _kotoho7StationAcceptanceDetail(
    _Kotoho7HypState state,
    SeismicStationEventRecord record, {
    required _Kotoho7StationSourceSelection selected,
    required DateTime observedAt,
    required Map<String, SeismicStationEventRecord> recordsByCode,
  }) {
    final code = record.descriptor.code;
    final base = <String, Object?>{
      'station_code': code,
      'source': selected.source,
      'residual_s': selected.residualSeconds,
      'grid_number': _kotoho7GridNumber(record),
      'current_shindo_index': _kotoho7CurrentShindoIndex(
        record,
        observedAt: observedAt,
      ),
      'change_speed_positive': _kotoho7ChangeSpeedPositive(
        record,
        observedAt: observedAt,
      ),
      'has_current_frame_evidence': _kotoho7HasCurrentFrameEvidenceRecord(
        record,
        observedAt: observedAt,
      ),
      'state_source_keys': state.sourceKeys.toList()..sort(),
      'assigned_count_before_add': state.assignedStationCodes.length,
      'scratch43_assigned_count_before_add': state.scratch43AssignedCount,
      'scratch43_max_first_station_distance_km':
          state.scratch43MaxFirstStationDistanceKm,
      'scratch43_max_source_distance_km': state.scratch43MaxSourceDistanceKm,
    };
    if (selected.source != 'scratch_4_2_source_cache') {
      return {
        ...base,
        'accept_reason': selected.source,
        'accept_model': 'grid_carrier_without_4_2_timing_window',
      };
    }

    final stationObservedAt = record.firstTriggerAt ?? record.firstRiseAt;
    if (stationObservedAt == null) {
      return {...base, 'accept_reason': 'diagnostic_missing_station_time'};
    }
    final stationObservedSeconds =
        stationObservedAt.difference(state.earliestObserved).inMilliseconds /
        1000.0;
    final detectionIdAgeSeconds =
        observedAt.difference(state.scratch43FirstDetectionAt).inMilliseconds /
        1000.0;
    final useSourceCache =
        state.sourceCache.score.isFinite &&
        detectionIdAgeSeconds > 5.0 &&
        state.sourceCache.score < 500.0;

    double latitude;
    double longitude;
    double depthKm;
    double originOffsetSeconds;
    String branch;
    final useFirstPointFallback = state.scratch43AssignedCount > 4;
    if (useSourceCache) {
      latitude = state.sourceCache.latitude;
      longitude = state.sourceCache.longitude;
      depthKm = state.sourceCache.depthKm;
      originOffsetSeconds = state.sourceCache.originOffsetSeconds;
      branch = '4_2_branch_source_cache';
    } else if (useFirstPointFallback) {
      latitude = state.initialLatitude;
      longitude = state.initialLongitude;
      depthKm = 10.0;
      originOffsetSeconds = -3.0;
      branch = '4_2_branch_first_point_fallback';
    } else {
      latitude = state.initialLatitude;
      longitude = state.initialLongitude;
      depthKm = 10.0;
      originOffsetSeconds = -3.0;
      branch = 'diagnostic_no_4_2_source_or_fallback';
    }

    final coordinate = record.descriptor.coordinate;
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      coordinate.latitude,
      coordinate.longitude,
    );
    final firstRecord = recordsByCode[state.firstStationCode];
    final firstDistanceKm = firstRecord == null
        ? null
        : _haversineKm(
            firstRecord.descriptor.coordinate.latitude,
            firstRecord.descriptor.coordinate.longitude,
            coordinate.latitude,
            coordinate.longitude,
          );
    final firstDistanceLimitKm = _kotoho7FirstStationRadiusKm(
      state,
      recordsByCode,
    );
    final sourceDistanceLimitKm = state.scratch43MaxSourceDistanceKm;
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: true,
    );
    final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: false,
    );
    final pArrivalSeconds = originOffsetSeconds + pTravelSeconds;
    final sArrivalSeconds = originOffsetSeconds + sTravelSeconds;
    final pToleranceSeconds = 5.0 + surfaceDistanceKm / 120.0;
    final sToleranceSeconds = 8.0 + surfaceDistanceKm / 120.0;
    final pResidualSeconds = (pArrivalSeconds - stationObservedSeconds).abs();
    final sResidualSeconds = (sArrivalSeconds - stationObservedSeconds).abs();
    String acceptReason;
    if (pResidualSeconds <= pToleranceSeconds) {
      acceptReason = '4_2_accept_p_window';
    } else if (stationObservedSeconds < pArrivalSeconds - pToleranceSeconds) {
      acceptReason = 'diagnostic_mismatch_before_p_window';
    } else if (stationObservedSeconds > sArrivalSeconds + sToleranceSeconds) {
      acceptReason = 'diagnostic_mismatch_after_s_window';
    } else {
      acceptReason = '4_2_accept_s_range';
    }

    return {
      ...base,
      'accept_reason': acceptReason,
      'accept_model': 'scratch_4_2_source_cache_timing_window_v1',
      'branch': branch,
      'detection_id_age_s': detectionIdAgeSeconds,
      'scratch43_first_detection_at': state.scratch43FirstDetectionAt
          .toIso8601String(),
      'station_observed_s': stationObservedSeconds,
      'source_cache_score': state.sourceCache.score,
      'source_latitude': latitude,
      'source_longitude': longitude,
      'source_depth_km': depthKm,
      'source_origin_offset_s': originOffsetSeconds,
      'surface_distance_km': surfaceDistanceKm,
      'hypocentral_distance_km': hypocentralDistanceKm,
      'first_station_distance_km': firstDistanceKm,
      'first_station_distance_limit_km': firstDistanceLimitKm,
      'source_distance_limit_km': sourceDistanceLimitKm,
      'p_arrival_s': pArrivalSeconds,
      'p_tolerance_s': pToleranceSeconds,
      'p_residual_s': pResidualSeconds,
      's_arrival_s': sArrivalSeconds,
      's_tolerance_s': sToleranceSeconds,
      's_residual_s': sResidualSeconds,
    };
  }

  void _incrementKotoho7Reason(Map<String, int>? counts, String reason) {
    if (counts == null) return;
    counts[reason] = (counts[reason] ?? 0) + 1;
  }

  void _recordKotoho7EstimatedSlotWrite(
    Map<String, int> counts,
    List<Map<String, Object?>> samples, {
    required String stationCode,
    required String reason,
    required List<int> slots,
    required DateTime observedAt,
    required int stationState,
  }) {
    counts[reason] = (counts[reason] ?? 0) + 1;
    if (samples.length >= 24) return;
    samples.add({
      'station_code': stationCode,
      'reason': reason,
      'slots': slots,
      'observed_at': observedAt.toIso8601String(),
      'station_state': stationState,
    });
  }

  double _kotoho7FirstStationRadiusKm(
    _Kotoho7HypState state,
    Map<String, SeismicStationEventRecord> recordsByCode,
  ) {
    final firstRecord = recordsByCode[state.firstStationCode];
    if (firstRecord == null) {
      return state.scratch43MaxFirstStationDistanceKm;
    }
    var maxDistanceKm = state.scratch43MaxFirstStationDistanceKm;
    for (final code in state.assignedStationCodes) {
      final record = recordsByCode[code];
      if (record == null) continue;
      final distanceKm = _kotoho7ScratchFirstStationDistanceKm(
        firstRecord,
        record,
      );
      if (distanceKm > maxDistanceKm) maxDistanceKm = distanceKm;
    }
    return maxDistanceKm;
  }

  List<SeismicStationEventRecord> _assignedTimingRecords(
    _Kotoho7HypState state,
    List<SeismicStationEventRecord> allTimingUsable,
  ) {
    final records = allTimingUsable
        .where(
          (record) =>
              state.assignedStationCodes.contains(record.descriptor.code),
        )
        .toList(growable: false);
    records.sort((left, right) {
      final leftAt = left.firstTriggerAt ?? left.firstRiseAt;
      final rightAt = right.firstTriggerAt ?? right.firstRiseAt;
      if (leftAt == null && rightAt == null) {
        return left.descriptor.code.compareTo(right.descriptor.code);
      }
      if (leftAt == null) return 1;
      if (rightAt == null) return -1;
      final timeCompare = leftAt.compareTo(rightAt);
      if (timeCompare != 0) return timeCompare;
      return left.descriptor.code.compareTo(right.descriptor.code);
    });
    return records;
  }

  ({
    Map<String, Object?> diagnostics,
    List<SeismicStationEventRecord> detectedRecords,
    List<SeismicStationEventRecord> unarrivedRecords,
  })
  _kotoho7GridScanProxyDiagnostics(
    SourceEstimationRequest request,
    _Kotoho7HypState state,
    _HypCandidate source, {
    required List<SeismicStationEventRecord> assignedTimingRecords,
    required List<SeismicStationEventRecord> unarrivedRecords,
    required DateTime observedAt,
  }) {
    final assignedCodes = state.assignedStationCodes;
    final assignedTimingCodes = {
      for (final record in assignedTimingRecords) record.descriptor.code,
    };
    final currentElapsedSeconds =
        observedAt.difference(state.earliestObserved).inMilliseconds / 1000.0;
    final sourceElapsedSeconds =
        currentElapsedSeconds - source.originOffsetSeconds;
    final pSurfaceRadiusKm = _kotoho7PWaveSurfaceRadiusKm(
      elapsedSeconds: sourceElapsedSeconds,
      depthKm: source.depthKm,
    );
    final recordsByGrid = <int, List<SeismicStationEventRecord>>{};
    for (final record in request.stations) {
      if (!request.sensorSelection.accepts(record.descriptor)) continue;
      recordsByGrid
          .putIfAbsent(
            _kotoho7GridNumber(record),
            () => <SeismicStationEventRecord>[],
          )
          .add(record);
    }

    var scannedGridCount = 0;
    var scannedPointCount = 0;
    var detectedSampleCount = 0;
    var detectedWithoutTimingCount = 0;
    var nonTargetScannedCount = 0;
    var deterministicUnarrivedCandidateCount = 0;
    var deterministicUnarrivedInactiveCount = 0;
    var deterministicUnarrivedActiveOrOtherCount = 0;
    var randomThinningBypassedCount = 0;
    var targetGridFallbackCandidateCount = 0;
    final detectedRecords = <SeismicStationEventRecord>[];
    final unarrivedCandidateRecords = <SeismicStationEventRecord>[];
    final samples = <Map<String, Object?>>[];

    for (final entry in recordsByGrid.entries) {
      final gridNumber = entry.key;
      final records = entry.value;
      final carrier = _scratchGridByNumber[gridNumber];
      final gridHasAnyId = carrier != null && carrier.state.scratch43Active;
      final gridHasTargetId =
          carrier != null &&
          identical(carrier.state, state) &&
          carrier.state.scratch43Active;
      final gridLatitude =
          records
              .map((record) => record.descriptor.coordinate.latitude)
              .reduce((a, b) => a + b) /
          records.length;
      final gridLongitude =
          records
              .map((record) => record.descriptor.coordinate.longitude)
              .reduce((a, b) => a + b) /
          records.length;
      final gridDistanceKm = _haversineKm(
        source.latitude,
        source.longitude,
        gridLatitude,
        gridLongitude,
      );
      final scanGrid =
          gridHasAnyId || gridDistanceKm < pSurfaceRadiusKm + 130.0;
      if (!scanGrid) continue;
      scannedGridCount += 1;
      scannedPointCount += records.length;

      for (final record in records) {
        final code = record.descriptor.code;
        final isTarget = assignedCodes.contains(code);
        if (isTarget) {
          if (assignedTimingCodes.contains(code)) {
            detectedSampleCount += 1;
            detectedRecords.add(record);
          } else {
            detectedWithoutTimingCount += 1;
          }
          continue;
        }

        nonTargetScannedCount += 1;
        final stationDistanceKm = _haversineKm(
          source.latitude,
          source.longitude,
          record.descriptor.coordinate.latitude,
          record.descriptor.coordinate.longitude,
        );
        final nearPFront = stationDistanceKm < pSurfaceRadiusKm + 30.0;
        final targetGridFallback = gridHasTargetId;
        if (assignedCodes.length >= 30) {
          randomThinningBypassedCount += 1;
        }
        if (!nearPFront && !targetGridFallback) continue;

        deterministicUnarrivedCandidateCount += 1;
        if (record.isActiveLike) {
          deterministicUnarrivedActiveOrOtherCount += 1;
        } else {
          deterministicUnarrivedInactiveCount += 1;
          unarrivedCandidateRecords.add(record);
        }
        if (targetGridFallback && !nearPFront) {
          targetGridFallbackCandidateCount += 1;
        }
        if (samples.length < 16) {
          samples.add({
            'station_code': code,
            'grid_number': gridNumber,
            'distance_km': stationDistanceKm,
            'near_p_front': nearPFront,
            'target_grid_fallback': targetGridFallback,
            'active_like': record.isActiveLike,
          });
        }
      }
    }

    final sortedDetectedRecords = _kotoho7SortedTimingRecords(detectedRecords);
    unarrivedCandidateRecords.sort(
      (a, b) => a.descriptor.code.compareTo(b.descriptor.code),
    );

    return (
      diagnostics: {
        'model': 'scratch_grid_scan_deterministic_proxy_v1_diagnostic_only',
        'mode': 'diagnostic_only_not_used_for_score',
        'p_surface_radius_km': pSurfaceRadiusKm,
        'source_elapsed_s': sourceElapsedSeconds,
        'grid_count': recordsByGrid.length,
        'scanned_grid_count': scannedGridCount,
        'scanned_point_count': scannedPointCount,
        'detected_sample_count': detectedSampleCount,
        'detected_without_timing_count': detectedWithoutTimingCount,
        'current_assigned_timing_count': assignedTimingRecords.length,
        'non_target_scanned_count': nonTargetScannedCount,
        'deterministic_unarrived_candidate_count':
            deterministicUnarrivedCandidateCount,
        'deterministic_unarrived_inactive_count':
            deterministicUnarrivedInactiveCount,
        'deterministic_unarrived_active_or_other_count':
            deterministicUnarrivedActiveOrOtherCount,
        'target_grid_fallback_candidate_count':
            targetGridFallbackCandidateCount,
        'current_unarrived_input_count': unarrivedRecords.length,
        'random_thinning_bypassed_count': randomThinningBypassedCount,
        'random_thinning_policy':
            'Scratch thins non-target points when 4-3 +4 >= 30; proxy keeps deterministic counts only',
        'sample': samples,
      },
      detectedRecords: sortedDetectedRecords,
      unarrivedRecords: List<SeismicStationEventRecord>.unmodifiable(
        unarrivedCandidateRecords,
      ),
    );
  }

  Map<String, Object?> _kotoho7GridScanScoreComparison(
    List<SeismicStationEventRecord> detectedRecords,
    List<SeismicStationEventRecord> unarrivedRecords,
    _HypCandidate currentBest, {
    required DateTime earliestObserved,
    required DateTime observedAt,
    required _HypCandidate phaseReference,
    required Map<String, bool> stationSFlagByCode,
  }) {
    final rescored = _scoreKotoho7HypCandidate(
      detectedRecords,
      unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      latitude: currentBest.latitude,
      longitude: currentBest.longitude,
      depthKm: currentBest.depthKm,
      originSeedSeconds: currentBest.originOffsetSeconds,
      phaseReferenceLatitude: phaseReference.latitude,
      phaseReferenceLongitude: phaseReference.longitude,
      phaseReferenceDepthKm: phaseReference.depthKm,
      phaseReferenceOriginOffsetSeconds: phaseReference.originOffsetSeconds,
      stationSFlagByCode: stationSFlagByCode,
    );
    return {
      'model': 'scratch_grid_scan_deterministic_proxy_score_comparison_v1',
      'status': rescored.score.isFinite ? 'rescored' : 'invalid_rescore',
      'current_score': currentBest.score,
      'grid_scan_score': rescored.score,
      'score_delta': rescored.score - currentBest.score,
      'current_detected_count':
          currentBest.phasePCount +
          currentBest.phaseSCount +
          currentBest.phaseOtherCount,
      'grid_scan_detected_count': detectedRecords.length,
      'current_unarrived_penalty': currentBest.unarrivedPenalty,
      'grid_scan_unarrived_penalty': rescored.unarrivedPenalty,
      'grid_scan_unarrived_input_count': unarrivedRecords.length,
      'grid_scan_unarrived_within_radius_count':
          rescored.scratchUnarrivedWithinRadiusCount,
      'current_s_factor': currentBest.scratchSFactor,
      'grid_scan_s_factor': rescored.scratchSFactor,
      'current_weight_sum': currentBest.scratchWeightSum,
      'grid_scan_weight_sum': rescored.scratchWeightSum,
      'grid_scan_phase_mean_residual_s': rescored.phaseMeanResidualSeconds,
      'grid_scan_phase_p_count': rescored.phasePCount,
      'grid_scan_phase_s_count': rescored.phaseSCount,
      'grid_scan_phase_other_count': rescored.phaseOtherCount,
      'grid_scan_reject_reason': rescored.scratchRejectReason,
    };
  }

  Map<String, Object?> _kotoho7GridScanSearchComparison(
    SourceEstimationRequest request,
    _Kotoho7HypState state,
    _HypCandidate currentBest, {
    required List<SeismicStationEventRecord> assignedTimingRecords,
    required List<SeismicStationEventRecord> unarrivedRecords,
    required DateTime earliestObserved,
    required DateTime observedAt,
    required (double, double, double, double) searchBounds,
    required _HypCandidate phaseReference,
    required Map<String, bool> stationSFlagByCode,
    required bool enableH2,
    required int h2MaxIterations,
    required int h10MaxIterations,
  }) {
    final initial = _scoreKotoho7GridScanCandidate(
      request,
      state,
      currentBest,
      assignedTimingRecords: assignedTimingRecords,
      unarrivedRecords: unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      phaseReference: phaseReference,
      stationSFlagByCode: stationSFlagByCode,
    );
    if (!initial.candidate.score.isFinite) {
      return {
        'model': 'scratch_grid_scan_deterministic_proxy_search_comparison_v1',
        'status': 'invalid_initial_grid_scan_candidate',
        'initial_reject_reason': initial.candidate.scratchRejectReason,
        'initial_detected_count': initial.detectedCount,
        'initial_unarrived_count': initial.unarrivedCount,
      };
    }

    final stages = <Map<String, Object?>>[];
    var best = initial.candidate;
    if (enableH2) {
      best = _kotoho7GridScanLocalSearchStage(
        request,
        state,
        assignedTimingRecords: assignedTimingRecords,
        unarrivedRecords: unarrivedRecords,
        earliestObserved: earliestObserved,
        observedAt: observedAt,
        searchBounds: searchBounds,
        currentBest: best,
        phaseReference: phaseReference,
        horizontalStepDeg: 0.5,
        depthStepKm: null,
        stageName: 'grid-scan-start-h2',
        stages: stages,
        maxIterations: math.min(h2MaxIterations, 8),
        stationSFlagByCode: stationSFlagByCode,
      );
    } else {
      stages.add({
        'stage': 'grid-scan-start-h2',
        'skipped': true,
        'skip_reason': 'scratch_requires_4_3_plus_4_gt_10',
      });
    }
    best = _kotoho7GridScanLocalSearchStage(
      request,
      state,
      assignedTimingRecords: assignedTimingRecords,
      unarrivedRecords: unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      searchBounds: searchBounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 0.1,
      depthStepKm: null,
      stageName: 'grid-scan-start-h10',
      stages: stages,
      maxIterations: math.min(h10MaxIterations, 12),
      stationSFlagByCode: stationSFlagByCode,
    );
    best = _kotoho7GridScanLocalSearchStage(
      request,
      state,
      assignedTimingRecords: assignedTimingRecords,
      unarrivedRecords: unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      searchBounds: searchBounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 0.1,
      depthStepKm: 50.0,
      stageName: 'grid-scan-start-h10-v50',
      stages: stages,
      maxIterations: 16,
      stationSFlagByCode: stationSFlagByCode,
    );
    best = _kotoho7GridScanLocalSearchStage(
      request,
      state,
      assignedTimingRecords: assignedTimingRecords,
      unarrivedRecords: unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      searchBounds: searchBounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 0.1,
      depthStepKm: 10.0,
      stageName: 'grid-scan-start-h10-v10',
      stages: stages,
      maxIterations: 16,
      stationSFlagByCode: stationSFlagByCode,
    );
    best = _kotoho7GridScanLocalSearchStage(
      request,
      state,
      assignedTimingRecords: assignedTimingRecords,
      unarrivedRecords: unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      searchBounds: searchBounds,
      currentBest: best,
      phaseReference: phaseReference,
      horizontalStepDeg: 1.0 / 60.0,
      depthStepKm: null,
      stageName: 'grid-scan-start-h60',
      stages: stages,
      maxIterations: 6,
      stationSFlagByCode: stationSFlagByCode,
    );

    return {
      'model': 'scratch_grid_scan_deterministic_proxy_search_comparison_v1',
      'status': 'rescored_capped_local_search',
      'mode': 'diagnostic_only_not_used_for_estimate',
      'iteration_cap_model':
          'capped_for_replay_latency_h2_8_h10_12_v50_16_v10_16_h60_6',
      'current_latitude': currentBest.latitude,
      'current_longitude': currentBest.longitude,
      'current_depth_km': currentBest.depthKm,
      'current_origin_offset_s': currentBest.originOffsetSeconds,
      'current_score': currentBest.score,
      'grid_scan_latitude': best.latitude,
      'grid_scan_longitude': best.longitude,
      'grid_scan_depth_km': best.depthKm,
      'grid_scan_origin_offset_s': best.originOffsetSeconds,
      'grid_scan_score': best.score,
      'score_delta': best.score - currentBest.score,
      'horizontal_shift_km': _haversineKm(
        currentBest.latitude,
        currentBest.longitude,
        best.latitude,
        best.longitude,
      ),
      'depth_delta_km': best.depthKm - currentBest.depthKm,
      'grid_scan_phase_mean_residual_s': best.phaseMeanResidualSeconds,
      'grid_scan_phase_p_count': best.phasePCount,
      'grid_scan_phase_s_count': best.phaseSCount,
      'grid_scan_phase_other_count': best.phaseOtherCount,
      'grid_scan_unarrived_penalty': best.unarrivedPenalty,
      'grid_scan_s_factor': best.scratchSFactor,
      'grid_scan_weight_sum': best.scratchWeightSum,
      'stages': stages,
    };
  }

  _HypCandidate _kotoho7GridScanLocalSearchStage(
    SourceEstimationRequest request,
    _Kotoho7HypState state, {
    required List<SeismicStationEventRecord> assignedTimingRecords,
    required List<SeismicStationEventRecord> unarrivedRecords,
    required DateTime earliestObserved,
    required DateTime observedAt,
    required (double, double, double, double) searchBounds,
    required _HypCandidate currentBest,
    required _HypCandidate phaseReference,
    required double horizontalStepDeg,
    required double? depthStepKm,
    required String stageName,
    required List<Map<String, Object?>> stages,
    required int maxIterations,
    required Map<String, bool> stationSFlagByCode,
  }) {
    var best = currentBest;
    var iterations = 0;
    var moved = false;
    var lastDetectedCount = 0;
    var lastUnarrivedCount = 0;
    var evaluatedCandidateCount = 0;
    var finiteCandidateCount = 0;
    var rejectedCandidateCount = 0;
    final firstIterationCandidateDiagnostics = <Map<String, Object?>>[];
    while (iterations < maxIterations) {
      iterations += 1;
      var localBest = best;
      final candidates = <({double lat, double lng, double depth})>[
        (lat: best.latitude, lng: best.longitude, depth: best.depthKm),
        (
          lat: best.latitude + horizontalStepDeg,
          lng: best.longitude,
          depth: best.depthKm,
        ),
        (
          lat: best.latitude - horizontalStepDeg,
          lng: best.longitude,
          depth: best.depthKm,
        ),
        (
          lat: best.latitude,
          lng: best.longitude + horizontalStepDeg,
          depth: best.depthKm,
        ),
        (
          lat: best.latitude,
          lng: best.longitude - horizontalStepDeg,
          depth: best.depthKm,
        ),
        if (depthStepKm != null)
          (
            lat: best.latitude,
            lng: best.longitude,
            depth: best.depthKm + depthStepKm,
          ),
        if (depthStepKm != null)
          (
            lat: best.latitude,
            lng: best.longitude,
            depth: best.depthKm - depthStepKm,
          ),
      ];
      for (final candidate in candidates) {
        if (candidate.lat < searchBounds.$1 ||
            candidate.lat > searchBounds.$2 ||
            candidate.lng < searchBounds.$3 ||
            candidate.lng > searchBounds.$4 ||
            candidate.depth < 10.0 ||
            candidate.depth > 700.0) {
          continue;
        }
        final seed = _HypCandidate(
          latitude: candidate.lat,
          longitude: candidate.lng,
          depthKm: candidate.depth,
          originOffsetSeconds: best.originOffsetSeconds,
          score: best.score,
          phaseScore: best.phaseScore,
          phaseMeanResidualSeconds: best.phaseMeanResidualSeconds,
          phaseResidualP90Seconds: best.phaseResidualP90Seconds,
          phasePCount: best.phasePCount,
          phaseSCount: best.phaseSCount,
          phaseOtherCount: best.phaseOtherCount,
          pairScore: 0,
          pairMeanResidualSeconds: 0,
          pairCount: 0,
          unarrivedPenalty: best.unarrivedPenalty,
          unarrivedPenaltyCount: best.unarrivedPenaltyCount,
          phaseBalancePenalty: 0,
          weightedCount: best.weightedCount,
        );
        final scored = _scoreKotoho7GridScanCandidate(
          request,
          state,
          seed,
          assignedTimingRecords: assignedTimingRecords,
          unarrivedRecords: unarrivedRecords,
          earliestObserved: earliestObserved,
          observedAt: observedAt,
          phaseReference: phaseReference,
          stationSFlagByCode: stationSFlagByCode,
        );
        evaluatedCandidateCount += 1;
        lastDetectedCount = scored.detectedCount;
        lastUnarrivedCount = scored.unarrivedCount;
        if (scored.candidate.score.isFinite) {
          finiteCandidateCount += 1;
        } else {
          rejectedCandidateCount += 1;
        }
        if (iterations == 1 && firstIterationCandidateDiagnostics.length < 12) {
          firstIterationCandidateDiagnostics.add({
            'latitude': candidate.lat,
            'longitude': candidate.lng,
            'depth_km': candidate.depth,
            'score': scored.candidate.score,
            'score_delta_from_stage_start':
                scored.candidate.score - currentBest.score,
            'phase_mean_residual_s': scored.candidate.phaseMeanResidualSeconds,
            'phase_p_count': scored.candidate.phasePCount,
            'phase_s_count': scored.candidate.phaseSCount,
            'phase_other_count': scored.candidate.phaseOtherCount,
            'unarrived_penalty': scored.candidate.unarrivedPenalty,
            'detected_count': scored.detectedCount,
            'unarrived_count': scored.unarrivedCount,
            'reject_reason': scored.candidate.scratchRejectReason,
          });
        }
        if (scored.candidate.score + 1e-6 < localBest.score) {
          localBest = scored.candidate;
        }
      }
      if (localBest.score + 1e-6 >= best.score) break;
      best = localBest;
      moved = true;
    }
    stages.add({
      'stage': stageName,
      'horizontal_step_deg': horizontalStepDeg,
      'depth_step_km': depthStepKm,
      'max_iterations': maxIterations,
      'iterations': iterations,
      'moved': moved,
      'evaluated_candidate_count': evaluatedCandidateCount,
      'finite_candidate_count': finiteCandidateCount,
      'rejected_candidate_count': rejectedCandidateCount,
      'first_iteration_candidates': firstIterationCandidateDiagnostics,
      'best_latitude': best.latitude,
      'best_longitude': best.longitude,
      'best_depth_km': best.depthKm,
      'best_origin_offset_s': best.originOffsetSeconds,
      'best_score': best.score,
      'phase_mean_residual_s': best.phaseMeanResidualSeconds,
      'phase_p_count': best.phasePCount,
      'phase_s_count': best.phaseSCount,
      'phase_other_count': best.phaseOtherCount,
      'unarrived_penalty': best.unarrivedPenalty,
      'detected_count_last_eval': lastDetectedCount,
      'unarrived_count_last_eval': lastUnarrivedCount,
    });
    return best;
  }

  ({_HypCandidate candidate, int detectedCount, int unarrivedCount})
  _scoreKotoho7GridScanCandidate(
    SourceEstimationRequest request,
    _Kotoho7HypState state,
    _HypCandidate seed, {
    required List<SeismicStationEventRecord> assignedTimingRecords,
    required List<SeismicStationEventRecord> unarrivedRecords,
    required DateTime earliestObserved,
    required DateTime observedAt,
    required _HypCandidate phaseReference,
    required Map<String, bool> stationSFlagByCode,
  }) {
    final proxy = _kotoho7GridScanProxyDiagnostics(
      request,
      state,
      seed,
      assignedTimingRecords: assignedTimingRecords,
      unarrivedRecords: unarrivedRecords,
      observedAt: observedAt,
    );
    if (proxy.detectedRecords.length < 3) {
      return (
        candidate: _invalidHypCandidate(
          latitude: seed.latitude,
          longitude: seed.longitude,
          depthKm: seed.depthKm,
          originSeedSeconds: seed.originOffsetSeconds,
          scratchRejectReason: 'grid_scan_detected_records_below_3',
        ),
        detectedCount: proxy.detectedRecords.length,
        unarrivedCount: proxy.unarrivedRecords.length,
      );
    }
    final scored = _scoreKotoho7HypCandidate(
      proxy.detectedRecords,
      proxy.unarrivedRecords,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      latitude: seed.latitude,
      longitude: seed.longitude,
      depthKm: seed.depthKm,
      originSeedSeconds: seed.originOffsetSeconds,
      phaseReferenceLatitude: phaseReference.latitude,
      phaseReferenceLongitude: phaseReference.longitude,
      phaseReferenceDepthKm: phaseReference.depthKm,
      phaseReferenceOriginOffsetSeconds: phaseReference.originOffsetSeconds,
      stationSFlagByCode: stationSFlagByCode,
    );
    return (
      candidate: scored,
      detectedCount: proxy.detectedRecords.length,
      unarrivedCount: proxy.unarrivedRecords.length,
    );
  }

  double _kotoho7PWaveSurfaceRadiusKm({
    required double elapsedSeconds,
    required double depthKm,
  }) {
    if (!elapsedSeconds.isFinite || elapsedSeconds <= 0.0) return 0.0;
    var low = 0.0;
    var high = 2000.0;
    for (var i = 0; i < 32; i++) {
      final mid = (low + high) / 2.0;
      final hypocentralDistanceKm = math.sqrt(mid * mid + depthKm * depthKm);
      final travelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: true,
      );
      if (travelSeconds <= elapsedSeconds) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  double? _kotoho7SourceCachePhaseResidualSeconds(
    SeismicStationEventRecord record,
    _Kotoho7HypState state,
  ) {
    final observedAt = record.firstTriggerAt ?? record.firstRiseAt;
    if (observedAt == null) return null;
    final coordinate = record.descriptor.coordinate;
    final source = state.sourceCache;
    if (!source.score.isFinite) return null;
    final originSeconds =
        observedAt.difference(state.earliestObserved).inMilliseconds / 1000.0 -
        source.originOffsetSeconds;
    if (!originSeconds.isFinite || originSeconds < 0) return null;
    final surfaceDistanceKm = _haversineKm(
      source.latitude,
      source.longitude,
      coordinate.latitude,
      coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + source.depthKm * source.depthKm,
    );
    final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: source.depthKm,
      pWave: true,
    );
    final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: source.depthKm,
      pWave: false,
    );
    final pToleranceSeconds = 5.0 + surfaceDistanceKm / 120.0;
    final sToleranceSeconds = 8.0 + surfaceDistanceKm / 120.0;
    final pResidualSeconds = (originSeconds - pTravelSeconds).abs();
    if (pResidualSeconds < pToleranceSeconds) return pResidualSeconds;
    final sResidualSeconds = (originSeconds - sTravelSeconds).abs();
    if (sResidualSeconds <= sToleranceSeconds) return sResidualSeconds;
    return null;
  }
}

class TriggerTimeDepthGridSearchEstimator implements SourceEstimator {
  final SourceEstimator? fallback;
  final double assumedWaveSpeedKmPerSec;
  final double coarseStepDeg;
  final double fineStepDeg;
  final double refineStepDeg;
  final double bboxPaddingDeg;
  final List<double> depthCandidatesKm;

  const TriggerTimeDepthGridSearchEstimator({
    this.fallback,
    this.assumedWaveSpeedKmPerSec = 4.0,
    this.coarseStepDeg = 0.20,
    this.fineStepDeg = 0.05,
    this.refineStepDeg = 0.02,
    this.bboxPaddingDeg = 0.60,
    this.depthCandidatesKm = const [0, 10, 20, 30, 40, 60, 80, 100, 150, 200],
  });

  @override
  String get methodId => 'trigger_time_depth_grid_v3';

  @override
  bool supports(SourceEstimationRequest request) {
    final triggeredCount = _usableTimingRecords(request).length;
    if (triggeredCount >= 4) {
      return true;
    }
    return fallback?.supports(request) ?? false;
  }

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final usable = _usableTimingRecords(request);
    if (usable.length < 4) {
      return fallback?.estimate(request);
    }

    final bounds = _searchBounds(usable, bboxPaddingDeg: bboxPaddingDeg);
    final earliestObserved = _earliestObserved(usable);
    final weightedCenter = _weightedCenter(usable);

    _DepthCandidate best = _DepthCandidate(
      latitude: weightedCenter.$1,
      longitude: weightedCenter.$2,
      depthKm: depthCandidatesKm.first,
      score: double.infinity,
    );

    best = _searchDepthGrid(
      usable,
      earliestObserved,
      minLat: bounds.$1,
      maxLat: bounds.$2,
      minLng: bounds.$3,
      maxLng: bounds.$4,
      stepDeg: coarseStepDeg,
      currentBest: best,
    );
    best = _searchDepthGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - coarseStepDeg * 1.5,
      maxLat: best.latitude + coarseStepDeg * 1.5,
      minLng: best.longitude - coarseStepDeg * 1.5,
      maxLng: best.longitude + coarseStepDeg * 1.5,
      stepDeg: fineStepDeg,
      currentBest: best,
    );
    best = _searchDepthGrid(
      usable,
      earliestObserved,
      minLat: best.latitude - fineStepDeg * 1.5,
      maxLat: best.latitude + fineStepDeg * 1.5,
      minLng: best.longitude - fineStepDeg * 1.5,
      maxLng: best.longitude + fineStepDeg * 1.5,
      stepDeg: refineStepDeg,
      currentBest: best,
    );

    if (!best.score.isFinite) {
      return fallback?.estimate(request);
    }

    final supportCount = usable.length;
    final timeFit = 1.0 / (1.0 + best.timeScore / math.max(1, supportCount));
    final rankFit = 1.0 / (1.0 + best.rankScore);
    final depthPenalty = math.min(0.18, best.depthKm / 1000.0);
    final confidence =
        (0.18 +
                timeFit * 0.42 +
                rankFit * 0.18 +
                math.min(0.22, supportCount * 0.025) -
                depthPenalty)
            .clamp(0.0, 0.95);

    final originTime = earliestObserved.subtract(
      Duration(
        milliseconds:
            (best.referenceDistanceKm / assumedWaveSpeedKmPerSec * 1000)
                .round(),
      ),
    );
    final magnitudeDiagnostics = _niedGifMagnitudeDiagnostics(
      usable,
      sourceLatitude: best.latitude,
      sourceLongitude: best.longitude,
      depthKm: best.depthKm,
      depthSource: 'trigger_time_depth_grid_supported',
    );
    final diagnosticMagnitude = _supportedDiagnosticMagnitude(
      magnitudeDiagnostics,
    );

    return SourceEstimate(
      latitude: best.latitude,
      longitude: best.longitude,
      depthKm: best.depthKm,
      magnitude: diagnosticMagnitude,
      confidence: confidence,
      method: methodId,
      supportingStationCount: supportCount,
      originTime: originTime,
      diagnostics: {
        'wave_speed_kmps': assumedWaveSpeedKmPerSec,
        'time_score': best.timeScore,
        'rank_score': best.rankScore,
        'final_score': best.score,
        'reference_distance_km': best.referenceDistanceKm,
        'best_depth_km': best.depthKm,
        'depth_candidates_km': depthCandidatesKm,
        ...magnitudeDiagnostics,
        'usable_station_count': supportCount,
        'search_bbox': [bounds.$1, bounds.$2, bounds.$3, bounds.$4],
        'top_timing_picks': _topTimingPicks(
          usable,
          earliestObserved: earliestObserved,
        ),
      },
    );
  }

  _DepthCandidate _searchDepthGrid(
    List<SeismicStationEventRecord> usable,
    DateTime earliestObserved, {
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double stepDeg,
    required _DepthCandidate currentBest,
  }) {
    var best = currentBest;
    for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
      for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
        for (final depthKm in depthCandidatesKm) {
          final scored = _scoreDepthCandidate(
            usable,
            earliestObserved,
            lat,
            lng,
            depthKm,
            assumedWaveSpeedKmPerSec: assumedWaveSpeedKmPerSec,
          );
          if (scored.score < best.score) {
            best = scored;
          }
        }
      }
    }
    return best;
  }
}

_NiedHypWorkerFrame? _niedHypWorkerFrame(SourceEstimationRequest request) {
  final hasWorkerInput =
      request.metadata.containsKey('nied_hypocenter_active_stations') ||
      request.metadata.containsKey('nied_hypocenter_new_active_stations') ||
      request.metadata.containsKey('nied_hypocenter_inactive_stations') ||
      request.metadata.containsKey('activeStations') ||
      request.metadata.containsKey('newActiveStations') ||
      request.metadata.containsKey('inactiveStations');
  final activeSnapshots = _niedHypSnapshotList(
    request.metadata['nied_hypocenter_active_stations'] ??
        request.metadata['activeStations'],
  );
  final hasExplicitNewActiveInput =
      request.metadata.containsKey('nied_hypocenter_new_active_stations') ||
      request.metadata.containsKey('newActiveStations');
  final newActiveSnapshots = _niedHypSnapshotList(
    request.metadata['nied_hypocenter_new_active_stations'] ??
        request.metadata['newActiveStations'],
  );
  final inactiveSnapshots = _niedHypSnapshotList(
    request.metadata['nied_hypocenter_inactive_stations'] ??
        request.metadata['inactiveStations'],
  );
  if (activeSnapshots.isEmpty &&
      newActiveSnapshots.isEmpty &&
      inactiveSnapshots.isEmpty &&
      !hasWorkerInput) {
    return null;
  }

  final activeByCode = <String, Map<String, Object?>>{};
  for (final snapshot in [...activeSnapshots, ...newActiveSnapshots]) {
    final code = _niedHypSnapshotCode(snapshot);
    if (code != null) activeByCode[code] = snapshot;
  }
  final newActiveByCode = <String, Map<String, Object?>>{};
  final registrationSnapshots = hasExplicitNewActiveInput
      ? newActiveSnapshots
      : activeSnapshots;
  for (final snapshot in registrationSnapshots) {
    final code = _niedHypSnapshotCode(snapshot);
    if (code != null) newActiveByCode[code] = snapshot;
  }
  final inactiveByCode = <String, Map<String, Object?>>{};
  for (final snapshot in inactiveSnapshots) {
    final code = _niedHypSnapshotCode(snapshot);
    if (code != null && !activeByCode.containsKey(code)) {
      inactiveByCode[code] = snapshot;
    }
  }
  if (activeByCode.isEmpty && inactiveByCode.isEmpty && !hasWorkerInput) {
    return null;
  }
  final adjacencyByStationId = _niedHypSnapshotAdjacency(
    request.metadata['nied_hypocenter_adj_station_ids'] ??
        request.metadata['adjStationIds'],
  );
  final detectionAdjacencyByCode = _niedHypSnapshotAdjacency(
    request.metadata['nied_detection_adj_station_codes'] ??
        request.metadata['detectionAdjStationCodes'],
  );
  final detectionGridDecimal = _niedHypDetectionGridDecimal(
    request.metadata['nied_hypocenter_detection_grid'] ??
        request.metadata['detectionGrid'],
  );

  final active = <_NiedHypWorkerStation>[];
  for (final snapshot in activeByCode.values) {
    final station = _niedHypStationFromSnapshot(snapshot, active: true);
    if (station != null) active.add(station);
  }
  final newActive = <_NiedHypWorkerStation>[];
  for (final snapshot in newActiveByCode.values) {
    final station = _niedHypStationFromSnapshot(snapshot, active: true);
    if (station != null) newActive.add(station);
  }
  final newActiveStationIdsWithoutTrigger = <String>{
    for (final snapshot in newActiveByCode.values)
      if (_niedHypSnapshotTime(snapshot['triggerStamp']) == null)
        (snapshot['id'] ?? _niedHypSnapshotCode(snapshot)).toString(),
  };
  request.metadata['nied_dart_hyp_input_station_order_model'] =
      'ka_active_station_table_order_matching_scratch_point_index';
  request.metadata['nied_dart_hyp_input_station_order'] = [
    for (final station in active) station.code,
  ];
  final inactive = <_NiedHypWorkerStation>[];
  for (final snapshot in inactiveByCode.values) {
    final station = _niedHypStationFromSnapshot(snapshot, active: false);
    if (station != null) inactive.add(station);
  }
  return _NiedHypWorkerFrame(
    newActiveStations: newActive,
    newActiveStationIdsWithoutTrigger: newActiveStationIdsWithoutTrigger,
    activeStations: active,
    inactiveStations: inactive,
    adjacencyByStationId: adjacencyByStationId,
    detectionAdjacencyByCode: detectionAdjacencyByCode,
    detectionGridDecimal: detectionGridDecimal,
    inactiveScope: request.metadata['nied_hypocenter_inactive_scope']
        ?.toString(),
  );
}

({double latitude, double longitude})? _niedHypDetectionGridDecimal(
  Object? value,
) {
  if (value is! Map) return null;
  final decimal = value['decimal'];
  if (decimal is! Iterable) return null;
  final values = decimal.toList(growable: false);
  if (values.length < 2) return null;
  final latitude = _doubleFromObject(values[0]);
  final longitude = _doubleFromObject(values[1]);
  if (latitude == null || longitude == null) return null;
  if (!QuakeCalculator.isUsableMapCoordinate(latitude, longitude)) return null;
  if (QuakeCalculator.isLikelyUninitializedCoordinate(latitude, longitude)) {
    return null;
  }
  return (latitude: latitude, longitude: longitude);
}

Map<String, Set<String>> _niedHypSnapshotAdjacency(Object? value) {
  if (value is! Map) return const <String, Set<String>>{};
  final result = <String, Set<String>>{};
  for (final entry in value.entries) {
    final neighbors = entry.value;
    if (neighbors is! Iterable) continue;
    result[entry.key.toString()] = {
      for (final neighbor in neighbors) neighbor.toString(),
    };
  }
  return result;
}

List<Map<String, Object?>> _niedHypSnapshotList(Object? value) {
  if (value is! Iterable) return const <Map<String, Object?>>[];
  return [
    for (final item in value)
      if (item is Map)
        item.map((key, value) => MapEntry(key.toString(), value)),
  ];
}

String? _niedHypSnapshotCode(Map<String, Object?> snapshot) {
  final code = snapshot['code'] ?? snapshot['stationCode'];
  if (code is String && code.isNotEmpty) return code;
  final id = snapshot['id'];
  if (id == null) return null;
  return id.toString();
}

_NiedHypWorkerStation? _niedHypStationFromSnapshot(
  Map<String, Object?> snapshot, {
  required bool active,
}) {
  final code = _niedHypSnapshotCode(snapshot);
  final latLng = _niedHypSnapshotLatLng(snapshot);
  if (code == null || latLng == null) return null;
  final updateAt = _niedHypSnapshotTime(snapshot['updateStamp']);
  final triggerAt = _niedHypSnapshotTime(snapshot['triggerStamp']);
  if (active && triggerAt == null) return null;
  final level = _intFromObject(snapshot['level']);
  final currentShindo = _doubleFromObject(snapshot['shindo']);
  final ascend = _intFromObject(snapshot['ascend']) ?? 0;
  return _NiedHypWorkerStation(
    id: snapshot['id']?.toString() ?? code,
    code: code,
    coordinate: latLng,
    triggerAt: triggerAt,
    updateAt: updateAt,
    level: level,
    currentShindo: currentShindo,
    ascend: ascend,
    active: active,
  );
}

LatLng? _niedHypSnapshotLatLng(Map<String, Object?> snapshot) {
  LatLng? parsed;
  final latLng = snapshot['latLng'];
  if (latLng is Iterable) {
    final values = latLng.toList(growable: false);
    if (values.length >= 2) {
      final lat = _doubleFromObject(values[0]);
      final lng = _doubleFromObject(values[1]);
      if (lat != null && lng != null) parsed = LatLng(lat, lng);
    }
  }
  if (parsed == null && latLng is Map) {
    final lat = _doubleFromObject(latLng['lat'] ?? latLng['latitude']);
    final lng = _doubleFromObject(
      latLng['lng'] ?? latLng['lon'] ?? latLng['longitude'],
    );
    if (lat != null && lng != null) parsed = LatLng(lat, lng);
  }
  parsed ??= () {
    final lat = _doubleFromObject(snapshot['lat'] ?? snapshot['latitude']);
    final lng = _doubleFromObject(
      snapshot['lng'] ?? snapshot['lon'] ?? snapshot['longitude'],
    );
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }();
  if (parsed == null) return null;
  if (!QuakeCalculator.isUsableMapCoordinate(
    parsed.latitude,
    parsed.longitude,
  )) {
    return null;
  }
  if (QuakeCalculator.isLikelyUninitializedCoordinate(
    parsed.latitude,
    parsed.longitude,
  )) {
    return null;
  }
  return parsed;
}

DateTime? _niedHypSnapshotTime(Object? value) {
  final millis = _intFromObject(value);
  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: false);
}

class _NiedHypWorkerFrame {
  const _NiedHypWorkerFrame({
    required this.newActiveStations,
    this.newActiveStationIdsWithoutTrigger = const <String>{},
    required this.activeStations,
    required this.inactiveStations,
    required this.adjacencyByStationId,
    this.detectionAdjacencyByCode = const <String, Set<String>>{},
    this.detectionGridDecimal,
    required this.inactiveScope,
  });

  final List<_NiedHypWorkerStation> newActiveStations;
  final Set<String> newActiveStationIdsWithoutTrigger;
  final List<_NiedHypWorkerStation> activeStations;
  final List<_NiedHypWorkerStation> inactiveStations;
  final Map<String, Set<String>> adjacencyByStationId;
  final Map<String, Set<String>> detectionAdjacencyByCode;
  final ({double latitude, double longitude})? detectionGridDecimal;
  final String? inactiveScope;
}

class _NiedHypEventState {
  final Map<int, _NiedHypDetectionState> detectionIds =
      <int, _NiedHypDetectionState>{};
  final Map<String, int> _stationDetectionIdByCode = <String, int>{};
  final Map<String, _NiedHypGridCarrier> _gridCarrierByKey =
      <String, _NiedHypGridCarrier>{};
  final Map<String, String> lastAssignmentAcceptedByCode = <String, String>{};
  final Map<String, String> lastAssignmentRejectedByCode = <String, String>{};
  int _nextDetectionId = 1;
  int? _selectedDetectionId;
  DateTime? _lastObservedAt;
  ({double latitude, double longitude})? _gridDecimal;
  int _sameSourceMergeCount = 0;
  int _referenceUpdateVersion = 0;
  String? _referenceInactiveStationsKey;
  final Set<String> _referenceIgnoredArrivalIds = <String>{};
  final Map<int, _NiedHypReferenceSubcluster> _referenceSubclustersById =
      <int, _NiedHypReferenceSubcluster>{};
  final Map<String, int> _referenceSubclusterIdByStationId = <String, int>{};
  int _nextReferenceSubclusterId = 1;
  String? lastSourceClearReason;
  final SrevKaizouMagnitudeIntensityState magnitudeIntensityState =
      SrevKaizouMagnitudeIntensityState();

  bool get hasLifecycleState => detectionIds.isNotEmpty;

  bool get hasActiveDetectionId =>
      detectionIds.values.any((state) => state.active);

  int get activeDetectionCount =>
      detectionIds.values.where((state) => state.active).length;

  Map<String, int> get stationDetectionIds => Map<String, int>.unmodifiable(
    Map<String, int>.from(_stationDetectionIdByCode),
  );

  Map<int, _NiedHypWorkerFrame> mergeFrame(
    _NiedHypWorkerFrame frame, {
    required DateTime observedAt,
    required double? scratchRuntimeTimerSeconds,
    required bool referenceAligned,
  }) {
    lastSourceClearReason = null;
    final previousObservedAt = _lastObservedAt;
    if (previousObservedAt != null && observedAt.isBefore(previousObservedAt)) {
      _reset();
    }
    _lastObservedAt = observedAt;
    _gridDecimal ??= frame.detectionGridDecimal;
    if (_gridDecimal == null && frame.activeStations.isNotEmpty) {
      final coordinate = frame.activeStations.first.coordinate;
      _gridDecimal = (
        latitude: niedDetectionGridDecimalPart(coordinate.latitude),
        longitude: niedDetectionGridDecimalPart(coordinate.longitude),
      );
    }
    if (!referenceAligned) {
      mergeSameSourceDetectionIds(observedAt: observedAt);
    }
    lastAssignmentAcceptedByCode.clear();
    lastAssignmentRejectedByCode.clear();
    for (final state in detectionIds.values) {
      state.worker
        ..lastAssignmentAcceptedByCode.clear()
        ..lastAssignmentRejectedByCode.clear();
    }

    if (referenceAligned) {
      return _mergeReferenceAlignedFrame(frame, observedAt: observedAt);
    }

    final incoming = frame.activeStations.toList(growable: false);
    for (final station in incoming) {
      final ownerId = _stationDetectionIdByCode[station.code];
      final owner = ownerId == null ? null : detectionIds[ownerId];
      if (owner != null && owner.active) {
        owner.worker.activeStationsByCode[station.code] = _mergeNiedHypStation(
          owner.worker.activeStationsByCode[station.code],
          station,
        );
      }
    }

    for (final station in frame.newActiveStations) {
      final ownerId = _stationDetectionIdByCode[station.code];
      final owner = ownerId == null ? null : detectionIds[ownerId];
      if (owner != null && owner.active) continue;
      final selection = _selectDetectionId(
        station,
        frame: frame,
        observedAt: observedAt,
        scratchRuntimeTimerSeconds: scratchRuntimeTimerSeconds,
      );
      if (selection == null) {
        lastAssignmentRejectedByCode[station.code] =
            'scratch_id3_reject_no_candidate_max_two_ids';
        continue;
      }
      _assignStation(
        selection.state,
        station,
        observedAt: observedAt,
        reason: selection.reason,
      );
    }

    _rebuildGridCarriers(incoming, observedAt: observedAt);
    if (_gridCarrierByKey.isEmpty && detectionIds.isNotEmpty) {
      _clearForEmptyGridCarrier();
    } else {
      _updateActiveLifecycle(observedAt);
    }
    final result = <int, _NiedHypWorkerFrame>{};
    for (final state in detectionIds.values) {
      if (!state.active) continue;
      final active = state.worker.activeStationsByCode.values.toList(
        growable: false,
      );
      final inactive = _inactiveForDetectionId(state, frame.inactiveStations);
      result[state.id] = _NiedHypWorkerFrame(
        newActiveStations: const <_NiedHypWorkerStation>[],
        activeStations: active,
        inactiveStations: inactive,
        adjacencyByStationId: frame.adjacencyByStationId,
        detectionAdjacencyByCode: frame.detectionAdjacencyByCode,
        detectionGridDecimal: _gridDecimal,
        inactiveScope: frame.inactiveScope,
      );
    }
    return result;
  }

  Map<int, _NiedHypWorkerFrame> _mergeReferenceAlignedFrame(
    _NiedHypWorkerFrame frame, {
    required DateTime observedAt,
  }) {
    if (frame.activeStations.isEmpty) {
      // NiedNet resets its worker whenever the active station set is empty.
      // Keep a later, separate detection from inheriting this cluster's history.
      _clearReferenceForEmptyActiveStations();
      return const <int, _NiedHypWorkerFrame>{};
    }

    final updateVersion = ++_referenceUpdateVersion;
    _referenceIgnoredArrivalIds
      ..addAll(frame.newActiveStationIdsWithoutTrigger)
      ..removeAll(frame.newActiveStations.map((station) => station.id));
    final inactiveStationsKey =
        '${frame.inactiveStations.length}:'
        '${frame.inactiveStations.map((station) => station.id).join(',')}';
    if (_referenceInactiveStationsKey != inactiveStationsKey) {
      _referenceInactiveStationsKey = inactiveStationsKey;
      for (final state in detectionIds.values) {
        if (state.active) _referenceMarkUpdated(state, updateVersion);
      }
    }
    final stateByStationId = _referenceActiveStatesByStationId();
    for (final station in frame.activeStations) {
      final state = stateByStationId[station.id];
      if (state == null) continue;
      final existing = state.worker.activeStationsByCode[station.code];
      final merged = _mergeNiedHypStation(existing, station);
      state.worker.activeStationsByCode[station.code] = merged;
      if (existing == null ||
          existing.level != merged.level ||
          existing.ascend != merged.ascend) {
        _referenceMarkUpdated(state, updateVersion);
      }
    }

    // The source snapshot can stop flagging a still-active station as new.
    // Restore it like NiedHypoInf's persistent active-station map, except for
    // stations first observed without a valid trigger timestamp: the original
    // addActiveStation() ignores those until a future valid new arrival.
    final arrivalsById = <String, _NiedHypWorkerStation>{
      for (final station in frame.newActiveStations)
        if (station.triggerAt != null) station.id: station,
      for (final station in frame.activeStations)
        if (!stateByStationId.containsKey(station.id) &&
            !_referenceIgnoredArrivalIds.contains(station.id) &&
            station.triggerAt != null)
          station.id: station,
    };
    for (final station in arrivalsById.values) {
      if (stateByStationId.containsKey(station.id)) continue;
      final neighborSubclusters = _referenceNeighborSubclusters(
        station,
        frame.adjacencyByStationId,
      );
      final matchingSubcluster = _referenceBestResidualSubcluster(station);
      // Keep both links when an arriving station bridges an adjacent cluster
      // and a cluster whose current result predicts its trigger. The reference
      // implementation merges the union rather than discarding either link.
      if (matchingSubcluster != null &&
          !neighborSubclusters.contains(matchingSubcluster)) {
        neighborSubclusters.add(matchingSubcluster);
      }
      late final _NiedHypDetectionState state;
      late final String assignmentReason;
      if (neighborSubclusters.isEmpty) {
        state = _referenceCreateState(station, observedAt: observedAt);
        _referenceCreateSubcluster(state);
        assignmentReason = 'kanameishi_reference_residual_or_new_cluster';
      } else if (neighborSubclusters.length == 1) {
        state = neighborSubclusters.single.state;
        assignmentReason = 'kanameishi_reference_adjacent_cluster';
      } else {
        final neighborStates = <_NiedHypDetectionState>{
          for (final cluster in neighborSubclusters) cluster.state,
        };
        state = _referenceMergeAdjacentStates(
          station,
          neighborStates,
          observedAt: observedAt,
          updateVersion: updateVersion,
          stateByStationId: stateByStationId,
        );
        _referenceMergeAdjacentSubclusters(
          arriving: station,
          clusters: neighborSubclusters,
          mergedState: state,
        );
        assignmentReason = 'kanameishi_reference_adjacent_cluster';
      }
      _referenceAssignStation(
        state,
        station,
        observedAt: observedAt,
        updateVersion: updateVersion,
        stateByStationId: stateByStationId,
        reason: assignmentReason,
      );
      _referenceAddStationToSubcluster(state, station);
    }

    _referenceRemoveInactiveStates(
      frame.inactiveStations,
      updateVersion: updateVersion,
      observedAt: observedAt,
    );
    return _referenceWorkerFrames(frame);
  }

  Map<String, _NiedHypDetectionState> _referenceActiveStatesByStationId() {
    _synchronizeReferenceSubclusters();
    final result = <String, _NiedHypDetectionState>{};
    for (final state in detectionIds.values) {
      if (!state.active) continue;
      for (final station in state.worker.activeStationsByCode.values) {
        result[station.id] = state;
      }
    }
    return result;
  }

  void _synchronizeReferenceSubclusters() {
    final activeStates = detectionIds.values
        .where((state) => state.active)
        .toSet();
    _referenceSubclustersById.removeWhere(
      (_, cluster) => !activeStates.contains(cluster.state),
    );
    _referenceSubclusterIdByStationId.removeWhere(
      (_, clusterId) => !_referenceSubclustersById.containsKey(clusterId),
    );
    for (final state in activeStates) {
      if (_referenceSubclusterForState(state) != null) continue;
      final cluster = _referenceCreateSubcluster(state);
      for (final station in _referenceOrderedStations(state)) {
        cluster.insert(station);
        _referenceSubclusterIdByStationId[station.id] = cluster.id;
      }
    }
  }

  List<_NiedHypReferenceSubcluster> _referenceNeighborSubclusters(
    _NiedHypWorkerStation station,
    Map<String, Set<String>> adjacencyByStationId,
  ) {
    final result = <_NiedHypReferenceSubcluster>[];
    final seen = <int>{};
    for (final neighborId
        in adjacencyByStationId[station.id] ?? const <String>{}) {
      final subclusterId = _referenceSubclusterIdByStationId[neighborId];
      final subcluster = subclusterId == null
          ? null
          : _referenceSubclustersById[subclusterId];
      if (subcluster != null && seen.add(subcluster.id)) {
        result.add(subcluster);
      }
    }
    return result;
  }

  _NiedHypReferenceSubcluster _referenceCreateSubcluster(
    _NiedHypDetectionState state,
  ) {
    final cluster = _NiedHypReferenceSubcluster(
      id: _nextReferenceSubclusterId++,
      state: state,
    );
    _referenceSubclustersById[cluster.id] = cluster;
    return cluster;
  }

  _NiedHypReferenceSubcluster? _referenceSubclusterForState(
    _NiedHypDetectionState state,
  ) {
    for (final cluster in _referenceSubclustersById.values) {
      if (identical(cluster.state, state)) return cluster;
    }
    return null;
  }

  void _referenceAddStationToSubcluster(
    _NiedHypDetectionState state,
    _NiedHypWorkerStation station,
  ) {
    final cluster =
        _referenceSubclusterForState(state) ??
        _referenceCreateSubcluster(state);
    cluster.insert(station);
    _referenceSubclusterIdByStationId[station.id] = cluster.id;
  }

  _NiedHypReferenceSubcluster? _referenceBestResidualSubcluster(
    _NiedHypWorkerStation station,
  ) {
    final triggerAt = station.triggerAt;
    if (triggerAt == null) return null;
    _NiedHypReferenceSubcluster? selected;
    var selectedResidualSeconds = double.infinity;
    for (final cluster in _referenceSubclustersById.values) {
      final result = cluster.state.worker.previousResult;
      if (result == null || !result.score.isFinite) continue;
      final distanceKm = _haversineKm(
        result.latitude,
        result.longitude,
        station.coordinate.latitude,
        station.coordinate.longitude,
      );
      final originMilliseconds =
          cluster.state.worker.referencePreviousOriginMilliseconds ??
          result.originTime.millisecondsSinceEpoch.toDouble();
      final observedSeconds =
          (triggerAt.millisecondsSinceEpoch - originMilliseconds) / 1000.0;
      final pResidual =
          (observedSeconds -
                  KanameishiJma2001TravelTimeTable.travelTimeSeconds(
                    surfaceDistanceKm: distanceKm,
                    depthKm: result.depthKm,
                    pWave: true,
                  ))
              .abs();
      final sResidual =
          (observedSeconds -
                  KanameishiJma2001TravelTimeTable.travelTimeSeconds(
                    surfaceDistanceKm: distanceKm,
                    depthKm: result.depthKm,
                    pWave: false,
                  ))
              .abs();
      final residual = math.min(pResidual, sResidual);
      final limitSeconds = cluster.stationIds.length >= 50 ? 7.5 : 5.0;
      if (residual <= limitSeconds && residual < selectedResidualSeconds) {
        selected = cluster;
        selectedResidualSeconds = residual;
      }
    }
    return selected;
  }

  void _referenceMergeAdjacentSubclusters({
    required _NiedHypWorkerStation arriving,
    required List<_NiedHypReferenceSubcluster> clusters,
    required _NiedHypDetectionState mergedState,
  }) {
    final merged = _referenceCreateSubcluster(mergedState);
    // NiedHypoInf reconstructs a bridging cluster from the arriving station
    // followed by each old cluster's existing insertion order.
    merged.insert(arriving);
    for (final cluster in clusters) {
      for (final station in cluster.orderedStations) {
        merged.insert(station);
      }
      _referenceSubclustersById.remove(cluster.id);
    }
    for (final station in merged.orderedStations) {
      _referenceSubclusterIdByStationId[station.id] = merged.id;
    }
  }

  _NiedHypDetectionState _referenceCreateState(
    _NiedHypWorkerStation station, {
    required DateTime observedAt,
  }) {
    final id = _nextDetectionId++;
    final state = _NiedHypDetectionState(
      id: id,
      serial: id,
      createdAt: observedAt,
      firstStationCode: station.code,
    );
    detectionIds[id] = state;
    return state;
  }

  void _referenceAssignStation(
    _NiedHypDetectionState state,
    _NiedHypWorkerStation station, {
    required DateTime observedAt,
    required int updateVersion,
    required Map<String, _NiedHypDetectionState> stateByStationId,
    required String reason,
  }) {
    state.worker.activeStationsByCode[station.code] = station;
    _referenceInsertStationIntoOrder(state, station);
    stateByStationId[station.id] = state;
    _stationDetectionIdByCode[station.code] = state.id;
    state.worker.lastAssignmentAcceptedByCode[station.code] = reason;
    lastAssignmentAcceptedByCode[station.code] = reason;
    state.lastAssignedAt = observedAt;
    _referenceMarkUpdated(state, updateVersion);
  }

  void _referenceInsertStationIntoOrder(
    _NiedHypDetectionState state,
    _NiedHypWorkerStation station,
  ) {
    final order = state.referenceStationOrder;
    if (order.contains(station.code)) return;
    final triggerAt = station.triggerAt;
    if (triggerAt == null) return;
    var low = 0;
    var high = order.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final existing = state.worker.activeStationsByCode[order[middle]];
      final existingAt = existing?.triggerAt;
      if (existingAt != null && !existingAt.isAfter(triggerAt)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    order.insert(low, station.code);
  }

  List<_NiedHypWorkerStation> _referenceOrderedStations(
    _NiedHypDetectionState state,
  ) {
    final stations = <_NiedHypWorkerStation>[
      for (final code in state.referenceStationOrder)
        ?state.worker.activeStationsByCode[code],
    ];
    if (stations.length == state.worker.activeStationsByCode.length) {
      return stations;
    }
    final includedCodes = stations.map((station) => station.code).toSet();
    return [
      ...stations,
      for (final station in state.worker.activeStationsByCode.values)
        if (includedCodes.add(station.code)) station,
    ];
  }

  void _referenceMarkUpdated(_NiedHypDetectionState state, int updateVersion) {
    state.referenceDirty = true;
    if (state.referenceLastUpdateVersion != updateVersion) {
      state.referenceUpdates += 1;
      state.referenceLastUpdateVersion = updateVersion;
    }
  }

  _NiedHypDetectionState _referenceMergeAdjacentStates(
    _NiedHypWorkerStation arriving,
    Set<_NiedHypDetectionState> states, {
    required DateTime observedAt,
    required int updateVersion,
    required Map<String, _NiedHypDetectionState> stateByStationId,
  }) {
    final base = states.reduce(_referenceSelectMergeBaseState);
    final stations = <_NiedHypWorkerStation>[arriving];
    for (final state in states) {
      stations.addAll(_referenceOrderedStations(state));
      detectionIds.remove(state.id);
      state.active = false;
    }
    final merged = _referenceCreateState(stations.first, observedAt: observedAt)
      ..referenceUpdates = base.referenceUpdates
      ..referenceLastUpdateVersion = base.referenceLastUpdateVersion
      ..referenceReportNum = base.referenceReportNum;
    _referenceCopyWorkerState(merged.worker, base.worker);
    _referenceCopyPublishedHypocenterState(merged, base);
    for (final station in stations) {
      merged.worker.activeStationsByCode[station.code] = station;
      _referenceInsertStationIntoOrder(merged, station);
    }
    for (final station in _referenceOrderedStations(merged)) {
      stateByStationId[station.id] = merged;
      _stationDetectionIdByCode[station.code] = merged.id;
    }
    _referenceMarkUpdated(merged, updateVersion);
    return merged;
  }

  _NiedHypDetectionState _referenceSelectMergeBaseState(
    _NiedHypDetectionState left,
    _NiedHypDetectionState right,
  ) {
    final leftCount = left.worker.activeStationsByCode.length;
    final rightCount = right.worker.activeStationsByCode.length;
    if (leftCount != rightCount) return leftCount > rightCount ? left : right;
    return left.referenceUpdates >= right.referenceUpdates ? left : right;
  }

  void _referenceCopyWorkerState(
    _NiedHypWorkerState target,
    _NiedHypWorkerState source,
  ) {
    target
      ..previousResult = source.previousResult
      ..previousEstimate = source.previousEstimate
      ..referencePreviousOriginMilliseconds =
          source.referencePreviousOriginMilliseconds
      ..publishedCurvePanels = source.publishedCurvePanels
      ..publishedCurveRevision = source.publishedCurveRevision
      ..minimumPublishedScore = source.minimumPublishedScore;
    target.referencePreviousWavesByFirstWave
      ..clear()
      ..addAll({
        for (final entry in source.referencePreviousWavesByFirstWave.entries)
          entry.key: Map<String, bool>.from(entry.value),
      });
  }

  void _referenceCopyPublishedHypocenterState(
    _NiedHypDetectionState target,
    _NiedHypDetectionState source,
  ) {
    target
      ..referenceReportHypocenter = source.referenceReportHypocenter
      ..referenceStableHypocenter = source.referenceStableHypocenter
      ..referenceStableHypocenterUpdateCount =
          source.referenceStableHypocenterUpdateCount
      ..referenceStable = source.referenceStable;
    target.srevMagnitudePublicationState.copyFrom(
      source.srevMagnitudePublicationState,
    );
  }

  void _referenceRemoveInactiveStates(
    List<_NiedHypWorkerStation> inactiveStations, {
    required int updateVersion,
    required DateTime observedAt,
  }) {
    final inactiveIds = inactiveStations.map((station) => station.id).toSet();
    for (final state in detectionIds.values.toList(growable: false)) {
      final stations = state.worker.activeStationsByCode.values;
      final fullyInactive =
          stations.isNotEmpty &&
          stations.every((station) => inactiveIds.contains(station.id));
      if (!fullyInactive) {
        state.referenceInactiveUpdateCount = 0;
        continue;
      }
      _referenceMarkUpdated(state, updateVersion);
      state.referenceInactiveUpdateCount += 1;
      if (state.referenceInactiveUpdateCount < 10) continue;
      detectionIds.remove(state.id);
      state
        ..active = false
        ..inactiveAt = observedAt
        ..inactiveReason = 'kanameishi_reference_cluster_inactive_10_updates';
      for (final station in stations) {
        _stationDetectionIdByCode.remove(station.code);
      }
    }
  }

  bool mergeReferenceCloseClusters({required DateTime observedAt}) {
    final active = detectionIds.values
        .where((state) => state.active)
        .toList(growable: false);
    for (var leftIndex = 0; leftIndex < active.length; leftIndex++) {
      final left = active[leftIndex];
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < active.length;
        rightIndex++
      ) {
        final right = active[rightIndex];
        if (!_referenceClusterResultsCanMerge(left, right)) continue;
        _referenceMergeCloseStates(left, right, observedAt: observedAt);
        return true;
      }
    }
    return false;
  }

  bool _referenceClusterResultsCanMerge(
    _NiedHypDetectionState left,
    _NiedHypDetectionState right,
  ) {
    final leftResult = left.worker.previousResult;
    final rightResult = right.worker.previousResult;
    if (leftResult == null || rightResult == null) return false;
    if (!leftResult.score.isFinite || !rightResult.score.isFinite) return false;
    if ((leftResult.latitude - rightResult.latitude).abs() > 1.0) {
      return false;
    }
    final longitudeDifference = (leftResult.longitude - rightResult.longitude)
        .abs();
    if (math.min(longitudeDifference, 360.0 - longitudeDifference) > 1.0) {
      return false;
    }
    if ((leftResult.depthKm - rightResult.depthKm).abs() > 100.0) {
      return false;
    }
    return (leftResult.originTime
                .difference(rightResult.originTime)
                .inMilliseconds)
            .abs() <=
        10000;
  }

  void _referenceMergeCloseStates(
    _NiedHypDetectionState left,
    _NiedHypDetectionState right, {
    required DateTime observedAt,
  }) {
    final base = _referenceSelectMergeBaseState(left, right);
    final stations = <_NiedHypWorkerStation>[
      ..._referenceOrderedStations(left),
      ..._referenceOrderedStations(right),
    ];
    detectionIds
      ..remove(left.id)
      ..remove(right.id);
    left.active = false;
    right.active = false;
    final merged = _referenceCreateState(stations.first, observedAt: observedAt)
      ..referenceUpdates = base.referenceUpdates
      ..referenceLastUpdateVersion = base.referenceLastUpdateVersion
      ..referenceReportNum = base.referenceReportNum;
    _referenceCopyWorkerState(merged.worker, base.worker);
    _referenceCopyPublishedHypocenterState(merged, base);
    for (final station in stations) {
      merged.worker.activeStationsByCode[station.code] = station;
      _referenceInsertStationIntoOrder(merged, station);
    }
    for (final station in _referenceOrderedStations(merged)) {
      _stationDetectionIdByCode[station.code] = merged.id;
    }
  }

  Map<int, _NiedHypWorkerFrame> _referenceWorkerFrames(
    _NiedHypWorkerFrame frame,
  ) {
    final result = <int, _NiedHypWorkerFrame>{};
    for (final state in detectionIds.values) {
      if (!state.active) continue;
      final active = _referenceOrderedStations(state);
      final activeIds = active.map((station) => station.id).toSet();
      result[state.id] = _NiedHypWorkerFrame(
        newActiveStations: const <_NiedHypWorkerStation>[],
        activeStations: active,
        inactiveStations: frame.inactiveStations
            .where((station) => !activeIds.contains(station.id))
            .toList(growable: false),
        adjacencyByStationId: frame.adjacencyByStationId,
        detectionAdjacencyByCode: frame.detectionAdjacencyByCode,
        detectionGridDecimal: _gridDecimal,
        inactiveScope: frame.inactiveScope,
      );
    }
    return result;
  }

  void _clearReferenceForEmptyActiveStations() {
    lastSourceClearReason = 'kanameishi_reference_active_station_set_empty';
    detectionIds.clear();
    magnitudeIntensityState.clear();
    _stationDetectionIdByCode.clear();
    _gridCarrierByKey.clear();
    _selectedDetectionId = null;
    _nextDetectionId = 1;
    _referenceInactiveStationsKey = null;
    _referenceIgnoredArrivalIds.clear();
    _referenceSubclustersById.clear();
    _referenceSubclusterIdByStationId.clear();
    _nextReferenceSubclusterId = 1;
  }

  _NiedHypDetectionSelection? _selectDetectionId(
    _NiedHypWorkerStation station, {
    required _NiedHypWorkerFrame frame,
    required DateTime observedAt,
    required double? scratchRuntimeTimerSeconds,
  }) {
    final activeStates =
        detectionIds.values
            .where((state) => state.active)
            .toList(growable: false)
          ..sort((left, right) => left.serial.compareTo(right.serial));
    if (activeStates.isEmpty) {
      return detectionIds.length < 2
          ? _newDetectionId(station, observedAt: observedAt)
          : null;
    }

    if (scratchRuntimeTimerSeconds != null &&
        scratchRuntimeTimerSeconds >= 0 &&
        scratchRuntimeTimerSeconds < 10) {
      return _NiedHypDetectionSelection(
        activeStates.last,
        'scratch_id3_latest_id_shortcut',
      );
    }

    final nearest = _nearestExistingIdSelection(station, frame: frame);
    if (nearest != null) return nearest;

    final latestDistance = _latestIdDistanceSelection(
      station,
      observedAt: observedAt,
    );
    if (latestDistance != null) return latestDistance;

    final gridKey = _gridKey(station.coordinate);
    final currentCarrier = gridKey == null ? null : _gridCarrierByKey[gridKey];
    if (currentCarrier != null && currentCarrier.state.active) {
      final ageSeconds =
          observedAt.difference(currentCarrier.updatedAt).inMilliseconds /
          1000.0;
      if (ageSeconds >= 0 && ageSeconds < 2) {
        return _NiedHypDetectionSelection(
          currentCarrier.state,
          'scratch_grid_current',
        );
      }
    }

    _NiedHypDetectionState? bestState;
    double? bestResidual;
    String? bestReason;
    for (final state in activeStates.reversed) {
      final decision = _niedHypWorkerAssignmentDecision(
        station,
        state.worker.activeStationsByCode.values.toList(growable: false),
        state.worker.previousResult,
        observedAt: observedAt,
        allowInitialSeed: false,
      );
      if (!decision.accepted || decision.residualSeconds == null) continue;
      if (bestResidual == null || decision.residualSeconds! < bestResidual) {
        bestState = state;
        bestResidual = decision.residualSeconds;
        bestReason = decision.reason;
      }
    }
    if (bestState != null) {
      return _NiedHypDetectionSelection(bestState, bestReason!);
    }

    final around = _aroundGridCarrierSelection(station, observedAt: observedAt);
    if (around != null) return around;
    if (detectionIds.length < 2) {
      return _newDetectionId(station, observedAt: observedAt);
    }
    return null;
  }

  _NiedHypDetectionSelection? _nearestExistingIdSelection(
    _NiedHypWorkerStation station, {
    required _NiedHypWorkerFrame frame,
  }) {
    final candidateCodes = frame.detectionAdjacencyByCode[station.code];
    final candidates = <({String code, double distanceKm})>[];
    for (final entry in _stationDetectionIdByCode.entries) {
      if (candidateCodes != null && !candidateCodes.contains(entry.key)) {
        continue;
      }
      final state = detectionIds[entry.value];
      final neighbor = state?.worker.activeStationsByCode[entry.key];
      if (state == null || !state.active || neighbor == null) continue;
      final distanceKm = _haversineKm(
        station.coordinate.latitude,
        station.coordinate.longitude,
        neighbor.coordinate.latitude,
        neighbor.coordinate.longitude,
      );
      candidates.add((code: entry.key, distanceKm: distanceKm));
    }
    candidates.sort((left, right) {
      final distanceCompare = left.distanceKm.compareTo(right.distanceKm);
      return distanceCompare != 0
          ? distanceCompare
          : left.code.compareTo(right.code);
    });
    _NiedHypDetectionState? selected;
    var selectedDeltaSeconds = 10.0;
    for (final candidate in candidates.take(7)) {
      if (candidate.distanceKm > 40) break;
      final id = _stationDetectionIdByCode[candidate.code];
      final state = id == null ? null : detectionIds[id];
      final neighbor = state?.worker.activeStationsByCode[candidate.code];
      if (state == null ||
          neighbor?.triggerAt == null ||
          station.triggerAt == null) {
        continue;
      }
      final deltaSeconds =
          (station.triggerAt!.difference(neighbor!.triggerAt!).inMilliseconds)
              .abs() /
          1000.0;
      if (deltaSeconds < selectedDeltaSeconds) {
        selected = state;
        selectedDeltaSeconds = deltaSeconds;
      }
    }
    return selected == null
        ? null
        : _NiedHypDetectionSelection(
            selected,
            'scratch_id4_1_nearest7_existing_id',
          );
  }

  _NiedHypDetectionSelection? _latestIdDistanceSelection(
    _NiedHypWorkerStation station, {
    required DateTime observedAt,
  }) {
    final rows = detectionIds.values.toList(growable: false)
      ..sort((left, right) => left.serial.compareTo(right.serial));
    if (rows.isEmpty) return null;
    final latest = rows.last;
    if (!latest.active) return null;
    if (rows.length >= 2) {
      final previous = rows[rows.length - 2];
      final previousAgeSeconds =
          observedAt.difference(previous.createdAt).inMilliseconds / 1000.0;
      if (previous.worker.activeStationsByCode.length <= 2 ||
          previousAgeSeconds <= 40) {
        return null;
      }
    }
    final ageSeconds =
        observedAt.difference(latest.createdAt).inMilliseconds / 1000.0;
    if (ageSeconds < 0 || ageSeconds >= 10) return null;
    final first = latest.worker.activeStationsByCode[latest.firstStationCode];
    if (first == null) return null;
    final distanceKm = _haversineKm(
      first.coordinate.latitude,
      first.coordinate.longitude,
      station.coordinate.latitude,
      station.coordinate.longitude,
    );
    if (distanceKm >= 400) return null;
    return _NiedHypDetectionSelection(latest, 'scratch_id4_latest_id_distance');
  }

  _NiedHypDetectionSelection? _aroundGridCarrierSelection(
    _NiedHypWorkerStation station, {
    required DateTime observedAt,
  }) {
    final center = _gridIndices(station.coordinate);
    if (center == null) return null;
    _NiedHypGridCarrier? best;
    for (var latitudeOffset = -1; latitudeOffset <= 1; latitudeOffset++) {
      for (var longitudeOffset = -1; longitudeOffset <= 1; longitudeOffset++) {
        final key = niedDetectionGridKey(
          center.latitude + latitudeOffset,
          center.longitude + longitudeOffset,
        );
        final carrier = _gridCarrierByKey[key];
        if (carrier == null || !carrier.state.active) continue;
        final ageSeconds =
            observedAt.difference(carrier.updatedAt).inMilliseconds / 1000.0;
        if (ageSeconds < 0 || ageSeconds > 5) continue;
        if (best == null || carrier.updatedAt.isAfter(best.updatedAt)) {
          best = carrier;
        }
      }
    }
    return best == null
        ? null
        : _NiedHypDetectionSelection(best.state, 'scratch_grid_around_9');
  }

  _NiedHypDetectionSelection _newDetectionId(
    _NiedHypWorkerStation station, {
    required DateTime observedAt,
  }) {
    final id = _nextDetectionId++;
    final state = _NiedHypDetectionState(
      id: id,
      serial: id,
      createdAt: observedAt,
      firstStationCode: station.code,
    );
    detectionIds[id] = state;
    return _NiedHypDetectionSelection(state, 'scratch_id3_new_detection_id');
  }

  void _assignStation(
    _NiedHypDetectionState state,
    _NiedHypWorkerStation station, {
    required DateTime observedAt,
    required String reason,
  }) {
    final previousOwnerId = _stationDetectionIdByCode[station.code];
    if (previousOwnerId != null && previousOwnerId != state.id) {
      detectionIds[previousOwnerId]?.worker.activeStationsByCode.remove(
        station.code,
      );
      detectionIds[previousOwnerId]?.worker.stationSFlagByCode.remove(
        station.code,
      );
    }
    state.worker.activeStationsByCode[station.code] = station;
    state.lastAssignedAt = observedAt;
    _stationDetectionIdByCode[station.code] = state.id;
    state.worker.lastAssignmentAcceptedByCode[station.code] = reason;
    lastAssignmentAcceptedByCode[station.code] = reason;
    final key = _gridKey(station.coordinate);
    if (key != null) {
      _gridCarrierByKey[key] = _NiedHypGridCarrier(
        state: state,
        updatedAt: observedAt,
        stationCode: station.code,
      );
    }
  }

  void _rebuildGridCarriers(
    List<_NiedHypWorkerStation> currentActive, {
    required DateTime observedAt,
  }) {
    _gridCarrierByKey.removeWhere((_, carrier) => !carrier.state.active);
    for (final station in currentActive) {
      final ownerId = _stationDetectionIdByCode[station.code];
      final state = ownerId == null ? null : detectionIds[ownerId];
      final key = _gridKey(station.coordinate);
      if (state == null || !state.active || key == null) continue;
      final prior = _gridCarrierByKey[key];
      _gridCarrierByKey[key] = _NiedHypGridCarrier(
        state: state,
        updatedAt: prior != null && prior.state.id == state.id
            ? prior.updatedAt
            : observedAt,
        stationCode: station.code,
      );
    }
  }

  void _updateActiveLifecycle(DateTime observedAt) {
    final presentIds = {
      for (final carrier in _gridCarrierByKey.values) carrier.state.id,
    };
    for (final state in detectionIds.values) {
      if (!state.active) continue;
      final ageSeconds =
          observedAt.difference(state.createdAt).inMilliseconds / 1000.0;
      if (!presentIds.contains(state.id) && ageSeconds > 2) {
        state
          ..active = false
          ..inactiveAt = observedAt
          ..inactiveReason = 'scratch_detection_id_grid_presence_disappeared';
        continue;
      }
      final assignedCount = state.worker.activeStationsByCode.length;
      final expireSeconds = assignedCount < 200 ? (3 + assignedCount) * 2 : 400;
      if (ageSeconds > expireSeconds) {
        state
          ..active = false
          ..inactiveAt = observedAt
          ..inactiveReason = 'scratch_detection_id_expire_at_passed';
        continue;
      }
      if (ageSeconds > 150 && assignedCount < 50) {
        state
          ..active = false
          ..inactiveAt = observedAt
          ..inactiveReason = 'scratch_detection_id_age_150_small_cluster';
        continue;
      }
      if (assignedCount < 2) {
        state
          ..active = false
          ..inactiveAt = observedAt
          ..inactiveReason = 'scratch_detection_id_member_count_below_2';
        continue;
      }

      final first = state.worker.activeStationsByCode[state.firstStationCode];
      var maxDetectedDistanceKm = 0.0;
      var maxJmaShindo = -1;
      if (first != null) {
        for (final station in state.worker.activeStationsByCode.values) {
          maxDetectedDistanceKm = math.max(
            maxDetectedDistanceKm,
            _scratchDetectionIdDistanceKm(first.coordinate, station.coordinate),
          );
          final level = station.level;
          if (level != null) {
            maxJmaShindo = math.max(
              maxJmaShindo,
              JpShindoScale.jmaNumberFromKanameishiLevel(level),
            );
          }
        }
      }
      final publishedScore =
          state.worker.previousResult?.score ?? double.infinity;
      if (assignedCount < 5 &&
          maxDetectedDistanceKm < 80 &&
          publishedScore > 3000 &&
          maxJmaShindo < 3 &&
          ageSeconds > 10) {
        state
          ..active = false
          ..inactiveAt = observedAt
          ..inactiveReason =
              'scratch_detection_id_small_low_intensity_high_error';
      }
    }
    if (_selectedDetectionId != null &&
        detectionIds[_selectedDetectionId]?.active != true) {
      _selectedDetectionId = null;
    }
  }

  void _clearForEmptyGridCarrier() {
    lastSourceClearReason = 'scratch_grid_carrier_id_set_empty';
    detectionIds.clear();
    magnitudeIntensityState.clear();
    _stationDetectionIdByCode.clear();
    _gridCarrierByKey.clear();
    _selectedDetectionId = null;
    _nextDetectionId = 1;
  }

  List<_NiedHypWorkerStation> _inactiveForDetectionId(
    _NiedHypDetectionState state,
    List<_NiedHypWorkerStation> inactive,
  ) {
    return inactive
        .where(
          (station) =>
              !state.worker.activeStationsByCode.containsKey(station.code),
        )
        .toList(growable: false);
  }

  void mergeSameSourceDetectionIds({required DateTime observedAt}) {
    final active =
        detectionIds.values
            .where(
              (state) =>
                  state.active &&
                  state.worker.previousResult != null &&
                  state.worker.previousResult!.score < 500,
            )
            .toList(growable: false)
          ..sort((left, right) => left.serial.compareTo(right.serial));
    if (active.length < 2) return;
    final source = active[active.length - 2];
    final target = active.last;
    final firstDetectionDeltaSeconds =
        (target.createdAt.difference(source.createdAt).inMilliseconds).abs() /
        1000.0;
    if (firstDetectionDeltaSeconds >= 20) return;
    final sourceResult = source.worker.previousResult!;
    final targetResult = target.worker.previousResult!;
    final distanceKm = _haversineKm(
      sourceResult.latitude,
      sourceResult.longitude,
      targetResult.latitude,
      targetResult.longitude,
    );
    final averageRadius =
        (_maxFirstStationDistance(source) + _maxFirstStationDistance(target)) /
        2.0;
    if (distanceKm >= 50 + averageRadius / 2.0) return;

    for (final entry in source.worker.activeStationsByCode.entries) {
      target.worker.activeStationsByCode.putIfAbsent(
        entry.key,
        () => entry.value,
      );
      _stationDetectionIdByCode[entry.key] = target.id;
    }
    for (final entry in source.worker.stationSFlagByCode.entries) {
      target.worker.stationSFlagByCode.putIfAbsent(
        entry.key,
        () => entry.value,
      );
    }
    if (sourceResult.score < targetResult.score) {
      target.worker
        ..previousResult = sourceResult
        ..previousEstimate = source.worker.previousEstimate
        ..publishedCurvePanels = source.worker.publishedCurvePanels;
    }
    final sourceMinimum = source.worker.minimumPublishedScore;
    final targetMinimum = target.worker.minimumPublishedScore;
    if (sourceMinimum != null) {
      target.worker.minimumPublishedScore = targetMinimum == null
          ? sourceMinimum
          : math.min(sourceMinimum, targetMinimum);
    }
    target
      ..lastOutputBaseEstimate = null
      ..lastOutputEstimate = null;
    for (final entry in _gridCarrierByKey.entries.toList(growable: false)) {
      if (entry.value.state.id != source.id) continue;
      _gridCarrierByKey[entry.key] = _NiedHypGridCarrier(
        state: target,
        updatedAt: entry.value.updatedAt,
        stationCode: entry.value.stationCode,
      );
    }
    source
      ..active = false
      ..inactiveAt = observedAt
      ..inactiveReason = 'scratch_same_source_merged_into_${target.id}';
    if (_selectedDetectionId == source.id) _selectedDetectionId = target.id;
    _sameSourceMergeCount += 1;
  }

  double _maxFirstStationDistance(_NiedHypDetectionState state) {
    final first = state.worker.activeStationsByCode[state.firstStationCode];
    if (first == null) return 0;
    var maximum = 0.0;
    for (final station in state.worker.activeStationsByCode.values) {
      maximum = math.max(
        maximum,
        _scratchDetectionIdDistanceKm(first.coordinate, station.coordinate),
      );
    }
    return maximum;
  }

  int? selectOutputDetectionId({
    required Set<String> currentActiveCodes,
    required Set<int> estimatedIds,
  }) {
    final candidates = estimatedIds
        .map((id) => detectionIds[id])
        .whereType<_NiedHypDetectionState>()
        .where((state) => state.active)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      final leftOverlap = left.worker.activeStationsByCode.keys
          .where(currentActiveCodes.contains)
          .length;
      final rightOverlap = right.worker.activeStationsByCode.keys
          .where(currentActiveCodes.contains)
          .length;
      final overlapCompare = rightOverlap.compareTo(leftOverlap);
      if (overlapCompare != 0) return overlapCompare;
      if (left.id == _selectedDetectionId) return -1;
      if (right.id == _selectedDetectionId) return 1;
      return right.serial.compareTo(left.serial);
    });
    _selectedDetectionId = candidates.first.id;
    return _selectedDetectionId;
  }

  List<Map<String, Object?>> diagnostics({
    required Map<int, SourceEstimate> estimatesById,
    required int? selectedId,
    required DateTime observedAt,
  }) {
    final states = detectionIds.values.toList(growable: false)
      ..sort((left, right) => left.serial.compareTo(right.serial));
    return List<Map<String, Object?>>.unmodifiable([
      for (final state in states)
        {
          'id': state.id,
          'serial': state.serial,
          'selected': state.id == selectedId,
          'active': state.active,
          'created_at': state.createdAt.toIso8601String(),
          'age_s':
              observedAt.difference(state.createdAt).inMilliseconds / 1000.0,
          'last_assigned_at': state.lastAssignedAt.toIso8601String(),
          'first_station_code': state.firstStationCode,
          'station_order_model':
              'ka_active_station_table_order_matching_scratch_point_index',
          'assigned_station_order': state.worker.activeStationsByCode.keys
              .toList(growable: false),
          'assigned_station_count': state.worker.activeStationsByCode.length,
          'assigned_station_codes':
              (state.worker.activeStationsByCode.keys.toList()..sort()),
          'cached_s_flag_count': state.worker.stationSFlagByCode.values
              .where((value) => value)
              .length,
          'has_estimate': estimatesById.containsKey(state.id),
          'report_num': state.referenceReportNum,
          'stable': state.referenceStable,
          'stable_update_count': state.referenceStableHypocenterUpdateCount,
          'score': state.worker.previousResult?.score.isFinite == true
              ? state.worker.previousResult!.score
              : null,
          'inactive_at': state.inactiveAt?.toIso8601String(),
          'inactive_reason': state.inactiveReason,
          'grid_carrier_count': _gridCarrierByKey.values
              .where((entry) => entry.state.id == state.id)
              .length,
          'same_source_merge_count': _sameSourceMergeCount,
          'output_selection_model':
              'current_ka_active_station_overlap_keep_previous_on_tie',
        },
    ]);
  }

  List<Map<String, Object?>> sourceSnapshots({
    required Map<int, SourceEstimate> estimatesById,
    required int? selectedId,
  }) {
    final states = detectionIds.values.toList(growable: false)
      ..sort((left, right) => left.serial.compareTo(right.serial));
    return List<Map<String, Object?>>.unmodifiable([
      for (final state in states)
        if (estimatesById[state.id] case final estimate?)
          {
            'detection_id': state.id,
            'selected': state.id == selectedId,
            'latitude': estimate.latitude,
            'longitude': estimate.longitude,
            'depth_km': estimate.depthKm,
            'magnitude': estimate.magnitude,
            'origin_time': estimate.originTime?.toIso8601String(),
            'confidence': estimate.confidence,
            'method': estimate.method,
            'supporting_station_count': estimate.supportingStationCount,
            'assigned_station_count': state.worker.activeStationsByCode.length,
            'report_num': state.referenceReportNum,
            'stable': state.referenceStable,
            'stable_update_count': state.referenceStableHypocenterUpdateCount,
            'score': state.worker.previousResult?.score.isFinite == true
                ? state.worker.previousResult!.score
                : null,
            'diagnostics': {
              for (final key in const <String>[
                'error_level',
                'score',
                'wave_elapsed_s',
                'wave_radius_cap_km',
                'best_source_p_radius_km',
                'best_source_s_radius_km',
                'best_source_error',
              ])
                if (estimate.diagnostics.containsKey(key))
                  key: estimate.diagnostics[key],
              'nied_dart_hyp_report_num': state.referenceReportNum,
              'nied_dart_hyp_stable': state.referenceStable,
              'nied_dart_hyp_stable_update_count':
                  state.referenceStableHypocenterUpdateCount,
              'nied_dart_hyp_selected': state.id == selectedId,
              'selected_detection_id': state.id,
            },
          },
    ]);
  }

  ({int latitude, int longitude})? _gridIndices(LatLng coordinate) {
    final decimal = _gridDecimal;
    if (decimal == null) return null;
    return (
      latitude: niedDetectionGridAxisIndex(
        coordinate.latitude,
        decimal.latitude,
      ),
      longitude: niedDetectionGridAxisIndex(
        coordinate.longitude,
        decimal.longitude,
      ),
    );
  }

  String? _gridKey(LatLng coordinate) {
    final indices = _gridIndices(coordinate);
    return indices == null
        ? null
        : niedDetectionGridKey(indices.latitude, indices.longitude);
  }

  void _reset() {
    detectionIds.clear();
    _stationDetectionIdByCode.clear();
    _gridCarrierByKey.clear();
    lastAssignmentAcceptedByCode.clear();
    lastAssignmentRejectedByCode.clear();
    _nextDetectionId = 1;
    _selectedDetectionId = null;
    _gridDecimal = null;
    _sameSourceMergeCount = 0;
    _referenceIgnoredArrivalIds.clear();
    _referenceSubclustersById.clear();
    _referenceSubclusterIdByStationId.clear();
    _nextReferenceSubclusterId = 1;
    magnitudeIntensityState.clear();
    lastSourceClearReason = 'scratch_event_time_reversed_reset';
  }
}

class _NiedHypDetectionState {
  _NiedHypDetectionState({
    required this.id,
    required this.serial,
    required this.createdAt,
    required this.firstStationCode,
  }) : lastAssignedAt = createdAt;

  final int id;
  final int serial;
  final DateTime createdAt;
  final String firstStationCode;
  final _NiedHypWorkerState worker = _NiedHypWorkerState();
  final List<String> referenceStationOrder = <String>[];
  DateTime lastAssignedAt;
  bool active = true;
  DateTime? inactiveAt;
  String? inactiveReason;
  int referenceUpdates = 0;
  int referenceReportNum = 0;
  final SrevKaizouMagnitudePublicationState srevMagnitudePublicationState =
      SrevKaizouMagnitudePublicationState();
  _NiedPublishedHypocenter? referenceReportHypocenter;
  _NiedPublishedHypocenter? referenceStableHypocenter;
  int referenceStableHypocenterUpdateCount = 0;
  bool referenceStable = false;
  int referenceInactiveUpdateCount = 0;
  int? referenceLastUpdateVersion;
  bool referenceDirty = true;
  bool referenceEvaluated = false;
  SourceEstimate? lastOutputBaseEstimate;
  SourceEstimate? lastOutputEstimate;

  void refreshPublishedHypocenterState(
    SourceEstimate? estimate, {
    required int stableThreshold,
    required double epsilon,
  }) {
    if (estimate == null) {
      referenceStableHypocenter = null;
      referenceStableHypocenterUpdateCount = 0;
      referenceStable = false;
      return;
    }

    final hypocenter = _NiedPublishedHypocenter.fromEstimate(estimate);
    if (!_samePublishedHypocenter(
      referenceReportHypocenter,
      hypocenter,
      epsilon,
    )) {
      referenceReportNum += 1;
      referenceReportHypocenter = hypocenter;
    }

    if (_samePublishedHypocenter(
      referenceStableHypocenter,
      hypocenter,
      epsilon,
    )) {
      referenceStableHypocenterUpdateCount += 1;
    } else {
      referenceStableHypocenter = hypocenter;
      referenceStableHypocenterUpdateCount = 1;
      referenceStable = false;
    }
    if (referenceStableHypocenterUpdateCount >= stableThreshold) {
      referenceStable = true;
    }
  }

  int get expireSeconds {
    final count = worker.activeStationsByCode.length;
    return count < 200 ? (3 + count) * 2 : 400;
  }

  DateTime get expireAt => createdAt.add(Duration(seconds: expireSeconds));
}

class _NiedPublishedHypocenter {
  const _NiedPublishedHypocenter({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
  });

  factory _NiedPublishedHypocenter.fromEstimate(SourceEstimate estimate) =>
      _NiedPublishedHypocenter(
        latitude: estimate.latitude,
        longitude: estimate.longitude,
        depthKm: estimate.depthKm,
      );

  final double latitude;
  final double longitude;
  final double? depthKm;
}

bool _samePublishedHypocenter(
  _NiedPublishedHypocenter? left,
  _NiedPublishedHypocenter? right,
  double epsilon,
) {
  if (left == null || right == null) return false;
  final leftDepth = left.depthKm;
  final rightDepth = right.depthKm;
  if ((leftDepth == null) != (rightDepth == null)) return false;
  final longitudeDifference = (left.longitude - right.longitude).abs();
  return (left.latitude - right.latitude).abs() <= epsilon &&
      math.min(longitudeDifference, 360.0 - longitudeDifference) <= epsilon &&
      (leftDepth == null || (leftDepth - rightDepth!).abs() <= epsilon);
}

/// Reference-only cluster bookkeeping. The app-visible detection state remains
/// the owner of inference/output, while this preserves NiedHypoInf's exact
/// station insertion order across temporary adjacent clusters.
class _NiedHypReferenceSubcluster {
  _NiedHypReferenceSubcluster({required this.id, required this.state});

  final int id;
  final _NiedHypDetectionState state;
  final Map<String, _NiedHypWorkerStation> _stationsById =
      <String, _NiedHypWorkerStation>{};
  final List<String> stationIds = <String>[];

  List<_NiedHypWorkerStation> get orderedStations => [
    for (final id in stationIds) ?_stationsById[id],
  ];

  void insert(_NiedHypWorkerStation station) {
    final existing = _stationsById[station.id];
    _stationsById[station.id] = station;
    if (existing != null) return;
    final triggerAt = station.triggerAt;
    if (triggerAt == null) return;
    var low = 0;
    var high = stationIds.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final existingAt = _stationsById[stationIds[middle]]?.triggerAt;
      if (existingAt != null && !existingAt.isAfter(triggerAt)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    stationIds.insert(low, station.id);
  }
}

class _NiedHypDetectionSelection {
  const _NiedHypDetectionSelection(this.state, this.reason);

  final _NiedHypDetectionState state;
  final String reason;
}

class _NiedHypGridCarrier {
  const _NiedHypGridCarrier({
    required this.state,
    required this.updatedAt,
    required this.stationCode,
  });

  final _NiedHypDetectionState state;
  final DateTime updatedAt;
  final String stationCode;
}

_NiedHypWorkerStation _mergeNiedHypStation(
  _NiedHypWorkerStation? existing,
  _NiedHypWorkerStation incoming,
) {
  if (existing == null) return incoming;
  return _NiedHypWorkerStation(
    id: existing.id,
    code: existing.code,
    coordinate: existing.coordinate,
    triggerAt: existing.triggerAt,
    updateAt: incoming.updateAt ?? existing.updateAt,
    level: math.max(existing.level ?? -1, incoming.level ?? -1).toInt(),
    currentShindo: incoming.currentShindo,
    ascend: math.max(existing.ascend, incoming.ascend),
    active: true,
  );
}

class _NiedHypWorkerState {
  final Map<String, _NiedHypWorkerStation> activeStationsByCode =
      <String, _NiedHypWorkerStation>{};
  final Map<String, bool> stationSFlagByCode = <String, bool>{};
  final Map<String, Map<String, bool>> referencePreviousWavesByFirstWave =
      <String, Map<String, bool>>{'P': <String, bool>{}, 'S': <String, bool>{}};
  final Map<String, String> lastAssignmentAcceptedByCode = <String, String>{};
  final Map<String, String> lastAssignmentRejectedByCode = <String, String>{};
  _NiedHypWorkerResult? previousResult;
  SourceEstimate? previousEstimate;
  List<Map<String, Object?>>? publishedCurvePanels;
  int publishedCurveRevision = 0;
  double? minimumPublishedScore;
  double? referencePreviousOriginMilliseconds;
  DateTime? lastObservedAt;

  _NiedHypWorkerFrame mergeFrame(
    _NiedHypWorkerFrame frame, {
    required DateTime observedAt,
  }) {
    final previousObservedAt = lastObservedAt;
    if (previousObservedAt != null && observedAt.isBefore(previousObservedAt)) {
      activeStationsByCode.clear();
      stationSFlagByCode.clear();
      referencePreviousWavesByFirstWave
        ..clear()
        ..['P'] = <String, bool>{}
        ..['S'] = <String, bool>{};
      previousResult = null;
      previousEstimate = null;
      publishedCurvePanels = null;
      publishedCurveRevision = 0;
      minimumPublishedScore = null;
      referencePreviousOriginMilliseconds = null;
    }
    lastObservedAt = observedAt;
    lastAssignmentAcceptedByCode.clear();
    lastAssignmentRejectedByCode.clear();

    for (final incoming in frame.activeStations) {
      final existing = activeStationsByCode[incoming.code];
      if (existing == null) {
        final decision = _niedHypWorkerAssignmentDecision(
          incoming,
          activeStationsByCode.values.toList(growable: false),
          previousResult,
          observedAt: observedAt,
        );
        if (!decision.accepted) {
          lastAssignmentRejectedByCode[incoming.code] = decision.reason;
          continue;
        }
        lastAssignmentAcceptedByCode[incoming.code] = decision.reason;
        activeStationsByCode[incoming.code] = incoming;
        continue;
      }
      activeStationsByCode[incoming.code] = _NiedHypWorkerStation(
        id: existing.id,
        code: existing.code,
        coordinate: existing.coordinate,
        triggerAt: existing.triggerAt,
        updateAt: incoming.updateAt ?? existing.updateAt,
        level: math.max(existing.level ?? -1, incoming.level ?? -1).toInt(),
        currentShindo: incoming.currentShindo,
        ascend: math.max(existing.ascend, incoming.ascend),
        active: true,
      );
    }

    final active = activeStationsByCode.values.toList(growable: false)
      ..sort((left, right) {
        final leftAt = left.triggerAt;
        final rightAt = right.triggerAt;
        if (leftAt == null && rightAt == null) {
          return left.code.compareTo(right.code);
        }
        if (leftAt == null) return 1;
        if (rightAt == null) return -1;
        final timeCompare = leftAt.compareTo(rightAt);
        return timeCompare != 0 ? timeCompare : left.code.compareTo(right.code);
      });
    final inactive = frame.inactiveStations
        .where((station) => !activeStationsByCode.containsKey(station.code))
        .toList(growable: false);
    stationSFlagByCode.removeWhere(
      (code, _) => !activeStationsByCode.containsKey(code),
    );
    return _NiedHypWorkerFrame(
      newActiveStations: const <_NiedHypWorkerStation>[],
      activeStations: active,
      inactiveStations: inactive,
      adjacencyByStationId: frame.adjacencyByStationId,
      inactiveScope: frame.inactiveScope,
    );
  }
}

class _NiedHypWorkerStation {
  const _NiedHypWorkerStation({
    required this.id,
    required this.code,
    required this.coordinate,
    required this.triggerAt,
    required this.updateAt,
    required this.level,
    required this.currentShindo,
    required this.ascend,
    required this.active,
  });

  final String id;
  final String code;
  final LatLng coordinate;
  final DateTime? triggerAt;
  final DateTime? updateAt;
  final int? level;
  final double? currentShindo;
  final int ascend;
  final bool active;
}

class _NiedHypWorkerCandidateConstraints {
  const _NiedHypWorkerCandidateConstraints({
    required this.firstLatitude,
    required this.firstLongitude,
    required this.maxDetectedDistanceKm,
    required this.maxAllowedDepthKm,
    required this.maxAllowedDistanceKm,
    required this.referenceAligned,
  });

  final double firstLatitude;
  final double firstLongitude;
  final double maxDetectedDistanceKm;
  final double maxAllowedDepthKm;
  final double maxAllowedDistanceKm;
  final bool referenceAligned;
}

class _NiedHypWorkerResult {
  const _NiedHypWorkerResult({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.originTime,
    required this.originOffsetSeconds,
    required this.score,
    required this.errorLevel,
    required this.rmse,
    required this.weightSum,
    required this.weightedResidualSquares,
    required this.stationScale,
    required this.inactivePenalty,
    required this.inactivePRadiusKm,
    required this.inactiveReferenceDistanceKm,
    required this.inactivePenaltyWeight,
    required this.waveCountPenaltyMultiplier,
    required this.effectiveStationCount,
    required this.qualityScore,
    required this.qualityRank,
    required this.pWaveCount,
    required this.sWaveCount,
    required this.otherWaveCount,
    required this.searchStages,
    this.referencePreviousWavesByFirstWave =
        const <String, Map<String, bool>>{},
    this.referenceScenarioDiagnostics = const <String, Object?>{},
  });

  final double latitude;
  final double longitude;
  final double depthKm;
  final DateTime originTime;
  final double originOffsetSeconds;
  final double score;
  final double errorLevel;
  final double rmse;
  final double weightSum;
  final double weightedResidualSquares;
  final double stationScale;
  final double inactivePenalty;
  final double inactivePRadiusKm;
  final double inactiveReferenceDistanceKm;
  final double inactivePenaltyWeight;
  final double waveCountPenaltyMultiplier;
  final int effectiveStationCount;
  final double qualityScore;
  final String qualityRank;
  final int pWaveCount;
  final int sWaveCount;
  final int otherWaveCount;
  final List<Map<String, Object?>> searchStages;
  final Map<String, Map<String, bool>> referencePreviousWavesByFirstWave;
  // Only populated by the kanameishi-aligned experiment. This keeps replay
  // comparison evidence with the estimate without changing the default path.
  final Map<String, Object?> referenceScenarioDiagnostics;
}

class _NiedReferenceScenario {
  const _NiedReferenceScenario({
    required this.result,
    required this.wavesByStationId,
  });

  final _NiedHypWorkerResult result;
  final Map<String, bool> wavesByStationId;
}

({bool accepted, String reason, double? residualSeconds})
_niedHypWorkerAssignmentDecision(
  _NiedHypWorkerStation station,
  List<_NiedHypWorkerStation> assigned,
  _NiedHypWorkerResult? previousResult, {
  required DateTime observedAt,
  bool allowInitialSeed = true,
}) {
  if (assigned.isEmpty || (previousResult == null && allowInitialSeed)) {
    return (
      accepted: true,
      reason: 'initial_event_station_without_previous_source',
      residualSeconds: null,
    );
  }
  final timedAssigned =
      assigned.where((item) => item.triggerAt != null).toList(growable: false)
        ..sort((left, right) {
          final byTime = left.triggerAt!.compareTo(right.triggerAt!);
          return byTime != 0 ? byTime : left.code.compareTo(right.code);
        });
  final triggerAt = station.triggerAt;
  if (timedAssigned.isEmpty || triggerAt == null) {
    return (
      accepted: false,
      reason: 'scratch_4_2_reject_no_station_time',
      residualSeconds: null,
    );
  }
  final earliestAt = timedAssigned.first.triggerAt!;
  final detectionIdAgeSeconds =
      observedAt.difference(earliestAt).inMilliseconds / 1000.0;
  final useSourceCache =
      previousResult != null &&
      previousResult.score.isFinite &&
      detectionIdAgeSeconds > 5.0 &&
      previousResult.score < 500.0;

  late final double latitude;
  late final double longitude;
  late final double depthKm;
  late final double originOffsetSeconds;
  if (useSourceCache) {
    final sourceCache = previousResult;
    latitude = (sourceCache.latitude * 60.0).round() / 60.0;
    longitude = (sourceCache.longitude * 60.0).round() / 60.0;
    depthKm = sourceCache.depthKm.roundToDouble();
    originOffsetSeconds =
        (sourceCache.originTime.difference(earliestAt).inMilliseconds / 1000.0)
            .roundToDouble();
  } else if (assigned.length > 4) {
    latitude = _roundTo(timedAssigned.first.coordinate.latitude, 0.01);
    longitude = _roundTo(timedAssigned.first.coordinate.longitude, 0.01);
    depthKm = 10.0;
    originOffsetSeconds = -3.0;
  } else {
    return (
      accepted: false,
      reason: 'scratch_4_2_reject_no_source_or_fallback',
      residualSeconds: null,
    );
  }

  final surfaceDistanceKm = _haversineKm(
    latitude,
    longitude,
    station.coordinate.latitude,
    station.coordinate.longitude,
  );
  final hypocentralDistanceKm = math.sqrt(
    surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
  );
  final stationObservedSeconds =
      triggerAt.difference(earliestAt).inMilliseconds / 1000.0;
  final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
    hypocentralDistanceKm: hypocentralDistanceKm,
    depthKm: depthKm,
    pWave: true,
  );
  final pArrivalSeconds = originOffsetSeconds + pTravelSeconds;
  final pToleranceSeconds = 5.0 + surfaceDistanceKm / 120.0;
  final pResidualSeconds = (pArrivalSeconds - stationObservedSeconds).abs();
  if (pResidualSeconds <= pToleranceSeconds) {
    return (
      accepted: true,
      reason: 'scratch_4_2_accept_p_window',
      residualSeconds: pResidualSeconds,
    );
  }

  final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
    hypocentralDistanceKm: hypocentralDistanceKm,
    depthKm: depthKm,
    pWave: false,
  );
  final sArrivalSeconds = originOffsetSeconds + sTravelSeconds;
  final sToleranceSeconds = 8.0 + surfaceDistanceKm / 120.0;
  if (stationObservedSeconds < pArrivalSeconds - pToleranceSeconds) {
    return (
      accepted: false,
      reason: 'scratch_4_2_reject_before_p_window',
      residualSeconds: pResidualSeconds,
    );
  }
  if (stationObservedSeconds > sArrivalSeconds + sToleranceSeconds) {
    return (
      accepted: false,
      reason: 'scratch_4_2_reject_after_s_window',
      residualSeconds: (sArrivalSeconds - stationObservedSeconds).abs(),
    );
  }
  return (
    accepted: true,
    reason: 'scratch_4_2_accept_s_range',
    residualSeconds: (sArrivalSeconds - stationObservedSeconds).abs(),
  );
}

SourceEstimate? _estimateNiedHypWorkerFrame(
  SourceEstimationRequest request,
  _NiedHypWorkerFrame frame,
  _NiedHypWorkerState state, {
  required String firstStationCode,
  required DateTime detectionCreatedAt,
  required String methodId,
  required NiedHypWritebackPolicy writebackPolicy,
  required double historicalMinimumMultiplier,
  required NiedHypSearchSchedule searchSchedule,
}) {
  const minInferenceClusterSize = 5;
  final indexedClusterStations =
      frame.activeStations.indexed
          .where((entry) => entry.$2.triggerAt != null)
          .toList(growable: false)
        ..sort((left, right) {
          final byTime = left.$2.triggerAt!.compareTo(right.$2.triggerAt!);
          return byTime != 0 ? byTime : left.$1.compareTo(right.$1);
        });
  final clusterStations = indexedClusterStations
      .map((entry) => entry.$2)
      .toList(growable: false);
  final weightedActive = clusterStations
      .where((station) => station.ascend >= 2)
      .toList(growable: false);
  final zeroContributionStations = clusterStations
      .where((station) => station.ascend < 2)
      .toList(growable: false);
  final referenceAlignedSearch =
      searchSchedule == NiedHypSearchSchedule.referenceBroadFourStage;
  // NiedHypoInf admits a cluster once five active stations have formed.  A
  // station with a small/zero ascend may contribute little to the score, but
  // it must not make the cluster fail the HYP trigger threshold.
  if (clusterStations.length < minInferenceClusterSize) {
    request.metadata['nied_dart_hyp_worker_null_reason'] =
        'ka_active_cluster_count_below_5';
    request.metadata
      ..['nied_dart_hyp_worker_active_count'] = clusterStations.length
      ..['nied_dart_hyp_worker_effective_active_count'] = weightedActive.length
      ..['nied_dart_hyp_worker_zero_contribution_count'] =
          zeroContributionStations.length;
    return null;
  }
  // NiedHypoInf keeps zero-weight L stations in trigger order. They do not
  // enter residuals, but they do determine rank weights for the whole cluster.
  final active = referenceAlignedSearch ? clusterStations : weightedActive;
  final inactive = _niedHypWorkerNearbyInactiveStations(frame, active);

  // Relative chart/scoring time starts at the first station that actually
  // contributes to this pass. Shifting the reference leaves absolute origin
  // time and every residual unchanged, while excluded KA zero-weight members
  // no longer create a hidden offset in the published curve.
  final earliestAt = active.first.triggerAt!;
  _NiedHypWorkerStation? seedStation;
  for (final station in clusterStations) {
    if (station.code == firstStationCode) {
      seedStation = station;
      break;
    }
  }
  if (seedStation == null) {
    request.metadata['nied_dart_hyp_worker_null_reason'] =
        'scratch_detection_id_first_station_missing';
    request.metadata['nied_dart_hyp_worker_first_station_code'] =
        firstStationCode;
    return null;
  }
  final seedTriggerAt = referenceAlignedSearch
      ? earliestAt
      : seedStation.triggerAt!;
  final earliestStations = active
      .where((station) => station.triggerAt == earliestAt)
      .toList(growable: false);
  final seedLat = referenceAlignedSearch
      ? _roundTo(
          earliestStations
                  .map((station) => station.coordinate.latitude)
                  .reduce((sum, value) => sum + value) /
              earliestStations.length,
          0.1,
        )
      : (seedStation.coordinate.latitude * 60).roundToDouble() / 60.0;
  final seedLng = referenceAlignedSearch
      ? _roundTo(
          earliestStations
                  .map((station) => station.coordinate.longitude)
                  .reduce((sum, value) => sum + value) /
              earliestStations.length,
          0.1,
        )
      : (seedStation.coordinate.longitude * 60).roundToDouble() / 60.0;
  final seedOriginAt = seedTriggerAt.subtract(const Duration(seconds: 2));
  final candidateConstraints = _niedHypWorkerCandidateConstraints(
    active,
    firstStation: seedStation,
    referenceAligned: referenceAlignedSearch,
  );
  final elapsedSinceFirstTriggerSeconds =
      request.observedAt.difference(seedTriggerAt).inMilliseconds / 1000.0;
  final elapsedSinceDetectionSeconds =
      request.observedAt.difference(detectionCreatedAt).inMilliseconds / 1000.0;
  final hypAgeSeconds = elapsedSinceDetectionSeconds;
  final allowSWave = elapsedSinceDetectionSeconds > 15.0;
  final inactivePenaltyGateOpen =
      elapsedSinceDetectionSeconds <= 3.0 ||
      (elapsedSinceDetectionSeconds <= 10.0 && active.length < 30);
  request.metadata['nied_dart_hyp_worker_reused'] = false;
  final previousResult = state.previousResult;
  if (hypAgeSeconds >= 120.0) {
    final previousEstimate = state.previousEstimate;
    if (previousResult == null || previousEstimate == null) {
      request.metadata['nied_dart_hyp_worker_null_reason'] =
          'scratch_hyp_age_limit_without_published_source';
      return null;
    }
    final waveRadii = _niedHypWorkerWaveRadii(
      observedAt: request.observedAt,
      originTime: previousResult.originTime,
      depthKm: previousResult.depthKm,
      maxDetectedDistanceKm: candidateConstraints.maxDetectedDistanceKm,
    );
    request.metadata
      ..['nied_dart_hyp_worker_input'] = 'ka_nied_station_snapshot_v1'
      ..['nied_dart_hyp_worker_active_count'] = clusterStations.length
      ..['nied_dart_hyp_worker_effective_active_count'] = active.length
      ..['nied_dart_hyp_worker_zero_contribution_count'] =
          zeroContributionStations.length
      ..['nied_dart_hyp_worker_inactive_count'] = inactive.length
      ..remove('nied_dart_hyp_worker_null_reason');
    final estimate = SourceEstimate(
      latitude: previousEstimate.latitude,
      longitude: previousEstimate.longitude,
      depthKm: previousEstimate.depthKm,
      magnitude: previousEstimate.magnitude,
      originTime: previousEstimate.originTime,
      confidence: previousEstimate.confidence,
      method: previousEstimate.method,
      supportingStationCount: previousEstimate.supportingStationCount,
      diagnostics: {
        ...previousEstimate.diagnostics,
        'elapsed_since_first_trigger_s': elapsedSinceFirstTriggerSeconds,
        'elapsed_since_detection_id_created_s': elapsedSinceDetectionSeconds,
        'hyp_age_s': hypAgeSeconds,
        'hyp_calculation_enabled': false,
        'search_cycle_ran': false,
        'search_cycle_finished': true,
        'search_termination_reason': 'scratch_hyp_age_limit_120s',
        'wave_elapsed_s': waveRadii.elapsedSeconds,
        'wave_radius_cap_km': waveRadii.radiusCapKm,
        'wave_radius_visible': waveRadii.visible,
        'best_source_p_radius_km': waveRadii.pRadiusKm,
        'best_source_s_radius_km': waveRadii.sRadiusKm,
      },
    );
    state.previousEstimate = estimate;
    return estimate;
  }
  if (previousResult != null) {
    _refreshNiedHypWorkerStationSFlags(
      state.stationSFlagByCode,
      active,
      previousResult,
    );
  }
  final scoringSFlagByCode = Map<String, bool>.from(state.stationSFlagByCode);
  final useTemporaryEpicenter = referenceAlignedSearch
      ? previousResult == null
      : previousResult == null || elapsedSinceDetectionSeconds < 10.0;
  final startLatitude = useTemporaryEpicenter
      ? seedLat
      : previousResult.latitude;
  final startLongitude = useTemporaryEpicenter
      ? seedLng
      : previousResult.longitude;
  final startDepthKm = useTemporaryEpicenter ? 10.0 : previousResult.depthKm;
  final searchStopwatch = Stopwatch()..start();
  var candidateScoreCallCount = 1;
  var current = _scoreNiedHypWorkerCandidate(
    active,
    inactive,
    observedAt: request.observedAt,
    earliestAt: earliestAt,
    latitude: startLatitude,
    longitude: startLongitude,
    depthKm: startDepthKm,
    allowSWave: allowSWave,
    applyInactivePenalty: inactivePenaltyGateOpen,
    stationSFlagByCode: scoringSFlagByCode,
    candidateConstraints: candidateConstraints,
    adjacencyByStationId: frame.adjacencyByStationId,
    referenceAligned: referenceAlignedSearch,
    referencePreviousWavesByFirstWave: state.referencePreviousWavesByFirstWave,
  );
  final stages = <Map<String, Object?>>[];
  final steps = switch (searchSchedule) {
    NiedHypSearchSchedule.scratchViewerFiveStage =>
      <({double degree, double? depth, bool enabled, int moveLimit})>[
        (
          degree: 0.5,
          depth: null,
          enabled: active.length > 10,
          moveLimit: elapsedSinceDetectionSeconds < 5.0 ? 15 : 30,
        ),
        (
          degree: 0.1,
          depth: null,
          enabled: true,
          moveLimit: elapsedSinceDetectionSeconds < 5.0
              ? (active.length < 10 ? 6 : 40)
              : 80,
        ),
        (degree: 0.1, depth: 50.0, enabled: true, moveLimit: 100),
        (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 100),
        (degree: 1 / 60, depth: null, enabled: true, moveLimit: 10),
      ],
    NiedHypSearchSchedule.referenceBroadFourStage =>
      <({double degree, double? depth, bool enabled, int moveLimit})>[
        (degree: 3.0, depth: 100.0, enabled: true, moveLimit: 1000),
        (degree: 1.0, depth: 50.0, enabled: true, moveLimit: 1000),
        (degree: 0.3, depth: 20.0, enabled: true, moveLimit: 1000),
        (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 1000),
      ],
    NiedHypSearchSchedule.scratchFiveStageWithBroadRescue =>
      <({double degree, double? depth, bool enabled, int moveLimit})>[
        (
          degree: 0.5,
          depth: null,
          enabled: active.length > 10,
          moveLimit: elapsedSinceDetectionSeconds < 5.0 ? 15 : 30,
        ),
        (
          degree: 0.1,
          depth: null,
          enabled: true,
          moveLimit: elapsedSinceDetectionSeconds < 5.0
              ? (active.length < 10 ? 6 : 40)
              : 80,
        ),
        (degree: 0.1, depth: 50.0, enabled: true, moveLimit: 100),
        (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 100),
        (degree: 1 / 60, depth: null, enabled: true, moveLimit: 10),
        (degree: 3.0, depth: 100.0, enabled: true, moveLimit: 1000),
        (degree: 1.0, depth: 50.0, enabled: true, moveLimit: 1000),
        (degree: 0.3, depth: 20.0, enabled: true, moveLimit: 1000),
        (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 1000),
        (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 100),
        (degree: 1 / 60, depth: null, enabled: true, moveLimit: 10),
      ],
    NiedHypSearchSchedule.scratchFiveStageJointNeighborhood =>
      <({double degree, double? depth, bool enabled, int moveLimit})>[
        (
          degree: 0.5,
          depth: null,
          enabled: active.length > 10,
          moveLimit: elapsedSinceDetectionSeconds < 5.0 ? 15 : 30,
        ),
        (
          degree: 0.1,
          depth: null,
          enabled: true,
          moveLimit: elapsedSinceDetectionSeconds < 5.0
              ? (active.length < 10 ? 6 : 40)
              : 80,
        ),
        (degree: 0.1, depth: 50.0, enabled: true, moveLimit: 100),
        (degree: 0.1, depth: 10.0, enabled: true, moveLimit: 100),
        (degree: 1 / 60, depth: null, enabled: true, moveLimit: 10),
      ],
  };
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
      final rejectReason = _niedHypWorkerCandidateRejectReason(
        latitude: lat,
        longitude: lng,
        depthKm: depthKm,
        constraints: candidateConstraints,
      );
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
      final candidate = _scoreNiedHypWorkerCandidate(
        active,
        inactive,
        observedAt: request.observedAt,
        earliestAt: earliestAt,
        latitude: lat,
        longitude: lng,
        depthKm: depthKm,
        allowSWave: allowSWave,
        applyInactivePenalty: inactivePenaltyGateOpen,
        stationSFlagByCode: scoringSFlagByCode,
        candidateConstraints: candidateConstraints,
        adjacencyByStationId: frame.adjacencyByStationId,
        referenceAligned: referenceAlignedSearch,
        referencePreviousWavesByFirstWave:
            state.referencePreviousWavesByFirstWave,
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
          NiedHypSearchSchedule.scratchFiveStageJointNeighborhood) {
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
  searchStopwatch.stop();
  // NiedHypoInf keeps rejected clusters internally, but does not publish one
  // until it has at least one effective station with a real score. The
  // reference port uses a finite 1e12 sentinel for some rejected candidates,
  // so checking `isFinite` alone would leak a support-0 placeholder to the
  // map and unified UI.
  final hasPublishableResult =
      searchedResult.effectiveStationCount > 0 &&
      searchedResult.weightSum > 0 &&
      searchedResult.score.isFinite &&
      searchedResult.errorLevel.isFinite;
  if (!hasPublishableResult) {
    request.metadata['nied_dart_hyp_worker_null_reason'] =
        'nied_hyp_candidate_has_no_effective_station_result';
    return null;
  }
  final previousPublishedResult = state.previousResult;
  final minimumPublishedScore = state.minimumPublishedScore;
  final searchResultAccepted = referenceAlignedSearch
      ? true
      : switch (writebackPolicy) {
          _
              when previousPublishedResult == null ||
                  elapsedSinceDetectionSeconds < 10.0 =>
            true,
          NiedHypWritebackPolicy.historicalMinimumMultiplier =>
            minimumPublishedScore == null ||
                searchedResult.score <
                    minimumPublishedScore * historicalMinimumMultiplier,
          NiedHypWritebackPolicy.nonIncreasingCurrent =>
            searchedResult.score <= previousPublishedResult.score,
        };
  final result = searchResultAccepted
      ? searchedResult
      : previousPublishedResult!;
  late final List<Map<String, Object?>> curvePanels;
  if (searchResultAccepted) {
    curvePanels = _niedHypWorkerCurvePanels(
      result,
      active,
      earliestAt: earliestAt,
      allowSWave: allowSWave,
      stationSFlagByCode: scoringSFlagByCode,
      candidateConstraints: candidateConstraints,
    );
    state.publishedCurveRevision += 1;
    _refreshNiedHypWorkerStationSFlags(
      state.stationSFlagByCode,
      active,
      result,
    );
    state
      ..previousResult = result
      ..publishedCurvePanels = curvePanels
      ..minimumPublishedScore = minimumPublishedScore == null
          ? result.score
          : math.min(minimumPublishedScore, result.score);
    if (referenceAlignedSearch) {
      state.referencePreviousWavesByFirstWave
        ..clear()
        ..addAll({
          for (final entry in result.referencePreviousWavesByFirstWave.entries)
            entry.key: Map<String, bool>.from(entry.value),
        });
      state.referencePreviousOriginMilliseconds =
          earliestAt.millisecondsSinceEpoch +
          result.originOffsetSeconds * 1000.0;
    }
  } else {
    curvePanels =
        state.publishedCurvePanels ??
        _niedHypPublishedCurvePanelsFromEstimate(state.previousEstimate) ??
        const <Map<String, Object?>>[];
  }
  final waveRadii = _niedHypWorkerWaveRadii(
    observedAt: request.observedAt,
    originTime: result.originTime,
    depthKm: result.depthKm,
    maxDetectedDistanceKm: candidateConstraints.maxDetectedDistanceKm,
  );
  final confidence = _niedHypWorkerConfidence(result);
  request.metadata
    ..['nied_dart_hyp_worker_input'] = 'ka_nied_station_snapshot_v1'
    ..['nied_dart_hyp_worker_active_count'] = clusterStations.length
    ..['nied_dart_hyp_worker_effective_active_count'] = active.length
    ..['nied_dart_hyp_worker_zero_contribution_count'] =
        zeroContributionStations.length
    ..['nied_dart_hyp_worker_inactive_count'] = inactive.length
    ..remove('nied_dart_hyp_worker_null_reason');
  final estimate = SourceEstimate(
    latitude: result.latitude,
    longitude: result.longitude,
    depthKm: result.depthKm,
    originTime: result.originTime,
    confidence: confidence,
    method: methodId,
    supportingStationCount: result.effectiveStationCount,
    diagnostics: {
      'method': methodId,
      'input_format': 'ka_nied_station_snapshot_v1',
      'inactive_station_scope':
          frame.inactiveScope ?? 'legacy_hypocenter_adjacency',
      'detection_grid': request.metadata['nied_hypocenter_detection_grid'],
      'calculation_model': referenceAlignedSearch
          ? 'kanameishi_find_nied_hypocenter_reference_port_v1'
          : 'article_scratch_hypocenter_core_v2',
      'temporary_epicenter_seed_model': referenceAlignedSearch
          ? 'kanameishi_earliest_timestamp_station_mean_round_0_1_degree'
          : 'scratch_hyp_first_station_round_to_1_60_degree_origin_minus_2s',
      'search_start_model': useTemporaryEpicenter
          ? (referenceAlignedSearch
                ? 'kanameishi_initial_hypocenter_before_first_result'
                : 'article_step2_temporary_epicenter_within_first_10s')
          : (referenceAlignedSearch
                ? 'kanameishi_previous_cluster_hypocenter'
                : 'article_step2_previous_hypocenter_after_first_10s'),
      'elapsed_since_first_trigger_s': elapsedSinceFirstTriggerSeconds,
      'elapsed_since_detection_id_created_s': elapsedSinceDetectionSeconds,
      'hyp_age_s': hypAgeSeconds,
      'hyp_calculation_enabled': true,
      'search_cycle_ran': true,
      'search_cycle_finished': true,
      'search_candidate_score_call_count': candidateScoreCallCount,
      'search_elapsed_ms': searchStopwatch.elapsedMilliseconds,
      'search_termination_reason': 'scratch_all_enabled_stages_finished',
      'search_result_update_model': referenceAlignedSearch
          ? 'kanameishi_dirty_cluster_replaces_current_result'
          : switch (writebackPolicy) {
              NiedHypWritebackPolicy.historicalMinimumMultiplier =>
                'scratch_4_4_first_10s_or_below_historical_min_times_multiplier',
              NiedHypWritebackPolicy.nonIncreasingCurrent =>
                'experiment_first_10s_or_non_increasing_current_score',
            },
      'search_result_writeback_policy': writebackPolicy.name,
      'search_schedule': searchSchedule.name,
      'search_schedule_reference': switch (searchSchedule) {
        NiedHypSearchSchedule.scratchViewerFiveStage =>
          'scratch_project_hyp_viewer_five_stage',
        NiedHypSearchSchedule.referenceBroadFourStage =>
          'kanameishi_nied_hypo_inf_broad_four_stage_experiment_same_article_score',
        NiedHypSearchSchedule.scratchFiveStageWithBroadRescue =>
          'scratch_five_stage_then_broad_lower_score_only_then_fine_experiment',
        NiedHypSearchSchedule.scratchFiveStageJointNeighborhood =>
          'scratch_five_stage_with_joint_lat_lng_depth_neighbors_experiment',
      },
      'historical_minimum_score_multiplier': historicalMinimumMultiplier,
      'search_result_accepted': searchResultAccepted,
      'historical_minimum_published_score': state.minimumPublishedScore,
      'searched_result': {
        'latitude': searchedResult.latitude,
        'longitude': searchedResult.longitude,
        'depth_km': searchedResult.depthKm,
        'origin_time': searchedResult.originTime.toIso8601String(),
        'score': searchedResult.score,
      },
      's_wave_gate_open': allowSWave,
      'phase_cache_reference_model':
          'scratch_4_4_quantized_assignment_only_lat_lng_1_60_depth_origin_integer',
      'station_assignment_model':
          'scratch_4_2_previous_source_p_window_then_s_range',
      'station_contribution_model':
          'ka_zero_weight_gate_max_ascend_below_2_then_scratch_distance_weight',
      'cluster_station_count': clusterStations.length,
      'effective_input_station_count': active.length,
      'zero_contribution_station_count': zeroContributionStations.length,
      'zero_contribution_station_codes': [
        for (final station in zeroContributionStations.take(80)) station.code,
      ],
      'candidate_constraints': {
        'model': referenceAlignedSearch
            ? 'reference_hypocenter_normalized_global_domain'
            : 'scratch_hyp_dynamic_candidate_domain',
        'first_station_code': seedStation.code,
        'max_detected_distance_km': candidateConstraints.maxDetectedDistanceKm,
        'max_allowed_depth_km': candidateConstraints.maxAllowedDepthKm,
        'max_allowed_first_station_distance_km':
            candidateConstraints.maxAllowedDistanceKm,
        'latitude_min': referenceAlignedSearch ? -90.0 : 15.0,
        'latitude_max': referenceAlignedSearch ? 90.0 : 55.0,
        'longitude_min': referenceAlignedSearch ? -180.0 : 115.0,
        'longitude_max': referenceAlignedSearch ? 180.0 : 155.0,
      },
      'station_assignment_accepted': Map<String, String>.from(
        state.lastAssignmentAcceptedByCode,
      ),
      'station_assignment_rejected': Map<String, String>.from(
        state.lastAssignmentRejectedByCode,
      ),
      'cached_s_flag_count': state.stationSFlagByCode.values
          .where((isS) => isS)
          .length,
      'historical_active_count': clusterStations.length,
      'temporary_epicenter_seed': {
        'station_code': seedStation.code,
        'trigger_at': seedTriggerAt.toIso8601String(),
        'origin_time': seedOriginAt.toIso8601String(),
        'latitude': seedLat,
        'longitude': seedLng,
        'depth_km': 10.0,
      },
      'search_steps': [
        for (final step in steps)
          {
            'degree': step.degree,
            'depth': step.depth,
            'enabled': step.enabled,
            'move_limit': step.moveLimit,
          },
      ],
      'score_model':
          'scratch_hyp_weighted_variance_station_scale_inactive_plus_s_multiplier',
      'inactive_penalty_gate_model':
          'kotoho7_article_elapsed_le_3_or_elapsed_le_10_and_active_lt_30',
      'inactive_penalty_gate_open': inactivePenaltyGateOpen,
      'score': result.score,
      'error_level': result.errorLevel,
      'rmse': result.rmse,
      'weight_sum': result.weightSum,
      'weighted_residual_squares': result.weightedResidualSquares,
      'station_scale': result.stationScale,
      'inactive_penalty': result.inactivePenalty,
      'inactive_p_radius_km': result.inactivePRadiusKm,
      'inactive_reference_distance_km': result.inactiveReferenceDistanceKm,
      'inactive_penalty_weight': result.inactivePenaltyWeight,
      'wave_count_penalty_multiplier': result.waveCountPenaltyMultiplier,
      'effective_station_count': result.effectiveStationCount,
      'quality_score': result.qualityScore,
      'quality_rank': result.qualityRank,
      'wave_counts': {
        'P': result.pWaveCount,
        'S': result.sWaveCount,
        'O': result.otherWaveCount,
      },
      if (result.referenceScenarioDiagnostics.isNotEmpty)
        'reference_scenario_diagnostics': result.referenceScenarioDiagnostics,
      'wave_radius_model': 'scratch_4_4_jma2001_inverse_capped_by_cluster',
      'wave_elapsed_s': waveRadii.elapsedSeconds,
      'wave_radius_cap_km': waveRadii.radiusCapKm,
      'wave_radius_visible': waveRadii.visible,
      'best_source_p_radius_km': waveRadii.pRadiusKm,
      'best_source_s_radius_km': waveRadii.sRadiusKm,
      'search': {'type': 'article_scratch_neighbor_descent', 'stages': stages},
      'map_candidate_model': 'published_result_only',
      'travel_time_curve_source': 'published_result_accepted_scoring_snapshot',
      'travel_time_curve_frozen': !searchResultAccepted,
      'travel_time_curve_revision': state.publishedCurveRevision,
      'travel_time_curve_sample_count': curvePanels.isEmpty
          ? 0
          : ((curvePanels.first['samples'] as List?)?.length ?? 0),
      'travel_time_curve_panels': curvePanels,
    },
  );
  state.previousEstimate = estimate;
  return estimate;
}

({
  double elapsedSeconds,
  double pRadiusKm,
  double sRadiusKm,
  double radiusCapKm,
  bool visible,
})
_niedHypWorkerWaveRadii({
  required DateTime observedAt,
  required DateTime originTime,
  required double depthKm,
  required double maxDetectedDistanceKm,
}) {
  const hiddenRadius = 999999.0;
  final radiusCapKm = 100.0 + maxDetectedDistanceKm * 3.0;
  final elapsedSeconds = math.max(
    0.0,
    observedAt.difference(originTime).inMilliseconds / 1000.0,
  );
  if (elapsedSeconds >= 300.0) {
    return (
      elapsedSeconds: elapsedSeconds,
      pRadiusKm: hiddenRadius,
      sRadiusKm: hiddenRadius,
      radiusCapKm: radiusCapKm,
      visible: false,
    );
  }
  return (
    elapsedSeconds: elapsedSeconds,
    pRadiusKm: math.min(
      Jma2001TravelTimeApproximation.epicentralRadiusKm(
        elapsedSeconds: elapsedSeconds,
        depthKm: depthKm,
        pWave: true,
      ),
      radiusCapKm,
    ),
    sRadiusKm: math.min(
      Jma2001TravelTimeApproximation.epicentralRadiusKm(
        elapsedSeconds: elapsedSeconds,
        depthKm: depthKm,
        pWave: false,
      ),
      radiusCapKm,
    ),
    radiusCapKm: radiusCapKm,
    visible: true,
  );
}

List<_NiedHypWorkerStation> _niedHypWorkerNearbyInactiveStations(
  _NiedHypWorkerFrame frame,
  List<_NiedHypWorkerStation> active,
) {
  if (frame.inactiveScope == 'ka_detection_surrounding_9_grid' ||
      frame.inactiveScope ==
          'ka_level_present_all_network_scratch_dynamic_radius') {
    return frame.inactiveStations;
  }
  if (frame.adjacencyByStationId.isEmpty) return frame.inactiveStations;
  final nearbyIds = <String>{};
  for (final station in active) {
    nearbyIds.addAll(frame.adjacencyByStationId[station.id] ?? const {});
  }
  return frame.inactiveStations
      .where((station) => nearbyIds.contains(station.id))
      .toList(growable: false);
}

List<Map<String, Object?>> _niedHypWorkerCurvePanels(
  _NiedHypWorkerResult center,
  List<_NiedHypWorkerStation> active, {
  required DateTime earliestAt,
  required bool allowSWave,
  required Map<String, bool> stationSFlagByCode,
  required _NiedHypWorkerCandidateConstraints candidateConstraints,
}) {
  return [
    _niedHypWorkerCurvePanel(
      center,
      active,
      earliestAt: earliestAt,
      label: 'current',
      selected: true,
      allowSWave: allowSWave,
      stationSFlagByCode: stationSFlagByCode,
      candidateConstraints: candidateConstraints,
    ),
  ];
}

List<Map<String, Object?>>? _niedHypPublishedCurvePanelsFromEstimate(
  SourceEstimate? estimate,
) {
  final rawPanels = estimate?.diagnostics['travel_time_curve_panels'];
  if (rawPanels is List<Map<String, Object?>>) return rawPanels;
  return null;
}

Map<String, Object?> _niedHypWorkerCurvePanel(
  _NiedHypWorkerResult result,
  List<_NiedHypWorkerStation> active, {
  required DateTime earliestAt,
  required String label,
  required bool selected,
  required bool allowSWave,
  required Map<String, bool> stationSFlagByCode,
  required _NiedHypWorkerCandidateConstraints candidateConstraints,
}) {
  final samples = <Map<String, Object?>>[];
  var maxDistanceKm = 0.0;
  var minObservedSeconds = double.infinity;
  var maxObservedSeconds = -double.infinity;
  final firstDetectedDistanceKm = _niedHypWorkerFirstDetectedDistanceKm(
    result.latitude,
    result.longitude,
    candidateConstraints,
  );
  final stationRows =
      <
        ({
          _NiedHypWorkerStation station,
          double distanceKm,
          double observedSeconds,
          double selectedTravelSeconds,
          double weight,
          bool useS,
        })
      >[];
  for (final station in active) {
    final distanceKm = _haversineKm(
      result.latitude,
      result.longitude,
      station.coordinate.latitude,
      station.coordinate.longitude,
    );
    if (distanceKm > maxDistanceKm) maxDistanceKm = distanceKm;
    final observedSeconds =
        station.triggerAt!.difference(earliestAt).inMilliseconds / 1000.0;
    if (observedSeconds < minObservedSeconds) {
      minObservedSeconds = observedSeconds;
    }
    if (observedSeconds > maxObservedSeconds) {
      maxObservedSeconds = observedSeconds;
    }
    final hypocentralDistanceKm = math.sqrt(
      distanceKm * distanceKm + result.depthKm * result.depthKm,
    );
    final useS = allowSWave && (stationSFlagByCode[station.code] ?? false);
    final selectedTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: result.depthKm,
      pWave: !useS,
    );
    final weight = _niedHypWorkerDistanceWeight(
      firstDetectedDistanceKm,
      distanceKm,
    );
    stationRows.add((
      station: station,
      distanceKm: distanceKm,
      observedSeconds: observedSeconds,
      selectedTravelSeconds: selectedTravel,
      weight: weight,
      useS: useS,
    ));
  }
  final originOffsetSeconds = result.originOffsetSeconds;
  for (final row in stationRows) {
    final station = row.station;
    final predictedSeconds = originOffsetSeconds + row.selectedTravelSeconds;
    samples.add({
      'id': station.id,
      'code': station.code,
      'latitude': station.coordinate.latitude,
      'longitude': station.coordinate.longitude,
      'trigger_stamp': station.triggerAt!.millisecondsSinceEpoch,
      'update_stamp': station.updateAt?.millisecondsSinceEpoch,
      'distance_km': row.distanceKm,
      'epicentral_distance_km': row.distanceKm,
      'hypocentral_distance_km': math.sqrt(
        row.distanceKm * row.distanceKm + result.depthKm * result.depthKm,
      ),
      'observed_s': row.observedSeconds,
      'predicted_s': predictedSeconds,
      'residual_s': row.observedSeconds - predictedSeconds,
      'wave': row.useS ? 'S' : 'P',
      'weight': row.weight,
      'level': station.level,
      'ascend': station.ascend,
    });
  }
  samples.sort(
    (left, right) => ((left['distance_km']! as num).toDouble()).compareTo(
      (right['distance_km']! as num).toDouble(),
    ),
  );
  // The panel is an inspection view of this exact scoring pass. Keep its
  // distance domain tied to the farthest real station instead of extending it
  // to a display-friendly synthetic boundary.
  final lineMaxKm = maxDistanceKm > 0 ? maxDistanceKm : 1.0;
  final activeTimingRmse = result.weightSum > 0
      ? math.sqrt(result.weightedResidualSquares / result.weightSum)
      : null;
  final pCurve = <Map<String, Object?>>[];
  final sCurve = <Map<String, Object?>>[];
  for (var i = 0; i <= 32; i++) {
    final distanceKm = lineMaxKm * i / 32.0;
    final hypocentralDistanceKm = math.sqrt(
      distanceKm * distanceKm + result.depthKm * result.depthKm,
    );
    final pTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: result.depthKm,
      pWave: true,
    );
    final sTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: result.depthKm,
      pWave: false,
    );
    pCurve.add({
      'distance_km': distanceKm,
      'arrival_s': originOffsetSeconds + pTravel,
    });
    sCurve.add({
      'distance_km': distanceKm,
      'arrival_s': originOffsetSeconds + sTravel,
    });
  }
  return {
    'label': label,
    'selected': selected,
    'latitude': result.latitude,
    'longitude': result.longitude,
    'depth_km': result.depthKm,
    'origin_time': result.originTime.toIso8601String(),
    'time_reference': earliestAt.toIso8601String(),
    'time_reference_model': 'earliest_effective_scoring_station_trigger',
    'distance_axis_model': 'epicentral_surface_distance_haversine_6371_km',
    'travel_time_model':
        'jma2001_scratch_polynomial_hypocentral_distance_input',
    'origin_offset_s': originOffsetSeconds,
    'score': result.score,
    'error_level': result.errorLevel,
    'rmse': result.rmse,
    'active_timing_rmse': activeTimingRmse,
    'weight_sum': result.weightSum,
    'weighted_residual_squares': result.weightedResidualSquares,
    'station_scale': result.stationScale,
    'wave_count_penalty_multiplier': result.waveCountPenaltyMultiplier,
    'p_wave_count': result.pWaveCount,
    's_wave_count': result.sWaveCount,
    'effective_station_count': result.effectiveStationCount,
    'inactive_penalty': result.inactivePenalty,
    'inactive_p_radius_km': result.inactivePRadiusKm,
    'inactive_reference_distance_km': result.inactiveReferenceDistanceKm,
    'quality_rank': result.qualityRank,
    'observed_min_s': minObservedSeconds.isFinite ? minObservedSeconds : null,
    'observed_max_s': maxObservedSeconds.isFinite ? maxObservedSeconds : null,
    'distance_max_km': maxDistanceKm,
    'samples': selected ? samples : samples.take(80).toList(growable: false),
    'curve': pCurve,
    'p_curve': pCurve,
    's_curve': sCurve,
  };
}

void _refreshNiedHypWorkerStationSFlags(
  Map<String, bool> stationSFlagByCode,
  List<_NiedHypWorkerStation> active,
  _NiedHypWorkerResult reference,
) {
  final referenceLatitude = (reference.latitude * 60.0).round() / 60.0;
  final referenceLongitude = (reference.longitude * 60.0).round() / 60.0;
  final referenceDepthKm = reference.depthKm.roundToDouble();
  final referenceOriginTime = DateTime.fromMillisecondsSinceEpoch(
    (reference.originTime.millisecondsSinceEpoch / 1000.0).round() * 1000,
    isUtc: reference.originTime.isUtc,
  );
  for (final station in active) {
    if (stationSFlagByCode.containsKey(station.code)) continue;
    final triggerAt = station.triggerAt;
    if (triggerAt == null) continue;
    final surfaceDistanceKm = _haversineKm(
      referenceLatitude,
      referenceLongitude,
      station.coordinate.latitude,
      station.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm +
          referenceDepthKm * referenceDepthKm,
    );
    final pTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: referenceDepthKm,
      pWave: true,
    );
    final sTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: referenceDepthKm,
      pWave: false,
    );
    final pArrival = referenceOriginTime.add(
      Duration(milliseconds: (pTravel * 1000).round()),
    );
    final sArrival = referenceOriginTime.add(
      Duration(milliseconds: (sTravel * 1000).round()),
    );
    final pResidualMs = triggerAt.difference(pArrival).inMilliseconds.abs();
    final sResidualMs = triggerAt.difference(sArrival).inMilliseconds.abs();
    stationSFlagByCode[station.code] = sResidualMs < pResidualMs;
  }
}

_NiedHypWorkerResult _scoreNiedReferenceCandidate(
  List<_NiedHypWorkerStation> active,
  List<_NiedHypWorkerStation> inactive, {
  required double latitude,
  required double longitude,
  required double depthKm,
  required DateTime earliestAt,
  required Map<String, Set<String>> adjacencyByStationId,
  required Map<String, Map<String, bool>> referencePreviousWavesByFirstWave,
}) {
  final stationCount = active.length;
  if (stationCount < 5) {
    return _invalidNiedHypWorkerResult(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originTime: earliestAt,
      activeCount: stationCount,
    );
  }
  final weights = List<double>.generate(stationCount, (index) {
    final station = active[index];
    final densityWeight =
        1.0 /
        math.sqrt(math.max(1, adjacencyByStationId[station.id]?.length ?? 0));
    final rankRatio = (index + 1) / math.max(stationCount, 100);
    final rankWeight = rankRatio <= 0.2
        ? 1.0
        : rankRatio <= 0.4
        ? 1.5 - rankRatio * 2.5
        : rankRatio <= 0.8
        ? 0.9 - rankRatio
        : 0.1;
    final ascendWeight = station.ascend >= 4
        ? math.min(0.2 * station.ascend, 2.0)
        : station.ascend >= 3
        ? 0.3
        : station.ascend >= 2
        ? 0.1
        : 0.0;
    return densityWeight * rankWeight * ascendWeight;
  });

  final pOrigins = List<double>.filled(stationCount, 0.0);
  final sOrigins = List<double>.filled(stationCount, 0.0);
  for (var index = 0; index < stationCount; index++) {
    final station = active[index];
    final distanceKm = _kanameishiHaversineKm(
      latitude,
      longitude,
      station.coordinate.latitude,
      station.coordinate.longitude,
    );
    final observedSeconds =
        station.triggerAt!.difference(earliestAt).inMilliseconds / 1000.0;
    pOrigins[index] =
        observedSeconds -
        KanameishiJma2001TravelTimeTable.travelTimeSeconds(
          surfaceDistanceKm: distanceKm,
          depthKm: depthKm,
          pWave: true,
        );
    sOrigins[index] =
        observedSeconds -
        KanameishiJma2001TravelTimeTable.travelTimeSeconds(
          surfaceDistanceKm: distanceKm,
          depthKm: depthKm,
          pWave: false,
        );
  }
  double originFor(int index, bool useS) =>
      useS ? sOrigins[index] : pOrigins[index];

  double? weightedOriginForIndexes(Iterable<int> indexes, List<bool?> waves) {
    var sum = 0.0;
    var weightSum = 0.0;
    for (final index in indexes) {
      final wave = waves[index];
      if (wave == null || weights[index] <= 0) continue;
      sum += originFor(index, wave) * weights[index];
      weightSum += weights[index];
    }
    return weightSum > 0 ? sum / weightSum : null;
  }

  double? weightedOrigin(List<bool?> waves) =>
      weightedOriginForIndexes(Iterable<int>.generate(stationCount), waves);

  void inferMissingWaves(List<bool?> waves, List<int> orderedOriginIndexes) {
    // NiedHypoInf.js retains originEntries in insertion order: the two anchors
    // first, then each middle-out inference. The floating-point accumulation
    // affects close P/S scenario comparisons, so do not rebuild by station ID.
    for (final index in _niedReferenceMiddleOutIndexes(stationCount)) {
      if (waves[index] != null) continue;
      final center = weightedOriginForIndexes(orderedOriginIndexes, waves);
      if (center == null || weights[index] <= 0) continue;
      final pDifference = (originFor(index, false) - center).abs();
      final sDifference = (originFor(index, true) - center).abs();
      // calcGreedyScenarioLikelihood() uses the default residual filter once
      // 30 weighted stations have established an origin-time center.
      if (orderedOriginIndexes.length >= 30) {
        var residualSum = 0.0;
        for (final item in orderedOriginIndexes) {
          residualSum += (originFor(item, waves[item]!) - center).abs();
        }
        final meanResidual = residualSum / orderedOriginIndexes.length;
        final threshold = math.max(meanResidual * 3.0, 5.0);
        if (pDifference > threshold && sDifference > threshold) continue;
      }
      waves[index] = pDifference <= sDifference * 2.0 ? false : true;
      orderedOriginIndexes.add(index);
    }
  }

  _NiedReferenceScenario? scoreScenario(
    List<bool?> waves, {
    required String scenario,
    required String firstWave,
    String? lastWave,
    int filterStageLevel = 0,
    List<int>? orderedOriginIndexes,
  }) {
    final originIndexes =
        orderedOriginIndexes ??
        <int>[
          for (var index = 0; index < stationCount; index++)
            if (waves[index] != null && weights[index] > 0) index,
        ];
    final originSeconds = weightedOriginForIndexes(originIndexes, waves);
    if (originSeconds == null) return null;
    var weightSum = 0.0;
    var residualSquares = 0.0;
    var pCount = 0;
    var sCount = 0;
    var lCount = 0;
    var oCount = 0;
    for (final index in originIndexes) {
      final wave = waves[index]!;
      final weight = weights[index];
      final residual = originFor(index, wave) - originSeconds;
      weightSum += weight;
      residualSquares += weight * residual * residual;
    }
    for (var index = 0; index < stationCount; index++) {
      final wave = waves[index];
      final weight = weights[index];
      if (wave == null) {
        if (weight <= 0) {
          lCount += 1;
        } else {
          oCount += 1;
        }
      } else if (wave) {
        sCount += 1;
      } else {
        pCount += 1;
      }
    }
    final effectiveCount = pCount + sCount;
    if (weightSum <= 0 || effectiveCount == 0) return null;

    final referenceDistances = <double>[
      for (final station in active)
        if (station.ascend >= 3 && (station.level ?? -1) >= 4)
          _kanameishiHaversineKm(
            latitude,
            longitude,
            station.coordinate.latitude,
            station.coordinate.longitude,
          ),
    ]..sort();
    var inactivePenalty = 0.0;
    if (referenceDistances.isNotEmpty) {
      final referenceDistance =
          referenceDistances[math.max(
            (referenceDistances.length * 0.9).floor() - 1,
            0,
          )];
      final inactiveDistances = <double>[
        for (final station in inactive)
          if (station.updateAt != null)
            _kanameishiHaversineKm(
              latitude,
              longitude,
              station.coordinate.latitude,
              station.coordinate.longitude,
            ),
      ]..sort();
      final penalized = inactiveDistances
          .takeWhile((distance) => distance <= referenceDistance)
          .length;
      if (inactiveDistances.length > effectiveCount &&
          inactiveDistances[effectiveCount] <= referenceDistance) {
        return null;
      }
      inactivePenalty = penalized / effectiveCount;
    }
    final rmse = math.sqrt(residualSquares / weightSum);
    final inactiveWeight = effectiveCount >= 50
        ? 0.0
        : 10.0 * (1.0 - effectiveCount / 50.0);
    final waveMultiplier = math.min(
      math.max(sCount / math.max(1, pCount) - 2.0, 1.0),
      3.0,
    );
    final score = (rmse + inactivePenalty * inactiveWeight) * waveMultiplier;
    final qualityScore =
        3.8 + math.sqrt(effectiveCount / 10.0) * 0.2 - score * 5.0 / 3.0;
    final result = _NiedHypWorkerResult(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originTime: earliestAt.add(
        Duration(milliseconds: (originSeconds * 1000).round()),
      ),
      originOffsetSeconds: originSeconds,
      score: score,
      errorLevel: score,
      rmse: rmse,
      weightSum: weightSum,
      weightedResidualSquares: residualSquares,
      stationScale: 1.0,
      inactivePenalty: inactivePenalty,
      inactivePRadiusKm: 0.0,
      inactiveReferenceDistanceKm: 0.0,
      inactivePenaltyWeight: inactiveWeight,
      waveCountPenaltyMultiplier: waveMultiplier,
      effectiveStationCount: effectiveCount,
      qualityScore: qualityScore,
      qualityRank: _niedHypWorkerQualityRank(qualityScore, effectiveCount),
      pWaveCount: pCount,
      sWaveCount: sCount,
      otherWaveCount: stationCount - effectiveCount,
      searchStages: const [],
      referenceScenarioDiagnostics: <String, Object?>{
        'reference_scenario': scenario,
        'reference_first_wave': firstWave,
        'reference_last_wave': lastWave,
        'reference_filter_stage_level': filterStageLevel,
        'reference_p_wave_count': pCount,
        'reference_s_wave_count': sCount,
        'reference_l_wave_count': lCount,
        'reference_o_wave_count': oCount,
        'reference_inactive_penalty': inactivePenalty,
        'reference_inactive_penalty_weight': inactiveWeight,
        'reference_wave_count_penalty_multiplier': waveMultiplier,
      },
    );
    return _NiedReferenceScenario(
      result: result,
      wavesByStationId: <String, bool>{
        for (var index = 0; index < stationCount; index++)
          if (waves[index] != null) active[index].id: waves[index]!,
      },
    );
  }

  Iterable<int> anchorCandidates(
    int preferred,
    int center,
    int centerDirection,
  ) sync* {
    final emitted = <int>{};
    void add(int index) => emitted.add(index);
    final step = centerDirection > 0 ? 1 : -1;
    for (
      var index = preferred;
      centerDirection > 0 ? index <= center : index >= center;
      index += step
    ) {
      if (index >= 0 && index < stationCount) add(index);
    }
    for (
      var offset = 1;
      preferred - offset >= 0 || preferred + offset < stationCount;
      offset++
    ) {
      if (preferred - offset >= 0) add(preferred - offset);
      if (preferred + offset < stationCount) add(preferred + offset);
    }
    yield* emitted;
  }

  int? findAnchor(int preferred, int center, int direction, Set<int> used) {
    for (final index in anchorCandidates(preferred, center, direction)) {
      if (!used.contains(index) && weights[index] > 0) return index;
    }
    return null;
  }

  _NiedReferenceScenario? greedy(bool firstUsesS, bool lastUsesS) {
    final lastIndex = stationCount - 1;
    final firstAnchor = findAnchor(
      (lastIndex * 0.25).ceil(),
      (lastIndex * 0.75).floor(),
      1,
      <int>{},
    );
    if (firstAnchor == null) return null;
    final lastAnchor = findAnchor(
      (lastIndex * 0.75).floor(),
      (lastIndex * 0.25).ceil(),
      -1,
      <int>{firstAnchor},
    );
    if (lastAnchor == null) return null;
    final waves = List<bool?>.filled(stationCount, null)
      ..[firstAnchor] = firstUsesS
      ..[lastAnchor] = lastUsesS;
    final orderedOriginIndexes = <int>[firstAnchor, lastAnchor];
    inferMissingWaves(waves, orderedOriginIndexes);
    return scoreScenario(
      waves,
      scenario: '${firstUsesS ? 'S' : 'P'}${lastUsesS ? 'S' : 'P'}',
      firstWave: firstUsesS ? 'S' : 'P',
      lastWave: lastUsesS ? 'S' : 'P',
      orderedOriginIndexes: orderedOriginIndexes,
    );
  }

  _NiedReferenceScenario? inherited(Map<String, bool> prior, bool firstUsesS) {
    final waves = List<bool?>.generate(stationCount, (index) {
      final wave = prior[active[index].id];
      return weights[index] > 0 ? wave : null;
    });
    final inheritedIndexes = <int>[
      // NiedHypoInf.js builds inherited originEntries through
      // createScenarioInferenceIndexes(), which is middle-out. Keep that
      // insertion order through filtering, inference, and final scoring: the
      // weighted mean has observable floating-point differences for dense
      // clusters when rebuilt in station-array order.
      for (final index in _niedReferenceMiddleOutIndexes(stationCount))
        if (waves[index] != null) index,
    ];
    if (inheritedIndexes.isEmpty || weightedOrigin(waves) == null) return null;

    // Literal units from NiedHypoInf.js are milliseconds; originFor is seconds.
    var filterStageLevel = 0;
    var pWaveBias = 2.0;
    ({int minCount, double ratio, double minResidual})? selectedFilter;
    final inheritedOrigin = weightedOrigin(waves)!;
    final meanResidual =
        inheritedIndexes
            .map(
              (index) =>
                  (originFor(index, waves[index]!) - inheritedOrigin).abs(),
            )
            .fold(0.0, (sum, value) => sum + value) /
        inheritedIndexes.length;
    final stages =
        <
          ({
            int level,
            int minCount,
            double minRemainingRatio,
            double ratio,
            double minResidual,
            double? maxMeanResidual,
            double pWaveBias,
          })
        >[
          (
            level: 3,
            minCount: 100,
            minRemainingRatio: 0.9,
            ratio: 2.0,
            minResidual: 3.0,
            maxMeanResidual: 1.5,
            pWaveBias: 1.0,
          ),
          (
            level: 2,
            minCount: 30,
            minRemainingRatio: 0.8,
            ratio: 2.5,
            minResidual: 4.0,
            maxMeanResidual: 2.0,
            pWaveBias: 1.5,
          ),
          (
            level: 1,
            minCount: 10,
            minRemainingRatio: 0.5,
            ratio: 3.0,
            minResidual: 5.0,
            maxMeanResidual: null,
            pWaveBias: 2.0,
          ),
        ];
    for (final stage in stages) {
      if (inheritedIndexes.length < stage.minCount ||
          (stage.maxMeanResidual != null &&
              meanResidual > stage.maxMeanResidual!)) {
        continue;
      }
      final threshold = math.max(meanResidual * stage.ratio, stage.minResidual);
      final outliers = <int>{
        for (final index in inheritedIndexes)
          if (index > 0 &&
              (originFor(index, waves[index]!) - inheritedOrigin).abs() >
                  threshold)
            index,
      };
      final remaining = inheritedIndexes.length - outliers.length;
      final weightedCount = weights.where((weight) => weight > 0).length;
      if (remaining < stage.minCount ||
          remaining < weightedCount * stage.minRemainingRatio) {
        continue;
      }
      for (final index in outliers) {
        waves[index] = null;
      }
      inheritedIndexes.removeWhere((index) => outliers.contains(index));
      filterStageLevel = stage.level;
      pWaveBias = stage.pWaveBias;
      selectedFilter = (
        minCount: stage.minCount,
        ratio: stage.ratio,
        minResidual: stage.minResidual,
      );
      break;
    }

    for (final index in _niedReferenceMiddleOutIndexes(stationCount)) {
      if (waves[index] != null || weights[index] <= 0) continue;
      final center = weightedOriginForIndexes(inheritedIndexes, waves);
      if (center == null) return null;
      final pDifference = (originFor(index, false) - center).abs();
      final sDifference = (originFor(index, true) - center).abs();
      if (selectedFilter != null) {
        if (inheritedIndexes.length >= selectedFilter.minCount) {
          final mean =
              inheritedIndexes
                  .map((item) => (originFor(item, waves[item]!) - center).abs())
                  .fold(0.0, (sum, value) => sum + value) /
              inheritedIndexes.length;
          final threshold = math.max(
            mean * selectedFilter.ratio,
            selectedFilter.minResidual,
          );
          if (pDifference > threshold && sDifference > threshold) {
            continue;
          }
        }
      }
      waves[index] = pDifference <= sDifference * pWaveBias ? false : true;
      inheritedIndexes.add(index);
    }
    return scoreScenario(
      waves,
      scenario: '${firstUsesS ? 'S' : 'P'}_PREV',
      firstWave: firstUsesS ? 'S' : 'P',
      filterStageLevel: filterStageLevel,
      orderedOriginIndexes: inheritedIndexes,
    );
  }

  final previousResults = <String, _NiedReferenceScenario>{};
  final previousWaves = <String, Map<String, bool>>{};
  final candidateSummaries = <Map<String, Object?>>[];
  for (final firstUsesS in const [false, true]) {
    final candidates = <_NiedReferenceScenario?>[
      greedy(firstUsesS, false),
      greedy(firstUsesS, true),
      if ((referencePreviousWavesByFirstWave[firstUsesS ? 'S' : 'P'] ??
              const <String, bool>{})
          .isNotEmpty)
        inherited(
          referencePreviousWavesByFirstWave[firstUsesS ? 'S' : 'P']!,
          firstUsesS,
        ),
    ].whereType<_NiedReferenceScenario>().toList(growable: false);
    if (candidates.isEmpty) continue;
    candidateSummaries.addAll([
      for (final candidate in candidates)
        <String, Object?>{
          'first_wave': firstUsesS ? 'S' : 'P',
          'scenario': candidate
              .result
              .referenceScenarioDiagnostics['reference_scenario'],
          'score': candidate.result.score,
          'rmse': candidate.result.rmse,
          'p_wave_count': candidate.result.pWaveCount,
          's_wave_count': candidate.result.sWaveCount,
          'filter_stage_level': candidate
              .result
              .referenceScenarioDiagnostics['reference_filter_stage_level'],
        },
    ]);
    final selected = candidates.reduce(
      (best, item) => item.result.score < best.result.score ? item : best,
    );
    final key = firstUsesS ? 'S' : 'P';
    previousResults[key] = selected;
    previousWaves[key] = Map<String, bool>.from(selected.wavesByStationId);
  }
  if (previousResults.isEmpty) {
    return _niedReferenceRejectedCandidate(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originTime: earliestAt,
      activeCount: stationCount,
    );
  }
  final best = previousResults.values.reduce(
    (best, item) => item.result.score < best.result.score ? item : best,
  );
  return best.result.copyWith(
    referencePreviousWavesByFirstWave: previousWaves,
    referenceScenarioDiagnostics: <String, Object?>{
      ...best.result.referenceScenarioDiagnostics,
      'reference_scenario_candidates': candidateSummaries,
    },
  );
}

Iterable<int> _niedReferenceMiddleOutIndexes(int count) sync* {
  final middle = (count - 1) ~/ 2;
  yield middle;
  for (
    var offset = 1;
    middle - offset >= 0 || middle + offset < count;
    offset++
  ) {
    if (middle + offset < count) yield middle + offset;
    if (middle - offset >= 0) yield middle - offset;
  }
}

_NiedHypWorkerResult _scoreNiedHypWorkerCandidate(
  List<_NiedHypWorkerStation> active,
  List<_NiedHypWorkerStation> inactive, {
  required DateTime observedAt,
  required DateTime earliestAt,
  required double latitude,
  required double longitude,
  required double depthKm,
  required bool allowSWave,
  required bool applyInactivePenalty,
  required Map<String, bool> stationSFlagByCode,
  required _NiedHypWorkerCandidateConstraints candidateConstraints,
  required Map<String, Set<String>> adjacencyByStationId,
  required bool referenceAligned,
  required Map<String, Map<String, bool>> referencePreviousWavesByFirstWave,
}) {
  if (_niedHypWorkerCandidateRejectReason(
        latitude: latitude,
        longitude: longitude,
        depthKm: depthKm,
        constraints: candidateConstraints,
      ) !=
      null) {
    return _invalidNiedHypWorkerResult(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originTime: earliestAt,
      activeCount: active.length,
    );
  }
  if (referenceAligned) {
    return _scoreNiedReferenceCandidate(
      active,
      inactive,
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      earliestAt: earliestAt,
      adjacencyByStationId: adjacencyByStationId,
      referencePreviousWavesByFirstWave: referencePreviousWavesByFirstWave,
    );
  }
  final originSamples = <double>[];
  final weights = <double>[];
  final selectedWaves = <String>[];
  var originSum = 0.0;
  var weightSum = 0.0;
  var effectiveStationCount = 0;
  final firstDetectedDistanceKm = _niedHypWorkerFirstDetectedDistanceKm(
    latitude,
    longitude,
    candidateConstraints,
  );

  for (var index = 0; index < active.length; index++) {
    final station = active[index];
    final distanceKm = _haversineKm(
      latitude,
      longitude,
      station.coordinate.latitude,
      station.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      distanceKm * distanceKm + depthKm * depthKm,
    );
    final useS = allowSWave && (stationSFlagByCode[station.code] ?? false);
    final selectedTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: !useS,
    );
    final observedSeconds =
        station.triggerAt!.difference(earliestAt).inMilliseconds / 1000.0;
    final stationOrigin = observedSeconds - selectedTravel;
    final weight = _niedHypWorkerDistanceWeight(
      firstDetectedDistanceKm,
      distanceKm,
    );
    originSamples.add(stationOrigin);
    weights.add(weight);
    selectedWaves.add(useS ? 'S' : 'P');
    originSum += stationOrigin;
    if (weight > 0) {
      effectiveStationCount += 1;
      weightSum += weight;
    }
  }

  if (effectiveStationCount == 0 || weightSum <= 0) {
    return _invalidNiedHypWorkerResult(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originTime: earliestAt,
      activeCount: active.length,
    );
  }

  // Article step (3): use the mean origin time of all detected stations,
  // then sum each squared residual multiplied by its distance weight.
  final originSeconds = originSum / originSamples.length;
  var weightedResidualSquares = 0.0;
  var pCount = 0;
  var sCount = 0;
  for (var index = 0; index < originSamples.length; index++) {
    final residual = (originSamples[index] - originSeconds).abs();
    weightedResidualSquares += residual * residual * weights[index];
    if (weights[index] <= 0) continue;
    if (selectedWaves[index] == 'S') {
      sCount += 1;
    } else {
      pCount += 1;
    }
  }
  final inactiveEvaluation = applyInactivePenalty
      ? _niedHypWorkerInactivePenalty(
          inactive,
          latitude: latitude,
          longitude: longitude,
          depthKm: depthKm,
          originSeconds: originSeconds,
          observedSeconds:
              observedAt.difference(earliestAt).inMilliseconds / 1000.0,
          maxDetectedDistanceKm: candidateConstraints.maxDetectedDistanceKm,
        )
      : (penalty: 0.0, pRadiusKm: 0.0, referenceDistanceKm: 0.0);
  final inactivePenalty = inactiveEvaluation.penalty;
  final scaledResidualSquares = weightedResidualSquares + inactivePenalty;
  final stationScale =
      30.0 +
      20000.0 / (1.0 + originSamples.length * originSamples.length) +
      2000.0 / (50.0 + originSamples.length);
  final waveCountPenaltyMultiplier = math.max(
    0.25,
    1.0 - sCount * 3.0 / originSamples.length,
  );
  final inactivePenaltyWeight =
      stationScale / weightSum * waveCountPenaltyMultiplier;
  final rmse = math.sqrt(scaledResidualSquares / weightSum);
  final errorLevel = scaledResidualSquares / weightSum * stationScale;
  final score = errorLevel * waveCountPenaltyMultiplier;
  final qualityScore =
      3.8 +
      math.sqrt(effectiveStationCount / 10) * 0.2 -
      (rmse + inactivePenalty / math.max(1, effectiveStationCount)) * 5 / 3;
  final qualityRank = _niedHypWorkerQualityRank(
    qualityScore,
    effectiveStationCount,
  );
  return _NiedHypWorkerResult(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originTime: earliestAt.add(
      Duration(milliseconds: (originSeconds * 1000).round()),
    ),
    originOffsetSeconds: originSeconds,
    score: score,
    errorLevel: errorLevel,
    rmse: rmse,
    weightSum: weightSum,
    weightedResidualSquares: weightedResidualSquares,
    stationScale: stationScale,
    inactivePenalty: inactivePenalty,
    inactivePRadiusKm: inactiveEvaluation.pRadiusKm,
    inactiveReferenceDistanceKm: inactiveEvaluation.referenceDistanceKm,
    inactivePenaltyWeight: inactivePenaltyWeight,
    waveCountPenaltyMultiplier: waveCountPenaltyMultiplier,
    effectiveStationCount: effectiveStationCount,
    qualityScore: qualityScore,
    qualityRank: qualityRank,
    pWaveCount: pCount,
    sWaveCount: sCount,
    otherWaveCount: active.length - effectiveStationCount,
    searchStages: const [],
  );
}

String? _niedHypWorkerDepthRejectReason(double depthKm) {
  if (!depthKm.isFinite) return 'non_finite_depth';
  if (depthKm < 10.0) return 'depth_below_10_km';
  if (depthKm > 700.0) return 'depth_above_700_km';
  return null;
}

_NiedHypWorkerCandidateConstraints _niedHypWorkerCandidateConstraints(
  List<_NiedHypWorkerStation> active, {
  required _NiedHypWorkerStation firstStation,
  required bool referenceAligned,
}) {
  var maxDetectedDistanceKm = 0.0;
  for (final station in active) {
    maxDetectedDistanceKm = math.max(
      maxDetectedDistanceKm,
      _scratchDetectionIdDistanceKm(
        firstStation.coordinate,
        station.coordinate,
      ),
    );
  }
  return _NiedHypWorkerCandidateConstraints(
    firstLatitude: firstStation.coordinate.latitude,
    firstLongitude: firstStation.coordinate.longitude,
    maxDetectedDistanceKm: maxDetectedDistanceKm,
    maxAllowedDepthKm: referenceAligned
        ? 700.0
        : (11.0 + math.pow(maxDetectedDistanceKm, 3) * 0.00008).roundToDouble(),
    maxAllowedDistanceKm: referenceAligned
        ? 20038.0
        : (50.0 + 0.3 * (active.length * 10.0 + maxDetectedDistanceKm))
              .roundToDouble(),
    referenceAligned: referenceAligned,
  );
}

double _scratchDetectionIdDistanceKm(LatLng first, LatLng second) {
  double mercatorLatitudeDegrees(double latitude) {
    final radians = latitude * math.pi / 180.0;
    return math.log(math.tan(math.pi / 4.0 + radians / 2.0)) * 180.0 / math.pi;
  }

  final xDifference = (second.longitude - first.longitude) * 10.0;
  final yDifference =
      (mercatorLatitudeDegrees(second.latitude) -
          mercatorLatitudeDegrees(first.latitude)) *
      10.0;
  return math.sqrt(xDifference * xDifference + yDifference * yDifference) *
      11.0;
}

String? _niedHypWorkerCandidateRejectReason({
  required double latitude,
  required double longitude,
  required double depthKm,
  required _NiedHypWorkerCandidateConstraints constraints,
}) {
  final depthReason = constraints.referenceAligned
      ? (!depthKm.isFinite
            ? 'non_finite_depth'
            : depthKm < 0.0
            ? 'depth_below_0_km'
            : depthKm > 700.0
            ? 'depth_above_700_km'
            : null)
      : _niedHypWorkerDepthRejectReason(depthKm);
  if (depthReason != null) return depthReason;
  if (!constraints.referenceAligned &&
      depthKm > constraints.maxAllowedDepthKm) {
    return 'depth_above_scratch_dynamic_max';
  }
  if (!longitude.isFinite || !latitude.isFinite) {
    return 'non_finite_coordinate';
  }
  if (!constraints.referenceAligned &&
      (longitude < 115.0 || longitude > 155.0)) {
    return 'longitude_outside_scratch_bounds';
  }
  if (constraints.referenceAligned
      ? latitude < -90.0 || latitude > 90.0
      : latitude < 15.0 || latitude > 55.0) {
    return 'latitude_outside_scratch_bounds';
  }
  final firstStationDistanceKm = _haversineKm(
    latitude,
    longitude,
    constraints.firstLatitude,
    constraints.firstLongitude,
  );
  if (!constraints.referenceAligned &&
      firstStationDistanceKm > constraints.maxAllowedDistanceKm) {
    return 'distance_from_first_station_above_scratch_max';
  }
  return null;
}

_NiedHypWorkerResult _invalidNiedHypWorkerResult({
  required double latitude,
  required double longitude,
  required double depthKm,
  required DateTime originTime,
  required int activeCount,
}) {
  return _NiedHypWorkerResult(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originTime: originTime,
    originOffsetSeconds: 0,
    score: double.infinity,
    errorLevel: double.infinity,
    rmse: double.infinity,
    weightSum: 0,
    weightedResidualSquares: double.infinity,
    stationScale: double.infinity,
    inactivePenalty: 0,
    inactivePRadiusKm: 0,
    inactiveReferenceDistanceKm: 0,
    inactivePenaltyWeight: 0,
    waveCountPenaltyMultiplier: 1,
    effectiveStationCount: 0,
    qualityScore: double.negativeInfinity,
    qualityRank: 'D',
    pWaveCount: 0,
    sWaveCount: 0,
    otherWaveCount: activeCount,
    searchStages: const [],
  );
}

_NiedHypWorkerResult _niedReferenceRejectedCandidate({
  required double latitude,
  required double longitude,
  required double depthKm,
  required DateTime originTime,
  required int activeCount,
}) {
  const rejectedScore = 1e12;
  return _NiedHypWorkerResult(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originTime: originTime,
    originOffsetSeconds: 0.0,
    score: rejectedScore,
    errorLevel: rejectedScore,
    rmse: rejectedScore,
    weightSum: 0.0,
    weightedResidualSquares: rejectedScore,
    stationScale: 1.0,
    inactivePenalty: rejectedScore,
    inactivePRadiusKm: 0.0,
    inactiveReferenceDistanceKm: 0.0,
    inactivePenaltyWeight: 0.0,
    waveCountPenaltyMultiplier: 1.0,
    effectiveStationCount: 0,
    qualityScore: -rejectedScore,
    qualityRank: 'D',
    pWaveCount: 0,
    sWaveCount: 0,
    otherWaveCount: activeCount,
    searchStages: const [],
  );
}

double _niedHypWorkerFirstDetectedDistanceKm(
  double latitude,
  double longitude,
  _NiedHypWorkerCandidateConstraints constraints,
) {
  return math.max(
    50.0,
    _haversineKm(
      latitude,
      longitude,
      constraints.firstLatitude,
      constraints.firstLongitude,
    ),
  );
}

double _niedHypWorkerDistanceWeight(
  double firstDetectedDistanceKm,
  double stationDistanceKm,
) {
  return firstDetectedDistanceKm / math.max(50.0, stationDistanceKm);
}

({double penalty, double pRadiusKm, double referenceDistanceKm})
_niedHypWorkerInactivePenalty(
  List<_NiedHypWorkerStation> inactive, {
  required double latitude,
  required double longitude,
  required double depthKm,
  required double originSeconds,
  required double observedSeconds,
  required double maxDetectedDistanceKm,
}) {
  final elapsedSinceOriginSeconds = math.max(
    0.0,
    observedSeconds - originSeconds,
  );
  final rawPRadiusKm = Jma2001TravelTimeApproximation.epicentralRadiusKm(
    elapsedSeconds: elapsedSinceOriginSeconds,
    depthKm: depthKm,
    pWave: true,
  );
  final pRadiusCapKm = 100.0 + maxDetectedDistanceKm * 3.0;
  final pRadiusKm = math.min(rawPRadiusKm, pRadiusCapKm);
  final referenceDistance = pRadiusKm + 30.0;
  if (inactive.isEmpty) {
    return (
      penalty: 0.0,
      pRadiusKm: pRadiusKm,
      referenceDistanceKm: referenceDistance,
    );
  }
  var penalty = 0;
  for (final station in inactive) {
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      station.coordinate.latitude,
      station.coordinate.longitude,
    );
    if (surfaceDistanceKm > referenceDistance) continue;
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final pTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: true,
    );
    if (originSeconds + pTravel <= observedSeconds) penalty += 1;
  }
  return (
    penalty: penalty.toDouble(),
    pRadiusKm: pRadiusKm,
    referenceDistanceKm: referenceDistance,
  );
}

String _niedHypWorkerQualityRank(double qualityScore, int effectiveCount) {
  final scoreRank = qualityScore < 0
      ? 'D'
      : qualityScore < 1
      ? 'C'
      : qualityScore < 2
      ? 'B'
      : qualityScore < 3
      ? 'A'
      : 'S';
  const minCounts = {'S': 200, 'A': 100, 'B': 30, 'C': 10, 'D': 0};
  for (final rank in const ['S', 'A', 'B', 'C', 'D']) {
    if (minCounts[rank]! <= effectiveCount &&
        minCounts[rank]! <= minCounts[scoreRank]!) {
      return rank;
    }
  }
  return 'D';
}

double _niedHypWorkerConfidence(_NiedHypWorkerResult result) {
  final rankBase = switch (result.qualityRank) {
    'S' => 0.84,
    'A' => 0.72,
    'B' => 0.58,
    'C' => 0.42,
    _ => 0.25,
  };
  return (rankBase + math.min(0.12, result.effectiveStationCount / 500))
      .clamp(0.0, 0.92)
      .toDouble();
}

double _roundTo(double value, double step) => (value / step).round() * step;

extension on _NiedHypWorkerResult {
  _NiedHypWorkerResult copyWith({
    List<Map<String, Object?>>? searchStages,
    Map<String, Map<String, bool>>? referencePreviousWavesByFirstWave,
    Map<String, Object?>? referenceScenarioDiagnostics,
  }) {
    return _NiedHypWorkerResult(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originTime: originTime,
      originOffsetSeconds: originOffsetSeconds,
      score: score,
      errorLevel: errorLevel,
      rmse: rmse,
      weightSum: weightSum,
      weightedResidualSquares: weightedResidualSquares,
      stationScale: stationScale,
      inactivePenalty: inactivePenalty,
      inactivePRadiusKm: inactivePRadiusKm,
      inactiveReferenceDistanceKm: inactiveReferenceDistanceKm,
      inactivePenaltyWeight: inactivePenaltyWeight,
      waveCountPenaltyMultiplier: waveCountPenaltyMultiplier,
      effectiveStationCount: effectiveStationCount,
      qualityScore: qualityScore,
      qualityRank: qualityRank,
      pWaveCount: pWaveCount,
      sWaveCount: sWaveCount,
      otherWaveCount: otherWaveCount,
      searchStages: searchStages ?? this.searchStages,
      referencePreviousWavesByFirstWave:
          referencePreviousWavesByFirstWave ??
          this.referencePreviousWavesByFirstWave,
      referenceScenarioDiagnostics:
          referenceScenarioDiagnostics ?? this.referenceScenarioDiagnostics,
    );
  }
}

List<SeismicStationEventRecord> _usableTimingRecords(
  SourceEstimationRequest request, {
  bool requireAssociation = true,
  bool requireActiveLike = true,
  int? maxRecords = 48,
}) {
  final usable = request.stations
      .where((record) {
        return request.sensorSelection.accepts(record.descriptor) &&
            (!requireAssociation || _isAssociatedRecord(request, record)) &&
            (!requireActiveLike || record.isActiveLike) &&
            (record.firstTriggerAt ?? record.firstRiseAt) != null;
      })
      .toList(growable: false);
  if (maxRecords == null || usable.length <= maxRecords) {
    return usable;
  }

  final earliest = List<SeismicStationEventRecord>.from(usable)
    ..sort((a, b) {
      final aTime = a.firstTriggerAt ?? a.firstRiseAt!;
      final bTime = b.firstTriggerAt ?? b.firstRiseAt!;
      final timeCmp = aTime.compareTo(bTime);
      if (timeCmp != 0) return timeCmp;
      return a.descriptor.code.compareTo(b.descriptor.code);
    });
  final strongest = List<SeismicStationEventRecord>.from(usable)
    ..sort((a, b) {
      final bValue = b.lastValue ?? b.peakValue ?? -99;
      final aValue = a.lastValue ?? a.peakValue ?? -99;
      final valueCmp = bValue.compareTo(aValue);
      if (valueCmp != 0) return valueCmp;
      return a.descriptor.code.compareTo(b.descriptor.code);
    });

  final selected = <String, SeismicStationEventRecord>{};
  for (final record in earliest.take(24)) {
    selected[record.descriptor.code] = record;
  }
  for (final record in strongest.take(24)) {
    selected[record.descriptor.code] = record;
  }

  final result = selected.values.toList(growable: false)
    ..sort((a, b) {
      final aTime = a.firstTriggerAt ?? a.firstRiseAt!;
      final bTime = b.firstTriggerAt ?? b.firstRiseAt!;
      final timeCmp = aTime.compareTo(bTime);
      if (timeCmp != 0) return timeCmp;
      return a.descriptor.code.compareTo(b.descriptor.code);
    });
  return result.take(maxRecords).toList(growable: false);
}

bool _isAssociatedRecord(
  SourceEstimationRequest request,
  SeismicStationEventRecord record,
) {
  final accepted = _sourceMemberIds(request);
  return accepted.isEmpty || accepted.contains(record.descriptor.code);
}

Set<String> _sourceMemberIds(SourceEstimationRequest request) {
  final preferRawMembers =
      request.metadata['kotoho7_prefer_raw_member_ids'] == true ||
      request.metadata['kotoho7_event_id_mode'] == 'raw_diagnostic';
  if (preferRawMembers) {
    final rawMemberIds = request.metadata['source_trigger_raw_member_ids'];
    if (rawMemberIds is Iterable) {
      final accepted = rawMemberIds.whereType<String>().toSet();
      if (accepted.isNotEmpty) return accepted;
    }
  }
  final memberIds = request.metadata['source_trigger_member_ids'];
  if (memberIds is! Iterable) return const <String>{};
  return memberIds.whereType<String>().toSet();
}

DateTime _earliestObserved(List<SeismicStationEventRecord> usable) {
  return usable
      .map((record) => record.firstTriggerAt ?? record.firstRiseAt!)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

(double, double, double, double) _searchBounds(
  List<SeismicStationEventRecord> usable, {
  required double bboxPaddingDeg,
}) {
  final latitudes = usable.map((s) => s.descriptor.coordinate.latitude);
  final longitudes = usable.map((s) => s.descriptor.coordinate.longitude);
  return (
    latitudes.reduce(math.min) - bboxPaddingDeg,
    latitudes.reduce(math.max) + bboxPaddingDeg,
    longitudes.reduce(math.min) - bboxPaddingDeg,
    longitudes.reduce(math.max) + bboxPaddingDeg,
  );
}

(double, double) _weightedCenter(List<SeismicStationEventRecord> usable) {
  double latSum = 0;
  double lngSum = 0;
  double weightSum = 0;
  for (final record in usable) {
    final weight = math.max(
      0.3,
      (record.lastValue ?? record.peakValue ?? -2.5) + 3.5,
    );
    latSum += record.descriptor.coordinate.latitude * weight;
    lngSum += record.descriptor.coordinate.longitude * weight;
    weightSum += weight;
  }
  return (latSum / weightSum, lngSum / weightSum);
}

({double azimuthalGapDeg, double nearestDistanceKm, bool isOneSided})
_stationGeometryAt(
  List<SeismicStationEventRecord> usable, {
  required double latitude,
  required double longitude,
}) {
  final bearings =
      usable
          .map(
            (record) => _bearingDegrees(
              latitude,
              longitude,
              record.descriptor.coordinate.latitude,
              record.descriptor.coordinate.longitude,
            ),
          )
          .toList(growable: false)
        ..sort();
  var azimuthalGapDeg = 360.0;
  if (bearings.length > 1) {
    azimuthalGapDeg = 0;
    for (var index = 1; index < bearings.length; index++) {
      azimuthalGapDeg = math.max(
        azimuthalGapDeg,
        bearings[index] - bearings[index - 1],
      );
    }
    azimuthalGapDeg = math.max(
      azimuthalGapDeg,
      bearings.first + 360 - bearings.last,
    );
  }
  final nearestDistanceKm = usable
      .map(
        (record) => _haversineKm(
          latitude,
          longitude,
          record.descriptor.coordinate.latitude,
          record.descriptor.coordinate.longitude,
        ),
      )
      .reduce(math.min);
  return (
    azimuthalGapDeg: azimuthalGapDeg,
    nearestDistanceKm: nearestDistanceKm,
    isOneSided: azimuthalGapDeg > 180,
  );
}

double _searchBoundaryMarginDeg(
  _Candidate candidate,
  (double, double, double, double) bounds,
) {
  return [
    candidate.latitude - bounds.$1,
    bounds.$2 - candidate.latitude,
    candidate.longitude - bounds.$3,
    bounds.$4 - candidate.longitude,
  ].reduce(math.min);
}

double _bearingDegrees(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final fromLat = fromLatitude * math.pi / 180;
  final toLat = toLatitude * math.pi / 180;
  final deltaLng = (toLongitude - fromLongitude) * math.pi / 180;
  final y = math.sin(deltaLng) * math.cos(toLat);
  final x =
      math.cos(fromLat) * math.sin(toLat) -
      math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

(double, double) _horizontalUncertaintyKm({
  required ({double azimuthalGapDeg, double nearestDistanceKm, bool isOneSided})
  geometry,
  required double searchBoundaryMarginDeg,
  required int supportCount,
}) {
  final supportReduction = math.min(20.0, supportCount * 1.2);
  final oneSidedPenalty = geometry.isOneSided
      ? math.max(0.0, geometry.azimuthalGapDeg - 180.0) * 0.25
      : 0.0;
  final nearSupportPenalty =
      math.max(0.0, geometry.nearestDistanceKm - 30.0) *
      (geometry.isOneSided ? 0.55 : 0.25);
  final boundaryPenalty = searchBoundaryMarginDeg <= 0
      ? 25.0
      : math.max(0.0, 0.20 - searchBoundaryMarginDeg) * 60.0;
  final p50 = math.max(
    8.0,
    12.0 +
        oneSidedPenalty +
        nearSupportPenalty +
        boundaryPenalty -
        supportReduction,
  );
  final p90 = math.max(
    p50 * (geometry.isOneSided ? 2.1 : 1.6),
    p50 + (geometry.isOneSided ? 35.0 : 18.0),
  );
  return (p50, p90);
}

double _oneSidedBoundaryGeometryPenalty(
  List<SeismicStationEventRecord> usable,
  double lat,
  double lng, {
  required (double, double, double, double) searchBounds,
  required double boundaryHitThresholdDeg,
  required double oneSidedBoundaryPenaltyPerKm,
  required double oneSidedBoundarySupportedDistanceKm,
}) {
  if (oneSidedBoundaryPenaltyPerKm <= 0) return 0;
  final candidate = _Candidate(latitude: lat, longitude: lng, score: 0);
  final marginDeg = _searchBoundaryMarginDeg(candidate, searchBounds);
  if (marginDeg > boundaryHitThresholdDeg) return 0;
  final geometry = _stationGeometryAt(usable, latitude: lat, longitude: lng);
  if (!geometry.isOneSided) return 0;
  final unsupportedDistanceKm = math.max(
    0.0,
    geometry.nearestDistanceKm - oneSidedBoundarySupportedDistanceKm,
  );
  return unsupportedDistanceKm * oneSidedBoundaryPenaltyPerKm;
}

List<Map<String, Object?>> _topTimingPicks(
  List<SeismicStationEventRecord> usable, {
  required DateTime earliestObserved,
  int limit = 6,
}) {
  final picks = usable
      .map((record) {
        final observedAt = record.firstTriggerAt ?? record.firstRiseAt!;
        return <String, Object?>{
          'code': record.descriptor.code,
          'network': record.descriptor.network,
          'latitude': record.descriptor.coordinate.latitude,
          'longitude': record.descriptor.coordinate.longitude,
          'delay_s':
              observedAt.difference(earliestObserved).inMilliseconds / 1000.0,
          'value': record.lastValue ?? record.peakValue,
          'pga': _independentPhysicalValue(record, StationValueType.pga),
          'pgv': _independentPhysicalValue(record, StationValueType.pgv),
          'pgd': _independentPhysicalValue(record, StationValueType.pgd),
          'activity': record.lastActivity,
          'ascend': record.lastAscend,
        };
      })
      .toList(growable: false);
  picks.sort((a, b) {
    final aDelay = (a['delay_s'] as double?) ?? double.infinity;
    final bDelay = (b['delay_s'] as double?) ?? double.infinity;
    return aDelay.compareTo(bDelay);
  });
  return picks.take(limit).toList(growable: false);
}

_Candidate _scoreCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng, {
  required double assumedWaveSpeedKmPerSec,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances = <double>[];
  final values = <double>[];

  for (final record in usable) {
    final obs = record.firstTriggerAt ?? record.firstRiseAt!;
    final delaySec = obs.difference(earliestObserved).inMilliseconds / 1000.0;
    final distanceKm = _haversineKm(
      lat,
      lng,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    observedSeconds.add(delaySec);
    distances.add(distanceKm);
    values.add(record.lastValue ?? record.peakValue ?? -3.0);
  }

  final minDistance = distances.reduce(math.min);
  for (final distanceKm in distances) {
    predictedSeconds.add((distanceKm - minDistance) / assumedWaveSpeedKmPerSec);
  }

  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final rankScore = _rankScore(distances, values);
  final nearestStrongPenalty = _nearestStrongPenalty(distances, values);
  final finalScore = timeScore + rankScore + nearestStrongPenalty;

  return _Candidate(
    latitude: lat,
    longitude: lng,
    score: finalScore,
    timeScore: timeScore,
    rankScore: rankScore + nearestStrongPenalty,
    referenceDistanceKm: minDistance,
  );
}

_Candidate _scoreNiedGifCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng, {
  required (double, double) weightedCenter,
  required double assumedWaveSpeedKmPerSec,
  required double centerDistancePenaltyPerKm,
  required double singleWaveTimeScoreWeight,
  required double phaseLineScoreWeight,
  required double groupedPhaseLineScoreWeight,
  required double phaseDifferenceScoreWeight,
  required (double, double, double, double) searchBounds,
  required double boundaryHitThresholdDeg,
  required double oneSidedBoundaryPenaltyPerKm,
  required double oneSidedBoundarySupportedDistanceKm,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances = <double>[];
  final shindoValues = <double>[];
  for (final record in usable) {
    final obs = record.firstTriggerAt ?? record.firstRiseAt!;
    final delaySec = obs.difference(earliestObserved).inMilliseconds / 1000.0;
    final distanceKm = _haversineKm(
      lat,
      lng,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    observedSeconds.add(delaySec);
    distances.add(distanceKm);
    shindoValues.add(record.lastValue ?? record.peakValue ?? -3.0);
  }

  final minDistance = distances.reduce(math.min);
  for (final distanceKm in distances) {
    predictedSeconds.add((distanceKm - minDistance) / assumedWaveSpeedKmPerSec);
  }

  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final phaseLineFit = _phaseLineFitScore(observedSeconds, distances);
  final groupedPhaseLineFit = _groupedPhaseLineFitScore(
    observedSeconds,
    distances,
  );
  final phaseDifferenceFit = _phaseDifferenceFitScore(
    observedSeconds,
    phaseLineFit.predictedSeconds,
    phaseLineFit.acceptedPhaseIndexes,
  );
  final geometry = _stationGeometryAt(usable, latitude: lat, longitude: lng);
  final oneSidedScoreMode = geometry.isOneSided;
  const rankWeight = 1.0;
  const centerWeight = 1.0;
  final shindoRank = _rankScore(distances, shindoValues);
  final nearestPenalty = _nearestStrongPenalty(distances, shindoValues);
  final centerPenalty =
      _haversineKm(lat, lng, weightedCenter.$1, weightedCenter.$2) *
      centerDistancePenaltyPerKm *
      centerWeight;
  final geometryPenalty = _oneSidedBoundaryGeometryPenalty(
    usable,
    lat,
    lng,
    searchBounds: searchBounds,
    boundaryHitThresholdDeg: boundaryHitThresholdDeg,
    oneSidedBoundaryPenaltyPerKm: oneSidedBoundaryPenaltyPerKm,
    oneSidedBoundarySupportedDistanceKm: oneSidedBoundarySupportedDistanceKm,
  );

  final rankScore =
      (shindoRank + nearestPenalty) * rankWeight +
      centerPenalty +
      geometryPenalty;
  final finalScore =
      timeScore * singleWaveTimeScoreWeight +
      phaseLineFit.score * phaseLineScoreWeight +
      groupedPhaseLineFit.score * groupedPhaseLineScoreWeight +
      phaseDifferenceFit.score * phaseDifferenceScoreWeight +
      rankScore;

  return _Candidate(
    latitude: lat,
    longitude: lng,
    score: finalScore,
    timeScore: timeScore,
    phaseLineScore: phaseLineFit.score,
    groupedPhaseLineScore: groupedPhaseLineFit.score,
    groupedPhaseLineMeanResidualSeconds:
        groupedPhaseLineFit.meanResidualSeconds,
    groupedPhaseBestDepthKm: groupedPhaseLineFit.depthKm,
    groupedPhaseDepthMeanResidualSeconds:
        groupedPhaseLineFit.meanResidualSeconds,
    groupedPhaseDepthSupported: groupedPhaseLineFit.depthSupported,
    groupedPhaseLinePCount: groupedPhaseLineFit.pCount,
    groupedPhaseLineSCount: groupedPhaseLineFit.sCount,
    groupedPhaseLineOtherCount: groupedPhaseLineFit.otherCount,
    pOnlyLineMeanResidualSeconds: groupedPhaseLineFit.pOnlyMeanResidualSeconds,
    pOnlyLineResidualP90Seconds: groupedPhaseLineFit.pOnlyResidualP90Seconds,
    pOnlyBestDepthKm: groupedPhaseLineFit.pOnlyBestDepthKm,
    pOnlyDepthMeanResidualSeconds:
        groupedPhaseLineFit.pOnlyDepthMeanResidualSeconds,
    pOnlyDepthSupported: groupedPhaseLineFit.pOnlyDepthSupported,
    sOnlyLineMeanResidualSeconds: groupedPhaseLineFit.sOnlyMeanResidualSeconds,
    sOnlyLineResidualP90Seconds: groupedPhaseLineFit.sOnlyResidualP90Seconds,
    phaseDifferenceScore: phaseDifferenceFit.score,
    phaseDifferencePairCount: phaseDifferenceFit.pairCount,
    phaseDifferenceMeanResidualSeconds: phaseDifferenceFit.meanResidualSeconds,
    phaseLinePCount: phaseLineFit.pCount,
    phaseLineSCount: phaseLineFit.sCount,
    phaseLineOtherCount: phaseLineFit.otherCount,
    phaseLineMeanResidualSeconds: phaseLineFit.meanResidualSeconds,
    oneSidedScoreMode: oneSidedScoreMode,
    rankScore: rankScore,
    geometryPenalty: geometryPenalty,
    referenceDistanceKm: minDistance,
  );
}

_Candidate _scoreNiedPhysicalCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng, {
  required (double, double) weightedCenter,
  required double assumedWaveSpeedKmPerSec,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances = <double>[];
  final shindoValues = <double>[];
  final pgaValues = <double?>[];
  final pgvValues = <double?>[];
  final pgdValues = <double?>[];
  for (final record in usable) {
    final observedAt = record.firstTriggerAt ?? record.firstRiseAt!;
    observedSeconds.add(
      observedAt.difference(earliestObserved).inMilliseconds / 1000.0,
    );
    distances.add(
      _haversineKm(
        lat,
        lng,
        record.descriptor.coordinate.latitude,
        record.descriptor.coordinate.longitude,
      ),
    );
    shindoValues.add(record.lastValue ?? record.peakValue ?? -3.0);
    pgaValues.add(_logPhysical(record, StationValueType.pga));
    pgvValues.add(_logPhysical(record, StationValueType.pgv));
    pgdValues.add(_logPhysical(record, StationValueType.pgd));
  }
  final minDistance = distances.reduce(math.min);
  for (final distance in distances) {
    predictedSeconds.add((distance - minDistance) / assumedWaveSpeedKmPerSec);
  }
  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final rankScore =
      _rankScore(distances, shindoValues) +
      _rankScoreOptionalNormalized(distances, pgaValues) * 0.35 +
      _rankScoreOptionalNormalized(distances, pgvValues) * 0.20 +
      _rankScoreOptionalNormalized(distances, pgdValues) * 0.10 +
      _nearestStrongPenalty(distances, shindoValues) +
      _haversineKm(lat, lng, weightedCenter.$1, weightedCenter.$2) * 0.015;
  return _Candidate(
    latitude: lat,
    longitude: lng,
    score: timeScore * 1.15 + rankScore,
    timeScore: timeScore,
    rankScore: rankScore,
    referenceDistanceKm: minDistance,
  );
}

double? _logPhysical(
  SeismicStationEventRecord record,
  StationValueType quantity,
) {
  final value = _independentPhysicalValue(record, quantity);
  return value == null || value <= 0 ? null : math.log(value) / math.ln10;
}

double _rankScoreOptionalNormalized(
  List<double> distances,
  List<double?> values,
) {
  var score = 0.0;
  for (var i = 0; i < values.length; i++) {
    final left = values[i];
    if (left == null || !left.isFinite) continue;
    for (var j = i + 1; j < values.length; j++) {
      final right = values[j];
      if (right == null || !right.isFinite) continue;
      final valueDiff = left - right;
      if (valueDiff.abs() < 0.05) continue;
      final distanceDiff = distances[i] - distances[j];
      if ((valueDiff > 0 && distanceDiff > 0) ||
          (valueDiff < 0 && distanceDiff < 0)) {
        score += 0.25;
      }
    }
  }
  return score;
}

double? _independentPhysicalValue(
  SeismicStationEventRecord record,
  StationValueType quantity,
) {
  final provenance = record.provenance[quantity];
  if (provenance?.mayBeUsedAsIndependentEvidence != true) return null;
  return switch (quantity) {
    StationValueType.pga => record.lastPga,
    StationValueType.pgv => record.lastPgv,
    StationValueType.pgd => record.lastPgd,
    _ => null,
  };
}

_DepthCandidate _scoreDepthCandidate(
  List<SeismicStationEventRecord> usable,
  DateTime earliestObserved,
  double lat,
  double lng,
  double depthKm, {
  required double assumedWaveSpeedKmPerSec,
}) {
  final observedSeconds = <double>[];
  final predictedSeconds = <double>[];
  final distances3d = <double>[];
  final surfaceDistances = <double>[];
  final values = <double>[];

  for (final record in usable) {
    final obs = record.firstTriggerAt ?? record.firstRiseAt!;
    final delaySec = obs.difference(earliestObserved).inMilliseconds / 1000.0;
    final surfaceDistanceKm = _haversineKm(
      lat,
      lng,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final distance3d = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    observedSeconds.add(delaySec);
    surfaceDistances.add(surfaceDistanceKm);
    distances3d.add(distance3d);
    values.add(record.lastValue ?? record.peakValue ?? -3.0);
  }

  final minDistance = distances3d.reduce(math.min);
  for (final distanceKm in distances3d) {
    predictedSeconds.add((distanceKm - minDistance) / assumedWaveSpeedKmPerSec);
  }

  final timeScore = _timeResidualScore(observedSeconds, predictedSeconds);
  final rankScore = _rankScore(surfaceDistances, values);
  final nearestStrongPenalty = _nearestStrongPenalty(surfaceDistances, values);
  final depthRegularization = depthKm * 0.0025;
  final finalScore =
      timeScore + rankScore + nearestStrongPenalty + depthRegularization;

  return _DepthCandidate(
    latitude: lat,
    longitude: lng,
    depthKm: depthKm,
    score: finalScore,
    timeScore: timeScore,
    rankScore: rankScore + nearestStrongPenalty + depthRegularization,
    referenceDistanceKm: minDistance,
  );
}

double _timeResidualScore(List<double> observed, List<double> predicted) {
  double score = 0;
  for (var i = 0; i < observed.length; i++) {
    final residual = observed[i] - predicted[i];
    score += residual * residual;
  }
  return score;
}

_PhaseLineFit _phaseLineFitScore(
  List<double> observedSeconds,
  List<double> distancesKm,
) {
  const pWaveSpeedKmPerSec = 6.0;
  const sWaveSpeedKmPerSec = 3.5;
  const residualToleranceSeconds = 2.8;
  const depthKm = 40.0;

  final pPredicted = <double>[];
  final sPredicted = <double>[];
  for (final distanceKm in distancesKm) {
    final hypocentralDistanceKm = math.sqrt(
      distanceKm * distanceKm + depthKm * depthKm,
    );
    pPredicted.add(hypocentralDistanceKm / pWaveSpeedKmPerSec);
    sPredicted.add(hypocentralDistanceKm / sWaveSpeedKmPerSec);
  }

  final firstPredicted = [...pPredicted, ...sPredicted].reduce(math.min);
  var score = 0.0;
  var residualSum = 0.0;
  var pCount = 0;
  var sCount = 0;
  var otherCount = 0;
  final acceptedPhaseIndexes = <int>[];
  final predictedSeconds = <double>[];
  for (var index = 0; index < observedSeconds.length; index++) {
    final pSeconds = pPredicted[index] - firstPredicted;
    final sSeconds = sPredicted[index] - firstPredicted;
    final pResidual = (observedSeconds[index] - pSeconds).abs();
    final sResidual = (observedSeconds[index] - sSeconds).abs();
    final bestResidual = math.min(pResidual, sResidual);
    final acceptedPhaseIndex = pResidual <= sResidual ? 0 : 1;
    predictedSeconds.add(acceptedPhaseIndex == 0 ? pSeconds : sSeconds);
    residualSum += bestResidual;
    score += bestResidual * bestResidual;
    if (bestResidual > residualToleranceSeconds) {
      otherCount += 1;
    } else if (pResidual <= sResidual) {
      pCount += 1;
      acceptedPhaseIndexes.add(index);
    } else {
      sCount += 1;
      acceptedPhaseIndexes.add(index);
    }
  }

  return _PhaseLineFit(
    score: score,
    pCount: pCount,
    sCount: sCount,
    otherCount: otherCount,
    meanResidualSeconds: observedSeconds.isEmpty
        ? 0
        : residualSum / observedSeconds.length,
    predictedSeconds: predictedSeconds,
    acceptedPhaseIndexes: acceptedPhaseIndexes,
  );
}

_GroupedPhaseLineFit _groupedPhaseLineFitScore(
  List<double> observedSeconds,
  List<double> distancesKm,
) {
  const depthCandidatesKm = [10.0, 20.0, 40.0, 60.0, 80.0, 100.0, 140.0];
  var bestGrouped = _groupedPhaseLineFitAtDepth(
    observedSeconds,
    distancesKm,
    depthKm: depthCandidatesKm.first,
  );
  var bestPOnly = bestGrouped;
  for (final depthKm in depthCandidatesKm.skip(1)) {
    final fit = _groupedPhaseLineFitAtDepth(
      observedSeconds,
      distancesKm,
      depthKm: depthKm,
    );
    if (fit.meanResidualSeconds < bestGrouped.meanResidualSeconds) {
      bestGrouped = fit;
    }
    if (fit.pOnlyMeanResidualSeconds < bestPOnly.pOnlyMeanResidualSeconds) {
      bestPOnly = fit;
    }
  }
  return bestGrouped.copyWith(
    pOnlyBestDepthKm: bestPOnly.depthKm,
    pOnlyDepthMeanResidualSeconds: bestPOnly.pOnlyMeanResidualSeconds,
    pOnlyDepthSupported: false,
  );
}

Map<String, Object?> _niedGifMagnitudeDiagnostics(
  List<SeismicStationEventRecord> usable, {
  required double sourceLatitude,
  required double sourceLongitude,
  required double depthKm,
  required String depthSource,
}) {
  const minimumUsableIntensity = -0.8;
  final stationMagnitudes = <double>[];
  for (final record in usable) {
    final observedIntensity = math.max(
      record.peakValue ?? double.negativeInfinity,
      record.lastValue ?? double.negativeInfinity,
    );
    if (!observedIntensity.isFinite ||
        observedIntensity < minimumUsableIntensity) {
      continue;
    }
    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final magnitude = _invertJmaStyleIntensityMagnitude(
      observedIntensity: observedIntensity,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (magnitude != null) stationMagnitudes.add(magnitude);
  }

  if (stationMagnitudes.length < 3) {
    return {
      'diagnostic_magnitude_supported': false,
      'diagnostic_magnitude_station_count': stationMagnitudes.length,
      'diagnostic_magnitude_depth_km': depthKm,
      'diagnostic_magnitude_depth_source': depthSource,
      'diagnostic_magnitude_model': 'jma_style_intensity_inverse_v1',
    };
  }

  final medianMagnitude = _median(stationMagnitudes);
  final p25 = _percentile(stationMagnitudes, 0.25);
  final p75 = _percentile(stationMagnitudes, 0.75);
  final spread = p75 - p25;
  return {
    'diagnostic_magnitude_jma_style': medianMagnitude,
    'diagnostic_magnitude_supported': spread <= 1.2,
    'diagnostic_magnitude_station_count': stationMagnitudes.length,
    'diagnostic_magnitude_iqr': spread,
    'diagnostic_magnitude_p25': p25,
    'diagnostic_magnitude_p75': p75,
    'diagnostic_magnitude_depth_km': depthKm,
    'diagnostic_magnitude_depth_source': depthSource,
    'diagnostic_magnitude_model': 'jma_style_intensity_inverse_v1',
    'diagnostic_magnitude_min_station_intensity': minimumUsableIntensity,
  };
}

double? _supportedDiagnosticMagnitude(Map<String, Object?> diagnostics) {
  if (diagnostics['diagnostic_magnitude_supported'] != true) return null;
  final value = diagnostics['diagnostic_magnitude_jma_style'];
  if (value is! num) return null;
  final magnitude = value.toDouble();
  return magnitude.isFinite ? magnitude : null;
}

double? _supportedDiagnosticDepthKm(Map<String, Object?> diagnostics) {
  if (diagnostics['depth_supported'] != true) return null;
  final value = diagnostics['depth_km'];
  if (value is! num) return null;
  final depthKm = value.toDouble();
  return depthKm.isFinite ? depthKm : null;
}

double? _invertJmaStyleIntensityMagnitude({
  required double observedIntensity,
  required double depthKm,
  required double hypocentralDistanceKm,
}) {
  if (!observedIntensity.isFinite ||
      !depthKm.isFinite ||
      !hypocentralDistanceKm.isFinite ||
      hypocentralDistanceKm <= 0) {
    return null;
  }
  var low = 0.0;
  var high = 9.5;
  for (var i = 0; i < 36; i++) {
    final mid = (low + high) / 2.0;
    final predicted = _jmaStyleInstrumentalIntensity(
      magnitude: mid,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (predicted < observedIntensity) {
      low = mid;
    } else {
      high = mid;
    }
  }
  final magnitude = (low + high) / 2.0;
  if (!magnitude.isFinite) return null;
  return magnitude.clamp(0.0, 9.5);
}

double _jmaStyleInstrumentalIntensity({
  required double magnitude,
  required double depthKm,
  required double hypocentralDistanceKm,
}) {
  final mw = magnitude - 0.171;
  final x = math.max(hypocentralDistanceKm, 1.0);
  final logPgv600 =
      0.58 * mw +
      0.0038 * depthKm -
      1.29 -
      _log10(x + 0.0028 * math.pow(10, 0.50 * mw)) -
      0.002 * x;
  final pgv600 = math.pow(10, logPgv600).toDouble();
  final surfacePgv = 0.90 * pgv600;
  if (surfacePgv <= 0) return -3.0;
  return 2.68 + 1.72 * _log10(surfacePgv);
}

Map<String, Object?> _niedGifHypDiagnostics(
  SourceEstimationRequest request,
  List<SeismicStationEventRecord> usable, {
  required DateTime earliestObserved,
  required _Candidate seed,
  required (double, double, double, double) searchBounds,
  required double coarseStepDeg,
  required double fineStepDeg,
  required double unarrivedPenaltyScoreWeight,
  required double depthRegularizationWeight,
  required double sSupportBonusPerStation,
  required double maxSSupportBonus,
  String methodId = 'nied_gif_hyp_v1',
  bool useJma2001TravelTime = false,
  bool useJqStyleScoring = false,
}) {
  if (usable.length < 3) {
    return {
      'method': methodId,
      'supported': false,
      'reason': 'insufficient_triggered_stations',
    };
  }
  final unarrived = _hypUnarrivedRecords(request, usable, limit: 64);
  final depthCandidatesKm = const [10.0, 20.0, 40.0, 60.0, 80.0, 100.0, 140.0];
  var best = _HypCandidate(
    latitude: seed.latitude,
    longitude: seed.longitude,
    depthKm: 40,
    originOffsetSeconds: 0,
    score: double.infinity,
    phaseScore: double.infinity,
    phaseMeanResidualSeconds: double.infinity,
    phaseResidualP90Seconds: double.infinity,
    phasePCount: 0,
    phaseSCount: 0,
    phaseOtherCount: 0,
    pairScore: double.infinity,
    pairMeanResidualSeconds: double.infinity,
    pairCount: 0,
    unarrivedPenalty: 0,
    unarrivedPenaltyCount: 0,
    phaseBalancePenalty: 0,
    weightedCount: 0,
  );
  final searchStages = <Map<String, Object?>>[];

  best = _searchHypGrid(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    minLat: searchBounds.$1,
    maxLat: searchBounds.$2,
    minLng: searchBounds.$3,
    maxLng: searchBounds.$4,
    stepDeg: coarseStepDeg,
    depthCandidatesKm: depthCandidatesKm,
    currentBest: best,
    unarrivedPenaltyScoreWeight: unarrivedPenaltyScoreWeight,
    depthRegularizationWeight: depthRegularizationWeight,
    sSupportBonusPerStation: sSupportBonusPerStation,
    maxSSupportBonus: maxSSupportBonus,
    useJma2001TravelTime: useJma2001TravelTime,
    useJqStyleScoring: useJqStyleScoring,
  );
  searchStages.add({
    'stage': 'coarse',
    'step_deg': coarseStepDeg,
    'depth_candidates_km': depthCandidatesKm,
    'best_latitude': best.latitude,
    'best_longitude': best.longitude,
    'best_depth_km': best.depthKm,
    'best_score': best.score,
  });
  best = _searchHypGrid(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    minLat: best.latitude - coarseStepDeg * 1.4,
    maxLat: best.latitude + coarseStepDeg * 1.4,
    minLng: best.longitude - coarseStepDeg * 1.4,
    maxLng: best.longitude + coarseStepDeg * 1.4,
    stepDeg: fineStepDeg,
    depthCandidatesKm: depthCandidatesKm,
    currentBest: best,
    unarrivedPenaltyScoreWeight: unarrivedPenaltyScoreWeight,
    depthRegularizationWeight: depthRegularizationWeight,
    sSupportBonusPerStation: sSupportBonusPerStation,
    maxSSupportBonus: maxSSupportBonus,
    useJma2001TravelTime: useJma2001TravelTime,
    useJqStyleScoring: useJqStyleScoring,
  );
  searchStages.add({
    'stage': 'fine',
    'step_deg': fineStepDeg,
    'depth_candidates_km': depthCandidatesKm,
    'best_latitude': best.latitude,
    'best_longitude': best.longitude,
    'best_depth_km': best.depthKm,
    'best_score': best.score,
  });
  if (useJqStyleScoring) {
    final refineStepDeg = math.max(0.02, fineStepDeg / 2.0);
    final refineDepthCandidates = _hypLocalDepthCandidates(
      best.depthKm,
      depthCandidatesKm,
    );
    final refineCandidate = _searchHypGrid(
      usable,
      unarrived,
      earliestObserved: earliestObserved,
      observedAt: request.observedAt,
      minLat: best.latitude - fineStepDeg * 1.2,
      maxLat: best.latitude + fineStepDeg * 1.2,
      minLng: best.longitude - fineStepDeg * 1.2,
      maxLng: best.longitude + fineStepDeg * 1.2,
      stepDeg: refineStepDeg,
      depthCandidatesKm: refineDepthCandidates,
      currentBest: best,
      unarrivedPenaltyScoreWeight: unarrivedPenaltyScoreWeight,
      depthRegularizationWeight: depthRegularizationWeight,
      sSupportBonusPerStation: sSupportBonusPerStation,
      maxSSupportBonus: maxSSupportBonus,
      useJma2001TravelTime: useJma2001TravelTime,
      useJqStyleScoring: useJqStyleScoring,
    );
    searchStages.add({
      'stage': 'jq_refine',
      'applied': false,
      'reason': 'diagnostic_candidate_only_until_replay_safe',
      'step_deg': refineStepDeg,
      'depth_candidates_km': refineDepthCandidates,
      'candidate_latitude': refineCandidate.latitude,
      'candidate_longitude': refineCandidate.longitude,
      'candidate_depth_km': refineCandidate.depthKm,
      'candidate_score': refineCandidate.score,
      'candidate_phase_p_count': refineCandidate.phasePCount,
      'candidate_phase_s_count': refineCandidate.phaseSCount,
      'candidate_phase_other_count': refineCandidate.phaseOtherCount,
      'candidate_phase_mean_residual_s':
          refineCandidate.phaseMeanResidualSeconds,
      'candidate_pair_mean_residual_s': refineCandidate.pairMeanResidualSeconds,
      'candidate_unarrived_penalty': refineCandidate.unarrivedPenalty,
    });
  }

  final maxSupportedUnarrivedPenalty = useJqStyleScoring ? 80.0 : 60.0;
  final depthSupported =
      best.phasePCount >= 3 &&
      best.phaseSCount >= 3 &&
      best.phaseMeanResidualSeconds <= 2.2 &&
      best.pairMeanResidualSeconds <= 2.5 &&
      best.unarrivedPenalty <= maxSupportedUnarrivedPenalty;
  final pOnlySupported =
      best.phasePCount >= 4 &&
      best.phaseSCount == 0 &&
      best.phaseMeanResidualSeconds <= 2.0 &&
      best.pairMeanResidualSeconds <= 2.5;
  final supported =
      best.phasePCount >= 3 &&
      best.phaseSCount >= 2 &&
      best.phaseMeanResidualSeconds <= 2.8 &&
      best.pairMeanResidualSeconds <= 3.5 &&
      best.unarrivedPenalty <= maxSupportedUnarrivedPenalty;
  final supportReasons = _hypSupportReasons(
    supported: supported,
    depthSupported: depthSupported,
    pOnlySupported: pOnlySupported,
  );
  final unsupportedReasons = _hypUnsupportedReasons(
    best,
    supported: supported,
    depthSupported: depthSupported,
    pOnlySupported: pOnlySupported,
    maxSupportedUnarrivedPenalty: maxSupportedUnarrivedPenalty,
  );
  final originTime = earliestObserved.add(
    Duration(milliseconds: (best.originOffsetSeconds * 1000).round()),
  );
  final sPhaseGateElapsedSeconds =
      request.observedAt.difference(earliestObserved).inMilliseconds / 1000.0;
  final sPhaseGateOpen = sPhaseGateElapsedSeconds > 15.0;
  final referenceStateProxy = useJqStyleScoring
      ? _hypReferenceStateProxy(
          request,
          usable,
          earliestObserved: earliestObserved,
          best: best,
          useJma2001TravelTime: useJma2001TravelTime,
        )
      : null;
  return {
    'method': methodId,
    'travel_time_model': useJma2001TravelTime
        ? 'jma2001_polynomial_from_jq_reference_js'
        : 'fixed_speed_p6_s3_5',
    'scoring_model': useJqStyleScoring
        ? 'jq_reference_candidate_s_flag_origin_variance_v1'
        : 'weighted_residual_pair_penalty_v1',
    'supported': supported,
    'p_only_supported': pOnlySupported,
    'depth_supported': depthSupported,
    'support_reasons': supportReasons,
    'unsupported_reasons': unsupportedReasons,
    'latitude': best.latitude,
    'longitude': best.longitude,
    'depth_km': best.depthKm,
    'origin_time': originTime.toIso8601String(),
    'origin_offset_s': best.originOffsetSeconds,
    'score': best.score,
    'phase_score': best.phaseScore,
    'phase_mean_residual_s': best.phaseMeanResidualSeconds,
    'phase_residual_p90_s': best.phaseResidualP90Seconds,
    'phase_p_count': best.phasePCount,
    'phase_s_count': best.phaseSCount,
    'phase_other_count': best.phaseOtherCount,
    'phase_origin_model': useJqStyleScoring
        ? 'diagnostic_phase_origin_clusters_v1'
        : null,
    'station_s_flag_model': useJqStyleScoring
        ? 'candidate_predicted_s_closer_than_p_after_15s_v1'
        : null,
    's_phase_gate_elapsed_s': useJqStyleScoring
        ? sPhaseGateElapsedSeconds
        : null,
    's_phase_gate_open': useJqStyleScoring ? sPhaseGateOpen : null,
    'jq_reference_state_proxy': referenceStateProxy,
    'p_origin_cluster_count': best.pOriginClusterCount,
    's_origin_cluster_count': best.sOriginClusterCount,
    'p_origin_mean_s': best.pOriginMeanSeconds,
    's_origin_mean_s': best.sOriginMeanSeconds,
    'p_origin_spread_s': best.pOriginSpreadSeconds,
    's_origin_spread_s': best.sOriginSpreadSeconds,
    'phase_origin_mean_gap_s': best.phaseOriginMeanGapSeconds,
    'pair_score': best.pairScore,
    'pair_mean_residual_s': best.pairMeanResidualSeconds,
    'pair_count': best.pairCount,
    'unarrived_penalty': best.unarrivedPenalty,
    'unarrived_penalty_count': best.unarrivedPenaltyCount,
    'max_supported_unarrived_penalty': maxSupportedUnarrivedPenalty,
    'phase_balance_penalty': best.phaseBalancePenalty,
    'unarrived_candidate_count': unarrived.length,
    'weighted_count': best.weightedCount,
    'depth_candidates_km': depthCandidatesKm,
    'scoring_config': {
      'unarrived_penalty_weight': unarrivedPenaltyScoreWeight,
      'depth_regularization_weight': depthRegularizationWeight,
      's_support_bonus_per_station': sSupportBonusPerStation,
      'max_s_support_bonus': maxSSupportBonus,
      'jq_style_scoring': useJqStyleScoring,
      'max_supported_unarrived_penalty': maxSupportedUnarrivedPenalty,
    },
    'search': {
      'coarse_step_deg': coarseStepDeg,
      'fine_step_deg': fineStepDeg,
      'stages': searchStages,
      'bbox': [
        searchBounds.$1,
        searchBounds.$2,
        searchBounds.$3,
        searchBounds.$4,
      ],
    },
  };
}

Map<String, Object?> _niedGifHypKotoho7ReferenceDiagnostics(
  SourceEstimationRequest request,
  List<SeismicStationEventRecord> usable, {
  required DateTime earliestObserved,
  required (double, double, double, double) searchBounds,
}) {
  const methodId = 'nied_gif_hyp_kotoho7_reference_replay_v1';
  if (usable.length < 3) {
    return {
      'method': methodId,
      'supported': false,
      'reason': 'insufficient_triggered_stations',
    };
  }

  final sortedUsable = [...usable]
    ..sort((left, right) {
      final leftAt = left.firstTriggerAt ?? left.firstRiseAt;
      final rightAt = right.firstTriggerAt ?? right.firstRiseAt;
      if (leftAt == null && rightAt == null) return 0;
      if (leftAt == null) return 1;
      if (rightAt == null) return -1;
      return leftAt.compareTo(rightAt);
    });
  final first = sortedUsable.first;
  final unarrived = _kotoho7UnarrivedRecords(request, usable);
  final candidateConstraints = _kotoho7CandidateConstraints(
    _kotoho7SortedTimingRecords(usable),
  );
  final seedLatitude =
      (first.descriptor.coordinate.latitude * 100).round() / 100.0;
  final seedLongitude =
      (first.descriptor.coordinate.longitude * 100).round() / 100.0;

  var best = _scoreKotoho7HypCandidate(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    latitude: seedLatitude,
    longitude: seedLongitude,
    depthKm: 10.0,
    originSeedSeconds: -2.0,
  );
  final phaseReference = best;
  final stages = <Map<String, Object?>>[];
  final elapsedSinceFirstDetectionSeconds =
      request.observedAt.difference(earliestObserved).inMilliseconds / 1000.0;
  final earlyLowCountPenalty =
      elapsedSinceFirstDetectionSeconds < 5.0 && usable.length < 10;
  final earlyHighCountPenalty =
      elapsedSinceFirstDetectionSeconds < 5.0 && usable.length >= 10;
  final h2MaxIterations = earlyLowCountPenalty
      ? 1
      : earlyHighCountPenalty
      ? 15
      : 30;
  final h10MaxIterations = earlyLowCountPenalty
      ? 6
      : earlyHighCountPenalty
      ? 40
      : 80;

  best = _kotoho7LocalSearchStage(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    searchBounds: searchBounds,
    currentBest: best,
    phaseReference: phaseReference,
    horizontalStepDeg: 0.5,
    depthStepKm: null,
    stageName: 'start-h2',
    stages: stages,
    maxIterations: h2MaxIterations,
  );
  best = _kotoho7LocalSearchStage(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    searchBounds: searchBounds,
    currentBest: best,
    phaseReference: phaseReference,
    horizontalStepDeg: 0.1,
    depthStepKm: null,
    stageName: 'start-h10',
    stages: stages,
    maxIterations: h10MaxIterations,
  );
  best = _kotoho7LocalSearchStage(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    searchBounds: searchBounds,
    currentBest: best,
    phaseReference: phaseReference,
    horizontalStepDeg: 0.1,
    depthStepKm: 50.0,
    stageName: 'start-h10-v50',
    stages: stages,
    maxIterations: 100,
  );
  best = _kotoho7LocalSearchStage(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    searchBounds: searchBounds,
    currentBest: best,
    phaseReference: phaseReference,
    horizontalStepDeg: 0.1,
    depthStepKm: 10.0,
    stageName: 'start-h10-v10',
    stages: stages,
    maxIterations: 100,
  );
  best = _kotoho7LocalSearchStage(
    usable,
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: request.observedAt,
    searchBounds: searchBounds,
    currentBest: best,
    phaseReference: phaseReference,
    horizontalStepDeg: 1.0 / 60.0,
    depthStepKm: null,
    stageName: 'start-h60',
    stages: stages,
    maxIterations: 10,
  );
  if (!best.score.isFinite) {
    return {
      'method': methodId,
      'reference_url': 'https://note.com/kotoho7/n/n59e423877b1b',
      'reference_title': '揺れ検知から震央を検出してみる',
      'supported': false,
      'reason': 'no_finite_kotoho7_candidate',
      'usable_station_count': usable.length,
      'candidate_constraints': {
        'model':
            'scratch_4_3_offset4_count_offset5_distance_proxy_from_current_usable_v1',
        'max_detected_distance_km': candidateConstraints.maxDetectedDistanceKm,
        'max_allowed_depth_km': candidateConstraints.maxAllowedDepthKm,
        'max_allowed_distance_km': candidateConstraints.maxAllowedDistanceKm,
      },
      'single_trigger_circle_eew_gate': _kotoho7CircleEewGateDiagnostics(
        request,
      ),
      'search': {
        'type': 'staged_neighbor_descent',
        'stages': stages
            .map(
              (stage) => {
                ...stage,
                if (stage['best_score'] is double &&
                    !(stage['best_score']! as double).isFinite)
                  'best_score': null,
                if (stage['phase_mean_residual_s'] is double &&
                    !(stage['phase_mean_residual_s']! as double).isFinite)
                  'phase_mean_residual_s': null,
              },
            )
            .toList(growable: false),
      },
    };
  }

  final phaseSupportCount = best.phasePCount + best.phaseSCount;
  final supported =
      phaseSupportCount >= 3 &&
      best.phaseMeanResidualSeconds <= 2.8 &&
      best.unarrivedPenalty <= 80.0;
  final depthSupported = supported && best.depthKm > 10.0;
  final originTime = earliestObserved.add(
    Duration(milliseconds: (best.originOffsetSeconds * 1000).round()),
  );

  return {
    'method': methodId,
    'reference_url': 'https://note.com/kotoho7/n/n59e423877b1b',
    'reference_title': '揺れ検知から震央を検出してみる',
    'reference_scope':
        'diagnostic replay of kotoho7/Scratch-style staged local search',
    'travel_time_model': 'jma2001_polynomial_from_jq_reference_js',
    'scoring_model': 'kotoho7_article_error_level_with_s_flag_proxy_v2',
    'supported': supported,
    'p_only_supported':
        best.phasePCount >= 4 &&
        best.phaseSCount == 0 &&
        best.phaseMeanResidualSeconds <= 2.5,
    'depth_supported': depthSupported,
    'latitude': best.latitude,
    'longitude': best.longitude,
    'depth_km': best.depthKm,
    'origin_time': originTime.toIso8601String(),
    'origin_offset_s': best.originOffsetSeconds,
    'score': best.score,
    'phase_score': best.phaseScore,
    'phase_mean_residual_s': best.phaseMeanResidualSeconds,
    'phase_residual_p90_s': best.phaseResidualP90Seconds,
    'phase_p_count': best.phasePCount,
    'phase_s_count': best.phaseSCount,
    'phase_other_count': best.phaseOtherCount,
    'unarrived_penalty': best.unarrivedPenalty,
    'unarrived_penalty_count': best.unarrivedPenaltyCount,
    'weighted_count': best.weightedCount,
    'candidate_constraints': {
      'model':
          'scratch_4_3_offset4_count_offset5_distance_proxy_from_current_usable_v1',
      'max_detected_distance_km': candidateConstraints.maxDetectedDistanceKm,
      'max_allowed_depth_km': candidateConstraints.maxAllowedDepthKm,
      'max_allowed_distance_km': candidateConstraints.maxAllowedDistanceKm,
    },
    'single_trigger_circle_eew_gate': _kotoho7CircleEewGateDiagnostics(request),
    'initial_source_cache': {
      'latitude': seedLatitude,
      'longitude': seedLongitude,
      'depth_km': 10.0,
      'origin_offset_s': -2.0,
      'source': 'first_detected_station_rounded_0_01deg',
      'station_code': first.descriptor.code,
    },
    'search': {
      'type': 'staged_neighbor_descent',
      'max_iterations_per_stage':
          'Scratch-derived dynamic: h2/h10 depend on early age/count; v50=100, v10=100, h60=10',
      'neighbor_set':
          'current, lon +/- step, lat +/- step, optional depth +/- step',
      'stages': stages,
      'bbox': [
        searchBounds.$1,
        searchBounds.$2,
        searchBounds.$3,
        searchBounds.$4,
      ],
    },
    'scoring_config': const {
      'origin_mean':
          'plain arithmetic mean of detected-station selected P/S origins',
      'origin_scatter':
          'scratch-style normalized weighted squared origin scatter',
      'station_weight':
          'first_detected_station_distance / station_distance, fixed to 1 within 50km',
      'phase_model':
          'P until 15s gate; after gate use S when cached ten:+6 is true',
      'station_s_flag_model':
          'scratch_stateful_ten_plus_6_from_cached_plus_7_plus_8_v3',
      'scratch_error_scale':
          'S-factor * ((weightedResidualSquares + unarrivedCount) / weightSum) * (30 + 20000/(1+n^2) + 2000/(50+n))',
      'unarrived_gate':
          'elapsed <= 3s or elapsed <= 10s with detectedCount < 30',
      'unarrived_penalty': '+1 per predicted-arrived undetected station',
    },
  };
}

Map<String, Object?> _kotoho7CircleEewGateDiagnostics(
  SourceEstimationRequest request,
) {
  const expectedMetadataKeys = <String>[
    'kotoho7_eew_slots',
    'kotoho7_eew_active_flags',
    'kotoho7_eew_extra_info',
    'kotoho7_station_eew_source_distances_km',
  ];
  final presentKeys = <String>[
    for (final key in expectedMetadataKeys)
      if (request.metadata.containsKey(key)) key,
  ];
  return {
    'model': 'scratch_tandoku_circle_trigger_eew_gate',
    'implemented': false,
    'reason': presentKeys.length == expectedMetadataKeys.length
        ? 'metadata_present_but_gate_not_wired'
        : 'missing_scratch_eew_circle_inputs',
    'scratch_branch': '単独トリガ 状態 -> 円の中トリガ',
    'scratch_requirements': const {
      'eew_active_global': 'EEW全体で発表中？ == 1',
      'eew_active_per_slot': '0-1EEW発表中[slot + 1] > 0',
      'eew_depth_gate': '0EEW[slot * 14 + 8] < 150',
      'station_distance_cache': 'ten c:震源距離[(station - 1) * 10 + slot + 1]',
      'magnitude': '0EEW[slot * 14 + 9]',
      'depth_km': '0EEW[slot * 14 + 8]',
      'inner_radius_km': '0EEW[slot * 14 + 13] - 100',
      'outer_radius_km': '0EEW[slot * 14 + 12] * 0.8',
      'extra_radius_factor': '0-2EEW追加情報[slot * 14 + 3]',
      'predicted_intensity_gate': '距離の震度 > -0.5 OR station distance < 200km',
    },
    'expected_metadata_keys': expectedMetadataKeys,
    'present_metadata_keys': presentKeys,
    'metadata_source':
        'current NIED GIF source-estimation request does not carry Scratch 0EEW/0-1EEW/0-2EEW equivalents',
  };
}

(double, double, double, double) _kotoho7SearchBounds(
  List<SeismicStationEventRecord> usable, {
  required double bboxPaddingDeg,
}) {
  return _searchBounds(usable, bboxPaddingDeg: math.max(2.5, bboxPaddingDeg));
}

List<SeismicStationEventRecord> _kotoho7UnarrivedRecords(
  SourceEstimationRequest request,
  List<SeismicStationEventRecord> usable,
) {
  final usableCodes = {for (final record in usable) record.descriptor.code};
  final result = request.stations
      .where((record) {
        return request.sensorSelection.accepts(record.descriptor) &&
            !usableCodes.contains(record.descriptor.code) &&
            !record.isActiveLike;
      })
      .toList(growable: false);
  result.sort((a, b) => a.descriptor.code.compareTo(b.descriptor.code));
  return result;
}

_HypCandidate _kotoho7LocalSearchStage(
  List<SeismicStationEventRecord> usable,
  List<SeismicStationEventRecord> unarrived, {
  required DateTime earliestObserved,
  required DateTime observedAt,
  required (double, double, double, double) searchBounds,
  required _HypCandidate currentBest,
  required _HypCandidate phaseReference,
  required double horizontalStepDeg,
  required double? depthStepKm,
  required String stageName,
  required List<Map<String, Object?>> stages,
  int maxIterations = 150,
  Map<String, bool>? stationSFlagByCode,
  Map<String, DateTime>? stationObservedAtByCode,
}) {
  var best = currentBest;
  var iterations = 0;
  var moved = false;
  while (iterations < maxIterations) {
    iterations += 1;
    var localBest = best;
    final candidates = <({double lat, double lng, double depth})>[
      (lat: best.latitude, lng: best.longitude, depth: best.depthKm),
      (
        lat: best.latitude + horizontalStepDeg,
        lng: best.longitude,
        depth: best.depthKm,
      ),
      (
        lat: best.latitude - horizontalStepDeg,
        lng: best.longitude,
        depth: best.depthKm,
      ),
      (
        lat: best.latitude,
        lng: best.longitude + horizontalStepDeg,
        depth: best.depthKm,
      ),
      (
        lat: best.latitude,
        lng: best.longitude - horizontalStepDeg,
        depth: best.depthKm,
      ),
      if (depthStepKm != null)
        (
          lat: best.latitude,
          lng: best.longitude,
          depth: best.depthKm + depthStepKm,
        ),
      if (depthStepKm != null)
        (
          lat: best.latitude,
          lng: best.longitude,
          depth: best.depthKm - depthStepKm,
        ),
    ];
    for (final candidate in candidates) {
      if (candidate.lat < searchBounds.$1 ||
          candidate.lat > searchBounds.$2 ||
          candidate.lng < searchBounds.$3 ||
          candidate.lng > searchBounds.$4 ||
          candidate.depth < 10.0 ||
          candidate.depth > 700.0) {
        continue;
      }
      final scored = _scoreKotoho7HypCandidate(
        usable,
        unarrived,
        earliestObserved: earliestObserved,
        observedAt: observedAt,
        latitude: candidate.lat,
        longitude: candidate.lng,
        depthKm: candidate.depth,
        originSeedSeconds: best.originOffsetSeconds,
        phaseReferenceLatitude: phaseReference.latitude,
        phaseReferenceLongitude: phaseReference.longitude,
        phaseReferenceDepthKm: phaseReference.depthKm,
        phaseReferenceOriginOffsetSeconds: phaseReference.originOffsetSeconds,
        stationSFlagByCode: stationSFlagByCode,
        stationObservedAtByCode: stationObservedAtByCode,
      );
      if (scored.score + 1e-6 < localBest.score) {
        localBest = scored;
      }
    }
    if (localBest.score + 1e-6 >= best.score) break;
    best = localBest;
    moved = true;
  }
  stages.add({
    'stage': stageName,
    'horizontal_step_deg': horizontalStepDeg,
    'depth_step_km': depthStepKm,
    'max_iterations': maxIterations,
    'iterations': iterations,
    'moved': moved,
    'best_latitude': best.latitude,
    'best_longitude': best.longitude,
    'best_depth_km': best.depthKm,
    'best_origin_offset_s': best.originOffsetSeconds,
    'best_score': best.score,
    'phase_mean_residual_s': best.phaseMeanResidualSeconds,
    'phase_p_count': best.phasePCount,
    'phase_s_count': best.phaseSCount,
    'phase_other_count': best.phaseOtherCount,
    'unarrived_penalty': best.unarrivedPenalty,
    's_factor': best.scratchSFactor,
    's_flag_count': best.scratchSFlagCount,
    'weighted_residual_squares': best.scratchWeightedResidualSquares,
    'weight_sum': best.scratchWeightSum,
    'station_count_scale': best.scratchStationCountScale,
    'unarrived_gate_open': best.scratchUnarrivedGateOpen,
    'unarrived_input_count': best.scratchUnarrivedInputCount,
    'unarrived_within_radius_count': best.scratchUnarrivedWithinRadiusCount,
    'distance_from_first_detected_km': best.scratchDistanceFromFirstDetectedKm,
    'max_allowed_depth_km': best.scratchMaxAllowedDepthKm,
    'max_allowed_distance_km': best.scratchMaxAllowedDistanceKm,
    'reject_reason': best.scratchRejectReason,
  });
  return best;
}

_HypCandidate _scoreKotoho7HypCandidate(
  List<SeismicStationEventRecord> usable,
  List<SeismicStationEventRecord> unarrived, {
  required DateTime earliestObserved,
  required DateTime observedAt,
  required double latitude,
  required double longitude,
  required double depthKm,
  required double originSeedSeconds,
  double? phaseReferenceLatitude,
  double? phaseReferenceLongitude,
  double? phaseReferenceDepthKm,
  double? phaseReferenceOriginOffsetSeconds,
  Map<String, bool>? stationSFlagByCode,
  Map<String, DateTime>? stationObservedAtByCode,
}) {
  const residualToleranceSeconds = 2.8;
  final sortedUsable = _kotoho7SortedTimingRecords(usable);
  final constraints = _kotoho7CandidateConstraints(sortedUsable);
  final distanceFromFirstDetectedKm = _haversineKm(
    latitude,
    longitude,
    constraints.firstDetectedLatitude,
    constraints.firstDetectedLongitude,
  );
  if (depthKm < 10.0 ||
      depthKm > 700.0 ||
      depthKm > constraints.maxAllowedDepthKm ||
      distanceFromFirstDetectedKm > constraints.maxAllowedDistanceKm) {
    final rejectReason = depthKm < 10.0
        ? 'scratch_stop_depth_lt_10'
        : depthKm > 700.0
        ? 'scratch_stop_depth_gt_700'
        : depthKm > constraints.maxAllowedDepthKm
        ? 'scratch_stop_depth_gt_allowed_max'
        : 'scratch_stop_distance_from_first_gt_allowed_max';
    return _invalidHypCandidate(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originSeedSeconds: originSeedSeconds,
      scratchRejectReason: rejectReason,
      scratchDistanceFromFirstDetectedKm: distanceFromFirstDetectedKm,
      scratchMaxAllowedDepthKm: constraints.maxAllowedDepthKm,
      scratchMaxAllowedDistanceKm: constraints.maxAllowedDistanceKm,
    );
  }
  final observedSeconds = <double>[];
  final pTravelSeconds = <double>[];
  final sTravelSeconds = <double>[];
  final distances = <double>[];

  for (final record in sortedUsable) {
    final stationObservedAt =
        stationObservedAtByCode?[record.descriptor.code] ??
        record.firstTriggerAt ??
        record.firstRiseAt;
    if (stationObservedAt == null) continue;
    observedSeconds.add(
      stationObservedAt.difference(earliestObserved).inMilliseconds / 1000.0,
    );
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    distances.add(surfaceDistanceKm);
    pTravelSeconds.add(
      Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: true,
      ),
    );
    sTravelSeconds.add(
      Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: false,
      ),
    );
  }

  if (observedSeconds.isEmpty) {
    return _invalidHypCandidate(
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originSeedSeconds: originSeedSeconds,
      scratchRejectReason: 'scratch_stop_no_detected_time_samples',
      scratchDistanceFromFirstDetectedKm: distanceFromFirstDetectedKm,
      scratchMaxAllowedDepthKm: constraints.maxAllowedDepthKm,
      scratchMaxAllowedDistanceKm: constraints.maxAllowedDistanceKm,
    );
  }

  final currentElapsedSeconds =
      observedAt.difference(earliestObserved).inMilliseconds / 1000.0;
  final sGateOpen = currentElapsedSeconds > 15.0;
  final firstDetectedDistanceKm = math.max(50.0, distances.first);
  final sFlagReferenceLatitude = phaseReferenceLatitude ?? latitude;
  final sFlagReferenceLongitude = phaseReferenceLongitude ?? longitude;
  final sFlagReferenceDepthKm = phaseReferenceDepthKm ?? depthKm;
  final sFlagReferenceOriginOffsetSeconds =
      phaseReferenceOriginOffsetSeconds ?? originSeedSeconds;
  final weights = <double>[];
  final originSamples = <double>[];
  final phaseIndexes = <int>[];
  var sFlagCount = 0;
  for (var index = 0; index < observedSeconds.length; index++) {
    final distanceKm = math.max(50.0, distances[index]);
    final weight = firstDetectedDistanceKm / distanceKm;
    final pOrigin = observedSeconds[index] - pTravelSeconds[index];
    final sOrigin = observedSeconds[index] - sTravelSeconds[index];
    final phaseReferenceSurfaceDistanceKm = _haversineKm(
      sFlagReferenceLatitude,
      sFlagReferenceLongitude,
      sortedUsable[index].descriptor.coordinate.latitude,
      sortedUsable[index].descriptor.coordinate.longitude,
    );
    final phaseReferenceHypocentralDistanceKm = math.sqrt(
      phaseReferenceSurfaceDistanceKm * phaseReferenceSurfaceDistanceKm +
          sFlagReferenceDepthKm * sFlagReferenceDepthKm,
    );
    final phaseReferencePArrivalSeconds =
        sFlagReferenceOriginOffsetSeconds +
        Jma2001TravelTimeApproximation.travelTimeSeconds(
          hypocentralDistanceKm: phaseReferenceHypocentralDistanceKm,
          depthKm: sFlagReferenceDepthKm,
          pWave: true,
        );
    final phaseReferenceSArrivalSeconds =
        sFlagReferenceOriginOffsetSeconds +
        Jma2001TravelTimeApproximation.travelTimeSeconds(
          hypocentralDistanceKm: phaseReferenceHypocentralDistanceKm,
          depthKm: sFlagReferenceDepthKm,
          pWave: false,
        );
    final stationCode = sortedUsable[index].descriptor.code;
    final cachedSFlag = stationSFlagByCode?[stationCode];
    final articleSFlagProxy =
        cachedSFlag ??
        ((observedSeconds[index] - phaseReferenceSArrivalSeconds).abs() <
            (observedSeconds[index] - phaseReferencePArrivalSeconds).abs());
    final useS = sGateOpen && articleSFlagProxy;
    if (articleSFlagProxy) sFlagCount += 1;
    weights.add(weight);
    originSamples.add(useS ? sOrigin : pOrigin);
    phaseIndexes.add(useS ? 1 : 0);
  }
  final originOffset = originSamples.isEmpty
      ? originSeedSeconds
      : _mean(originSamples);

  var weightedResidualSquares = 0.0;
  var residualSum = 0.0;
  var weightSum = 0.0;
  var pCount = 0;
  var sCount = 0;
  var otherCount = 0;
  final residuals = <double>[];
  for (var index = 0; index < originSamples.length; index++) {
    final residual = (originSamples[index] - originOffset).abs();
    residuals.add(residual);
    residualSum += residual;
    weightSum += weights[index];
    weightedResidualSquares += weights[index] * residual * residual;
    if (residual > residualToleranceSeconds) {
      otherCount += 1;
    } else if (phaseIndexes[index] == 1) {
      sCount += 1;
    } else {
      pCount += 1;
    }
  }

  final unarrivedGateOpen =
      currentElapsedSeconds <= 3.0 ||
      (currentElapsedSeconds <= 10.0 && sortedUsable.length < 30);
  var unarrivedPenalty = 0.0;
  var unarrivedPenaltyCount = 0;
  var unarrivedWithinRadiusCount = 0;
  if (unarrivedGateOpen && unarrived.isNotEmpty && distances.isNotEmpty) {
    final maxDetectedDistanceKm = distances.reduce(math.max);
    for (final record in unarrived) {
      final surfaceDistanceKm = _haversineKm(
        latitude,
        longitude,
        record.descriptor.coordinate.latitude,
        record.descriptor.coordinate.longitude,
      );
      if (surfaceDistanceKm > maxDetectedDistanceKm + 30.0) continue;
      unarrivedWithinRadiusCount += 1;
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: true,
      );
      final predictedArrivalSeconds = originOffset + pTravelSeconds;
      if (currentElapsedSeconds > predictedArrivalSeconds) {
        unarrivedPenalty += 1.0;
        unarrivedPenaltyCount += 1;
      }
    }
  }
  final phaseCount = originSamples.length;
  final weightDenominator = weightSum <= 0 ? phaseCount.toDouble() : weightSum;
  final stationCountScale =
      30.0 +
      20000.0 / (1.0 + phaseCount * phaseCount) +
      2000.0 / (50.0 + phaseCount);
  final sFactor = math.max(
    0.25,
    1.0 - (sFlagCount * 3.0) / math.max(1, phaseCount),
  );
  final phaseScore = weightDenominator <= 0
      ? double.infinity
      : sFactor *
            ((weightedResidualSquares + unarrivedPenalty) / weightDenominator) *
            stationCountScale;
  final score = phaseScore;

  return _HypCandidate(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originOffsetSeconds: originOffset,
    score: score,
    phaseScore: phaseScore,
    phaseMeanResidualSeconds: residuals.isEmpty
        ? 0
        : residualSum / residuals.length,
    phaseResidualP90Seconds: _percentile(residuals, 0.90),
    phasePCount: pCount,
    phaseSCount: sCount,
    phaseOtherCount: otherCount,
    pairScore: 0,
    pairMeanResidualSeconds: 0,
    pairCount: 0,
    unarrivedPenalty: unarrivedPenalty,
    unarrivedPenaltyCount: unarrivedPenaltyCount,
    phaseBalancePenalty: 0,
    weightedCount: weightSum,
    scratchSFactor: sFactor,
    scratchSFlagCount: sFlagCount,
    scratchWeightedResidualSquares: weightedResidualSquares,
    scratchWeightSum: weightSum,
    scratchStationCountScale: stationCountScale,
    scratchUnarrivedGateOpen: unarrivedGateOpen,
    scratchUnarrivedInputCount: unarrived.length,
    scratchUnarrivedWithinRadiusCount: unarrivedWithinRadiusCount,
    scratchDistanceFromFirstDetectedKm: distanceFromFirstDetectedKm,
    scratchMaxAllowedDepthKm: constraints.maxAllowedDepthKm,
    scratchMaxAllowedDistanceKm: constraints.maxAllowedDistanceKm,
  );
}

List<SeismicStationEventRecord> _kotoho7SortedTimingRecords(
  List<SeismicStationEventRecord> usable,
) {
  return [...usable]..sort((left, right) {
    final leftAt = left.firstTriggerAt ?? left.firstRiseAt;
    final rightAt = right.firstTriggerAt ?? right.firstRiseAt;
    if (leftAt == null && rightAt == null) {
      return left.descriptor.code.compareTo(right.descriptor.code);
    }
    if (leftAt == null) return 1;
    if (rightAt == null) return -1;
    final timeCmp = leftAt.compareTo(rightAt);
    if (timeCmp != 0) return timeCmp;
    return left.descriptor.code.compareTo(right.descriptor.code);
  });
}

_HypCandidate _invalidHypCandidate({
  required double latitude,
  required double longitude,
  required double depthKm,
  required double originSeedSeconds,
  String? scratchRejectReason,
  double? scratchDistanceFromFirstDetectedKm,
  double? scratchMaxAllowedDepthKm,
  double? scratchMaxAllowedDistanceKm,
}) {
  return _HypCandidate(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originOffsetSeconds: originSeedSeconds,
    score: double.infinity,
    phaseScore: double.infinity,
    phaseMeanResidualSeconds: double.infinity,
    phaseResidualP90Seconds: double.infinity,
    phasePCount: 0,
    phaseSCount: 0,
    phaseOtherCount: 0,
    pairScore: 0,
    pairMeanResidualSeconds: 0,
    pairCount: 0,
    unarrivedPenalty: 0,
    unarrivedPenaltyCount: 0,
    phaseBalancePenalty: 0,
    weightedCount: 0,
    scratchRejectReason: scratchRejectReason,
    scratchDistanceFromFirstDetectedKm: scratchDistanceFromFirstDetectedKm,
    scratchMaxAllowedDepthKm: scratchMaxAllowedDepthKm,
    scratchMaxAllowedDistanceKm: scratchMaxAllowedDistanceKm,
  );
}

({
  double firstDetectedLatitude,
  double firstDetectedLongitude,
  double maxDetectedDistanceKm,
  double maxAllowedDepthKm,
  double maxAllowedDistanceKm,
})
_kotoho7CandidateConstraints(List<SeismicStationEventRecord> sortedUsable) {
  final first = sortedUsable.first;
  final firstLat = first.descriptor.coordinate.latitude;
  final firstLng = first.descriptor.coordinate.longitude;
  var maxDetectedDistanceKm = 0.0;
  for (final record in sortedUsable) {
    maxDetectedDistanceKm = math.max(
      maxDetectedDistanceKm,
      _haversineKm(
        firstLat,
        firstLng,
        record.descriptor.coordinate.latitude,
        record.descriptor.coordinate.longitude,
      ),
    );
  }
  final detectedCount = sortedUsable.length;
  final maxAllowedDepthKm =
      (11.0 + math.pow(maxDetectedDistanceKm, 3) * 0.00008).roundToDouble();
  final maxAllowedDistanceKm =
      (50.0 + 0.3 * (detectedCount * 10.0 + maxDetectedDistanceKm))
          .roundToDouble();
  return (
    firstDetectedLatitude: firstLat,
    firstDetectedLongitude: firstLng,
    maxDetectedDistanceKm: maxDetectedDistanceKm,
    maxAllowedDepthKm: maxAllowedDepthKm,
    maxAllowedDistanceKm: maxAllowedDistanceKm,
  );
}

Map<String, Object?> _hypReferenceStateProxy(
  SourceEstimationRequest request,
  List<SeismicStationEventRecord> usable, {
  required DateTime earliestObserved,
  required _HypCandidate best,
  required bool useJma2001TravelTime,
}) {
  const pWaveSpeedKmPerSec = 6.0;
  const sWaveSpeedKmPerSec = 3.5;
  const residualToleranceSeconds = 2.8;
  const stationRowLimit = 32;

  final currentCloudTimeSeconds = _secondsSince(
    request.observedAt,
    earliestObserved,
  );
  final firstDetectionTimeSeconds = 0.0;
  final sGateOpen = currentCloudTimeSeconds > firstDetectionTimeSeconds + 15.0;
  final sourceOriginSeconds = best.originOffsetSeconds;
  final rows = <Map<String, Object?>>[];
  var derivedSFlagCount = 0;
  var gatedSCount = 0;
  var acceptedPCount = 0;
  var acceptedSCount = 0;
  var otherCount = 0;
  var referenceLikeDerivedSFlagCount = 0;
  var referenceLikeGatedSCount = 0;
  var referenceLikeAcceptedPCount = 0;
  var referenceLikeAcceptedSCount = 0;
  var referenceLikeOtherCount = 0;
  var pretriggerCacheProxyCount = 0;
  var nearestSevenFallbackCount = 0;

  for (final record in usable) {
    final observedAt = record.firstTriggerAt ?? record.firstRiseAt;
    if (observedAt == null) continue;
    final observedSeconds = _secondsSince(observedAt, earliestObserved);
    final pretriggerCacheSeconds = _hypPretriggerCacheSeconds(
      record,
      earliestObserved: earliestObserved,
      fallbackObservedAt: observedAt,
    );
    final nearestSeven = _hypNearestSevenOlderObservedTime(
      record,
      usable,
      earliestObserved: earliestObserved,
      currentCloudTimeSeconds: currentCloudTimeSeconds,
    );
    final referenceLikeTime = _hypReferenceLikeObservedSeconds(
      rawObservedSeconds: observedSeconds,
      pretriggerCacheSeconds: pretriggerCacheSeconds,
      nearestSevenOlderSeconds: nearestSeven.seconds,
      currentCloudTimeSeconds: currentCloudTimeSeconds,
    );
    if (referenceLikeTime.source == 'ten_plus_5_pretrigger_cache_proxy') {
      pretriggerCacheProxyCount++;
    }
    if (referenceLikeTime.source == 'nearest_7_old_trigger_fallback_proxy') {
      nearestSevenFallbackCount++;
    }
    final lastObservedSeconds = record.lastObservedAt == null
        ? null
        : _secondsSince(record.lastObservedAt!, earliestObserved);
    final surfaceDistanceKm = _haversineKm(
      best.latitude,
      best.longitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + best.depthKm * best.depthKm,
    );
    final pTravelSeconds = useJma2001TravelTime
        ? Jma2001TravelTimeApproximation.travelTimeSeconds(
            hypocentralDistanceKm: hypocentralDistanceKm,
            depthKm: best.depthKm,
            pWave: true,
          )
        : hypocentralDistanceKm / pWaveSpeedKmPerSec;
    final sTravelSeconds = useJma2001TravelTime
        ? Jma2001TravelTimeApproximation.travelTimeSeconds(
            hypocentralDistanceKm: hypocentralDistanceKm,
            depthKm: best.depthKm,
            pWave: false,
          )
        : hypocentralDistanceKm / sWaveSpeedKmPerSec;
    final predictedPSeconds = sourceOriginSeconds + pTravelSeconds;
    final predictedSSeconds = sourceOriginSeconds + sTravelSeconds;
    final pResidualSeconds = (observedSeconds - predictedPSeconds).abs();
    final sResidualSeconds = (observedSeconds - predictedSSeconds).abs();
    final stationSFlag = sResidualSeconds < pResidualSeconds;
    final useS = sGateOpen && stationSFlag;
    final selectedResidualSeconds = useS ? sResidualSeconds : pResidualSeconds;
    final accepted = selectedResidualSeconds <= residualToleranceSeconds;
    if (stationSFlag) derivedSFlagCount++;
    if (useS) gatedSCount++;
    if (!accepted) {
      otherCount++;
    } else if (useS) {
      acceptedSCount++;
    } else {
      acceptedPCount++;
    }
    final referenceLikePResidualSeconds =
        (referenceLikeTime.seconds - predictedPSeconds).abs();
    final referenceLikeSResidualSeconds =
        (referenceLikeTime.seconds - predictedSSeconds).abs();
    final referenceLikeStationSFlag =
        referenceLikeSResidualSeconds < referenceLikePResidualSeconds;
    final referenceLikeUseS = sGateOpen && referenceLikeStationSFlag;
    final referenceLikeSelectedResidualSeconds = referenceLikeUseS
        ? referenceLikeSResidualSeconds
        : referenceLikePResidualSeconds;
    final referenceLikeAccepted =
        referenceLikeSelectedResidualSeconds <= residualToleranceSeconds;
    if (referenceLikeStationSFlag) referenceLikeDerivedSFlagCount++;
    if (referenceLikeUseS) referenceLikeGatedSCount++;
    if (!referenceLikeAccepted) {
      referenceLikeOtherCount++;
    } else if (referenceLikeUseS) {
      referenceLikeAcceptedSCount++;
    } else {
      referenceLikeAcceptedPCount++;
    }
    final sortKey =
        (stationSFlag ? 100000.0 : 0.0) +
        (useS ? 10000.0 : 0.0) +
        math.min(9999.0, selectedResidualSeconds);
    rows.add({
      '_sort_key': sortKey,
      'station_id': record.descriptor.stationId,
      'code': record.descriptor.code,
      'network': record.descriptor.network,
      'latitude': record.descriptor.coordinate.latitude,
      'longitude': record.descriptor.coordinate.longitude,
      'sensor_role': record.descriptor.sensorRole.name,
      'ten_plus_1_observed_time_s': observedSeconds,
      'ten_plus_1_observed_time': observedAt.toIso8601String(),
      'observed_time_source': record.firstTriggerAt != null
          ? 'first_trigger_at'
          : 'first_rise_at',
      'ten_plus_1_reference_like_time_s': referenceLikeTime.seconds,
      'ten_plus_1_reference_like_source': referenceLikeTime.source,
      'ten_plus_2_last_update_time_s': lastObservedSeconds,
      'ten_plus_3_detection_id_proxy': 1,
      'ten_plus_4_distance_km': surfaceDistanceKm,
      'ten_plus_5_pretrigger_cache_s': pretriggerCacheSeconds,
      'ten_plus_5_pretrigger_cache_model':
          'stateful_rising_frame_write_clear_proxy_v1',
      'nearest_7_old_trigger_time_s': nearestSeven.seconds,
      'nearest_7_old_trigger_station_codes': nearestSeven.stationCodes,
      'ten_plus_6_s_closer_than_p': stationSFlag,
      'reference_like_ten_plus_6_s_closer_than_p': referenceLikeStationSFlag,
      'ten_plus_7_predicted_p_arrival_s': predictedPSeconds,
      'ten_plus_8_predicted_s_arrival_s': predictedSSeconds,
      'p_travel_s': pTravelSeconds,
      's_travel_s': sTravelSeconds,
      'p_residual_s': pResidualSeconds,
      's_residual_s': sResidualSeconds,
      'reference_like_p_residual_s': referenceLikePResidualSeconds,
      'reference_like_s_residual_s': referenceLikeSResidualSeconds,
      'phase_after_gate': useS ? 'S' : 'P',
      'reference_like_phase_after_gate': referenceLikeUseS ? 'S' : 'P',
      'selected_residual_s': selectedResidualSeconds,
      'reference_like_selected_residual_s':
          referenceLikeSelectedResidualSeconds,
      'accepted_by_residual_proxy': accepted,
      'reference_like_accepted_by_residual_proxy': referenceLikeAccepted,
      'recompute_trigger_proxy_reasons': const [
        'membership_assignment_or_change',
        'source_cache_update',
        'distance_cache_update',
      ],
      'last_value': record.lastValue,
      'peak_value': record.peakValue,
      'last_detect_level': record.lastDetectLevel,
      'last_activity': record.lastActivity,
      'sample_count': record.sampleCount,
    });
  }

  rows.sort((left, right) {
    final leftKey = (left['_sort_key'] as num?)?.toDouble() ?? 0.0;
    final rightKey = (right['_sort_key'] as num?)?.toDouble() ?? 0.0;
    return rightKey.compareTo(leftKey);
  });
  final exportedRows = rows
      .take(stationRowLimit)
      .map((row) {
        final copy = Map<String, Object?>.from(row);
        copy.remove('_sort_key');
        return copy;
      })
      .toList(growable: false);

  return {
    'model': 'jq_reference_state_proxy_v1',
    'status': 'proxy_not_full_state_machine',
    'caveats': const [
      'ten_plus_5 is reconstructed from Dart station observation history with a stateful rising-frame proxy, not copied from the reference runtime',
      'detection_id membership is collapsed to one proxy id for this diagnostic',
      '4-4 source cache is represented by the selected HYP/JQ candidate',
    ],
    'station_row_limit': stationRowLimit,
    'station_count': rows.length,
    'exported_station_count': exportedRows.length,
    'current_cloud_time_s': currentCloudTimeSeconds,
    'first_detection_time_s': firstDetectionTimeSeconds,
    's_gate_threshold_s': 15.0,
    's_gate_open': sGateOpen,
    'detection_id_proxy': {
      'id': 1,
      'four_3_offset_proxy': 0,
      'first_detection_time_s': firstDetectionTimeSeconds,
      'current_age_s': currentCloudTimeSeconds - firstDetectionTimeSeconds,
      'active_station_count': usable.length,
    },
    'source_cache_4_4_proxy': {
      'plus_2_longitude': best.longitude,
      'plus_3_latitude': best.latitude,
      'plus_4_depth_km': best.depthKm,
      'plus_5_origin_time_s': sourceOriginSeconds,
      'origin_time': earliestObserved
          .add(Duration(milliseconds: (sourceOriginSeconds * 1000).round()))
          .toIso8601String(),
    },
    'station_state_counts': {
      'ten_plus_6_s_closer_than_p_count': derivedSFlagCount,
      'gated_s_count': gatedSCount,
      'accepted_p_count': acceptedPCount,
      'accepted_s_count': acceptedSCount,
      'other_count': otherCount,
      'reference_like_ten_plus_6_s_closer_than_p_count':
          referenceLikeDerivedSFlagCount,
      'reference_like_gated_s_count': referenceLikeGatedSCount,
      'reference_like_accepted_p_count': referenceLikeAcceptedPCount,
      'reference_like_accepted_s_count': referenceLikeAcceptedSCount,
      'reference_like_other_count': referenceLikeOtherCount,
      'ten_plus_5_pretrigger_cache_proxy_count': pretriggerCacheProxyCount,
      'nearest_7_old_trigger_fallback_proxy_count': nearestSevenFallbackCount,
    },
    'station_field_map': const {
      'ten_plus_1': 'observed/trigger time used by HYP',
      'ten_plus_2': 'last/update time cache',
      'ten_plus_3': 'detection id membership',
      'ten_plus_4': 'distance cache to detection/source',
      'ten_plus_5': 'stateful pre-trigger/rise cache proxy',
      'ten_plus_6': 'abs(observed - S_pred) < abs(observed - P_pred)',
      'ten_plus_7': 'predicted P arrival from current source cache',
      'ten_plus_8': 'predicted S arrival from current source cache',
    },
    'stations': exportedRows,
  };
}

double _secondsSince(DateTime value, DateTime origin) =>
    value.difference(origin).inMilliseconds / 1000.0;

double? _hypPretriggerCacheSeconds(
  SeismicStationEventRecord record, {
  required DateTime earliestObserved,
  required DateTime fallbackObservedAt,
}) {
  double? cacheSeconds;
  double? previousSignal;
  int? previousDetectLevel;
  for (final frame in record.observationHistory.frames) {
    if (frame.dataTime.isAfter(fallbackObservedAt)) break;
    if (frame.isMissing || frame.isStale || !frame.isDecodable) continue;
    final signal = _hypFrameSignal(frame);
    final activeLike = _hypFrameActiveLike(frame);
    if (!activeLike) {
      cacheSeconds = null;
      previousSignal = signal ?? previousSignal;
      previousDetectLevel = frame.detectLevel ?? previousDetectLevel;
      continue;
    }
    final risingBySignal =
        signal != null &&
        (previousSignal == null || signal > previousSignal + 0.01);
    final detectLevel = frame.detectLevel;
    final risingByDetectLevel =
        detectLevel != null &&
        (previousDetectLevel == null || detectLevel > previousDetectLevel);
    final rising = risingBySignal || risingByDetectLevel || frame.isTriggered;
    if (rising) {
      cacheSeconds ??= _secondsSince(frame.dataTime, earliestObserved);
    } else {
      cacheSeconds = null;
    }
    previousSignal = signal ?? previousSignal;
    previousDetectLevel = detectLevel ?? previousDetectLevel;
  }
  if (cacheSeconds != null) {
    final fallbackSeconds = _secondsSince(fallbackObservedAt, earliestObserved);
    if (fallbackSeconds - cacheSeconds <= 20.0) return cacheSeconds;
  }
  return null;
}

double? _hypFrameSignal(SeismicStationObservationFrame frame) {
  final value = frame.value;
  if (value != null && value.isFinite) return value;
  final kaLevel = frame.rawLevel ?? frame.detectLevel;
  if (kaLevel != null) {
    return JpShindoScale.rawShindoFromKanameishiLevel(kaLevel);
  }
  return null;
}

bool _hypFrameActiveLike(SeismicStationObservationFrame frame) {
  final signal = _hypFrameSignal(frame);
  return frame.isTriggered ||
      (frame.detectLevel != null && frame.detectLevel! > 0) ||
      (signal != null && signal > 0.0);
}

({double? seconds, List<String> stationCodes})
_hypNearestSevenOlderObservedTime(
  SeismicStationEventRecord record,
  List<SeismicStationEventRecord> usable, {
  required DateTime earliestObserved,
  required double currentCloudTimeSeconds,
}) {
  final neighbors = <({SeismicStationEventRecord record, double distanceKm})>[];
  for (final other in usable) {
    if (identical(other, record)) continue;
    final otherObservedAt = other.firstTriggerAt ?? other.firstRiseAt;
    if (otherObservedAt == null) continue;
    neighbors.add((
      record: other,
      distanceKm: _haversineKm(
        record.descriptor.coordinate.latitude,
        record.descriptor.coordinate.longitude,
        other.descriptor.coordinate.latitude,
        other.descriptor.coordinate.longitude,
      ),
    ));
  }
  neighbors.sort((left, right) => left.distanceKm.compareTo(right.distanceKm));
  double? selected;
  final selectedCodes = <String>[];
  for (final neighbor in neighbors.take(7)) {
    final observedAt =
        neighbor.record.firstTriggerAt ?? neighbor.record.firstRiseAt;
    if (observedAt == null) continue;
    final seconds = _secondsSince(observedAt, earliestObserved);
    if (currentCloudTimeSeconds - seconds <= 20.0) continue;
    if (selected == null || seconds > selected) {
      selected = seconds;
    }
    selectedCodes.add(neighbor.record.descriptor.code);
  }
  selectedCodes.sort();
  return (seconds: selected, stationCodes: selectedCodes);
}

({double seconds, String source}) _hypReferenceLikeObservedSeconds({
  required double rawObservedSeconds,
  required double? pretriggerCacheSeconds,
  required double? nearestSevenOlderSeconds,
  required double currentCloudTimeSeconds,
}) {
  if (pretriggerCacheSeconds != null) {
    return (
      seconds: pretriggerCacheSeconds,
      source: 'ten_plus_5_pretrigger_cache_proxy',
    );
  }
  if (nearestSevenOlderSeconds != null &&
      currentCloudTimeSeconds - nearestSevenOlderSeconds > 20.0) {
    return (
      seconds: nearestSevenOlderSeconds,
      source: 'nearest_7_old_trigger_fallback_proxy',
    );
  }
  return (seconds: rawObservedSeconds, source: 'first_trigger_or_rise');
}

List<String> _hypSupportReasons({
  required bool supported,
  required bool depthSupported,
  required bool pOnlySupported,
}) {
  final reasons = <String>[];
  if (supported) reasons.add('two_phase_timing_supported');
  if (depthSupported) reasons.add('two_phase_depth_supported');
  if (pOnlySupported) reasons.add('p_only_timing_fit_only');
  return reasons;
}

List<String> _hypUnsupportedReasons(
  _HypCandidate candidate, {
  required bool supported,
  required bool depthSupported,
  required bool pOnlySupported,
  required double maxSupportedUnarrivedPenalty,
}) {
  if (supported || depthSupported || pOnlySupported) return const [];
  final reasons = <String>[];
  if (candidate.phasePCount < 3) reasons.add('insufficient_p_support');
  if (candidate.phaseSCount < 2) reasons.add('insufficient_s_support');
  if (candidate.phaseSCount == 0) reasons.add('no_s_support');
  if (candidate.phaseMeanResidualSeconds > 2.8) {
    reasons.add('phase_residual_too_large');
  }
  if (candidate.pairMeanResidualSeconds > 3.5) {
    reasons.add('pair_residual_too_large');
  }
  if (candidate.unarrivedPenalty > maxSupportedUnarrivedPenalty) {
    reasons.add('unarrived_penalty_too_large');
  }
  if (candidate.depthKm >= 100.0 &&
      candidate.unarrivedPenalty > maxSupportedUnarrivedPenalty) {
    reasons.add('deep_candidate_with_unarrived_gap');
  }
  return reasons;
}

List<double> _hypLocalDepthCandidates(
  double centerDepthKm,
  List<double> baseDepthCandidatesKm,
) {
  final candidates = <double>{
    centerDepthKm,
    for (final depthKm in baseDepthCandidatesKm)
      if ((depthKm - centerDepthKm).abs() <= 30.0) depthKm,
  }.toList();
  candidates.sort();
  return candidates;
}

_HypCandidate _searchHypGrid(
  List<SeismicStationEventRecord> usable,
  List<SeismicStationEventRecord> unarrived, {
  required DateTime earliestObserved,
  required DateTime observedAt,
  required double minLat,
  required double maxLat,
  required double minLng,
  required double maxLng,
  required double stepDeg,
  required List<double> depthCandidatesKm,
  required _HypCandidate currentBest,
  required double unarrivedPenaltyScoreWeight,
  required double depthRegularizationWeight,
  required double sSupportBonusPerStation,
  required double maxSSupportBonus,
  required bool useJma2001TravelTime,
  required bool useJqStyleScoring,
}) {
  var best = currentBest;
  for (double lat = minLat; lat <= maxLat + 1e-9; lat += stepDeg) {
    for (double lng = minLng; lng <= maxLng + 1e-9; lng += stepDeg) {
      for (final depthKm in depthCandidatesKm) {
        final scored = _scoreHypCandidate(
          usable,
          unarrived,
          earliestObserved: earliestObserved,
          observedAt: observedAt,
          latitude: lat,
          longitude: lng,
          depthKm: depthKm,
          unarrivedPenaltyScoreWeight: unarrivedPenaltyScoreWeight,
          depthRegularizationWeight: depthRegularizationWeight,
          sSupportBonusPerStation: sSupportBonusPerStation,
          maxSSupportBonus: maxSSupportBonus,
          useJma2001TravelTime: useJma2001TravelTime,
          useJqStyleScoring: useJqStyleScoring,
        );
        if (scored.score < best.score) best = scored;
      }
    }
  }
  return best;
}

_HypCandidate _scoreHypCandidate(
  List<SeismicStationEventRecord> usable,
  List<SeismicStationEventRecord> unarrived, {
  required DateTime earliestObserved,
  required DateTime observedAt,
  required double latitude,
  required double longitude,
  required double depthKm,
  required double unarrivedPenaltyScoreWeight,
  required double depthRegularizationWeight,
  required double sSupportBonusPerStation,
  required double maxSSupportBonus,
  required bool useJma2001TravelTime,
  required bool useJqStyleScoring,
}) {
  const pWaveSpeedKmPerSec = 6.0;
  const sWaveSpeedKmPerSec = 3.5;
  const residualToleranceSeconds = 2.8;
  final observedSeconds = <double>[];
  final pTravelSeconds = <double>[];
  final sTravelSeconds = <double>[];
  final distances = <double>[];
  for (final record in usable) {
    final observedAt = record.firstTriggerAt ?? record.firstRiseAt!;
    observedSeconds.add(
      observedAt.difference(earliestObserved).inMilliseconds / 1000.0,
    );
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    distances.add(surfaceDistanceKm);
    pTravelSeconds.add(
      useJma2001TravelTime
          ? Jma2001TravelTimeApproximation.travelTimeSeconds(
              hypocentralDistanceKm: hypocentralDistanceKm,
              depthKm: depthKm,
              pWave: true,
            )
          : hypocentralDistanceKm / pWaveSpeedKmPerSec,
    );
    sTravelSeconds.add(
      useJma2001TravelTime
          ? Jma2001TravelTimeApproximation.travelTimeSeconds(
              hypocentralDistanceKm: hypocentralDistanceKm,
              depthKm: depthKm,
              pWave: false,
            )
          : hypocentralDistanceKm / sWaveSpeedKmPerSec,
    );
  }

  final originOffsets = _hypOriginOffsetCandidates(
    observedSeconds,
    pTravelSeconds,
    sTravelSeconds,
  );
  var best = _HypCandidate(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originOffsetSeconds: originOffsets.first,
    score: double.infinity,
    phaseScore: double.infinity,
    phaseMeanResidualSeconds: double.infinity,
    phaseResidualP90Seconds: double.infinity,
    phasePCount: 0,
    phaseSCount: 0,
    phaseOtherCount: 0,
    pairScore: double.infinity,
    pairMeanResidualSeconds: double.infinity,
    pairCount: 0,
    unarrivedPenalty: 0,
    unarrivedPenaltyCount: 0,
    phaseBalancePenalty: 0,
    weightedCount: 0,
  );

  final firstDistanceKm = distances.reduce(math.min);
  for (final originOffset in originOffsets) {
    if (useJqStyleScoring) {
      final scored = _scoreHypCandidateJqStyle(
        unarrived,
        earliestObserved: earliestObserved,
        observedAt: observedAt,
        latitude: latitude,
        longitude: longitude,
        depthKm: depthKm,
        originSeedSeconds: originOffset,
        observedSeconds: observedSeconds,
        pTravelSeconds: pTravelSeconds,
        sTravelSeconds: sTravelSeconds,
        distances: distances,
        unarrivedPenaltyScoreWeight: unarrivedPenaltyScoreWeight,
        depthRegularizationWeight: depthRegularizationWeight,
        useJma2001TravelTime: useJma2001TravelTime,
      );
      if (scored.score < best.score) best = scored;
      continue;
    }

    final residuals = <double>[];
    final acceptedObserved = <double>[];
    final acceptedPredicted = <double>[];
    var phaseScore = 0.0;
    var residualSum = 0.0;
    var weightSum = 0.0;
    var pCount = 0;
    var sCount = 0;
    var otherCount = 0;
    for (var index = 0; index < observedSeconds.length; index++) {
      final pPredicted = originOffset + pTravelSeconds[index];
      final sPredicted = originOffset + sTravelSeconds[index];
      final pResidual = (observedSeconds[index] - pPredicted).abs();
      final sResidual = (observedSeconds[index] - sPredicted).abs();
      final bestResidual = math.min(pResidual, sResidual);
      final weight =
          (math.max(25.0, firstDistanceKm) / math.max(25.0, distances[index]))
              .clamp(0.25, 2.0);
      final cappedResidual = math.min(8.0, bestResidual);
      phaseScore += weight * cappedResidual * cappedResidual;
      residualSum += bestResidual;
      weightSum += weight;
      residuals.add(bestResidual);
      if (bestResidual > residualToleranceSeconds) {
        otherCount += 1;
        phaseScore += weight * 3.5;
      } else if (pResidual <= sResidual) {
        pCount += 1;
        acceptedObserved.add(observedSeconds[index]);
        acceptedPredicted.add(pPredicted);
      } else {
        sCount += 1;
        acceptedObserved.add(observedSeconds[index]);
        acceptedPredicted.add(sPredicted);
      }
    }

    final pair = _hypPairResidual(
      acceptedObserved,
      acceptedPredicted,
      maxPairs: 80,
    );
    final unarrivedPenalty = _hypUnarrivedPenalty(
      unarrived,
      earliestObserved: earliestObserved,
      observedAt: observedAt,
      latitude: latitude,
      longitude: longitude,
      depthKm: depthKm,
      originOffsetSeconds: originOffset,
      pWaveSpeedKmPerSec: pWaveSpeedKmPerSec,
      useJma2001TravelTime: useJma2001TravelTime,
    );
    final depthRegularization = depthKm * depthRegularizationWeight;
    final sSupportBonus = math.min(
      maxSSupportBonus,
      sCount * sSupportBonusPerStation,
    );
    final score =
        phaseScore +
        pair.score * 0.75 +
        unarrivedPenalty.penalty * unarrivedPenaltyScoreWeight +
        depthRegularization -
        sSupportBonus;
    if (score < best.score) {
      best = _HypCandidate(
        latitude: latitude,
        longitude: longitude,
        depthKm: depthKm,
        originOffsetSeconds: originOffset,
        score: score,
        phaseScore: phaseScore,
        phaseMeanResidualSeconds: residuals.isEmpty
            ? 0
            : residualSum / residuals.length,
        phaseResidualP90Seconds: _percentile(residuals, 0.90),
        phasePCount: pCount,
        phaseSCount: sCount,
        phaseOtherCount: otherCount,
        pairScore: pair.score,
        pairMeanResidualSeconds: pair.meanResidualSeconds,
        pairCount: pair.count,
        unarrivedPenalty: unarrivedPenalty.penalty,
        unarrivedPenaltyCount: unarrivedPenalty.count,
        phaseBalancePenalty: 0,
        weightedCount: weightSum,
      );
    }
  }
  return best;
}

_HypCandidate _scoreHypCandidateJqStyle(
  List<SeismicStationEventRecord> unarrived, {
  required DateTime earliestObserved,
  required DateTime observedAt,
  required double latitude,
  required double longitude,
  required double depthKm,
  required double originSeedSeconds,
  required List<double> observedSeconds,
  required List<double> pTravelSeconds,
  required List<double> sTravelSeconds,
  required List<double> distances,
  required double unarrivedPenaltyScoreWeight,
  required double depthRegularizationWeight,
  required bool useJma2001TravelTime,
}) {
  const pWaveSpeedKmPerSec = 6.0;
  const residualToleranceSeconds = 2.8;
  final sPhaseGateOpen =
      observedAt.difference(earliestObserved).inMilliseconds / 1000.0 > 15.0;

  var originOffset = originSeedSeconds;
  var phaseIndexes = List<int>.filled(observedSeconds.length, 0);

  for (var iteration = 0; iteration < 2; iteration++) {
    final originSamples = <double>[];
    final originWeights = <double>[];
    final nextPhaseIndexes = List<int>.filled(observedSeconds.length, 0);
    final firstDistanceKm = distances.reduce(math.min);

    for (var index = 0; index < observedSeconds.length; index++) {
      final pResidual =
          (observedSeconds[index] - (originOffset + pTravelSeconds[index]))
              .abs();
      final sResidual =
          (observedSeconds[index] - (originOffset + sTravelSeconds[index]))
              .abs();
      final useS = sPhaseGateOpen && sResidual < pResidual;
      final bestResidual = useS ? sResidual : pResidual;
      nextPhaseIndexes[index] = useS ? 1 : 0;
      if (bestResidual > residualToleranceSeconds) continue;
      final travelSeconds = useS
          ? sTravelSeconds[index]
          : pTravelSeconds[index];
      final weight =
          (math.max(25.0, firstDistanceKm) / math.max(25.0, distances[index]))
              .clamp(0.25, 2.0);
      originSamples.add(observedSeconds[index] - travelSeconds);
      originWeights.add(weight);
    }

    if (originSamples.isEmpty) {
      for (var index = 0; index < observedSeconds.length; index++) {
        final pOrigin = observedSeconds[index] - pTravelSeconds[index];
        final sOrigin = observedSeconds[index] - sTravelSeconds[index];
        final chooseS =
            sPhaseGateOpen &&
            (originOffset - sOrigin).abs() < (originOffset - pOrigin).abs();
        originSamples.add(chooseS ? sOrigin : pOrigin);
        originWeights.add(1.0);
        nextPhaseIndexes[index] = chooseS ? 1 : 0;
      }
    }

    originOffset = _weightedMean(originSamples, originWeights);
    phaseIndexes = nextPhaseIndexes;
  }

  final residuals = <double>[];
  final acceptedObserved = <double>[];
  final acceptedPredicted = <double>[];
  final firstDistanceKm = distances.reduce(math.min);
  var weightedResidualSquares = 0.0;
  var residualSum = 0.0;
  var weightSum = 0.0;
  var pCount = 0;
  var sCount = 0;
  var otherCount = 0;
  final pOriginSamples = <double>[];
  final sOriginSamples = <double>[];
  final pOriginWeights = <double>[];
  final sOriginWeights = <double>[];

  for (var index = 0; index < observedSeconds.length; index++) {
    final travelSeconds = phaseIndexes[index] == 1
        ? sTravelSeconds[index]
        : pTravelSeconds[index];
    final predicted = originOffset + travelSeconds;
    final residual = (observedSeconds[index] - predicted).abs();
    final weight =
        (math.max(25.0, firstDistanceKm) / math.max(25.0, distances[index]))
            .clamp(0.25, 2.0);
    residuals.add(residual);
    residualSum += residual;
    weightSum += weight;
    weightedResidualSquares += weight * residual * residual;
    if (residual > residualToleranceSeconds) {
      otherCount += 1;
      continue;
    }
    acceptedObserved.add(observedSeconds[index]);
    acceptedPredicted.add(predicted);
    if (phaseIndexes[index] == 1) {
      sCount += 1;
      sOriginSamples.add(observedSeconds[index] - sTravelSeconds[index]);
      sOriginWeights.add(weight);
    } else {
      pCount += 1;
      pOriginSamples.add(observedSeconds[index] - pTravelSeconds[index]);
      pOriginWeights.add(weight);
    }
  }

  final acceptedCount = pCount + sCount;
  final weightedVariance = weightSum == 0
      ? double.infinity
      : weightedResidualSquares / weightSum;
  final sSupportMultiplier = sCount == 0
      ? 1.8
      : sCount == 1
      ? 1.35
      : sCount == 2
      ? 1.15
      : math.max(0.82, 1.0 - (sCount - 3) * 0.03);
  final sampleSizePenalty =
      1.0 + math.max(0, 6 - acceptedCount) * 0.15 + otherCount * 0.08;
  final phaseScore =
      weightedVariance *
          math.max(1.0, weightSum) *
          sSupportMultiplier *
          sampleSizePenalty +
      otherCount * 2.5;
  final pair = _hypPairResidual(
    acceptedObserved,
    acceptedPredicted,
    maxPairs: 80,
  );
  final unarrivedPenalty = _hypUnarrivedPenalty(
    unarrived,
    earliestObserved: earliestObserved,
    observedAt: observedAt,
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originOffsetSeconds: originOffset,
    pWaveSpeedKmPerSec: pWaveSpeedKmPerSec,
    useJma2001TravelTime: useJma2001TravelTime,
    countLike: true,
  );
  final phaseBalancePenalty = _jqStylePhaseBalancePenalty(
    pCount: pCount,
    sCount: sCount,
    otherCount: otherCount,
    observedCount: observedSeconds.length,
  );
  final phaseOrigin = _jqStylePhaseOriginDiagnostics(
    pOriginSamples: pOriginSamples,
    pOriginWeights: pOriginWeights,
    sOriginSamples: sOriginSamples,
    sOriginWeights: sOriginWeights,
  );
  final score =
      phaseScore +
      pair.score * 0.25 +
      unarrivedPenalty.penalty * unarrivedPenaltyScoreWeight * 4.0 +
      depthKm * depthRegularizationWeight;

  return _HypCandidate(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    originOffsetSeconds: originOffset,
    score: score,
    phaseScore: phaseScore,
    phaseMeanResidualSeconds: residuals.isEmpty
        ? 0
        : residualSum / residuals.length,
    phaseResidualP90Seconds: _percentile(residuals, 0.90),
    phasePCount: pCount,
    phaseSCount: sCount,
    phaseOtherCount: otherCount,
    pairScore: pair.score,
    pairMeanResidualSeconds: pair.meanResidualSeconds,
    pairCount: pair.count,
    unarrivedPenalty: unarrivedPenalty.penalty,
    unarrivedPenaltyCount: unarrivedPenalty.count,
    phaseBalancePenalty: phaseBalancePenalty,
    weightedCount: weightSum,
    pOriginClusterCount: phaseOrigin.pClusterCount,
    sOriginClusterCount: phaseOrigin.sClusterCount,
    pOriginMeanSeconds: phaseOrigin.pMeanSeconds,
    sOriginMeanSeconds: phaseOrigin.sMeanSeconds,
    pOriginSpreadSeconds: phaseOrigin.pSpreadSeconds,
    sOriginSpreadSeconds: phaseOrigin.sSpreadSeconds,
    phaseOriginMeanGapSeconds: phaseOrigin.meanGapSeconds,
  );
}

({
  int pClusterCount,
  int sClusterCount,
  double? pMeanSeconds,
  double? sMeanSeconds,
  double? pSpreadSeconds,
  double? sSpreadSeconds,
  double? meanGapSeconds,
})
_jqStylePhaseOriginDiagnostics({
  required List<double> pOriginSamples,
  required List<double> pOriginWeights,
  required List<double> sOriginSamples,
  required List<double> sOriginWeights,
}) {
  final pMean = pOriginSamples.isEmpty
      ? null
      : _weightedMean(pOriginSamples, pOriginWeights);
  final sMean = sOriginSamples.isEmpty
      ? null
      : _weightedMean(sOriginSamples, sOriginWeights);
  return (
    pClusterCount: _originClusterCount(pOriginSamples),
    sClusterCount: _originClusterCount(sOriginSamples),
    pMeanSeconds: pMean,
    sMeanSeconds: sMean,
    pSpreadSeconds: _originSpreadSeconds(pOriginSamples),
    sSpreadSeconds: _originSpreadSeconds(sOriginSamples),
    meanGapSeconds: pMean == null || sMean == null
        ? null
        : (sMean - pMean).abs(),
  );
}

int _originClusterCount(List<double> samples) {
  if (samples.isEmpty) return 0;
  final sorted = [...samples]..sort();
  var clusters = 1;
  var clusterStart = sorted.first;
  for (final sample in sorted.skip(1)) {
    if (sample - clusterStart > 1.5) {
      clusters += 1;
      clusterStart = sample;
    }
  }
  return clusters;
}

double? _originSpreadSeconds(List<double> samples) {
  if (samples.length < 2) return null;
  return _percentile(samples, 0.90) - _percentile(samples, 0.10);
}

double _jqStylePhaseBalancePenalty({
  required int pCount,
  required int sCount,
  required int otherCount,
  required int observedCount,
}) {
  final acceptedCount = pCount + sCount;
  if (acceptedCount == 0) return 120.0 + otherCount * 5.0;
  var penalty = 0.0;
  if (pCount == 0) {
    penalty += 120.0;
  } else if (pCount == 1) {
    penalty += 50.0;
  } else if (pCount == 2) {
    penalty += 20.0;
  }
  if (sCount == 0) {
    penalty += 60.0;
  } else if (sCount == 1) {
    penalty += 25.0;
  }
  final pShare = pCount / acceptedCount;
  final sShare = sCount / acceptedCount;
  if (pShare < 0.15) penalty += (0.15 - pShare) * observedCount * 12.0;
  if (sShare < 0.15) penalty += (0.15 - sShare) * observedCount * 8.0;
  return penalty;
}

List<double> _hypOriginOffsetCandidates(
  List<double> observedSeconds,
  List<double> pTravelSeconds,
  List<double> sTravelSeconds,
) {
  final pOffsets = <double>[];
  final sOffsets = <double>[];
  for (var index = 0; index < observedSeconds.length; index++) {
    pOffsets.add(observedSeconds[index] - pTravelSeconds[index]);
    sOffsets.add(observedSeconds[index] - sTravelSeconds[index]);
  }
  final combined = [...pOffsets, ...sOffsets]..sort();
  final candidates = <double>[
    _median(pOffsets),
    _median(sOffsets),
    _percentile(combined, 0.10),
    _percentile(combined, 0.25),
    _percentile(combined, 0.50),
    _percentile(combined, 0.75),
    _percentile(combined, 0.90),
  ];
  if (combined.length <= 36) {
    candidates.addAll(combined);
  } else {
    final step = math.max(1, (combined.length / 12).floor());
    for (var index = 0; index < combined.length; index += step) {
      candidates.add(combined[index]);
    }
  }
  candidates.sort();
  final unique = <double>[];
  for (final value in candidates) {
    if (unique.isEmpty || (value - unique.last).abs() > 0.05) {
      unique.add(value);
    }
  }
  return unique.isEmpty ? const [0.0] : unique;
}

({double score, double meanResidualSeconds, int count}) _hypPairResidual(
  List<double> observedSeconds,
  List<double> predictedSeconds, {
  required int maxPairs,
}) {
  if (observedSeconds.length < 2) {
    return (score: 0.0, meanResidualSeconds: 0.0, count: 0);
  }
  var score = 0.0;
  var sum = 0.0;
  var count = 0;
  for (var left = 0; left < observedSeconds.length; left++) {
    for (var right = left + 1; right < observedSeconds.length; right++) {
      final observedDelta = observedSeconds[left] - observedSeconds[right];
      final predictedDelta = predictedSeconds[left] - predictedSeconds[right];
      final residual = (observedDelta - predictedDelta).abs();
      final capped = math.min(6.0, residual);
      score += capped * capped;
      sum += residual;
      count += 1;
      if (count >= maxPairs) {
        return (
          score: score / count * observedSeconds.length,
          meanResidualSeconds: sum / count,
          count: count,
        );
      }
    }
  }
  return (
    score: count == 0 ? 0.0 : score / count * observedSeconds.length,
    meanResidualSeconds: count == 0 ? 0.0 : sum / count,
    count: count,
  );
}

({double penalty, int count}) _hypUnarrivedPenalty(
  List<SeismicStationEventRecord> unarrived, {
  required DateTime earliestObserved,
  required DateTime observedAt,
  required double latitude,
  required double longitude,
  required double depthKm,
  required double originOffsetSeconds,
  required double pWaveSpeedKmPerSec,
  required bool useJma2001TravelTime,
  bool countLike = false,
}) {
  if (unarrived.isEmpty) return (penalty: 0.0, count: 0);
  final elapsedSeconds =
      observedAt.difference(earliestObserved).inMilliseconds / 1000.0;
  var penalty = 0.0;
  var count = 0;
  for (final record in unarrived) {
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final pTravelSeconds = useJma2001TravelTime
        ? Jma2001TravelTimeApproximation.travelTimeSeconds(
            hypocentralDistanceKm: hypocentralDistanceKm,
            depthKm: depthKm,
            pWave: true,
          )
        : hypocentralDistanceKm / pWaveSpeedKmPerSec;
    final predictedP = originOffsetSeconds + pTravelSeconds;
    final overdueSeconds = elapsedSeconds - predictedP - 2.0;
    if (overdueSeconds <= 0) continue;
    count += 1;
    penalty += countLike ? 1.0 : math.min(2.0, overdueSeconds * 0.12);
  }
  return (penalty: penalty, count: count);
}

List<SeismicStationEventRecord> _hypUnarrivedRecords(
  SourceEstimationRequest request,
  List<SeismicStationEventRecord> usable, {
  required int limit,
}) {
  final usableCodes = {for (final record in usable) record.descriptor.code};
  final center = _weightedCenter(usable);
  final candidates = request.stations
      .where((record) {
        return request.sensorSelection.accepts(record.descriptor) &&
            !usableCodes.contains(record.descriptor.code) &&
            !record.isActiveLike;
      })
      .toList(growable: false);
  candidates.sort((a, b) {
    final da = _haversineKm(
      center.$1,
      center.$2,
      a.descriptor.coordinate.latitude,
      a.descriptor.coordinate.longitude,
    );
    final db = _haversineKm(
      center.$1,
      center.$2,
      b.descriptor.coordinate.latitude,
      b.descriptor.coordinate.longitude,
    );
    final cmp = da.compareTo(db);
    if (cmp != 0) return cmp;
    return a.descriptor.code.compareTo(b.descriptor.code);
  });
  return candidates.take(limit).toList(growable: false);
}

_GroupedPhaseLineFit _groupedPhaseLineFitAtDepth(
  List<double> observedSeconds,
  List<double> distancesKm, {
  required double depthKm,
}) {
  const pWaveSpeedKmPerSec = 6.0;
  const sWaveSpeedKmPerSec = 3.5;
  const residualToleranceSeconds = 2.8;
  final pTravelSeconds = <double>[];
  final sTravelSeconds = <double>[];
  for (final distanceKm in distancesKm) {
    final hypocentralDistanceKm = math.sqrt(
      distanceKm * distanceKm + depthKm * depthKm,
    );
    pTravelSeconds.add(hypocentralDistanceKm / pWaveSpeedKmPerSec);
    sTravelSeconds.add(hypocentralDistanceKm / sWaveSpeedKmPerSec);
  }

  final pOffset = _median([
    for (var index = 0; index < observedSeconds.length; index++)
      observedSeconds[index] - pTravelSeconds[index],
  ]);
  final sOffset = _median([
    for (var index = 0; index < observedSeconds.length; index++)
      observedSeconds[index] - sTravelSeconds[index],
  ]);

  final pResiduals = <double>[];
  final sResiduals = <double>[];
  var score = 0.0;
  var residualSum = 0.0;
  var pCount = 0;
  var sCount = 0;
  var otherCount = 0;
  for (var index = 0; index < observedSeconds.length; index++) {
    final pResidual =
        (observedSeconds[index] - (pTravelSeconds[index] + pOffset)).abs();
    final sResidual =
        (observedSeconds[index] - (sTravelSeconds[index] + sOffset)).abs();
    pResiduals.add(pResidual);
    sResiduals.add(sResidual);

    final bestResidual = math.min(pResidual, sResidual);
    residualSum += bestResidual;
    score += bestResidual * bestResidual;
    if (bestResidual > residualToleranceSeconds) {
      otherCount += 1;
    } else if (pResidual <= sResidual) {
      pCount += 1;
    } else {
      sCount += 1;
    }
  }

  final count = observedSeconds.length;
  final depthSupported =
      pCount >= 3 &&
      sCount >= 3 &&
      otherCount <= math.max(1, (count * 0.35).round()) &&
      (count == 0 ? 0 : residualSum / count) <= 2.2;
  return _GroupedPhaseLineFit(
    depthKm: depthKm,
    score: score,
    pCount: pCount,
    sCount: sCount,
    otherCount: otherCount,
    meanResidualSeconds: count == 0 ? 0 : residualSum / count,
    depthSupported: depthSupported,
    pOnlyMeanResidualSeconds: _mean(pResiduals),
    pOnlyResidualP90Seconds: _percentile(pResiduals, 0.90),
    pOnlyBestDepthKm: depthKm,
    pOnlyDepthMeanResidualSeconds: _mean(pResiduals),
    pOnlyDepthSupported: false,
    sOnlyMeanResidualSeconds: _mean(sResiduals),
    sOnlyResidualP90Seconds: _percentile(sResiduals, 0.90),
  );
}

_PhaseDifferenceFit _phaseDifferenceFitScore(
  List<double> observedSeconds,
  List<double> predictedSeconds,
  List<int> acceptedPhaseIndexes,
) {
  if (acceptedPhaseIndexes.length < 2) {
    return const _PhaseDifferenceFit(
      score: 0,
      pairCount: 0,
      meanResidualSeconds: 0,
    );
  }

  var score = 0.0;
  var residualSum = 0.0;
  var pairCount = 0;
  for (
    var leftIndex = 0;
    leftIndex < acceptedPhaseIndexes.length;
    leftIndex++
  ) {
    final i = acceptedPhaseIndexes[leftIndex];
    for (
      var rightIndex = leftIndex + 1;
      rightIndex < acceptedPhaseIndexes.length;
      rightIndex++
    ) {
      final j = acceptedPhaseIndexes[rightIndex];
      final observedDelta = observedSeconds[i] - observedSeconds[j];
      final predictedDelta = predictedSeconds[i] - predictedSeconds[j];
      final residual = (observedDelta - predictedDelta).abs();
      final cappedResidual = math.min(6.0, residual);
      score += cappedResidual * cappedResidual;
      residualSum += residual;
      pairCount += 1;
    }
  }

  final meanResidual = pairCount == 0 ? 0.0 : residualSum / pairCount;
  return _PhaseDifferenceFit(
    score: pairCount == 0 ? 0 : score / pairCount * acceptedPhaseIndexes.length,
    pairCount: pairCount,
    meanResidualSeconds: meanResidual,
  );
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

double _weightedMean(List<double> values, List<double> weights) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  var weightSum = 0.0;
  for (var index = 0; index < values.length; index++) {
    final weight = index < weights.length ? weights[index] : 1.0;
    sum += values[index] * weight;
    weightSum += weight;
  }
  return weightSum == 0 ? _mean(values) : sum / weightSum;
}

double _median(List<double> values) => _percentile(values, 0.50);

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  final position = (sorted.length - 1) * percentile.clamp(0.0, 1.0);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = position - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}

double _rankScore(List<double> distances, List<double> values) {
  double rankScore = 0;
  for (var i = 0; i < values.length; i++) {
    for (var j = i + 1; j < values.length; j++) {
      final valueDiff = values[i] - values[j];
      if (valueDiff.abs() < 0.15) continue;
      final distDiff = distances[i] - distances[j];
      if (valueDiff > 0 && distDiff > 0) {
        rankScore += math.min(2.0, valueDiff.abs()) * 0.35;
      } else if (valueDiff < 0 && distDiff < 0) {
        rankScore += math.min(2.0, valueDiff.abs()) * 0.35;
      }
    }
  }
  return rankScore;
}

double _nearestStrongPenalty(List<double> distances, List<double> values) {
  var strongestIndex = 0;
  var strongestValue = values.first;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > strongestValue) {
      strongestValue = values[i];
      strongestIndex = i;
    }
  }
  final nearestDistance = distances.reduce(math.min);
  final strongestDistance = distances[strongestIndex];
  return math.max(0, strongestDistance - nearestDistance) * 0.08;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

// NiedHypoInf.js uses this geodesic radius in its candidate scorer. Keep this
// isolated from the application's existing distance model.
double _kanameishiHaversineKm(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadiusKm = 6371.0088;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * math.pi / 180.0;

double _kotoho7ScratchDistanceKm(
  double lon1,
  double lat1,
  double lon2,
  double lat2,
) {
  final lat1Rad = _degToRad(lat1);
  final lat2Rad = _degToRad(lat2);
  final lonDeltaRad = _degToRad(lon1 - lon2);
  final cosine =
      math.sin(lat1Rad) * math.sin(lat2Rad) +
      math.cos(lat1Rad) * math.cos(lat2Rad) * math.cos(lonDeltaRad);
  return 111.31949 * _radToDeg(math.acos(cosine.clamp(-1.0, 1.0)));
}

double _radToDeg(double rad) => rad * 180.0 / math.pi;

int _kotoho7ScratchGridNumberFromCoordinate({
  required double latitude,
  required double longitude,
}) {
  return ((latitude.floor() - 23) * 23) + (longitude.floor() - 122);
}

Map<int, List<int>> _buildKotoho7ScratchStationIndicesByGridNumber() {
  final byGrid = <int, List<int>>{};
  for (
    var stationIndex = 0;
    stationIndex < _kotoho7ScratchStationCount;
    stationIndex++
  ) {
    final station = NiedStationDb.stations[stationIndex];
    final gridNumber = _kotoho7ScratchGridNumberFromCoordinate(
      latitude: (station['lat'] as num).toDouble(),
      longitude: (station['lng'] as num).toDouble(),
    );
    // Scratch initializes grid state for `1..530` and then builds
    // `dc grid連番:点がある番号` from grid numbers contained in
    // `dc ten:点からグリッド番号`.
    if (gridNumber < 1 || gridNumber > 530) continue;
    final stationIndices = byGrid.putIfAbsent(gridNumber, () => <int>[]);
    stationIndices.add(stationIndex + 1);
  }
  return Map<int, List<int>>.unmodifiable(
    byGrid.map((gridNumber, stationIndices) {
      return MapEntry(gridNumber, List<int>.unmodifiable(stationIndices));
    }),
  );
}

List<List<int>> _buildKotoho7ScratchGridStationIndicesBySerialIndex() {
  final itemNumberByGrid = <int, int>{
    for (
      var index = 0;
      index < _kotoho7ScratchPopulatedGridNumbers.length;
      index++
    )
      _kotoho7ScratchPopulatedGridNumbers[index]: index + 1,
  };
  final flatSlots = List<int?>.filled(
    _kotoho7ScratchPopulatedGridNumbers.length * 70,
    null,
  );
  for (
    var stationIndex = 0;
    stationIndex < _kotoho7ScratchStationCount;
    stationIndex++
  ) {
    final station = NiedStationDb.stations[stationIndex];
    final gridNumber = _kotoho7ScratchGridNumberFromCoordinate(
      latitude: (station['lat'] as num).toDouble(),
      longitude: (station['lng'] as num).toDouble(),
    );
    final itemNumber = itemNumberByGrid[gridNumber];
    if (itemNumber == null) continue;
    var slotIndex = 70 * (itemNumber - 1);
    while (slotIndex < flatSlots.length && flatSlots[slotIndex] != null) {
      slotIndex += 1;
    }
    if (slotIndex < flatSlots.length) {
      flatSlots[slotIndex] = stationIndex + 1;
    }
  }

  final bySerial = <List<int>>[];
  for (
    var serialIndex = 0;
    serialIndex < _kotoho7ScratchPopulatedGridNumbers.length;
    serialIndex++
  ) {
    final start = serialIndex * 70;
    final stationIndices = <int>[];
    for (var offset = 0; offset < 70; offset++) {
      final stationIndex = flatSlots[start + offset];
      if (stationIndex != null) stationIndices.add(stationIndex);
    }
    bySerial.add(List<int>.unmodifiable(stationIndices));
  }
  return List<List<int>>.unmodifiable(bySerial);
}

List<List<({double distanceKm, int stationIndex})>>
_buildKotoho7GeneratedNearest7() {
  final result = <List<({double distanceKm, int stationIndex})>>[];
  for (
    var centerIndex = 0;
    centerIndex < _kotoho7ScratchStationCount;
    centerIndex++
  ) {
    final center = NiedStationDb.stations[centerIndex];
    final centerLon = (center['lng'] as num).toDouble();
    final centerLat = (center['lat'] as num).toDouble();
    final nearest = <({double distanceKm, int stationIndex})>[];
    for (
      var candidateIndex = 0;
      candidateIndex < _kotoho7ScratchStationCount;
      candidateIndex++
    ) {
      if (candidateIndex == centerIndex) continue;
      final candidate = NiedStationDb.stations[candidateIndex];
      final distanceKm = _kotoho7ScratchDistanceKm(
        centerLon,
        centerLat,
        (candidate['lng'] as num).toDouble(),
        (candidate['lat'] as num).toDouble(),
      );
      nearest.add((distanceKm: distanceKm, stationIndex: candidateIndex + 1));
    }
    nearest.sort((left, right) {
      final distanceCompare = left.distanceKm.compareTo(right.distanceKm);
      if (distanceCompare != 0) return distanceCompare;
      return left.stationIndex.compareTo(right.stationIndex);
    });
    result.add(List.unmodifiable(nearest.take(7)));
  }
  return List.unmodifiable(result);
}

double _log10(double value) => math.log(value) / math.ln10;

class _Candidate {
  final double latitude;
  final double longitude;
  final double score;
  final double timeScore;
  final double phaseLineScore;
  final double groupedPhaseLineScore;
  final double groupedPhaseLineMeanResidualSeconds;
  final double groupedPhaseBestDepthKm;
  final double groupedPhaseDepthMeanResidualSeconds;
  final bool groupedPhaseDepthSupported;
  final int groupedPhaseLinePCount;
  final int groupedPhaseLineSCount;
  final int groupedPhaseLineOtherCount;
  final double pOnlyLineMeanResidualSeconds;
  final double pOnlyLineResidualP90Seconds;
  final double pOnlyBestDepthKm;
  final double pOnlyDepthMeanResidualSeconds;
  final bool pOnlyDepthSupported;
  final double sOnlyLineMeanResidualSeconds;
  final double sOnlyLineResidualP90Seconds;
  final double phaseDifferenceScore;
  final int phaseDifferencePairCount;
  final double phaseDifferenceMeanResidualSeconds;
  final int phaseLinePCount;
  final int phaseLineSCount;
  final int phaseLineOtherCount;
  final double phaseLineMeanResidualSeconds;
  final bool oneSidedScoreMode;
  final double rankScore;
  final double geometryPenalty;
  final double referenceDistanceKm;

  const _Candidate({
    required this.latitude,
    required this.longitude,
    required this.score,
    this.timeScore = double.infinity,
    this.phaseLineScore = double.infinity,
    this.groupedPhaseLineScore = double.infinity,
    this.groupedPhaseLineMeanResidualSeconds = double.infinity,
    this.groupedPhaseBestDepthKm = 0,
    this.groupedPhaseDepthMeanResidualSeconds = double.infinity,
    this.groupedPhaseDepthSupported = false,
    this.groupedPhaseLinePCount = 0,
    this.groupedPhaseLineSCount = 0,
    this.groupedPhaseLineOtherCount = 0,
    this.pOnlyLineMeanResidualSeconds = double.infinity,
    this.pOnlyLineResidualP90Seconds = double.infinity,
    this.pOnlyBestDepthKm = 0,
    this.pOnlyDepthMeanResidualSeconds = double.infinity,
    this.pOnlyDepthSupported = false,
    this.sOnlyLineMeanResidualSeconds = double.infinity,
    this.sOnlyLineResidualP90Seconds = double.infinity,
    this.phaseDifferenceScore = double.infinity,
    this.phaseDifferencePairCount = 0,
    this.phaseDifferenceMeanResidualSeconds = double.infinity,
    this.phaseLinePCount = 0,
    this.phaseLineSCount = 0,
    this.phaseLineOtherCount = 0,
    this.phaseLineMeanResidualSeconds = double.infinity,
    this.oneSidedScoreMode = false,
    this.rankScore = double.infinity,
    this.geometryPenalty = 0,
    this.referenceDistanceKm = 0,
  });
}

class _PhaseLineFit {
  final double score;
  final int pCount;
  final int sCount;
  final int otherCount;
  final double meanResidualSeconds;
  final List<double> predictedSeconds;
  final List<int> acceptedPhaseIndexes;

  const _PhaseLineFit({
    required this.score,
    required this.pCount,
    required this.sCount,
    required this.otherCount,
    required this.meanResidualSeconds,
    required this.predictedSeconds,
    required this.acceptedPhaseIndexes,
  });
}

class _GroupedPhaseLineFit {
  final double depthKm;
  final double score;
  final int pCount;
  final int sCount;
  final int otherCount;
  final double meanResidualSeconds;
  final bool depthSupported;
  final double pOnlyMeanResidualSeconds;
  final double pOnlyResidualP90Seconds;
  final double pOnlyBestDepthKm;
  final double pOnlyDepthMeanResidualSeconds;
  final bool pOnlyDepthSupported;
  final double sOnlyMeanResidualSeconds;
  final double sOnlyResidualP90Seconds;

  const _GroupedPhaseLineFit({
    required this.depthKm,
    required this.score,
    required this.pCount,
    required this.sCount,
    required this.otherCount,
    required this.meanResidualSeconds,
    required this.depthSupported,
    required this.pOnlyMeanResidualSeconds,
    required this.pOnlyResidualP90Seconds,
    required this.pOnlyBestDepthKm,
    required this.pOnlyDepthMeanResidualSeconds,
    required this.pOnlyDepthSupported,
    required this.sOnlyMeanResidualSeconds,
    required this.sOnlyResidualP90Seconds,
  });

  _GroupedPhaseLineFit copyWith({
    double? pOnlyBestDepthKm,
    double? pOnlyDepthMeanResidualSeconds,
    bool? pOnlyDepthSupported,
  }) {
    return _GroupedPhaseLineFit(
      depthKm: depthKm,
      score: score,
      pCount: pCount,
      sCount: sCount,
      otherCount: otherCount,
      meanResidualSeconds: meanResidualSeconds,
      depthSupported: depthSupported,
      pOnlyMeanResidualSeconds: pOnlyMeanResidualSeconds,
      pOnlyResidualP90Seconds: pOnlyResidualP90Seconds,
      pOnlyBestDepthKm: pOnlyBestDepthKm ?? this.pOnlyBestDepthKm,
      pOnlyDepthMeanResidualSeconds:
          pOnlyDepthMeanResidualSeconds ?? this.pOnlyDepthMeanResidualSeconds,
      pOnlyDepthSupported: pOnlyDepthSupported ?? this.pOnlyDepthSupported,
      sOnlyMeanResidualSeconds: sOnlyMeanResidualSeconds,
      sOnlyResidualP90Seconds: sOnlyResidualP90Seconds,
    );
  }
}

class _PhaseDifferenceFit {
  final double score;
  final int pairCount;
  final double meanResidualSeconds;

  const _PhaseDifferenceFit({
    required this.score,
    required this.pairCount,
    required this.meanResidualSeconds,
  });
}

class _HypCandidate {
  final double latitude;
  final double longitude;
  final double depthKm;
  final double originOffsetSeconds;
  final double score;
  final double phaseScore;
  final double phaseMeanResidualSeconds;
  final double phaseResidualP90Seconds;
  final int phasePCount;
  final int phaseSCount;
  final int phaseOtherCount;
  final double pairScore;
  final double pairMeanResidualSeconds;
  final int pairCount;
  final double unarrivedPenalty;
  final int unarrivedPenaltyCount;
  final double phaseBalancePenalty;
  final double weightedCount;
  final double? scratchSFactor;
  final int? scratchSFlagCount;
  final double? scratchWeightedResidualSquares;
  final double? scratchWeightSum;
  final double? scratchStationCountScale;
  final bool? scratchUnarrivedGateOpen;
  final int? scratchUnarrivedInputCount;
  final int? scratchUnarrivedWithinRadiusCount;
  final double? scratchDistanceFromFirstDetectedKm;
  final double? scratchMaxAllowedDepthKm;
  final double? scratchMaxAllowedDistanceKm;
  final String? scratchRejectReason;
  final int? pOriginClusterCount;
  final int? sOriginClusterCount;
  final double? pOriginMeanSeconds;
  final double? sOriginMeanSeconds;
  final double? pOriginSpreadSeconds;
  final double? sOriginSpreadSeconds;
  final double? phaseOriginMeanGapSeconds;

  const _HypCandidate({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.originOffsetSeconds,
    required this.score,
    required this.phaseScore,
    required this.phaseMeanResidualSeconds,
    required this.phaseResidualP90Seconds,
    required this.phasePCount,
    required this.phaseSCount,
    required this.phaseOtherCount,
    required this.pairScore,
    required this.pairMeanResidualSeconds,
    required this.pairCount,
    required this.unarrivedPenalty,
    required this.unarrivedPenaltyCount,
    required this.phaseBalancePenalty,
    required this.weightedCount,
    this.scratchSFactor,
    this.scratchSFlagCount,
    this.scratchWeightedResidualSquares,
    this.scratchWeightSum,
    this.scratchStationCountScale,
    this.scratchUnarrivedGateOpen,
    this.scratchUnarrivedInputCount,
    this.scratchUnarrivedWithinRadiusCount,
    this.scratchDistanceFromFirstDetectedKm,
    this.scratchMaxAllowedDepthKm,
    this.scratchMaxAllowedDistanceKm,
    this.scratchRejectReason,
    this.pOriginClusterCount,
    this.sOriginClusterCount,
    this.pOriginMeanSeconds,
    this.sOriginMeanSeconds,
    this.pOriginSpreadSeconds,
    this.sOriginSpreadSeconds,
    this.phaseOriginMeanGapSeconds,
  });

  _HypCandidate copyWith({
    double? latitude,
    double? longitude,
    double? depthKm,
    double? originOffsetSeconds,
  }) {
    return _HypCandidate(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      depthKm: depthKm ?? this.depthKm,
      originOffsetSeconds: originOffsetSeconds ?? this.originOffsetSeconds,
      score: score,
      phaseScore: phaseScore,
      phaseMeanResidualSeconds: phaseMeanResidualSeconds,
      phaseResidualP90Seconds: phaseResidualP90Seconds,
      phasePCount: phasePCount,
      phaseSCount: phaseSCount,
      phaseOtherCount: phaseOtherCount,
      pairScore: pairScore,
      pairMeanResidualSeconds: pairMeanResidualSeconds,
      pairCount: pairCount,
      unarrivedPenalty: unarrivedPenalty,
      unarrivedPenaltyCount: unarrivedPenaltyCount,
      phaseBalancePenalty: phaseBalancePenalty,
      weightedCount: weightedCount,
      scratchSFactor: scratchSFactor,
      scratchSFlagCount: scratchSFlagCount,
      scratchWeightedResidualSquares: scratchWeightedResidualSquares,
      scratchWeightSum: scratchWeightSum,
      scratchStationCountScale: scratchStationCountScale,
      scratchUnarrivedGateOpen: scratchUnarrivedGateOpen,
      scratchUnarrivedInputCount: scratchUnarrivedInputCount,
      scratchUnarrivedWithinRadiusCount: scratchUnarrivedWithinRadiusCount,
      scratchDistanceFromFirstDetectedKm: scratchDistanceFromFirstDetectedKm,
      scratchMaxAllowedDepthKm: scratchMaxAllowedDepthKm,
      scratchMaxAllowedDistanceKm: scratchMaxAllowedDistanceKm,
      scratchRejectReason: scratchRejectReason,
      pOriginClusterCount: pOriginClusterCount,
      sOriginClusterCount: sOriginClusterCount,
      pOriginMeanSeconds: pOriginMeanSeconds,
      sOriginMeanSeconds: sOriginMeanSeconds,
      pOriginSpreadSeconds: pOriginSpreadSeconds,
      sOriginSpreadSeconds: sOriginSpreadSeconds,
      phaseOriginMeanGapSeconds: phaseOriginMeanGapSeconds,
    );
  }
}

class _Kotoho7DetectionAcceleration {
  final double score;
  final double threshold;
  final int timeAreaCount;
  final int closeTimeAreaCount;
  final int permittedCount;
  final int minimumPointCount;
  final int scratchThresholdDigit;
  final int scratchThresholdCode;
  final double thirdNearestDistanceKm;
  final int recentPermittedCount;
  final int highNeighborCount;
  final int risingNeighborCount;
  final int ngRejectedCount;
  final int contributionCount;
  final bool hasEnoughObservedPoints;
  final bool qualifiesNormalPermission;
  final String reason;

  const _Kotoho7DetectionAcceleration({
    required this.score,
    required this.threshold,
    required this.timeAreaCount,
    required this.closeTimeAreaCount,
    required this.permittedCount,
    required this.minimumPointCount,
    required this.scratchThresholdDigit,
    required this.scratchThresholdCode,
    required this.thirdNearestDistanceKm,
    required this.recentPermittedCount,
    required this.highNeighborCount,
    required this.risingNeighborCount,
    required this.ngRejectedCount,
    required this.contributionCount,
    required this.hasEnoughObservedPoints,
    required this.qualifiesNormalPermission,
    required this.reason,
  });
}

class _Kotoho7HypState {
  final DateTime earliestObserved;
  final DateTime initializedAt;
  DateTime lastUpdatedAt;
  String firstStationCode;
  double initialLatitude;
  double initialLongitude;
  final Set<String> sourceKeys;
  final Set<String> assignedStationCodes;
  final Map<String, DateTime> scratchStationFirstUseAt;
  final Map<String, DateTime> scratchStationLastUpdateAt;
  final Map<String, DateTime> scratchStationPendingCloudAt;
  final Map<String, int> scratchStationPermissionState;
  final Map<String, int> scratchDetectionPermissionState;
  final Map<String, DateTime> scratchDetectionTriggerAt;
  final Map<String, String> scratchDetectionPermissionReason;
  final Map<String, double> scratchDetectionAccelerationScore;
  final Map<String, int> scratchDetectionAccelerationTimeAreaCount;
  final Map<String, String> scratchDetectionAccelerationReason;
  final Map<String, double> scratchDetectionPermittedShindo;
  final Map<String, double> scratchStationMaxShindoValue;
  final Map<String, DateTime> scratchStationMaxShindoUpdatedAt;
  final Map<int, double> scratchGridDetectionMax;
  final Map<int, double> scratchGridDetectionMaxKeep;
  final Map<String, double> scratchStationPArrivalSeconds;
  final Map<String, double> scratchStationSArrivalSeconds;
  final Map<String, bool> scratchStationSFlag;
  final Map<String, double> scratchShadowStationPArrivalSeconds;
  final Map<String, double> scratchShadowStationSArrivalSeconds;
  final Map<String, bool> scratchShadowStationSFlag;
  final Map<String, double> scratchStationFirstDistanceKm;
  _HypCandidate sourceCache;
  int revision;
  String lastSourceSelectionModel;
  String? lastSourceSelectionSelectedKey;
  int lastSourceSelectionCandidateCount;
  int lastSourceSelectionFitCount;
  double? lastSourceSelectionMeanResidualSeconds;
  int lastSameSourceMergeCount;
  List<String> lastSameSourceMergeKeys;
  int lastSameSourceMergeAddedStationCount;
  DateTime scratch43FirstDetectionAt;
  DateTime scratch43LastDetectionAt;
  DateTime? scratch43LastSourceCacheUpdatedAt;
  int scratch43Serial;
  bool scratch43CreatedByMidFrameNewId;
  DateTime? scratch43SingleStationGraceUntil;
  bool scratch43Active;
  DateTime? scratch43InactiveAt;
  String? scratch43InactiveReason;
  DateTime? scratch43ExpireAt;
  double? scratch43LastExpireWindowSeconds;
  int scratch43LastGridPresenceCount;
  double? scratch43LastGridPresenceDisappearedAgeSeconds;
  double? scratch43LastMaxCurrentShindoIndex;
  double? scratch43PreviousMaxCurrentShindoIndex;
  int scratch43AssignedCount;
  double scratch43MaxFirstStationDistanceKm;
  double scratch43MaxSourceDistanceKm;
  double scratch43BestScore;
  double scratch43BestRawScore;
  double? scratch43BestPhaseMeanResidualSeconds;
  List<String>? scratch43BestSourceKeys;
  int lastAssignmentAddedCount;
  int lastAssignmentRejectedCount;
  int lastAssignmentRecoveryAddedCount;
  int lastAssignmentReriseRefreshCount;
  int lastAssignmentMidFrameNewIdCount;
  int lastAssignmentRemovedCount;
  int lastAssignmentImmediatePsRecomputeCount;
  int lastAssignmentImmediateDistanceUpdateCount;
  int lastAssignmentNegativeCountDelta;
  int lastAssignmentResetClearedPlus3Count;
  int lastAssignmentResetClearedPsCacheCount;
  int lastAssignmentResetClearedDistanceCount;
  int lastAssignmentWouldSwitchOtherIdCount;
  int lastDetectionPermissionPromotedCount;
  int lastDetectionPermissionDemotedCount;
  int lastDetectionPermissionRefreshedCount;
  List<String> lastAssignmentAddedStationCodes;
  List<String> lastAssignmentRejectedStationCodes;
  List<String> lastAssignmentRecoveryAddedStationCodes;
  List<String> lastAssignmentReriseRefreshStationCodes;
  List<String> lastAssignmentMidFrameNewIdStationCodes;
  List<String> lastAssignmentRemovedStationCodes;
  Map<String, int> lastAssignmentAddedSourceCounts;
  Map<String, int> lastAssignmentRejectedSourceCounts;
  Map<String, int> lastAssignmentCandidateReasonCounts;
  Map<String, int> lastAssignmentResetReasonCounts;
  Map<String, int> lastAssignmentWouldSwitchOtherIdSourceCounts;
  Map<String, int> lastAssignmentAcceptedSameIdReasonCounts;
  Map<String, int> lastDetectionPermissionReasonCounts;
  Map<String, int> lastEstimatedSlotWriteReasonCounts;
  List<Map<String, Object?>> lastAssignmentAddedSourceSamples;
  List<Map<String, Object?>> lastAssignmentWouldSwitchOtherIdSamples;
  List<Map<String, Object?>> lastAssignmentAcceptedSameIdSamples;
  List<Map<String, Object?>> lastEstimatedSlotWriteSamples;

  _Kotoho7HypState({
    required this.earliestObserved,
    required this.initializedAt,
    required this.lastUpdatedAt,
    required this.firstStationCode,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.sourceKeys,
    required this.assignedStationCodes,
    required this.sourceCache,
    this.scratch43Serial = 0,
    this.scratch43CreatedByMidFrameNewId = false,
    this.scratch43SingleStationGraceUntil,
    Map<String, DateTime>? scratchStationFirstUseAt,
    Map<String, DateTime>? scratchStationLastUpdateAt,
    Map<String, DateTime>? scratchStationPendingCloudAt,
    Map<String, int>? scratchStationPermissionState,
    Map<String, int>? scratchDetectionPermissionState,
    Map<String, DateTime>? scratchDetectionTriggerAt,
    Map<String, String>? scratchDetectionPermissionReason,
    Map<String, double>? scratchDetectionAccelerationScore,
    Map<String, int>? scratchDetectionAccelerationTimeAreaCount,
    Map<String, String>? scratchDetectionAccelerationReason,
    Map<String, double>? scratchDetectionPermittedShindo,
    Map<String, double>? scratchStationMaxShindoValue,
    Map<String, DateTime>? scratchStationMaxShindoUpdatedAt,
    Map<int, double>? scratchGridDetectionMax,
    Map<int, double>? scratchGridDetectionMaxKeep,
    Map<String, double>? scratchStationPArrivalSeconds,
    Map<String, double>? scratchStationSArrivalSeconds,
    Map<String, bool>? scratchStationSFlag,
    Map<String, double>? scratchShadowStationPArrivalSeconds,
    Map<String, double>? scratchShadowStationSArrivalSeconds,
    Map<String, bool>? scratchShadowStationSFlag,
    Map<String, double>? scratchStationFirstDistanceKm,
  }) : scratchStationFirstUseAt =
           scratchStationFirstUseAt ?? <String, DateTime>{},
       scratchStationLastUpdateAt =
           scratchStationLastUpdateAt ?? <String, DateTime>{},
       scratchStationPendingCloudAt =
           scratchStationPendingCloudAt ?? <String, DateTime>{},
       scratchStationPermissionState =
           scratchStationPermissionState ?? <String, int>{},
       scratchDetectionPermissionState =
           scratchDetectionPermissionState ?? <String, int>{},
       scratchDetectionTriggerAt =
           scratchDetectionTriggerAt ?? <String, DateTime>{},
       scratchDetectionPermissionReason =
           scratchDetectionPermissionReason ?? <String, String>{},
       scratchDetectionAccelerationScore =
           scratchDetectionAccelerationScore ?? <String, double>{},
       scratchDetectionAccelerationTimeAreaCount =
           scratchDetectionAccelerationTimeAreaCount ?? <String, int>{},
       scratchDetectionAccelerationReason =
           scratchDetectionAccelerationReason ?? <String, String>{},
       scratchDetectionPermittedShindo =
           scratchDetectionPermittedShindo ?? <String, double>{},
       scratchStationMaxShindoValue =
           scratchStationMaxShindoValue ?? <String, double>{},
       scratchStationMaxShindoUpdatedAt =
           scratchStationMaxShindoUpdatedAt ?? <String, DateTime>{},
       scratchGridDetectionMax = scratchGridDetectionMax ?? <int, double>{},
       scratchGridDetectionMaxKeep =
           scratchGridDetectionMaxKeep ?? <int, double>{},
       scratchStationPArrivalSeconds =
           scratchStationPArrivalSeconds ?? <String, double>{},
       scratchStationSArrivalSeconds =
           scratchStationSArrivalSeconds ?? <String, double>{},
       scratchStationSFlag = scratchStationSFlag ?? <String, bool>{},
       scratchShadowStationPArrivalSeconds =
           scratchShadowStationPArrivalSeconds ?? <String, double>{},
       scratchShadowStationSArrivalSeconds =
           scratchShadowStationSArrivalSeconds ?? <String, double>{},
       scratchShadowStationSFlag =
           scratchShadowStationSFlag ?? <String, bool>{},
       scratchStationFirstDistanceKm =
           scratchStationFirstDistanceKm ?? <String, double>{},
       revision = 0,
       lastSourceSelectionModel = 'uninitialized',
       lastSourceSelectionSelectedKey = null,
       lastSourceSelectionCandidateCount = 0,
       lastSourceSelectionFitCount = 0,
       lastSourceSelectionMeanResidualSeconds = null,
       lastSameSourceMergeCount = 0,
       lastSameSourceMergeKeys = const <String>[],
       lastSameSourceMergeAddedStationCount = 0,
       scratch43FirstDetectionAt = earliestObserved,
       scratch43LastDetectionAt = lastUpdatedAt,
       scratch43LastSourceCacheUpdatedAt = null,
       scratch43Active = true,
       scratch43InactiveAt = null,
       scratch43InactiveReason = null,
       scratch43ExpireAt = null,
       scratch43LastExpireWindowSeconds = null,
       scratch43LastGridPresenceCount = 0,
       scratch43LastGridPresenceDisappearedAgeSeconds = null,
       scratch43LastMaxCurrentShindoIndex = null,
       scratch43PreviousMaxCurrentShindoIndex = null,
       scratch43AssignedCount = assignedStationCodes.length,
       scratch43MaxFirstStationDistanceKm = 0,
       scratch43MaxSourceDistanceKm = 0.0,
       scratch43BestScore = double.infinity,
       scratch43BestRawScore = double.infinity,
       scratch43BestPhaseMeanResidualSeconds = null,
       scratch43BestSourceKeys = null,
       lastAssignmentAddedCount = 0,
       lastAssignmentRejectedCount = 0,
       lastAssignmentRecoveryAddedCount = 0,
       lastAssignmentReriseRefreshCount = 0,
       lastAssignmentMidFrameNewIdCount = 0,
       lastAssignmentRemovedCount = 0,
       lastAssignmentImmediatePsRecomputeCount = 0,
       lastAssignmentImmediateDistanceUpdateCount = 0,
       lastAssignmentNegativeCountDelta = 0,
       lastAssignmentResetClearedPlus3Count = 0,
       lastAssignmentResetClearedPsCacheCount = 0,
       lastAssignmentResetClearedDistanceCount = 0,
       lastAssignmentWouldSwitchOtherIdCount = 0,
       lastDetectionPermissionPromotedCount = 0,
       lastDetectionPermissionDemotedCount = 0,
       lastDetectionPermissionRefreshedCount = 0,
       lastAssignmentAddedStationCodes = const <String>[],
       lastAssignmentRejectedStationCodes = const <String>[],
       lastAssignmentRecoveryAddedStationCodes = const <String>[],
       lastAssignmentReriseRefreshStationCodes = const <String>[],
       lastAssignmentMidFrameNewIdStationCodes = const <String>[],
       lastAssignmentRemovedStationCodes = const <String>[],
       lastAssignmentAddedSourceCounts = const <String, int>{},
       lastAssignmentRejectedSourceCounts = const <String, int>{},
       lastAssignmentCandidateReasonCounts = const <String, int>{},
       lastAssignmentResetReasonCounts = const <String, int>{},
       lastAssignmentWouldSwitchOtherIdSourceCounts = const <String, int>{},
       lastAssignmentAcceptedSameIdReasonCounts = const <String, int>{},
       lastDetectionPermissionReasonCounts = const <String, int>{},
       lastEstimatedSlotWriteReasonCounts = const <String, int>{},
       lastAssignmentAddedSourceSamples = const <Map<String, Object?>>[],
       lastAssignmentWouldSwitchOtherIdSamples = const <Map<String, Object?>>[],
       lastAssignmentAcceptedSameIdSamples = const <Map<String, Object?>>[],
       lastEstimatedSlotWriteSamples = const <Map<String, Object?>>[];
}

class _Kotoho7StationResetResult {
  final String reason;
  final int negativeCountDelta;
  final bool clearedPlus3;
  final bool clearedPsCache;
  final bool clearedDistance;

  const _Kotoho7StationResetResult({
    required this.reason,
    required this.negativeCountDelta,
    required this.clearedPlus3,
    required this.clearedPsCache,
    required this.clearedDistance,
  });
}

class _Kotoho7SourceSelection {
  final String key;
  final _Kotoho7HypState state;
  final int fitCount;
  final int candidateCount;
  final double meanResidualSeconds;
  final double p90ResidualSeconds;

  const _Kotoho7SourceSelection({
    required this.key,
    required this.state,
    required this.fitCount,
    required this.candidateCount,
    required this.meanResidualSeconds,
    required this.p90ResidualSeconds,
  });
}

class _Kotoho7StationSourceSelection {
  final _Kotoho7HypState state;
  final String source;
  final double? residualSeconds;

  const _Kotoho7StationSourceSelection({
    required this.state,
    required this.source,
    required this.residualSeconds,
  });
}

class _Kotoho7GridCarrierEntry {
  final _Kotoho7HypState state;
  final DateTime updatedAt;
  final double latitude;
  final double longitude;
  final int gridNumber;
  final String stationCode;
  final String selectionSource;

  const _Kotoho7GridCarrierEntry({
    required this.state,
    required this.updatedAt,
    required this.latitude,
    required this.longitude,
    required this.gridNumber,
    required this.stationCode,
    required this.selectionSource,
  });
}

class _DepthCandidate extends _Candidate {
  final double depthKm;

  const _DepthCandidate({
    required super.latitude,
    required super.longitude,
    required this.depthKm,
    required super.score,
    super.timeScore,
    super.rankScore,
    super.referenceDistanceKm,
  });
}
