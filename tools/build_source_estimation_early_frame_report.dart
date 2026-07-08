import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _hybridMethod = 'nied_gif_hybrid_v1';
const _defaultInput =
    '.dart_tool/source_estimation_benchmark/20260621_fukushima_offshore_m32_eq6.reference.json';
const _defaultOutput =
    '.dart_tool/source_estimation_early_frame_report/fukushima_miyagi_m32.json';
const _defaultMarkdown =
    'docs/baselines/fukushima_miyagi_m32_early_frame_report.generated.md';
const _defaultOutputDirectory =
    '.dart_tool/source_estimation_early_frame_report';
const _defaultFrameCount = 10;
const _waveSpeedKmPerSec = 3.8;

// Diagnostic-only static attenuation coefficients. These are used only to
// compare relative within-frame scatter across candidate locations.
const _attenuationLogDistanceCoefficient = 2.0;
const _attenuationLinearDistanceCoefficient = 0.0;
const _attenuationNearDistanceKm = 5.0;

void main(List<String> args) {
  final inputDirectoryPath = _argument(args, '--input-directory');
  final outputDirectoryPath =
      _argument(args, '--output-directory') ?? _defaultOutputDirectory;
  final markdownDirectoryPath =
      _argument(args, '--markdown-directory') ?? outputDirectoryPath;
  final inputPath = _argument(args, '--input') ?? _defaultInput;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;
  final frameCount =
      int.tryParse(_argument(args, '--frame-count') ?? '') ??
      _defaultFrameCount;

  if (inputDirectoryPath != null) {
    _runDirectoryMode(
      inputDirectoryPath: inputDirectoryPath,
      outputDirectoryPath: outputDirectoryPath,
      markdownDirectoryPath: markdownDirectoryPath,
      frameCount: frameCount,
    );
    return;
  }

  _writeReport(
    input: File(inputPath),
    outputPath: outputPath,
    markdownPath: markdownPath,
    frameCount: frameCount,
  );
}

void _runDirectoryMode({
  required String inputDirectoryPath,
  required String outputDirectoryPath,
  required String markdownDirectoryPath,
  required int frameCount,
}) {
  final inputDirectory = Directory(inputDirectoryPath);
  if (!inputDirectory.existsSync()) {
    stderr.writeln(
      'Benchmark report directory does not exist: ${inputDirectory.path}',
    );
    exitCode = 66;
    return;
  }

  final files =
      inputDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  var written = 0;
  final skipped = <Map<String, Object?>>[];
  for (final input in files) {
    final slug = _slug(input);
    final outputPath = '$outputDirectoryPath/$slug.json';
    final markdownPath = '$markdownDirectoryPath/$slug.md';
    try {
      if (_writeReport(
        input: input,
        outputPath: outputPath,
        markdownPath: markdownPath,
        frameCount: frameCount,
        quiet: true,
      )) {
        written++;
      }
    } on FormatException catch (error) {
      skipped.add({'file': input.path, 'reason': error.message});
    }
  }

  stdout.writeln(
    'wrote $written early-frame reports from ${inputDirectory.path}',
  );
  if (skipped.isNotEmpty) {
    stdout.writeln('skipped ${skipped.length} reports:');
    for (final entry in skipped) {
      stdout.writeln('- ${entry['file']}: ${entry['reason']}');
    }
  }
  stdout.writeln('json directory: $outputDirectoryPath');
  stdout.writeln('markdown directory: $markdownDirectoryPath');
}

