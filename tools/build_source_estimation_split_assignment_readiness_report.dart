import 'dart:convert';
import 'dart:io';

const _defaultPlanPath =
    'docs/data/source_estimation_split_assignment_plan.json';
const _defaultHinetDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutputPath =
    '.dart_tool/source_estimation_split_assignment_readiness/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_estimation_split_assignment_readiness.generated.md';

void main(List<String> args) {
  final planPath = _argument(args, '--plan') ?? _defaultPlanPath;
  final hinetDecisionPath =
      _argument(args, '--hinet-decisions') ?? _defaultHinetDecisionPath;
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = _ReadinessReport.build(
    planFile: File(planPath),
    hinetDecisionFile: File(hinetDecisionPath),
    fixtureDirectory: Directory(fixtureDirectory),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation split assignment readiness report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ReadinessReport {
  final String planPath;
  final String hinetDecisionPath;
  final String fixtureDirectory;
  final List<_CaseReadiness> cases;
  final List<String> errors;
  final List<String> warnings;

  const _ReadinessReport({
    required this.planPath,
    required this.hinetDecisionPath,
    required this.fixtureDirectory,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _ReadinessReport.build({
    required File planFile,
    required File hinetDecisionFile,
    required Directory fixtureDirectory,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    if (!planFile.existsSync()) {
      errors.add('split_assignment_plan_missing:${planFile.path}');
      return _ReadinessReport(
        planPath: planFile.path,
        hinetDecisionPath: hinetDecisionFile.path,
        fixtureDirectory: fixtureDirectory.path,
        cases: const [],
        errors: errors,
        warnings: warnings,
      );
    }
    if (!fixtureDirectory.existsSync()) {
      errors.add('fixture_directory_missing:${fixtureDirectory.path}');
      return _ReadinessReport(
        planPath: planFile.path,
        hinetDecisionPath: hinetDecisionFile.path,
        fixtureDirectory: fixtureDirectory.path,
        cases: const [],
        errors: errors,
        warnings: warnings,
      );
    }

    final planJson =
        jsonDecode(planFile.readAsStringSync()) as Map<String, Object?>;
    final hinetDecisions = _readHinetDecisions(hinetDecisionFile, errors);
    final fixtureByCaseId = _readFixtures(fixtureDirectory, errors);
    final cases = <_CaseReadiness>[];
    for (final rawCase in _list(planJson['cases'])) {
      final planCase = _map(rawCase);
      final caseId = planCase['caseId']?.toString();
      if (caseId == null || caseId.isEmpty) {
        errors.add('split_assignment_plan_case_missing_case_id');
        continue;
      }
      final fixture = fixtureByCaseId[caseId];
      if (fixture == null) {
        errors.add('split_assignment_fixture_missing:$caseId');
        continue;
      }
      cases.add(
        _CaseReadiness.fromPlanAndFixture(
          planCase: planCase,
          fixtureFile: fixture.file,
          fixture: fixture.json,
          hinetDecision: hinetDecisions[caseId] ?? const <String, Object?>{},
        ),
      );
    }

    final duplicatePlanned = _duplicates(
      [
        for (final rawCase in _list(planJson['cases']))
          _map(rawCase)['caseId']?.toString() ?? '',
      ]..removeWhere((value) => value.isEmpty),
    );
    for (final caseId in duplicatePlanned) {
      errors.add('split_assignment_plan_duplicate_case:$caseId');
    }

    const allowedRecommendationSplits = {'train', 'validation', 'test'};
    for (final entry in cases) {
      if (entry.suggestedSplit.isEmpty) continue;
      if (!allowedRecommendationSplits.contains(entry.suggestedSplit)) {
        errors.add(
          'invalid_manual_split_recommendation:'
          '${entry.caseId}:${entry.suggestedSplit}',
        );
      }
      if (entry.manualSplitAssignmentPending &&
          !entry.readyForManualSplitAssignment) {
        warnings.add(
          'manual_split_recommendation_before_requirements_complete:'
          '${entry.caseId}',
        );
      }
    }
    final manualReadyCount = cases
        .where((entry) => entry.readyForManualSplitAssignment)
        .length;
    if (manualReadyCount > 0) {
      warnings.add(
        'split_assignment_ready_cases_require_manual_split:$manualReadyCount',
      );
    }
    final finalCatalogBlocked = cases
        .where(
          (entry) => entry.conditions.any(
            (condition) =>
                condition.status == 'pending' &&
                condition.reason ==
                    'jma_final_catalog_missing_for_recent_event',
          ),
        )
        .length;
    if (finalCatalogBlocked > 0) {
      warnings.add(
        'recent_jma_final_catalog_links_pending:$finalCatalogBlocked',
      );
    }

    cases.sort((left, right) => left.caseId.compareTo(right.caseId));
    return _ReadinessReport(
      planPath: planFile.path,
      hinetDecisionPath: hinetDecisionFile.path,
      fixtureDirectory: fixtureDirectory.path,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final statusCounts = <String, int>{};
    for (final entry in cases) {
      for (final condition in entry.conditions) {
        statusCounts[condition.status] =
            (statusCounts[condition.status] ?? 0) + 1;
      }
    }
    return {
      'schemaVersion': 'source_estimation_split_assignment_readiness_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'planPath': planPath,
      'hinetDecisionPath': hinetDecisionPath,
      'fixtureDirectory': fixtureDirectory,
      'summary': {
        'caseCount': cases.length,
        'readyForFrozenSplitCount': cases
            .where((entry) => entry.readyForFrozenSplit)
            .length,
        'readyForManualSplitAssignmentCount': cases
            .where((entry) => entry.readyForManualSplitAssignment)
            .length,
        'blockedByManualSplitAssignmentCount': cases
            .where((entry) => entry.manualSplitAssignmentPending)
            .length,
        'conditionStatusCounts': statusCounts,
        'nextActionCounts': _nextActionCounts(cases),
        'manualSplitRecommendationCounts': _manualSplitRecommendationCounts(
          cases,
        ),
        'datasetUseTierCounts': _datasetUseTierCounts(cases),
      },
      'errors': errors,
      'warnings': warnings,
      'cases': cases.map((entry) => entry.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = json['summary'] as Map<String, Object?>;
    final buffer = StringBuffer()
      ..writeln('# Source Estimation Split Assignment Readiness')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Plan: `$planPath`')
      ..writeln('- Hi-net decisions: `$hinetDecisionPath`')
      ..writeln('- Fixture directory: `$fixtureDirectory`')
      ..writeln('- Cases: `${summary['caseCount']}`')
      ..writeln(
        '- Ready for frozen split: `${summary['readyForFrozenSplitCount']}`',
      )
      ..writeln(
        '- Ready for manual split assignment: '
        '`${summary['readyForManualSplitAssignmentCount']}`',
      )
      ..writeln(
        '- Manual split assignment pending: '
        '`${summary['blockedByManualSplitAssignmentCount']}`',
      )
      ..writeln(
        '- Dataset use tiers: '
        '`${summary['datasetUseTierCounts']}`',
      )
      ..writeln()
      ..writeln('## Validation')
      ..writeln()
      ..writeln(
        errors.isEmpty
            ? '- Errors: none'
            : '- Errors: `${errors.join('`, `')}`',
      )
      ..writeln(
        warnings.isEmpty
            ? '- Warnings: none'
            : '- Warnings: `${warnings.join('`, `')}`',
      )
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Tier | Planned use | Truth source | Capture | Catalog/review | Split | Manual-ready | Ready | Next action | Suggested split |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final entry in cases) {
      buffer.writeln(
        '| `${entry.caseId}` | `${entry.datasetUseTier}` | '
        '`${entry.plannedUse}` | '
        '`${entry.truthSource}` | `${entry.captureStatus}` | '
        '`${entry.catalogOrReviewStatus}` | `${entry.splitStatus}` | '
        '${entry.readyForManualSplitAssignment ? 'yes' : 'no'} | '
        '${entry.readyForFrozenSplit ? 'yes' : 'no'} | '
        '`${entry.nextAction}` | `${entry.suggestedSplit}` |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Condition Details')
      ..writeln();
    for (final entry in cases) {
      buffer.writeln('### ${entry.caseId}');
      if (entry.suggestedSplit.isNotEmpty) {
        buffer.writeln(
          '- `manual_split_recommendation`: `${entry.suggestedSplit}` '
          '(${entry.suggestedSplitReason})',
        );
        if (entry.suggestedSplitConstraints.isNotEmpty) {
          buffer.writeln(
            '- `manual_split_constraints`: '
            '`${entry.suggestedSplitConstraints.join('`, `')}`',
          );
        }
      }
      buffer.writeln(
        '- `dataset_use_tier`: `${entry.datasetUseTier}` '
        '(${entry.datasetUseTierReason})',
      );
      for (final condition in entry.conditions) {
        buffer.writeln(
          '- `${condition.name}`: `${condition.status}` '
          '(${condition.reason})',
        );
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

Map<String, int> _nextActionCounts(List<_CaseReadiness> cases) {
  final counts = <String, int>{};
  for (final entry in cases) {
    counts[entry.nextAction] = (counts[entry.nextAction] ?? 0) + 1;
  }
  return counts;
}

Map<String, int> _manualSplitRecommendationCounts(List<_CaseReadiness> cases) {
  final counts = <String, int>{};
  for (final entry in cases) {
    final key = entry.suggestedSplit.isEmpty ? 'none' : entry.suggestedSplit;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

Map<String, int> _datasetUseTierCounts(List<_CaseReadiness> cases) {
  final counts = <String, int>{};
  for (final entry in cases) {
    counts[entry.datasetUseTier] = (counts[entry.datasetUseTier] ?? 0) + 1;
  }
  return counts;
}

class _FixtureEntry {
  final File file;
  final Map<String, Object?> json;

  const _FixtureEntry({required this.file, required this.json});
}

Map<String, _FixtureEntry> _readFixtures(
  Directory directory,
  List<String> errors,
) {
  final result = <String, _FixtureEntry>{};
  final skip = {
    'baseline_suite.json',
    'dataset_splits.json',
    'detection_suite.json',
    'knet_waveform_event_candidates.json',
  };
  for (final file in directory.listSync().whereType<File>().where(
    (file) => file.path.endsWith('.json'),
  )) {
    final name = file.uri.pathSegments.last;
    if (skip.contains(name)) continue;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final caseId = json['caseId']?.toString();
      if (caseId == null || caseId.isEmpty) {
        errors.add('fixture_missing_case_id:${file.path}');
        continue;
      }
      if (result.containsKey(caseId)) {
        errors.add('fixture_duplicate_case_id:$caseId');
      }
      result[caseId] = _FixtureEntry(file: file, json: json);
    } catch (error) {
      errors.add('fixture_json_parse_failed:${file.path}:$error');
    }
  }
  return result;
}

Map<String, Map<String, Object?>> _readHinetDecisions(
  File file,
  List<String> errors,
) {
  if (!file.existsSync()) {
    errors.add('hinet_truth_quality_decisions_missing:${file.path}');
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (decoded['schemaVersion'] != 'hinet_truth_quality_review_decisions_v1') {
      errors.add(
        'hinet_truth_quality_decisions_unexpected_schema:${file.path}',
      );
    }
    return {
      for (final entry in _list(decoded['cases']).map(_map))
        if ((entry['caseId']?.toString() ?? '').isNotEmpty)
          entry['caseId']!.toString(): entry,
    };
  } catch (error) {
    errors.add(
      'hinet_truth_quality_decisions_parse_failed:${file.path}:$error',
    );
    return const {};
  }
}

class _CaseReadiness {
  final String caseId;
  final String plannedUse;
  final String currentStatus;
  final String fixturePath;
  final String truthSource;
  final bool catalogTruthVerified;
  final String splitStatus;
  final String captureStatus;
  final String catalogOrReviewStatus;
  final String suggestedSplit;
  final String suggestedSplitReason;
  final List<String> suggestedSplitConstraints;
  final List<_ConditionReadiness> conditions;

  const _CaseReadiness({
    required this.caseId,
    required this.plannedUse,
    required this.currentStatus,
    required this.fixturePath,
    required this.truthSource,
    required this.catalogTruthVerified,
    required this.splitStatus,
    required this.captureStatus,
    required this.catalogOrReviewStatus,
    required this.suggestedSplit,
    required this.suggestedSplitReason,
    required this.suggestedSplitConstraints,
    required this.conditions,
  });

  factory _CaseReadiness.fromPlanAndFixture({
    required Map<String, Object?> planCase,
    required File fixtureFile,
    required Map<String, Object?> fixture,
    required Map<String, Object?> hinetDecision,
  }) {
    final caseId = planCase['caseId']!.toString();
    final truth = _map(fixture['truth']);
    final labels = _map(fixture['eventLabels']);
    final requirements = _list(
      planCase['requiredBeforeFrozenSplit'],
    ).map((entry) => entry.toString()).toList(growable: false);
    final recommendation = _map(planCase['manualSplitRecommendation']);
    final conditions = [
      for (final requirement in requirements)
        _evaluateCondition(
          name: requirement,
          caseId: caseId,
          fixtureFile: fixtureFile,
          fixture: fixture,
          hinetDecision: hinetDecision,
        ),
    ];
    final captureStatus = _firstStatus(
      conditions,
      'confirm_capture_provenance',
    );
    final catalogOrReviewStatus = _catalogOrReviewSummary(conditions);
    return _CaseReadiness(
      caseId: caseId,
      plannedUse: planCase['plannedUse']?.toString() ?? '',
      currentStatus: planCase['currentStatus']?.toString() ?? '',
      fixturePath: fixtureFile.path,
      truthSource: truth['source']?.toString() ?? '',
      catalogTruthVerified: labels['catalogTruthVerified'] == true,
      splitStatus: fixture['splitStatus']?.toString() ?? 'unspecified',
      captureStatus: captureStatus ?? 'not_required',
      catalogOrReviewStatus: catalogOrReviewStatus,
      suggestedSplit: recommendation['suggestedSplit']?.toString() ?? '',
      suggestedSplitReason: recommendation['reason']?.toString() ?? '',
      suggestedSplitConstraints: _list(
        recommendation['constraints'],
      ).map((entry) => entry.toString()).toList(growable: false),
      conditions: conditions,
    );
  }

  bool get readyForFrozenSplit =>
      conditions.isNotEmpty &&
      conditions.every((condition) => condition.status == 'complete');

  bool get manualSplitAssignmentPending => conditions.any(
    (condition) =>
        condition.name == 'assign_event_level_split' &&
        condition.status != 'complete',
  );

  bool get readyForManualSplitAssignment =>
      manualSplitAssignmentPending &&
      conditions
          .where((condition) => condition.name != 'assign_event_level_split')
          .every((condition) => condition.status == 'complete');

  String get nextAction {
    final nonSplitPending = conditions.where(
      (condition) =>
          condition.name != 'assign_event_level_split' &&
          condition.status != 'complete',
    );
    if (nonSplitPending.isNotEmpty) {
      return nonSplitPending.first.name;
    }
    final splitPending = conditions.where(
      (condition) =>
          condition.name == 'assign_event_level_split' &&
          condition.status != 'complete',
    );
    if (splitPending.isNotEmpty) return splitPending.first.name;
    if (splitAssignmentComplete) return 'split_assignment_complete';
    return readyForFrozenSplit
        ? 'ready_for_frozen_split'
        : 'no_pending_action_detected';
  }

  bool get splitAssignmentComplete => conditions.any(
    (condition) =>
        condition.name == 'assign_event_level_split' &&
        condition.status == 'complete',
  );

  bool get _captureIncompleteOrMissing =>
      conditions.any(
        (condition) =>
            condition.name == 'confirm_capture_provenance' &&
            condition.status != 'complete',
      ) ||
      captureStatus == 'pending';

  bool get _diagnosticIsolationComplete => conditions.any(
    (condition) =>
        condition.name == 'keep_candidate_region_diagnostic_only' &&
        condition.status == 'complete',
  );

  String get datasetUseTier {
    if (readyForFrozenSplit) return 'strict_ready';
    if (_captureIncompleteOrMissing) return 'metadata_only_or_incomplete';
    if (fixturePath.isNotEmpty || _diagnosticIsolationComplete) {
      return 'diagnostic_ready';
    }
    return 'metadata_only_or_incomplete';
  }

  String get datasetUseTierReason {
    switch (datasetUseTier) {
      case 'strict_ready':
        return 'all_frozen_split_requirements_complete';
      case 'diagnostic_ready':
        return 'local_fixture_or_capture_available_but_review_or_split_pending';
      case 'metadata_only_or_incomplete':
        if (_captureIncompleteOrMissing) {
          return 'local_capture_missing_or_has_failed_frames';
        }
        return 'local_fixture_or_capture_not_confirmed';
      default:
        return 'unknown_dataset_use_tier';
    }
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'datasetUseTier': datasetUseTier,
    'datasetUseTierReason': datasetUseTierReason,
    'plannedUse': plannedUse,
    'currentStatus': currentStatus,
    'fixturePath': fixturePath,
    'truthSource': truthSource,
    'catalogTruthVerified': catalogTruthVerified,
    'splitStatus': splitStatus,
    'captureStatus': captureStatus,
    'catalogOrReviewStatus': catalogOrReviewStatus,
    'readyForFrozenSplit': readyForFrozenSplit,
    'readyForManualSplitAssignment': readyForManualSplitAssignment,
    'nextAction': nextAction,
    'manualSplitRecommendation': suggestedSplit.isEmpty
        ? null
        : {
            'suggestedSplit': suggestedSplit,
            'reason': suggestedSplitReason,
            'constraints': suggestedSplitConstraints,
          },
    'conditions': conditions.map((entry) => entry.toJson()).toList(),
  };
}

String? _firstStatus(List<_ConditionReadiness> conditions, String name) {
  for (final condition in conditions) {
    if (condition.name == name) return condition.status;
  }
  return null;
}

String _catalogOrReviewSummary(List<_ConditionReadiness> conditions) {
  final relevant = conditions.where(
    (condition) =>
        condition.name.contains('catalog') ||
        condition.name.contains('hinet') ||
        condition.name.contains('equake') ||
        condition.name.contains('threshold'),
  );
  if (relevant.isEmpty) return 'not_required';
  if (relevant.every((condition) => condition.status == 'complete')) {
    return 'complete';
  }
  return relevant.map((condition) => condition.reason).join(';');
}

class _ConditionReadiness {
  final String name;
  final String status;
  final String reason;
  final Map<String, Object?> evidence;

  const _ConditionReadiness({
    required this.name,
    required this.status,
    required this.reason,
    this.evidence = const {},
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'status': status,
    'reason': reason,
    'evidence': evidence,
  };
}

_ConditionReadiness _evaluateCondition({
  required String name,
  required String caseId,
  required File fixtureFile,
  required Map<String, Object?> fixture,
  required Map<String, Object?> hinetDecision,
}) {
  final truth = _map(fixture['truth']);
  final labels = _map(fixture['eventLabels']);
  final splitStatus = fixture['splitStatus']?.toString() ?? 'unspecified';
  final truthSource = truth['source']?.toString() ?? '';

  switch (name) {
    case 'confirm_capture_provenance':
      return _captureProvenanceCondition(name, fixtureFile, fixture);
    case 'keep_candidate_region_diagnostic_only':
      return _ConditionReadiness(
        name: name,
        status:
            labels['includeInDetectionMetrics'] == false &&
                splitStatus == 'unassigned_reference'
            ? 'complete'
            : 'pending',
        reason:
            labels['includeInDetectionMetrics'] == false &&
                splitStatus == 'unassigned_reference'
            ? 'isolated_from_frozen_metrics_and_coordinate_switch_guards'
            : 'candidate_region_case_not_isolated_from_frozen_metrics',
        evidence: {
          'includeInDetectionMetrics': labels['includeInDetectionMetrics'],
          'splitStatus': splitStatus,
        },
      );
    case 'keep_candidate_region_false_recovery_diagnostic_only':
      return _ConditionReadiness(
        name: name,
        status: 'pending',
        reason: 'false_recovery_guard_requires_explicit_split_gate',
        evidence: {
          'includeInDetectionMetrics': labels['includeInDetectionMetrics'],
          'splitStatus': splitStatus,
          'truthSource': truthSource,
          'diagnosticOnly': true,
        },
      );
    case 'review_jma_catalog_link':
      if (truthSource == 'jma_final_catalog' && truth.containsKey('catalog')) {
        return _ConditionReadiness(
          name: name,
          status: 'complete',
          reason: 'linked_to_versioned_jma_final_catalog',
          evidence: {'truthSource': truthSource, 'catalog': truth['catalog']},
        );
      }
      return _ConditionReadiness(
        name: name,
        status: 'pending',
        reason: truthSource == 'jma_source_and_intensity_information'
            ? 'jma_final_catalog_missing_for_recent_event'
            : 'not_linked_to_jma_final_catalog',
        evidence: {
          'truthSource': truthSource,
          'catalogTruthVerified': labels['catalogTruthVerified'],
          'hasCatalogObject': truth.containsKey('catalog'),
        },
      );
    case 'review_hinet_preliminary_truth_quality':
    case 'review_hinet_truth_quality':
      final hinetAccepted =
          hinetDecision['acceptedForConstrainedReferenceSplit'] == true ||
          hinetDecision['decisionStatus'] == 'accepted_constrained_reference';
      if (truthSource.contains('hinet') && hinetAccepted) {
        return _ConditionReadiness(
          name: name,
          status: 'complete',
          reason: 'hinet_constrained_reference_review_accepted',
          evidence: {
            'truthSource': truthSource,
            'truthQuality': _map(fixture['classification'])['truthQuality'],
            'catalogTruthVerified': labels['catalogTruthVerified'],
            'decisionStatus': hinetDecision['decisionStatus'],
            'acceptedForConstrainedReferenceSplit':
                hinetDecision['acceptedForConstrainedReferenceSplit'],
            'reviewedAtUtc': hinetDecision['reviewedAtUtc'],
            'reviewer': hinetDecision['reviewer'],
          },
        );
      }
      return _ConditionReadiness(
        name: name,
        status: truthSource.contains('hinet') ? 'pending' : 'pending',
        reason: truthSource.contains('hinet')
            ? 'hinet_preliminary_reference_requires_manual_review'
            : 'hinet_reference_source_missing',
        evidence: {
          'truthSource': truthSource,
          'truthQuality': _map(fixture['classification'])['truthQuality'],
          'catalogTruthVerified': labels['catalogTruthVerified'],
          'decisionStatus': hinetDecision['decisionStatus'],
          'acceptedForConstrainedReferenceSplit':
              hinetDecision['acceptedForConstrainedReferenceSplit'],
        },
      );
    case 'link_final_catalog_or_hinet_revision':
      return _ConditionReadiness(
        name: name,
        status: 'pending',
        reason: 'final_catalog_or_hinet_revision_not_linked',
        evidence: {
          'truthSource': truthSource,
          'catalogTruthVerified': labels['catalogTruthVerified'],
        },
      );
    case 'review_equake_reference_only_truth':
      return _ConditionReadiness(
        name: name,
        status:
            truthSource.contains('equake') &&
                labels['catalogTruthVerified'] == false
            ? 'complete'
            : 'pending',
        reason:
            truthSource.contains('equake') &&
                labels['catalogTruthVerified'] == false
            ? 'equake_kept_reference_only_not_catalog_truth'
            : 'equake_reference_only_status_not_proven',
        evidence: {
          'truthSource': truthSource,
          'catalogTruthVerified': labels['catalogTruthVerified'],
        },
      );
    case 'review_source_trigger_threshold_effect':
      final thresholdEvidence = _sourceTriggerThresholdEvidence(caseId);
      final thresholdCleared =
          thresholdEvidence['thresholdReviewCleared'] == true;
      return _ConditionReadiness(
        name: name,
        status: thresholdCleared ? 'complete' : 'pending',
        reason: thresholdCleared
            ? 'source_trigger_threshold_review_cleared'
            : 'source_trigger_threshold_effect_not_reviewed',
        evidence: {'truthSource': truthSource, ...thresholdEvidence},
      );
    case 'assign_event_level_split':
      return _ConditionReadiness(
        name: name,
        status: splitStatus == 'unassigned_reference' ? 'pending' : 'complete',
        reason: splitStatus == 'unassigned_reference'
            ? 'manual_event_level_split_assignment_required'
            : 'already_assigned_to_frozen_split',
        evidence: {'splitStatus': splitStatus},
      );
    default:
      return _ConditionReadiness(
        name: name,
        status: 'pending',
        reason: 'unknown_requirement',
      );
  }
}

_ConditionReadiness _captureProvenanceCondition(
  String name,
  File fixtureFile,
  Map<String, Object?> fixture,
) {
  final fixtureCapture = _map(fixture['capture']);
  final captureDirectory =
      fixture['captureDirectory']?.toString() ??
      fixtureCapture['directory']?.toString() ??
      '';
  final captureDir = Directory(
    _resolvePath(fixtureFile.parent.parent.parent.parent, captureDirectory),
  );
  final manifestFile = File(
    '${captureDir.path}${Platform.pathSeparator}'
    'capture_manifest.json',
  );
  final evidence = <String, Object?>{
    'captureDirectory': captureDirectory,
    'captureDirectorySource': fixture['captureDirectory'] == null
        ? 'legacy_capture_directory'
        : 'captureDirectory',
    'captureDirectoryExists': captureDir.existsSync(),
    'captureManifestExists': manifestFile.existsSync(),
    'fixtureMissingGifCount': fixtureCapture['missingGifCount'],
    'fixtureGifCount': fixtureCapture['gifCount'],
  };

  if (!captureDir.existsSync()) {
    return _ConditionReadiness(
      name: name,
      status: 'pending',
      reason: 'capture_directory_missing',
      evidence: evidence,
    );
  }

  if (manifestFile.existsSync()) {
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    final failedGifCount = _intValue(manifest['failedGifCount']);
    final captureInProgress = manifest['captureInProgress'] == true;
    evidence
      ..['captureInProgress'] = captureInProgress
      ..['failedGifCount'] = failedGifCount
      ..['downloadedGifCount'] = _intValue(manifest['downloadedGifCount'])
      ..['expectedGifCount'] = _intValue(manifest['expectedGifCount']);
    return _ConditionReadiness(
      name: name,
      status: !captureInProgress && failedGifCount == 0
          ? 'complete'
          : 'pending',
      reason: !captureInProgress && failedGifCount == 0
          ? 'capture_manifest_complete_with_zero_failures'
          : 'capture_manifest_incomplete_or_has_failures',
      evidence: evidence,
    );
  }

  final missingGifCount = _intValue(fixtureCapture['missingGifCount']);
  if (missingGifCount == 0 && _intValue(fixtureCapture['gifCount']) > 0) {
    return _ConditionReadiness(
      name: name,
      status: 'complete',
      reason: 'fixture_capture_summary_has_zero_missing_gifs',
      evidence: evidence,
    );
  }

  return _ConditionReadiness(
    name: name,
    status: 'pending',
    reason: 'capture_manifest_or_complete_fixture_summary_missing',
    evidence: evidence,
  );
}

Map<String, Object?> _sourceTriggerThresholdEvidence(String caseId) {
  final reportFile = File(
    '.dart_tool/source_trigger_threshold_review/report.json',
  );
  if (!reportFile.existsSync()) {
    return const {
      'thresholdReviewReportPath':
          '.dart_tool/source_trigger_threshold_review/report.json',
      'thresholdReviewReportExists': false,
      'thresholdReviewCleared': false,
    };
  }
  try {
    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    final reportCase = _map(report['case']);
    final summary = _map(report['summary']);
    final reportCaseId = reportCase['caseId']?.toString();
    final matchesCase = reportCaseId == caseId;
    return {
      'thresholdReviewReportPath': reportFile.path,
      'thresholdReviewReportExists': true,
      'thresholdReviewStatus': report['status']?.toString(),
      'thresholdReviewCaseId': reportCaseId,
      'thresholdReviewMatchesCase': matchesCase,
      'thresholdReviewCleared':
          matchesCase &&
          report['status'] == 'pass' &&
          reportCase['thresholdReviewCleared'] == true,
      'quietWindowCount': summary['quietWindowCount'],
      'quietWindowCandidateFrameCount':
          summary['quietWindowCandidateFrameCount'],
      'quietWindowConfirmedFrameCount':
          summary['quietWindowConfirmedFrameCount'],
      'quietWindowFalseEstimateFrameCount':
          summary['quietWindowFalseEstimateFrameCount'],
    };
  } catch (error) {
    return {
      'thresholdReviewReportPath': reportFile.path,
      'thresholdReviewReportExists': true,
      'thresholdReviewParseError': error.toString(),
      'thresholdReviewCleared': false,
    };
  }
}

String _resolvePath(Directory workspaceRoot, String path) {
  if (path.isEmpty) return path;
  if (_isAbsolutePath(path)) return path;
  return '${workspaceRoot.path}${Platform.pathSeparator}$path';
}

bool _isAbsolutePath(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

Set<String> _duplicates(List<String> values) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final value in values) {
    if (!seen.add(value)) duplicates.add(value);
  }
  return duplicates;
}
