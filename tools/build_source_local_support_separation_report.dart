import 'dart:convert';
import 'dart:io';

const _defaultOutputPath =
    '.dart_tool/source_local_support_separation_report/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_local_support_separation_report.generated.md';

const _caseInputs = {
  '20260621_fukushima_offshore_m32_eq6':
      '.dart_tool/source_estimation_benchmark/'
      '20260621_fukushima_offshore_m32_eq6.reference.json',
  '20260625_iwate_offshore_m32_jma':
      '.dart_tool/source_estimation_benchmark/'
      '20260625_iwate_offshore_m32_jma.reference.json',
};

const _localSupportThresholds = {
  'minMemberCount': 8,
  'minMemberGrowth': 4,
  'maxEstimateMemberCentroidDistanceKm': 50.0,
  'minConvergenceKm': 80.0,
  'confirmationWindowSeconds': 5.0,
};

void main(List<String> args) {
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceLocalSupportSeparationReportJson(
    caseInputs: _caseInputs.map(
      (caseId, path) => MapEntry(caseId, _argument(args, '--$caseId') ?? path),
    ),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source local-support separation report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceLocalSupportSeparationReportJson({
  Map<String, String> caseInputs = _caseInputs,
}) {
  final errors = <String>[];
  final cases = <Map<String, Object?>>[];
  for (final entry in caseInputs.entries) {
    final benchmark = _readJsonFile(entry.value, errors);
    if (benchmark.isEmpty) continue;
    cases.add(_caseReport(entry.key, entry.value, benchmark));
  }

  cases.sort(
    (left, right) =>
        (left['caseId'] as String).compareTo(right['caseId'] as String),
  );
  final summary = _summary(cases);
  final validation = _validation(cases, summary, errors);
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_local_support_separation_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'diagnosticOnly': true,
      'strictMetricEligible': false,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'This report validates local-support gate separation between a false-recovery guard and a positive guard.',
    },
    'thresholds': _localSupportThresholds,
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _caseReport(
  String caseId,
  String inputPath,
  Map<String, Object?> benchmark,
) {
  final frames = <Map<String, Object?>>[];
  for (final rawFrame in _list(benchmark['frames'])) {
    final frame = _map(rawFrame);
    final method = _map(_map(frame['methods'])['nied_gif_hybrid_v1']);
    final metadata = _map(method['eventMetadata']);
    final region = _mapOrNull(metadata['candidate_region']);
    final local = _mapOrNull(metadata['candidate_region_local_support_gate']);
    if (region == null || local == null) continue;
    frames.add(_frameReport(frame['observedAtJst']?.toString(), region, local));
  }

  final confirmedFrames = frames
      .where((frame) => frame['localSupportConfirmed'] == true)
      .toList(growable: false);
  final nearCompleteBlockedFrames = frames
      .where((frame) => frame['nearCompleteBlockedOnlyByGrowth'] == true)
      .toList(growable: false);

  return {
    'caseId': caseId,
    'inputPath': inputPath,
    'role': caseId.contains('fukushima')
        ? 'false_recovery_guard'
        : 'local_support_positive_guard',
    'frameCount': frames.length,
    'localSupportConfirmedCount': confirmedFrames.length,
    'confirmedDelayedCount': frames
        .where((frame) => frame['status'] == 'confirmedDelayed')
        .length,
    'expiredCount': frames
        .where((frame) => frame['status'] == 'expired')
        .length,
    'productionCoordinateSwitchAllowedCount': frames
        .where((frame) => frame['productionCoordinateSwitchAllowed'] == true)
        .length,
    'nearCompleteBlockedOnlyByGrowthCount': nearCompleteBlockedFrames.length,
    'maxMemberGrowthWhenBlockedOnlyByGrowth': _maxInt(
      nearCompleteBlockedFrames,
      'memberCountGrowth',
    ),
    'minConfirmedMemberGrowth': _minInt(confirmedFrames, 'memberCountGrowth'),
    'diagnosis': _caseDiagnosis(caseId, confirmedFrames),
    'frames': frames,
  };
}

Map<String, Object?> _frameReport(
  String? observedAtJst,
  Map<String, Object?> region,
  Map<String, Object?> local,
) {
  final firstObservedAt = region['first_observed_at']?.toString();
  final ageSeconds = _ageSeconds(
    observedAtJst: observedAtJst,
    firstObservedAt: firstObservedAt,
  );
  final supported = {
    'memberCount': local['member_count_supported'] == true,
    'memberGrowth': local['member_growth_supported'] == true,
    'estimateMemberDistance':
        local['estimate_member_distance_supported'] == true,
    'convergence': local['convergence_supported'] == true,
    'geometry': local['geometry_supported'] == true,
  };
  final blockingReasons = [
    for (final entry in supported.entries)
      if (!entry.value) entry.key,
    if (ageSeconds != null &&
        ageSeconds > (_localSupportThresholds['confirmationWindowSeconds']!))
      'confirmationWindow',
  ];
  final nearCompleteBlockedOnlyByGrowth =
      supported['memberCount'] == true &&
      supported['memberGrowth'] == false &&
      supported['estimateMemberDistance'] == true &&
      supported['convergence'] == true &&
      supported['geometry'] == true &&
      local['local_support_confirmed'] != true;

  return {
    'observedAtJst': observedAtJst,
    'status': region['status'],
    'reason': region['reason'],
    'firstObservedAtJst': firstObservedAt,
    'pendingAgeSeconds': ageSeconds,
    'withinConfirmationWindow': ageSeconds == null
        ? null
        : ageSeconds <=
              (_localSupportThresholds['confirmationWindowSeconds']! as double),
    'localSupportConfirmed': local['local_support_confirmed'] == true,
    'support': supported,
    'blockingReasons': blockingReasons,
    'nearCompleteBlockedOnlyByGrowth': nearCompleteBlockedOnlyByGrowth,
    'memberCount': _nullableInt(local['member_count']),
    'initialMemberCount': _nullableInt(local['initial_member_count']),
    'memberCountGrowth': _nullableInt(local['member_count_growth']),
    'estimateMemberDistanceKm': _number(
      local['estimate_member_centroid_distance_km'],
    ),
    'initialEstimateMemberDistanceKm': _number(
      local['initial_estimate_member_centroid_distance_km'],
    ),
    'convergenceKm': _number(local['convergence_km']),
    'geometry': local['station_geometry'],
    'localSupportReason': local['reason'],
    'productionCoordinateSwitchAllowed':
        region['production_coordinate_switch_allowed'] == true,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'localSupportConfirmedCaseCount': cases
        .where((entry) => _intValue(entry['localSupportConfirmedCount']) > 0)
        .length,
    'falseRecoveryGuardConfirmedCount': cases
        .where(
          (entry) =>
              entry['role'] == 'false_recovery_guard' &&
              _intValue(entry['localSupportConfirmedCount']) > 0,
        )
        .length,
    'positiveGuardConfirmedCount': cases
        .where(
          (entry) =>
              entry['role'] == 'local_support_positive_guard' &&
              _intValue(entry['localSupportConfirmedCount']) > 0,
        )
        .length,
    'productionCoordinateSwitchAllowedCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['productionCoordinateSwitchAllowedCount']),
    ),
    'nearCompleteBlockedOnlyByGrowthCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['nearCompleteBlockedOnlyByGrowthCount']),
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
  final byId = {
    for (final entry in cases) entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final fukushima = byId['20260621_fukushima_offshore_m32_eq6'];
  final iwate = byId['20260625_iwate_offshore_m32_jma'];
  if (fukushima == null) {
    violations.add('missing_fukushima_false_recovery_guard');
  }
  if (iwate == null) {
    violations.add('missing_iwate_positive_guard');
  }
  if (_intValue(fukushima?['localSupportConfirmedCount']) != 0) {
    violations.add('fukushima_local_support_false_recovery');
  }
  if (_intValue(fukushima?['nearCompleteBlockedOnlyByGrowthCount']) < 1) {
    violations.add('fukushima_missing_growth_blocked_near_complete_frame');
  }
  if (_intValue(iwate?['localSupportConfirmedCount']) != 1) {
    violations.add('iwate_local_support_confirmation_regressed');
  }
  if (_intValue(iwate?['minConfirmedMemberGrowth']) < 4) {
    violations.add('iwate_confirmed_without_min_growth');
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_present');
  }
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _caseDiagnosis(
  String caseId,
  List<Map<String, Object?>> confirmedFrames,
) {
  if (caseId.contains('fukushima')) {
    return confirmedFrames.isEmpty
        ? 'blocked_false_recovery_by_member_growth'
        : 'false_recovery_not_blocked';
  }
  return confirmedFrames.length == 1
      ? 'confirmed_positive_by_full_local_support'
      : 'positive_confirmation_regressed';
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Local-Support Separation Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- False-recovery guard confirmations: `${summary['falseRecoveryGuardConfirmedCount']}`',
    )
    ..writeln(
      '- Positive guard confirmations: `${summary['positiveGuardConfirmedCount']}`',
    )
    ..writeln(
      '- Near-complete frames blocked only by growth: `${summary['nearCompleteBlockedOnlyByGrowthCount']}`',
    )
    ..writeln(
      '- Production coordinate switches: `${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Thresholds')
    ..writeln()
    ..writeln(
      '| Member count | Member growth | Est-member distance | Convergence | Window |',
    )
    ..writeln('| ---: | ---: | ---: | ---: | ---: |')
    ..writeln(
      '| `${_localSupportThresholds['minMemberCount']}` | '
      '`${_localSupportThresholds['minMemberGrowth']}` | '
      '`${_localSupportThresholds['maxEstimateMemberCentroidDistanceKm']}km` | '
      '`${_localSupportThresholds['minConvergenceKm']}km` | '
      '`${_localSupportThresholds['confirmationWindowSeconds']}s` |',
    )
    ..writeln()
    ..writeln('## Case Summary')
    ..writeln()
    ..writeln(
      '| Case | Role | Diagnosis | Frames | Confirmed | Expired | Growth-blocked near-complete | Switch |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |');

  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['role']}` | '
      '`${entry['diagnosis']}` | ${entry['frameCount']} | '
      '${entry['localSupportConfirmedCount']} | ${entry['expiredCount']} | '
      '${entry['nearCompleteBlockedOnlyByGrowthCount']} | '
      '${entry['productionCoordinateSwitchAllowedCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Local-Support Frames')
    ..writeln()
    ..writeln(
      '| Case | Time | Status | Age | Confirm | Count | Growth | Distance | Converge | Geometry | Blockers |',
    )
    ..writeln(
      '| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |',
    );
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    for (final rawFrame in _list(entry['frames'])) {
      final frame = _map(rawFrame);
      if (!_interestingFrame(frame)) continue;
      buffer.writeln(
        '| `${entry['caseId']}` | `${frame['observedAtJst']}` | '
        '`${frame['status']}` | ${_fmt(frame['pendingAgeSeconds'], digits: 0)} | '
        '${frame['localSupportConfirmed'] == true ? 'yes' : 'no'} | '
        '${frame['memberCount'] ?? '--'} | '
        '${frame['memberCountGrowth'] ?? '--'} | '
        '${_fmt(frame['estimateMemberDistanceKm'])} | '
        '${_fmt(frame['convergenceKm'])} | '
        '`${frame['geometry'] ?? '--'}` | '
        '${_codeList(_list(frame['blockingReasons']))} |',
      );
    }
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

bool _interestingFrame(Map<String, Object?> frame) {
  return frame['localSupportConfirmed'] == true ||
      frame['nearCompleteBlockedOnlyByGrowth'] == true ||
      frame['status'] == 'expired';
}

double? _ageSeconds({
  required String? observedAtJst,
  required String? firstObservedAt,
}) {
  if (observedAtJst == null || firstObservedAt == null) return null;
  final observed = DateTime.tryParse(observedAtJst);
  final first = DateTime.tryParse(firstObservedAt);
  if (observed == null || first == null) return null;
  return observed.difference(first).inMilliseconds /
      Duration.millisecondsPerSecond;
}

int? _minInt(List<Map<String, Object?>> entries, String field) {
  final values = entries
      .map((entry) => _nullableInt(entry[field]))
      .whereType<int>()
      .toList(growable: false);
  if (values.isEmpty) return null;
  return values.reduce((left, right) => left < right ? left : right);
}

int? _maxInt(List<Map<String, Object?>> entries, String field) {
  final values = entries
      .map((entry) => _nullableInt(entry[field]))
      .whereType<int>()
      .toList(growable: false);
  if (values.isEmpty) return null;
  return values.reduce((left, right) => left > right ? left : right);
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
