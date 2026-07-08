import 'dart:convert';
import 'dart:io';

const _hybridMethod = 'nied_gif_hybrid_v1';
const _defaultCaseIds = <String>{
  '20260610_nara_m36',
  '20260621_fukushima_offshore_m32_eq6',
  '20260622_kushiro_offshore_m30_jma',
};

void main(List<String> args) {
  final inputPath =
      _argument(args, '--input') ?? '.dart_tool/source_estimation_benchmark';
  final outputPath =
      _argument(args, '--output') ??
      '.dart_tool/source_estimation_failure_trace/report.json';
  final markdownPath =
      _argument(args, '--markdown') ??
      'docs/baselines/source_estimation_failure_trace.generated.md';
  final requestedCases = _arguments(args, '--case').toSet();
  final selectedCases = requestedCases.isEmpty
      ? _defaultCaseIds
      : requestedCases;

  final input = Directory(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('Benchmark directory does not exist: ${input.path}');
    exitCode = 66;
    return;
  }

  final traces = <_CaseTrace>[];
  for (final file in input.listSync().whereType<File>().where(
    (entry) => entry.path.toLowerCase().endsWith('.json'),
  )) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) continue;
    final report = decoded.cast<String, Object?>();
    final caseData = _map(report['case']);
    final caseId = caseData['caseId']?.toString();
    if (caseId == null || !selectedCases.contains(caseId)) continue;
    traces.add(_CaseTrace.fromReport(file, report));
  }
  traces.sort((left, right) => left.caseId.compareTo(right.caseId));

  final missing = selectedCases.difference(
    traces.map((trace) => trace.caseId).toSet(),
  );
  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 'source_estimation_failure_trace_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'inputDirectory': input.path,
      'method': _hybridMethod,
      'caseCount': traces.length,
      'missingCaseIds': missing.toList()..sort(),
      'cases': traces.map((trace) => trace.toJson()).toList(),
    }),
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(traces, missing));

  stdout.writeln('wrote ${traces.length} source-estimation failure traces');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  if (missing.isNotEmpty) {
    stderr.writeln('missing cases: ${missing.join(', ')}');
    exitCode = 65;
  }
}

class _CaseTrace {
  final String caseId;
  final String reportFile;
  final Map<String, Object?> truth;
  final List<_FrameTrace> frames;
  final Map<String, int> selectedFrameIndexes;
  final List<String> findings;

  const _CaseTrace({
    required this.caseId,
    required this.reportFile,
    required this.truth,
    required this.frames,
    required this.selectedFrameIndexes,
    required this.findings,
  });

