import 'dart:convert';
import 'dart:io';

const _hybridMethod = 'nied_gif_hybrid_v1';
const _defaultManifest =
    'docs/data/source_candidate_region_validation_manifest.json';
const _defaultOutput =
    '.dart_tool/source_candidate_region_timeline_report/report.json';
const _defaultMarkdown =
    'docs/baselines/source_candidate_region_timeline.generated.md';

void main(List<String> args) {
  final manifestPath = _argument(args, '--manifest') ?? _defaultManifest;
  final manifest = _ValidationManifest.read(manifestPath);
  final inputPaths = _arguments(args, '--input');
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;
  final inputs = inputPaths.isEmpty
      ? manifest.cases.map((entry) => entry.benchmarkInput)
      : inputPaths;

  final cases = <_CaseTimeline>[];
  final skipped = <Map<String, Object?>>[];
  for (final path in inputs) {
    final input = File(path);
    if (!input.existsSync()) {
      skipped.add({'file': path, 'reason': 'missing_input'});
      continue;
    }
    try {
      final decoded = jsonDecode(input.readAsStringSync());
      if (decoded is! Map) {
        skipped.add({'file': path, 'reason': 'not_a_json_object'});
        continue;
      }
      cases.add(
        _CaseTimeline.fromBenchmark(input, decoded.cast<String, Object?>()),
      );
    } on FormatException catch (error) {
      skipped.add({
        'file': path,
        'reason': 'invalid_json',
        'error': error.message,
      });
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'source_candidate_region_timeline_v2',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'method': _hybridMethod,
    'validationManifest': manifest.toJson(),
    'cases': cases.map((entry) => entry.toJson()).toList(growable: false),
    'skippedFiles': skipped,
    'validation': _validation(manifest, cases, skipped).toJson(),
  };

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    _markdown(manifest, cases, skipped, _validation(manifest, cases, skipped)),
  );

  stdout.writeln('wrote candidate-region timeline for ${cases.length} cases');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

class _ValidationManifest {
  final String path;
  final String schemaVersion;
  final String? description;
  final List<_ValidationCaseSpec> cases;

  const _ValidationManifest({
    required this.path,
    required this.schemaVersion,
    required this.description,
    required this.cases,
  });

  factory _ValidationManifest.read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Validation manifest does not exist', path);
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('validation manifest must be a JSON object');
    }
    final data = decoded.cast<String, Object?>();
    final cases = _list(data['cases'])
        .map((entry) => _ValidationCaseSpec.fromJson(_map(entry)))
        .toList(growable: false);
    if (cases.isEmpty) {
      throw const FormatException('validation manifest must define cases');
    }
    return _ValidationManifest(
      path: path,
      schemaVersion: data['schemaVersion']?.toString() ?? '',
      description: data['description']?.toString(),
      cases: cases,
    );
  }

  Map<String, Object?> toJson() => {
    'path': path,
    'schemaVersion': schemaVersion,
    'description': description,
    'cases': cases.map((entry) => entry.toJson()).toList(growable: false),
  };
}

class _ValidationCaseSpec {
  final String caseId;
  final String role;
  final String benchmarkInput;
  final Map<String, int> expectations;

  const _ValidationCaseSpec({
    required this.caseId,
    required this.role,
    required this.benchmarkInput,
    required this.expectations,
  });

  factory _ValidationCaseSpec.fromJson(Map<String, Object?> json) {
    final caseId = json['caseId']?.toString();
    final benchmarkInput = json['benchmarkInput']?.toString();
    if (caseId == null || caseId.isEmpty) {
      throw const FormatException('manifest case is missing caseId');
    }
    if (benchmarkInput == null || benchmarkInput.isEmpty) {
      throw FormatException('manifest case $caseId is missing benchmarkInput');
    }
    return _ValidationCaseSpec(
      caseId: caseId,
      role: json['role']?.toString() ?? 'unspecified',
      benchmarkInput: benchmarkInput,
      expectations: _map(
        json['expectations'],
      ).map((key, value) => MapEntry(key, _int(value) ?? 0)),
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'role': role,
    'benchmarkInput': benchmarkInput,
    'expectations': expectations,
  };
}

class _CaseTimeline {
  final String caseId;
  final String inputPath;
  final List<_TimelineFrame> frames;

