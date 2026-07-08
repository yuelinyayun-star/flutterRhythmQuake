import 'dart:convert';
import 'dart:io';

const _defaultReadinessPath =
    '.dart_tool/source_estimation_split_assignment_readiness/report.json';
const _defaultPromotionPath =
    '.dart_tool/source_candidate_promotion_report/matrix.json';
const _defaultTimelinePath =
    '.dart_tool/source_candidate_region_timeline_report/report.json';
const _defaultEarlyFrameDirectory =
    '.dart_tool/source_estimation_early_frame_report/matrix';
const _defaultOutputPath =
    '.dart_tool/source_estimation_diagnostic_ready/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_estimation_diagnostic_ready.generated.md';

void main(List<String> args) {
  final readinessPath = _argument(args, '--readiness') ?? _defaultReadinessPath;
  final promotionPath = _argument(args, '--promotion') ?? _defaultPromotionPath;
  final timelinePath = _argument(args, '--timeline') ?? _defaultTimelinePath;
  final earlyFrameDirectory =
      _argument(args, '--early-frame-directory') ?? _defaultEarlyFrameDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceEstimationDiagnosticReadyReportJson(
    readinessPath: readinessPath,
    promotionPath: promotionPath,
    timelinePath: timelinePath,
    earlyFrameDirectory: earlyFrameDirectory,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source-estimation diagnostic-ready report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if ((report['errors'] as List).isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceEstimationDiagnosticReadyReportJson({
  String readinessPath = _defaultReadinessPath,
  String promotionPath = _defaultPromotionPath,
  String timelinePath = _defaultTimelinePath,
  String earlyFrameDirectory = _defaultEarlyFrameDirectory,
}) {
  final errors = <String>[];
  final warnings = <String>[];

  final readiness = _readJsonFile(readinessPath, errors);
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
  for (final raw in _list(readiness['cases'])) {
    final readinessCase = _map(raw);
    if (readinessCase['datasetUseTier'] != 'diagnostic_ready') continue;
    final caseId = readinessCase['caseId']?.toString() ?? '';
    if (caseId.isEmpty) {
      errors.add('diagnostic_ready_case_missing_case_id');
      continue;
    }
    final earlyFramePath = '$earlyFrameDirectory/$caseId.json';
    final earlyFrame = _readOptionalJsonFile(earlyFramePath, warnings);
    final promotionCase = promotionByCase[caseId];
    final timelineCase = timelineByCase[caseId];
    cases.add(
      _caseJson(
        readinessCase: readinessCase,
        earlyFramePath: earlyFramePath,
        earlyFrame: earlyFrame,
        promotionCase: promotionCase,
        timelineCase: timelineCase,
      ),
    );
  }

  cases.sort(
    (left, right) =>
        (left['caseId'] as String).compareTo(right['caseId'] as String),
  );

  final actionCounts = <String, int>{};
  final roleCounts = <String, int>{};
  for (final entry in cases) {
    final action = entry['recommendedNextDiagnosticAction'] as String;
    final role = entry['diagnosticRole'] as String;
    actionCounts[action] = (actionCounts[action] ?? 0) + 1;
    roleCounts[role] = (roleCounts[role] ?? 0) + 1;
  }

  return {
    'schemaVersion': 'source_estimation_diagnostic_ready_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'readinessReportPath': readinessPath,
    'promotionReportPath': promotionPath,
    'timelineReportPath': timelinePath,
    'earlyFrameDirectory': earlyFrameDirectory,
    'summary': {
      'diagnosticReadyCount': cases.length,
      'strictMetricEligibleCount': 0,
      'productionCoordinateSwitchAllowedCount': cases.fold<int>(
        0,
        (sum, entry) =>
            sum +
            _intValue(_map(entry['timeline'])['coordinateSwitchAllowedCount']),
      ),
      'withEarlyFrameReportCount': cases
          .where((entry) => entry['earlyFrame'] != null)
          .length,
      'withPromotionReportCount': cases
          .where((entry) => entry['promotion'] != null)
          .length,
      'withTimelineReportCount': cases
          .where((entry) => entry['timeline'] != null)
          .length,
      'candidateFrameCount': cases.fold<int>(
        0,
        (sum, entry) =>
            sum + _intValue(_map(entry['promotion'])['candidateFrameCount']),
      ),
      'offlineMissedPositiveFrameCount': cases.fold<int>(
        0,
        (sum, entry) =>
            sum +
            _intValue(_map(entry['promotion'])['offlineMissedPositiveFrames']),
      ),
      'offlineFalseAcceptFrameCount': cases.fold<int>(
        0,
        (sum, entry) =>
            sum +
            _intValue(_map(entry['promotion'])['offlineFalseAcceptFrames']),
      ),
      'delayedRecoveredMissedPositiveFrameCount': cases.fold<int>(
        0,
        (sum, entry) =>
            sum +
            _intValue(
              _map(entry['promotion'])['delayedRecoveredMissedPositiveFrames'],
            ),
      ),
      'actionCounts': actionCounts,
      'diagnosticRoleCounts': roleCounts,
    },
    'policy': {
      'strictMetricEligible': false,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'diagnostic_ready cases may guide algorithm diagnosis only; do not use them for final metric claims or frozen split reporting.',
    },
    'errors': errors,
    'warnings': warnings,
    'cases': cases,
  };
}

Map<String, Object?> _caseJson({
  required Map<String, Object?> readinessCase,
  required String earlyFramePath,
  required Map<String, Object?>? earlyFrame,
  required Map<String, Object?>? promotionCase,
  required Map<String, Object?>? timelineCase,
}) {
  final promotion = _promotionSummary(promotionCase);
  final timeline = _timelineSummary(timelineCase);
  final early = _earlyFrameSummary(earlyFramePath, earlyFrame);
  final role = _diagnosticRole(readinessCase, promotionCase, timelineCase);
  final action = _recommendedAction(role, promotionCase, timelineCase);
  return {
    'caseId': readinessCase['caseId'],
    'datasetUseTier': readinessCase['datasetUseTier'],
    'datasetUseTierReason': readinessCase['datasetUseTierReason'],
    'diagnosticRole': role,
    'recommendedNextDiagnosticAction': action,
    'plannedUse': readinessCase['plannedUse'],
    'truthSource': readinessCase['truthSource'],
    'captureStatus': readinessCase['captureStatus'],
    'catalogOrReviewStatus': readinessCase['catalogOrReviewStatus'],
    'splitStatus': readinessCase['splitStatus'],
    'readyForFrozenSplit': readinessCase['readyForFrozenSplit'],
    'productionCoordinateSwitchAllowed': false,
    'earlyFrame': early,
    'promotion': promotion,
    'timeline': timeline,
  };
}

Map<String, Object?>? _earlyFrameSummary(
  String path,
  Map<String, Object?>? earlyFrame,
) {
  if (earlyFrame == null) return null;
  final frames = _list(earlyFrame['frames']).map(_map).toList(growable: false);
  final errors = [
    for (final frame in frames) _number(frame['errorKm']),
  ].whereType<double>().toList(growable: false);
  return {
    'path': path,
    'frameCount': frames.length,
    'firstErrorKm': errors.isEmpty ? null : errors.first,
    'finalErrorKm': errors.isEmpty ? null : errors.last,
    'worstErrorKm': errors.isEmpty
        ? null
        : errors.reduce((a, b) => a > b ? a : b),
    'findings': _list(earlyFrame['findings']),
  };
}

Map<String, Object?>? _promotionSummary(Map<String, Object?>? promotionCase) {
  if (promotionCase == null) return null;
  return {
    'earlyFrameCount': promotionCase['earlyFrameCount'],
    'candidateFrameCount': promotionCase['candidateFrameCount'],
    'acceptedCandidateFrames': promotionCase['acceptedCandidateFrames'],
    'rejectedCandidateFrames': promotionCase['rejectedCandidateFrames'],
    'offlineImprovedCandidateFrames':
        promotionCase['offlineImprovedCandidateFrames'],
    'offlineFalseAcceptFrames': promotionCase['offlineFalseAcceptFrames'],
    'offlineMissedPositiveFrames': promotionCase['offlineMissedPositiveFrames'],
    'delayedRecoveredMissedPositiveFrames':
        promotionCase['delayedRecoveredMissedPositiveFrames'],
    'delayedFalseRecoveryFrames': promotionCase['delayedFalseRecoveryFrames'],
    'findings': _list(promotionCase['findings']),
  };
}

Map<String, Object?>? _timelineSummary(Map<String, Object?>? timelineCase) {
  if (timelineCase == null) return null;
  return {
    'frameCount': timelineCase['frameCount'],
    'pendingCount': timelineCase['pendingCount'],
    'confirmedDelayedCount': timelineCase['confirmedDelayedCount'],
    'residualConfirmedDelayedCount':
        timelineCase['residualConfirmedDelayedCount'],
    'localSupportConfirmedDelayedCount':
        timelineCase['localSupportConfirmedDelayedCount'],
    'confirmedImmediateCount': timelineCase['confirmedImmediateCount'],
    'expiredCount': timelineCase['expiredCount'],
    'localSupportConfirmedCount': timelineCase['localSupportConfirmedCount'],
    'coordinateSwitchAllowedCount':
        timelineCase['coordinateSwitchAllowedCount'],
  };
}

String _diagnosticRole(
  Map<String, Object?> readinessCase,
  Map<String, Object?>? promotionCase,
  Map<String, Object?>? timelineCase,
) {
  final plannedUse = readinessCase['plannedUse']?.toString() ?? '';
  if (plannedUse.contains('false_recovery_guard')) {
    return 'false_recovery_guard';
  }
  if (plannedUse.contains('local_support')) {
    return 'local_support_positive_guard';
  }
  if (plannedUse.contains('residual')) {
    return 'residual_candidate_region_guard';
  }
  if (_intValue(promotionCase?['candidateFrameCount']) == 0 &&
      _intValue(timelineCase?['frameCount']) == 0) {
    return 'no_candidate_control';
  }
  return 'reference_pool';
}

String _recommendedAction(
  String role,
  Map<String, Object?>? promotionCase,
  Map<String, Object?>? timelineCase,
) {
  if (_intValue(promotionCase?['offlineMissedPositiveFrames']) > 0) {
    if (_intValue(promotionCase?['delayedRecoveredMissedPositiveFrames']) > 0) {
      return 'study_delayed_confirmation_recovery';
    }
    return 'inspect_candidate_rejection_residuals';
  }
  if (_intValue(timelineCase?['confirmedImmediateCount']) > 0) {
    return 'keep_as_positive_residual_guard';
  }
  if (_intValue(timelineCase?['localSupportConfirmedCount']) > 0) {
    return 'keep_as_local_support_guard';
  }
  if (role == 'no_candidate_control') return 'keep_as_no_candidate_control';
  if (role == 'false_recovery_guard') return 'keep_as_false_recovery_guard';
  return 'use_for_baseline_stability_review';
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final buffer = StringBuffer()
    ..writeln('# Source Estimation Diagnostic-Ready Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Diagnostic-ready cases: `${summary['diagnosticReadyCount']}`')
    ..writeln('- Strict metric eligible in this report: `0`')
    ..writeln(
      '- Production coordinate switch allowed: '
      '`${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln('- Candidate frames: `${summary['candidateFrameCount']}`')
    ..writeln(
      '- Offline missed positive frames: '
      '`${summary['offlineMissedPositiveFrameCount']}`',
    )
    ..writeln(
      '- Delayed recovered missed positives: '
      '`${summary['delayedRecoveredMissedPositiveFrameCount']}`',
    )
    ..writeln()
    ..writeln('## Policy')
    ..writeln()
    ..writeln(
      '- These cases are diagnostic-only. They may guide algorithm work, but '
      'must not be used for final metric claims or frozen split reporting.',
    )
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Role | Action | Planned use | Promotion | Timeline | Catalog/review |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');

  for (final raw in _list(report['cases'])) {
    final entry = _map(raw);
    final promotion = _map(entry['promotion']);
    final timeline = _map(entry['timeline']);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['diagnosticRole']}` | '
      '`${entry['recommendedNextDiagnosticAction']}` | '
      '`${entry['plannedUse']}` | '
      'cand `${promotion['candidateFrameCount'] ?? 'n/a'}`, '
      'accept `${promotion['acceptedCandidateFrames'] ?? 'n/a'}`, '
      'miss `${promotion['offlineMissedPositiveFrames'] ?? 'n/a'}` | '
      'imm `${timeline['confirmedImmediateCount'] ?? 'n/a'}`, '
      'delayed `${timeline['confirmedDelayedCount'] ?? 'n/a'}`, '
      'local `${timeline['localSupportConfirmedCount'] ?? 'n/a'}` | '
      '`${entry['catalogOrReviewStatus']}` |',
    );
  }
  return buffer.toString();
}

Map<String, Object?> _readJsonFile(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('json_file_missing:$path');
    return const {};
  }
  try {
    return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
  } catch (error) {
    errors.add('json_file_parse_failed:$path:$error');
    return const {};
  }
}

Map<String, Object?>? _readOptionalJsonFile(
  String path,
  List<String> warnings,
) {
  final file = File(path);
  if (!file.existsSync()) {
    warnings.add('optional_json_file_missing:$path');
    return null;
  }
  try {
    return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
  } catch (error) {
    warnings.add('optional_json_file_parse_failed:$path:$error');
    return null;
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
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