  factory _CaseTrace.fromReport(File file, Map<String, Object?> report) {
    final caseData = _map(report['case']);
    final truth = _map(caseData['truth']);
    final frameData = _list(report['frames']);
    final frames = <_FrameTrace>[];
    var previousMembers = <String>{};
    var previousPicks = <String>{};
    var associatedMembers = <String>{};
    String? associatedEventId;

    for (var sourceIndex = 0; sourceIndex < frameData.length; sourceIndex++) {
      final frame = _map(frameData[sourceIndex]);
      final detection = _map(frame['eventDetection']);
      final eventId = detection['eventId']?.toString();
      if (eventId != null && eventId != associatedEventId) {
        associatedEventId = eventId;
        associatedMembers = <String>{};
      }
      associatedMembers.addAll(_strings(detection['memberStationIds']));
      final method = _map(_map(frame['methods'])[_hybridMethod]);
      final estimate = _mapOrNull(method['estimate']);
      if (estimate == null) continue;
      final members = _strings(detection['memberStationIds']).toSet();
      final diagnostics = _map(estimate['diagnostics']);
      final picks = _list(diagnostics['top_timing_picks'])
          .map(_map)
          .map((pick) => pick['code']?.toString())
          .whereType<String>()
          .toSet();
      frames.add(
        _FrameTrace.fromData(
          traceIndex: frames.length,
          sourceFrameIndex: sourceIndex,
          frame: frame,
          method: method,
          estimate: estimate,
          truth: truth,
          previousMembers: previousMembers,
          previousPicks: previousPicks,
          associatedMembers: associatedMembers,
        ),
      );
      previousMembers = members;
      previousPicks = picks;
    }

    final selected = <String, int>{};
    if (frames.isNotEmpty) {
      selected['first'] = 0;
      selected['worst'] = _maxIndex(frames, (frame) => frame.errorKm);
      selected['largest_jump'] = _maxIndex(frames, (frame) => frame.jumpKm);
      selected['final'] = frames.length - 1;
    }

    return _CaseTrace(
      caseId: caseData['caseId']?.toString() ?? file.uri.pathSegments.last,
      reportFile: file.path,
      truth: truth,
      frames: frames,
      selectedFrameIndexes: selected,
      findings: _findings(frames, selected),
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'reportFile': reportFile,
    'truth': truth,
    'estimateFrameCount': frames.length,
    'selectedFrames': {
      for (final entry in selectedFrameIndexes.entries)
        entry.key: frames[entry.value].toJson(),
    },
    'findings': findings,
    'frames': frames.map((frame) => frame.toJson()).toList(),
  };
}

class _FrameTrace {
  final int traceIndex;
  final int sourceFrameIndex;
  final String? observedAt;
  final String? detectionState;
  final List<String> memberStationIds;
  final List<String> addedMembers;
  final List<String> removedMembers;
  final Map<String, Object?> component;
  final double? latitude;
  final double? longitude;
  final double? errorKm;
  final double? jumpKm;
  final double? confidence;
  final int supportingStationCount;
  final Map<String, Object?> scores;
  final Map<String, Object?> stationGeometry;
  final List<double> searchBoundingBox;
  final bool? truthInsideSearchBoundingBox;
  final List<Map<String, Object?>> timingPicks;
  final List<String> timingPickStationIds;
  final List<String> timingPicksInMembers;
  final List<String> timingPicksOutsideMembers;
  final List<String> associatedMemberStationIds;
  final List<String> timingPicksInAssociatedMembers;
  final List<String> timingPicksOutsideAssociatedMembers;
  final List<String> addedTimingPicks;
  final List<String> removedTimingPicks;

  const _FrameTrace({
    required this.traceIndex,
    required this.sourceFrameIndex,
    required this.observedAt,
    required this.detectionState,
    required this.memberStationIds,
    required this.addedMembers,
    required this.removedMembers,
    required this.component,
    required this.latitude,
    required this.longitude,
    required this.errorKm,
    required this.jumpKm,
    required this.confidence,
    required this.supportingStationCount,
    required this.scores,
    required this.stationGeometry,
    required this.searchBoundingBox,
    required this.truthInsideSearchBoundingBox,
    required this.timingPicks,
    required this.timingPickStationIds,
    required this.timingPicksInMembers,
    required this.timingPicksOutsideMembers,
    required this.associatedMemberStationIds,
    required this.timingPicksInAssociatedMembers,
    required this.timingPicksOutsideAssociatedMembers,
    required this.addedTimingPicks,
    required this.removedTimingPicks,
  });

