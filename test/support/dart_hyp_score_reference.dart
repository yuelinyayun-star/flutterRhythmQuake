// Frozen mechanically from before-hyp-score.zip. Do not update to match Rust.
// Controlled ABI edge tests use this original scorer; raw performance replay is separate.
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_geometry.dart';
import 'package:flutterrhythmquake/core/source_estimation/kanameishi_jma2001_travel_time_table.dart';
import 'package:flutterrhythmquake/core/source_estimation/palert_source_profile.dart';
part 'dart_hyp_search_reference.dart';

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
    this.palertMaxLevel,
    this.palertSecondMaxLevel,
    this.nonQuietBoundary,
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
  final int? palertMaxLevel;
  final int? palertSecondMaxLevel;
  final DateTime? nonQuietBoundary;

  bool get hasInferenceWeight => palertMaxLevel != null
      ? PAlertSourceProfile.pickWeight(palertMaxLevel!) > 0
      : ascend >= 2;
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

_NiedHypWorkerResult _scoreNiedReferenceCandidate(
  List<_NiedHypWorkerStation> active,
  List<_NiedHypWorkerStation> inactive, {
  NativeHypGeometry? nativeGeometry,
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
    final ascendWeight = station.palertMaxLevel != null
        ? PAlertSourceProfile.pickWeight(station.palertMaxLevel!)
        : station.ascend >= 4
        ? math.min(0.2 * station.ascend, 2.0)
        : station.ascend >= 3
        ? 0.3
        : station.ascend >= 2
        ? 0.1
        : 0.0;
    return densityWeight * rankWeight * ascendWeight;
  });

  final geometryValues = nativeGeometry?.evaluate(latitude, longitude, depthKm);
  final distances = List<double>.filled(stationCount, 0.0);
  final pOrigins = List<double>.filled(stationCount, 0.0);
  final sOrigins = List<double>.filled(stationCount, 0.0);
  for (var index = 0; index < stationCount; index++) {
    final station = active[index];
    final distanceKm =
        geometryValues?[index * 3] ??
        _kanameishiHaversineKm(
          latitude,
          longitude,
          station.coordinate.latitude,
          station.coordinate.longitude,
        );
    distances[index] = distanceKm;
    final observedSeconds =
        station.triggerAt!.difference(earliestAt).inMilliseconds / 1000.0;
    pOrigins[index] =
        observedSeconds -
        (geometryValues?[index * 3 + 1] ??
            KanameishiJma2001TravelTimeTable.travelTimeSeconds(
              surfaceDistanceKm: distanceKm,
              depthKm: depthKm,
              pWave: true,
            ));
    sOrigins[index] =
        observedSeconds -
        (geometryValues?[index * 3 + 2] ??
            KanameishiJma2001TravelTimeTable.travelTimeSeconds(
              surfaceDistanceKm: distanceKm,
              depthKm: depthKm,
              pWave: false,
            ));
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

  // These distances depend only on the candidate, not the P/S scenario.
  final palert = active.any((station) => station.palertMaxLevel != null);
  final referenceDistances = <double>[
    for (var index = 0; index < stationCount; index++)
      if (palert
          ? (active[index].palertSecondMaxLevel ?? -1) >= 9
          : active[index].ascend >= 3 && (active[index].level ?? -1) >= 4)
        distances[index],
  ]..sort();
  final referenceDistance = referenceDistances.isEmpty
      ? null
      : referenceDistances[math.max(
          (referenceDistances.length * (palert ? 0.8 : 0.9)).floor() - 1,
          0,
        )];
  final inactiveDistances = <double>[
    if (referenceDistance != null)
      for (final station in inactive)
        if (station.updateAt != null &&
            (!palert ||
                (station.nonQuietBoundary?.isBefore(earliestAt) ?? false)))
          _kanameishiHaversineKm(
            latitude,
            longitude,
            station.coordinate.latitude,
            station.coordinate.longitude,
          ),
  ]..sort();
  final penalized = referenceDistance == null
      ? 0
      : inactiveDistances
            .takeWhile((distance) => distance <= referenceDistance)
            .length;

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

    var inactivePenalty = 0.0;
    if (referenceDistance != null) {
      if (inactiveDistances.length > effectiveCount &&
          inactiveDistances[effectiveCount] <= referenceDistance) {
        return null;
      }
      inactivePenalty = penalized / effectiveCount;
    }
    final rmse = math.sqrt(residualSquares / weightSum);
    final inactiveWeight = effectiveCount >= 50
        ? 0.0
        : (palert ? 8.0 : 10.0) * (1.0 - effectiveCount / 50.0);
    final waveMultiplier = palert
        ? 1 +
              (0.5 * (sCount / math.max(1, pCount) - (8 + filterStageLevel)))
                  .clamp(0.0, 2.0 - 0.5 * filterStageLevel)
        : math.min(math.max(sCount / math.max(1, pCount) - 2.0, 1.0), 3.0);
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

_NiedHypWorkerResult _referenceHypScoreResult(
  List<double> coordinates,
  Int64List info,
  Int64List observedMilliseconds,
  int inactiveCount,
  double latitude,
  double longitude,
  double depth,
) {
  final count = observedMilliseconds.length;
  final base = DateTime.utc(2026);
  final active = <_NiedHypWorkerStation>[
    for (var i = 0; i < count; i++)
      _NiedHypWorkerStation(
        id: '$i',
        code: '$i',
        coordinate: LatLng(coordinates[i * 2], coordinates[i * 2 + 1]),
        triggerAt: base.add(Duration(milliseconds: observedMilliseconds[i])),
        updateAt: base,
        level: info[i * 8 + 2],
        currentShindo: null,
        ascend: info[i * 8 + 1],
        active: true,
        palertMaxLevel: info[i * 8 + 3] != 0 ? info[i * 8 + 4] : null,
        palertSecondMaxLevel: info[i * 8 + 5],
      ),
  ];
  final inactive = <_NiedHypWorkerStation>[
    for (var i = 0; i < inactiveCount; i++)
      _NiedHypWorkerStation(
        id: 'I$i',
        code: 'I$i',
        coordinate: LatLng(
          coordinates[(count + i) * 2],
          coordinates[(count + i) * 2 + 1],
        ),
        triggerAt: null,
        updateAt: base,
        level: null,
        currentShindo: null,
        ascend: 0,
        active: false,
        nonQuietBoundary: base.subtract(const Duration(microseconds: 1)),
      ),
  ];
  final result = _scoreNiedReferenceCandidate(
    active,
    inactive,
    latitude: latitude,
    longitude: longitude,
    depthKm: depth,
    earliestAt: base,
    adjacencyByStationId: {
      for (var i = 0; i < count; i++)
        '$i': {for (var j = 0; j < info[i * 8]; j++) 'N$j'},
    },
    referencePreviousWavesByFirstWave: {
      for (var side = 0; side < 2; side++)
        side == 0 ? 'P' : 'S': {
          for (var i = 0; i < count; i++)
            if (info[i * 8 + 6 + side] >= 0) '$i': info[i * 8 + 6 + side] == 1,
        },
    },
  );
  return result;
}

Map<String, Object?>? referenceHypScore(
  List<double> coordinates,
  Int64List info,
  Int64List observedMilliseconds,
  int inactiveCount,
  double latitude,
  double longitude,
  double depth,
) {
  final result = _referenceHypScoreResult(
    coordinates,
    info,
    observedMilliseconds,
    inactiveCount,
    latitude,
    longitude,
    depth,
  );
  if (result.effectiveStationCount == 0) return null;
  return {
    'fields': [
      result.originOffsetSeconds,
      result.score,
      result.rmse,
      result.weightSum,
      result.weightedResidualSquares,
      result.inactivePenalty,
      result.inactivePenaltyWeight,
      result.waveCountPenaltyMultiplier,
      result.effectiveStationCount.toDouble(),
      result.qualityScore,
      result.pWaveCount.toDouble(),
      result.sWaveCount.toDouble(),
      result.referenceScenarioDiagnostics['reference_l_wave_count']!.toString(),
      result.referenceScenarioDiagnostics['reference_o_wave_count']!.toString(),
    ],
    'diagnostics': result.referenceScenarioDiagnostics,
    'waves': result.referencePreviousWavesByFirstWave,
  };
}
