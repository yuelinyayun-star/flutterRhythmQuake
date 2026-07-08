import 'dart:convert';
import 'dart:io';

const _defaultDiagnosticReadyPath =
    '.dart_tool/source_estimation_diagnostic_ready/report.json';
const _defaultPromotionPath =
    '.dart_tool/source_candidate_promotion_report/matrix.json';
const _defaultTimelinePath =
    '.dart_tool/source_candidate_region_timeline_report/report.json';
const _defaultOutputPath =
    '.dart_tool/source_candidate_rejection_residual_report/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_candidate_rejection_residual_report.generated.md';

const _expectedCoreCaseIds = {
  '20260621_fukushima_offshore_m32_eq6',
  '20260622_kushiro_offshore_m30_jma',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260625_iwate_offshore_m32_jma',
};

void main(List<String> args) {
  final diagnosticReadyPath =
      _argument(args, '--diagnostic-ready') ?? _defaultDiagnosticReadyPath;
  final promotionPath = _argument(args, '--promotion') ?? _defaultPromotionPath;
  final timelinePath = _argument(args, '--timeline') ?? _defaultTimelinePath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceCandidateRejectionResidualReportJson(
    diagnosticReadyPath: diagnosticReadyPath,
    promotionPath: promotionPath,
    timelinePath: timelinePath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source candidate rejection residual report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceCandidateRejectionResidualReportJson({
  String diagnosticReadyPath = _defaultDiagnosticReadyPath,
  String promotionPath = _defaultPromotionPath,
  String timelinePath = _defaultTimelinePath,
}) {
  final errors = <String>[];
  final diagnosticReady = _readJsonFile(diagnosticReadyPath, errors);
  final promotion = _readJsonFile(promotionPath, errors);
  final timeline = _readJsonFile(timelinePath, errors);

  final diagnosticByCase = {
    for (final raw in _list(diagnosticReady['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');
  final promotionByCase = {
    for (final raw in _list(promotion['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');
  final timelineByCase = {
    for (final raw in _list(timeline['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');

  final cases = <Map<String, Object?>>[];
  for (final caseId in _expectedCoreCaseIds.toList()..sort()) {
    final diagnosticCase = diagnosticByCase[caseId];
    final promotionCase = promotionByCase[caseId];
    final timelineCase = timelineByCase[caseId];
    if (diagnosticCase == null) {
      errors.add('missing_diagnostic_case:$caseId');
      continue;
    }
    if (promotionCase == null) {
      errors.add('missing_promotion_case:$caseId');
      continue;
    }
    cases.add(
      _caseReport(
        diagnosticCase: diagnosticCase,
        promotionCase: promotionCase,
        timelineCase: timelineCase,
      ),
    );
  }

  final summary = _summary(cases);
  final validation = _validation(cases, summary, errors);
  final violations = _list(validation['violations']);
  final status = errors.isEmpty && violations.isEmpty ? 'pass' : 'fail';

  return {
    'schemaVersion': 'source_candidate_rejection_residual_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': status,
    'inputs': {
      'diagnosticReadyReport': diagnosticReadyPath,
      'promotionReport': promotionPath,
      'timelineReport': timelinePath,
    },
    'policy': const {
      'diagnosticOnly': true,
      'strictMetricEligible': false,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'This report explains candidate-region gate behavior only. It must not replace production source coordinates.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _caseReport({
  required Map<String, Object?> diagnosticCase,
  required Map<String, Object?> promotionCase,
  required Map<String, Object?>? timelineCase,
}) {
  final caseId = diagnosticCase['caseId']?.toString() ?? '';
  final promotionFrames = _list(
    promotionCase['frames'],
  ).map(_map).toList(growable: false);
  final timelineFrames = _list(
    timelineCase?['frames'],
  ).map(_map).toList(growable: false);
  final timelineByTime = {
    for (final frame in timelineFrames)
      frame['observedAtJst']?.toString() ?? '': frame,
  }..remove('');

  final frameDiagnostics = <Map<String, Object?>>[];
  for (final frame in promotionFrames) {
    final time = frame['observedAtJst']?.toString();
    final gate = _map(frame['productionGate']);
    final offline = _map(frame['offlineEvaluation']);
    final delayed = _map(frame['delayedConfirmationDiagnostic']);
    final timelineFrame = timelineByTime[time];
    frameDiagnostics.add(
      _frameDiagnostic(
        frame: frame,
        gate: gate,
        offline: offline,
        delayed: delayed,
        timelineFrame: timelineFrame,
      ),
    );
  }

  final rejectedOfflineImproved = frameDiagnostics
      .where(
        (frame) =>
            frame['accepted'] == false && frame['candidateImproves'] == true,
      )
      .length;
  final localSupportConfirmed = _intValue(
    timelineCase?['localSupportConfirmedCount'],
  );
  final residualDelayed = _intValue(
    timelineCase?['residualConfirmedDelayedCount'],
  );

  return {
    'caseId': caseId,
    'diagnosticRole': diagnosticCase['diagnosticRole'],
    'recommendedNextDiagnosticAction':
        diagnosticCase['recommendedNextDiagnosticAction'],
    'plannedUse': diagnosticCase['plannedUse'],
    'datasetUseTier': diagnosticCase['datasetUseTier'],
    'caseDiagnosis': _caseDiagnosis(
      diagnosticCase,
      promotionCase,
      timelineCase,
    ),
    'promotion': {
      'candidateFrameCount': _intValue(promotionCase['candidateFrameCount']),
      'acceptedCandidateFrames': _intValue(
        promotionCase['acceptedCandidateFrames'],
      ),
      'rejectedCandidateFrames': _intValue(
        promotionCase['rejectedCandidateFrames'],
      ),
      'offlineImprovedCandidateFrames': _intValue(
        promotionCase['offlineImprovedCandidateFrames'],
      ),
      'offlineFalseAcceptFrames': _intValue(
        promotionCase['offlineFalseAcceptFrames'],
      ),
      'offlineMissedPositiveFrames': _intValue(
        promotionCase['offlineMissedPositiveFrames'],
      ),
      'delayedRecoveredMissedPositiveFrames': _intValue(
        promotionCase['delayedRecoveredMissedPositiveFrames'],
      ),
    },
    'timeline': timelineCase == null
        ? null
        : {
            'frameCount': _intValue(timelineCase['frameCount']),
            'pendingCount': _intValue(timelineCase['pendingCount']),
            'confirmedDelayedCount': _intValue(
              timelineCase['confirmedDelayedCount'],
            ),
            'residualConfirmedDelayedCount': residualDelayed,
            'localSupportConfirmedDelayedCount': _intValue(
              timelineCase['localSupportConfirmedDelayedCount'],
            ),
            'confirmedImmediateCount': _intValue(
              timelineCase['confirmedImmediateCount'],
            ),
            'expiredCount': _intValue(timelineCase['expiredCount']),
            'localSupportConfirmedCount': localSupportConfirmed,
            'coordinateSwitchAllowedCount': _intValue(
              timelineCase['coordinateSwitchAllowedCount'],
            ),
          },
    'rejectedOfflineImprovedFrameCount': rejectedOfflineImproved,
    'frameDiagnostics': frameDiagnostics,
    'timelineDiagnostics': timelineFrames
        .map(_timelineDiagnostic)
        .toList(growable: false),
  };
}

Map<String, Object?> _frameDiagnostic({
  required Map<String, Object?> frame,
  required Map<String, Object?> gate,
  required Map<String, Object?> offline,
  required Map<String, Object?> delayed,
  required Map<String, Object?>? timelineFrame,
}) {
  final accepted = gate['accepted'] == true;
  final candidateImproves = offline['candidateImprovesTruthError'] == true;
  final delayedConfirmed = delayed['confirmed'] == true;
  return {
    'sourceFrameIndex': _intValue(frame['sourceFrameIndex']),
    'observedAtJst': frame['observedAtJst'],
    'diagnosis': _frameDiagnosis(
      accepted: accepted,
      candidateImproves: candidateImproves,
      delayedConfirmed: delayedConfirmed,
      timelineFrame: timelineFrame,
    ),
    'accepted': accepted,
    'candidateImproves': candidateImproves,
    'baselineErrorKm': _number(offline['baselineErrorKm']),
    'candidateErrorKm': _number(offline['candidateErrorKm']),
    'errorImprovementKm': _errorImprovementKm(offline),
    'rankDelta': _number(gate['rankDelta']),
    'attenuationDelta': _number(gate['attenuationDelta']),
    'attenuationRatio': _number(gate['attenuationRatio']),
    'travelRatioDiagnosticOnly': _number(gate['travelRatioDiagnosticOnly']),
    'dualResidualRegression': gate['dualResidualRegression'] == true,
    'rejectReasons': _list(
      gate['rejectReasons'],
    ).map((entry) => entry.toString()).toList(growable: false),
    'delayedConfirmationDiagnostic': delayed,
    'timelineLocalSupport': timelineFrame == null
        ? null
        : {
            'status': timelineFrame['status'],
            'reason': timelineFrame['reason'],
            'confirmed': timelineFrame['localSupportConfirmed'] == true,
            'memberCount': _intValue(timelineFrame['localSupportMemberCount']),
            'memberCountGrowth': _nullableInt(
              timelineFrame['localSupportMemberCountGrowth'],
            ),
            'estimateMemberDistanceKm': _number(
              timelineFrame['localSupportEstimateMemberDistanceKm'],
            ),
            'convergenceKm': _number(
              timelineFrame['localSupportConvergenceKm'],
            ),
            'geometry': timelineFrame['localSupportGeometry'],
          },
  };
}

Map<String, Object?> _timelineDiagnostic(Map<String, Object?> frame) => {
  'observedAtJst': frame['observedAtJst'],
  'status': frame['status'],
  'reason': frame['reason'],
  'residualSupported': frame['residualSupported'] == true,
  'localSupportConfirmed': frame['localSupportConfirmed'] == true,
  'productionCoordinateSwitchAllowed':
      frame['productionCoordinateSwitchAllowed'] == true,
  'memberCount': _intValue(frame['localSupportMemberCount']),
  'memberCountGrowth': _nullableInt(frame['localSupportMemberCountGrowth']),
  'estimateMemberDistanceKm': _number(
    frame['localSupportEstimateMemberDistanceKm'],
  ),
  'convergenceKm': _number(frame['localSupportConvergenceKm']),
  'geometry': frame['localSupportGeometry'],
};

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  final inspectCases = cases
      .where(
        (entry) =>
            entry['recommendedNextDiagnosticAction'] ==
            'inspect_candidate_rejection_residuals',
      )
      .toList(growable: false);
  return {
    'coreCaseCount': cases.length,
    'inspectCandidateRejectionCaseCount': inspectCases.length,
    'candidateFrameCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(_map(entry['promotion'])['candidateFrameCount']),
    ),
    'coreRejectedOfflineImprovedFrameCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['rejectedOfflineImprovedFrameCount']),
    ),
    'inspectRejectedOfflineImprovedFrameCount': inspectCases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(entry['rejectedOfflineImprovedFrameCount']),
    ),
    'offlineFalseAcceptFrameCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum + _intValue(_map(entry['promotion'])['offlineFalseAcceptFrames']),
    ),
    'productionCoordinateSwitchAllowedCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum +
          _intValue(_map(entry['timeline'])['coordinateSwitchAllowedCount']),
    ),
    'residualDelayedRecoveredFrameCount': cases.fold<int>(
      0,
      (sum, entry) =>
          sum +
          _intValue(
            _map(entry['promotion'])['delayedRecoveredMissedPositiveFrames'],
          ),
    ),
    'localSupportConfirmedDelayedCaseCount': cases
        .where(
          (entry) =>
              _intValue(
                _map(entry['timeline'])['localSupportConfirmedDelayedCount'],
              ) >
              0,
        )
        .length,
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
  for (final caseId in _expectedCoreCaseIds) {
    if (!byId.containsKey(caseId)) violations.add('missing_core_case:$caseId');
  }
  if (_intValue(summary['inspectCandidateRejectionCaseCount']) != 2) {
    violations.add('unexpected_inspect_case_count');
  }
  if (_intValue(summary['inspectRejectedOfflineImprovedFrameCount']) != 10) {
    violations.add('unexpected_inspect_rejected_offline_improved_count');
  }
  if (_intValue(summary['coreRejectedOfflineImprovedFrameCount']) != 13) {
    violations.add('unexpected_core_rejected_offline_improved_count');
  }
  if (_intValue(summary['offlineFalseAcceptFrameCount']) != 0) {
    violations.add('offline_false_accepts_present');
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_present');
  }

  final fukushima = byId['20260621_fukushima_offshore_m32_eq6'];
  if (_intValue(_map(fukushima?['timeline'])['confirmedDelayedCount']) != 0) {
    violations.add('fukushima_unexpected_delayed_confirmation');
  }
  if (_intValue(fukushima?['rejectedOfflineImprovedFrameCount']) != 7) {
    violations.add('fukushima_unexpected_rejected_positive_count');
  }

  final kushiro = byId['20260622_kushiro_offshore_m30_jma'];
  if (_intValue(
        _map(kushiro?['promotion'])['delayedRecoveredMissedPositiveFrames'],
      ) !=
      3) {
    violations.add('kushiro_delayed_recovery_regressed');
  }

  final tomakomai = byId['20260622_tomakomai_south_offshore_m35_hinet'];
  if (_intValue(_map(tomakomai?['promotion'])['acceptedCandidateFrames']) !=
      3) {
    violations.add('tomakomai_immediate_positive_regressed');
  }

  final iwate = byId['20260625_iwate_offshore_m32_jma'];
  if (_intValue(
        _map(iwate?['timeline'])['localSupportConfirmedDelayedCount'],
      ) !=
      1) {
    violations.add('iwate_local_support_recovery_regressed');
  }
  if (_intValue(iwate?['rejectedOfflineImprovedFrameCount']) != 3) {
    violations.add('iwate_unexpected_rejected_positive_count');
  }

  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'expectedCoreCases': (_expectedCoreCaseIds.toList()..sort()),
    'violations': violations,
  };
}

String _caseDiagnosis(
  Map<String, Object?> diagnosticCase,
  Map<String, Object?> promotionCase,
  Map<String, Object?>? timelineCase,
) {
  final action = diagnosticCase['recommendedNextDiagnosticAction'];
  final accepted = _intValue(promotionCase['acceptedCandidateFrames']);
  final missed = _intValue(promotionCase['offlineMissedPositiveFrames']);
  final residualDelayed = _intValue(
    timelineCase?['residualConfirmedDelayedCount'],
  );
  final localDelayed = _intValue(
    timelineCase?['localSupportConfirmedDelayedCount'],
  );
  if (action == 'inspect_candidate_rejection_residuals' && localDelayed > 0) {
    return 'local_support_recovers_residual_rejection';
  }
  if (action == 'inspect_candidate_rejection_residuals' && missed > 0) {
    return 'residual_gate_rejects_offline_positive_candidates';
  }
  if (residualDelayed > 0) return 'residual_delayed_recovery_positive_guard';
  if (accepted > 0) return 'residual_immediate_positive_guard';
  return 'diagnostic_control';
}

String _frameDiagnosis({
  required bool accepted,
  required bool candidateImproves,
  required bool delayedConfirmed,
  required Map<String, Object?>? timelineFrame,
}) {
  if (accepted && candidateImproves) return 'accepted_positive';
  if (accepted && !candidateImproves) return 'accepted_false_positive';
  if (!accepted && candidateImproves && delayedConfirmed) {
    return 'residual_delayed_recovered_positive';
  }
  if (!accepted &&
      candidateImproves &&
      timelineFrame?['localSupportConfirmed'] == true) {
    return 'local_support_recovered_positive';
  }
  if (!accepted && candidateImproves) return 'rejected_offline_positive';
  return 'rejected_non_positive';
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
    ..writeln('# Source Candidate Rejection Residual Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Core cases: `${summary['coreCaseCount']}`')
    ..writeln(
      '- Inspect rejection cases: `${summary['inspectCandidateRejectionCaseCount']}`',
    )
    ..writeln(
      '- Inspect rejected offline-positive frames: `${summary['inspectRejectedOfflineImprovedFrameCount']}`',
    )
    ..writeln(
      '- Core rejected offline-positive frames: `${summary['coreRejectedOfflineImprovedFrameCount']}`',
    )
    ..writeln(
      '- Offline false accepts: `${summary['offlineFalseAcceptFrameCount']}`',
    )
    ..writeln(
      '- Production coordinate switches: `${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Policy')
    ..writeln()
    ..writeln(
      '- Diagnostic-only. Candidate coordinates remain blocked from production switching.',
    )
    ..writeln(
      '- Truth-error columns are offline labels used only to inspect gate behavior.',
    )
    ..writeln()
    ..writeln('## Case Summary')
    ..writeln()
    ..writeln(
      '| Case | Action | Diagnosis | Cand | Accept | Miss | Delayed | Local delayed | Switch |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    final promotion = _map(entry['promotion']);
    final timeline = _map(entry['timeline']);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['recommendedNextDiagnosticAction']}` | '
      '`${entry['caseDiagnosis']}` | '
      '${promotion['candidateFrameCount']} | '
      '${promotion['acceptedCandidateFrames']} | '
      '${promotion['offlineMissedPositiveFrames']} | '
      '${promotion['delayedRecoveredMissedPositiveFrames']} | '
      '${timeline['localSupportConfirmedDelayedCount'] ?? 'n/a'} | '
      '${timeline['coordinateSwitchAllowedCount'] ?? 'n/a'} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Rejected Offline-Positive Frames')
    ..writeln();

  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    final frames = _list(entry['frameDiagnostics'])
        .map(_map)
        .where(
          (frame) =>
              frame['accepted'] == false && frame['candidateImproves'] == true,
        )
        .toList(growable: false);
    if (frames.isEmpty) continue;
    buffer
      ..writeln('### ${entry['caseId']}')
      ..writeln()
      ..writeln(
        '| Time | Diagnosis | Base err | Cand err | Gain | Rank d | Atten d | Atten r | Travel r | Local support | Reject reason |',
      )
      ..writeln(
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |',
      );
    for (final frame in frames) {
      final local = _map(frame['timelineLocalSupport']);
      buffer.writeln(
        '| `${frame['observedAtJst']}` | `${frame['diagnosis']}` | '
        '${_fmt(frame['baselineErrorKm'])} | '
        '${_fmt(frame['candidateErrorKm'])} | '
        '${_fmt(frame['errorImprovementKm'])} | '
        '${_fmt(frame['rankDelta'], digits: 3)} | '
        '${_fmt(frame['attenuationDelta'], digits: 3)} | '
        '${_fmt(frame['attenuationRatio'], digits: 2)} | '
        '${_fmt(frame['travelRatioDiagnosticOnly'], digits: 2)} | '
        '${_localSupportLabel(local)} | '
        '${_codeList(_list(frame['rejectReasons']))} |',
      );
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Candidate-Region Timeline Diagnostics')
    ..writeln()
    ..writeln(
      '| Case | Time | Status | Reason | Residual | Local support | Members | Est-member | Converge | Geometry | Switch |',
    )
    ..writeln(
      '| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |',
    );

  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    for (final rawFrame in _list(entry['timelineDiagnostics'])) {
      final frame = _map(rawFrame);
      buffer.writeln(
        '| `${entry['caseId']}` | `${frame['observedAtJst']}` | '
        '`${frame['status']}` | `${frame['reason']}` | '
        '${frame['residualSupported'] == true ? 'yes' : 'no'} | '
        '${frame['localSupportConfirmed'] == true ? 'yes' : 'no'} | '
        '${frame['memberCount'] ?? '--'} | '
        '${_fmt(frame['estimateMemberDistanceKm'])} | '
        '${_fmt(frame['convergenceKm'])} | '
        '`${frame['geometry'] ?? '--'}` | '
        '${frame['productionCoordinateSwitchAllowed'] == true ? 'yes' : 'no'} |',
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

String _localSupportLabel(Map<String, Object?> local) {
  if (local.isEmpty) return '--';
  final status = local['status'] ?? '--';
  final members = local['memberCount'] ?? '--';
  final distance = _fmt(local['estimateMemberDistanceKm']);
  final convergence = _fmt(local['convergenceKm']);
  final geometry = local['geometry'] ?? '--';
  return '`$status`, m=$members, d=$distance, conv=$convergence, `$geometry`';
}

String _codeList(List<Object?> items) {
  if (items.isEmpty) return '--';
  return items.map((item) => '`${item.toString()}`').join(', ');
}

String _fmt(Object? value, {int digits = 1}) {
  final number = _number(value);
  if (number == null || !number.isFinite) return '--';
  return number.toStringAsFixed(digits);
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
