import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _defaultInputDirectory = '.dart_tool/source_estimation_benchmark';
const _defaultOutputPath =
    '.dart_tool/kotoho7_existing_member_reregister_report/report.json';
const _method = 'nied_gif_hyp_kotoho7_reference_replay_v1';

final Map<String, _StationLocation> _stationByCode = {
  for (final row in NiedStationDb.stations)
    (row['code'] as String): _StationLocation(
      latitude: (row['lat'] as num).toDouble(),
      longitude: (row['lng'] as num).toDouble(),
    ),
};

void main(List<String> args) {
  final inputDirectory = Directory(
    _argument(args, '--input') ?? _defaultInputDirectory,
  );
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final outputFile = File(outputPath);
  final cases = <Map<String, Object?>>[];

  if (inputDirectory.existsSync()) {
    final files =
        inputDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.reference.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
      if (decoded is! Map<String, Object?>) continue;
      final summary = _summarizeCase(file, decoded);
      if (summary != null) cases.add(summary);
    }
  }

  final casesWithRawOverlap = cases
      .where((entry) => _int(entry['rawOverlapFrameCount']) > 0)
      .length;
  final casesWithEffectiveOverlap = cases
      .where((entry) => _int(entry['effectiveOverlapFrameCount']) > 0)
      .length;
  final report = <String, Object?>{
    'schemaVersion': 'kotoho7_existing_member_reregister_report_v1',
    'inputDirectory': inputDirectory.path,
    'method': _method,
    'purpose':
        'Offline diagnostic for Scratch 検出id3 existing-member re-register candidates. It does not run replay and must not be moved into estimator hot-path metadata.',
    'caseCount': cases.length,
    'casesWithRawOverlap': casesWithRawOverlap,
    'casesWithEffectiveOverlap': casesWithEffectiveOverlap,
    'cases': cases,
  };

  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  stdout.writeln('Wrote ${outputFile.path}');
}

