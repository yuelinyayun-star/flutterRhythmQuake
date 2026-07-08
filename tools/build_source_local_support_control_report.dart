import 'dart:convert';
import 'dart:io';

const _defaultManifestPath =
    'docs/data/source_candidate_region_validation_manifest.json';
const _defaultOutputPath =
    '.dart_tool/source_local_support_control_report/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_local_support_control_report.generated.md';

const _positiveLocalSupportRoles = {'local_support_delayed_positive_guard'};

void main(List<String> args) {
  final manifestPath = _argument(args, '--manifest') ?? _defaultManifestPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceLocalSupportControlReportJson(
    manifestPath: manifestPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source local-support control report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceLocalSupportControlReportJson({
  String manifestPath = _defaultManifestPath,
}) {
  final errors = <String>[];
  final manifest = _readJsonFile(manifestPath, errors);
  final cases = <Map<String, Object?>>[];
  for (final rawCase in _list(manifest['cases'])) {
    final spec = _map(rawCase);
    final caseId = spec['caseId']?.toString() ?? '';
    final inputPath = spec['benchmarkInput']?.toString() ?? '';
    if (caseId.isEmpty || inputPath.isEmpty) {
      errors.add('manifest_case_missing_id_or_input');
      continue;
    }
    final benchmark = _readJsonFile(inputPath, errors);
    cases.add(_caseReport(spec, inputPath, benchmark));
  }

  final summary = _summary(cases);
  final validation = _validation(cases, summary, errors);
  final violations = _list(validation['violations']);
  return {
    'schemaVersion': 'source_local_support_control_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'manifestPath': manifestPath,
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'All candidate-region local-support confirmations are metadata-only and must not switch production coordinates.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _caseReport(
  Map<String, Object?> spec,
  String inputPath,
  Map<String, Object?> benchmark,
) {
  final caseId = spec['caseId']?.toString() ?? '';
  final role = spec['role']?.toString() ?? 'unspecified';
  final frames = <Map<String, Object?>>[];
  for (final rawFrame in _list(benchmark['frames'])) {
    final frame = _map(rawFrame);
    final method = _map(_map(frame['methods'])['nied_gif_hybrid_v1']);
    final metadata = _map(method['eventMetadata']);
    final region = _mapOrNull(metadata['candidate_region']);
    if (region == null) continue;
    final local = _mapOrNull(metadata['candidate_region_local_support_gate']);
    frames.add(_frameReport(frame['observedAtJst']?.toString(), region, local));
  }
  final localConfirmedFrames = frames
      .where((frame) => frame['localSupportConfirmed'] == true)
      .toList(growable: false);
  final coordinateSwitchFrames = frames
      .where((frame) => frame['productionCoordinateSwitchAllowed'] == true)
      .toList(growable: false);
  final expectedLocalSupportAllowed = _positiveLocalSupportRoles.contains(role);
  return {
    'caseId': caseId,
    'role': role,
    'inputPath': inputPath,
    'expectedLocalSupportAllowed': expectedLocalSupportAllowed,
    'expectedCounts': _map(spec['expectations']),
    'frameCount': frames.length,
    'localSupportConfirmedCount': localConfirmedFrames.length,
    'confirmedDelayedCount': frames
        .where((frame) => frame['status'] == 'confirmedDelayed')
        .length,
    'confirmedImmediateCount': frames
        .where((frame) => frame['status'] == 'confirmedImmediate')
        .length,
    'expiredCount': frames
        .where((frame) => frame['status'] == 'expired')
        .length,
    'coordinateSwitchAllowedCount': coordinateSwitchFrames.length,
    'unexpectedLocalSupportConfirmationCount': expectedLocalSupportAllowed
        ? 0
        : localConfirmedFrames.length,
    'diagnosis': _caseDiagnosis(
      role: role,
      frameCount: frames.length,
      localConfirmedCount: localConfirmedFrames.length,
      coordinateSwitchCount: coordinateSwitchFrames.length,
    ),
    'localSupportConfirmedFrames': localConfirmedFrames,
    'coordinateSwitchFrames': coordinateSwitchFrames,
    'frames': frames,
  };
}

Map<String, Object?> _frameReport(
  String? observedAtJst,
  Map<String, Object?> region,
  Map<String, Object?>? local,
) {
  return {
    'observedAtJst': observedAtJst,
    'status': region['status'],
    'reason': region['reason'],
    'productionCoordinateSwitchAllowed':
        region['production_coordinate_switch_allowed'] == true,
    'localSupportConfirmed': local?['local_support_confirmed'] == true,
    'memberCount': _nullableInt(local?['member_count']),
    'initialMemberCount': _nullableInt(local?['initial_member_count']),
    'memberCountGrowth': _nullableInt(local?['member_count_growth']),
    'estimateMemberDistanceKm': _number(
      local?['estimate_member_centroid_distance_km'],
    ),
    'convergenceKm': _number(local?['convergence_km']),
    'geometry': local?['station_geometry'],
    'localSupportReason': local?['reason'],
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'caseWithCandidateRegionCount': cases
        .where((entry) => _intValue(entry['frameCount']) > 0)
        .length,
    'localSupportConfirmedCaseCount': cases
        .where((entry) => _intValue(entry['localSupportConfirmedCount']) > 0)
        .length,
    'unexpectedLocalSupportConfirmationCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['unexpectedLocalSupportConfirmationCount']),
    ),
    'productionCoordinateSwitchAllowedCount': cases.fold<int>(
      0,
      (sum, entry) => sum + _intValue(entry['coordinateSwitchAllowedCount']),
    ),
    'caseDiagnoses': {
      for (final entry in cases) entry['caseId'] as String: entry['diagnosis'],
    },
  };
}

Map<String, Object?> _validation(
  List<Map<String, Object?>> cases,
  Map<String, Object?> summary,
  List<String> errors,
) {
  final violations = <String>[];
  if (cases.length != 6) violations.add('unexpected_manifest_case_count');
  if (_intValue(summary['unexpectedLocalSupportConfirmationCount']) != 0) {
    violations.add('unexpected_local_support_confirmation');
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_present');
  }
  for (final entry in cases) {
    final expected = _map(entry['expectedCounts']);
    final expectedCoordinateSwitch = _nullableInt(
      expected['coordinateSwitchAllowedCount'],
    );
    if (expectedCoordinateSwitch != null &&
        _intValue(entry['coordinateSwitchAllowedCount']) !=
            expectedCoordinateSwitch) {
      violations.add('${entry['caseId']}:coordinate_switch_count_mismatch');
    }
    final expectedLocalSupport = _nullableInt(
      expected['localSupportConfirmedCount'],
    );
    if (expectedLocalSupport != null &&
        _intValue(entry['localSupportConfirmedCount']) !=
            expectedLocalSupport) {
      violations.add('${entry['caseId']}:local_support_count_mismatch');
    }
  }
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _caseDiagnosis({
  required String role,
  required int frameCount,
  required int localConfirmedCount,
  required int coordinateSwitchCount,
}) {
  if (coordinateSwitchCount > 0) return 'coordinate_switch_violation';
  if (_positiveLocalSupportRoles.contains(role)) {
    return localConfirmedCount == 1
        ? 'expected_local_support_positive'
        : 'local_support_positive_regressed';
  }
  if (localConfirmedCount > 0) return 'unexpected_local_support_confirmation';
  if (frameCount == 0) return 'no_candidate_region_control_clear';
  if (role.contains('residual')) return 'residual_guard_no_local_support';
  return 'local_support_control_clear';
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Local-Support Control Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Manifest cases: `${summary['caseCount']}`')
    ..writeln(
      '- Cases with candidate-region frames: `${summary['caseWithCandidateRegionCount']}`',
    )
    ..writeln(
      '- Local-support confirmed cases: `${summary['localSupportConfirmedCaseCount']}`',
    )
    ..writeln(
      '- Unexpected local-support confirmations: `${summary['unexpectedLocalSupportConfirmationCount']}`',
    )
    ..writeln(
      '- Production coordinate switches: `${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Case Summary')
    ..writeln()
    ..writeln(
      '| Case | Role | Diagnosis | Frames | Local confirm | Unexpected local | Immediate | Delayed | Expired | Switch |',
    )
    ..writeln(
      '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['role']}` | `${entry['diagnosis']}` | '
      '${entry['frameCount']} | ${entry['localSupportConfirmedCount']} | '
      '${entry['unexpectedLocalSupportConfirmationCount']} | '
      '${entry['confirmedImmediateCount']} | ${entry['confirmedDelayedCount']} | '
      '${entry['expiredCount']} | ${entry['coordinateSwitchAllowedCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Local-Support Confirmed Frames')
    ..writeln()
    ..writeln(
      '| Case | Time | Status | Count | Growth | Distance | Converge | Geometry |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | --- |');
  var wroteConfirmed = false;
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    for (final rawFrame in _list(entry['localSupportConfirmedFrames'])) {
      wroteConfirmed = true;
      final frame = _map(rawFrame);
      buffer.writeln(
        '| `${entry['caseId']}` | `${frame['observedAtJst']}` | '
        '`${frame['status']}` | ${frame['memberCount'] ?? '--'} | '
        '${frame['memberCountGrowth'] ?? '--'} | '
        '${_fmt(frame['estimateMemberDistanceKm'])} | '
        '${_fmt(frame['convergenceKm'])} | `${frame['geometry'] ?? '--'}` |',
      );
    }
  }
  if (!wroteConfirmed) {
    buffer.writeln('| -- | -- | -- | -- | -- | -- | -- | -- |');
  }

  buffer
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation['status']}`.');
  final violations = _list(validation['violations']);
  if (violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln('- Violations: ${_codeList(violations)}.');
  }
  buffer.writeln();
  return buffer.toString();
}

Map<String, Object?> _readJsonFile(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('json_file_missing:$path');
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) return decoded.cast<String, Object?>();
    errors.add('json_file_not_object:$path');
  } on FormatException catch (error) {
    errors.add('json_file_invalid:$path:${error.message}');
  }
  return const {};
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
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

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return _intValue(value);
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _fmt(Object? value, {int digits = 1}) {
  final number = _number(value);
  if (number == null || !number.isFinite) return '--';
  return number.toStringAsFixed(digits);
}

String _codeList(List<Object?> items) {
  if (items.isEmpty) return '--';
  return items.map((item) => '`${item.toString()}`').join(', ');
}
