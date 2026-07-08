import 'dart:convert';
import 'dart:io';

const _defaultReadinessPath =
    '.dart_tool/source_estimation_split_assignment_readiness/report.json';
const _defaultBlockerPath =
    '.dart_tool/source_estimation_split_blocker_queue/report.json';
const _defaultOutputPath =
    '.dart_tool/source_metric_readiness_triage/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_metric_readiness_triage.generated.md';

void main(List<String> args) {
  final readinessPath = _argument(args, '--readiness') ?? _defaultReadinessPath;
  final blockerPath = _argument(args, '--blockers') ?? _defaultBlockerPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceMetricReadinessTriageReportJson(
    readinessPath: readinessPath,
    blockerPath: blockerPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source metric-readiness triage report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceMetricReadinessTriageReportJson({
  String readinessPath = _defaultReadinessPath,
  String blockerPath = _defaultBlockerPath,
}) {
  final errors = <String>[];
  final readiness = _readJsonFile(readinessPath, errors);
  final blocker = _readJsonFile(blockerPath, errors);
  final readinessCases = _list(
    readiness['cases'],
  ).map(_map).map(_triageCase).toList(growable: false);
  final blockerCases = _list(
    blocker['blockers'],
  ).map(_map).toList(growable: false);
  final completedCases = _list(
    blocker['completedSplitAssignments'],
  ).map(_map).toList(growable: false);

  final summary = _summary(readinessCases, blockerCases, completedCases);
  final validation = _validation(
    readiness: readiness,
    blocker: blocker,
    cases: readinessCases,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_metric_readiness_triage_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'splitAssignmentReadiness': readinessPath,
      'splitBlockerQueue': blockerPath,
    },
    'policy': const {
      'diagnosticOnly': true,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'notes':
          'This report triages existing readiness evidence. It does not promote diagnostic-ready cases into metric-bearing splits.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': readinessCases,
    'blockedCases': blockerCases,
    'completedSplitAssignments': completedCases,
  };
}

Map<String, Object?> _triageCase(Map<String, Object?> entry) {
  final constraints = _constraints(entry);
  final tier = entry['datasetUseTier']?.toString() ?? '';
  final readyForFrozenSplit = entry['readyForFrozenSplit'] == true;
  final nextAction = entry['nextAction']?.toString() ?? '';
  final labelStatus = _referenceLabelStatus(entry);
  final metricBearingReady =
      readyForFrozenSplit &&
      !constraints.contains('do_not_treat_as_catalog_truth') &&
      !constraints.contains('do_not_use_for_final_test_claims') &&
      entry['catalogTruthVerified'] == true;
  final triageTier = metricBearingReady
      ? 'metric_bearing_ready'
      : readyForFrozenSplit
      ? 'reference_validation_only'
      : tier == 'diagnostic_ready'
      ? 'diagnostic_ready_blocked'
      : 'metadata_only_or_incomplete';
  return {
    'caseId': entry['caseId'],
    'triageTier': triageTier,
    'datasetUseTier': tier,
    'plannedUse': entry['plannedUse'],
    'truthSource': entry['truthSource'],
    'referenceLabelStatus': labelStatus,
    'referenceLabelSource': _referenceLabelSource(entry),
    'catalogTruthVerified': entry['catalogTruthVerified'] == true,
    'splitStatus': entry['splitStatus'],
    'captureStatus': entry['captureStatus'],
    'catalogOrReviewStatus': entry['catalogOrReviewStatus'],
    'readyForFrozenSplit': readyForFrozenSplit,
    'readyForManualSplitAssignment':
        entry['readyForManualSplitAssignment'] == true,
    'nextAction': nextAction,
    'manualSplitConstraints': constraints,
    'metricBearingReady': metricBearingReady,
    'metricBlockingReason': _metricBlockingReason(
      entry: entry,
      triageTier: triageTier,
      constraints: constraints,
      referenceLabelStatus: labelStatus,
    ),
  };
}

String _metricBlockingReason({
  required Map<String, Object?> entry,
  required String triageTier,
  required List<String> constraints,
  required String referenceLabelStatus,
}) {
  if (triageTier == 'metric_bearing_ready') return 'none';
  if (triageTier == 'reference_validation_only') {
    if (constraints.contains('do_not_use_for_final_test_claims')) {
      return 'reference_only_validation_not_for_final_metric_claims';
    }
    if (constraints.contains('do_not_treat_as_catalog_truth')) {
      return 'reference_only_not_catalog_truth';
    }
    return 'reference_validation_only';
  }
  if (triageTier == 'diagnostic_ready_blocked') {
    if (entry['nextAction'] == 'review_jma_catalog_link' &&
        referenceLabelStatus == 'jma_reference_label_available') {
      return 'jma_reference_label_available_final_catalog_link_pending';
    }
    return entry['nextAction']?.toString() ?? 'unknown_next_action';
  }
  return entry['datasetUseTierReason']?.toString() ??
      'metadata_or_capture_incomplete';
}

String _referenceLabelStatus(Map<String, Object?> entry) {
  final truthSource = entry['truthSource']?.toString().toLowerCase() ?? '';
  if (truthSource.contains('jma_source_and_intensity') ||
      truthSource == 'jma') {
    return 'jma_reference_label_available';
  }
  if (truthSource.contains('hinet')) {
    return 'hinet_reference_label_available';
  }
  if (truthSource.contains('equake')) {
    return 'equake_reference_label_available';
  }
  return truthSource.isEmpty
      ? 'reference_label_unknown'
      : 'reference_label_available';
}

String _referenceLabelSource(Map<String, Object?> entry) {
  final status = _referenceLabelStatus(entry);
  if (status == 'jma_reference_label_available') {
    final catalogStatus = entry['catalogOrReviewStatus']?.toString() ?? '';
    return catalogStatus == 'jma_final_catalog_missing_for_recent_event'
        ? 'jma_source_and_intensity_label_not_final_catalog'
        : 'jma_label';
  }
  return entry['truthSource']?.toString() ?? 'unknown';
}

Map<String, Object?> _summary(
  List<Map<String, Object?>> cases,
  List<Map<String, Object?>> blockers,
  List<Map<String, Object?>> completed,
) {
  return {
    'caseCount': cases.length,
    'metricBearingReadyCount': cases
        .where((entry) => entry['triageTier'] == 'metric_bearing_ready')
        .length,
    'referenceValidationOnlyCount': cases
        .where((entry) => entry['triageTier'] == 'reference_validation_only')
        .length,
    'diagnosticReadyBlockedCount': cases
        .where((entry) => entry['triageTier'] == 'diagnostic_ready_blocked')
        .length,
    'metadataOnlyOrIncompleteCount': cases
        .where((entry) => entry['triageTier'] == 'metadata_only_or_incomplete')
        .length,
    'blockedCaseCount': blockers.length,
    'completedSplitAssignmentCount': completed.length,
    'readyForManualSplitAssignmentCount': cases
        .where((entry) => entry['readyForManualSplitAssignment'] == true)
        .length,
    'candidateRegionDiagnosticBlockedCount': cases
        .where(
          (entry) =>
              entry['triageTier'] == 'diagnostic_ready_blocked' &&
              entry['plannedUse']?.toString().contains('candidate_region') ==
                  true,
        )
        .length,
    'referenceLabelAvailableCount': cases
        .where(
          (entry) =>
              entry['referenceLabelStatus']?.toString().endsWith(
                '_reference_label_available',
              ) ==
              true,
        )
        .length,
    'jmaReferenceLabelAvailableCount': cases
        .where(
          (entry) =>
              entry['referenceLabelStatus'] == 'jma_reference_label_available',
        )
        .length,
    'nextActionCounts': _counts(cases.map((entry) => entry['nextAction'])),
    'triageTierCounts': _counts(cases.map((entry) => entry['triageTier'])),
    'referenceLabelStatusCounts': _counts(
      cases.map((entry) => entry['referenceLabelStatus']),
    ),
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> readiness,
  required Map<String, Object?> blocker,
  required List<Map<String, Object?>> cases,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (readiness['status'] != 'pass') {
    violations.add('split_assignment_readiness_not_pass');
  }
  if (blocker['status'] != 'pass') {
    violations.add('split_blocker_queue_not_pass');
  }
  if (_intValue(summary['caseCount']) != 19) {
    violations.add('unexpected_case_count');
  }
  if (_intValue(summary['metricBearingReadyCount']) != 0) {
    violations.add('unexpected_metric_bearing_ready_case');
  }
  if (_intValue(summary['referenceValidationOnlyCount']) != 7) {
    violations.add('reference_validation_only_count_changed');
  }
  if (_intValue(summary['diagnosticReadyBlockedCount']) != 8) {
    violations.add('diagnostic_ready_blocked_count_changed');
  }
  if (_intValue(summary['metadataOnlyOrIncompleteCount']) != 4) {
    violations.add('metadata_only_or_incomplete_count_changed');
  }
  final byCaseId = {
    for (final entry in cases) entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  for (final caseId in [
    '20260622_kushiro_offshore_m30_jma',
    '20260625_iwate_offshore_m32_jma',
    '20260621_fukushima_offshore_m32_eq6',
    '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
    '20260627_fukushima_aizu_m36_jma_equake17',
  ]) {
    if (byCaseId[caseId]?['triageTier'] != 'diagnostic_ready_blocked') {
      violations.add('$caseId:not_diagnostic_ready_blocked');
    }
  }
  if (byCaseId['20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8']?['triageTier'] !=
      'metadata_only_or_incomplete') {
    violations.add(
      '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8:'
      'not_metadata_only_or_incomplete',
    );
  }
  for (final caseId in [
    '20260622_fukushima_offshore_m22_eq4',
    '20260622_iwate_east_offshore_m30_hinet',
    '20260622_iwate_offshore_m30_eq10',
    '20260622_tomakomai_south_offshore_m35_hinet',
    '20260622_wakayama_south_m25_hinet',
    '20260623_tokachi_southeast_offshore_m34_hinet',
    'noto_m27_20260621_jma_eq5',
  ]) {
    if (byCaseId[caseId]?['triageTier'] != 'reference_validation_only') {
      violations.add('$caseId:not_reference_validation_only');
    }
  }
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Metric-Readiness Triage')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln('- Metric-bearing ready: `${summary['metricBearingReadyCount']}`')
    ..writeln(
      '- Reference-validation only: '
      '`${summary['referenceValidationOnlyCount']}`',
    )
    ..writeln(
      '- Diagnostic-ready blocked: '
      '`${summary['diagnosticReadyBlockedCount']}`',
    )
    ..writeln(
      '- Metadata-only/incomplete: '
      '`${summary['metadataOnlyOrIncompleteCount']}`',
    )
    ..writeln(
      '- Ready for manual split assignment: '
      '`${summary['readyForManualSplitAssignmentCount']}`',
    )
    ..writeln(
      '- Reference labels available: '
      '`${summary['referenceLabelAvailableCount']}`',
    )
    ..writeln(
      '- JMA reference labels available: '
      '`${summary['jmaReferenceLabelAvailableCount']}`',
    )
    ..writeln()
    ..writeln('## Triage')
    ..writeln()
    ..writeln(
      '| Case | Triage | Label | Planned use | Split | Next action | Metric blocker |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['triageTier']}` | '
      '`${entry['referenceLabelStatus']}` | `${entry['plannedUse']}` | '
      '`${entry['splitStatus']}` | '
      '`${entry['nextAction']}` | `${entry['metricBlockingReason']}` |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- No current case is ready for metric-bearing validation or final accuracy claims.',
    )
    ..writeln(
      '- The `${summary['referenceValidationOnlyCount']}` strict-ready cases remain reference-validation only because their constraints forbid final test claims and catalog-truth use.',
    )
    ..writeln(
      '- The `${summary['diagnosticReadyBlockedCount']}` diagnostic-ready cases remain useful for algorithm diagnostics but are blocked by JMA catalog, Hi-net review, final-catalog/revision evidence, or diagnostic-only PLUM replay scope.',
    )
    ..writeln(
      '- PLUM-like replay lead-time cases marked `keep_plum_like_diagnostic_only` must not be promoted into metric-bearing source-estimation split assignment from this report.',
    )
    ..writeln(
      '- JMA source-and-intensity labels count as reference labels for diagnostic use; the pending final-catalog link only blocks metric-bearing truth claims.',
    )
    ..writeln(
      '- Manual-ready constrained references still require explicit event-level split assignment before they can leave the blocker queue.',
    )
    ..writeln(
      '- The `${summary['metadataOnlyOrIncompleteCount']}` metadata-only/incomplete cases remain blocked by capture provenance or incomplete local replay packages.',
    )
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

List<String> _constraints(Map<String, Object?> entry) {
  final recommendation = _map(entry['manualSplitRecommendation']);
  return _list(
    recommendation['constraints'],
  ).map((value) => value.toString()).toList(growable: false);
}

Map<String, int> _counts(Iterable<Object?> values) {
  final result = <String, int>{};
  for (final value in values) {
    final key = value?.toString() ?? '';
    if (key.isEmpty) continue;
    result[key] = (result[key] ?? 0) + 1;
  }
  return result;
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

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _codeList(List<Object?> items) {
  if (items.isEmpty) return '--';
  return items.map((item) => '`${item.toString()}`').join(', ');
}