Map<String, Object?>? _summarizeCase(File file, Map<String, Object?> json) {
  final frames = json['frames'];
  if (frames is! List) return null;
  final caseJson = _map(json['case']);
  final caseId =
      _string(caseJson['caseId']) ??
      file.uri.pathSegments.last.replaceAll('.reference.json', '');

  var estimateFrameCount = 0;
  var rawOverlapFrameCount = 0;
  var effectiveOverlapFrameCount = 0;
  var continuityOverlapFrameCount = 0;
  var rawOverlapTotal = 0;
  var effectiveOverlapTotal = 0;
  var continuityOverlapTotal = 0;
  var assignedStationTotal = 0;
  var rawMemberTotal = 0;
  var effectiveMemberTotal = 0;
  var continuityMemberTotal = 0;
  var assignmentAddedTotal = 0;
  var assignmentReriseRefreshTotal = 0;
  var assignmentRemovedTotal = 0;
  var assignmentNegativeCountDeltaTotal = 0;
  var assignmentWouldSwitchOtherIdTotal = 0;
  var framesWithWouldSwitchOtherId = 0;
  var geometryProxyEvaluatedTotal = 0;
  var geometryProxySameIdCandidateTotal = 0;
  var geometryProxyFirstPointFallbackTotal = 0;
  var geometryProxyRejectedWideTotal = 0;
  var geometryProxyMissingCoordinateTotal = 0;
  var geometryProxyNoSourceTotal = 0;
  var phaseProxyPWindowTotal = 0;
  var phaseProxySRangeTotal = 0;
  var phaseProxyRejectedBeforePTotal = 0;
  var phaseProxyRejectedAfterSTotal = 0;
  var phaseProxyMissingObservedTimeTotal = 0;
  var trueTimingPhaseProxyPWindowTotal = 0;
  var trueTimingPhaseProxySRangeTotal = 0;
  var trueTimingPhaseProxyRejectedBeforePTotal = 0;
  var trueTimingPhaseProxyRejectedAfterSTotal = 0;
  var trueTimingPhaseProxyMissingObservedTimeTotal = 0;
  var id2SimulationFrameCount = 0;
  var id2WouldCallId3Total = 0;
  var id2InitialState5DirectTotal = 0;
  var id2InitialRiseNearest7SupportedTotal = 0;
  var id2ExistingReriseCandidateTotal = 0;
  var id2ExistingRefreshPlus2OnlyTotal = 0;
  var id2ExistingNoId3Total = 0;
  var id2StrictUnknown0WouldCallId3Total = 0;
  var id2PermissionCacheWouldCallId3Total = 0;
  var maxRawOverlap = 0;
  var maxEffectiveOverlap = 0;
  var maxContinuityOverlap = 0;
  double? maxPositiveShadowScoreDelta;
  Map<String, Object?>? finalFrame;
  Map<String, Object?>? maxRawOverlapFrame;
  Map<String, Object?>? maxEffectiveOverlapFrame;
  Map<String, Object?>? maxPositiveShadowScoreDeltaFrame;
  final topRawOverlapFrames = <Map<String, Object?>>[];
  final topEffectiveOverlapFrames = <Map<String, Object?>>[];
  final firstRawMemberAtByCode = <String, DateTime>{};
  final trueObservedAtByCode = <String, DateTime>{};

  for (final rawFrame in frames) {
    final frame = _map(rawFrame);
    final method = _map(_map(frame['methods'])[_method]);
    final estimate = _map(method['estimate']);
    if (estimate.isEmpty) continue;
    final diagnostics = _map(estimate['diagnostics']);
    final cache = _map(diagnostics['stateful_source_cache']);
    final id2Simulation = _scratchId2Simulation(cache);
    final assigned = _stringSet(cache['assigned_station_codes']);
    if (assigned.isEmpty) continue;
    estimateFrameCount += 1;

    final metadata = _map(frame['sourceTriggerMetadata']);
    final rawMembers = _stringSet(metadata['source_trigger_raw_member_ids']);
    for (final entry in _stationObservedAtByCode(
      metadata['station_trigger_observation_times'],
    ).entries) {
      final previous = trueObservedAtByCode[entry.key];
      if (previous == null || entry.value.isBefore(previous)) {
        trueObservedAtByCode[entry.key] = entry.value;
      }
    }
    final frameObservedAt = _dateTime(frame['observedAtJst']);
    if (frameObservedAt != null) {
      for (final code in rawMembers) {
        firstRawMemberAtByCode.putIfAbsent(code, () => frameObservedAt);
      }
    }
    final effectiveMembers = _stringSet(metadata['source_trigger_member_ids']);
    final continuityMembers = _stringSet(
      metadata['source_trigger_continuity_member_ids'],
    );
    final rawOverlap = assigned.intersection(rawMembers);
    final effectiveOverlap = assigned.intersection(effectiveMembers);
    final continuityOverlap = assigned.intersection(continuityMembers);
    final geometryProxy = _existingPlus3GeometryProxy(
      frame: frame,
      diagnostics: diagnostics,
      cache: cache,
      rawOverlap: rawOverlap,
      firstRawMemberAtByCode: firstRawMemberAtByCode,
      trueObservedAtByCode: trueObservedAtByCode,
    );
    final summary = _frameSummary(
      frame: frame,
      method: method,
      estimate: estimate,
      cache: cache,
      rawOverlap: rawOverlap,
      effectiveOverlap: effectiveOverlap,
      continuityOverlap: continuityOverlap,
      rawMemberCount: rawMembers.length,
      effectiveMemberCount: effectiveMembers.length,
      continuityMemberCount: continuityMembers.length,
      geometryProxy: geometryProxy,
    );
    finalFrame = summary;

    rawOverlapTotal += rawOverlap.length;
    effectiveOverlapTotal += effectiveOverlap.length;
    continuityOverlapTotal += continuityOverlap.length;
    assignedStationTotal += assigned.length;
    rawMemberTotal += rawMembers.length;
    effectiveMemberTotal += effectiveMembers.length;
    continuityMemberTotal += continuityMembers.length;
    final addedCount = _int(cache['last_assignment_added_count']);
    final reriseRefreshCount = _int(
      cache['last_assignment_rerise_refresh_count'],
    );
    final removedCount = _int(cache['last_assignment_removed_count']);
    final negativeDelta = _int(cache['last_assignment_negative_count_delta']);
    final wouldSwitchCount = _int(
      cache['last_assignment_would_switch_other_id_count'],
    );
    assignmentAddedTotal += addedCount;
    assignmentReriseRefreshTotal += reriseRefreshCount;
    assignmentRemovedTotal += removedCount;
    assignmentNegativeCountDeltaTotal += negativeDelta;
    assignmentWouldSwitchOtherIdTotal += wouldSwitchCount;
    if (wouldSwitchCount > 0) framesWithWouldSwitchOtherId += 1;
    geometryProxyEvaluatedTotal += geometryProxy.evaluatedCount;
    geometryProxySameIdCandidateTotal += geometryProxy.sameIdCandidateCount;
    geometryProxyFirstPointFallbackTotal +=
        geometryProxy.firstPointFallbackCount;
    geometryProxyRejectedWideTotal += geometryProxy.rejectedWideCount;
    geometryProxyMissingCoordinateTotal += geometryProxy.missingCoordinateCount;
    geometryProxyNoSourceTotal += geometryProxy.noSourceOrFallbackCount;
    phaseProxyPWindowTotal += geometryProxy.phasePWindowCount;
    phaseProxySRangeTotal += geometryProxy.phaseSRangeCount;
    phaseProxyRejectedBeforePTotal += geometryProxy.phaseRejectedBeforePCount;
    phaseProxyRejectedAfterSTotal += geometryProxy.phaseRejectedAfterSCount;
    phaseProxyMissingObservedTimeTotal +=
        geometryProxy.phaseMissingObservedTimeCount;
    trueTimingPhaseProxyPWindowTotal += geometryProxy.truePhasePWindowCount;
    trueTimingPhaseProxySRangeTotal += geometryProxy.truePhaseSRangeCount;
    trueTimingPhaseProxyRejectedBeforePTotal +=
        geometryProxy.truePhaseRejectedBeforePCount;
    trueTimingPhaseProxyRejectedAfterSTotal +=
        geometryProxy.truePhaseRejectedAfterSCount;
    trueTimingPhaseProxyMissingObservedTimeTotal +=
        geometryProxy.truePhaseMissingObservedTimeCount;
    if (id2Simulation.isNotEmpty) {
      id2SimulationFrameCount += 1;
      id2WouldCallId3Total += _int(id2Simulation['would_call_id3_count']);
      id2InitialState5DirectTotal += _int(
        id2Simulation['initial_state5_direct_count'],
      );
      id2InitialRiseNearest7SupportedTotal += _int(
        id2Simulation['initial_rise_nearest7_supported_count'],
      );
      id2ExistingReriseCandidateTotal += _int(
        id2Simulation['existing_rerise_candidate_count'],
      );
      id2ExistingRefreshPlus2OnlyTotal += _int(
        id2Simulation['existing_refresh_plus2_only_count'],
      );
      id2ExistingNoId3Total += _int(id2Simulation['existing_no_id3_count']);
      id2StrictUnknown0WouldCallId3Total += _int(
        id2Simulation['strict_unknown0_would_call_id3_count'],
      );
      id2PermissionCacheWouldCallId3Total += _int(
        id2Simulation['permission_cache_would_call_id3_count'],
      );
    }
    if (rawOverlap.isNotEmpty) rawOverlapFrameCount += 1;
    if (effectiveOverlap.isNotEmpty) effectiveOverlapFrameCount += 1;
    if (continuityOverlap.isNotEmpty) continuityOverlapFrameCount += 1;
    if (rawOverlap.length > maxRawOverlap) {
      maxRawOverlap = rawOverlap.length;
      maxRawOverlapFrame = summary;
    }
    if (effectiveOverlap.length > maxEffectiveOverlap) {
      maxEffectiveOverlap = effectiveOverlap.length;
      maxEffectiveOverlapFrame = summary;
    }
    if (continuityOverlap.length > maxContinuityOverlap) {
      maxContinuityOverlap = continuityOverlap.length;
    }
    final shadowDelta = _double(summary['shadowScoreDeltaVsCurrent']);
    if (shadowDelta != null &&
        shadowDelta > 0 &&
        (maxPositiveShadowScoreDelta == null ||
            shadowDelta > maxPositiveShadowScoreDelta)) {
      maxPositiveShadowScoreDelta = shadowDelta;
      maxPositiveShadowScoreDeltaFrame = summary;
    }
    _insertTopFrame(
      topRawOverlapFrames,
      summary,
      key: 'rawExistingMemberOverlapCount',
    );
    _insertTopFrame(
      topEffectiveOverlapFrames,
      summary,
      key: 'effectiveExistingMemberOverlapCount',
    );
  }

  final finalRawOverlap = _int(finalFrame?['rawExistingMemberOverlapCount']);
  final finalEffectiveOverlap = _int(
    finalFrame?['effectiveExistingMemberOverlapCount'],
  );
  return {
    'caseId': caseId,
    'path': file.path,
    'frameCount': frames.length,
    'estimateFrameCount': estimateFrameCount,
    'interpretation': _interpretCase(
      estimateFrameCount: estimateFrameCount,
      rawOverlapFrameCount: rawOverlapFrameCount,
      effectiveOverlapFrameCount: effectiveOverlapFrameCount,
      rawOverlapTotal: rawOverlapTotal,
      effectiveOverlapTotal: effectiveOverlapTotal,
      finalRawOverlap: finalRawOverlap,
      finalEffectiveOverlap: finalEffectiveOverlap,
    ),
    'rawOverlapFrameCount': rawOverlapFrameCount,
    'effectiveOverlapFrameCount': effectiveOverlapFrameCount,
    'continuityOverlapFrameCount': continuityOverlapFrameCount,
    'rawOverlapFrameRatio': _ratio(rawOverlapFrameCount, estimateFrameCount),
    'effectiveOverlapFrameRatio': _ratio(
      effectiveOverlapFrameCount,
      estimateFrameCount,
    ),
    'rawOverlapTotal': rawOverlapTotal,
    'effectiveOverlapTotal': effectiveOverlapTotal,
    'continuityOverlapTotal': continuityOverlapTotal,
    'existingPlus3CurrentFrameSkipCandidateTotal': rawOverlapTotal,
    'existingPlus3CurrentFrameSkipCandidateFrameCount': rawOverlapFrameCount,
    'existingPlus3OfflineProbeRequired': rawOverlapTotal > 0,
    'existingPlus3OfflineProbeReason':
        'source_estimator hot path keeps already-assigned current detections behind the Scratch +3 skip guard; running 4-2 selection there makes Fukushima replay hit the five-minute timeout',
    'existingPlus3GeometryProxyModel':
        'offline_same_id_source_cache_geometry_only_no_phase_residual_v1',
    'existingPlus3GeometryProxyEvaluatedTotal': geometryProxyEvaluatedTotal,
    'existingPlus3GeometryProxySameIdCandidateTotal':
        geometryProxySameIdCandidateTotal,
    'existingPlus3GeometryProxyFirstPointFallbackTotal':
        geometryProxyFirstPointFallbackTotal,
    'existingPlus3GeometryProxyRejectedWideTotal':
        geometryProxyRejectedWideTotal,
    'existingPlus3GeometryProxyMissingCoordinateTotal':
        geometryProxyMissingCoordinateTotal,
    'existingPlus3GeometryProxyNoSourceTotal': geometryProxyNoSourceTotal,
    'existingPlus3PhaseProxyModel':
        'offline_same_id_4_2_phase_proxy_using_first_raw_member_time_v1',
    'existingPlus3PhaseProxyPWindowTotal': phaseProxyPWindowTotal,
    'existingPlus3PhaseProxySRangeTotal': phaseProxySRangeTotal,
    'existingPlus3PhaseProxyRejectedBeforePTotal':
        phaseProxyRejectedBeforePTotal,
    'existingPlus3PhaseProxyRejectedAfterSTotal': phaseProxyRejectedAfterSTotal,
    'existingPlus3PhaseProxyMissingObservedTimeTotal':
        phaseProxyMissingObservedTimeTotal,
    'existingPlus3TrueTimingPhaseProxyModel':
        'offline_same_id_4_2_phase_proxy_using_station_first_trigger_or_rise_time_v1',
    'existingPlus3TrueTimingPhaseProxyPWindowTotal':
        trueTimingPhaseProxyPWindowTotal,
    'existingPlus3TrueTimingPhaseProxySRangeTotal':
        trueTimingPhaseProxySRangeTotal,
    'existingPlus3TrueTimingPhaseProxyRejectedBeforePTotal':
        trueTimingPhaseProxyRejectedBeforePTotal,
    'existingPlus3TrueTimingPhaseProxyRejectedAfterSTotal':
        trueTimingPhaseProxyRejectedAfterSTotal,
    'existingPlus3TrueTimingPhaseProxyMissingObservedTimeTotal':
        trueTimingPhaseProxyMissingObservedTimeTotal,
    'scratchId2SimulationFrameCount': id2SimulationFrameCount,
    'scratchId2WouldCallId3Total': id2WouldCallId3Total,
    'scratchId2InitialState5DirectTotal': id2InitialState5DirectTotal,
    'scratchId2InitialRiseNearest7SupportedTotal':
        id2InitialRiseNearest7SupportedTotal,
    'scratchId2ExistingReriseCandidateTotal': id2ExistingReriseCandidateTotal,
    'scratchId2ExistingRefreshPlus2OnlyTotal': id2ExistingRefreshPlus2OnlyTotal,
    'scratchId2ExistingNoId3Total': id2ExistingNoId3Total,
    'scratchId2StrictUnknown0WouldCallId3Total':
        id2StrictUnknown0WouldCallId3Total,
    'scratchId2PermissionCacheWouldCallId3Total':
        id2PermissionCacheWouldCallId3Total,
    'assignedStationTotal': assignedStationTotal,
    'rawMemberTotal': rawMemberTotal,
    'effectiveMemberTotal': effectiveMemberTotal,
    'continuityMemberTotal': continuityMemberTotal,
    'assignmentAddedTotal': assignmentAddedTotal,
    'assignmentReriseRefreshTotal': assignmentReriseRefreshTotal,
    'assignmentRemovedTotal': assignmentRemovedTotal,
    'assignmentNegativeCountDeltaTotal': assignmentNegativeCountDeltaTotal,
    'assignmentWouldSwitchOtherIdTotal': assignmentWouldSwitchOtherIdTotal,
    'framesWithWouldSwitchOtherId': framesWithWouldSwitchOtherId,
    'rawOverlapAssignedRatio': _ratio(rawOverlapTotal, assignedStationTotal),
    'effectiveOverlapAssignedRatio': _ratio(
      effectiveOverlapTotal,
      assignedStationTotal,
    ),
    'finalEffectiveMinusRawOverlap': finalEffectiveOverlap - finalRawOverlap,
    'maxRawOverlap': maxRawOverlap,
    'maxEffectiveOverlap': maxEffectiveOverlap,
    'maxContinuityOverlap': maxContinuityOverlap,
    'maxPositiveShadowScoreDelta': maxPositiveShadowScoreDelta,
    'maxRawOverlapFrame': maxRawOverlapFrame,
    'maxEffectiveOverlapFrame': maxEffectiveOverlapFrame,
    'maxPositiveShadowScoreDeltaFrame': maxPositiveShadowScoreDeltaFrame,
    'topRawOverlapFrames': topRawOverlapFrames,
    'topEffectiveOverlapFrames': topEffectiveOverlapFrames,
    'finalFrame': finalFrame,
  };
}