  const _CaseTimeline({
    required this.caseId,
    required this.inputPath,
    required this.frames,
  });

  factory _CaseTimeline.fromBenchmark(
    File input,
    Map<String, Object?> benchmark,
  ) {
    final caseData = _map(benchmark['case']);
    final frames = <_TimelineFrame>[];
    for (final rawFrame in _list(benchmark['frames'])) {
      final frame = _map(rawFrame);
      final method = _map(_map(frame['methods'])[_hybridMethod]);
      final metadata = _map(method['eventMetadata']);
      final candidateRegion = _mapOrNull(metadata['candidate_region']);
      if (candidateRegion == null) continue;
      frames.add(
        _TimelineFrame.fromFrame(
          observedAtJst: frame['observedAtJst']?.toString(),
          estimate: _mapOrNull(method['estimate']),
          candidateRegion: candidateRegion,
          residualGate: _mapOrNull(metadata['candidate_region_residual_gate']),
          localSupportGate: _mapOrNull(
            metadata['candidate_region_local_support_gate'],
          ),
        ),
      );
    }
    return _CaseTimeline(
      caseId: caseData['caseId']?.toString() ?? input.uri.pathSegments.last,
      inputPath: input.path,
      frames: frames,
    );
  }

  int get pendingCount =>
      frames.where((frame) => frame.status == 'pending').length;

  int get confirmedDelayedCount =>
      frames.where((frame) => frame.status == 'confirmedDelayed').length;

  int get residualConfirmedDelayedCount => frames
      .where(
        (frame) =>
            frame.status == 'confirmedDelayed' && frame.residualSupported,
      )
      .length;

  int get localSupportConfirmedDelayedCount => frames
      .where(
        (frame) =>
            frame.status == 'confirmedDelayed' && frame.localSupportConfirmed,
      )
      .length;

  int get confirmedImmediateCount =>
      frames.where((frame) => frame.status == 'confirmedImmediate').length;

  int get expiredCount =>
      frames.where((frame) => frame.status == 'expired').length;

  int get coordinateSwitchAllowedCount =>
      frames.where((frame) => frame.productionCoordinateSwitchAllowed).length;

  int get localSupportConfirmedCount =>
      frames.where((frame) => frame.localSupportConfirmed).length;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'inputPath': inputPath,
    'frameCount': frames.length,
    'pendingCount': pendingCount,
    'confirmedDelayedCount': confirmedDelayedCount,
    'residualConfirmedDelayedCount': residualConfirmedDelayedCount,
    'localSupportConfirmedDelayedCount': localSupportConfirmedDelayedCount,
    'confirmedImmediateCount': confirmedImmediateCount,
    'expiredCount': expiredCount,
    'localSupportConfirmedCount': localSupportConfirmedCount,
    'coordinateSwitchAllowedCount': coordinateSwitchAllowedCount,
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
  };
}

class _TimelineValidation {
  final List<String> violations;
  final List<String> expectedCases;

  const _TimelineValidation({
    required this.violations,
    required this.expectedCases,
  });

  bool get passed => violations.isEmpty;

  Map<String, Object?> toJson() => {
    'status': passed ? 'pass' : 'fail',
    'violations': violations,
    'expectedCases': expectedCases,
  };
}

_TimelineValidation _validation(
  _ValidationManifest manifest,
  List<_CaseTimeline> cases,
  List<Map<String, Object?>> skipped,
) {
  final byId = {for (final entry in cases) entry.caseId: entry};
  final violations = <String>[];
  if (skipped.isNotEmpty) {
    violations.add('timeline_has_skipped_inputs');
  }
  for (final spec in manifest.cases) {
    final entry = byId[spec.caseId];
    if (entry == null) {
      violations.add('missing_case:${spec.caseId}');
      continue;
    }
    if (entry.inputPath.replaceAll('\\', '/') !=
        spec.benchmarkInput.replaceAll('\\', '/')) {
      violations.add('input_mismatch:${spec.caseId}:${entry.inputPath}');
    }
    for (final expectation in spec.expectations.entries) {
      final actual = _timelineCount(entry, expectation.key);
      if (actual == null) {
        violations.add('unknown_expectation:${spec.caseId}:${expectation.key}');
      } else if (actual != expectation.value) {
        violations.add(
          '${spec.caseId}:${expectation.key}:$actual!=expected_${expectation.value}',
        );
      }
    }
  }
  for (final entry in cases) {
    if (entry.coordinateSwitchAllowedCount != 0) {
      violations.add('coordinate_switch:${entry.caseId}');
    }
  }
  return _TimelineValidation(
    violations: violations,
    expectedCases: manifest.cases.map((entry) => entry.caseId).toList(),
  );
}

