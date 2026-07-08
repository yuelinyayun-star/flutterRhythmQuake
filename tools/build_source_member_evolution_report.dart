import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _methodId = 'nied_gif_hybrid_v1';
const _defaultInput =
    '.dart_tool/source_estimation_benchmark/20260621_fukushima_offshore_m32_eq6.reference.json';
const _defaultOutput =
    '.dart_tool/source_member_evolution/fukushima_miyagi_m32.json';
const _defaultMarkdown =
    'docs/baselines/fukushima_miyagi_m32_member_evolution.generated.md';

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

  final report = _MemberEvolutionReport.fromBenchmark(
    input,
    decoded.cast<String, Object?>(),
    _stationIndex(),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote member-evolution report for ${report.caseId}');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

class _MemberEvolutionReport {
  final String caseId;
  final String inputPath;
  final Map<String, Object?> truth;
  final List<_FrameEvolution> frames;
  final Map<String, int> selectedFrameIndexes;
  final List<String> findings;

  const _MemberEvolutionReport({
    required this.caseId,
    required this.inputPath,
    required this.truth,
    required this.frames,
    required this.selectedFrameIndexes,
    required this.findings,
  });

  factory _MemberEvolutionReport.fromBenchmark(
    File input,
    Map<String, Object?> report,
    Map<String, _StationMeta> stationIndex,
  ) {
    final caseData = _map(report['case']);
    final truth = _map(caseData['truth']);
    final truthLat = _number(truth['latitude']);
    final truthLng = _number(truth['longitude']);
    if (truthLat == null || truthLng == null) {
      throw const FormatException('truth latitude/longitude is required');
    }

    final frames = <_FrameEvolution>[];
    var previousMembers = <String>{};
    String? previousEventId;
    var previousEstimateLatLng = (lat: null as double?, lng: null as double?);
    for (var index = 0; index < _list(report['frames']).length; index++) {
      final frame = _map(_list(report['frames'])[index]);
      final detection = _mapOrNull(frame['eventDetection']);
      if (detection == null) continue;
      final members = _strings(detection['memberStationIds']).toSet();
      if (members.isEmpty) continue;
      final method = _map(_map(frame['methods'])[_methodId]);
      final estimate = _mapOrNull(method['estimate']);
      final diagnostics = _map(estimate?['diagnostics']);
      final estimateLat = _number(estimate?['latitude']);
      final estimateLng = _number(estimate?['longitude']);
      final estimateJumpKm =
          estimateLat != null &&
              estimateLng != null &&
              previousEstimateLatLng.lat != null &&
              previousEstimateLatLng.lng != null
          ? _haversineKm(
              previousEstimateLatLng.lat!,
              previousEstimateLatLng.lng!,
              estimateLat,
              estimateLng,
            )
          : null;
      final evolution = _FrameEvolution.fromData(
        frameIndex: index,
        frame: frame,
        detection: detection,
        estimate: estimate,
        diagnostics: diagnostics,
        truthLat: truthLat,
        truthLng: truthLng,
        stationIndex: stationIndex,
        previousMembers: previousMembers,
        previousEventId: previousEventId,
        estimateJumpKm: estimateJumpKm ?? _number(method['jumpKm']),
      );
      frames.add(evolution);
      previousMembers = members;
      previousEventId = detection['eventId']?.toString();
      if (estimateLat != null && estimateLng != null) {
        previousEstimateLatLng = (lat: estimateLat, lng: estimateLng);
      }
    }

    final selected = <String, int>{};
    if (frames.isNotEmpty) {
      selected['first_detection'] = 0;
      final firstEstimate = _firstIndex(frames, (frame) => frame.hasEstimate);
      if (firstEstimate != null) selected['first_estimate'] = firstEstimate;
      final eventReplacement = _firstIndex(
        frames,
        (frame) => frame.eventIdChanged,
      );
      if (eventReplacement != null) {
        selected['event_replacement'] = eventReplacement;
      }
      selected['largest_member_turnover'] = _maxIndex(
        frames,
        (frame) => frame.memberTurnoverCount.toDouble(),
      );
      selected['largest_estimate_jump'] = _maxIndex(
        frames,
        (frame) => frame.estimateJumpKm,
      );
      selected['worst_error'] = _maxIndex(frames, (frame) => frame.errorKm);
      selected['final_detection'] = frames.length - 1;
    }

    return _MemberEvolutionReport(
      caseId: caseData['caseId']?.toString() ?? input.uri.pathSegments.last,
      inputPath: input.path,
      truth: truth,
      frames: frames,
      selectedFrameIndexes: selected,
      findings: _findings(frames, selected),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'source_member_evolution_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'caseId': caseId,
    'inputPath': inputPath,
    'method': _methodId,
    'truth': truth,
    'frameCount': frames.length,
    'estimateFrameCount': frames.where((frame) => frame.hasEstimate).length,
    'selectedFrames': {
      for (final entry in selectedFrameIndexes.entries)
        entry.key: frames[entry.value].toJson(),
    },
    'findings': findings,
    'frames': frames.map((frame) => frame.toJson()).toList(),
  };
}

class _FrameEvolution {
  final int frameIndex;
  final String? observedAtJst;
  final String? eventId;
  final String? previousEventId;
  final bool eventIdChanged;
  final String? state;
  final int activeStationCount;
  final int memberCount;
  final List<String> members;
  final List<String> addedMembers;
  final List<String> removedMembers;
  final double? memberCentroidLatitude;
  final double? memberCentroidLongitude;
  final double? memberCentroidDistanceToTruthKm;
  final double? componentCentroidLatitude;
  final double? componentCentroidLongitude;
  final double? componentCentroidDistanceToTruthKm;
  final int? largestComponentSize;
  final double? largestComponentDiameterKm;
  final double? largestComponentTriggerSpanSeconds;
  final List<String> largestComponentStationIds;
  final double? estimateLatitude;
  final double? estimateLongitude;
  final double? errorKm;
  final double? estimateJumpKm;
  final List<double> searchBoundingBox;
  final bool? truthInsideSearchBoundingBox;
  final List<String> timingPickStationIds;
  final List<String> timingPicksOutsideMembers;
  final Map<String, Object?> geometry;

  const _FrameEvolution({
    required this.frameIndex,
    required this.observedAtJst,
    required this.eventId,
    required this.previousEventId,
    required this.eventIdChanged,
    required this.state,
    required this.activeStationCount,
    required this.memberCount,
    required this.members,
    required this.addedMembers,
    required this.removedMembers,
    required this.memberCentroidLatitude,
    required this.memberCentroidLongitude,
    required this.memberCentroidDistanceToTruthKm,
    required this.componentCentroidLatitude,
    required this.componentCentroidLongitude,
    required this.componentCentroidDistanceToTruthKm,
    required this.largestComponentSize,
    required this.largestComponentDiameterKm,
    required this.largestComponentTriggerSpanSeconds,
    required this.largestComponentStationIds,
    required this.estimateLatitude,
    required this.estimateLongitude,
    required this.errorKm,
    required this.estimateJumpKm,
    required this.searchBoundingBox,
    required this.truthInsideSearchBoundingBox,
    required this.timingPickStationIds,
    required this.timingPicksOutsideMembers,
    required this.geometry,
  });

  factory _FrameEvolution.fromData({
    required int frameIndex,
    required Map<String, Object?> frame,
    required Map<String, Object?> detection,
    required Map<String, Object?>? estimate,
    required Map<String, Object?> diagnostics,
    required double truthLat,
    required double truthLng,
    required Map<String, _StationMeta> stationIndex,
    required Set<String> previousMembers,
    required String? previousEventId,
    required double? estimateJumpKm,
  }) {
    final metadata = _map(detection['metadata']);
    final members = _strings(detection['memberStationIds']).toSet();
    final memberCentroid = _centroid(members, stationIndex);
    final componentLat = _number(metadata['largestComponentCentroidLatitude']);
    final componentLng = _number(metadata['largestComponentCentroidLongitude']);
    final bbox = _numbers(diagnostics['search_bbox']);
    final picks = _list(diagnostics['top_timing_picks'])
        .map(_map)
        .map((pick) => pick['code']?.toString())
        .whereType<String>()
        .toSet();

    return _FrameEvolution(
      frameIndex: frameIndex,
      observedAtJst: frame['observedAtJst']?.toString(),
      eventId: detection['eventId']?.toString(),
      previousEventId: previousEventId,
      eventIdChanged:
          previousEventId != null &&
          previousEventId != detection['eventId']?.toString(),
      state: detection['state']?.toString(),
      activeStationCount: _integer(frame['activeStationCount']) ?? 0,
      memberCount: members.length,
      members: _sorted(members),
      addedMembers: _sorted(members.difference(previousMembers)),
      removedMembers: _sorted(previousMembers.difference(members)),
      memberCentroidLatitude: memberCentroid?.lat,
      memberCentroidLongitude: memberCentroid?.lng,
      memberCentroidDistanceToTruthKm: memberCentroid == null
          ? null
          : _haversineKm(
              memberCentroid.lat,
              memberCentroid.lng,
              truthLat,
              truthLng,
            ),
      componentCentroidLatitude: componentLat,
      componentCentroidLongitude: componentLng,
      componentCentroidDistanceToTruthKm:
          componentLat == null || componentLng == null
          ? null
          : _haversineKm(componentLat, componentLng, truthLat, truthLng),
      largestComponentSize: _integer(metadata['largestComponentSize']),
      largestComponentDiameterKm: _number(
        metadata['largestComponentDiameterKm'],
      ),
      largestComponentTriggerSpanSeconds: _number(
        metadata['largestComponentTriggerTimeSpanSeconds'],
      ),
      largestComponentStationIds: _strings(
        metadata['largestComponentStationIds'],
      ),
      estimateLatitude: _number(estimate?['latitude']),
      estimateLongitude: _number(estimate?['longitude']),
      errorKm: _number(
        _map(frame['methods'])[_methodId] is Map
            ? _map(_map(frame['methods'])[_methodId])['errorKm']
            : null,
      ),
      estimateJumpKm: estimateJumpKm,
      searchBoundingBox: bbox,
      truthInsideSearchBoundingBox: _insideBoundingBox(
        bbox,
        truthLat,
        truthLng,
      ),
      timingPickStationIds: _sorted(picks),
      timingPicksOutsideMembers: _sorted(picks.difference(members)),
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
        'horizontalUncertaintyP90Km': _number(
          diagnostics['horizontal_uncertainty_p90_km'],
        ),
      },
    );
  }

  bool get hasEstimate => estimateLatitude != null && estimateLongitude != null;

  int get memberTurnoverCount => addedMembers.length + removedMembers.length;

  Map<String, Object?> toJson() => {
    'frameIndex': frameIndex,
    'observedAtJst': observedAtJst,
    'eventId': eventId,
    'previousEventId': previousEventId,
    'eventIdChanged': eventIdChanged,
    'state': state,
    'activeStationCount': activeStationCount,
    'memberCount': memberCount,
    'members': members,
    'addedMembers': addedMembers,
    'removedMembers': removedMembers,
    'memberTurnoverCount': memberTurnoverCount,
    'memberCentroid': {
      'latitude': memberCentroidLatitude,
      'longitude': memberCentroidLongitude,
      'distanceToTruthKm': memberCentroidDistanceToTruthKm,
    },
    'largestComponent': {
      'size': largestComponentSize,
      'diameterKm': largestComponentDiameterKm,
      'triggerSpanSeconds': largestComponentTriggerSpanSeconds,
      'centroidLatitude': componentCentroidLatitude,
      'centroidLongitude': componentCentroidLongitude,
      'centroidDistanceToTruthKm': componentCentroidDistanceToTruthKm,
      'stationIds': largestComponentStationIds,
    },
    'estimate': {
      'latitude': estimateLatitude,
      'longitude': estimateLongitude,
      'errorKm': errorKm,
      'jumpKm': estimateJumpKm,
    },
    'searchBoundingBox': searchBoundingBox,
    'truthInsideSearchBoundingBox': truthInsideSearchBoundingBox,
    'timingPickStationIds': timingPickStationIds,
    'timingPicksOutsideMembers': timingPicksOutsideMembers,
    'geometry': geometry,
  };
}

class _StationMeta {
  final double lat;
  final double lng;

  const _StationMeta({required this.lat, required this.lng});
}

class _LatLng {
  final double lat;
  final double lng;

  const _LatLng(this.lat, this.lng);
}

Map<String, _StationMeta> _stationIndex() {
  final result = <String, _StationMeta>{};
  for (final station in NiedStationDb.stations) {
    final code = station['code']?.toString();
    final lat = _number(station['lat']);
    final lng = _number(station['lng']);
    if (code == null || lat == null || lng == null) continue;
    result[code] = _StationMeta(lat: lat, lng: lng);
  }
  return result;
}

List<String> _findings(
  List<_FrameEvolution> frames,
  Map<String, int> selected,
) {
  if (frames.isEmpty) return const ['no_source_trigger_frames'];
  final findings = <String>[];
  final largestJump = selected['largest_estimate_jump'] == null
      ? null
      : frames[selected['largest_estimate_jump']!];
  if ((largestJump?.estimateJumpKm ?? 0) >= 100) {
    findings.add('large_estimate_jump');
  }
  if ((largestJump?.memberTurnoverCount ?? 0) >= 5) {
    findings.add('member_turnover_at_largest_jump');
  }
  if (frames.any((frame) => frame.eventIdChanged)) {
    findings.add('source_event_replacement');
  }
  final truthOutsideCount = frames
      .where((frame) => frame.hasEstimate)
      .where((frame) => frame.truthInsideSearchBoundingBox == false)
      .length;
  if (truthOutsideCount > 0) {
    findings.add('truth_outside_estimator_search_box');
  }
  final lateFarCentroids = frames
      .where((frame) => (frame.memberCentroidDistanceToTruthKm ?? 0) >= 250)
      .length;
  if (lateFarCentroids >= 3) {
    findings.add('member_centroid_drifted_far_from_truth');
  }
  return findings;
}

String _markdown(_MemberEvolutionReport report) {
  final selected = report.selectedFrameIndexes.entries.toList();
  final largestJumpIndex = report.selectedFrameIndexes['largest_estimate_jump'];
  final window = largestJumpIndex == null
      ? <_FrameEvolution>[]
      : report.frames
            .where(
              (frame) =>
                  frame.frameIndex >=
                      report.frames[largestJumpIndex].frameIndex - 4 &&
                  frame.frameIndex <=
                      report.frames[largestJumpIndex].frameIndex + 4,
            )
            .toList();

  final buffer = StringBuffer()
    ..writeln('# ${report.caseId} Member Evolution')
    ..writeln()
    ..writeln('Generated from `${report.inputPath}`.')
    ..writeln('No production estimator weights are changed by this report.')
    ..writeln()
    ..writeln('- Case: `${report.caseId}`')
    ..writeln('- Source-trigger frames: ${report.frames.length}')
    ..writeln(
      '- Estimate frames: ${report.frames.where((frame) => frame.hasEstimate).length}',
    )
    ..writeln(
      '- Findings: ${report.findings.map((item) => '`$item`').join(', ')}',
    )
    ..writeln()
    ..writeln('## Selected Frames')
    ..writeln()
    ..writeln(
      '| Frame | Time | State | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Truth in search | Picks outside members | Geometry |',
    )
    ..writeln(
      '| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- |',
    );
  for (final entry in selected) {
    final frame = report.frames[entry.value];
    buffer.writeln(_frameRow(entry.key, frame));
  }

  if (window.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Largest Jump Window')
      ..writeln()
      ..writeln('Rows marked with `*` changed source event ID.')
      ..writeln()
      ..writeln(
        '| Index | Time | Members (+/-) | Member centroid dist | Component dist | Estimate err/jump | Members |',
      )
      ..writeln('| ---: | --- | ---: | ---: | ---: | ---: | --- |');
    for (final frame in window) {
      buffer.writeln(
        '| ${frame.frameIndex}${frame.eventIdChanged ? ' *' : ''} | ${frame.observedAtJst ?? '-'} | '
        '${frame.memberCount} (+${frame.addedMembers.length}/-${frame.removedMembers.length}) | '
        '${_format(frame.memberCentroidDistanceToTruthKm, 'km')} | '
        '${_format(frame.componentCentroidDistanceToTruthKm, 'km')} | '
        '${_format(frame.errorKm, 'km')} / ${_format(frame.estimateJumpKm, 'km')} | '
        '`${_compactList(frame.members, limit: 8)}` |',
      );
    }
  }

  final jumpFrame = largestJumpIndex == null
      ? null
      : report.frames[largestJumpIndex];
  if (jumpFrame != null) {
    buffer
      ..writeln()
      ..writeln('## Largest Jump Detail')
      ..writeln()
      ..writeln('- Time: `${jumpFrame.observedAtJst}`')
      ..writeln('- Event ID: `${jumpFrame.eventId}`')
      ..writeln('- Added members: `${jumpFrame.addedMembers.join(', ')}`')
      ..writeln('- Removed members: `${jumpFrame.removedMembers.join(', ')}`')
      ..writeln(
        '- Largest component stations: `${jumpFrame.largestComponentStationIds.join(', ')}`',
      )
      ..writeln(
        '- Timing picks outside current members: `${jumpFrame.timingPicksOutsideMembers.join(', ')}`',
      );
  }

  final eventReplacementIndex =
      report.selectedFrameIndexes['event_replacement'];
  final eventReplacement = eventReplacementIndex == null
      ? null
      : report.frames[eventReplacementIndex];
  if (eventReplacement != null) {
    buffer
      ..writeln()
      ..writeln('## Event Replacement Detail')
      ..writeln()
      ..writeln('- Time: `${eventReplacement.observedAtJst}`')
      ..writeln('- Previous event ID: `${eventReplacement.previousEventId}`')
      ..writeln('- New event ID: `${eventReplacement.eventId}`')
      ..writeln(
        '- New member centroid distance to truth: '
        '${_format(eventReplacement.memberCentroidDistanceToTruthKm, 'km')}',
      )
      ..writeln('- New members: `${eventReplacement.members.join(', ')}`');
  }

  return buffer.toString();
}

String _frameRow(String label, _FrameEvolution frame) {
  return '| `$label` | ${frame.observedAtJst ?? '-'} | ${frame.state ?? '-'} | '
      '${frame.memberCount} (+${frame.addedMembers.length}/-${frame.removedMembers.length}) | '
      '${_format(frame.memberCentroidDistanceToTruthKm, 'km')} | '
      '${_format(frame.componentCentroidDistanceToTruthKm, 'km')} | '
      '${_format(frame.errorKm, 'km')} / ${_format(frame.estimateJumpKm, 'km')} | '
      '${frame.truthInsideSearchBoundingBox ?? '-'} | '
      '${frame.timingPicksOutsideMembers.length}/${frame.timingPickStationIds.length} | '
      '${frame.geometry['classification'] ?? '-'} |';
}

String? _argument(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    if (args[index] == name && index + 1 < args.length) {
      return args[index + 1];
    }
    if (args[index].startsWith('$name=')) {
      return args[index].substring(name.length + 1);
    }
  }
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) => value is Iterable
    ? value.map((item) => item.toString()).toList()
    : const [];