String _interpretCase({
  required int estimateFrameCount,
  required int rawOverlapFrameCount,
  required int effectiveOverlapFrameCount,
  required int rawOverlapTotal,
  required int effectiveOverlapTotal,
  required int finalRawOverlap,
  required int finalEffectiveOverlap,
}) {
  if (estimateFrameCount == 0) return 'no_estimate_frames';
  if (rawOverlapTotal == 0 && effectiveOverlapTotal == 0) {
    return 'no_existing_member_overlap';
  }
  if (rawOverlapTotal == 0 && effectiveOverlapTotal > 0) {
    return 'effective_retention_only_no_raw_current_overlap';
  }
  final rawFrameRatio = rawOverlapFrameCount / estimateFrameCount;
  final effectiveMinusRawFinal = finalEffectiveOverlap - finalRawOverlap;
  if (rawFrameRatio >= 0.8) {
    if (effectiveMinusRawFinal >= 30 &&
        finalEffectiveOverlap >= finalRawOverlap * 3) {
      return 'persistent_raw_overlap_with_late_effective_retention_dominance';
    }
    return 'persistent_raw_current_overlap';
  }
  if (effectiveOverlapFrameCount > rawOverlapFrameCount * 2) {
    return 'mixed_overlap_effective_retention_dominant';
  }
  return 'raw_current_overlap_present';
}