int? _timelineCount(_CaseTimeline entry, String field) {
  return switch (field) {
    'frameCount' => entry.frames.length,
    'pendingCount' => entry.pendingCount,
    'confirmedDelayedCount' => entry.confirmedDelayedCount,
    'residualConfirmedDelayedCount' => entry.residualConfirmedDelayedCount,
    'localSupportConfirmedDelayedCount' =>
      entry.localSupportConfirmedDelayedCount,
    'confirmedImmediateCount' => entry.confirmedImmediateCount,
    'expiredCount' => entry.expiredCount,
    'localSupportConfirmedCount' => entry.localSupportConfirmedCount,
    'coordinateSwitchAllowedCount' => entry.coordinateSwitchAllowedCount,
    _ => null,
  };
}

class _TimelineFrame {
  final String? observedAtJst;
  final String? status;
  final String? reason;
  final double? latitude;
  final double? longitude;
  final double? estimateLatitude;
  final double? estimateLongitude;
  final double? confirmationDelaySeconds;
  final double? clusterDistanceKm;
  final bool residualSupported;
  final bool productionCoordinateSwitchAllowed;
  final double? rankDelta;
  final double? attenuationDelta;
  final double? attenuationRatio;
  final bool localSupportConfirmed;
  final int? localSupportMemberCount;
  final int? localSupportMemberCountGrowth;
  final double? localSupportEstimateMemberDistanceKm;
  final double? localSupportConvergenceKm;
  final String? localSupportGeometry;

  const _TimelineFrame({
    required this.observedAtJst,
    required this.status,
    required this.reason,
    required this.latitude,
    required this.longitude,
    required this.estimateLatitude,
    required this.estimateLongitude,
    required this.confirmationDelaySeconds,
    required this.clusterDistanceKm,
    required this.residualSupported,
    required this.productionCoordinateSwitchAllowed,
    required this.rankDelta,
    required this.attenuationDelta,
    required this.attenuationRatio,
    required this.localSupportConfirmed,
    required this.localSupportMemberCount,
    required this.localSupportMemberCountGrowth,
    required this.localSupportEstimateMemberDistanceKm,
    required this.localSupportConvergenceKm,
    required this.localSupportGeometry,
  });