  factory _FrameTrace.fromData({
    required int traceIndex,
    required int sourceFrameIndex,
    required Map<String, Object?> frame,
    required Map<String, Object?> method,
    required Map<String, Object?> estimate,
    required Map<String, Object?> truth,
    required Set<String> previousMembers,
    required Set<String> previousPicks,
    required Set<String> associatedMembers,
  }) {
    final detection = _map(frame['eventDetection']);
    final metadata = _map(detection['metadata']);
    final members = _strings(detection['memberStationIds']).toSet();
    final diagnostics = _map(estimate['diagnostics']);
    final timingPicks = _list(diagnostics['top_timing_picks'])
        .map(_map)
        .map(
          (pick) => <String, Object?>{
            'code': pick['code']?.toString(),
            'delaySeconds': _number(pick['delay_s']),
            'value': _number(pick['value']),
            'activity': _number(pick['activity']),
            'ascend': _integer(pick['ascend']),
          },
        )
        .toList();
    final picks = timingPicks
        .map((pick) => pick['code']?.toString())
        .whereType<String>()
        .toSet();
    final bbox = _numbers(diagnostics['search_bbox']);
    final truthLatitude = _number(truth['latitude']);
    final truthLongitude = _number(truth['longitude']);

    return _FrameTrace(
      traceIndex: traceIndex,
      sourceFrameIndex: sourceFrameIndex,
      observedAt: frame['observedAtJst']?.toString(),
      detectionState: detection['state']?.toString(),
      memberStationIds: _sorted(members),
      addedMembers: _sorted(members.difference(previousMembers)),
      removedMembers: _sorted(previousMembers.difference(members)),
      component: {
        'size': _integer(metadata['largestComponentSize']),
        'diameterKm': _number(metadata['largestComponentDiameterKm']),
        'triggerTimeSpanSeconds': _number(
          metadata['largestComponentTriggerTimeSpanSeconds'],
        ),
        'centroidLatitude': _number(
          metadata['largestComponentCentroidLatitude'],
        ),
        'centroidLongitude': _number(
          metadata['largestComponentCentroidLongitude'],
        ),
      },
      latitude: _number(estimate['latitude']),
      longitude: _number(estimate['longitude']),
      errorKm: _number(method['errorKm']),
      jumpKm: _number(method['jumpKm']),
      confidence: _number(estimate['confidence']),
      supportingStationCount: _integer(estimate['supportingStationCount']) ?? 0,
      scores: {
        'time': _number(diagnostics['time_score']),
        'rank': _number(diagnostics['rank_score']),
        'final': _number(diagnostics['final_score']),
        'referenceDistanceKm': _number(diagnostics['reference_distance_km']),
      },
      stationGeometry: {
        'classification': diagnostics['station_geometry']?.toString(),
        'azimuthalGapDeg': _number(diagnostics['station_azimuthal_gap_deg']),
        'nearestStationDistanceKm': _number(
          diagnostics['nearest_station_distance_km'],
        ),
        'searchBoundaryMarginDeg': _number(
          diagnostics['search_boundary_margin_deg'],
        ),
        'searchBoundaryHit': diagnostics['search_boundary_hit'] == true,
      },
      searchBoundingBox: bbox,
      truthInsideSearchBoundingBox: _insideBoundingBox(
        bbox,
        truthLatitude,
        truthLongitude,
      ),
      timingPicks: timingPicks,
      timingPickStationIds: _sorted(picks),
      timingPicksInMembers: _sorted(picks.intersection(members)),
      timingPicksOutsideMembers: _sorted(picks.difference(members)),
      associatedMemberStationIds: _sorted(associatedMembers),
      timingPicksInAssociatedMembers: _sorted(
        picks.intersection(associatedMembers),
      ),
      timingPicksOutsideAssociatedMembers: _sorted(
        picks.difference(associatedMembers),
      ),
      addedTimingPicks: _sorted(picks.difference(previousPicks)),
      removedTimingPicks: _sorted(previousPicks.difference(picks)),
    );
  }

  double get timingPickMemberOverlap => timingPickStationIds.isEmpty
      ? 0
      : timingPicksInMembers.length / timingPickStationIds.length;

  double get timingPickAssociatedMemberOverlap => timingPickStationIds.isEmpty
      ? 0
      : timingPicksInAssociatedMembers.length / timingPickStationIds.length;