Map<String, Object?> _frameSummary({
  required Map<String, Object?> frame,
  required Map<String, Object?> method,
  required Map<String, Object?> estimate,
  required Map<String, Object?> cache,
  required Set<String> rawOverlap,
  required Set<String> effectiveOverlap,
  required Set<String> continuityOverlap,
  required int rawMemberCount,
  required int effectiveMemberCount,
  required int continuityMemberCount,
  required _GeometryProxySummary geometryProxy,
}) {
  final diagnostics = _map(estimate['diagnostics']);
  final shadow = _map(cache['station_ps_cache_shadow']);
  final shadowRescore = _map(shadow['shadow_rescore']);
  final id2Simulation = _scratchId2Simulation(cache);
  return {
    'observedAtJst': frame['observedAtJst'],
    'errorKm': method['errorKm'],
    'latitude': estimate['latitude'],
    'longitude': estimate['longitude'],
    'depthKm': estimate['depthKm'],
    'score': diagnostics['score'],
    'phasePCount': diagnostics['phase_p_count'],
    'phaseSCount': diagnostics['phase_s_count'],
    'phaseOtherCount': diagnostics['phase_other_count'],
    'assignedStationCount': cache['assigned_station_count'],
    'rawMemberCount': rawMemberCount,
    'effectiveMemberCount': effectiveMemberCount,
    'continuityMemberCount': continuityMemberCount,
    'rawExistingMemberOverlapCount': rawOverlap.length,
    'effectiveExistingMemberOverlapCount': effectiveOverlap.length,
    'continuityExistingMemberOverlapCount': continuityOverlap.length,
    'lastAssignmentAddedCount': cache['last_assignment_added_count'],
    'lastAssignmentReriseRefreshCount':
        cache['last_assignment_rerise_refresh_count'],
    'lastAssignmentRemovedCount': cache['last_assignment_removed_count'],
    'lastAssignmentNegativeCountDelta':
        cache['last_assignment_negative_count_delta'],
    'lastAssignmentWouldSwitchOtherIdCount':
        cache['last_assignment_would_switch_other_id_count'],
    'existingPlus3GeometryProxy': geometryProxy.toJson(),
    'scratchId2WouldCallId3Count': id2Simulation['would_call_id3_count'],
    'scratchId2InitialState5DirectCount':
        id2Simulation['initial_state5_direct_count'],
    'scratchId2InitialRiseNearest7SupportedCount':
        id2Simulation['initial_rise_nearest7_supported_count'],
    'scratchId2ExistingReriseCandidateCount':
        id2Simulation['existing_rerise_candidate_count'],
    'scratchId2ExistingRefreshPlus2OnlyCount':
        id2Simulation['existing_refresh_plus2_only_count'],
    'scratchId2ExistingNoId3Count': id2Simulation['existing_no_id3_count'],
    'scratchId2StrictUnknown0WouldCallId3Count':
        id2Simulation['strict_unknown0_would_call_id3_count'],
    'scratchId2PermissionCacheWouldCallId3Count':
        id2Simulation['permission_cache_would_call_id3_count'],
    'rawExistingMemberOverlapSample': _sample(rawOverlap),
    'effectiveExistingMemberOverlapSample': _sample(effectiveOverlap),
    'shadowScore': shadowRescore['score'],
    'shadowScoreDeltaVsCurrent': shadowRescore['score_delta_vs_current'],
    'shadowPhasePCount': shadowRescore['phase_p_count'],
    'shadowPhaseSCount': shadowRescore['phase_s_count'],
    'shadowPhaseOtherCount': shadowRescore['phase_other_count'],
    'shadowMissingSFlagCount': shadow['missing_shadow_s_flag_count'],
    'shadowSFlagDisagreementCount': shadow['s_flag_disagreement_count'],
  };
}

