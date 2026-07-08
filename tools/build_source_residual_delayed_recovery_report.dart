import 'dart:convert';
import 'dart:io';

const _defaultPromotionPath =
    '.dart_tool/source_candidate_promotion_report/matrix.json';
const _defaultTimelinePath =
    '.dart_tool/source_candidate_region_timeline_report/report.json';
const _defaultOutputPath =
    '.dart_tool/source_residual_delayed_recovery_report/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_residual_delayed_recovery_report.generated.md';

const _caseIds = {
  '20260621_fukushima_offshore_m32_eq6': 'false_recovery_guard',
  '20260622_kushiro_offshore_m30_jma': 'residual_delayed_positive_guard',
  '20260622_tomakomai_south_offshore_m35_hinet':
      'residual_immediate_positive_guard',
};

void main(List<String> args) {
  final promotionPath = _argument(args, '--promotion') ?? _defaultPromotionPath;
  final timelinePath = _argument(args, '--timeline') ?? _defaultTimelinePath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceResidualDelayedRecoveryReportJson(
    promotionPath: promotionPath,
    timelinePath: timelinePath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source residual delayed-recovery report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceResidualDelayedRecoveryReportJson({
  String promotionPath = _defaultPromotionPath,
  String timelinePath = _defaultTimelinePath,
}) {
  final errors = <String>[];
  final promotion = _readJsonFile(promotionPath, errors);
  final timeline = _readJsonFile(timelinePath, errors);
  final promotionByCase = {
    for (final raw in _list(promotion['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');
  final timelineByCase = {
    for (final raw in _list(timeline['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');

  final cases = <Map<String, Object?>>[];
  for (final entry in _caseIds.entries) {
    final promotionCase = promotionByCase[entry.key];
    if (promotionCase == null) {
      errors.add('missing_promotion_case:${entry.key}');
      continue;
    }
    cases.add(
      _caseReport(
        caseId: entry.key,
        role: entry.value,
        promotionCase: promotionCase,
        timelineCase: timelineByCase[entry.key],
      ),
    );
  }

  final summary = _summary(cases);
  final validation = _validation(cases, summary, errors);
  final violations = _list(validation['violations']);
  return {
    'schemaVersion': 'source_residual_delayed_recovery_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'promotionReport': promotionPath,
      'timelineReport': timelinePath,
    },
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'Residual delayed recovery may annotate pending candidate regions but must not relax the initial residual gate or switch production coordinates.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _caseReport({
  required String caseId,
  required String role,
  required Map<String, Object?> promotionCase,
  required Map<String, Object?>? timelineCase,
}) {
  final frames = _list(
    promotionCase['frames'],
  ).map(_map).map(_frameReport).toList(growable: false);
  final byTime = {
    for (final frame in frames) frame['observedAtJst']?.toString() ?? '': frame,
  }..remove('');
  final rejectedPositiveFrames = frames
      .where(
        (frame) =>
            frame['accepted'] == false && frame['candidateImproves'] == true,
      )
      .toList(growable: false);
  final delayedRecoveredFrames = rejectedPositiveFrames
      .where((frame) => _map(frame['delayedConfirmation'])['confirmed'] == true)
      .map((frame) {
        final delayed = _map(frame['delayedConfirmation']);
        final confirmingTime = delayed['confirmingObservedAtJst']?.toString();
        final confirmingFrame = byTime[confirmingTime];
        return {
          ...frame,
          'confirmingFrame': confirmingFrame,
          'recoveryMechanism': _recoveryMechanism(frame, confirmingFrame),
        };
      })
      .toList(growable: false);
  final acceptedPositiveFrames = frames
      .where(
        (frame) =>
            frame['accepted'] == true && frame['candidateImproves'] == true,
      )
      .toList(growable: false);

  return {
    'caseId': caseId,
    'role': role,
    'caseDiagnosis': _caseDiagnosis(
      role: role,
      delayedRecoveredFrames: delayedRecoveredFrames,
      rejectedPositiveFrames: rejectedPositiveFrames,
    ),
    'candidateFrameCount': frames.length,
    'acceptedPositiveFrameCount': acceptedPositiveFrames.length,
    'rejectedPositiveFrameCount': rejectedPositiveFrames.length,
    'delayedRecoveredPositiveFrameCount': delayedRecoveredFrames.length,
    'dualRegressionRejectedPositiveFrameCount': rejectedPositiveFrames
        .where((frame) => frame['dualResidualRegression'] == true)
        .length,
    'noSupportRejectedPositiveFrameCount': rejectedPositiveFrames
        .where(
          (frame) =>
              frame['rankSupportsCandidate'] == false &&
              frame['attenuationSupportsCandidate'] == false,
        )
        .length,
    'residualConfirmedDelayedCount': _intValue(
      _map(timelineCase)['residualConfirmedDelayedCount'],
    ),
    'localSupportConfirmedDelayedCount': _intValue(
      _map(timelineCase)['localSupportConfirmedDelayedCount'],
    ),
    'confirmedImmediateCount': _intValue(
      _map(timelineCase)['confirmedImmediateCount'],
    ),
    'coordinateSwitchAllowedCount': _intValue(
      _map(timelineCase)['coordinateSwitchAllowedCount'],
    ),
    'acceptedPositiveFrames': acceptedPositiveFrames,
    'rejectedPositiveFrames': rejectedPositiveFrames,
    'delayedRecoveredFrames': delayedRecoveredFrames,
  };
}

Map<String, Object?> _frameReport(Map<String, Object?> frame) {
  final gate = _map(frame['productionGate']);
  final offline = _map(frame['offlineEvaluation']);
  final delayed = _map(frame['delayedConfirmationDiagnostic']);
  final residuals = _map(frame['residuals']);
  final travel = _map(residuals['travelTimeRmsSeconds']);
  final rank = _map(residuals['rankInversionRate']);
  final attenuation = _map(residuals['attenuationRms']);
  return {
    'sourceFrameIndex': _intValue(frame['sourceFrameIndex']),
    'observedAtJst': frame['observedAtJst'],
    'accepted': gate['accepted'] == true,
    'candidateImproves': offline['candidateImprovesTruthError'] == true,
    'baselineErrorKm': _number(offline['baselineErrorKm']),
    'candidateErrorKm': _number(offline['candidateErrorKm']),
    'errorImprovementKm': _errorImprovementKm(offline),
    'rankSupportsCandidate': gate['rankSupportsCandidate'] == true,
    'attenuationSupportsCandidate':
        gate['attenuationSupportsCandidate'] == true,
    'dualResidualRegression': gate['dualResidualRegression'] == true,
    'rejectReasons': _list(
      gate['rejectReasons'],
    ).map((entry) => entry.toString()).toList(growable: false),
    'rankDelta': _number(gate['rankDelta']),
    'attenuationDelta': _number(gate['attenuationDelta']),
    'attenuationRatio': _number(gate['attenuationRatio']),
    'travelRatioDiagnosticOnly': _number(gate['travelRatioDiagnosticOnly']),
    'travelTimeRmsBaseline': _number(travel['baseline']),
    'travelTimeRmsCandidate': _number(travel['candidate']),
    'rankInversionBaseline': _number(rank['baseline']),
    'rankInversionCandidate': _number(rank['candidate']),
    'attenuationRmsBaseline': _number(attenuation['baseline']),
    'attenuationRmsCandidate': _number(attenuation['candidate']),
    'delayedConfirmation': delayed,
  };
}

Map<String, Object?> _recoveryMechanism(
  Map<String, Object?> rejectedFrame,
  Map<String, Object?>? confirmingFrame,
) {
  if (confirmingFrame == null) {
    return const {'status': 'missing_confirming_frame'};
  }
  return {
    'status': 'same_region_residual_confirmation',
    'confirmingObservedAtJst': confirmingFrame['observedAtJst'],
    'confirmingRankDelta': confirmingFrame['rankDelta'],
    'confirmingAttenuationDelta': confirmingFrame['attenuationDelta'],
    'confirmingRankSupportsCandidate':
        confirmingFrame['rankSupportsCandidate'] == true,
    'confirmingAttenuationSupportsCandidate':
        confirmingFrame['attenuationSupportsCandidate'] == true,
    'confirmingDualResidualRegression':
        confirmingFrame['dualResidualRegression'] == true,
    'rejectedRankDelta': rejectedFrame['rankDelta'],
    'rejectedAttenuationDelta': rejectedFrame['attenuationDelta'],
    'rejectedDualResidualRegression':
        rejectedFrame['dualResidualRegression'] == true,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'delayedRecoveredPositiveFrameCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['delayedRecoveredPositiveFrameCount']),
    ),
    'falseRecoveryGuardDelayedRecoveredFrameCount': cases.fold<int>(
      0,
      (sum, entry) => entry['role'] == 'false_recovery_guard'
          ? sum + _intValue(entry['delayedRecoveredPositiveFrameCount'])
          : sum,
    ),
    'positiveGuardDelayedRecoveredFrameCount': cases.fold<int>(
      0,
      (sum, entry) => entry['role'] == 'residual_delayed_positive_guard'
          ? sum + _intValue(entry['delayedRecoveredPositiveFrameCount'])
          : sum,
    ),
    'immediatePositiveGuardAcceptedFrameCount': cases.fold<int>(
      0,
      (sum, entry) => entry['role'] == 'residual_immediate_positive_guard'
          ? sum + _intValue(entry['acceptedPositiveFrameCount'])
          : sum,
    ),
    'productionCoordinateSwitchAllowedCount': cases.fold<int>(
      0,
      (sum, entry) => sum + _intValue(entry['coordinateSwitchAllowedCount']),
    ),
    'caseDiagnoses': {
      for (final entry in cases)
        entry['caseId'] as String: entry['caseDiagnosis'],
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
  final kushiro = byId['20260622_kushiro_offshore_m30_jma'];
  final tomakomai = byId['20260622_tomakomai_south_offshore_m35_hinet'];
  if (fukushima == null) violations.add('missing_fukushima_guard');
  if (kushiro == null) violations.add('missing_kushiro_guard');
  if (tomakomai == null) violations.add('missing_tomakomai_guard');
  if (_intValue(fukushima?['delayedRecoveredPositiveFrameCount']) != 0) {
    violations.add('fukushima_delayed_false_recovery');
  }
  if (_intValue(fukushima?['dualRegressionRejectedPositiveFrameCount']) < 1) {
    violations.add('fukushima_missing_dual_regression_guard_evidence');
  }
  if (_intValue(kushiro?['delayedRecoveredPositiveFrameCount']) != 3) {
    violations.add('kushiro_delayed_recovery_count_regressed');
  }
  if (_intValue(kushiro?['dualRegressionRejectedPositiveFrameCount']) != 0) {
    violations.add('kushiro_early_rejections_should_not_dual_regress');
  }
  if (_intValue(kushiro?['residualConfirmedDelayedCount']) != 1) {
    violations.add('kushiro_missing_residual_confirmed_delayed');
  }
  if (_intValue(tomakomai?['acceptedPositiveFrameCount']) != 3) {
    violations.add('tomakomai_immediate_positive_acceptance_regressed');
  }
  if (_intValue(tomakomai?['rejectedPositiveFrameCount']) != 0) {
    violations.add('tomakomai_unexpected_rejected_positive');
  }
  if (_intValue(tomakomai?['confirmedImmediateCount']) != 3) {
    violations.add('tomakomai_missing_immediate_confirmations');
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_present');
  }
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _caseDiagnosis({
  required String role,
  required List<Map<String, Object?>> delayedRecoveredFrames,
  required List<Map<String, Object?>> rejectedPositiveFrames,
}) {
  if (role == 'residual_delayed_positive_guard') {
    return delayedRecoveredFrames.length == 3
        ? 'same_region_residual_recovery_after_initial_no_support'
        : 'residual_delayed_recovery_regressed';
  }
  if (role == 'residual_immediate_positive_guard') {
    return rejectedPositiveFrames.isEmpty
        ? 'immediate_acceptance_by_dual_residual_support'
        : 'immediate_positive_guard_regressed';
  }
  final hasDualRegression = rejectedPositiveFrames.any(
    (frame) => frame['dualResidualRegression'] == true,
  );
  return delayedRecoveredFrames.isEmpty && hasDualRegression
      ? 'dual_regression_blocks_false_recovery'
      : 'false_recovery_guard_regressed';
}

double? _errorImprovementKm(Map<String, Object?> offline) {
  final baseline = _number(offline['baselineErrorKm']);
  final candidate = _number(offline['candidateErrorKm']);
  if (baseline == null || candidate == null) return null;
  return baseline - candidate;
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Residual Delayed-Recovery Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln(
      '- Delayed recovered positive frames: `${summary['delayedRecoveredPositiveFrameCount']}`',
    )
    ..writeln(
      '- False-recovery guard delayed recovered frames: `${summary['falseRecoveryGuardDelayedRecoveredFrameCount']}`',
    )
    ..writeln(
      '- Positive guard delayed recovered frames: `${summary['positiveGuardDelayedRecoveredFrameCount']}`',
    )
    ..writeln(
      '- Immediate positive guard accepted frames: `${summary['immediatePositiveGuardAcceptedFrameCount']}`',
    )
    ..writeln(
      '- Production coordinate switches: `${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Case Summary')
    ..writeln()
    ..writeln(
      '| Case | Role | Diagnosis | Rejected positive | Delayed recovered | Dual-reg rejected | Accepted positive | Immediate | Residual delayed | Switch |',
    )
    ..writeln(
      '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['role']}` | `${entry['caseDiagnosis']}` | '
      '${entry['rejectedPositiveFrameCount']} | '
      '${entry['delayedRecoveredPositiveFrameCount']} | '
      '${entry['dualRegressionRejectedPositiveFrameCount']} | '
      '${entry['acceptedPositiveFrameCount']} | '
      '${entry['confirmedImmediateCount']} | '
      '${entry['residualConfirmedDelayedCount']} | '
      '${entry['coordinateSwitchAllowedCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Delayed Recovered Frames')
    ..writeln()
    ..writeln(
      '| Case | Time | Delay | Base err | Cand err | Gain | Reject rank d | Reject atten r | Confirm time | Confirm rank d | Confirm atten d |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: |',
    );
  var wroteRecovered = false;
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    for (final rawFrame in _list(entry['delayedRecoveredFrames'])) {
      wroteRecovered = true;
      final frame = _map(rawFrame);
      final delayed = _map(frame['delayedConfirmation']);
      final recovery = _map(frame['recoveryMechanism']);
      buffer.writeln(
        '| `${entry['caseId']}` | `${frame['observedAtJst']}` | '
        '${_fmt(delayed['delaySeconds'], digits: 0)} | '
        '${_fmt(frame['baselineErrorKm'])} | '
        '${_fmt(frame['candidateErrorKm'])} | '
        '${_fmt(frame['errorImprovementKm'])} | '
        '${_fmt(frame['rankDelta'], digits: 3)} | '
        '${_fmt(frame['attenuationRatio'], digits: 2)} | '
        '`${recovery['confirmingObservedAtJst'] ?? '--'}` | '
        '${_fmt(recovery['confirmingRankDelta'], digits: 3)} | '
        '${_fmt(recovery['confirmingAttenuationDelta'], digits: 3)} |',
      );
    }
  }
  if (!wroteRecovered) {
    buffer.writeln('| -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |');
  }

  buffer
    ..writeln()
    ..writeln('## Immediate Accepted Positive Frames')
    ..writeln()
    ..writeln(
      '| Case | Time | Base err | Cand err | Gain | Rank d | Atten d | Atten r | Travel r |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  var wroteAccepted = false;
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    if (entry['role'] != 'residual_immediate_positive_guard') continue;
    for (final rawFrame in _list(entry['acceptedPositiveFrames'])) {
      wroteAccepted = true;
      final frame = _map(rawFrame);
      buffer.writeln(
        '| `${entry['caseId']}` | `${frame['observedAtJst']}` | '
        '${_fmt(frame['baselineErrorKm'])} | '
        '${_fmt(frame['candidateErrorKm'])} | '
        '${_fmt(frame['errorImprovementKm'])} | '
        '${_fmt(frame['rankDelta'], digits: 3)} | '
        '${_fmt(frame['attenuationDelta'], digits: 3)} | '
        '${_fmt(frame['attenuationRatio'], digits: 2)} | '
        '${_fmt(frame['travelRatioDiagnosticOnly'], digits: 2)} |',
      );
    }
  }
  if (!wroteAccepted) {
    buffer.writeln('| -- | -- | -- | -- | -- | -- | -- | -- | -- |');
  }

  buffer
    ..writeln()
    ..writeln('## False-Recovery Guard Rejected Positives')
    ..writeln()
    ..writeln(
      '| Case | Time | Base err | Cand err | Gain | Rank d | Atten r | Travel r | Dual regression | Reasons |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |',
    );
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    if (entry['role'] != 'false_recovery_guard') continue;
    for (final rawFrame in _list(entry['rejectedPositiveFrames'])) {
      final frame = _map(rawFrame);
      buffer.writeln(
        '| `${entry['caseId']}` | `${frame['observedAtJst']}` | '
        '${_fmt(frame['baselineErrorKm'])} | '
        '${_fmt(frame['candidateErrorKm'])} | '
        '${_fmt(frame['errorImprovementKm'])} | '
        '${_fmt(frame['rankDelta'], digits: 3)} | '
        '${_fmt(frame['attenuationRatio'], digits: 2)} | '
        '${_fmt(frame['travelRatioDiagnosticOnly'], digits: 2)} | '
        '${frame['dualResidualRegression'] == true ? 'yes' : 'no'} | '
        '${_codeList(_list(frame['rejectReasons']))} |',
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

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
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