  Map<String, Object?> toJson() => {
    'traceIndex': traceIndex,
    'sourceFrameIndex': sourceFrameIndex,
    'observedAtJst': observedAt,
    'detectionState': detectionState,
    'memberStationIds': memberStationIds,
    'addedMembers': addedMembers,
    'removedMembers': removedMembers,
    'component': component,
    'estimate': {
      'latitude': latitude,
      'longitude': longitude,
      'errorKm': errorKm,
      'jumpKm': jumpKm,
      'confidence': confidence,
      'supportingStationCount': supportingStationCount,
    },
    'scores': scores,
    'stationGeometry': stationGeometry,
    'searchBoundingBox': searchBoundingBox,
    'truthInsideSearchBoundingBox': truthInsideSearchBoundingBox,
    'timingPicks': timingPicks,
    'timingPickStationIds': timingPickStationIds,
    'timingPicksInMembers': timingPicksInMembers,
    'timingPicksOutsideMembers': timingPicksOutsideMembers,
    'timingPickMemberOverlap': timingPickMemberOverlap,
    'associatedMemberStationIds': associatedMemberStationIds,
    'timingPicksInAssociatedMembers': timingPicksInAssociatedMembers,
    'timingPicksOutsideAssociatedMembers': timingPicksOutsideAssociatedMembers,
    'timingPickAssociatedMemberOverlap': timingPickAssociatedMemberOverlap,
    'addedTimingPicks': addedTimingPicks,
    'removedTimingPicks': removedTimingPicks,
  };
}

List<String> _findings(List<_FrameTrace> frames, Map<String, int> selected) {
  if (frames.isEmpty) return const ['hybrid_emitted_no_estimates'];
  final findings = <String>[];
  final lowOverlapCount = frames
      .where((frame) => frame.timingPickAssociatedMemberOverlap < 0.5)
      .length;
  if (lowOverlapCount > frames.length / 2) {
    findings.add('timing_pick_scope_mismatch');
  }
  final outsideSearchCount = frames
      .where((frame) => frame.truthInsideSearchBoundingBox == false)
      .length;
  if (outsideSearchCount > 0) {
    findings.add('truth_outside_search_bbox');
  }
  final selectedFrames = selected.values.map((index) => frames[index]);
  if (selectedFrames.any(
    (frame) =>
        frame.stationGeometry['classification'] == 'one_sided' &&
        frame.stationGeometry['searchBoundaryHit'] == true,
  )) {
    findings.add('one_sided_boundary_solution');
  }
  final worst = frames[selected['worst']!];
  if (worst.errorKm != null && worst.errorKm! >= 150) {
    findings.add('catastrophic_frame_error');
  }
  final largestJump = frames[selected['largest_jump']!];
  if ((largestJump.jumpKm ?? 0) >= 60) {
    findings.add('large_interframe_jump');
  }
  if (largestJump.addedMembers.isNotEmpty ||
      largestJump.removedMembers.isNotEmpty) {
    findings.add('membership_changed_at_largest_jump');
  }
  if (largestJump.addedTimingPicks.isNotEmpty ||
      largestJump.removedTimingPicks.isNotEmpty) {
    findings.add('timing_picks_changed_at_largest_jump');
  }
  return findings;
}

String _markdown(List<_CaseTrace> traces, Set<String> missing) {
  final buffer = StringBuffer()
    ..writeln('# Source Estimation Failure Trace')
    ..writeln()
    ..writeln('Generated from existing benchmark frame diagnostics.')
    ..writeln('No production estimator weights are changed by this report.')
    ..writeln();
  if (missing.isNotEmpty) {
    buffer
      ..writeln('Missing cases: `${missing.join('`, `')}`.')
      ..writeln();
  }
  for (final trace in traces) {
    buffer
      ..writeln('## `${trace.caseId}`')
      ..writeln()
      ..writeln('- Estimate frames: ${trace.frames.length}')
      ..writeln(
        '- Findings: ${trace.findings.map((item) => '`$item`').join(', ')}',
      )
      ..writeln()
      ..writeln(
        '| Frame | Time | Error km | Jump km | Members (+/-) | Picks in event | Truth in search | Estimate |',
      )
      ..writeln('| --- | --- | ---: | ---: | --- | ---: | --- | --- |');
    for (final entry in trace.selectedFrameIndexes.entries) {
      final frame = trace.frames[entry.value];
      buffer.writeln(
        '| ${entry.key} | ${frame.observedAt ?? '-'} | '
        '${_format(frame.errorKm)} | ${_format(frame.jumpKm)} | '
        '${frame.memberStationIds.length} '
        '(+${frame.addedMembers.length}/-${frame.removedMembers.length}) | '
        '${frame.timingPicksInAssociatedMembers.length}/${frame.timingPickStationIds.length} | '
        '${frame.truthInsideSearchBoundingBox ?? '-'} | '
        '${_coordinate(frame.latitude, frame.longitude)} |',
      );
    }
    buffer.writeln();

    for (final entry in trace.selectedFrameIndexes.entries) {
      final frame = trace.frames[entry.value];
      buffer
        ..writeln('### ${entry.key.replaceAll('_', ' ')}')
        ..writeln()
        ..writeln('- Time: `${frame.observedAt}`')
        ..writeln(
          '- Member changes: +`${frame.addedMembers.join(', ')}` '
          '-`${frame.removedMembers.join(', ')}`',
        )
        ..writeln(
          '- Timing picks inside members: '
          '`${frame.timingPicksInMembers.join(', ')}`',
        )
        ..writeln(
          '- Timing picks outside members: '
          '`${frame.timingPicksOutsideMembers.join(', ')}`',
        )
        ..writeln(
          '- Timing picks outside accumulated event membership: '
          '`${frame.timingPicksOutsideAssociatedMembers.join(', ')}`',
        )
        ..writeln(
          '- Component centroid: '
          '${_coordinate(_number(frame.component['centroidLatitude']), _number(frame.component['centroidLongitude']))}',
        )
        ..writeln(
          '- Scores: time ${_format(_number(frame.scores['time']))}, '
          'rank ${_format(_number(frame.scores['rank']))}, '
          'final ${_format(_number(frame.scores['final']))}',
        )
        ..writeln(
          '- Geometry: `${frame.stationGeometry['classification'] ?? '-'}`, '
          'azimuthal gap '
          '${_format(_number(frame.stationGeometry['azimuthalGapDeg']))} deg, '
          'nearest station '
          '${_format(_number(frame.stationGeometry['nearestStationDistanceKm']))} km, '
          'boundary margin '
          '${_format(_number(frame.stationGeometry['searchBoundaryMarginDeg']))} deg',
        )
        ..writeln();
    }
  }
  return buffer.toString();
}

int _maxIndex(List<_FrameTrace> frames, double? Function(_FrameTrace) value) {
  var bestIndex = 0;
  var bestValue = double.negativeInfinity;
  for (var index = 0; index < frames.length; index++) {
    final candidate = value(frames[index]) ?? double.negativeInfinity;
    if (candidate > bestValue) {
      bestIndex = index;
      bestValue = candidate;
    }
  }
  return bestIndex;
}

bool? _insideBoundingBox(
  List<double> bbox,
  double? latitude,
  double? longitude,
) {
  if (bbox.length != 4 || latitude == null || longitude == null) return null;
  return latitude >= bbox[0] &&
      latitude <= bbox[1] &&
      longitude >= bbox[2] &&
      longitude <= bbox[3];
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
}

List<String> _arguments(List<String> args, String name) {
  final values = <String>[];
  for (var index = 0; index < args.length - 1; index++) {
    if (args[index] == name) values.add(args[index + 1]);
  }
  return values;
}

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : <String, Object?>{};

Map<String, Object?>? _mapOrNull(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

double? _number(Object? value) => value is num ? value.toDouble() : null;

int? _integer(Object? value) => value is num ? value.toInt() : null;

List<double> _numbers(Object? value) =>
    _list(value).whereType<num>().map((item) => item.toDouble()).toList();

List<String> _strings(Object? value) =>
    _list(value).map((item) => item.toString()).toList();

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

String _format(double? value) => value == null ? '-' : value.toStringAsFixed(1);

String _coordinate(double? latitude, double? longitude) =>
    latitude == null || longitude == null
    ? '-'
    : '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