_GeometryProxySummary _existingPlus3GeometryProxy({
  required Map<String, Object?> frame,
  required Map<String, Object?> diagnostics,
  required Map<String, Object?> cache,
  required Set<String> rawOverlap,
  required Map<String, DateTime> firstRawMemberAtByCode,
  required Map<String, DateTime> trueObservedAtByCode,
}) {
  if (rawOverlap.isEmpty) return _GeometryProxySummary.empty();

  final sourceCache = _map(cache['scratch_4_4_source_cache']);
  final proxy43 = _map(cache['scratch_4_3_proxy']);
  final sourceLatitude = _double(sourceCache['slot_plus_3_latitude']);
  final sourceLongitude = _double(sourceCache['slot_plus_2_longitude']);
  final sourceDepthKm = _double(sourceCache['slot_plus_4_depth_km']);
  final sourceOriginOffsetSeconds = _double(
    sourceCache['slot_plus_5_origin_offset_s'],
  );
  final sourceScore =
      _double(proxy43['best_score']) ?? _double(diagnostics['score']);
  final assignedCount = _int(cache['assigned_station_count']);
  final observedAt = _dateTime(frame['observedAtJst']);
  final earliestObservedAt = _dateTime(cache['earliest_observed_at']);
  final elapsedSinceStateStartSeconds =
      observedAt == null || earliestObservedAt == null
      ? null
      : observedAt.difference(earliestObservedAt).inMilliseconds / 1000.0;
  final firstDistanceLimitKm =
      _double(proxy43['max_first_station_distance_km']) ?? 0.0;
  final sourceDistanceLimitKm =
      _double(proxy43['max_source_distance_km']) ?? 0.0;
  final useSourceCache =
      sourceLatitude != null &&
      sourceLongitude != null &&
      sourceDepthKm != null &&
      sourceOriginOffsetSeconds != null &&
      sourceScore != null &&
      sourceScore.isFinite &&
      elapsedSinceStateStartSeconds != null &&
      elapsedSinceStateStartSeconds > 5.0 &&
      sourceScore < 500.0;
  final useFirstPointFallback = !useSourceCache && assignedCount > 4;

  var evaluatedCount = 0;
  var sameIdCandidateCount = 0;
  var firstPointFallbackCount = 0;
  var rejectedWideCount = 0;
  var missingCoordinateCount = 0;
  var noSourceOrFallbackCount = 0;
  var distanceSum = 0.0;
  var maxDistance = 0.0;
  var phasePWindowCount = 0;
  var phaseSRangeCount = 0;
  var phaseRejectedBeforePCount = 0;
  var phaseRejectedAfterSCount = 0;
  var phaseMissingObservedTimeCount = 0;
  var truePhasePWindowCount = 0;
  var truePhaseSRangeCount = 0;
  var truePhaseRejectedBeforePCount = 0;
  var truePhaseRejectedAfterSCount = 0;
  var truePhaseMissingObservedTimeCount = 0;
  final samples = <Map<String, Object?>>[];

  for (final code in rawOverlap) {
    evaluatedCount += 1;
    final station = _stationByCode[code];
    if (station == null) {
      missingCoordinateCount += 1;
      if (samples.length < 16) {
        samples.add({'station_code': code, 'decision': 'missing_coordinate'});
      }
      continue;
    }
    if (!useSourceCache && !useFirstPointFallback) {
      noSourceOrFallbackCount += 1;
      if (samples.length < 16) {
        samples.add({
          'station_code': code,
          'decision': 'no_source_or_fallback',
          'source_score': sourceScore,
          'elapsed_since_state_start_s': elapsedSinceStateStartSeconds,
          'assigned_count': assignedCount,
        });
      }
      continue;
    }
    if (!useSourceCache) {
      firstPointFallbackCount += 1;
      if (samples.length < 16) {
        samples.add({
          'station_code': code,
          'decision': 'first_point_fallback_possible',
          'assigned_count': assignedCount,
        });
      }
      continue;
    }

    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      station.latitude,
      station.longitude,
    );
    distanceSum += surfaceDistanceKm;
    maxDistance = math.max(maxDistance, surfaceDistanceKm);
    final tooOldWide =
        surfaceDistanceKm > 900.0 &&
        elapsedSinceStateStartSeconds > 100.0 &&
        sourceDistanceLimitKm > 0.0 &&
        1.5 * sourceDistanceLimitKm < surfaceDistanceKm;
    final wideAfter15Seconds =
        surfaceDistanceKm > 900.0 &&
        elapsedSinceStateStartSeconds > 15.0 &&
        firstDistanceLimitKm > 0.0 &&
        1.4 * firstDistanceLimitKm < surfaceDistanceKm;
    if (tooOldWide || wideAfter15Seconds) {
      rejectedWideCount += 1;
      if (samples.length < 16) {
        samples.add({
          'station_code': code,
          'decision': tooOldWide
              ? 'reject_wide_old_plus10'
              : 'reject_wide_after15_plus5',
          'surface_distance_km': surfaceDistanceKm,
          'first_distance_limit_km': firstDistanceLimitKm,
          'source_distance_limit_km': sourceDistanceLimitKm,
        });
      }
      continue;
    }

    sameIdCandidateCount += 1;
    final phase = _classifyPhaseWindow(
      stationObservedAt: firstRawMemberAtByCode[code],
      earliestObservedAt: earliestObservedAt,
      sourceOriginOffsetSeconds: sourceOriginOffsetSeconds,
      surfaceDistanceKm: surfaceDistanceKm,
      sourceDepthKm: sourceDepthKm,
      missingDecision: 'phase_missing_first_raw_member_time',
    );
    switch (phase.kind) {
      case _PhaseWindowKind.p:
        phasePWindowCount += 1;
      case _PhaseWindowKind.s:
        phaseSRangeCount += 1;
      case _PhaseWindowKind.beforeP:
        phaseRejectedBeforePCount += 1;
      case _PhaseWindowKind.afterS:
        phaseRejectedAfterSCount += 1;
      case _PhaseWindowKind.missing:
        phaseMissingObservedTimeCount += 1;
    }
    final truePhase = _classifyPhaseWindow(
      stationObservedAt: trueObservedAtByCode[code],
      earliestObservedAt: earliestObservedAt,
      sourceOriginOffsetSeconds: sourceOriginOffsetSeconds,
      surfaceDistanceKm: surfaceDistanceKm,
      sourceDepthKm: sourceDepthKm,
      missingDecision: 'phase_missing_station_first_trigger_or_rise_time',
    );
    switch (truePhase.kind) {
      case _PhaseWindowKind.p:
        truePhasePWindowCount += 1;
      case _PhaseWindowKind.s:
        truePhaseSRangeCount += 1;
      case _PhaseWindowKind.beforeP:
        truePhaseRejectedBeforePCount += 1;
      case _PhaseWindowKind.afterS:
        truePhaseRejectedAfterSCount += 1;
      case _PhaseWindowKind.missing:
        truePhaseMissingObservedTimeCount += 1;
    }
    if (samples.length < 16) {
      samples.add({
        'station_code': code,
        'decision': 'same_id_geometry_possible',
        'phase_decision': phase.decision,
        'true_timing_phase_decision': truePhase.decision,
        'surface_distance_km': surfaceDistanceKm,
        'station_observed_s': phase.stationObservedSeconds,
        'true_station_observed_s': truePhase.stationObservedSeconds,
        'p_arrival_s': phase.pArrivalSeconds,
        's_arrival_s': phase.sArrivalSeconds,
        'p_residual_s': phase.pResidualSeconds,
        's_residual_s': phase.sResidualSeconds,
        'true_p_residual_s': truePhase.pResidualSeconds,
        'true_s_residual_s': truePhase.sResidualSeconds,
      });
    }
  }

  final distanceCount = sameIdCandidateCount + rejectedWideCount;
  return _GeometryProxySummary(
    evaluatedCount: evaluatedCount,
    sameIdCandidateCount: sameIdCandidateCount,
    firstPointFallbackCount: firstPointFallbackCount,
    rejectedWideCount: rejectedWideCount,
    missingCoordinateCount: missingCoordinateCount,
    noSourceOrFallbackCount: noSourceOrFallbackCount,
    phasePWindowCount: phasePWindowCount,
    phaseSRangeCount: phaseSRangeCount,
    phaseRejectedBeforePCount: phaseRejectedBeforePCount,
    phaseRejectedAfterSCount: phaseRejectedAfterSCount,
    phaseMissingObservedTimeCount: phaseMissingObservedTimeCount,
    truePhasePWindowCount: truePhasePWindowCount,
    truePhaseSRangeCount: truePhaseSRangeCount,
    truePhaseRejectedBeforePCount: truePhaseRejectedBeforePCount,
    truePhaseRejectedAfterSCount: truePhaseRejectedAfterSCount,
    truePhaseMissingObservedTimeCount: truePhaseMissingObservedTimeCount,
    meanSurfaceDistanceKm: distanceCount == 0
        ? null
        : distanceSum / distanceCount,
    maxSurfaceDistanceKm: distanceCount == 0 ? null : maxDistance,
    useSourceCache: useSourceCache,
    useFirstPointFallback: useFirstPointFallback,
    sourceScore: sourceScore,
    elapsedSinceStateStartSeconds: elapsedSinceStateStartSeconds,
    samples: List<Map<String, Object?>>.unmodifiable(samples),
  );
}