  factory _TimelineFrame.fromFrame({
    required String? observedAtJst,
    required Map<String, Object?>? estimate,
    required Map<String, Object?> candidateRegion,
    required Map<String, Object?>? residualGate,
    required Map<String, Object?>? localSupportGate,
  }) {
    return _TimelineFrame(
      observedAtJst: observedAtJst,
      status: candidateRegion['status']?.toString(),
      reason: candidateRegion['reason']?.toString(),
      latitude: _number(candidateRegion['latitude']),
      longitude: _number(candidateRegion['longitude']),
      estimateLatitude: _number(estimate?['latitude']),
      estimateLongitude: _number(estimate?['longitude']),
      confirmationDelaySeconds: _number(
        candidateRegion['confirmation_delay_seconds'],
      ),
      clusterDistanceKm: _number(candidateRegion['cluster_distance_km']),
      productionCoordinateSwitchAllowed:
          candidateRegion['production_coordinate_switch_allowed'] == true,
      residualSupported: residualGate?['residual_supported'] == true,
      rankDelta: _number(residualGate?['rank_delta']),
      attenuationDelta: _number(residualGate?['attenuation_delta']),
      attenuationRatio: _number(residualGate?['attenuation_ratio']),
      localSupportConfirmed:
          localSupportGate?['local_support_confirmed'] == true,
      localSupportMemberCount: _int(localSupportGate?['member_count']),
      localSupportMemberCountGrowth: _int(
        localSupportGate?['member_count_growth'],
      ),
      localSupportEstimateMemberDistanceKm: _number(
        localSupportGate?['estimate_member_centroid_distance_km'],
      ),
      localSupportConvergenceKm: _number(localSupportGate?['convergence_km']),
      localSupportGeometry: localSupportGate?['station_geometry']?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
    'observedAtJst': observedAtJst,
    'status': status,
    'reason': reason,
    'latitude': latitude,
    'longitude': longitude,
    'estimateLatitude': estimateLatitude,
    'estimateLongitude': estimateLongitude,
    'confirmationDelaySeconds': confirmationDelaySeconds,
    'clusterDistanceKm': clusterDistanceKm,
    'residualSupported': residualSupported,
    'productionCoordinateSwitchAllowed': productionCoordinateSwitchAllowed,
    'rankDelta': rankDelta,
    'attenuationDelta': attenuationDelta,
    'attenuationRatio': attenuationRatio,
    'localSupportConfirmed': localSupportConfirmed,
    'localSupportMemberCount': localSupportMemberCount,
    'localSupportMemberCountGrowth': localSupportMemberCountGrowth,
    'localSupportEstimateMemberDistanceKm':
        localSupportEstimateMemberDistanceKm,
    'localSupportConvergenceKm': localSupportConvergenceKm,
    'localSupportGeometry': localSupportGeometry,
  };
}

String _markdown(
  _ValidationManifest manifest,
  List<_CaseTimeline> cases,
  List<Map<String, Object?>> skipped,
  _TimelineValidation validation,
) {
  final buffer = StringBuffer()
    ..writeln('# Source Candidate-Region Timeline')
    ..writeln()
    ..writeln(
      'Generated from benchmark reports. This is metadata-only validation; '
      'source estimate coordinates are not switched.',
    )
    ..writeln()
    ..writeln('- Manifest: `${manifest.path}`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln(
      '| Case | Frames | Pending | Confirmed delayed | Confirmed immediate | Expired | Local support | Coordinate switches |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final entry in cases) {
    buffer.writeln(
      '| `${entry.caseId}` | ${entry.frames.length} | ${entry.pendingCount} | '
      '${entry.confirmedDelayedCount} '
      '(${entry.residualConfirmedDelayedCount} residual / '
      '${entry.localSupportConfirmedDelayedCount} local) | '
      '${entry.confirmedImmediateCount} | '
      '${entry.expiredCount} | ${entry.localSupportConfirmedCount} | '
      '${entry.coordinateSwitchAllowedCount} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Coverage Manifest')
    ..writeln()
    ..writeln('| Case | Role | Expectations |')
    ..writeln('| --- | --- | --- |');
  for (final spec in manifest.cases) {
    buffer.writeln(
      '| `${spec.caseId}` | `${spec.role}` | '
      '${_expectationList(spec.expectations)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Timelines')
    ..writeln();
  for (final entry in cases) {
    buffer
      ..writeln('### ${entry.caseId}')
      ..writeln()
      ..writeln(
        '| Time | Status | Reason | Residual | Local support | Region | Estimate | Delay | Cluster | Rank delta | Atten delta | Members | Est-member | Converge | Geometry | Switch |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |',
      );
    for (final frame in entry.frames) {
      buffer.writeln(
        '| `${frame.observedAtJst ?? ''}` | `${frame.status ?? ''}` | '
        '`${frame.reason ?? '--'}` | '
        '${frame.residualSupported ? 'yes' : 'no'} | '
        '${frame.localSupportConfirmed ? 'yes' : 'no'} | '
        '${_point(frame.latitude, frame.longitude)} | '
        '${_point(frame.estimateLatitude, frame.estimateLongitude)} | '
        '${_fmt(frame.confirmationDelaySeconds, suffix: 's')} | '
        '${_fmt(frame.clusterDistanceKm, suffix: 'km')} | '
        '${_fmt(frame.rankDelta, digits: 3)} | '
        '${_fmt(frame.attenuationDelta, digits: 3)} | '
        '${frame.localSupportMemberCount ?? '--'}'
        '${_growthSuffix(frame.localSupportMemberCountGrowth)} | '
        '${_fmt(frame.localSupportEstimateMemberDistanceKm, suffix: 'km')} | '
        '${_fmt(frame.localSupportConvergenceKm, suffix: 'km')} | '
        '`${frame.localSupportGeometry ?? '--'}` | '
        '${frame.productionCoordinateSwitchAllowed ? 'yes' : 'no'} |',
      );
    }
    buffer.writeln();
  }

  if (skipped.isNotEmpty) {
    buffer
      ..writeln('## Skipped Files')
      ..writeln()
      ..writeln('| File | Reason |')
      ..writeln('| --- | --- |');
    for (final entry in skipped) {
      buffer.writeln('| `${entry['file']}` | `${entry['reason']}` |');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation.passed ? 'pass' : 'fail'}`.');
  if (validation.violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln('- Violations:');
    for (final violation in validation.violations) {
      buffer.writeln('  - `$violation`');
    }
  }
  buffer.writeln();

  final delayedCases = cases
      .where((entry) => entry.confirmedDelayedCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final residualDelayedCases = cases
      .where((entry) => entry.residualConfirmedDelayedCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final localDelayedCases = cases
      .where((entry) => entry.localSupportConfirmedDelayedCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final immediateCases = cases
      .where((entry) => entry.confirmedImmediateCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final pendingOnlyCases = cases
      .where(
        (entry) =>
            entry.frames.isNotEmpty &&
            entry.confirmedDelayedCount == 0 &&
            entry.confirmedImmediateCount == 0,
      )
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final coordinateSwitchCases = cases
      .where((entry) => entry.coordinateSwitchAllowedCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final localSupportCases = cases
      .where((entry) => entry.localSupportConfirmedCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Delayed-confirmed candidate-region cases: ${_caseList(delayedCases)}.',
    )
    ..writeln(
      '- Residual delayed-confirmed cases: '
      '${_caseList(residualDelayedCases)}.',
    )
    ..writeln(
      '- Local-support delayed-confirmed cases: '
      '${_caseList(localDelayedCases)}.',
    )
    ..writeln(
      '- Immediate-confirmed candidate-region cases: '
      '${_caseList(immediateCases)}.',
    )
    ..writeln(
      '- Pending-only candidate-region cases: ${_caseList(pendingOnlyCases)}.',
    )
    ..writeln(
      '- Local-support recovered cases: ${_caseList(localSupportCases)}.',
    )
    ..writeln(
      '- Production coordinate switch cases: ${_caseList(coordinateSwitchCases)}.',
    )
    ..writeln(
      '- Candidate-region metadata remains diagnostic-only. Pending-only cases '
      'must be treated as uncertainty evidence, not coordinate replacements.',
    );
  return buffer.toString();
}

String _expectationList(Map<String, int> expectations) {
  if (expectations.isEmpty) return '--';
  return expectations.entries
      .map((entry) => '`${entry.key}=${entry.value}`')
      .join(', ');
}

String _caseList(List<String> caseIds) {
  if (caseIds.isEmpty) return 'none';
  return caseIds.map((caseId) => '`$caseId`').join(', ');
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

List<String> _arguments(List<String> args, String name) {
  final result = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) {
      result.add(args[i + 1]);
      i++;
    } else if (arg.startsWith('$name=')) {
      result.add(arg.substring(name.length + 1));
    }
  }
  return result;
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
  if (value is List) return value.cast<Object?>();
  return const [];
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _point(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return '--';
  return '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}';
}

String _fmt(double? value, {int digits = 1, String suffix = ''}) {
  if (value == null || !value.isFinite) return '--';
  return '${value.toStringAsFixed(digits)}$suffix';
}

String _growthSuffix(int? value) {
  if (value == null) return '';
  if (value == 0) return ' (+0)';
  return ' (${value > 0 ? '+' : ''}$value)';
}