List<double> _numbers(Object? value) => value is Iterable
    ? value.map(_number).whereType<double>().toList(growable: false)
    : const [];

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

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

int? _firstIndex(
  List<_FrameEvolution> frames,
  bool Function(_FrameEvolution frame) predicate,
) {
  for (var index = 0; index < frames.length; index++) {
    if (predicate(frames[index])) return index;
  }
  return null;
}

int _maxIndex(
  List<_FrameEvolution> frames,
  double? Function(_FrameEvolution frame) value,
) {
  var bestIndex = 0;
  var bestValue = double.negativeInfinity;
  for (var index = 0; index < frames.length; index++) {
    final candidate = value(frames[index]);
    if (candidate == null) continue;
    if (candidate > bestValue) {
      bestIndex = index;
      bestValue = candidate;
    }
  }
  return bestIndex;
}

_LatLng? _centroid(
  Set<String> members,
  Map<String, _StationMeta> stationIndex,
) {
  var latSum = 0.0;
  var lngSum = 0.0;
  var count = 0;
  for (final member in members) {
    final station = stationIndex[member];
    if (station == null) continue;
    latSum += station.lat;
    lngSum += station.lng;
    count++;
  }
  return count == 0 ? null : _LatLng(latSum / count, lngSum / count);
}

bool? _insideBoundingBox(List<double> bbox, double latitude, double longitude) {
  if (bbox.length != 4) return null;
  return latitude >= bbox[0] &&
      latitude <= bbox[1] &&
      longitude >= bbox[2] &&
      longitude <= bbox[3];
}

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

double _degToRad(double degrees) => degrees * math.pi / 180.0;

String _format(Object? value, String unit) {
  final number = _number(value);
  if (number == null || !number.isFinite) return '-';
  final suffix = unit.isEmpty ? '' : ' $unit';
  return '${number.toStringAsFixed(1)}$suffix';
}

String _compactList(List<String> values, {required int limit}) {
  if (values.length <= limit) return values.join(', ');
  return '${values.take(limit).join(', ')}, ... +${values.length - limit}';
}