void _insertTopFrame(
  List<Map<String, Object?>> frames,
  Map<String, Object?> frame, {
  required String key,
}) {
  final value = _int(frame[key]);
  if (value <= 0) return;
  frames.add(frame);
  frames.sort((left, right) => _int(right[key]).compareTo(_int(left[key])));
  if (frames.length > 12) frames.removeLast();
}

class _GeometryProxySummary {
  final int evaluatedCount;
  final int sameIdCandidateCount;
  final int firstPointFallbackCount;
  final int rejectedWideCount;
  final int missingCoordinateCount;
  final int noSourceOrFallbackCount;
  final int phasePWindowCount;
  final int phaseSRangeCount;
  final int phaseRejectedBeforePCount;
  final int phaseRejectedAfterSCount;
  final int phaseMissingObservedTimeCount;
  final int truePhasePWindowCount;
  final int truePhaseSRangeCount;
  final int truePhaseRejectedBeforePCount;
  final int truePhaseRejectedAfterSCount;
  final int truePhaseMissingObservedTimeCount;
  final double? meanSurfaceDistanceKm;
  final double? maxSurfaceDistanceKm;
  final bool useSourceCache;
  final bool useFirstPointFallback;
  final double? sourceScore;
  final double? elapsedSinceStateStartSeconds;
  final List<Map<String, Object?>> samples;