bool _writeReport({
  required File input,
  required String outputPath,
  required String markdownPath,
  required int frameCount,
  bool quiet = false,
}) {
  if (!input.existsSync()) {
    stderr.writeln('Benchmark report does not exist: ${input.path}');
    exitCode = 66;
    return false;
  }

  final decoded = jsonDecode(input.readAsStringSync());
  if (decoded is! Map) {
    stderr.writeln('Benchmark report is not a JSON object: ${input.path}');
    exitCode = 65;
    return false;
  }

  final report = _EarlyFrameReport.fromBenchmark(
    input: input,
    report: decoded.cast<String, Object?>(),
    stationIndex: _stationIndex(),
    frameCount: frameCount,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  if (!quiet) {
    stdout.writeln('wrote early-frame report for ${report.caseId}');
    stdout.writeln('json: ${output.path}');
    stdout.writeln('markdown: ${markdown.path}');
  }
  return true;
}

class _EarlyFrameReport {
  final String caseId;
  final String inputPath;
  final Map<String, Object?> truth;
  final int requestedFrameCount;
  final List<_EarlyFrame> frames;
  final List<String> findings;

  const _EarlyFrameReport({
    required this.caseId,
    required this.inputPath,
    required this.truth,
    required this.requestedFrameCount,
    required this.frames,
    required this.findings,
  });

  factory _EarlyFrameReport.fromBenchmark({
    required File input,
    required Map<String, Object?> report,
    required Map<String, _StationMeta> stationIndex,
    required int frameCount,
  }) {
    final caseData = _map(report['case']);
    final truth = _map(caseData['truth']);
    final truthLat = _number(truth['latitude']);
    final truthLng = _number(truth['longitude']);
    if (truthLat == null || truthLng == null) {
      throw const FormatException('case truth latitude/longitude is required');
    }

    final frames = <_EarlyFrame>[];
    for (final rawFrame in _list(report['frames'])) {
      final frame = _map(rawFrame);
      final method = _map(_map(frame['methods'])[_hybridMethod]);
      final estimate = _mapOrNull(method['estimate']);
      if (estimate == null) continue;
      final earlyFrame = _EarlyFrame.fromFrame(
        index: _list(report['frames']).indexOf(rawFrame),
        frame: frame,
        method: method,
        estimate: estimate,
        truthLat: truthLat,
        truthLng: truthLng,
        stationIndex: stationIndex,
      );
      if (earlyFrame.picks.isNotEmpty) frames.add(earlyFrame);
      if (frames.length >= frameCount) break;
    }

    return _EarlyFrameReport(
      caseId: caseData['caseId']?.toString() ?? 'unknown_case',
      inputPath: input.path,
      truth: truth,
      requestedFrameCount: frameCount,
      frames: frames,
      findings: _findings(frames),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'source_estimation_early_frame_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'caseId': caseId,
    'inputPath': inputPath,
    'method': _hybridMethod,
    'requestedFrameCount': requestedFrameCount,
    'waveSpeedKmPerSec': _waveSpeedKmPerSec,
    'attenuationDiagnostic': const {
      'model': 'within_frame_static_scatter_v1',
      'productionScoring': false,
      'logDistanceCoefficient': _attenuationLogDistanceCoefficient,
      'linearDistanceCoefficient': _attenuationLinearDistanceCoefficient,
      'nearDistanceKm': _attenuationNearDistanceKm,
    },
    'truth': truth,
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
    'findings': findings,
  };
}

class _EarlyFrame {
  final int index;
  final String? observedAtJst;
  final double estimateLatitude;
  final double estimateLongitude;
  final double? errorKm;
  final double? jumpKm;
  final _LocationDiagnostics baseline;
  final _LocationDiagnostics truth;
  final _LocationDiagnostics? candidate;
  final Map<String, Object?> geometry;
  final Map<String, Object?> scores;
  final Map<String, Object?> sourceTriggerMetadata;
  final bool truthInsideSearchBox;
  final List<_Pick> picks;

  const _EarlyFrame({
    required this.index,
    required this.observedAtJst,
    required this.estimateLatitude,
    required this.estimateLongitude,
    required this.errorKm,
    required this.jumpKm,
    required this.baseline,
    required this.truth,
    required this.candidate,
    required this.geometry,
    required this.scores,
    required this.sourceTriggerMetadata,
    required this.truthInsideSearchBox,
    required this.picks,
  });

  factory _EarlyFrame.fromFrame({
    required int index,
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
    final picks = _picks(diagnostics, stationIndex);
    final candidatePoint = _candidatePoint(diagnostics, truthLat, truthLng);
    final searchBox = _numbers(diagnostics['search_bbox']);

    return _EarlyFrame(
      index: index,
      observedAtJst: frame['observedAtJst']?.toString(),
      estimateLatitude: estimateLat,
      estimateLongitude: estimateLng,
      errorKm: _number(method['errorKm']),
      jumpKm: _number(method['jumpKm']),
      baseline: _LocationDiagnostics.forLocation(
        label: 'baseline',
        latitude: estimateLat,
        longitude: estimateLng,
        truthLat: truthLat,
        truthLng: truthLng,
        picks: picks,
      ),
      truth: _LocationDiagnostics.forLocation(
        label: 'truth',
        latitude: truthLat,
        longitude: truthLng,
        truthLat: truthLat,
        truthLng: truthLng,
        picks: picks,
      ),
      candidate: candidatePoint == null
          ? null
          : _LocationDiagnostics.forLocation(
              label: 'candidate',
              latitude: candidatePoint.latitude,
              longitude: candidatePoint.longitude,
              truthLat: truthLat,
              truthLng: truthLng,
              picks: picks,
              applied: candidatePoint.applied,
              score: candidatePoint.score,
            ),
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
        'searchBox': searchBox,
      },
      scores: {
        'time': _number(diagnostics['time_score']),
        'rank': _number(diagnostics['rank_score']),
        'geometryPenalty': _number(diagnostics['geometry_penalty']),
        'final': _number(diagnostics['final_score']),
      },
      sourceTriggerMetadata: _map(frame['sourceTriggerMetadata']),
      truthInsideSearchBox: _insideSearchBox(truthLat, truthLng, searchBox),
      picks: picks,
    );
  }

  bool get candidateImproves =>
      candidate != null && candidate!.errorKm < (errorKm ?? double.infinity);

  Map<String, Object?> toJson() => {
    'sourceFrameIndex': index,
    'observedAtJst': observedAtJst,
    'estimate': {
      'latitude': estimateLatitude,
      'longitude': estimateLongitude,
      'errorKm': errorKm,
      'jumpKm': jumpKm,
    },
    'truthInsideSearchBox': truthInsideSearchBox,
    'geometry': geometry,
    'scores': scores,
    'sourceTriggerMetadata': sourceTriggerMetadata,
    'baseline': baseline.toJson(),
    'candidate': candidate?.toJson(),
    'truth': truth.toJson(),
    'candidateImproves': candidateImproves,
    'picks': picks.map((pick) => pick.toJson()).toList(growable: false),
  };
}

class _LocationDiagnostics {
  final String label;
  final double latitude;
  final double longitude;
  final double errorKm;
  final bool? applied;
  final double? score;
  final _Stats travelTimeResiduals;
  final _RankStats rank;
  final _Stats attenuationResiduals;
  final double? medianPickDistanceKm;

  const _LocationDiagnostics({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.errorKm,
    required this.applied,
    required this.score,
    required this.travelTimeResiduals,
    required this.rank,
    required this.attenuationResiduals,
    required this.medianPickDistanceKm,
  });

  factory _LocationDiagnostics.forLocation({
    required String label,
    required double latitude,
    required double longitude,
    required double truthLat,
    required double truthLng,
    required List<_Pick> picks,
    bool? applied,
    double? score,
  }) {
    final distances = [
      for (final pick in picks)
        _haversineKm(latitude, longitude, pick.latitude, pick.longitude),
    ];
    final minDistance = distances.isEmpty ? 0.0 : distances.reduce(math.min);
    final travelResiduals = <double>[];
    final attenuationTerms = <double>[];
    for (var i = 0; i < picks.length; i++) {
      final predicted = (distances[i] - minDistance) / _waveSpeedKmPerSec;
      travelResiduals.add(picks[i].observedDelaySeconds - predicted);
      final value = picks[i].value;
      if (value != null && value.isFinite) {
        attenuationTerms.add(
          value +
              _attenuationLogDistanceCoefficient *
                  _log10(distances[i] + _attenuationNearDistanceKm) +
              _attenuationLinearDistanceCoefficient * distances[i],
        );
      }
    }
    final sourceScale = _median(attenuationTerms);
    final attenuationResiduals = sourceScale == null
        ? const <double>[]
        : [for (final term in attenuationTerms) term - sourceScale];

    return _LocationDiagnostics(
      label: label,
      latitude: latitude,
      longitude: longitude,
      errorKm: _haversineKm(latitude, longitude, truthLat, truthLng),
      applied: applied,
      score: score,
      travelTimeResiduals: _Stats.fromValues(travelResiduals),
      rank: _RankStats.fromInputs(picks, distances),
      attenuationResiduals: _Stats.fromValues(attenuationResiduals),
      medianPickDistanceKm: _median(distances),
    );
  }

  Map<String, Object?> toJson() => {
    'label': label,
    'latitude': latitude,
    'longitude': longitude,
    'errorKm': errorKm,
    'applied': applied,
    'score': score,
    'travelTimeResiduals': travelTimeResiduals.toJson(unit: 'seconds'),
    'rank': rank.toJson(),
    'attenuationResiduals': attenuationResiduals.toJson(
      unit: 'intensity_units',
    ),
    'medianPickDistanceKm': medianPickDistanceKm,
  };
}

class _Pick {
  final String code;
  final String network;
  final double latitude;
  final double longitude;
  final double observedDelaySeconds;
  final double? value;
  final double? activity;
  final int? ascend;

  const _Pick({
    required this.code,
    required this.network,
    required this.latitude,
    required this.longitude,
    required this.observedDelaySeconds,
    required this.value,
    required this.activity,
    required this.ascend,
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
  };
}

class _CandidatePoint {
  final double latitude;
  final double longitude;
  final bool applied;
  final double? score;

  const _CandidatePoint({
    required this.latitude,
    required this.longitude,
    required this.applied,
    required this.score,
  });
}

class _Stats {
  final double? mean;
  final double? meanAbs;
  final double? rms;
  final double? maxAbs;

  const _Stats({
    required this.mean,
    required this.meanAbs,
    required this.rms,
    required this.maxAbs,
  });

  factory _Stats.fromValues(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList();
    if (list.isEmpty) {
      return const _Stats(mean: null, meanAbs: null, rms: null, maxAbs: null);
    }
    final sum = list.fold<double>(0, (total, value) => total + value);
    final abs = list.map((value) => value.abs()).toList();
    final square = list.fold<double>(
      0,
      (total, value) => total + value * value,
    );
    return _Stats(
      mean: sum / list.length,
      meanAbs:
          abs.fold<double>(0, (total, value) => total + value) / list.length,
      rms: math.sqrt(square / list.length),
      maxAbs: abs.reduce(math.max),
    );
  }

  Map<String, Object?> toJson({required String unit}) => {
    'unit': unit,
    'mean': mean,
    'meanAbs': meanAbs,
    'rms': rms,
    'maxAbs': maxAbs,
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

  factory _RankStats.fromInputs(List<_Pick> picks, List<double> distancesKm) {
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

List<String> _findings(List<_EarlyFrame> frames) {
  if (frames.isEmpty) return const ['no_early_estimate_frames'];
  final findings = <String>[];
  if (frames.any((frame) => !frame.truthInsideSearchBox)) {
    findings.add('truth_outside_search_box_in_early_frames');
  }
  if (frames.any((frame) => frame.geometry['classification'] == 'one_sided')) {
    findings.add('one_sided_early_geometry');
  }
  if (frames.any((frame) => (frame.errorKm ?? 0) >= 150)) {
    findings.add('catastrophic_early_error');
  }
  final candidateFrames = frames.where((frame) => frame.candidate != null);
  if (candidateFrames.isNotEmpty) {
    final improved = candidateFrames.where((frame) => frame.candidateImproves);
    if (improved.length == candidateFrames.length) {
      findings.add('candidate_improves_all_candidate_frames');
    } else {
      findings.add('candidate_has_mixed_early_frame_effect');
    }
  }
  if (frames.any(
    (frame) =>
        (frame.baseline.travelTimeResiduals.rms ?? 0) > 5 &&
        (frame.truth.travelTimeResiduals.rms ?? 0) > 5,
  )) {
    findings.add('large_travel_time_residuals_do_not_uniquely_select_truth');
  }
  return findings;
}

String _markdown(_EarlyFrameReport report) {
  final buffer = StringBuffer()
    ..writeln('# ${report.caseId} Early Frame Report')
    ..writeln()
    ..writeln('Generated from `${report.inputPath}`.')
    ..writeln(
      'This is diagnostic-only; no production estimator weights are changed.',
    )
    ..writeln()
    ..writeln('- Case: `${report.caseId}`')
    ..writeln('- Method: `$_hybridMethod`')
    ..writeln('- Early estimate frames: ${report.frames.length}')
    ..writeln(
      '- Findings: ${report.findings.map((item) => '`$item`').join(', ')}',
    )
    ..writeln()
    ..writeln('## Frame Summary')
    ..writeln()
    ..writeln(
      '| # | Time | Err | Jump | Candidate err | Truth in bbox | Geometry | P90u | Travel RMS base/cand/truth | Rank inv base/cand/truth | Atten RMS base/cand/truth |',
    )
    ..writeln(
      '| ---: | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- |',
    );

  for (var i = 0; i < report.frames.length; i++) {
    final frame = report.frames[i];
    final candidate = frame.candidate;
    buffer.writeln(
      '| ${i + 1} | ${frame.observedAtJst ?? '-'} | '
      '${_format(frame.errorKm, 'km')} | '
      '${_format(frame.jumpKm, 'km')} | '
      '${candidate == null ? '-' : _format(candidate.errorKm, 'km')} | '
      '${frame.truthInsideSearchBox ? 'yes' : 'no'} | '
      '${frame.geometry['classification'] ?? '-'} | '
      '${_format(_number(frame.geometry['horizontalUncertaintyP90Km']), 'km')} | '
      '${_format(frame.baseline.travelTimeResiduals.rms, 's')} / '
      '${_format(candidate?.travelTimeResiduals.rms, 's')} / '
      '${_format(frame.truth.travelTimeResiduals.rms, 's')} | '
      '${_percent(frame.baseline.rank.inversionRate)} / '
      '${candidate == null ? '-' : _percent(candidate.rank.inversionRate)} / '
      '${_percent(frame.truth.rank.inversionRate)} | '
      '${_format(frame.baseline.attenuationResiduals.rms, '')} / '
      '${_format(candidate?.attenuationResiduals.rms, '')} / '
      '${_format(frame.truth.attenuationResiduals.rms, '')} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Interpretation')
    ..writeln()
    ..writeln(
      '- `Candidate err` is the diagnostic centroid-guard candidate when emitted.',
    )
    ..writeln(
      '- Travel RMS uses relative arrival delays with $_waveSpeedKmPerSec km/s.',
    )
    ..writeln(
      '- Atten RMS is within-frame static attenuation scatter, not a trained production score.',
    )
    ..writeln()
    ..writeln('## Candidate Frames')
    ..writeln()
    ..writeln(
      '| Time | Baseline | Candidate | Truth | Baseline err | Candidate err | Travel RMS delta | Atten RMS delta |',
    )
    ..writeln('| --- | --- | --- | --- | ---: | ---: | ---: | ---: |');

  for (final frame in report.frames.where((frame) => frame.candidate != null)) {
    final candidate = frame.candidate!;
    buffer.writeln(
      '| ${frame.observedAtJst ?? '-'} | '
      '${_point(frame.baseline)} | '
      '${_point(candidate)} | '
      '${_point(frame.truth)} | '
      '${_format(frame.baseline.errorKm, 'km')} | '
      '${_format(candidate.errorKm, 'km')} | '
      '${_signedDelta(candidate.travelTimeResiduals.rms, frame.baseline.travelTimeResiduals.rms, 's')} | '
      '${_signedDelta(candidate.attenuationResiduals.rms, frame.baseline.attenuationResiduals.rms, '')} |',
    );
  }

  return buffer.toString();
}

String _point(_LocationDiagnostics location) =>
    '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';

List<_Pick> _picks(
  Map<String, Object?> diagnostics,
  Map<String, _StationMeta> stationIndex,
) {
  final result = <_Pick>[];
  for (final rawPick in _list(diagnostics['top_timing_picks'])) {
    final pick = _map(rawPick);
    final code = pick['code']?.toString();
    final observedDelay = _number(pick['delay_s']);
    if (code == null || observedDelay == null) continue;
    final station = stationIndex[code];
    if (station == null) continue;
    result.add(
      _Pick(
        code: code,
        network: station.network,
        latitude: station.lat,
        longitude: station.lng,
        observedDelaySeconds: observedDelay,
        value: _number(pick['value']),
        activity: _number(pick['activity']),
        ascend: _integer(pick['ascend']),
      ),
    );
  }
  return result;
}

_CandidatePoint? _candidatePoint(
  Map<String, Object?> diagnostics,
  double truthLat,
  double truthLng,
) {
  final corrections = _map(diagnostics['candidate_corrections']);
  final guard = _map(corrections['one_sided_boundary_centroid_guard']);
  final lat = _number(guard['latitude']);
  final lng = _number(guard['longitude']);
  if (lat == null || lng == null) return null;
  return _CandidatePoint(
    latitude: lat,
    longitude: lng,
    applied: guard['applied'] == true,
    score: _number(guard['score']),
  );
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

bool _insideSearchBox(double lat, double lng, List<double> bbox) {
  if (bbox.length != 4) return false;
  return lat >= bbox[0] && lat <= bbox[1] && lng >= bbox[2] && lng <= bbox[3];
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _slug(File file) {
  var name = file.uri.pathSegments.isEmpty
      ? file.path
      : file.uri.pathSegments.last;
  const suffixes = ['.reference.json', '.json'];
  for (final suffix in suffixes) {
    if (name.toLowerCase().endsWith(suffix)) {
      name = name.substring(0, name.length - suffix.length);
      break;
    }
  }
  return name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<double> _numbers(Object? value) =>
    _list(value).map(_number).whereType<double>().toList(growable: false);

double? _median(List<double> values) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180.0;

double _log10(double value) => math.log(value) / math.ln10;

String _format(double? value, String unit) {
  if (value == null || !value.isFinite) return '-';
  final suffix = unit.isEmpty ? '' : ' $unit';
  if (value.abs() >= 100) return '${value.toStringAsFixed(0)}$suffix';
  if (value.abs() >= 10) return '${value.toStringAsFixed(1)}$suffix';
  return '${value.toStringAsFixed(2)}$suffix';
}

String _percent(double? value) {
  if (value == null || !value.isFinite) return '-';
  return '${(value * 100).toStringAsFixed(0)}%';
}

String _signedDelta(double? left, double? right, String unit) {
  if (left == null || right == null || !left.isFinite || !right.isFinite) {
    return '-';
  }
  final delta = left - right;
  final sign = delta >= 0 ? '+' : '';
  final suffix = unit.isEmpty ? '' : ' $unit';
  return '$sign${delta.toStringAsFixed(2)}$suffix';
}
