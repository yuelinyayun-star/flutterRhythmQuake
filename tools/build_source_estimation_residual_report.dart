import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _hybridMethod = 'nied_gif_hybrid_v1';
const _defaultCaseId = '20260621_fukushima_offshore_m32_eq6';
const _defaultInput =
    '.dart_tool/source_estimation_benchmark/20260621_fukushima_offshore_m32_eq6.reference.json';
const _defaultOutput =
    '.dart_tool/source_estimation_residual_report/fukushima_miyagi_m32.json';
const _defaultMarkdown =
    'docs/baselines/fukushima_miyagi_m32_residual_report.generated.md';
const _waveSpeedKmPerSec = 3.8;

void main(List<String> args) {
  final inputPath = _argument(args, '--input') ?? _defaultInput;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('Benchmark report does not exist: ${input.path}');
    exitCode = 66;
    return;
  }

  final decoded = jsonDecode(input.readAsStringSync());
  if (decoded is! Map) {
    stderr.writeln('Benchmark report is not a JSON object: ${input.path}');
    exitCode = 65;
    return;
  }

  final stationIndex = _stationIndex();
  final report = _ResidualReport.fromBenchmark(
    input,
    decoded.cast<String, Object?>(),
    stationIndex,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote residual report for ${report.caseId}');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

class _ResidualReport {
  final String caseId;
  final String inputPath;
  final String? region;
  final Map<String, Object?> truth;
  final int estimateFrameCount;
  final Map<String, _FrameResidual> selectedFrames;
  final List<String> findings;

  const _ResidualReport({
    required this.caseId,
    required this.inputPath,
    required this.region,
    required this.truth,
    required this.estimateFrameCount,
    required this.selectedFrames,
    required this.findings,
  });

  factory _ResidualReport.fromBenchmark(
    File input,
    Map<String, Object?> report,
    Map<String, _StationMeta> stationIndex,
  ) {
    final caseData = _map(report['case']);
    final classification = _map(caseData['classification']);
    final truth = _map(caseData['truth']);
    final truthLat = _number(truth['latitude']);
    final truthLng = _number(truth['longitude']);
    if (truthLat == null || truthLng == null) {
      throw const FormatException('case truth latitude/longitude is required');
    }

    final frames = <_FrameResidual>[];
    for (final rawFrame in _list(report['frames'])) {
      final frame = _map(rawFrame);
      final method = _map(_map(frame['methods'])[_hybridMethod]);
      final estimate = _mapOrNull(method['estimate']);
      if (estimate == null) continue;
      final residual = _FrameResidual.fromFrame(
        sourceFrameIndex: _list(report['frames']).indexOf(rawFrame),
        frame: frame,
        method: method,
        estimate: estimate,
        truthLat: truthLat,
        truthLng: truthLng,
        stationIndex: stationIndex,
      );
      if (residual.picks.isNotEmpty) frames.add(residual);
    }

    final selected = <String, _FrameResidual>{};
    if (frames.isNotEmpty) {
      selected['first'] = frames.first;
      selected['worst'] = frames[_maxIndex(frames, (frame) => frame.errorKm)];
      selected['largest_jump'] =
          frames[_maxIndex(frames, (frame) => frame.jumpKm)];
      selected['final'] = frames.last;
    }

    return _ResidualReport(
      caseId: caseData['caseId']?.toString() ?? _defaultCaseId,
      inputPath: input.path,
      region: classification['region']?.toString(),
      truth: truth,
      estimateFrameCount: frames.length,
      selectedFrames: selected,
      findings: _findings(frames, selected),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'source_estimation_residual_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'caseId': caseId,
    'inputPath': inputPath,
    'region': region,
    'method': _hybridMethod,
    'waveSpeedKmPerSec': _waveSpeedKmPerSec,
    'truth': truth,
    'estimateFrameCount': estimateFrameCount,
    'selectedFrames': selectedFrames.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'findings': findings,
  };
}

class _FrameResidual {
  final int sourceFrameIndex;
  final String? observedAtJst;
  final double? errorKm;
  final double? jumpKm;
  final double estimateLatitude;
  final double estimateLongitude;
  final _CandidateCorrectionResidual? candidateCorrection;
  final Map<String, Object?> geometry;
  final Map<String, Object?> scores;
  final List<_PickResidual> picks;
  final _ResidualStats estimateResiduals;
  final _ResidualStats truthResiduals;
  final _RankStats estimateRank;
  final _RankStats truthRank;
  final double estimateCentroidDistanceKm;
  final double truthCentroidDistanceKm;
  final double medianPickDistanceToEstimateKm;
  final double medianPickDistanceToTruthKm;

  const _FrameResidual({
    required this.sourceFrameIndex,
    required this.observedAtJst,
    required this.errorKm,
    required this.jumpKm,
    required this.estimateLatitude,
    required this.estimateLongitude,
    required this.candidateCorrection,
    required this.geometry,
    required this.scores,
    required this.picks,
    required this.estimateResiduals,
    required this.truthResiduals,
    required this.estimateRank,
    required this.truthRank,
    required this.estimateCentroidDistanceKm,
    required this.truthCentroidDistanceKm,
    required this.medianPickDistanceToEstimateKm,
    required this.medianPickDistanceToTruthKm,
  });

  factory _FrameResidual.fromFrame({
    required int sourceFrameIndex,
    required Map<String, Object?> frame,
    required Map<String, Object?> method,
    required Map<String, Object?> estimate,
    required double truthLat,
    required double truthLng,
    required Map<String, _StationMeta> stationIndex,
  }) {
    final estimateLat = _number(estimate['latitude']);
    final estimateLng = _number(estimate['longitude']);
    if (estimateLat == null || estimateLng == null) {
      throw const FormatException('estimate latitude/longitude is required');
    }
    final diagnostics = _map(estimate['diagnostics']);
    final rawPicks = _list(diagnostics['top_timing_picks']);
    final pickInputs = <_PickInput>[];
    for (final rawPick in rawPicks) {
      final pick = _map(rawPick);
      final code = pick['code']?.toString();
      final observedDelay = _number(pick['delay_s']);
      if (code == null || observedDelay == null) continue;
      final station = stationIndex[code];
      if (station == null) continue;
      pickInputs.add(
        _PickInput(
          code: code,
          station: station,
          observedDelaySeconds: observedDelay,
          value: _number(pick['value']),
          activity: _number(pick['activity']),
          ascend: _integer(pick['ascend']),
        ),
      );
    }

    final estimateDistances = pickInputs
        .map(
          (pick) => _haversineKm(
            estimateLat,
            estimateLng,
            pick.station.lat,
            pick.station.lng,
          ),
        )
        .toList(growable: false);
    final truthDistances = pickInputs
        .map(
          (pick) => _haversineKm(
            truthLat,
            truthLng,
            pick.station.lat,
            pick.station.lng,
          ),
        )
        .toList(growable: false);
    final minEstimateDistance = estimateDistances.isEmpty
        ? 0.0
        : estimateDistances.reduce(math.min);
    final minTruthDistance = truthDistances.isEmpty
        ? 0.0
        : truthDistances.reduce(math.min);
    final centroid = _centroid(pickInputs);
    final candidateCorrection = _CandidateCorrectionResidual.fromDiagnostics(
      diagnostics,
      truthLat: truthLat,
      truthLng: truthLng,
      picks: pickInputs,
    );

    final picks = <_PickResidual>[];
    for (var index = 0; index < pickInputs.length; index++) {
      final input = pickInputs[index];
      final estimateDistance = estimateDistances[index];
      final truthDistance = truthDistances[index];
      final estimatePredicted =
          (estimateDistance - minEstimateDistance) / _waveSpeedKmPerSec;
      final truthPredicted =
          (truthDistance - minTruthDistance) / _waveSpeedKmPerSec;
      picks.add(
        _PickResidual(
          code: input.code,
          network: input.station.network,
          latitude: input.station.lat,
          longitude: input.station.lng,
          observedDelaySeconds: input.observedDelaySeconds,
          value: input.value,
          activity: input.activity,
          ascend: input.ascend,
          distanceToEstimateKm: estimateDistance,
          distanceToTruthKm: truthDistance,
          bearingFromEstimateDeg: _bearingDegrees(
            estimateLat,
            estimateLng,
            input.station.lat,
            input.station.lng,
          ),
          bearingFromTruthDeg: _bearingDegrees(
            truthLat,
            truthLng,
            input.station.lat,
            input.station.lng,
          ),
          estimatePredictedDelaySeconds: estimatePredicted,
          truthPredictedDelaySeconds: truthPredicted,
          estimateResidualSeconds:
              input.observedDelaySeconds - estimatePredicted,
          truthResidualSeconds: input.observedDelaySeconds - truthPredicted,
        ),
      );
    }

    picks.sort(
      (left, right) =>
          left.observedDelaySeconds.compareTo(right.observedDelaySeconds),
    );
    return _FrameResidual(
      sourceFrameIndex: sourceFrameIndex,
      observedAtJst: frame['observedAtJst']?.toString(),
      errorKm: _number(method['errorKm']),
      jumpKm: _number(method['jumpKm']),
      estimateLatitude: estimateLat,
      estimateLongitude: estimateLng,
      candidateCorrection: candidateCorrection,
      geometry: {
        'classification': diagnostics['station_geometry']?.toString(),
        'azimuthalGapDeg': _number(diagnostics['station_azimuthal_gap_deg']),
        'nearestStationDistanceKm': _number(
          diagnostics['nearest_station_distance_km'],
        ),
        'searchBoundaryMarginDeg': _number(
          diagnostics['search_boundary_margin_deg'],
        ),
        'searchBoundaryHit': diagnostics['search_boundary_hit'] == true,
        'horizontalUncertaintyP50Km': _number(
          diagnostics['horizontal_uncertainty_p50_km'],
        ),
        'horizontalUncertaintyP90Km': _number(
          diagnostics['horizontal_uncertainty_p90_km'],
        ),
      },
      scores: {
        'time': _number(diagnostics['time_score']),
        'rank': _number(diagnostics['rank_score']),
        'geometryPenalty': _number(diagnostics['geometry_penalty']),
        'final': _number(diagnostics['final_score']),
      },
      picks: picks,
      estimateResiduals: _ResidualStats.fromValues(
        picks.map((pick) => pick.estimateResidualSeconds),
      ),
      truthResiduals: _ResidualStats.fromValues(
        picks.map((pick) => pick.truthResidualSeconds),
      ),
      estimateRank: _RankStats.fromPicks(
        picks,
        distanceSelector: (pick) => pick.distanceToEstimateKm,
      ),
      truthRank: _RankStats.fromPicks(
        picks,
        distanceSelector: (pick) => pick.distanceToTruthKm,
      ),
      estimateCentroidDistanceKm: centroid == null
          ? double.nan
          : _haversineKm(estimateLat, estimateLng, centroid.$1, centroid.$2),
      truthCentroidDistanceKm: centroid == null
          ? double.nan
          : _haversineKm(truthLat, truthLng, centroid.$1, centroid.$2),
      medianPickDistanceToEstimateKm: _median(estimateDistances) ?? double.nan,
      medianPickDistanceToTruthKm: _median(truthDistances) ?? double.nan,
    );
  }

  Map<String, Object?> toJson() => {
    'sourceFrameIndex': sourceFrameIndex,
    'observedAtJst': observedAtJst,
    'estimate': {
      'latitude': estimateLatitude,
      'longitude': estimateLongitude,
      'errorKm': errorKm,
      'jumpKm': jumpKm,
    },
    'candidateCorrection': candidateCorrection?.toJson(),
    'geometry': geometry,
    'scores': scores,
    'pickCount': picks.length,
    'estimateResiduals': estimateResiduals.toJson(),
    'truthResiduals': truthResiduals.toJson(),
    'estimateRank': estimateRank.toJson(),
    'truthRank': truthRank.toJson(),
    'estimateCentroidDistanceKm': _finiteOrNull(estimateCentroidDistanceKm),
    'truthCentroidDistanceKm': _finiteOrNull(truthCentroidDistanceKm),
    'medianPickDistanceToEstimateKm': _finiteOrNull(
      medianPickDistanceToEstimateKm,
    ),
    'medianPickDistanceToTruthKm': _finiteOrNull(medianPickDistanceToTruthKm),
    'picks': picks.map((pick) => pick.toJson()).toList(),
  };
}

class _CandidateCorrectionResidual {
  final double latitude;
  final double longitude;
  final double errorKm;
  final bool applied;
  final double? score;
  final _ResidualStats residuals;
  final _RankStats rank;
  final double medianPickDistanceKm;

  const _CandidateCorrectionResidual({
    required this.latitude,
    required this.longitude,
    required this.errorKm,
    required this.applied,
    required this.score,
    required this.residuals,
    required this.rank,
    required this.medianPickDistanceKm,
  });

  factory _CandidateCorrectionResidual.fromDiagnostics(
    Map<String, Object?> diagnostics, {
    required double truthLat,
    required double truthLng,
    required List<_PickInput> picks,
  }) {
    final corrections = _map(diagnostics['candidate_corrections']);
    final guard = _map(corrections['one_sided_boundary_centroid_guard']);
    final latitude = _number(guard['latitude']);
    final longitude = _number(guard['longitude']);
    if (latitude == null || longitude == null) {
      return const _CandidateCorrectionResidual.none();
    }

    final distances = picks
        .map(
          (pick) => _haversineKm(
            latitude,
            longitude,
            pick.station.lat,
            pick.station.lng,
          ),
        )
        .toList(growable: false);
    final minDistance = distances.isEmpty ? 0.0 : distances.reduce(math.min);
    final residuals = <double>[];
    for (var index = 0; index < picks.length; index++) {
      final predicted = (distances[index] - minDistance) / _waveSpeedKmPerSec;
      residuals.add(picks[index].observedDelaySeconds - predicted);
    }

    return _CandidateCorrectionResidual(
      latitude: latitude,
      longitude: longitude,
      errorKm: _haversineKm(latitude, longitude, truthLat, truthLng),
      applied: guard['applied'] == true,
      score: _number(guard['score']),
      residuals: _ResidualStats.fromValues(residuals),
      rank: _RankStats.fromInputs(picks, distances),
      medianPickDistanceKm: _median(distances) ?? double.nan,
    );
  }

  const _CandidateCorrectionResidual.none()
    : latitude = double.nan,
      longitude = double.nan,
      errorKm = double.nan,
      applied = false,
      score = null,
      residuals = const _ResidualStats(
        mean: null,
        meanAbs: null,
        rms: null,
        maxAbs: null,
      ),
      rank = const _RankStats(
        comparablePairs: 0,
        inversionPairs: 0,
        inversionRate: 0,
      ),
      medianPickDistanceKm = double.nan;

  bool get exists => latitude.isFinite && longitude.isFinite;

  Map<String, Object?>? toJson() => exists
      ? {
          'latitude': latitude,
          'longitude': longitude,
          'errorKm': errorKm,
          'applied': applied,
          'score': score,
          'residuals': residuals.toJson(),
          'rank': rank.toJson(),
          'medianPickDistanceKm': _finiteOrNull(medianPickDistanceKm),
        }
      : null;
}

class _PickInput {
  final String code;
  final _StationMeta station;
  final double observedDelaySeconds;
  final double? value;
  final double? activity;
  final int? ascend;

  const _PickInput({
    required this.code,
    required this.station,
    required this.observedDelaySeconds,
    required this.value,
    required this.activity,
    required this.ascend,
  });
}

class _PickResidual {
  final String code;
  final String network;
  final double latitude;
  final double longitude;
  final double observedDelaySeconds;
  final double? value;
  final double? activity;
  final int? ascend;
  final double distanceToEstimateKm;
  final double distanceToTruthKm;
  final double bearingFromEstimateDeg;
  final double bearingFromTruthDeg;
  final double estimatePredictedDelaySeconds;
  final double truthPredictedDelaySeconds;
  final double estimateResidualSeconds;
  final double truthResidualSeconds;

  const _PickResidual({
    required this.code,
    required this.network,
    required this.latitude,
    required this.longitude,
    required this.observedDelaySeconds,
    required this.value,
    required this.activity,
    required this.ascend,
    required this.distanceToEstimateKm,
    required this.distanceToTruthKm,
    required this.bearingFromEstimateDeg,
    required this.bearingFromTruthDeg,
    required this.estimatePredictedDelaySeconds,
    required this.truthPredictedDelaySeconds,
    required this.estimateResidualSeconds,
    required this.truthResidualSeconds,
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'network': network,
    'latitude': latitude,
    'longitude': longitude,
    'observedDelaySeconds': observedDelaySeconds,
    'value': value,
    'activity': activity,
    'ascend': ascend,
    'distanceToEstimateKm': distanceToEstimateKm,
    'distanceToTruthKm': distanceToTruthKm,
    'bearingFromEstimateDeg': bearingFromEstimateDeg,
    'bearingFromTruthDeg': bearingFromTruthDeg,
    'estimatePredictedDelaySeconds': estimatePredictedDelaySeconds,
    'truthPredictedDelaySeconds': truthPredictedDelaySeconds,
    'estimateResidualSeconds': estimateResidualSeconds,
    'truthResidualSeconds': truthResidualSeconds,
  };
}

class _ResidualStats {
  final double? mean;
  final double? meanAbs;
  final double? rms;
  final double? maxAbs;

  const _ResidualStats({
    required this.mean,
    required this.meanAbs,
    required this.rms,
    required this.maxAbs,
  });

  factory _ResidualStats.fromValues(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList();
    if (list.isEmpty) {
      return const _ResidualStats(
        mean: null,
        meanAbs: null,
        rms: null,
        maxAbs: null,
      );
    }
    final sum = list.fold<double>(0, (total, value) => total + value);
    final abs = list.map((value) => value.abs()).toList();
    final square = list.fold<double>(
      0,
      (total, value) => total + value * value,
    );
    return _ResidualStats(
      mean: sum / list.length,
      meanAbs:
          abs.fold<double>(0, (total, value) => total + value) / list.length,
      rms: math.sqrt(square / list.length),
      maxAbs: abs.reduce(math.max),
    );
  }

  Map<String, Object?> toJson() => {
    'meanSeconds': mean,
    'meanAbsSeconds': meanAbs,
    'rmsSeconds': rms,
    'maxAbsSeconds': maxAbs,
  };
}

class _RankStats {
  final int comparablePairs;
  final int inversionPairs;
  final double inversionRate;

  const _RankStats({
    required this.comparablePairs,
    required this.inversionPairs,
    required this.inversionRate,
  });

  factory _RankStats.fromPicks(
    List<_PickResidual> picks, {
    required double Function(_PickResidual pick) distanceSelector,
  }) {
    var comparable = 0;
    var inversions = 0;
    for (var i = 0; i < picks.length; i++) {
      final leftValue = picks[i].value;
      if (leftValue == null || !leftValue.isFinite) continue;
      for (var j = i + 1; j < picks.length; j++) {
        final rightValue = picks[j].value;
        if (rightValue == null || !rightValue.isFinite) continue;
        final valueDiff = leftValue - rightValue;
        if (valueDiff.abs() < 0.05) continue;
        comparable++;
        final distanceDiff =
            distanceSelector(picks[i]) - distanceSelector(picks[j]);
        if ((valueDiff > 0 && distanceDiff > 0) ||
            (valueDiff < 0 && distanceDiff < 0)) {
          inversions++;
        }
      }
    }
    return _RankStats(
      comparablePairs: comparable,
      inversionPairs: inversions,
      inversionRate: comparable == 0 ? 0 : inversions / comparable,
    );
  }

  factory _RankStats.fromInputs(
    List<_PickInput> picks,
    List<double> distancesKm,
  ) {
    var comparable = 0;
    var inversions = 0;
    for (var i = 0; i < picks.length; i++) {
      final leftValue = picks[i].value;
      if (leftValue == null || !leftValue.isFinite) continue;
      for (var j = i + 1; j < picks.length; j++) {
        final rightValue = picks[j].value;
        if (rightValue == null || !rightValue.isFinite) continue;
        final valueDiff = leftValue - rightValue;
        if (valueDiff.abs() < 0.05) continue;
        comparable++;
        final distanceDiff = distancesKm[i] - distancesKm[j];
        if ((valueDiff > 0 && distanceDiff > 0) ||
            (valueDiff < 0 && distanceDiff < 0)) {
          inversions++;
        }
      }
    }
    return _RankStats(
      comparablePairs: comparable,
      inversionPairs: inversions,
      inversionRate: comparable == 0 ? 0 : inversions / comparable,
    );
  }

  Map<String, Object?> toJson() => {
    'comparablePairs': comparablePairs,
    'inversionPairs': inversionPairs,
    'inversionRate': inversionRate,
  };
}

class _StationMeta {
  final String code;
  final String network;
  final double lat;
  final double lng;

  const _StationMeta({
    required this.code,
    required this.network,
    required this.lat,
    required this.lng,
  });
}

Map<String, _StationMeta> _stationIndex() {
  final result = <String, _StationMeta>{};
  for (final entry in NiedStationDb.stations) {
    final code = entry['code']?.toString();
    final lat = _number(entry['lat']);
    final lng = _number(entry['lng']);
    if (code == null || lat == null || lng == null) continue;
    result[code] = _StationMeta(
      code: code,
      network: entry['network']?.toString() ?? 'unknown',
      lat: lat,
      lng: lng,
    );
  }
  return result;
}

List<String> _findings(
  List<_FrameResidual> frames,
  Map<String, _FrameResidual> selected,
) {
  if (frames.isEmpty) return const ['no_estimated_frames'];
  final findings = <String>[];
  final worst = selected['worst'];
  if (worst != null) {
    final estimateRms = worst.estimateResiduals.rms;
    final truthRms = worst.truthResiduals.rms;
    if (estimateRms != null &&
        truthRms != null &&
        truthRms > estimateRms * 1.4) {
      findings.add('truth_has_worse_travel_time_fit_than_estimate');
    }
    if (estimateRms != null && estimateRms > 5) {
      findings.add('large_travel_time_residuals_even_at_estimate');
    }
    final truthRank = worst.truthRank.inversionRate;
    final estimateRank = worst.estimateRank.inversionRate;
    if (truthRank > estimateRank + 0.25) {
      findings.add('truth_has_worse_intensity_distance_rank');
    }
    final geometry = worst.geometry['classification'];
    if (geometry == 'one_sided' &&
        worst.geometry['searchBoundaryHit'] == true) {
      findings.add('one_sided_boundary_worst_frame');
    }
  }
  if (frames.any((frame) => (frame.errorKm ?? 0) >= 150)) {
    findings.add('catastrophic_location_error');
  }
  return findings;
}

String _markdown(_ResidualReport report) {
  final buffer = StringBuffer()
    ..writeln('# ${_reportTitle(report)}')
    ..writeln()
    ..writeln('Generated from `${report.inputPath}`.')
    ..writeln('No production estimator weights are changed by this report.')
    ..writeln()
    ..writeln('- Case: `${report.caseId}`')
    ..writeln('- Method: `$_hybridMethod`')
    ..writeln('- Estimate frames: ${report.estimateFrameCount}')
    ..writeln(
      '- Findings: ${report.findings.map((item) => '`$item`').join(', ')}',
    )
    ..writeln()
    ..writeln('## Selected Frames')
    ..writeln()
    ..writeln(
      '| Frame | Time | Error | Candidate | Jump | Pick count | Estimate RMS | Candidate RMS | Truth RMS | Estimate rank inv. | Candidate rank inv. | Truth rank inv. | Median dist est/cand/truth | Geometry |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |',
    );
  for (final entry in report.selectedFrames.entries) {
    final frame = entry.value;
    final candidate = frame.candidateCorrection;
    buffer.writeln(
      '| `${entry.key}` | ${frame.observedAtJst ?? '-'} | '
      '${_format(frame.errorKm, 'km')} | '
      '${_candidateFrameSummary(candidate)} | '
      '${_format(frame.jumpKm, 'km')} | '
      '${frame.picks.length} | '
      '${_format(frame.estimateResiduals.rms, 's')} | '
      '${_format(candidate?.exists == true ? candidate!.residuals.rms : null, 's')} | '
      '${_format(frame.truthResiduals.rms, 's')} | '
      '${_percent(frame.estimateRank.inversionRate)} | '
      '${candidate?.exists == true ? _percent(candidate!.rank.inversionRate) : '-'} | '
      '${_percent(frame.truthRank.inversionRate)} | '
      '${_format(frame.medianPickDistanceToEstimateKm, 'km')} / '
      '${_format(candidate?.exists == true ? candidate!.medianPickDistanceKm : null, 'km')} / '
      '${_format(frame.medianPickDistanceToTruthKm, 'km')} | '
      '${_geometrySummary(frame.geometry)} |',
    );
  }

  for (final entry in report.selectedFrames.entries) {
    final frame = entry.value;
    buffer
      ..writeln()
      ..writeln('## `${entry.key}` Picks')
      ..writeln()
      ..writeln(
        '| Code | Obs | Est pred/res | Truth pred/res | Dist est/truth | Bearing est/truth | Value |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final pick in frame.picks) {
      buffer.writeln(
        '| `${pick.code}` | ${_format(pick.observedDelaySeconds, 's')} | '
        '${_format(pick.estimatePredictedDelaySeconds, 's')} / '
        '${_signed(pick.estimateResidualSeconds, 's')} | '
        '${_format(pick.truthPredictedDelaySeconds, 's')} / '
        '${_signed(pick.truthResidualSeconds, 's')} | '
        '${_format(pick.distanceToEstimateKm, 'km')} / '
        '${_format(pick.distanceToTruthKm, 'km')} | '
        '${_format(pick.bearingFromEstimateDeg, 'deg')} / '
        '${_format(pick.bearingFromTruthDeg, 'deg')} | '
        '${_format(pick.value, '')} |',
      );
    }
  }
  return buffer.toString();
}

String _reportTitle(_ResidualReport report) {
  final region = report.region?.trim();
  if (region != null && region.isNotEmpty) {
    return '$region Residual Report';
  }
  return '${report.caseId} Residual Report';
}

String _geometrySummary(Map<String, Object?> geometry) {
  final classification = geometry['classification']?.toString() ?? '--';
  final gap = _format(geometry['azimuthalGapDeg'], 'deg');
  final nearest = _format(geometry['nearestStationDistanceKm'], 'km');
  final margin = _format(geometry['searchBoundaryMarginDeg'], 'deg');
  final boundary = geometry['searchBoundaryHit'] == true ? 'boundary' : 'inner';
  final p90 = _format(geometry['horizontalUncertaintyP90Km'], 'km');
  return '$classification; gap $gap; nearest $nearest; margin $margin; '
      '$boundary; P90u $p90';
}

String _candidateFrameSummary(_CandidateCorrectionResidual? candidate) {
  if (candidate == null || !candidate.exists) return '-';
  final applied = candidate.applied ? 'applied' : 'diagnostic';
  return '${_format(candidate.errorKm, 'km')} ($applied)';
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == name && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$name=')) return args[i].substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _integer(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

int _maxIndex(List<_FrameResidual> frames, double? Function(_FrameResidual) f) {
  var bestIndex = 0;
  var bestValue = double.negativeInfinity;
  for (var i = 0; i < frames.length; i++) {
    final value = f(frames[i]);
    if (value == null) continue;
    if (value > bestValue) {
      bestIndex = i;
      bestValue = value;
    }
  }
  return bestIndex;
}

(double, double)? _centroid(List<_PickInput> picks) {
  if (picks.isEmpty) return null;
  var lat = 0.0;
  var lng = 0.0;
  for (final pick in picks) {
    lat += pick.station.lat;
    lng += pick.station.lng;
  }
  return (lat / picks.length, lng / picks.length);
}

double? _median(List<double> values) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double? _finiteOrNull(double value) => value.isFinite ? value : null;

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _bearingDegrees(
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
) {
  final phi1 = _degToRad(fromLat);
  final phi2 = _degToRad(toLat);
  final deltaLng = _degToRad(toLng - fromLng);
  final y = math.sin(deltaLng) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(deltaLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _degToRad(double degrees) => degrees * math.pi / 180.0;

String _format(Object? value, String unit) {
  final number = _number(value);
  if (number == null || !number.isFinite) return '-';
  final suffix = unit.isEmpty ? '' : ' $unit';
  return '${number.toStringAsFixed(1)}$suffix';
}

String _signed(double value, String unit) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${_format(value, unit)}';
}

String _percent(double value) => '${(value * 100).toStringAsFixed(0)}%';