  const _GeometryProxySummary({
    required this.evaluatedCount,
    required this.sameIdCandidateCount,
    required this.firstPointFallbackCount,
    required this.rejectedWideCount,
    required this.missingCoordinateCount,
    required this.noSourceOrFallbackCount,
    required this.phasePWindowCount,
    required this.phaseSRangeCount,
    required this.phaseRejectedBeforePCount,
    required this.phaseRejectedAfterSCount,
    required this.phaseMissingObservedTimeCount,
    required this.truePhasePWindowCount,
    required this.truePhaseSRangeCount,
    required this.truePhaseRejectedBeforePCount,
    required this.truePhaseRejectedAfterSCount,
    required this.truePhaseMissingObservedTimeCount,
    required this.meanSurfaceDistanceKm,
    required this.maxSurfaceDistanceKm,
    required this.useSourceCache,
    required this.useFirstPointFallback,
    required this.sourceScore,
    required this.elapsedSinceStateStartSeconds,
    required this.samples,
  });

  factory _GeometryProxySummary.empty() => const _GeometryProxySummary(
    evaluatedCount: 0,
    sameIdCandidateCount: 0,
    firstPointFallbackCount: 0,
    rejectedWideCount: 0,
    missingCoordinateCount: 0,
    noSourceOrFallbackCount: 0,
    phasePWindowCount: 0,
    phaseSRangeCount: 0,
    phaseRejectedBeforePCount: 0,
    phaseRejectedAfterSCount: 0,
    phaseMissingObservedTimeCount: 0,
    truePhasePWindowCount: 0,
    truePhaseSRangeCount: 0,
    truePhaseRejectedBeforePCount: 0,
    truePhaseRejectedAfterSCount: 0,
    truePhaseMissingObservedTimeCount: 0,
    meanSurfaceDistanceKm: null,
    maxSurfaceDistanceKm: null,
    useSourceCache: false,
    useFirstPointFallback: false,
    sourceScore: null,
    elapsedSinceStateStartSeconds: null,
    samples: <Map<String, Object?>>[],
  );

  Map<String, Object?> toJson() => {
    'model': 'offline_same_id_source_cache_geometry_only_no_phase_residual_v1',
    'evaluated_count': evaluatedCount,
    'same_id_candidate_count': sameIdCandidateCount,
    'first_point_fallback_count': firstPointFallbackCount,
    'rejected_wide_count': rejectedWideCount,
    'missing_coordinate_count': missingCoordinateCount,
    'no_source_or_fallback_count': noSourceOrFallbackCount,
    'phase_proxy_model':
        'offline_same_id_4_2_phase_proxy_using_first_raw_member_time_v1',
    'phase_p_window_count': phasePWindowCount,
    'phase_s_range_count': phaseSRangeCount,
    'phase_rejected_before_p_count': phaseRejectedBeforePCount,
    'phase_rejected_after_s_count': phaseRejectedAfterSCount,
    'phase_missing_observed_time_count': phaseMissingObservedTimeCount,
    'true_timing_phase_proxy_model':
        'offline_same_id_4_2_phase_proxy_using_station_first_trigger_or_rise_time_v1',
    'true_timing_phase_p_window_count': truePhasePWindowCount,
    'true_timing_phase_s_range_count': truePhaseSRangeCount,
    'true_timing_phase_rejected_before_p_count': truePhaseRejectedBeforePCount,
    'true_timing_phase_rejected_after_s_count': truePhaseRejectedAfterSCount,
    'true_timing_phase_missing_observed_time_count':
        truePhaseMissingObservedTimeCount,
    'mean_surface_distance_km': meanSurfaceDistanceKm,
    'max_surface_distance_km': maxSurfaceDistanceKm,
    'use_source_cache': useSourceCache,
    'use_first_point_fallback': useFirstPointFallback,
    'source_score': sourceScore,
    'elapsed_since_state_start_s': elapsedSinceStateStartSeconds,
    'samples': samples,
  };
}

enum _PhaseWindowKind { p, s, beforeP, afterS, missing }

class _PhaseWindowDecision {
  final _PhaseWindowKind kind;
  final String decision;
  final double? stationObservedSeconds;
  final double? pArrivalSeconds;
  final double? sArrivalSeconds;
  final double? pResidualSeconds;
  final double? sResidualSeconds;

  const _PhaseWindowDecision({
    required this.kind,
    required this.decision,
    required this.stationObservedSeconds,
    required this.pArrivalSeconds,
    required this.sArrivalSeconds,
    required this.pResidualSeconds,
    required this.sResidualSeconds,
  });
}

_PhaseWindowDecision _classifyPhaseWindow({
  required DateTime? stationObservedAt,
  required DateTime? earliestObservedAt,
  required double sourceOriginOffsetSeconds,
  required double surfaceDistanceKm,
  required double sourceDepthKm,
  required String missingDecision,
}) {
  if (stationObservedAt == null || earliestObservedAt == null) {
    return _PhaseWindowDecision(
      kind: _PhaseWindowKind.missing,
      decision: missingDecision,
      stationObservedSeconds: null,
      pArrivalSeconds: null,
      sArrivalSeconds: null,
      pResidualSeconds: null,
      sResidualSeconds: null,
    );
  }

  final observedSeconds =
      stationObservedAt.difference(earliestObservedAt).inMilliseconds / 1000.0;
  final hypocentralDistanceKm = math.sqrt(
    surfaceDistanceKm * surfaceDistanceKm + sourceDepthKm * sourceDepthKm,
  );
  final pArrivalSeconds =
      sourceOriginOffsetSeconds +
      Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: sourceDepthKm,
        pWave: true,
      );
  final sArrivalSeconds =
      sourceOriginOffsetSeconds +
      Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: sourceDepthKm,
        pWave: false,
      );
  final pToleranceSeconds = 5.0 + surfaceDistanceKm / 120.0;
  final sToleranceSeconds = 8.0 + surfaceDistanceKm / 120.0;
  final pResidual = (pArrivalSeconds - observedSeconds).abs();
  final sResidual = (sArrivalSeconds - observedSeconds).abs();
  if (pResidual <= pToleranceSeconds) {
    return _PhaseWindowDecision(
      kind: _PhaseWindowKind.p,
      decision: 'phase_accept_p_window',
      stationObservedSeconds: observedSeconds,
      pArrivalSeconds: pArrivalSeconds,
      sArrivalSeconds: sArrivalSeconds,
      pResidualSeconds: pResidual,
      sResidualSeconds: sResidual,
    );
  }
  if (observedSeconds < pArrivalSeconds - pToleranceSeconds) {
    return _PhaseWindowDecision(
      kind: _PhaseWindowKind.beforeP,
      decision: 'phase_reject_before_p_window',
      stationObservedSeconds: observedSeconds,
      pArrivalSeconds: pArrivalSeconds,
      sArrivalSeconds: sArrivalSeconds,
      pResidualSeconds: pResidual,
      sResidualSeconds: sResidual,
    );
  }
  if (observedSeconds > sArrivalSeconds + sToleranceSeconds) {
    return _PhaseWindowDecision(
      kind: _PhaseWindowKind.afterS,
      decision: 'phase_reject_after_s_window',
      stationObservedSeconds: observedSeconds,
      pArrivalSeconds: pArrivalSeconds,
      sArrivalSeconds: sArrivalSeconds,
      pResidualSeconds: pResidual,
      sResidualSeconds: sResidual,
    );
  }
  return _PhaseWindowDecision(
    kind: _PhaseWindowKind.s,
    decision: 'phase_accept_s_range',
    stationObservedSeconds: observedSeconds,
    pArrivalSeconds: pArrivalSeconds,
    sArrivalSeconds: sArrivalSeconds,
    pResidualSeconds: pResidual,
    sResidualSeconds: sResidual,
  );
}

class _StationLocation {
  final double latitude;
  final double longitude;

  const _StationLocation({required this.latitude, required this.longitude});
}

List<String> _sample(Set<String> values) {
  final sorted = values.toList()..sort();
  return sorted.take(24).toList(growable: false);
}

Set<String> _stringSet(Object? value) {
  if (value is! List) return <String>{};
  return value.whereType<String>().where((item) => item.isNotEmpty).toSet();
}

Map<String, DateTime> _stationObservedAtByCode(Object? value) {
  final source = _map(value);
  if (source.isEmpty) return const <String, DateTime>{};
  final result = <String, DateTime>{};
  for (final entry in source.entries) {
    final timing = _map(entry.value);
    final observedAt =
        _dateTime(timing['first_trigger_at']) ??
        _dateTime(timing['first_rise_at']);
    if (observedAt != null) result[entry.key] = observedAt;
  }
  return result;
}

Map<String, Object?> _scratchId2Simulation(Map<String, Object?> cache) {
  final stationAssignmentSelection = _map(
    cache['station_assignment_selection'],
  );
  final entryPipeline = _map(stationAssignmentSelection['entry_pipeline']);
  return _map(entryPipeline['scratch_id2_full_loop_simulation']);
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

double? _ratio(int numerator, int denominator) =>
    denominator == 0 ? null : numerator / denominator;

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

double _haversineKm(
  double latitude1,
  double longitude1,
  double latitude2,
  double longitude2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _radians(latitude2 - latitude1);
  final dLon = _radians(longitude2 - longitude1);
  final lat1 = _radians(latitude1);
  final lat2 = _radians(latitude2);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180.0;

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
